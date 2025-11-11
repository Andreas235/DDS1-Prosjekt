-- tb_monpro_min.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_monpro_min is
end tb_monpro_min;

architecture sim of tb_monpro_min is
  -- Match your DUT generics
  constant W : integer := 32;
  constant K : integer := 8;  -- 256-bit

  -- ====== EDIT THESE CONSTANTS ======
  -- Modulus and n' (must match your RTL run)
  constant N_C      : std_logic_vector(255 downto 0) := x"99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D"; -- <-- put n here
  constant NPRIME_C : std_logic_vector(31 downto 0)  := x"8833C3BB"; -- <-- put (-n^{-1} mod 2^32) here

  -- Operands to test (a and b)
  constant A_IN_C   : std_logic_vector(255 downto 0) := x"86D4F1BF048415486B3D5FB7B00CA73ADF70014F54A0F7EBBE9EBA9191A90C9F"; -- example
  constant B_IN_C   : std_logic_vector(255 downto 0) := x"86D4F1BF048415486B3D5FB7B00CA73ADF70014F54A0F7EBBE9EBA9191A90C9F"; -- example
  -- ==================================

  -- Clock/reset
  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  -- DUT I/O
  signal start   : std_logic := '0';
  signal busy    : std_logic;
  signal done    : std_logic;
  signal a, b    : std_logic_vector(K*W-1 downto 0) := (others => '0');
  signal n       : std_logic_vector(K*W-1 downto 0) := (others => '0');
  signal n_prime : std_logic_vector(31 downto 0)    := (others => '0');
  signal r       : std_logic_vector(K*W-1 downto 0);

  component monpro
    generic ( W : integer := 32; K : integer := 8 );
    port (
      clk       : in  std_logic;
      reset_n   : in  std_logic;
      start     : in  std_logic;
      busy      : out std_logic;
      done      : out std_logic;
      a         : in  std_logic_vector(K*W-1 downto 0);
      b         : in  std_logic_vector(K*W-1 downto 0);
      n         : in  std_logic_vector(K*W-1 downto 0);
      n_prime   : in  std_logic_vector(31 downto 0);
      r         : out std_logic_vector(K*W-1 downto 0)
    );
  end component;

  -- Simple hex renderer (works in VHDL-93)
  function hex_nib(n : std_logic_vector(3 downto 0)) return character is
    variable u : unsigned(3 downto 0);
  begin
    u := unsigned(n);
    if u < 10 then
      return character'val(character'pos('0') + to_integer(u));
    else
      return character'val(character'pos('A') + to_integer(u) - 10);
    end if;
  end function;

  function slv_to_hex(slv : std_logic_vector) return string is
    constant N  : integer := slv'length / 4;
    variable res_str : string(1 to N);
    variable hi, lo  : integer;
    variable nib     : std_logic_vector(3 downto 0);
    variable r_words : std_logic_vector(255 downto 0);
  begin
    for i in 0 to N-1 loop
      hi  := slv'left - 4*i;
      lo  := hi - 3;
      nib := slv(hi downto lo);
      res_str(i+1) := hex_nib(nib);
    end loop;
    return res_str;
  end function;

begin
  -- 100 MHz clock
  clk <= not clk after 5 ns;

  -- DUT instance
  dut: monpro
    generic map ( W => W, K => K )
    port map (
      clk     => clk,
      reset_n => reset_n,
      start   => start,
      busy    => busy,
      done    => done,
      a       => a,
      b       => b,
      n       => n,
      n_prime => n_prime,
      r       => r
    );

  -- Stimulus: set inputs, pulse start, wait for done, print r
  stim: process
    variable r_words : std_logic_vector(255 downto 0);

  begin
    -- Apply constants
    n       <= N_C;
    n_prime <= NPRIME_C;
    a       <= A_IN_C;
    b       <= B_IN_C;

    -- Reset
    reset_n <= '0';
    wait for 50 ns;
    wait until rising_edge(clk);
    reset_n <= '1';
    wait until rising_edge(clk);

    -- Start one transaction
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- Wait for completion
    wait until rising_edge(clk);
    while done = '0' loop
      wait until rising_edge(clk);
    end loop;

    report "MonPro("
           & "A=0x" & slv_to_hex(a) & ", "
           & "B=0x" & slv_to_hex(b) & ")"
           severity note;
    report "R=0x" & slv_to_hex(r) severity note;
    

r_words := r(31 downto 0) & r(63 downto 32) & r(95 downto 64) &
           r(127 downto 96) & r(159 downto 128) & r(191 downto 160) &
           r(223 downto 192) & r(255 downto 224);
           report "R_be = 0x" & slv_to_hex(r_words) severity note;

    -- Optional: invariant-result must be < n
    assert unsigned(r) < unsigned(n)
      report "MonPro produced r >= n (bad reduction?)" severity failure;

    report "TB finished." severity note;
    wait;
  end process;

end sim;


