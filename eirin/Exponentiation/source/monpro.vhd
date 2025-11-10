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

  -- Pack/unpack helpers (LSW-first, i=0 -> bits [31:0])
  function unpack(slv: std_logic_vector) return vec_t is
    variable v : vec_t;
  begin
    for i in 0 to K-1 loop
      v(i) := unsigned(slv((i+1)*W-1 downto i*W));
    end loop;
    return v;
  end;
  function pack(v: vec_t) return std_logic_vector is
    variable slv : std_logic_vector(K*W-1 downto 0);
  begin
    for i in 0 to K-1 loop
      slv((i+1)*W-1 downto i*W) := std_logic_vector(v(i));
    end loop;
    return slv;
  end;

  -- Registers / storage
  signal A_reg, B_reg, N_reg : vec_t;
  signal i_idx               : integer range 0 to K-1 := 0;
  signal j_idx               : integer range 0 to K-1 := 0;

  -- carry must be 33 bits for 32x32 + carry folds
  signal carry     : unsigned(W+1 downto 0) := (others => '0'); -- 33 bits when W=32
  signal m_word    : word_t := (others => '0');

  -- inner accumulator split: K low words + a wide top that can hold two folds
  type    acc_core_t is array (0 to K-1) of word_t;
  signal  T_core : acc_core_t;
  signal  T_top  : unsigned(W+5 downto 0);  

  signal r_reg    : std_logic_vector(K*W-1 downto 0) := (others => '0');

  -- Split words
  signal a_lo, a_hi : unsigned(15 downto 0);
  signal b_lo, b_hi : unsigned(15 downto 0);
  signal n_lo, n_hi : unsigned(15 downto 0);
  signal m_lo, m_hi : unsigned(15 downto 0);

  -- Partial 64-bit accumulators
  signal ab_lo64, ab_hi64 : unsigned(63 downto 0);
  signal mn_lo64, mn_hi64 : unsigned(63 downto 0);
  signal m_lo64,  m_hi64  : unsigned(63 downto 0); -- for m = T0*n'

  -- Shared multiplier unit: two 16x16 multipliers
  signal mul0_a, mul0_b, mul1_a, mul1_b : unsigned(15 downto 0);
  signal mul0_p, mul1_p                 : unsigned(31 downto 0);

  -- n' as unsigned
  signal nprime_u : unsigned(31 downto 0);

  -- DSP mapping hint (optional)
  attribute use_dsp : string;
  attribute use_dsp of mul0_p : signal is "yes";
  attribute use_dsp of mul1_p : signal is "yes";

  -- FSM (Straight CIOS)
  type state_t is (
    S_IDLE, S_LOAD,

    -- per-i, Phase 1: AB accumulation across all j (no m yet)
    S_AB_J_PREP, S_AB0, S_AB1, S_AB_ADD, S_AB_NEXT, S_AB_FOLD,

    -- Compute m = low32( T(0) * n' )  (uses updated T(0)!)
    S_M0_SET, S_M0_USE, S_M1_SET, S_M1_USE,

    -- per-i, Phase 2: MN accumulation across all j (uses the m above)
    S_MN_J_PREP, S_MN0, S_MN1, S_MN_ADD, S_MN_NEXT, S_MN_FOLD,

    -- end of i-iteration
    S_SHIFT, S_NEXT_I,

    S_FINAL, S_DONE
  );
  signal st, st_n : state_t := S_IDLE;

begin
  -- DSPs
  mul0_p <= mul0_a * mul0_b;
  mul1_p <= mul1_a * mul1_b;

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
      when S_IDLE    => if start='1' then st_n <= S_LOAD; end if;
      when S_LOAD    => st_n <= S_AB_J_PREP;

      -- Phase 1: AB over all j
      when S_AB_J_PREP => st_n <= S_AB0;
      when S_AB0       => st_n <= S_AB1;
      when S_AB1       => st_n <= S_AB_ADD;
      when S_AB_ADD    => st_n <= S_AB_NEXT;
      when S_AB_NEXT   =>
        if j_idx = K-1 then st_n <= S_AB_FOLD;
        else               st_n <= S_AB_J_PREP;
        end if;
      when S_AB_FOLD   => st_n <= S_M0_SET;

      -- m = low32(T0 * n')
      when S_M0_SET    => st_n <= S_M0_USE;
      when S_M0_USE    => st_n <= S_M1_SET;
      when S_M1_SET    => st_n <= S_M1_USE;
      when S_M1_USE    => st_n <= S_MN_J_PREP;

      -- Phase 2: MN over all j
      when S_MN_J_PREP => st_n <= S_MN0;
      when S_MN0       => st_n <= S_MN1;
      when S_MN1       => st_n <= S_MN_ADD;
      when S_MN_ADD    => st_n <= S_MN_NEXT;
      when S_MN_NEXT   =>
        if j_idx = K-1 then st_n <= S_MN_FOLD;
        else               st_n <= S_MN_J_PREP;
        end if;
      when S_MN_FOLD   => st_n <= S_SHIFT;

      when S_SHIFT     => st_n <= S_NEXT_I;

      when S_NEXT_I    =>
        if i_idx = K-1 then st_n <= S_FINAL;
        else               st_n <= S_AB_J_PREP;
        end if;

      when S_FINAL     => st_n <= S_DONE;
      when S_DONE      => st_n <= S_IDLE;
    end case;
  end process;

  ------------------------------------------------------------------
  -- Datapath + control
  ------------------------------------------------------------------
  process(clk)
    variable sum64, tmp64 : unsigned(63 downto 0);
    variable sum66, tmp66 : unsigned(65 downto 0);
    variable res_vec : vec_t;
    variable ge_flag, eq_flag : boolean;
    variable wext_x, wext_y, tmp_w : unsigned(W downto 0);
    variable borrow  : unsigned(0 downto 0);
    variable idx_msw : integer;
    variable high_after : word_t;
    variable kclr : integer;
    variable m_word_v : word_t;
    -- helpers for folding + shifting the top accumulator
    variable c_ab, c_mn : unsigned(T_top'range);
    variable v_top, top_c : unsigned(T_top'range);
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        -- Clear regs/arrays
        for kclr in 0 to K-1 loop
          A_reg(kclr) <= (others => '0');
          B_reg(kclr) <= (others => '0');
          N_reg(kclr) <= (others => '0');
          T_core(kclr) <= (others => '0');
        end loop;
        T_top <= (others => '0');

        i_idx   <= 0; j_idx <= 0;
        carry   <= (others => '0');
        m_word  <= (others => '0');

        a_lo <= (others => '0'); a_hi <= (others => '0');
        b_lo <= (others => '0'); b_hi <= (others => '0');
        n_lo <= (others => '0'); n_hi <= (others => '0');
        m_lo <= (others => '0'); m_hi <= (others => '0');

        ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');
        mn_lo64 <= (others => '0'); mn_hi64 <= (others => '0');
        m_lo64  <= (others => '0'); m_hi64  <= (others => '0');

        mul0_a <= (others => '0'); mul0_b <= (others => '0');
        mul1_a <= (others => '0'); mul1_b <= (others => '0');

        r_reg  <= (others => '0');

      else
        case st is
          ------------------------------------------------------------
          when S_LOAD =>
            -- LSW-first slicing
            A_reg <= unpack(a);
            B_reg <= unpack(b);
            N_reg <= unpack(n);

            --report "A_reg(0) (LSW) = 0x" & to_hstring(std_logic_vector(A_reg(0))) severity note;
            --report "A_reg(K-1) (MSW) = 0x" & to_hstring(std_logic_vector(A_reg(K-1))) severity note;

            for kclr in 0 to K-1 loop
              T_core(kclr) <= (others => '0');
            end loop;
            T_top <= (others => '0');

            i_idx  <= 0;
            j_idx  <= 0;
            carry  <= (others => '0');

          ------------------------------------------------------------
          -- Phase 1: AB accumulation over j (no m yet)
          when S_AB_J_PREP =>
            -- prepare splits and preload AB0
            a_lo <= A_reg(i_idx)(15 downto 0);
            a_hi <= A_reg(i_idx)(31 downto 16);
            b_lo <= B_reg(j_idx)(15 downto 0);
            b_hi <= B_reg(j_idx)(31 downto 16);

            ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');

            mul0_a <= A_reg(i_idx)(15 downto 0);
            mul1_a <= A_reg(i_idx)(31 downto 16);
            mul0_b <= B_reg(j_idx)(15 downto 0);
            mul1_b <= B_reg(j_idx)(15 downto 0);

          when S_AB0 =>
            tmp64   := resize(mul0_p,64)
                    + shift_left(resize(mul1_p,64), 16);
            ab_lo64 <= tmp64;

            mul0_a <= a_lo; mul0_b <= b_hi;
            mul1_a <= a_hi; mul1_b <= b_hi;

          when S_AB1 =>
            tmp64   := shift_left(resize(mul0_p,64), 16)
                    + shift_left(resize(mul1_p,64), 32);
            ab_hi64 <= tmp64;

          when S_AB_ADD =>
            -- T[j] := T[j] + ab + carry
            tmp66  := resize(ab_lo64, 66) + resize(ab_hi64, 66);
            sum66  := tmp66 + resize(T_core(j_idx), 66) + resize(carry, 66);
            T_core(j_idx) <= word_t(sum66(31 downto 0)); -- keep low W
            carry         <=         sum66(65 downto 32);-- 33-bit carry

          when S_AB_NEXT =>
            if j_idx < K-1 then
              j_idx <= j_idx + 1;
            end if;

          when S_AB_FOLD =>
            -- capture carry and fold it into the top accumulator
            c_ab := resize(carry, T_top'length);
            v_top := T_top + c_ab;   -- what T_top will become this cycle
            T_top <= v_top;
            --report "AB_FOLD: carry_into_top = 0x" & to_hstring(std_logic_vector(c_ab)) & "  T_top(now) = 0x" & to_hstring(std_logic_vector(v_top)) severity note;

            carry <= (others => '0');
            j_idx <= 0;
            
          -- m = low32( T(0) * n' ) using two 16x16 passes
          when S_M0_SET =>
            m_lo64 <= (others => '0');
            m_hi64 <= (others => '0');

            a_lo <= T_core(0)(15 downto 0);
            a_hi <= T_core(0)(31 downto 16);
            n_lo <= nprime_u(15 downto 0);
            n_hi <= nprime_u(31 downto 16);

            mul0_a <= T_core(0)(15 downto 0);      -- a_lo * n_lo
            mul0_b <= nprime_u(15 downto 0);
            mul1_a <= T_core(0)(31 downto 16);     -- a_hi * n_lo
            mul1_b <= nprime_u(15 downto 0);

          when S_M0_USE =>
            tmp64  := resize(mul0_p,64) + shift_left(resize(mul1_p,64), 16);
            m_lo64 <= tmp64;

          when S_M1_SET =>
            mul0_a <= T_core(0)(15 downto 0);      -- a_lo * n_hi
            mul0_b <= nprime_u(31 downto 16);
            mul1_a <= T_core(0)(31 downto 16);     -- a_hi * n_hi
            mul1_b <= nprime_u(31 downto 16);

          when S_M1_USE =>
            tmp64   := shift_left(resize(mul0_p,64), 16)
                    + shift_left(resize(mul1_p,64), 32);
            m_hi64  <= tmp64;

            -- full 64-bit product, keep ONLY low W (radix-2^W rule)
            sum64   := m_lo64 + tmp64;
            m_word  <= word_t(sum64(31 downto 0));
            m_lo    <= sum64(15 downto 0);
            m_hi    <= sum64(31 downto 16);

            --report "m = 0x" & to_hstring(std_logic_vector(m_word)) severity note;

          ------------------------------------------------------------
          -- Phase 2: MN accumulation over j (using computed m)
          when S_MN_J_PREP =>
            mn_lo64 <= (others => '0'); mn_hi64 <= (others => '0');

            -- PRELOAD MN0 operands: m * n_lo (direct feed)
            mul0_a <= m_lo;                    mul0_b <= N_reg(j_idx)(15 downto 0);
            mul1_a <= m_hi;                    mul1_b <= N_reg(j_idx)(15 downto 0);

          when S_MN0 =>
            tmp64   := resize(mul0_p,64)
                    + shift_left(resize(mul1_p,64), 16);
            mn_lo64 <= tmp64;

            -- PRELOAD MN1 operands: m * n_hi (direct feed)
            mul0_a <= m_lo;                    mul0_b <= N_reg(j_idx)(31 downto 16);
            mul1_a <= m_hi;                    mul1_b <= N_reg(j_idx)(31 downto 16);

          when S_MN1 =>
            tmp64   := shift_left(resize(mul0_p,64), 16)
                    + shift_left(resize(mul1_p,64), 32);
            mn_hi64 <= tmp64;

          when S_MN_ADD =>
            tmp66  := resize(mn_lo64, 66) + resize(mn_hi64, 66);
            sum66  := tmp66 + resize(T_core(j_idx), 66) + resize(carry, 66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            carry         <=         sum66(65 downto 32);      -- 33-bit carry

          when S_MN_NEXT =>
            if j_idx < K-1 then
              j_idx <= j_idx + 1;
            end if;

         
          when S_MN_FOLD =>
            -- capture carry and fold it into the top accumulator
            c_mn := resize(carry, T_top'length);
            v_top := T_top + c_mn;   -- what T_top will become this cycle
            T_top <= v_top;

            --report "MN_FOLD: carry_into_top = 0x" & to_hstring(std_logic_vector(c_mn)) & "  T_top(now) = 0x" & to_hstring(std_logic_vector(v_top)) severity note;

            carry <= (others => '0');

          ------------------------------------------------------------
          when S_SHIFT =>
            -- Form a local copy of the current top so logs reflect the pre-shift value.
            v_top := T_top;

            -- Log the low W bits that will drop into the MSW of the core
            --report "top_before_shift = 0x" & to_hstring(std_logic_vector(v_top(W-1 downto 0))) severity note;

            -- Move the low W bits of v_top into the MSW word of T_core
            high_after := word_t(v_top(W-1 downto 0));

            -- Shift core right by one word
            for kclr in 0 to K-2 loop
              T_core(kclr) <= T_core(kclr+1);
            end loop;
            T_core(K-1) <= high_after;

            -- Now **preserve** the remaining top bits for the next i by shifting them down
            top_c := shift_right(v_top, W);
            T_top <= top_c;

            --report "top_after_shift_carry = 0x" & to_hstring(std_logic_vector(top_c)) severity note;

            -- Optional guard: warn (not assert) if we still have bits above our headroom
            if top_c(top_c'high downto W) /= ("0000") then
              report "WARN: T_top still has bits above W after shift; consider widening headroom" severity note;
            end if;

          when S_NEXT_I =>
            j_idx <= 0;
            if i_idx < K-1 then
              i_idx <= i_idx + 1;
            end if;

          ------------------------------------------------------------
          when S_FINAL =>
            -- pack result and conditional subtract n
            for kclr in 0 to K-1 loop
              res_vec(kclr) := T_core(kclr);
            end loop;

            -- MSW-first compare res_vec vs N_reg
            ge_flag := false; eq_flag := true;
            for kclr in 0 to K-1 loop
              idx_msw := K-1 - kclr;
              if res_vec(idx_msw) /= N_reg(idx_msw) then
                eq_flag := false;
                ge_flag := (res_vec(idx_msw) > N_reg(idx_msw));
                exit;
              end if;
            end loop;
            if eq_flag = true then ge_flag := true; end if;

            if ge_flag = true then
              -- subtract n (LSW-first)
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

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

end rtl;




