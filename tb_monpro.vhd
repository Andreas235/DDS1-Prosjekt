-- tb_monpro.vhd  (CIOS golden, strict VHDL-93/2002)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity monpro_tb is
end entity;

architecture tb of monpro_tb is
  -- Match DUT generics
  constant W  : integer := 32;
  constant K  : integer := 8;
  constant KW : integer := K*W;

  signal clk     : std_logic := '0';
  signal reset_n : std_logic := '0';

  signal start   : std_logic := '0';
  signal busy    : std_logic;
  signal done    : std_logic;

  signal a, b, n : std_logic_vector(KW-1 downto 0) := (others => '0');
  signal n_prime : std_logic_vector(31 downto 0)    := (others => '0');
  signal r       : std_logic_vector(KW-1 downto 0);

  constant Tclk  : time := 10 ns;

  -- Handy types
  subtype word_t is unsigned(W-1 downto 0);
  type    vec_t  is array (0 to K-1) of word_t;
  type    acc_t  is array (0 to K)   of word_t;   -- K+1 words

  --------------------------------------------------------------------
  -- Helpers (strict VHDL-93)
  --------------------------------------------------------------------
  function unpack(slv : std_logic_vector(KW-1 downto 0)) return vec_t is
    variable v : vec_t;
  begin
    for i in 0 to K-1 loop
      v(i) := unsigned(slv((i+1)*W-1 downto i*W));
    end loop;
    return v;
  end;

  function pack(v : vec_t) return std_logic_vector is
    variable slv : std_logic_vector(KW-1 downto 0);
  begin
    for i in 0 to K-1 loop
      slv((i+1)*W-1 downto i*W) := std_logic_vector(v(i));
    end loop;
    return slv;
  end;

  -- Newton inverse mod 2^32 (n0 odd): x <- x*(2 - n0*x) mod 2^32, start x=1.
  function inv32_mod2p32(n0 : unsigned(31 downto 0)) return unsigned is
    variable x      : unsigned(31 downto 0) := (others => '0');
    variable two    : unsigned(31 downto 0) := to_unsigned(2,32);
    variable tmp64  : unsigned(63 downto 0);
    variable nx32   : unsigned(31 downto 0);
    variable step   : unsigned(31 downto 0);
  begin
    x(0) := '1';
    for i in 0 to 4 loop
      tmp64 := unsigned(n0) * x;       -- 32x32 -> 64
      nx32  := tmp64(31 downto 0);
      step  := two - nx32;
      tmp64 := x * step;                -- 32x32 -> 64
      x     := tmp64(31 downto 0);
    end loop;
    return x;
  end;

  -- MSW-first compare: TRUE iff X >= Y
    function ge_vec(x,y: vec_t) return boolean is
      variable k : integer := K-1;
    begin
      -- walk from MSW down to LSW
      while k >= 0 loop
        if x(k) > y(k) then
          return true;
        elsif x(k) < y(k) then
          return false;
        end if;
        if k = 0 then
          exit;  -- equal
        else
          k := k - 1;
        end if;
      end loop;
      return true; -- equal
    end;

  -- Return X - Y (assumes X>=Y), word-serial with borrow
  function sub_vec_fn(x_in, y_in : vec_t) return vec_t is
    variable x      : vec_t := x_in;
    variable y      : vec_t := y_in;
    variable outv   : vec_t;
    variable borrow : unsigned(0 downto 0) := (others => '0');
    variable wext, nextw, pow2W, res_w1 : unsigned(W downto 0);
  begin
    pow2W := (others => '0'); pow2W(W) := '1';
    for i in 0 to K-1 loop
      wext  := resize(x(i), W+1);
      nextw := resize(y(i), W+1) + resize(borrow, W+1);
      if wext < nextw then
        res_w1  := (wext + pow2W) - nextw;
        outv(i) := word_t(res_w1(W-1 downto 0));
        borrow(0) := '1';
      else
        res_w1  := wext - nextw;
        outv(i) := word_t(res_w1(W-1 downto 0));
        borrow(0) := '0';
      end if;
    end loop;
    return outv;
  end;

  --------------------------------------------------------------------
  -- CIOS golden model (word-radix, W=32, K limbs)
  -- m := low32(T[0] * n'); then inner j-loop accumulates a*b + m*n + carry
  --------------------------------------------------------------------
    -- CIOS golden model (W=32, K limbs)
    -- m := low32(T[0] * n'); inner loop accumulates a*b + m*n + carry
    function monpro_ref(a_slv, b_slv, n_slv : std_logic_vector;
                        nprime32 : std_logic_vector(31 downto 0))
             return std_logic_vector is
      -- NOTE: uses architecture-level:
      --   subtype word_t; type vec_t; type acc_t; functions unpack/pack
      variable A, B, N : vec_t;
      variable np      : word_t;
      variable T       : acc_t;                      -- K+1 words
      variable i, j    : integer;
      variable carry   : word_t;
      variable prod64  : unsigned(63 downto 0);
      variable sum64   : unsigned(63 downto 0);
      variable tmp64   : unsigned(63 downto 0);
      variable m       : word_t;
      variable resv    : vec_t;
      variable res_slv : std_logic_vector(KW-1 downto 0);
    
      -- borrow/subtract vars (declared up-front: VHDL-93 friendly)
      variable borrow : unsigned(0 downto 0);
      variable wext, nextw, pow2W, res_w1 : unsigned(W downto 0);
    begin
      A  := unpack(a_slv);
      B  := unpack(b_slv);
      N  := unpack(n_slv);
      np := unsigned(nprime32);
    
      -- T := 0
      for i in 0 to K loop
        T(i) := (others=>'0');
      end loop;
    
      -- CIOS outer loop
      for i in 0 to K-1 loop
        -- m = low32(T[0] * n')
        tmp64 := unsigned(T(0)) * np;      -- 32×32 -> 64
        m     := word_t(tmp64(31 downto 0));
    
        -- T := T + A[i]*B + m*N (word-serial)
        carry := (others => '0');
        for j in 0 to K-1 loop
          prod64 := unsigned(A(i)) * unsigned(B(j));           -- a*b
          sum64  := prod64;
          tmp64  := unsigned(m) * unsigned(N(j));              -- m*n
          sum64  := sum64 + tmp64;
          sum64  := sum64 + resize(T(j),64) + resize(carry,64);
          T(j)   := word_t(sum64(31 downto 0));
          carry  := word_t(sum64(63 downto 32));
        end loop;
        T(K) := word_t(unsigned(T(K)) + unsigned(carry));
    
        -- logical right shift by one limb (drop T[0])
        for j in 0 to K-1 loop
          T(j) := T(j+1);
        end loop;
        T(K) := (others => '0');
      end loop;
    
      -- Collect result
      for j in 0 to K-1 loop
        resv(j) := T(j);
      end loop;
      res_slv := pack(resv);
    
      -- Conditional subtract if resv >= N (vector-wide compare via temp)
      if unsigned(res_slv) >= unsigned(n_slv) then
        borrow := (others => '0');
        pow2W  := (others => '0'); pow2W(W) := '1';
        for j in 0 to K-1 loop
          wext  := resize(resv(j), W+1);
          nextw := resize(N(j),   W+1) + resize(borrow, W+1);
          if wext < nextw then
            res_w1    := (wext + pow2W) - nextw;
            resv(j)   := word_t(res_w1(W-1 downto 0));
            borrow(0) := '1';
          else
            res_w1    := wext - nextw;
            resv(j)   := word_t(res_w1(W-1 downto 0));
            borrow(0) := '0';
          end if;
        end loop;
        res_slv := pack(resv);
      end if;
    
      return res_slv;
    end;


  -- xorshift32 PRNG
  function xorshift32(seed_in : unsigned(31 downto 0)) return unsigned is
    variable x : unsigned(31 downto 0) := seed_in;
  begin
    x := x xor (x sll 13);
    x := x xor (x srl 17);
    x := x xor (x sll 5);
    return x;
  end;

  -- Random-ish < n (reduce once if >= n)
  function rand_lt_n(seed_in : unsigned(31 downto 0); n_slv : std_logic_vector)
           return std_logic_vector is
    variable seed : unsigned(31 downto 0) := seed_in;
    variable outv : vec_t;
    variable nvec : vec_t;
    variable need_sub : boolean;
  begin
    nvec := unpack(n_slv);
    for i in 0 to K-1 loop
      seed   := xorshift32(seed);
      outv(i):= seed;
    end loop;
    need_sub := ge_vec(outv, nvec);
    if need_sub then
      outv := sub_vec_fn(outv, nvec);
    end if;
    return pack(outv);
  end;

begin
  --------------------------------------------------------------------
  -- Clock
  --------------------------------------------------------------------
  clk <= not clk after Tclk/2;

  --------------------------------------------------------------------
  -- DUT under test
  --------------------------------------------------------------------
  uut: entity work.monpro
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
  -- Stimulus (single process, drives signals directly)
  --------------------------------------------------------------------
  stim: process
    variable pass_count : integer := 0;
    variable fail_count : integer := 0;

    variable N_const    : std_logic_vector(KW-1 downto 0);
    variable A1, B1     : std_logic_vector(KW-1 downto 0);

    variable n0         : unsigned(31 downto 0);
    variable np         : unsigned(31 downto 0);
    variable n_fixed    : std_logic_vector(KW-1 downto 0);
    variable gold       : std_logic_vector(KW-1 downto 0);

    variable seed       : unsigned(31 downto 0) := x"12345678";
    variable tcase      : integer;
  begin
    -- reset
    reset_n <= '0';
    wait for 10*Tclk;
    reset_n <= '1';
    wait for 5*Tclk;

    -- A simple odd 256-bit modulus (LSW odd)
    N_const := (others => '0');
    N_const(31 downto 0)    := x"F0000001";
    N_const(63 downto 32)   := x"00000007";
    N_const(95 downto 64)   := x"00000013";
    N_const(127 downto 96)  := x"0000001D";
    N_const(159 downto 128) := x"00000009";
    N_const(191 downto 160) := x"00000003";
    N_const(223 downto 192) := x"00000001";
    N_const(255 downto 224) := x"00000001";

    -- Fix n to be odd in LSW and compute n'
    n0 := unsigned(N_const(31 downto 0));
    if n0(0) = '0' then
      n0 := n0 + 1;  -- ensure odd
    end if;
    n_fixed := N_const(KW-1 downto 32) & std_logic_vector(n0);
    np := (not inv32_mod2p32(n0)) + 1;

    ----------------------------------------------------------------
    -- TEST 0: Zero * Zero
    ----------------------------------------------------------------
    A1 := (others => '0'); B1 := (others => '0');

    a       <= A1;
    b       <= B1;
    n       <= n_fixed;
    n_prime <= std_logic_vector(np);
    gold    := monpro_ref(A1, B1, n_fixed, std_logic_vector(np));

    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    loop
      wait until rising_edge(clk);
      exit when done='1';
    end loop;

    if r = gold then
      report "PASS test 0";
      pass_count := pass_count + 1;
    else
      report "FAIL test 0" severity error;
      fail_count := fail_count + 1;
    end if;

    wait for 3*Tclk;

    ----------------------------------------------------------------
    -- TEST 1: Zero * One
    ----------------------------------------------------------------
    A1 := (others => '0'); B1 := (others => '1');

    a       <= A1;
    b       <= B1;
    n_prime <= std_logic_vector(np);
    gold    := monpro_ref(A1, B1, n_fixed, std_logic_vector(np));

    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    loop
      wait until rising_edge(clk);
      exit when done='1';
    end loop;

    if r = gold then
      report "PASS test 1";
      pass_count := pass_count + 1;
    else
      report "FAIL test 1" severity error;
      fail_count := fail_count + 1;
    end if;

    wait for 3*Tclk;

    ----------------------------------------------------------------
    -- TEST 2: AllOnes * AllOnes
    ----------------------------------------------------------------
    A1 := (others => '1'); B1 := (others => '1');

    a       <= A1;
    b       <= B1;
    n_prime <= std_logic_vector(np);
    gold    := monpro_ref(A1, B1, n_fixed, std_logic_vector(np));

    wait until rising_edge(clk);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    loop
      wait until rising_edge(clk);
      exit when done='1';
    end loop;

    if r = gold then
      report "PASS test 2";
      pass_count := pass_count + 1;
    else
      report "FAIL test 2" severity error;
      fail_count := fail_count + 1;
    end if;

    wait for 3*Tclk;

    ----------------------------------------------------------------
    -- TESTS 3..10: Random-ish (< n)
    ----------------------------------------------------------------
    for tcase in 3 to 10 loop
      A1 := rand_lt_n(seed, n_fixed); seed := xorshift32(seed);
      B1 := rand_lt_n(seed, n_fixed); seed := xorshift32(seed);

      a       <= A1;
      b       <= B1;
      n_prime <= std_logic_vector(np);
      gold    := monpro_ref(A1, B1, n_fixed, std_logic_vector(np));

      wait until rising_edge(clk);
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
      loop
        wait until rising_edge(clk);
        exit when done='1';
      end loop;

      if r = gold then
        report "PASS test (random)";
        pass_count := pass_count + 1;
      else
        report "FAIL test (random)" severity error;
        fail_count := fail_count + 1;
      end if;

      wait for 3*Tclk;
    end loop;

    ----------------------------------------------------------------
    -- Summary
    ----------------------------------------------------------------
    if fail_count = 0 then
      report "ALL TESTS PASSED";
    else
      assert false report "Some tests FAILED" severity failure;
    end if;

    wait;
  end process;

end architecture;






