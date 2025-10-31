-- filepath: c:\Users\student\Documents\group_5x2_old\tfe4141_rsa_integration_kit_2025\vlnw\vlnw.srcs\sources_1\new\monpro.vhd
-- Montgomery multiplication (CIOS), 4×16x16 multipliers for 32x32 in 1 cycle
-- W=32, K=8 default (256-bit). Handshake: start -> busy -> done
-- femfem

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity monpro is
  generic (
    W : integer := 32; -- word size
    K : integer := 8   -- number of limbs (256/W)
  );
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic;
    -- Control
    start     : in  std_logic;
    busy      : out std_logic;
    done      : out std_logic;
    -- Operands
    a         : in  std_logic_vector(K*W-1 downto 0);
    b         : in  std_logic_vector(K*W-1 downto 0);
    n         : in  std_logic_vector(K*W-1 downto 0);
    n_prime   : in  std_logic_vector(31 downto 0); -- -n^{-1} mod 2^32
    -- Result
    r         : out std_logic_vector(K*W-1 downto 0)
  );
end monpro;

architecture rtl of monpro is
  -- Types
  subtype word_t is unsigned(W-1 downto 0);
  type    vec_t  is array (0 to K-1) of word_t;

  -- Pack/unpack helpers (little-endian limbs)
  function unpack(slv: std_logic_vector) return vec_t is
    variable v : vec_t;
  begin
    for i in 0 to K-1 loop
      v(i) := unsigned(slv((i+1)*W-1 downto i*W));
    end loop;
    return v;
  end function;

  function pack(v: vec_t) return std_logic_vector is
    variable slv : std_logic_vector(K*W-1 downto 0);
  begin
    for i in 0 to K-1 loop
      slv((i+1)*W-1 downto i*W) := std_logic_vector(v(i));
    end loop;
    return slv;
  end function;

  -- Registers / storage
  signal A_reg, B_reg, N_reg : vec_t;
  signal T_core              : vec_t;
  -- Carry between limbs (needs 34 bits for W=32)
  signal carry               : unsigned(33 downto 0) := (others => '0');
  -- Top slot accumulates end-of-row carries (W + margin). Cleared after shift.
  signal T_top               : unsigned(W+3 downto 0) := (others => '0'); -- 36 bits for W=32
  signal m_word              : word_t := (others => '0');

  signal r_reg               : std_logic_vector(K*W-1 downto 0) := (others => '0');

  -- Indices
  signal i_idx               : integer range 0 to K-1 := 0;
  signal j_idx               : integer range 0 to K-1 := 0;

  -- 4×16x16 multipliers to form 32x32 in one cycle
  signal mul_a0, mul_b0      : unsigned(15 downto 0) := (others => '0'); -- x_lo * y_lo
  signal mul_a1, mul_b1      : unsigned(15 downto 0) := (others => '0'); -- x_lo * y_hi
  signal mul_a2, mul_b2      : unsigned(15 downto 0) := (others => '0'); -- x_hi * y_lo
  signal mul_a3, mul_b3      : unsigned(15 downto 0) := (others => '0'); -- x_hi * y_hi
  signal mul_p0, mul_p1      : unsigned(31 downto 0);
  signal mul_p2, mul_p3      : unsigned(31 downto 0);

  -- n' as unsigned
  signal nprime_u            : unsigned(31 downto 0);

  -- DSP mapping hint (optional)
  attribute use_dsp : string;
  attribute use_dsp of mul_p0 : signal is "yes";
  attribute use_dsp of mul_p1 : signal is "yes";
  attribute use_dsp of mul_p2 : signal is "yes";
  attribute use_dsp of mul_p3 : signal is "yes";

  -- FSM: AB loop (SET once, then ADD per j) → m (USE) → MN loop (ADD per j) → fold+shift
  type state_t is (
    S_IDLE, S_LOAD,
    S_AB_SET,               -- set mults for AB j=0
    S_AB_ADD,               -- per j: add product and set next j inputs
    S_AB_FOLD_MSET,         -- fold carry, set mults for m=T0*n'
    S_M_USE,                -- use mults for m, compute m_word and set MN j=0
    S_MN_ADD,               -- per j: add product and set next j inputs
    S_MN_FOLD_SHIFT_NEXT,   -- fold carry, shift, set next-i AB j=0 (if any)
    S_FINAL, S_DONE
  );
  signal st, st_n : state_t := S_IDLE;

