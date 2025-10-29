--femfem
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

  -- NEW (W+2+1 bits for full 34-bit carry across 32-bit limbs)
  signal carry : unsigned(W+2 downto 0) := (others => '0');
  signal m_word              : word_t := (others => '0');
  
  signal  T_core : acc_core_t;
  -- Must hold sum of two carries (up to 35 bits when W=32)
  signal  T_top  : unsigned(W+3 downto 0);  -- 35 bits when W=32

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

  -- FSM (Tight CIOS: AB loop → m → MN loop → fold+shift)
  type state_t is (
    S_IDLE, S_LOAD,

    -- AB phase (one-time preload + 3 cycles per j)
    S_AB_PREP0,
    S_AB0, S_AB1, S_AB_ADD,
    S_AB_FOLD_MPREP,         -- fold carry, prep m-pass0

    -- m = low32(T0*n') in 2 use cycles (after 1 prep above)
    S_M0, S_M1,              -- S_M1 also preloads MN j0

    -- MN phase (3 cycles per j)
    S_MN0, S_MN1, S_MN_ADD,
    S_MN_FOLD_SHIFT_NEXT,    -- fold carry, shift, inc i, preload next-i AB0

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
      when S_IDLE  => if start='1' then st_n <= S_LOAD; end if;
      when S_LOAD  => st_n <= S_AB_PREP0;

      -- AB phase
      when S_AB_PREP0 => st_n <= S_AB0;
      when S_AB0      => st_n <= S_AB1;
      when S_AB1      => st_n <= S_AB_ADD;
      when S_AB_ADD   =>
        if j_idx = K-1 then st_n <= S_AB_FOLD_MPREP;
        else               st_n <= S_AB0;
        end if;

      -- fold AB carry and prep m
      when S_AB_FOLD_MPREP => st_n <= S_M0;

      -- m compute (uses preloaded pass0)
      when S_M0      => st_n <= S_M1;
      when S_M1      => st_n <= S_MN0;

      -- MN phase
      when S_MN0     => st_n <= S_MN1;
      when S_MN1     => st_n <= S_MN_ADD;
      when S_MN_ADD  =>
        if j_idx = K-1 then st_n <= S_MN_FOLD_SHIFT_NEXT;
        else               st_n <= S_MN0;
        end if;

      when S_MN_FOLD_SHIFT_NEXT =>
        if i_idx = K-1 then st_n <= S_FINAL;
        else               st_n <= S_AB0;     -- next i starts at AB0 (already preloaded)
        end if;

      when S_FINAL   => st_n <= S_DONE;
      when S_DONE    => st_n <= S_IDLE;
    end case;
  end process;

  ------------------------------------------------------------------
  -- Datapath + control (tightened schedule)
  ------------------------------------------------------------------
  process(clk)
    variable sum64, tmp64 : unsigned(63 downto 0);
    variable sum66, tmp66 : unsigned(65 downto 0);
    variable res_vec : vec_t;
    variable ge_flag, eq_flag : boolean;
    variable wext_x, wext_y, tmp_w : unsigned(W downto 0);
    variable borrow  : unsigned(0 downto 0);
    variable idx_msw : integer;
    variable kclr    : integer;
    -- locals for m and preloads
    variable m_lo_next, m_hi_next : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        -- ...existing reset...
                carry  <= (others => '0');
        T_top  <= (others => '0');

        -- clear regs
        for kclr in 0 to K-1 loop
          A_reg(kclr) <= (others => '0');
          B_reg(kclr) <= (others => '0');
          N_reg(kclr) <= (others => '0');
          T_core(kclr) <= (others => '0');
        end loop;
        T_top  <= (others => '0');
        i_idx  <= 0; j_idx <= 0;
        carry  <= (others => '0');
        m_word <= (others => '0');
        ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');
        mn_lo64 <= (others => '0'); mn_hi64 <= (others => '0');
        m_lo64  <= (others => '0'); m_hi64  <= (others => '0');
        mul0_a <= (others => '0'); mul0_b <= (others => '0');
        mul1_a <= (others => '0'); mul1_b <= (others => '0');
        r_reg <= (others => '0');

      else
        case st is
          ------------------------------------------------------------
          when S_LOAD =>
            A_reg <= unpack(a);
            B_reg <= unpack(b);
            N_reg <= unpack(n);
            for kclr in 0 to K-1 loop T_core(kclr) <= (others => '0'); end loop;
            T_top <= (others => '0');
            i_idx <= 0; j_idx <= 0; carry <= (others => '0');

          ------------------------------------------------------------
          -- AB phase: one-time preload and 3-cycle loop per j
          when S_AB_PREP0 =>
            -- preload AB0 for j=0
            ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');
            mul0_a  <= A_reg(i_idx)(15 downto 0);
            mul1_a  <= A_reg(i_idx)(31 downto 16);
            mul0_b  <= B_reg(0)(15 downto 0);
            mul1_b  <= B_reg(0)(15 downto 0);
            j_idx   <= 0;

          when S_AB0 =>
            -- use preloaded AB0; preload AB1
            tmp64   := resize(mul0_p,64) + shift_left(resize(mul1_p,64),16);
            ab_lo64 <= tmp64;
            mul0_a  <= A_reg(i_idx)(15 downto 0);   mul0_b <= B_reg(j_idx)(31 downto 16);
            mul1_a  <= A_reg(i_idx)(31 downto 16);  mul1_b <= B_reg(j_idx)(31 downto 16);

          when S_AB1 =>
            -- use AB1
            tmp64   := shift_left(resize(mul0_p,64),16) + shift_left(resize(mul1_p,64),32);
            ab_hi64 <= tmp64;

          when S_AB_ADD =>
            -- T[j] += ab + carry
            tmp66  := resize(ab_lo64,66) + resize(ab_hi64,66);
            sum66  := tmp66 + resize(T_core(j_idx),66) + resize(carry,66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            -- carry is the upper 34 bits [65:32]
            carry         <=         sum66(65 downto 32);

            -- preload next j's AB0 and bump j (if any)
            if j_idx < K-1 then
              mul0_a <= A_reg(i_idx)(15 downto 0);
              mul1_a <= A_reg(i_idx)(31 downto 16);
              mul0_b <= B_reg(j_idx+1)(15 downto 0);
              mul1_b <= B_reg(j_idx+1)(15 downto 0);
              j_idx  <= j_idx + 1;
            end if;

          when S_AB_FOLD_MPREP =>
            -- fold AB carry
            T_top <= resize(T_top, W+4) + resize(carry, W+4);
            carry <= (others => '0');
            -- prep m pass0
            m_lo64 <= (others => '0'); m_hi64 <= (others => '0');
            mul0_a <= T_core(0)(15 downto 0);      mul0_b <= nprime_u(15 downto 0);
            mul1_a <= T_core(0)(31 downto 16);     mul1_b <= nprime_u(15 downto 0);

          ------------------------------------------------------------
          -- m = low32(T0*n'): 2 use cycles
          when S_M0 =>
            -- use pass0; preload pass1
            tmp64   := resize(mul0_p,64) + shift_left(resize(mul1_p,64),16);
            m_lo64  <= tmp64;
            mul0_a  <= T_core(0)(15 downto 0);     mul0_b <= nprime_u(31 downto 16);
            mul1_a  <= T_core(0)(31 downto 16);    mul1_b <= nprime_u(31 downto 16);

          when S_M1 =>
            -- finish product and form m_word; also preload MN j=0
            tmp64      := shift_left(resize(mul0_p,64),16) + shift_left(resize(mul1_p,64),32);
            m_hi64     <= tmp64;
            sum64      := m_lo64 + tmp64;
            m_word     <= word_t(sum64(31 downto 0));
            m_lo_next  := sum64(15 downto 0);
            m_hi_next  := sum64(31 downto 16);
            m_lo       <= m_lo_next;
            m_hi       <= m_hi_next;

            -- preload MN0 for j=0 using freshly computed m
            mn_lo64 <= (others => '0'); mn_hi64 <= (others => '0');
            j_idx   <= 0;
            mul0_a  <= m_lo_next;                 mul0_b <= N_reg(0)(15 downto 0);
            mul1_a  <= m_hi_next;                 mul1_b <= N_reg(0)(15 downto 0);

          ------------------------------------------------------------
          -- MN phase: 3-cycle loop per j
          when S_MN0 =>
            tmp64   := resize(mul0_p,64) + shift_left(resize(mul1_p,64),16);
            mn_lo64 <= tmp64;
            mul0_a  <= m_lo;                      mul0_b <= N_reg(j_idx)(31 downto 16);
            mul1_a  <= m_hi;                      mul1_b <= N_reg(j_idx)(31 downto 16);

          when S_MN1 =>
            tmp64   := shift_left(resize(mul0_p,64),16) + shift_left(resize(mul1_p,64),32);
            mn_hi64 <= tmp64;

          when S_MN_ADD =>
            tmp66  := resize(mn_lo64,66) + resize(mn_hi64,66);
            sum66  := tmp66 + resize(T_core(j_idx),66) + resize(carry,66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            carry         <=         sum66(64 downto 32);

            -- preload next j's MN0 and bump j (if any)          when S_MN_ADD =>
            tmp66  := resize(mn_lo64,66) + resize(mn_hi64,66);
            sum66  := tmp66 + resize(T_core(j_idx),66) + resize(carry,66);
            T_core(j_idx) <= word_t(sum66(31 downto 0));
            carry         <=         sum66(65 downto 32);

            -- preload next j's MN0 and bump j (if any)
            if j_idx < K-1 then
              mul0_a <= m_lo;                     mul0_b <= N_reg(j_idx+1)(15 downto 0);
              mul1_a <= m_hi;                     mul1_b <= N_reg(j_idx+1)(15 downto 0);
              j_idx  <= j_idx + 1;
            end if;

          ------------------------------------------------------------
          when S_MN_FOLD_SHIFT_NEXT =>
            -- fold MN carry
            T_top <= resize(T_top, W+4) + resize(carry, W+4);
            carry <= (others => '0');

            -- shift (drop T0), bring in low W bits of wide top
            for kclr in 0 to K-2 loop
              T_core(kclr) <= T_core(kclr+1);
            end loop;
            T_core(K-1) <= word_t(T_top(W-1 downto 0));
            T_top       <= (others => '0');

            -- if more i, prepare next-i AB0 here
            if i_idx < K-1 then
              i_idx  <= i_idx + 1;
              j_idx  <= 0;
              ab_lo64 <= (others => '0'); ab_hi64 <= (others => '0');
              mul0_a <= A_reg(i_idx+1)(15 downto 0);
              mul1_a <= A_reg(i_idx+1)(31 downto 16);
              mul0_b <= B_reg(0)(15 downto 0);
              mul1_b <= B_reg(0)(15 downto 0);
            end if;

          ------------------------------------------------------------
          when S_FINAL =>
            -- ...existing final compare/subtract and pack...
            for kclr in 0 to K-1 loop
              res_vec(kclr) := T_core(kclr);
            end loop;

            -- compare res_vec vs N_reg (MSW-first)
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

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;
end rtl;