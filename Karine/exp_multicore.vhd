library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exp_multicore is
  generic (
    C_block_size : integer := 256;
    N_CORES      : integer := 4;   -- must be <= MAX_CORES below
    DEBUG        : boolean := false
  );
  port (
    -- external interface: same as single exponentiation
    valid_in  : in  std_logic;
    ready_in  : out std_logic;
    last_in   : in  std_logic;

    -- input data
    message   : in  std_logic_vector(C_block_size-1 downto 0);
    key       : in  std_logic_vector(C_block_size-1 downto 0);
    r2_mod_n  : in  std_logic_vector(C_block_size-1 downto 0);
    n_prime   : in  std_logic_vector(31 downto 0);

    -- VLNW schedules
    vlnw_schedule_0 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_1 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_2 : in  std_logic_vector(255 downto 0);

    -- output control
    ready_out : in  std_logic;
    valid_out : out std_logic;

    -- output data
    result    : out std_logic_vector(C_block_size-1 downto 0);

    -- modulus
    modulus   : in  std_logic_vector(C_block_size-1 downto 0);

    -- utility
    clk       : in  std_logic;
    reset_n   : in  std_logic
  );
end exp_multicore;

architecture rtl of exp_multicore is

  constant MAX_CORES : integer := 4;
  constant LANES     : integer := 5;  -- matches exponentiation

  ---------------------------------------------------------------------------
  -- Sanity: make sure N_CORES <= MAX_CORES
  ---------------------------------------------------------------------------
  -- (Vivado won't enforce this strictly at elaboration, but it's a good hint)
  -- assert N_CORES <= MAX_CORES report "N_CORES exceeds MAX_CORES in exp_multicore" severity failure;

  ---------------------------------------------------------------------------
  -- Per-core handshake and data
  ---------------------------------------------------------------------------
  signal core_valid_in  : std_logic_vector(MAX_CORES-1 downto 0);
  signal core_last_in   : std_logic_vector(MAX_CORES-1 downto 0);
  signal core_ready_in  : std_logic_vector(MAX_CORES-1 downto 0);

  signal core_valid_out : std_logic_vector(MAX_CORES-1 downto 0);
  signal core_ready_out : std_logic_vector(MAX_CORES-1 downto 0);

  type result_array_t is array (0 to MAX_CORES-1) of std_logic_vector(C_block_size-1 downto 0);
  signal core_result : result_array_t;

  -- Per-core "how many messages in current batch (0..5)"
  type cnt_array_t is array (0 to MAX_CORES-1) of integer range 0 to LANES;
  signal batch_count : cnt_array_t := (others => 0);

  -- Which core is currently collecting a batch (-1 = none)
  signal open_core : integer range -1 to MAX_CORES-1 := -1;
  
  signal ready_in_s : std_logic;