begin
  -- Multiplier products
  mul_p0 <= mul_a0 * mul_b0;
  mul_p1 <= mul_a1 * mul_b1;
  mul_p2 <= mul_a2 * mul_b2;
  mul_p3 <= mul_a3 * mul_b3;

  -- Simple wires
  nprime_u <= unsigned(n_prime);
  r        <= r_reg;
  busy     <= '1' when (st /= S_IDLE and st /= S_DONE) else '0';
  done     <= '1' when st = S_DONE else '0';

  ------------------------------------------------------------------
  -- State register
  ------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        st <= S_IDLE;
      else
        st <= st_n;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------
  -- Next-state logic
  ------------------------------------------------------------------
  process(st, start, j_idx, i_idx)
  begin
    st_n <= st;
    case st is
      when S_IDLE =>
        if start = '1' then st_n <= S_LOAD; end if;

      when S_LOAD =>
        st_n <= S_AB_SET;

      when S_AB_SET =>
        st_n <= S_AB_ADD;

      when S_AB_ADD =>
        if j_idx = K-1 then
          st_n <= S_AB_FOLD_MSET;
        else
          st_n <= S_AB_ADD; -- continue j++
        end if;

      when S_AB_FOLD_MSET =>
        st_n <= S_M_USE;

      when S_M_USE =>
        st_n <= S_MN_ADD;

      when S_MN_ADD =>
        if j_idx = K-1 then
          st_n <= S_MN_FOLD_SHIFT_NEXT;
        else
          st_n <= S_MN_ADD; -- continue j++
        end if;

      when S_MN_FOLD_SHIFT_NEXT =>
        if i_idx = K-1 then
          st_n <= S_FINAL;
        else
          st_n <= S_AB_ADD; -- next-i AB j=0 already set here
        end if;

      when S_FINAL =>
        st_n <= S_DONE;

      when S_DONE =>
        st_n <= S_IDLE;

      when others =>
        st_n <= S_IDLE;
    end case;
  end process;

  ------------------------------------------------------------------
  -- Datapath + control
  ------------------------------------------------------------------
  process(clk)
    -- robust 32x32 from 4 partials with explicit 16-bit carry handling
    variable p00, p01, p10, p11    : unsigned(31 downto 0);
    variable cross_lo16, cross_hi16: unsigned(16 downto 0); -- 17-bit to catch carry
    variable prod64                : unsigned(63 downto 0);
    variable sum66                 : unsigned(65 downto 0);
    variable res_vec               : vec_t;
    variable ge_flag, eq_flag      : boolean;
    variable wext_x, wext_y, tmp_w : unsigned(W downto 0);
    variable borrow                : unsigned(0 downto 0);
    variable idx_msw               : integer;
    variable kclr                  : integer;
    variable top_sum               : unsigned(W+3 downto 0);
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        -- Clear regs
        for kclr in 0 to K-1 loop
          A_reg(kclr)  <= (others => '0');
          B_reg(kclr)  <= (others => '0');
          N_reg(kclr)  <= (others => '0');
          T_core(kclr) <= (others => '0');
        end loop;
        T_top   <= (others => '0');
        carry   <= (others => '0');
        m_word  <= (others => '0');
        i_idx   <= 0;
        j_idx   <= 0;
        mul_a0  <= (others => '0'); mul_b0 <= (others => '0');
        mul_a1  <= (others => '0'); mul_b1 <= (others => '0');
        mul_a2  <= (others => '0'); mul_b2 <= (others => '0');
        mul_a3  <= (others => '0'); mul_b3 <= (others => '0');
        r_reg   <= (others => '0');

      else
        case st is
          ------------------------------------------------------------
          when S_LOAD =>
            A_reg <= unpack(a);
            B_reg <= unpack(b);
            N_reg <= unpack(n);
            for kclr in 0 to K-1 loop
              T_core(kclr) <= (others => '0');
            end loop;
            T_top <= (others => '0');
            carry <= (others => '0');
            i_idx <= 0; j_idx <= 0;

          ------------------------------------------------------------
          -- AB initial set for j=0 (prepare multiplier inputs)
          when S_AB_SET =>
            mul_a0 <= A_reg(i_idx)(15 downto 0);   mul_b0 <= B_reg(0)(15 downto 0);
            mul_a1 <= A_reg(i_idx)(15 downto 0);   mul_b1 <= B_reg(0)(31 downto 16);
            mul_a2 <= A_reg(i_idx)(31 downto 16);  mul_b2 <= B_reg(0)(15 downto 0);
            mul_a3 <= A_reg(i_idx)(31 downto 16);  mul_b3 <= B_reg(0)(31 downto 16);
            j_idx  <= 0;

          ------------------------------------------------------------
          -- AB per-j add; also set next j's mul inputs (if any)
          when S_AB_ADD =>
            -- snapshot partials
            p00 := mul_p0; p01 := mul_p1; p10 := mul_p2; p11 := mul_p3;

            -- product = p00 + ((p01+p10)<<16) + (p11<<32), with 16-bit carry separated
            cross_lo16 := resize(p01(15 downto 0), 17) + resize(p10(15 downto 0), 17);
            cross_hi16 := resize(p01(31 downto 16), 17) + resize(p10(31 downto 16), 17) + resize(unsigned(cross_lo16(16 downto 16)), 17);

            prod64 := resize(p00,64)
                      + shift_left(resize(cross_lo16(15 downto 0),64), 16)
                      + shift_left(resize(p11,64) + resize(cross_hi16,64), 32);

            -- T[j] += prod64 + carry
            sum66 := resize(prod64,66) + resize(T_core(j_idx),66) + resize(carry,66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            carry         <= sum66(65 downto 32);

            -- Preload next j (if any)
            if j_idx < K-1 then
              mul_a0 <= A_reg(i_idx)(15 downto 0);   mul_b0 <= B_reg(j_idx+1)(15 downto 0);
              mul_a1 <= A_reg(i_idx)(15 downto 0);   mul_b1 <= B_reg(j_idx+1)(31 downto 16);
              mul_a2 <= A_reg(i_idx)(31 downto 16);  mul_b2 <= B_reg(j_idx+1)(15 downto 0);
              mul_a3 <= A_reg(i_idx)(31 downto 16);  mul_b3 <= B_reg(j_idx+1)(31 downto 16);
              j_idx  <= j_idx + 1;
            end if;

          ------------------------------------------------------------
          -- Fold AB carry and set muls for m = T0 * n'
          when S_AB_FOLD_MSET =>
            T_top <= resize(T_top, W+4) + resize(carry, W+4);
            carry <= (others => '0');

            -- Set muls for m: T_core(0) * nprime_u
            mul_a0 <= T_core(0)(15 downto 0);       mul_b0 <= nprime_u(15 downto 0);
            mul_a1 <= T_core(0)(15 downto 0);       mul_b1 <= nprime_u(31 downto 16);
            mul_a2 <= T_core(0)(31 downto 16);      mul_b2 <= nprime_u(15 downto 0);
            mul_a3 <= T_core(0)(31 downto 16);      mul_b3 <= nprime_u(31 downto 16);

          ------------------------------------------------------------
          -- Use m mult result; compute m_word and set MN j=0 mul inputs
          when S_M_USE =>
            p00 := mul_p0; p01 := mul_p1; p10 := mul_p2; p11 := mul_p3;
            cross_lo16 := resize(p01(15 downto 0), 17) + resize(p10(15 downto 0), 17);
            cross_hi16 := resize(p01(31 downto 16), 17) + resize(p10(31 downto 16), 17) + resize(unsigned(cross_lo16(16 downto 16)), 17);
            prod64 := resize(p00,64)
                      + shift_left(resize(cross_lo16(15 downto 0),64), 16)
                      + shift_left(resize(p11,64) + resize(cross_hi16,64), 32);

            m_word <= word_t(prod64(31 downto 0));      -- m = low 32 bits
            -- set MN j=0 using m halves
            mul_a0 <= prod64(15 downto 0);              mul_b0 <= N_reg(0)(15 downto 0);
            mul_a1 <= prod64(15 downto 0);              mul_b1 <= N_reg(0)(31 downto 16);
            mul_a2 <= prod64(31 downto 16);             mul_b2 <= N_reg(0)(15 downto 0);
            mul_a3 <= prod64(31 downto 16);             mul_b3 <= N_reg(0)(31 downto 16);
            j_idx  <= 0;

          ------------------------------------------------------------
          -- MN per-j add; also set next j's mul inputs (if any)
          when S_MN_ADD =>
            p00 := mul_p0; p01 := mul_p1; p10 := mul_p2; p11 := mul_p3;
            cross_lo16 := resize(p01(15 downto 0), 17) + resize(p10(15 downto 0), 17);
            cross_hi16 := resize(p01(31 downto 16), 17) + resize(p10(31 downto 16), 17) + resize(unsigned(cross_lo16(16 downto 16)), 17);
            prod64 := resize(p00,64)
                      + shift_left(resize(cross_lo16(15 downto 0),64), 16)
                      + shift_left(resize(p11,64) + resize(cross_hi16,64), 32);

            sum66 := resize(prod64,66) + resize(T_core(j_idx),66) + resize(carry,66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            carry         <= sum66(65 downto 32);

            -- Preload next j (if any)
            if j_idx < K-1 then
              mul_a0 <= m_word(15 downto 0);            mul_b0 <= N_reg(j_idx+1)(15 downto 0);
              mul_a1 <= m_word(15 downto 0);            mul_b1 <= N_reg(j_idx+1)(31 downto 16);
              mul_a2 <= m_word(31 downto 16);           mul_b2 <= N_reg(j_idx+1)(15 downto 0);
              mul_a3 <= m_word(31 downto 16);           mul_b3 <= N_reg(j_idx+1)(31 downto 16);
              j_idx  <= j_idx + 1;
            end if;

          ------------------------------------------------------------
          when S_MN_FOLD_SHIFT_NEXT =>
            -- fold MN carry into top and use immediately
            top_sum := resize(T_top, W+4) + resize(carry, W+4);
            carry   <= (others => '0');

            -- shift (drop T0), bring in low W bits of (T_top + carry)
            for kclr in 0 to K-2 loop
              T_core(kclr) <= T_core(kclr+1);
            end loop;
            T_core(K-1) <= word_t(top_sum(W-1 downto 0));
            T_top       <= (others => '0');

            -- if more i, prepare next-i AB j=0 here and jump straight to S_AB_ADD
            if i_idx < K-1 then
              i_idx  <= i_idx + 1;
              mul_a0 <= A_reg(i_idx+1)(15 downto 0);   mul_b0 <= B_reg(0)(15 downto 0);
              mul_a1 <= A_reg(i_idx+1)(15 downto 0);   mul_b1 <= B_reg(0)(31 downto 16);
              mul_a2 <= A_reg(i_idx+1)(31 downto 16);  mul_b2 <= B_reg(0)(15 downto 0);
              mul_a3 <= A_reg(i_idx+1)(31 downto 16);  mul_b3 <= B_reg(0)(31 downto 16);
              j_idx  <= 0;
            end if;

          ------------------------------------------------------------
          when S_FINAL =>
            -- Conditional subtraction if result >= N
            for kclr in 0 to K-1 loop
              res_vec(kclr) := T_core(kclr);
            end loop;

            -- Compare res_vec vs N_reg (MSW-first)
            ge_flag := false; eq_flag := true;
            for kclr in 0 to K-1 loop
              idx_msw := K-1 - kclr;
              if res_vec(idx_msw) /= N_reg(idx_msw) then
                eq_flag := false;
                ge_flag := (res_vec(idx_msw) > N_reg(idx_msw));
                exit;
              end if;
            end loop;
            if eq_flag then ge_flag := true; end if;

            if ge_flag then
              borrow := (others => '0');
              for kclr in 0 to K-1 loop
                wext_x := resize(res_vec(kclr), W+1);
                wext_y := resize(N_reg(kclr),  W+1) + resize(borrow, W+1);
                if wext_x < wext_y then
                  tmp_w := (wext_x + (to_unsigned(1, W+1) sll W)) - wext_y;
                  res_vec(kclr) := word_t(tmp_w(W-1 downto 0));
                  borrow(0)     := '1';
                else
                  tmp_w := wext_x - wext_y;
                  res_vec(kclr) := word_t(tmp_w(W-1 downto 0));
                  borrow(0)     := '0';
                end if;
              end loop;
            end if;

            r_reg <= pack(res_vec);

          when S_DONE =>
            null;

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;
end rtl;