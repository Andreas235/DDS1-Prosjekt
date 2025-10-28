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
  
  -- Accumulator: K low words + one (W+1)-bit top slot
  type    acc_core_t is array (0 to K-1) of word_t;

  -- Pack/unpack helpers (little-endian limbs)
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

  -- NEW (W+1 bits)
  signal carry : unsigned(W downto 0) := (others => '0');
  signal m_word              : word_t := (others => '0');
  
  signal  T_core : acc_core_t;
  -- NEW (must hold two 33-bit folds)
  signal  T_top  : unsigned(W+1 downto 0);  -- 34 bits when W=32

  signal r_reg               : std_logic_vector(K*W-1 downto 0) := (others => '0');

  -- Split words
  signal a_lo, a_hi : unsigned(15 downto 0);
  signal b_lo, b_hi : unsigned(15 downto 0);
  signal n_lo, n_hi : unsigned(15 downto 0);
  signal m_lo, m_hi : unsigned(15 downto 0);

  -- Partial 64-bit accumulators
  signal ab_lo64, ab_hi64 : unsigned(63 downto 0);
  signal mn_lo64, mn_hi64 : unsigned(63 downto 0);
  signal m_lo64,  m_hi64  : unsigned(63 downto 0); -- for m = T0*n'

  -- *** Shared multiplier unit: exactly two 16x16 multipliers ***
  signal mul0_a, mul0_b, mul1_a, mul1_b : unsigned(15 downto 0);
  signal mul0_p, mul1_p                 : unsigned(31 downto 0);

  -- n' as unsigned
  signal nprime_u : unsigned(31 downto 0);

  -- DSP mapping hint (optional)
  attribute use_dsp : string;
  attribute use_dsp of mul0_p : signal is "yes";
  attribute use_dsp of mul1_p : signal is "yes";

  -- FSM (Straight CIOS: AB phase → compute m → MN phase → shift)
  type state_t is (
    S_IDLE, S_LOAD,

    -- per-i, Phase 1: AB accumulation across all j (no m yet)
    S_AB_J_PREP,
    S_AB0, S_AB1,           -- two 16x16 passes to build 32x32 product
    S_AB_ADD,               -- add ab + T[j] + carry
    S_AB_NEXT,              -- advance j or finish AB phase
    S_AB_FOLD,              -- T(K) += carry; carry := 0

    -- Compute m = low32( T(0) * n' )  (uses updated T(0)!)
    S_M0_SET, S_M0_USE,
    S_M1_SET, S_M1_USE,

    -- per-i, Phase 2: MN accumulation across all j (uses the m above)
    S_MN_J_PREP,
    S_MN0, S_MN1,           -- two 16x16 passes to build 32x32 product
    S_MN_ADD,               -- add (m*n) + T[j] + carry
    S_MN_NEXT,              -- advance j or finish MN phase
    S_MN_FOLD,              -- T(K) += carry; carry := 0

    -- end of i-iteration
    S_SHIFT,                -- logical right shift by one word (drop T0)
    S_NEXT_I,               -- increment i or finish

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
    -- final packaging/compare/subtract
    variable res_vec : vec_t;
    variable ge_flag, eq_flag : boolean;
    variable wext_x, wext_y, tmp_w : unsigned(W downto 0);
    variable borrow  : unsigned(0 downto 0);
    variable idx_msw : integer;
    -- helpers
    variable high_after : word_t;
    variable kclr : integer;
    variable m_word_v : word_t;
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        -- Clear arrays (VHDL-93 safe)
        for kclr in 0 to K-1 loop
          A_reg(kclr) <= (others => '0');
          B_reg(kclr) <= (others => '0');
          N_reg(kclr) <= (others => '0');
        end loop;
        for kclr in 0 to K-1 loop
          T_core(kclr) <= (others => '0');
        end loop;
        T_top <= (others => '0');

        i_idx   <= 0;
        j_idx   <= 0;
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
            A_reg <= unpack(a);
            B_reg <= unpack(b);
            N_reg <= unpack(n);
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
            -- prepare splits from registers and PRELOAD AB0
            a_lo <= A_reg(i_idx)(15 downto 0);
            a_hi <= A_reg(i_idx)(31 downto 16);
            b_lo <= B_reg(j_idx)(15 downto 0);
            b_hi <= B_reg(j_idx)(31 downto 16);

            -- clear AB partials (MN unused this phase)
            ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');

            -- PRELOAD AB0 operands
            mul0_a <= A_reg(i_idx)(15 downto 0);
            mul1_a <= A_reg(i_idx)(31 downto 16);
            mul0_b <= B_reg(j_idx)(15 downto 0);
            mul1_b <= B_reg(j_idx)(15 downto 0);

          when S_AB0 =>
            -- USE AB0 products; PRELOAD AB1
            tmp64   := resize(mul0_p,64)
                     + shift_left(resize(mul1_p,64), 16);
            ab_lo64 <= tmp64;

            mul0_a <= a_lo; mul0_b <= b_hi;
            mul1_a <= a_hi; mul1_b <= b_hi;

          when S_AB1 =>
            -- USE AB1 products
            tmp64   := shift_left(resize(mul0_p,64), 16)
                     + shift_left(resize(mul1_p,64), 32);
            ab_hi64 <= tmp64;

          when S_AB_ADD =>
            -- T[j] := T[j] + ab + carry
            tmp66  := resize(ab_lo64, 66) + resize(ab_hi64, 66);
            sum66  := tmp66 + resize(T_core(j_idx), 66) + resize(carry, 66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));       -- low 32 bits
            carry         <=         sum66(64 downto 32);      -- **33-bit carry**

          when S_AB_NEXT =>
            if j_idx < K-1 then
              j_idx <= j_idx + 1;
            end if;

          when S_AB_FOLD =>
            -- fold carry into T(K) after AB phase; reset carry; j := 0
            T_top <= resize(T_top, W+2) + resize(carry, W+2);
            carry <= (others => '0');
            j_idx <= 0;

          ------------------------------------------------------------
          -- Compute m = low32( T(0) * n' ) with two 16x16 passes
            when S_M0_SET =>
              -- *** drive DSPs DIRECTLY from T(0) and n' ***
              m_lo64 <= (others => '0');
              m_hi64 <= (others => '0');
            
              -- split once for readability (locals are variables/signals, either is fine)
              a_lo <= T_core(0)(15 downto 0);
              a_hi <= T_core(0)(31 downto 16);
              n_lo <= nprime_u(15 downto 0);
              n_hi <= nprime_u(31 downto 16);
            
              -- S_M0_SET (first pass)
            mul0_a <= T_core(0)(15 downto 0);      -- a_lo
            mul0_b <= nprime_u(15 downto 0);       -- n_lo
            mul1_a <= T_core(0)(31 downto 16);     -- a_hi
            mul1_b <= nprime_u(15 downto 0);       -- n_lo
            
            when S_M0_USE =>
              tmp64  := resize(mul0_p,64) + shift_left(resize(mul1_p,64), 16);
              m_lo64 <= tmp64;
            
            when S_M1_SET =>
              -- S_M1_SET (second pass)
              mul0_a <= T_core(0)(15 downto 0);      -- a_lo
              mul0_b <= nprime_u(31 downto 16);      -- n_hi
              mul1_a <= T_core(0)(31 downto 16);     -- a_hi
              mul1_b <= nprime_u(31 downto 16);      -- n_hi
            
            when S_M1_USE =>
              tmp64   := shift_left(resize(mul0_p,64), 16)
                      + shift_left(resize(mul1_p,64), 32);
              m_hi64  <= tmp64;
            
              -- full 64-bit product of T(0)*n', keep low32 only
              sum64   := m_lo64 + tmp64;
              m_word  <= word_t(sum64(31 downto 0));
            
              -- cache halves of m for the MN phase (this is the ONLY place to set them)
              m_lo    <= sum64(15 downto 0);
              m_hi    <= sum64(31 downto 16);


          ------------------------------------------------------------
          -- Phase 2: MN accumulation over j (using computed m)
          when S_MN_J_PREP =>
            n_lo <= N_reg(j_idx)(15 downto 0);
            n_hi <= N_reg(j_idx)(31 downto 16);

            mn_lo64 <= (others => '0'); mn_hi64 <= (others => '0');

            -- PRELOAD MN0 operands: m * n_lo
            mul0_a <= m_lo; mul0_b <= n_lo;
            mul1_a <= m_hi; mul1_b <= n_lo;

          when S_MN0 =>
            -- USE MN0 products; PRELOAD MN1
            tmp64   := resize(mul0_p,64)
                     + shift_left(resize(mul1_p,64), 16);
            mn_lo64 <= tmp64;

            mul0_a <= m_lo; mul0_b <= n_hi;
            mul1_a <= m_hi; mul1_b <= n_hi;

          when S_MN1 =>
            -- USE MN1 products
            tmp64   := shift_left(resize(mul0_p,64), 16)
                     + shift_left(resize(mul1_p,64), 32);
            mn_hi64 <= tmp64;

          when S_MN_ADD =>
            -- T[j] := T[j] + (m*n) + carry
            tmp66  := resize(mn_lo64, 66) + resize(mn_hi64, 66);
            sum66  := tmp66 + resize(T_core(j_idx), 66) + resize(carry, 66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            carry         <=         sum66(64 downto 32);      -- **33-bit carry**

          when S_MN_NEXT =>
            if j_idx < K-1 then
              j_idx <= j_idx + 1;
            end if;

          when S_MN_FOLD =>
            -- fold carry after MN phase; reset carry
            T_top <= resize(T_top, W+2) + resize(carry, W+2);
            carry <= (others => '0');

          ------------------------------------------------------------
          when S_SHIFT =>
          -- take only the low W bits from the wide top
          high_after := word_t(T_top(W-1 downto 0));
        
          -- shift the core down by one word
          for kclr in 0 to K-2 loop
            T_core(kclr) <= T_core(kclr+1);
          end loop;
          T_core(K-1) <= high_after;
        
          -- clear the wide top for next i-iteration
          T_top <= (others => '0');

          when S_NEXT_I =>
            j_idx <= 0;
            if i_idx < K-1 then
              i_idx <= i_idx + 1;
            end if;

          ------------------------------------------------------------
          when S_FINAL =>
            -- pack T[0..K-1], conditional subtract N
            for kclr in 0 to K-1 loop
              res_vec(kclr) := T_core(kclr);
            end loop;

            -- MSW-first compare res_vec vs N_reg
            ge_flag := false; eq_flag := true;
            for kclr in 0 to K-1 loop
              idx_msw := K-1 - kclr;
              if res_vec(idx_msw) /= N_reg(idx_msw) then
                eq_flag := false;
                if res_vec(idx_msw) > N_reg(idx_msw) then
                  ge_flag := true;
                else
                  ge_flag := false;
                end if;
                exit;
              end if;
            end loop;
            if eq_flag = true then ge_flag := true; end if;

            if ge_flag = true then
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



