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
  type    acc_t  is array (0 to K)   of word_t; -- K+1 words (top slot)

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
  signal T                   : acc_t;     -- T[0..K]
  signal i_idx               : integer range 0 to K-1 := 0;
  signal j_idx               : integer range 0 to K-1 := 0;

  signal carry               : word_t := (others => '0');
  signal m_word              : word_t := (others => '0');

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

  -- FSM
    -- FSM
  type state_t is (
    S_IDLE, S_LOAD,

    -- m = low32(T0 * n') via two 16x16 passes (kept as SET/USE for safety)
    S_I_INIT,
    S_M0_SET, S_M0_USE,
    S_M1_SET, S_M1_USE,

    -- per-j: collapse to single-cycle passes (AB0, AB1, MN0, MN1), keep ADD
    S_J_PREP,
    S_AB0,
    S_AB1,
    S_MN0,
    S_MN1,
    S_ADD,

    S_AFTER_J,
    S_NEXT_I, S_FINAL, S_DONE
  );

  signal st, st_n : state_t := S_IDLE;

begin
  -- Shared multipliers (2 DSPs total)
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
      when S_LOAD    => st_n <= S_I_INIT;

      when S_I_INIT  => st_n <= S_M0_SET;
      when S_M0_SET  => st_n <= S_M0_USE;
      when S_M0_USE  => st_n <= S_M1_SET;
      when S_M1_SET  => st_n <= S_M1_USE;
      when S_M1_USE  => st_n <= S_J_PREP;

      when S_J_PREP  => st_n <= S_AB0;
      when S_AB0     => st_n <= S_AB1;
      when S_AB1     => st_n <= S_MN0;
      when S_MN0     => st_n <= S_MN1;
      when S_MN1     => st_n <= S_ADD;

      when S_ADD =>
        if j_idx = K-1 then st_n <= S_AFTER_J;
        else               st_n <= S_J_PREP;
        end if;

      when S_AFTER_J => st_n <= S_NEXT_I;

      when S_NEXT_I =>
        if i_idx = K-1 then
          st_n <= S_FINAL;
        else
          st_n <= S_I_INIT;
        end if;

      when S_FINAL   => st_n <= S_DONE;
      when S_DONE    => st_n <= S_IDLE;
    end case;
  end process;


  ------------------------------------------------------------------
  -- Datapath + control
  ------------------------------------------------------------------
  process(clk)
    variable sum64, tmp64 : unsigned(63 downto 0);
    -- final packaging/compare/subtract
    variable res_vec : vec_t;
    variable ge_flag, eq_flag : boolean;
    variable wext_x, wext_y, tmp_w : unsigned(W downto 0);
    variable borrow  : unsigned(0 downto 0);
    variable idx_msw : integer;
    -- carry-fold shift helper
    variable high_after : word_t;
    -- loop index for clears
    variable kclr : integer;
    variable m_word_v : word_t;  -- NEW: to hold low32(T0*n') this cycle
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        -- Clear arrays (VHDL-93 safe)
        for kclr in 0 to K-1 loop
          A_reg(kclr) <= (others => '0');
          B_reg(kclr) <= (others => '0');
          N_reg(kclr) <= (others => '0');
        end loop;
        for kclr in 0 to K loop
          T(kclr) <= (others => '0');
        end loop;

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
            for kclr in 0 to K loop T(kclr) <= (others => '0'); end loop;
            i_idx  <= 0;
            j_idx  <= 0;
            carry  <= (others => '0');

          ------------------------------------------------------------
          -- m = low32( T(0) * nprime_u ) via two 16x16 passes
          when S_I_INIT =>
            m_lo64 <= (others => '0');
            m_hi64 <= (others => '0');
            m_lo   <= T(0)(15 downto 0);
            m_hi   <= T(0)(31 downto 16);
            n_lo   <= nprime_u(15 downto 0);
            n_hi   <= nprime_u(31 downto 16);

          when S_M0_SET =>
            -- q0 = m_lo * n_lo (<<0); q1 = m_hi * n_lo (<<16)
            mul0_a <= m_lo; mul0_b <= n_lo;
            mul1_a <= m_hi; mul1_b <= n_lo;

          when S_M0_USE =>
            tmp64  := resize(mul0_p,64)
                      + shift_left(resize(mul1_p,64), 16);
            m_lo64 <= tmp64;

          when S_M1_SET =>
            -- q2 = m_lo * n_hi (<<16); q3 = m_hi * n_hi (<<32)
            mul0_a <= m_lo; mul0_b <= n_hi;
            mul1_a <= m_hi; mul1_b <= n_hi;

          when S_M1_USE =>
          -- Compute the "hi" partial of T0 * n' for this pass
          tmp64  := shift_left(resize(mul0_p,64), 16)
                    + shift_left(resize(mul1_p,64), 32);
        
          -- Form the FULL 64-bit product using the *fresh* tmp64 (hi) and the
          -- m_lo64 captured in S_M0_USE (lo). Do NOT read m_hi64 here.
          sum64    := m_lo64 + tmp64;
        
          -- Update the pipeline registers
          m_hi64   <= tmp64;
        
          -- Low 32 bits are m (Montgomery "m" = low32(T0 * n'))
          m_word_v := word_t(sum64(31 downto 0));
          m_word   <= m_word_v;
        
          -- VERY IMPORTANT: refresh m_lo/m_hi from the *new* m_word for MN passes
          m_lo     <= m_word_v(15 downto 0);
          m_hi     <= m_word_v(31 downto 16);
        
          carry    <= (others => '0');

          ------------------------------------------------------------
          -- Prepare j operands and PRELOAD AB0 multiplier inputs
          when S_J_PREP =>
            a_lo <= A_reg(i_idx)(15 downto 0);
            a_hi <= A_reg(i_idx)(31 downto 16);
            b_lo <= B_reg(j_idx)(15 downto 0);
            b_hi <= B_reg(j_idx)(31 downto 16);
            n_lo <= N_reg(j_idx)(15 downto 0);
            n_hi <= N_reg(j_idx)(31 downto 16);

            -- clear partials
            ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');
            mn_lo64 <= (others => '0'); mn_hi64 <= (others => '0');

            -- PRELOAD AB0 operands for the next cycle (use sources, not just-updated splits)
            mul0_a <= A_reg(i_idx)(15 downto 0);
            mul1_a <= A_reg(i_idx)(31 downto 16);
            mul0_b <= B_reg(j_idx)(15 downto 0);
            mul1_b <= B_reg(j_idx)(15 downto 0);


         ------------------------------------------------------------
          -- AB0: USE current mul products; PRELOAD AB1 operands
          when S_AB0 =>
            -- products seen here correspond to J_PREP's operand preload
            tmp64   := resize(mul0_p,64)
                      + shift_left(resize(mul1_p,64), 16);
            ab_lo64 <= tmp64;

            -- PRELOAD AB1 operands for next cycle
            mul0_a <= a_lo; mul0_b <= b_hi;
            mul1_a <= a_hi; mul1_b <= b_hi;

         ------------------------------------------------------------
          -- AB1: USE current mul products; PRELOAD MN0 operands
          when S_AB1 =>
            tmp64   := shift_left(resize(mul0_p,64), 16)
                      + shift_left(resize(mul1_p,64), 32);
            ab_hi64 <= tmp64;

            -- PRELOAD MN0 operands (m * n_lo)
            mul0_a <= m_lo; mul0_b <= n_lo;
            mul1_a <= m_hi; mul1_b <= n_lo;

        
            
          ------------------------------------------------------------
          -- MN0: USE current mul products; PRELOAD MN1 operands
          when S_MN0 =>
            tmp64   := resize(mul0_p,64)
                      + shift_left(resize(mul1_p,64), 16);
            mn_lo64 <= tmp64;

            -- PRELOAD MN1 operands (m * n_hi)
            mul0_a <= m_lo; mul0_b <= n_hi;
            mul1_a <= m_hi; mul1_b <= n_hi;

  
            
          ------------------------------------------------------------
          -- MN1: USE current mul products
          when S_MN1 =>
            tmp64   := shift_left(resize(mul0_p,64), 16)
                      + shift_left(resize(mul1_p,64), 32);
            mn_hi64 <= tmp64;

          ------------------------------------------------------------
          when S_ADD =>
            -- sum64 = (ab_lo64+ab_hi64) + (mn_lo64+mn_hi64) + T[j] + carry
            sum64 := ab_lo64 + ab_hi64;
            sum64 := sum64 + mn_lo64 + mn_hi64;
            sum64 := sum64 + resize(T(j_idx),64) + resize(carry,64);

            T(j_idx) <= word_t(sum64(31 downto 0));
            carry    <= word_t(sum64(63 downto 32));

            if j_idx < K-1 then
              j_idx <= j_idx + 1;
            end if;

          ------------------------------------------------------------
          when S_AFTER_J =>
            -- CIOS: fold final carry and logical shift by one word
            high_after := word_t(unsigned(T(K)) + unsigned(carry));

            -- new T(0..K-2) = old T(1..K-1)
            for kclr in 0 to K-2 loop
              T(kclr) <= T(kclr+1);
            end loop;
            T(K-1) <= high_after;   -- lands here after shift
            T(K)   <= (others => '0');

            carry  <= (others => '0');
            j_idx  <= 0;

          ------------------------------------------------------------
          when S_NEXT_I =>
            if i_idx < K-1 then
              i_idx <= i_idx + 1;
            end if;

          ------------------------------------------------------------
          when S_FINAL =>
            -- pack T[0..K-1], conditional subtract N
            for kclr in 0 to K-1 loop
              res_vec(kclr) := T(kclr);
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
              -- res_vec := res_vec - N_reg (word-serial)
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


