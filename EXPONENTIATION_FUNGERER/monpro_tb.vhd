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

  constant C_A2 : std_logic_vector(KW-1 downto 0) :=
    x"150d69cbcd04a2eba06ed0efd0183603ad5662ebf4dbc96f87a03d93643c35f0";
  constant C_B2 : std_logic_vector(KW-1 downto 0) :=
    x"038d882148c1d21a0983141322c900c0a702f60165aac0efdb88016de7ec9e05";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R2 : std_logic_vector(KW-1 downto 0) :=
    x"36df0b1309e2c3459d3abeaa294e370d8b12f0d7cd56e3664a9bf22f1699f19e";


  constant C_A1 : std_logic_vector(KW-1 downto 0) :=
    x"7b2c2cff3781db07b42ff01e242a6cfe7ef25a57c9491d84cb72a139c3897b63";
  constant C_B1 : std_logic_vector(KW-1 downto 0) :=
    x"f89aec4f5d4fab3f990d9124b40120839f8e068c36f94daf6cbd33e0955a2211";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R1 : std_logic_vector(KW-1 downto 0) :=
    x"2d9b33e33aba4fb7fd9dda7e04f91bb8110aa9a7fe4fa5e5f1a2dcbb3e681a25";

  constant C_A3 : std_logic_vector(KW-1 downto 0) :=
    x"4223d53d1a5f333321a4d30c9f741e13196f6fe8192c3f34bf077c6eed84a050";
  constant C_B3 : std_logic_vector(KW-1 downto 0) :=
    x"5a54577a1235f50c7091bd263dc274f72c0ec94e73cc40562e41dacd377f5161";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R3 : std_logic_vector(KW-1 downto 0) :=
    x"36a81b92cefd052f965595c5cb6085ba765d6f566cfd73e7a9ee32402780580c";
    
  constant C_A4 : std_logic_vector(KW-1 downto 0) :=
    x"d3c0c4fde53251c7334c40ec2db83c8f96b02d537354dd0b5841300efdef2772";
  constant C_B4 : std_logic_vector(KW-1 downto 0) :=
    x"21dc6c91f35e30246dbf7412fee3a0448e875bcdedd0b59c5ec75af92437bb47";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R4 : std_logic_vector(KW-1 downto 0) :=
    x"41cb3a792201748ceb52667412f6785af0be06a0753df2393c7f187378e4220f";    
    
    
  constant C_A5 : std_logic_vector(KW-1 downto 0) :=
    x"33bfccddb9d2a87445441a84eaa6a2445a60f3c778b8cccd86c927fc8d4e7660";
  constant C_B5 : std_logic_vector(KW-1 downto 0) :=
    x"e9538590d7c40b0fa414134993ba9baeb9f5004d5c924fbc309065607dbdde5b";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R5 : std_logic_vector(KW-1 downto 0) :=
    x"2a161917c0df0c80b529a8a23eadb6aa635cf4ece4cf3c44326a3bb702e20696";       

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

    wait until rising_edge(clk);
    
    start <= '1';
    wait for CLK_PERIOD;
    -- Drive inputs
    a       <= C_A1;
    b       <= C_B1;
    n       <= C_N;
    n_prime <= C_N_PRIME;
    
    -- Pulse start
    wait for CLK_PERIOD;
    start <= '0';
    a       <= C_A2;
    b       <= C_B2;

    wait for CLK_PERIOD;
    a       <= C_A3;
    b       <= C_B3;
    
    wait for CLK_PERIOD;
    a       <= C_A4;
    b       <= C_B4;
    
    wait for CLK_PERIOD;
    a       <= C_A5;
    b       <= C_B5;        

    -- Count cycles until done
    cycles := 0;
    loop
    wait for CLK_PERIOD;
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
         
    wait for 5*CLK_PERIOD;
    -- Drive inputs
    a       <= C_A2;
    b       <= C_B2;
    n       <= C_N;
    n_prime <= C_N_PRIME;

    -- Pulse start
    wait for 2*CLK_PERIOD;
    start <= '1';
    wait for 2*CLK_PERIOD;
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