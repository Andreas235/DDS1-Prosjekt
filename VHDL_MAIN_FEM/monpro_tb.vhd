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

  constant C_A : std_logic_vector(KW-1 downto 0) :=
--    x"4ED76052036851F7142CF1783B7F82D348D9B8E3E2DC4276B0CAD4E78F674692";
--    x"69ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567";
      x"1914dae33d65b78a9029940ac287486136d1a20ff5936c2774e82f676830c1a6";

  constant C_B : std_logic_vector(KW-1 downto 0) :=
--    x"77802675A284891B1C4633B913C659389057BF74123211F5EAB6C841E624A906";
--    x"6EDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
    x"4fc8b239c5a67176487434305023f7dcd9671c4e04dfaac67e4db3dd48796e5b";

  -- Expected REDC/CIOS result: (a*b*R^{-1}) mod n
  constant C_EXPECTED_R : std_logic_vector(KW-1 downto 0) :=
--    x"75EC707CCD93258BB10476108CDCA38017CBC29C417571B8F2AFEA77A36DCFAA";
--    x"328A777F8CDFBE115693E4C5B3C3487EDC08CAD3799F63BBA4C6F836A2E4F601";
    x"1f5b099b8996b66507fd90de9ab2b2e5f53205e8dc578e83f624a71e49e5a8cc";
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
    a       <= C_A;
    b       <= C_B;
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
    report "  exp = 0x" & to_hex(C_EXPECTED_R);

    -- PASS / FAIL print
    if r = C_EXPECTED_R then
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









