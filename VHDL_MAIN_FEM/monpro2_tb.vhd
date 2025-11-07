----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.11.2025 13:32:46
-- Design Name: 
-- Module Name: monpro2_tb - rtl
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity monpro2_tb is
end monpro2_tb;

architecture rtl of monpro2_tb is
  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  constant CLK_PERIOD : time := 10 ns;
  signal clk : std_logic := '0';

  --------------------------------------------------------------------
  -- DUT signals
  --------------------------------------------------------------------
  signal reset_n, start : std_logic := '0';
  signal busy, done     : std_logic;
  signal operand        : std_logic_vector(31 downto 0) := (others => '0');
  signal new_data       : std_logic_vector(1 downto 0) := "00";
  signal n              : std_logic_vector(31 downto 0) := (others => '0');
  signal n_prime        : std_logic_vector(31 downto 0) := (others => '0');
  signal r              : std_logic_vector(255 downto 0);

  --------------------------------------------------------------------
  -- Test vectors
  --------------------------------------------------------------------
  type vec256_array is array (natural range <>) of std_logic_vector(255 downto 0);
  constant TEST_A : vec256_array := (
    x"5b9e402b76181c9c95ce28ced7dde4c04d1e1f5773e9e67e4c907c8fa7c390cc",
    x"8f60c53bb52fa76d469a3b9a490eca9b1f5772cce572ec4713846d441af9fbb1",
    x"0ae6c5206a56a95614ae267f12a8bf8c62084ce19e08df8e26f99f8bc4e7135b"
  );
  constant TEST_B : vec256_array := (
    x"1808a604ed7dedcf26e8e371a4e312a51fae740f749aaac0ac10c9cc3469d8d4",
    x"10a2f2df9d2aa444e749ed66e18ff0900c61d1e35e8ce408f51ef74b88004abd",
    x"98ca11cc657b20aa771f4cffe1bd12dcb6a3c90bb0e1e20649bf14b4332845c1"
  );
  constant TEST_N : std_logic_vector(255 downto 0) :=
    x"99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D";
  constant TEST_N_PRIME : std_logic_vector(31 downto 0) := x"8833C3BB";
  constant EXPECTED_R : vec256_array := (
    x"184b7e4d8ff947e2de26b0b8f53c163e81446674168a412ec366d81cc4b96b4e",
    x"87460fc6a55cbc145a1921c2cd2b37cd7e135a065f6cb4569778f1ef6d8320d8",
    x"1fc0f35f4a35741a9ed4fcb881a235ef8d1d5cab77236a499539e4d01cc60adc"
  );

  --------------------------------------------------------------------
  -- Helper: HEX string
  --------------------------------------------------------------------
  function to_hex(slv : std_logic_vector) return string is
    constant HEX : string := "0123456789ABCDEF";
    constant N   : integer := slv'length/4;
    variable s   : string(1 to N);
    variable nib : std_logic_vector(3 downto 0);
    variable idx : integer;
  begin
    for j in 0 to N-1 loop
      nib := slv(slv'left - 4*j downto slv'left - 4*j - 3);
      idx := to_integer(unsigned(nib));
      s(j+1) := HEX(idx+1);
    end loop;
    return s;
  end;

begin
  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2;

  --------------------------------------------------------------------
  -- DUT instance
  --------------------------------------------------------------------
  DUT : entity work.monpro5
    port map(
      clk      => clk,
      reset    => reset_n,
      start    => start,
      busy     => busy,
      done     => done,
      operand  => operand,
      n        => n,
      n_prime  => n_prime,
      new_data => new_data
    );

  --------------------------------------------------------------------
  -- Stimulus process
  --------------------------------------------------------------------
  stim_proc : process
    variable cycles : integer;
  begin
    reset_n <= '0';
    start   <= '0';
    wait for 5*CLK_PERIOD;
    reset_n <= '1';
    wait for 2*CLK_PERIOD;

    n_prime <= TEST_N_PRIME;

    for test_idx in 0 to TEST_A'length-1 loop
      -- Send A chunks and n chunks
      for i in 0 to 7 loop
        operand  <= TEST_A(test_idx)(255-32*i downto 224-32*i);
        n        <= TEST_N(255-32*i downto 224-32*i);
        new_data <= "01"; -- write A_reg and n_reg
        wait until rising_edge(clk);
      end loop;

      -- Send B chunks
      for i in 0 to 7 loop
        operand  <= TEST_B(test_idx)(255-32*i downto 224-32*i);
        new_data <= "10"; -- write B_reg
        wait until rising_edge(clk);
      end loop;

      new_data <= "00";

      -- Pulse start
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      -- Wait until done
      cycles := 0;
      loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
        exit when done = '1';
      end loop;

      report "MonPro TEST " & integer'image(test_idx+1) & " DONE in " & integer'image(cycles) & " cycles.";
      report "  r   = 0x" & to_hex(r);
      report "  exp = 0x" & to_hex(EXPECTED_R(test_idx));

      if r = EXPECTED_R(test_idx) then
        report "PASS: MonPro output matches expected.";
      else
        report "FAIL: MonPro output mismatch." severity error;
      end if;

      -- Optional reset between tests
      reset_n <= '0';
      wait until rising_edge(clk);
      reset_n <= '1';
      wait until rising_edge(clk);
    end loop;

    wait for 10*CLK_PERIOD;
    report "Simulation complete." severity note;
    wait;
  end process;

end architecture;
