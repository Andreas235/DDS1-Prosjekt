library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_exponentiation_realistic is
end entity;

architecture sim of tb_exponentiation_realistic is
  ---------------------------------------------------------------------------
  -- Parameters
  ---------------------------------------------------------------------------
  constant C_BLOCK : integer := 256;

  ---------------------------------------------------------------------------
  -- Realistic constants (you can replace later)
  -- n is 256-bit odd modulus; R = 2^256; R2 = R^2 mod n
  -- n' = (-n^{-1}) mod 2^32 (depends only on n(31 downto 0); n must be odd)
  ---------------------------------------------------------------------------
  constant MODULUS_C  : std_logic_vector(C_BLOCK-1 downto 0)
    := x"99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D";  --RIKTIG

  constant R2MODN_C   : std_logic_vector(C_BLOCK-1 downto 0)
    := x"56DDF8B43061AD3DBCD1757244D1A19E2E8C849DDE4817E55BB29D1C20C06364"; --RIKTIG

  constant NPRIME_C   : std_logic_vector(31 downto 0)
    := x"8833C3BB"; --RIKTIG

--  PASSED
--  constant MESSAGE_C  : std_logic_vector(C_BLOCK-1 downto 0)
--    := x"704e5e0e346e7e1d61e19f5af3fe6c648bda7c9cd4fb846b189fc26de869f46e";
    
--  constant EXPECTED_RESULT_M  : std_logic_vector(C_BLOCK-1 downto 0)
--    := x"47D69AAD3C674409759981524CE494FD331DBE831A4970E6D6AB58052FFF24D0";

  -- Decrypt test
  constant MESSAGE_C  : std_logic_vector(C_BLOCK-1 downto 0)
    := x"82e4aa076ea2c02379b92d51d709e6f91115be3bfdb765f3f5189834ebcef835";
    
  constant EXPECTED_RESULT_M  : std_logic_vector(C_BLOCK-1 downto 0)
    := x"1fdb98b6ec4a80207089f920281362579442ebf8685c654812c94cd053466cce";

  -- Decrypt schedule
  constant DECR_SCHED0 : std_logic_vector(255 downto 0) :=
    x"b6682f00b07782b04f5fb84202b7e189f8427e12c11b781780f00b02f03bfe00";

  constant DECR_SCHED1 : std_logic_vector(255 downto 0) :=
    x"dc2103340be7fc2780580bc2fc00d601ebc1341341341dc37a703705e9c31019";
    
  constant DECR_SCHED2 : std_logic_vector(255 downto 0) := 
    x"e7016fff02700000000000000000000000000000000000000000000000000000";
        
        
  -- Encrypt test
  -- Encrypt schedule
  constant ENCR_SCHED0 : std_logic_vector(255 downto 0) :=
    x"0c20418618800000000000000000000000000000000000000000000000000000";

  constant ENCR_SCHED1 : std_logic_vector(255 downto 0) :=
    x"0000000000000000000000000000000000000000000000000000000000000000";
    
  constant ENCR_SCHED2 : std_logic_vector(255 downto 0) := 
    x"0000000000000000000000000000000000000000000000000000000000000000";
    
  constant MESSAGE_M  : std_logic_vector(C_BLOCK-1 downto 0)
    := x"0a23232323232323232323232323232323232323232323232323232323232323";
    
  constant EXPECTED_RESULT_C  : std_logic_vector(C_BLOCK-1 downto 0)
    := x"85ee722363960779206a2b37cc8b64b5fc12a934473fa0204bbaaf714bc90c01";
  ---------------------------------------------------------------------------
  -- Hex print helpers (VHDL-93 safe)
  ---------------------------------------------------------------------------
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

  -- Render an std_logic_vector as a hex string (MSB left). Width must be multiple of 4.
  function slv_to_hex(slv : std_logic_vector) return string is
    constant N  : integer := slv'length / 4;
    variable res_str : string(1 to N);
    variable hi, lo  : integer;
    variable nib     : std_logic_vector(3 downto 0);
  begin
    for i in 0 to N-1 loop
      hi  := slv'left - 4*i;
      lo  := hi - 3;
      nib := slv(hi downto lo);
      res_str(i+1) := hex_nib(nib);
    end loop;
    return res_str;
  end function;

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal clk       : std_logic := '0';
  signal reset_n   : std_logic := '0';

  signal valid_in  : std_logic := '0';
  signal ready_in  : std_logic;

  signal message   : std_logic_vector(C_BLOCK-1 downto 0);
  signal key       : std_logic_vector(C_BLOCK-1 downto 0) := (others => '0'); -- unused
  signal r2_mod_n  : std_logic_vector(C_BLOCK-1 downto 0);
  signal n_prime   : std_logic_vector(31 downto 0);

  signal vlnw0     : std_logic_vector(255 downto 0);
  signal vlnw1     : std_logic_vector(255 downto 0);
  signal vlnw2     : std_logic_vector(255 downto 0);

  signal ready_out : std_logic := '1';
  signal valid_out : std_logic;
  signal result    : std_logic_vector(C_BLOCK-1 downto 0);
  signal modulus   : std_logic_vector(C_BLOCK-1 downto 0);
  signal last_in   : std_logic := '0';
  signal last_out  : std_logic := '0';

