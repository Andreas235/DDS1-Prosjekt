library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exponentiation is
  generic (
    C_block_size : integer := 256;
    DEBUG        : boolean := true
  );
  port (
    -- input control
    valid_in  : in  std_logic;
    ready_in  : out std_logic;

    -- input data
    message   : in  std_logic_vector(C_block_size-1 downto 0);
    key       : in  std_logic_vector(C_block_size-1 downto 0);
    r2_mod_n  : in  std_logic_vector(C_block_size-1 downto 0);
    n_prime   : in  std_logic_vector(31 downto 0);

    -- VLNW schedules provided by software
    vlnw_schedule_0 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_1 : in  std_logic_vector(255 downto 0);

    -- output control
    ready_out : in  std_logic;
    valid_out : out std_logic;

    -- output data
    result    : out std_logic_vector(C_block_size-1 downto 0);

    -- modulus
    modulus   : in  std_logic_vector(C_block_size-1 downto 0);

    -- utility
    clk       : in  std_logic;
    reset_n   : in  std_logic
  );
end exponentiation;

architecture rtl of exponentiation is

  constant W : integer := 32;
  constant K : integer := C_block_size / W;

  component monpro
    generic (
      W : integer := 32; -- word size
      K : integer := 8   -- number of limbs (256/W)
    );
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

  component vlnw_controller
    port(
      clk                 : in  std_logic;
      reset               : in  std_logic; -- active-high
      load                : in  std_logic;
      monpro_done         : in  std_logic;
      vlnw_schedule_0     : in  std_logic_vector(255 downto 0);
      vlnw_schedule_1     : in  std_logic_vector(255 downto 0);
      read_precompute_adr : out std_logic_vector(3 downto 0);
      done                : out std_logic;
      monpro_op           : out std_logic_vector(1 downto 0)  -- "01"=square, "10"=multiply
    );
  end component;

  type table_t is array (0 to 7) of std_logic_vector(C_block_size-1 downto 0);

  type state_t is (
    S_IDLE,
    S_LATCH,
    S_TO_MONT_A, S_WAIT_TO_MONT_A,
    S_TO_MONT_ONE,
    S_A2,
    S_A3,
    S_GEN_ODD, S_WAIT_ODD,
    S_LOAD_VLNW,
    S_WAIT_OP,
    S_OP_SQ, S_OP_MUL,   -- LAUNCH states
    S_WAIT_MP,           -- waits for mp_done after any launch
    S_CHECK_VLNW_DONE,
    S_FROM_MONT,
    S_OUT
  );

  signal st            : state_t := S_IDLE;

  signal a_in, b_in    : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
  signal n_reg         : std_logic_vector(C_block_size-1 downto 0) := (others => '0');

  signal mp_start      : std_logic := '0';
  signal mp_busy       : std_logic;
  signal mp_done       : std_logic;
  signal mp_r          : std_logic_vector(C_block_size-1 downto 0);

  signal acc           : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
  signal oneM          : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
  signal A2            : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
  signal tbl           : table_t := (others => (others => '0'));
  signal tbl_idx       : integer range 0 to 7 := 0;

  -- VLNW
  signal vlnw_load     : std_logic := '0';
  signal vlnw_done     : std_logic;
  signal vlnw_op       : std_logic_vector(1 downto 0);
  signal vlnw_addr     : std_logic_vector(3 downto 0);

  -- I/O handshake
  signal ready_in_r    : std_logic := '1';
  signal valid_out_r   : std_logic := '0';
  signal result_r      : std_logic_vector(C_block_size-1 downto 0) := (others => '0');

  -- Multiply safety
  signal mul_addr_latched : std_logic_vector(3 downto 0);
  signal mul_idx_reg      : integer range 0 to 7;

  -- Latch true launch operands (works for both square and mul)
  signal a_latched, b_latched : std_logic_vector(C_block_size-1 downto 0);
  signal tbl_sel              : std_logic_vector(C_block_size-1 downto 0); -- latched tbl(idx)
  signal last_op              : std_logic_vector(1 downto 0) := "00";      -- remembers op for post-print

  signal obs_sq  : integer := 0;
  signal obs_mul : integer := 0;

  function vlnw_code_to_index(c : std_logic_vector(3 downto 0)) return integer is
  begin
    case c is
      when "0001" => return 0; -- 1
      when "0011" => return 1; -- 3
      when "0101" => return 2; -- 5
      when "0111" => return 3; -- 7
      when "1001" => return 4; -- 9
      when "1011" => return 5; -- 11
      when "1101" => return 6; -- 13
      when "1111" => return 7; -- 15
      when others => return -1; -- 0000 or invalid
    end case;
  end function;

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
  ready_in  <= ready_in_r;
  valid_out <= valid_out_r;
  result    <= result_r;

  u_monpro : monpro
    generic map ( W => W, K => K )
    port map (
      clk       => clk,
      reset_n   => reset_n,
      start     => mp_start,
      busy      => mp_busy,
      done      => mp_done,
      a         => a_in,
      b         => b_in,
      n         => n_reg,
      n_prime   => n_prime,
      r         => mp_r
    );

  u_vlnw : vlnw_controller
    port map (
      clk                 => clk,
      reset               => not reset_n,
      load                => vlnw_load,
      monpro_done         => mp_done,
      vlnw_schedule_0     => vlnw_schedule_0,
      vlnw_schedule_1     => vlnw_schedule_1,
      read_precompute_adr => vlnw_addr,
      done                => vlnw_done,
      monpro_op           => vlnw_op
    );

  process(clk, reset_n)
    variable i  : integer;
    variable idx: integer;
  begin
    if reset_n = '0' then
      st          <= S_IDLE;
      ready_in_r  <= '1';
      valid_out_r <= '0';
      result_r    <= (others => '0');

      a_in        <= (others => '0');
      b_in        <= (others => '0');
      n_reg       <= (others => '0');
      mp_start    <= '0';

      acc         <= (others => '0');
      oneM        <= (others => '0');
      A2          <= (others => '0');
      for i in 0 to 7 loop
        tbl(i) <= (others => '0');
      end loop;
      tbl_idx       <= 0;
      vlnw_load     <= '0';
      a_latched     <= (others => '0');
      b_latched     <= (others => '0');
      tbl_sel       <= (others => '0');
      mul_addr_latched <= (others => '0');
      mul_idx_reg   <= 0;
      last_op       <= "00";
      obs_sq        <= 0;
      obs_mul       <= 0;

    elsif rising_edge(clk) then
      mp_start  <= '0';
      vlnw_load <= '0';

      case st is
        when S_IDLE =>
          valid_out_r <= '0';
          ready_in_r  <= '1';
          if valid_in = '1' and ready_in_r = '1' then
            ready_in_r <= '0';
            st         <= S_LATCH;
          end if;

        when S_LATCH =>
          n_reg <= modulus;
          st    <= S_TO_MONT_A;

        -- toMont(A) = MonPro(A, R^2 mod n)
        when S_TO_MONT_A =>
          a_in     <= message;
          b_in     <= r2_mod_n;
          mp_start <= '1';
          st       <= S_WAIT_TO_MONT_A;

        when S_WAIT_TO_MONT_A =>
          if mp_done = '1' then
            acc <= mp_r;
            if DEBUG then
              report "toMont(A): A_M=0x" & slv_to_hex(mp_r) severity note;
            end if;

            -- toMont(1) = MonPro(1, R^2 mod n), LSW-first '1'
            a_in     <= (others => '0'); a_in(0) <= '1';
            b_in     <= r2_mod_n;
            mp_start <= '1';
            st       <= S_TO_MONT_ONE;
          end if;

        when S_TO_MONT_ONE =>
          if mp_done = '1' then
            oneM <= mp_r;
            if DEBUG then
              report "toMont(1): 1_M=0x" & slv_to_hex(mp_r) severity note;
            end if;
            tbl(0)  <= acc;           -- A^1
            a_in     <= acc;          -- compute A^2
            b_in     <= acc;
            mp_start <= '1';
            st       <= S_A2;
          end if;

        when S_A2 =>
          if mp_done = '1' then
            A2 <= mp_r;               -- A^2
            if DEBUG then
              report "precomp A^2_M = 0x" & slv_to_hex(mp_r) severity note;
            end if;
            a_in     <= mp_r;         -- A^3 = A^2 * A
            b_in     <= acc;
            mp_start <= '1';
            st       <= S_A3;
          end if;

        when S_A3 =>
          if mp_done = '1' then
            tbl(1)  <= mp_r;          -- A^3
            if DEBUG then
              report "precomp A^3_M = 0x" & slv_to_hex(mp_r) severity note;
            end if;
            tbl_idx <= 2;             -- next: A^5..A^15
            a_in     <= mp_r;         -- A^5 = A^3 * A^2
            b_in     <= A2;
            mp_start <= '1';
            st       <= S_GEN_ODD;
          end if;

        when S_GEN_ODD =>
          if mp_done = '1' then
            tbl(tbl_idx) <= mp_r;     -- A^(2*idx+1)
            if DEBUG then
              report "precomp A^" & integer'image(2*tbl_idx+1) &
                     "_M = 0x" & slv_to_hex(mp_r) severity note;
            end if;

            if tbl_idx = 7 then
              st <= S_LOAD_VLNW;
            else
              tbl_idx   <= tbl_idx + 1;
              a_in      <= mp_r;
              b_in      <= A2;
              mp_start  <= '1';
              st        <= S_WAIT_ODD;
            end if;
          end if;

        when S_WAIT_ODD =>
          st <= S_GEN_ODD;

        when S_LOAD_VLNW =>
          acc       <= oneM;     -- start from 1_M
          vlnw_load <= '1';
          st        <= S_WAIT_OP;

        when S_WAIT_OP =>
          if DEBUG then
            if vlnw_op = "01" then
              report "VLNW: SQUARE" severity note;
            elsif vlnw_op = "10" then
              report "VLNW: MULT addr=" & integer'image(to_integer(unsigned(vlnw_addr))) severity note;
            end if;
          end if;

          if mp_busy = '0' then
            if vlnw_done = '1' then
              -- convert out of Montgomery
              a_in     <= acc;
              b_in     <= (others => '0'); b_in(0) <= '1';
              mp_start <= '1';
              st       <= S_FROM_MONT;

            elsif vlnw_op = "01" then
              -- PREPARE square (no start yet)
              a_latched <= acc;
              b_latched <= acc;
              last_op   <= "01";
              st        <= S_OP_SQ;

            elsif vlnw_op = "10" then
              -- PREPARE multiply (no start yet)
              mul_addr_latched <= vlnw_addr;
              idx := vlnw_code_to_index(vlnw_addr);
              assert (vlnw_addr /= "0000")
                report "VLNW ERROR: multiply requested while v = 0000" severity failure;
              assert idx >= 0 report "VLNW addr invalid/zero for multiply" severity failure;
              assert idx <= 7 report "Precompute index out of range" severity failure;

              mul_idx_reg <= idx;     -- keep for logs
              a_latched   <= acc;     -- freeze A
              tbl_sel     <= tbl(idx);-- freeze chosen table word
              last_op     <= "10";
              st          <= S_OP_MUL;

            else
              null;
            end if;
          end if;

        -- LAUNCH square
        when S_OP_SQ =>
          a_in     <= a_latched;
          b_in     <= b_latched;
          mp_start <= '1';
          if DEBUG then
            report "LAUNCH SQUARE  A=" & slv_to_hex(a_latched) &
                   "  B=" & slv_to_hex(b_latched) severity note;
          end if;
          st <= S_WAIT_MP;

        -- LAUNCH multiply
        when S_OP_MUL =>
          a_in     <= a_latched;
          b_in     <= tbl_sel;
          mp_start <= '1';
          if DEBUG then
            report "LAUNCH MULT idx=" & integer'image(mul_idx_reg) &
                   "  A=" & slv_to_hex(a_latched) &
                   "  B=tbl[idx]=" & slv_to_hex(tbl_sel) severity note;
          end if;
          st <= S_WAIT_MP;

        -- Wait for MonPro to finish, then update acc and print
        when S_WAIT_MP =>
          if mp_done = '1' then
            acc <= mp_r;
            if DEBUG then
              if last_op = "01" then
                obs_sq <= obs_sq + 1;
                report "after SQUARE: acc=0x" & slv_to_hex(mp_r) severity note;
              elsif last_op = "10" then
                obs_mul <= obs_mul + 1;
                report "after MULT (idx=" & integer'image(mul_idx_reg) &
                       "): acc=0x" & slv_to_hex(mp_r) severity note;
              end if;
            end if;
            st <= S_CHECK_VLNW_DONE;
          end if;

        when S_CHECK_VLNW_DONE =>
          if vlnw_done = '1' then
            a_in     <= acc;
            b_in     <= (others => '0'); b_in(0) <= '1';
            mp_start <= '1';
            st       <= S_FROM_MONT;
          else
            st <= S_WAIT_OP;
          end if;

        when S_FROM_MONT =>
          if mp_done = '1' then
            result_r    <= mp_r;
            if DEBUG then
              report "fromMont: result=0x" & slv_to_hex(mp_r) severity note;
            end if;
            valid_out_r <= '1';
            st          <= S_OUT;
          end if;

        when S_OUT =>
          if ready_out = '1' then
            valid_out_r <= '0';
            st          <= S_IDLE;
          end if;

        when others =>
          st <= S_IDLE;
      end case;
    end if;
  end process;
end rtl;






