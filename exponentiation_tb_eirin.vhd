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
    := x"99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D";

  constant R2MODN_C   : std_logic_vector(C_BLOCK-1 downto 0)
    := x"56DDF8B43061AD3DBCD1757244D1A19E2E8C849DDE4817E55BB29D1C20C06364";

  constant NPRIME_C   : std_logic_vector(31 downto 0)
    := x"8833C3BB";

  constant MESSAGE_C  : std_logic_vector(C_BLOCK-1 downto 0)
    := x"47D69AAD3C674409759981524CE494FD331DBE831A4970E6D6AB58052FFF24D0";

  ---------------------------------------------------------------------------
  -- Your encoded schedule words (EXACT 256-bit binary strings; MSB-left)
  ---------------------------------------------------------------------------
  -- 0000 001
  constant SCHED0_BITS : std_logic_vector(255 downto 0) :=
    "1001110100111000000111111111111010111100111100111000001000111000000100111011111000000110111000000100111011111000010110111000001001111001111001111101111011111010111000011111111000010101111000000010111011111000001111111100111101111000000001111000001000111000";

  constant SCHED1_BITS : std_logic_vector(255 downto 0) :=
    "1101110000001111111101110000010111110000000101110111111011110000001011110011110000000101110000011111110001111111110001110000001111110101110000000001111101111011110111110000010101110000001011110000110101110111110000000011010000000000000000000000000000000000";
    
  --- ENCODED SCHEDULE BREAKDOWN ---
  -- Entries total: 78
  -- Word 0 bits (256): 
  -- Word 1 bits (256): 
    
    


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

  signal ready_out : std_logic := '1';
  signal valid_out : std_logic;
  signal result    : std_logic_vector(C_BLOCK-1 downto 0);
  signal modulus   : std_logic_vector(C_BLOCK-1 downto 0);

begin
  ---------------------------------------------------------------------------
  -- 100 MHz clock
  ---------------------------------------------------------------------------
  clk <= not clk after 5 ns;

  ---------------------------------------------------------------------------
  -- Tie constants to DUT inputs
  ---------------------------------------------------------------------------
  modulus  <= MODULUS_C;
  message  <= MESSAGE_C;
  r2_mod_n <= R2MODN_C;
  n_prime  <= NPRIME_C;
  vlnw0    <= SCHED0_BITS;
  vlnw1    <= SCHED1_BITS;

  ---------------------------------------------------------------------------
  -- DUT instance (no DEBUG generic here; your current exponentiation entity has none)
  ---------------------------------------------------------------------------
  dut: entity work.exponentiation
    generic map (
      C_block_size => C_BLOCK
    )
    port map (
      valid_in         => valid_in,
      ready_in         => ready_in,
      message          => message,
      key              => key,
      r2_mod_n         => r2_mod_n,
      n_prime          => n_prime,
      vlnw_schedule_0  => vlnw0,
      vlnw_schedule_1  => vlnw1,
      ready_out        => ready_out,
      valid_out        => valid_out,
      result           => result,
      modulus          => modulus,
      clk              => clk,
      reset_n          => reset_n
    );

  ---------------------------------------------------------------------------
  -- Stimulus
  ---------------------------------------------------------------------------
  stim: process
  begin
    -- Reset
    reset_n <= '0';
    wait for 200 ns;
    reset_n <= '1';
    wait for 50 ns;

    -- Show inputs in hex
    report "TB  message = 0x"  & slv_to_hex(message)  severity note;
    report "TB  modulus = 0x"  & slv_to_hex(modulus)  severity note;
    report "TB  R2_modn = 0x"  & slv_to_hex(r2_mod_n) severity note;
    report "TB  n_prime = 0x"  & slv_to_hex(std_logic_vector(n_prime)) severity note;

    -- Handshake one transaction
    wait until rising_edge(clk);
    while ready_in = '0' loop
      wait until rising_edge(clk);
    end loop;
    valid_in <= '1';
    wait until rising_edge(clk);
    valid_in <= '0';

    -- Wait for result and print hex
    wait until valid_out = '1';
    report "TB  result  = 0x" & slv_to_hex(result) severity note;

    wait for 100 ns;
    report "TB finished." severity note;
    wait;
  end process;

end architecture;







