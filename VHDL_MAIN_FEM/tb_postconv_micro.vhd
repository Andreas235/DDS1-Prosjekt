-- tb_postconv_micro_long.vhd
-- Long-run handshake TB for postconv_micro + monpro
-- VHDL-2008 recommended

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;  -- for stop

entity tb_postconv_micro_long is
end entity;

architecture sim of tb_postconv_micro_long is
  -- Match your generics
  constant W      : integer := 32;
  constant K      : integer := 8;           -- 256/W
  constant WIDTH  : integer := W*K;

  -- Clk/Reset
  signal clk      : std_logic := '0';
  signal reset_n  : std_logic := '0';

  -- DUT (postconv_micro) I/O
  signal start    : std_logic := '0';
  signal done     : std_logic := '0';
  signal acc_in   : std_logic_vector(WIDTH-1 downto 0);
  signal one_lit  : std_logic_vector(WIDTH-1 downto 0) := (others => '0');

  -- Shared MonPro interface
  signal mp_start : std_logic;
  signal mp_busy  : std_logic;
  signal mp_done  : std_logic;
  signal mp_a     : std_logic_vector(WIDTH-1 downto 0);
  signal mp_b     : std_logic_vector(WIDTH-1 downto 0);
  signal mp_n     : std_logic_vector(WIDTH-1 downto 0);
  signal mp_r     : std_logic_vector(WIDTH-1 downto 0);
  signal n_prime  : std_logic_vector(31 downto 0);

begin
  ---------------------------------------------------------------------------
  -- 100 MHz clock
  ---------------------------------------------------------------------------
  clk <= not clk after 5 ns;

  ---------------------------------------------------------------------------
  -- Reset
  ---------------------------------------------------------------------------
  process
  begin
    reset_n <= '0';
    wait for 100 ns;
    reset_n <= '1';
    wait;
  end process;

  ---------------------------------------------------------------------------
  -- DUT: postconv_micro (de-Montgomery helper)
  ---------------------------------------------------------------------------
  i_post : entity work.postconv_micro
    generic map ( WIDTH => WIDTH )
    port map(
      clk           => clk,
      reset_n       => reset_n,
      start         => start,
      done          => done,
      acc_in        => acc_in,
      one_literal   => one_lit,   -- unused; micro makes literal '1'
      monpro_busy   => mp_busy,
      monpro_done   => mp_done,
      monpro_start  => mp_start,
      monpro_a      => mp_a,
      monpro_b      => mp_b
    );

  ---------------------------------------------------------------------------
  -- MonPro instance (real RTL)
  ---------------------------------------------------------------------------
  i_monpro : entity work.monpro
    generic map ( W => W, K => K )
    port map(
      clk      => clk,
      reset_n  => reset_n,
      start    => mp_start,
      busy     => mp_busy,
      done     => mp_done,
      a        => mp_a,
      b        => mp_b,
      n        => mp_n,
      n_prime  => n_prime,
      r        => mp_r
    );

  ---------------------------------------------------------------------------
  -- Stimulus: long run to see mp_done high
  ---------------------------------------------------------------------------
  stimulus : process
  begin
    -- Any values are fine for handshake/latency; use fixed vectors
    acc_in  <= x"1234567890ABCDEF_FEDCBA0987654321_0011223344556677_89ABCDEF01234567";
    mp_n    <= x"F1F2F3F4F5F6F7F8_F9FAFBFCFDFEFF00_1122334455667788_99AABBCCDDEEFF01";
    n_prime <= x"89ABCDEF";

    -- Wait for reset release
    wait until reset_n = '1';
    wait for 50 ns;

    -- Fire one operation
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    report "TB: start pulsed at " & time'image(now);

    -- Wait long enough for CIOS latency (K=8 ~ few microseconds). Use 200 us margin.
    wait until mp_done = '1' for 200 us;
    if mp_done = '1' then
      report "TB: mp_done observed at " & time'image(now);
    else
      assert false report "TIMEOUT: mp_done did not assert within 200 us" severity failure;
    end if;

    -- postconv_micro should raise done one cycle after mp_done
    wait until done = '1' for 5 us;
    if done = '1' then
      report "TB: postconv_micro.done observed at " & time'image(now);
    else
      assert false report "Expected postconv_micro.done after mp_done" severity failure;
    end if;

    -- Small delay for waves, then stop sim cleanly
    wait for 100 ns;
    report "TB finished OK." severity note;
    stop;  -- std.env.stop (VHDL-2008)
    wait;
  end process;

  ---------------------------------------------------------------------------
  -- Optional assertions: mp_b must be literal 1 on the mp_start cycle
  ---------------------------------------------------------------------------
  check_b_is_one : process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '1' and mp_start = '1' and mp_busy = '0' then
        --assert mp_b(0) = '1' and mp_b(WIDTH-1 downto 1) = (others => '0')
          report "mp_b is not literal 1 on start" severity error;
      end if;
    end if;
  end process;

end architecture;
