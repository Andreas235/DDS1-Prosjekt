library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mac1 is
end tb_mac1;

architecture sim of tb_mac1 is

  -- DUT signals
  signal clk     : std_logic := '0';
  signal reset   : std_logic := '0';
  signal start   : std_logic := '0';
  signal done    : std_logic;
  signal A, B    : std_logic_vector(17 downto 0);
  signal C       : std_logic_vector(36 downto 0);
  signal r       : std_logic_vector(36 downto 0);

  -- Clock period constant
  constant clk_period : time := 10 ns;

begin
  --------------------------------------------------------------------
  -- Clock generation
  --------------------------------------------------------------------
  clk_process : process
  begin
    clk <= '0';
    wait for clk_period/2;
    clk <= '1';
    wait for clk_period/2;
  end process;

  --------------------------------------------------------------------
  -- Instantiate DUT
  --------------------------------------------------------------------
  uut: entity work.mac1
    port map (
      clk   => clk,
      reset => reset,
      start => start,
      done  => done,
      A     => A,
      B     => B,
      C     => C,
      r     => r
    );

  --------------------------------------------------------------------
  -- Stimulus process
  --------------------------------------------------------------------
  stim_proc : process
    variable expected : unsigned(36 downto 0);
  begin
    -- Initialize
    reset <= '1';
    A <= (others => '0');
    B <= (others => '0');
    C <= (others => '0');
    wait for 20 ns;
    reset <= '0';

    -- Test 1
    A <= std_logic_vector(to_unsigned(3, A'length));
    B <= std_logic_vector(to_unsigned(5, B'length));
    C <= std_logic_vector(to_unsigned(10, C'length));
    wait for clk_period * 3;

    expected := unsigned(A) * unsigned(B) + unsigned(C);
    report "Test 1: A=3, B=5, C=10 -> Expected=" & integer'image(to_integer(expected)) &
           " Got=" & integer'image(to_integer(unsigned(r)));

    -- Test 2
    A <= std_logic_vector(to_unsigned(100, A'length));
    B <= std_logic_vector(to_unsigned(200, B'length));
    C <= std_logic_vector(to_unsigned(50, C'length));
    wait for clk_period * 3;

    expected := unsigned(A) * unsigned(B) + unsigned(C);
    report "Test 2: A=100, B=200, C=50 -> Expected=" & integer'image(to_integer(expected)) &
           " Got=" & integer'image(to_integer(unsigned(r)));

    -- Test 3
    A <= std_logic_vector(to_unsigned(2**17-1, A'length));  -- max value
    B <= std_logic_vector(to_unsigned(2**17-1, B'length));
    C <= std_logic_vector(to_unsigned(1000, C'length));
    wait for clk_period * 3;

    expected := unsigned(A) * unsigned(B) + unsigned(C);
    report "Test 3: Max values -> Expected=" & integer'image(to_integer(expected(31 downto 0))) &
           " Got=" & integer'image(to_integer(unsigned(r(31 downto 0))));

    report "Simulation finished." severity note;
    wait;
  end process;

end sim;
