library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity postconv_micro is
  generic (
    WIDTH : integer := 256
  );
  port(
    clk           : in  std_logic;
    reset_n       : in  std_logic;
    start         : in  std_logic;
    done          : out std_logic;

    acc_in        : in  std_logic_vector(WIDTH-1 downto 0);
    one_literal   : in  std_logic_vector(WIDTH-1 downto 0); -- unused; we'll build 1 locally

    -- share MonPro
    monpro_busy   : in  std_logic;
    monpro_done   : in  std_logic;
    monpro_start  : out std_logic;
    monpro_a      : out std_logic_vector(WIDTH-1 downto 0);
    monpro_b      : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity;

architecture rtl of postconv_micro is
  type s_t is (IDLE, FIRE, WAIT_M, DONE);
  signal st : s_t := IDLE;
begin
  process(clk, reset_n)
  begin
    if reset_n = '0' then
      st <= IDLE;
      monpro_start <= '0';
      monpro_a <= (others=>'0');
      monpro_b <= (others=>'0');
      done <= '0';
    elsif rising_edge(clk) then
      monpro_start <= '0';
      done <= '0';

      case st is
        when IDLE =>
          if start = '1' then
            st <= FIRE;
          end if;

        when FIRE =>
          if monpro_busy = '0' then
            monpro_a <= acc_in;
            monpro_b <= (others=>'0'); monpro_b(0) <= '1'; -- literal 1
            monpro_start <= '1';
            st <= WAIT_M;
          end if;

        when WAIT_M =>
          if monpro_done = '1' then
            st <= DONE;
          end if;

        when DONE =>
          done <= '1';
          st <= IDLE;

      end case;
    end if;
  end process;
end architecture;

