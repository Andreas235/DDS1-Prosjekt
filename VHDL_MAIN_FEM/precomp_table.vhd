library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity precompute_table is
  generic (
    W : integer := 32;
    K : integer := 8  -- 256/W
  );
port (
  clk, reset_n : in std_logic;
  start_all       : in  std_logic;
  all_done        : out std_logic;
  start_from_mont : in  std_logic;
  from_mont_done  : out std_logic;
  base_in, modulus : in std_logic_vector(W*K-1 downto 0);
  n_prime         : in std_logic_vector(31 downto 0);
  monpro_start    : out std_logic; monpro_busy : in std_logic; monpro_done : in std_logic;
  monpro_a, monpro_b : out std_logic_vector(W*K-1 downto 0);
  monpro_result   : in  std_logic_vector(W*K-1 downto 0);
  tbl_raddr       : in  std_logic_vector(2 downto 0);
  tbl_rdata       : out std_logic_vector(W*K-1 downto 0);
  acc_in          : in  std_logic_vector(W*K-1 downto 0);
  acc_out         : out std_logic_vector(W*K-1 downto 0)
);

end entity precompute_table;

architecture rtl of precompute_table is
  type state_t is (IDLE, INIT, MULTIPLY, WAIT_DONE, STORE, FINISHED);
  signal state : state_t := IDLE;
  signal index : integer range 0 to 7 := 0;
  -- optional array form:
  type table_array_t is array (natural range <>) of std_logic_vector(W*K-1 downto 0);
  signal table : table_array_t(0 to 7);


begin

  process(clk, reset_n)
  begin
    if reset_n = '0' then
      state <= IDLE;
      all_done  <= '0';
      index <= 0;
    elsif rising_edge(clk) then
      case state is
        when IDLE =>
          if start_all = '1' then
            all_done <= '0';
            index <= 0;
            state <= INIT;
          end if;

        when INIT =>
          -- Set first element to base
          table(0) <= base_in;
          state <= MULTIPLY;

        when MULTIPLY =>
          if monpro_busy = '0' then
            monpro_a <= table(index);
            monpro_b <= base_in;
            monpro_start <= '1';
            state <= WAIT_DONE;
          end if;

        when WAIT_DONE =>
          monpro_start <= '0';
          if monpro_done = '1' then
            table(index+1) <= monpro_result;
            if index = 6 then
              state <= FINISHED;
            else
              index <= index + 1;
              state <= MULTIPLY;
            end if;
          end if;

        when FINISHED =>
          all_done <= '1';
          state <= IDLE;
      end case;
    end if;
  end process;
  
  
tbl_rdata <= table(to_integer(unsigned(tbl_raddr)));


end architecture;