begin

  ---------------------------------------------------------------------------
  -- Instantiate N_CORES exponentiation cores
  ---------------------------------------------------------------------------
  gen_core : for i in 0 to MAX_CORES-1 generate
  begin
    u_exp : if i < N_CORES generate
      u_exp_inst : entity work.exponentiation
        generic map (
          C_block_size => C_block_size,
          DEBUG        => DEBUG
        )
        port map (
          valid_in  => core_valid_in(i),
          ready_in  => core_ready_in(i),
          last_in   => core_last_in(i),

          message   => message,
          key       => key,
          r2_mod_n  => r2_mod_n,
          n_prime   => n_prime,

          vlnw_schedule_0 => vlnw_schedule_0,
          vlnw_schedule_1 => vlnw_schedule_1,
          vlnw_schedule_2 => vlnw_schedule_2,

          ready_out => core_ready_out(i),
          valid_out => core_valid_out(i),

          result    => core_result(i),

          modulus   => modulus,

          clk       => clk,
          reset_n   => reset_n
        );
    end generate;
  end generate;

  ---------------------------------------------------------------------------
  -- READY to upstream
  --  - If we are currently building a batch for some core (open_core >= 0),
  --    we are ready if that core is ready.
  --  - Otherwise, we are ready if ANY core is ready to start a new batch.
  ---------------------------------------------------------------------------
    process (core_ready_in, open_core)
      variable any_ready : std_logic := '0';
    begin
      if open_core >= 0 then
        ready_in_s <= core_ready_in(open_core);
      else
        any_ready := '0';
        for i in 0 to N_CORES-1 loop
          if core_ready_in(i) = '1' then
            any_ready := '1';
          end if;
        end loop;
        ready_in_s <= any_ready;
      end if;
    end process;
    
    -- drive the port from the internal signal
    ready_in <= ready_in_s;

  ---------------------------------------------------------------------------
  -- Input scheduler: assign batches of <=5 messages per core
  ---------------------------------------------------------------------------
  process (clk, reset_n)
    variable i_sel  : integer;
    variable chosen : integer;
  begin
    if reset_n = '0' then
      core_valid_in <= (others => '0');
      core_last_in  <= (others => '0');
      for i_sel in 0 to MAX_CORES-1 loop
        batch_count(i_sel) <= 0;
      end loop;
      open_core <= -1;

    elsif rising_edge(clk) then
      -- defaults every cycle
      core_valid_in <= (others => '0');
      core_last_in  <= (others => '0');

      if (valid_in = '1') and (ready_in_s = '1') then
        --------------------------------------------------------------------
        -- 1) Decide which core to send this message to
        --------------------------------------------------------------------
        if open_core >= 0 then
          -- We already have an active batch for this core
          chosen := open_core;
        else
          -- No open batch: pick the first ready core
          chosen := -1;
          for i_sel in 0 to N_CORES-1 loop
            if (core_ready_in(i_sel) = '1') and (chosen = -1) then
              chosen := i_sel;
            end if;
          end loop;
          if chosen = -1 then
            -- Should not happen when ready_in='1', but guard anyway
            chosen := 0;
          end if;
          open_core <= chosen;
        end if;

        --------------------------------------------------------------------
        -- 2) Send this message to the chosen core
        --------------------------------------------------------------------
        core_valid_in(chosen) <= '1';

        -- Decide if this message should be 'last' for that core:
        --  - if we just filled 5 messages, OR
        --  - if the global stream says last_in='1'
        if (batch_count(chosen) = LANES-1) or (last_in = '1') then
          core_last_in(chosen) <= '1';
          batch_count(chosen)  <= 0;
          open_core            <= -1;  -- close this batch, next message opens new batch
        else
          core_last_in(chosen) <= '0';
          batch_count(chosen)  <= batch_count(chosen) + 1;
        end if;

      end if; -- valid_in & ready_in
    end if; -- rising_edge
  end process;

  ---------------------------------------------------------------------------
  -- Output arbiter (in-order across batches because:
  --  - same key/modulus => same latency per full batch
  --  - batches assigned sequentially to cores; no interleaving
  --
  -- We:
  --  - pick the first core with valid_out='1' as the active output
  --  - give *that* core ready_out = external ready_out
  --  - give all other cores ready_out = '0'
  ---------------------------------------------------------------------------
  process (core_valid_out, core_result, ready_out)
    variable found     : boolean := false;
    variable sel_index : integer := 0;
    variable i         : integer;
  begin
    valid_out      <= '0';
    result         <= (others => '0');
    core_ready_out <= (others => '0');

    found     := false;
    sel_index := 0;

    -- Choose first core with a valid result
    for i in 0 to N_CORES-1 loop
      if (core_valid_out(i) = '1') and (not found) then
        found     := true;
        sel_index := i;
      end if;
    end loop;

    if found then
      valid_out <= '1';
      result    <= core_result(sel_index);

      -- Only the selected core sees downstream ready
      if ready_out = '1' then
        core_ready_out(sel_index) <= '1';
      else
        core_ready_out(sel_index) <= '0';
      end if;
    end if;
  end process;

end rtl;