begin
  ---------------------------------------------------------------------------
  -- 100 MHz clock
  ---------------------------------------------------------------------------
  clk <= not clk after 5 ns;

  dut: entity work.exponentiation
    generic map (
      C_block_size => C_BLOCK
    )
    port map (
      valid_in         => valid_in,
      ready_in         => ready_in,
      last_in          => last_in,
      message          => message,
      key              => key,
      r2_mod_n         => r2_mod_n,
      n_prime          => n_prime,
      vlnw_schedule_0  => vlnw0,
      vlnw_schedule_1  => vlnw1,
      vlnw_schedule_2  => vlnw2,
      ready_out        => ready_out,
      valid_out        => valid_out,
      last_out         => last_out,
      result           => result,
      modulus          => modulus,
      clk              => clk,
      reset_n          => reset_n
    );

  ---------------------------------------------------------------------------
  -- Stimulus
  ---------------------------------------------------------------------------
  stim: process
      variable cycles : integer := 0;
  begin
    -- Reset
    reset_n <= '0';
    wait for 200 ns;
    reset_n <= '1';
    wait for 50 ns;




    -- DECRYPTION TEST
    -- Handshake one transaction
    wait until rising_edge(clk);
    while ready_in = '0' loop
      wait until rising_edge(clk);
    end loop;
    valid_in <= '1';
    modulus  <= MODULUS_C;
    message  <= MESSAGE_C;
    r2_mod_n <= R2MODN_C;
    n_prime  <= NPRIME_C;
    vlnw0    <= DECR_SCHED0;
    vlnw1    <= DECR_SCHED1;
    vlnw2    <= DECR_SCHED2;    
        wait until rising_edge(clk);
    valid_in <= '0';
    
    -- Show inputs in hex
    report "TB  message = 0x"  & slv_to_hex(message)  severity note;
    report "TB  modulus = 0x"  & slv_to_hex(modulus)  severity note;
    report "TB  R2_modn = 0x"  & slv_to_hex(r2_mod_n) severity note;
    report "TB  n_prime = 0x"  & slv_to_hex(std_logic_vector(n_prime)) severity note;    

    -- Count cycles until done
    cycles := 0;
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when valid_out = '1';
    end loop;
    
    -- Wait for result and print hex
    report "Exponentiation DONE in " & integer'image(cycles) & " cycles.";
    report "Final    result  = 0x" & slv_to_hex(result) severity note;
    report "Expected result  = 0x" & slv_to_hex(EXPECTED_RESULT_M) severity note;
    if result = EXPECTED_RESULT_M then
        report "PASS: EXPONENTIATION output matches expected.";
    else
        report "FAIL: EXPONENTIATION output mismatch." severity error;
    end if;
    
    
    
    
    
    
    
    -- ENCRYPTION TEST
    -- Handshake one transaction
    wait until rising_edge(clk);
    while ready_in = '0' loop
      wait until rising_edge(clk);
    end loop;
    valid_in <= '1';
    modulus  <= MODULUS_C;
    message  <= MESSAGE_M;
    r2_mod_n <= R2MODN_C;
    n_prime  <= NPRIME_C;
    vlnw0    <= ENCR_SCHED0;
    vlnw1    <= ENCR_SCHED1;
    vlnw2    <= ENCR_SCHED2;    
        wait until rising_edge(clk);
    valid_in <= '0';
    
        -- Show inputs in hex
    report "TB  message = 0x"  & slv_to_hex(message)  severity note;
    report "TB  modulus = 0x"  & slv_to_hex(modulus)  severity note;
    report "TB  R2_modn = 0x"  & slv_to_hex(r2_mod_n) severity note;
    report "TB  n_prime = 0x"  & slv_to_hex(std_logic_vector(n_prime)) severity note;

    -- Count cycles until done
    cycles := 0;
    loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
      exit when valid_out = '1';
    end loop;
    
    -- Wait for result and print hex
    report "Exponentiation DONE in " & integer'image(cycles) & " cycles.";
    report "Final    result  = 0x" & slv_to_hex(result) severity note;
    report "Expected result  = 0x" & slv_to_hex(EXPECTED_RESULT_C) severity note;
    if result = EXPECTED_RESULT_C then
        report "PASS: EXPONENTIATION output matches expected.";
    else
        report "FAIL: EXPONENTIATION output mismatch." severity error;
    end if;    
    
    
    
    
    
    wait for 100 ns;
    report "TB finished." severity note;
    wait;
  end process;

end architecture;