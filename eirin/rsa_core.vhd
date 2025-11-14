library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_core is
  generic (
    C_BLOCK_SIZE : integer := 256
  );
  port (
    clk             : in  std_logic;
    reset_n         : in  std_logic;

    -- Slave msgin
    msgin_valid     : in  std_logic;
    msgin_ready     : out std_logic;
    msgin_data      : in  std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    msgin_last      : in  std_logic;

    -- Master msgout
    msgout_valid    : out std_logic;
    msgout_ready    : in  std_logic;
    msgout_data     : out std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    msgout_last     : out std_logic;

    -- Precompute/schedule
    r2_mod_n        : in  std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    n_prime         : in  std_logic_vector(31 downto 0);
    vlnw_schedule_0 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_1 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_2 : in  std_logic_vector(255 downto 0);

    -- Keys/status
    key_e_d         : in  std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    key_n           : in  std_logic_vector(C_BLOCK_SIZE-1 downto 0)
    --rsa_status      : out std_logic_vector(31 downto 0)
  );
end rsa_core;

architecture rtl of rsa_core is
  -- Handshake wires to exponentiation
  signal exp_ready_in  : std_logic;
  signal exp_valid_out : std_logic;
  signal exp_result    : std_logic_vector(C_BLOCK_SIZE-1 downto 0);

  -- 1-deep "last" FIFO
  signal last_q       : std_logic := '0';
  signal last_q_valid : std_logic := '0';
  -- --- small FIFO for 'last' flags ---
  constant LAST_FIFO_DEPTH : integer := 16;  -- >= max in-flight messages
  subtype idx_t is integer range 0 to LAST_FIFO_DEPTH-1;
    
  type last_fifo_t is array (0 to LAST_FIFO_DEPTH-1) of std_logic;
  signal last_fifo : last_fifo_t := (others => '0');
  signal wr_ptr    : idx_t := 0;
  signal rd_ptr    : idx_t := 0;
  signal fifo_cnt  : integer range 0 to LAST_FIFO_DEPTH := 0;
begin
  -- Exponentiation instance
  i_exponentiation : entity work.exponentiation
    generic map (
      C_block_size => C_BLOCK_SIZE
    )
    port map (
      -- input data/control
      message         => msgin_data,
      key             => key_e_d,
      r2_mod_n        => r2_mod_n,
      n_prime         => n_prime,
      vlnw_schedule_0 => vlnw_schedule_0,
      vlnw_schedule_1 => vlnw_schedule_1,
      vlnw_schedule_2 => vlnw_schedule_2,
      valid_in        => msgin_valid,

      -- handshake to/from core
      ready_in        => exp_ready_in,     -- from exponentiation
      ready_out       => msgout_ready,     -- to exponentiation
      last_in         => msgin_last,
      valid_out       => exp_valid_out,    -- from exponentiation

      -- result / modulus / clk
      result          => exp_result,
      modulus         => key_n,
      clk             => clk,
      reset_n         => reset_n
    );

    ------------------------------------------------------------------------------
    -- Handshake glue with a small FIFO for msgin_last
    ------------------------------------------------------------------------------
    
    -- Let exponentiation control intake; do NOT gate by 'last'
    msgin_ready <= exp_ready_in;
    
    -- Outputs come straight from exponentiation
    msgout_valid <= exp_valid_out;
    msgout_data  <= exp_result;
    

    
    -- Drive msgout_last from the entry that will be consumed next
    msgout_last <= last_fifo(rd_ptr);
    
    process(clk, reset_n)
    begin
      if reset_n = '0' then
        last_fifo <= (others => '0');
        wr_ptr    <= 0;
        rd_ptr    <= 0;
        fifo_cnt  <= 0;
    
      elsif rising_edge(clk) then
        -- enqueue: one 'last' bit per accepted input beat
        if (msgin_valid = '1') and (msgin_ready = '1') then
          last_fifo(wr_ptr) <= msgin_last;
          wr_ptr            <= (wr_ptr + 1) mod LAST_FIFO_DEPTH;
          if fifo_cnt < LAST_FIFO_DEPTH then
            fifo_cnt <= fifo_cnt + 1;
          end if;
        end if;
    
        -- dequeue: exactly when an output transfers
        if (exp_valid_out = '1') and (msgout_ready = '1') then
          rd_ptr <= (rd_ptr + 1) mod LAST_FIFO_DEPTH;
          if fifo_cnt > 0 then
            fifo_cnt <= fifo_cnt - 1;
          end if;
        end if;
    
        -- (optional) sanity checks
        -- if (exp_valid_out='1') and (msgout_ready='1') then
        --   assert fifo_cnt > 0
        --     report "last FIFO underflow" severity failure;
        -- end if;
      end if;
    end process;

  -- (Optional) safety: output must not be valid unless we have a last stored
  -- assert (exp_valid_out = '0') or (last_q_valid = '1')
  --   report "Output valid but last_q_valid=0" severity failure;

  --rsa_status <= (others => '0');
end rtl;

