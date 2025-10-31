library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity monpro_tb is
end monpro_tb;

architecture tb of monpro_tb is
  --------------------------------------------------------------------
  -- MonPro generics  
  --------------------------------------------------------------------
  constant W  : integer := 32;
  constant K  : integer := 8;
  constant KW : integer := K*W;

  --------------------------------------------------------------------
  -- Clocking
  --------------------------------------------------------------------
  constant CLK_PERIOD : time := 10 ns;
  signal   clk        : std_logic := '0';

  --------------------------------------------------------------------
  -- DUT I/O
  --------------------------------------------------------------------
  signal reset_n : std_logic := '0';
  signal start   : std_logic := '0';
  signal busy    : std_logic;
  signal done    : std_logic;

  signal a, b, n : std_logic_vector(KW-1 downto 0) := (others => '0');
  signal n_prime : std_logic_vector(31 downto 0)    := (others => '0');
  signal r       : std_logic_vector(KW-1 downto 0);

--acc, prev 0xf793fa1b23135af844376afa0254206772157962c7cbe9ce321a534dc7d634b
--precompute 0x26c5eb1b633656a4a8935dbfec7809d5f0ab227524f0ed33c2721ef49f7468c1
--acc after monpro 0x7c806a85e8db0b3a8eafe8c8ff586b0e3775095be3bbb9f1250b64e3e994f5cd
  --------------------------------------------------------------------
  -- Test vectors (yours)
  --------------------------------------------------------------------
  constant C_N : std_logic_vector(KW-1 downto 0) :=
    x"99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D";
  constant C_N_PRIME : std_logic_vector(31 downto 0) := x"8833C3BB"; -- 2285093819

  constant C_A1 : std_logic_vector(KW-1 downto 0) :=
    x"5b9e402b76181c9c95ce28ced7dde4c04d1e1f5773e9e67e4c907c8fa7c390cc";
  constant C_B1 : std_logic_vector(KW-1 downto 0) :=
    x"1808a604ed7dedcf26e8e371a4e312a51fae740f749aaac0ac10c9cc3469d8d4";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R1 : std_logic_vector(KW-1 downto 0) :=
    x"184b7e4d8ff947e2de26b0b8f53c163e81446674168a412ec366d81cc4b96b4e";


  constant C_A2 : std_logic_vector(KW-1 downto 0) :=
    x"8f60c53bb52fa76d469a3b9a490eca9b1f5772cce572ec4713846d441af9fbb1";
  constant C_B2 : std_logic_vector(KW-1 downto 0) :=
    x"10a2f2df9d2aa444e749ed66e18ff0900c61d1e35e8ce408f51ef74b88004abd";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R2 : std_logic_vector(KW-1 downto 0) :=
    x"87460fc6a55cbc145a1921c2cd2b37cd7e135a065f6cb4569778f1ef6d8320d8";

  constant C_A3 : std_logic_vector(KW-1 downto 0) :=
    x"0ae6c5206a56a95614ae267f12a8bf8c62084ce19e08df8e26f99f8bc4e7135b";
  constant C_B3 : std_logic_vector(KW-1 downto 0) :=
    x"98ca11cc657b20aa771f4cffe1bd12dcb6a3c90bb0e1e20649bf14b4332845c1";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R3 : std_logic_vector(KW-1 downto 0) :=
    x"1fc0f35f4a35741a9ed4fcb881a235ef8d1d5cab77236a499539e4d01cc60adc";

  --------------------------------------------------------------------
  -- Helper: std_logic_vector → HEX string (VHDL-93 friendly)
  --------------------------------------------------------------------
  function to_hex(slv : std_logic_vector) return string is
    constant HEX : string := "0123456789ABCDEF";
    constant N   : integer := slv'length/4;  -- assumes multiple of 4
    variable s   : string(1 to N);
    variable nib : std_logic_vector(3 downto 0);
    variable idx : integer;
  begin
    -- build from MSB nibble to LSB nibble
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
  -- DUT
  --------------------------------------------------------------------
  DUT : entity work.monpro
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

  --------------------------------------------------------------------
  -- Stimulus
  --------------------------------------------------------------------
  stim_proc : process
    variable cycles : integer := 0;
  begin
    -- Reset
    reset_n <= '0';
    start   <= '0';
    wait for 5*CLK_PERIOD;
    reset_n <= '1';
    wait for 2*CLK_PERIOD;

    -- Drive inputs
    a       <= C_A1;
    b       <= C_B1;
    n       <= C_N;
    n_prime <= C_N_PRIME;

    -- Pulse start
    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- Count cycles until done
    cycles := 0;
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when done = '1';
    end loop;
    
    

    -- Always print the DUT result and expected
    report "MonPro DONE in " & integer'image(cycles) & " cycles.";
    report "  r   = 0x" & to_hex(r);
    report "  exp = 0x" & to_hex(C_EXPECTED_R1);

    -- PASS / FAIL print
    if r = C_EXPECTED_R1 then
      report "PASS: MonPro output matches expected.";
    else
      report "FAIL: MonPro output mismatch." severity error;
    end if;
            
    -- Drive inputs
    a       <= C_A2;
    b       <= C_B2;
    n       <= C_N;
    n_prime <= C_N_PRIME;

    -- Pulse start
    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- Count cycles until done
    cycles := 0;
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when done = '1';
    end loop;
    
    -- Always print the DUT result and expected
    report "MonPro DONE in " & integer'image(cycles) & " cycles.";
    report "  r   = 0x" & to_hex(r);
    report "  exp = 0x" & to_hex(C_EXPECTED_R2);

    -- PASS / FAIL print
    if r = C_EXPECTED_R2 then
      report "PASS: MonPro output matches expected.";
    else
      report "FAIL: MonPro output mismatch." severity error;
    end if;

    -- Drive inputs
    a       <= C_A3;
    b       <= C_B3;
    n       <= C_N;
    n_prime <= C_N_PRIME;

    -- Pulse start
    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    -- Count cycles until done
    cycles := 0;
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when done = '1';
    end loop;
    
    -- Always print the DUT result and expected
    report "MonPro DONE in " & integer'image(cycles) & " cycles.";
    report "  r   = 0x" & to_hex(r);
    report "  exp = 0x" & to_hex(C_EXPECTED_R3);

    -- PASS / FAIL print
    if r = C_EXPECTED_R3 then
      report "PASS: MonPro output matches expected.";
    else
      report "FAIL: MonPro output mismatch." severity error;
    end if;

    -- End sim
    wait for 10*CLK_PERIOD;
    report "Simulation complete." severity note;
    wait;
  end process;

end architecture;









