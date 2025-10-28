library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exponentiation is
  generic (
    C_block_size : integer := 256
  );
  port (
    -- input control
    valid_in  : in  std_logic;
    ready_in  : out std_logic;

    -- input data
    message   : in  std_logic_vector(C_block_size-1 downto 0); -- M
    key       : in  std_logic_vector(C_block_size-1 downto 0); -- e or d (you called it key_e_d)
    modulus   : in  std_logic_vector(C_block_size-1 downto 0); -- n

    -- precomputed montgomery constants (SW provides)
    r2_mod_n  : in  std_logic_vector(C_block_size-1 downto 0); -- R^2 mod n
    n_prime   : in  std_logic_vector(31 downto 0);             -- -n^{-1} mod 2^32

    -- output control
    ready_out : in  std_logic;
    valid_out : out std_logic;

    -- output data
    result    : out std_logic_vector(C_block_size-1 downto 0);

    -- utility
    clk       : in  std_logic;
    reset_n   : in  std_logic
  );
end exponentiation;

architecture rtl of exponentiation is
  --------------------------------------------------------------------------
  -- Constants
  --------------------------------------------------------------------------
  constant W : integer := 32;
  constant K : integer := C_block_size / W;

  --------------------------------------------------------------------------
  -- Local registers (latched inputs + accumulators)
  --------------------------------------------------------------------------
  signal M_reg, E_reg, N_reg   : std_logic_vector(C_block_size-1 downto 0);
  signal Acc_reg               : std_logic_vector(C_block_size-1 downto 0);
  signal Base_reg              : std_logic_vector(C_block_size-1 downto 0); -- optional/debug

  --------------------------------------------------------------------------
  -- MonPro shared interface (arbitrated)
  --------------------------------------------------------------------------
  signal mp_start  : std_logic;
  signal mp_busy   : std_logic;
  signal mp_done   : std_logic;
  signal mp_a      : std_logic_vector(C_block_size-1 downto 0);
  signal mp_b      : std_logic_vector(C_block_size-1 downto 0);
  signal mp_n      : std_logic_vector(C_block_size-1 downto 0);
  signal mp_r      : std_logic_vector(C_block_size-1 downto 0);

  -- PRE (precompute_table) -> MonPro
  signal prep_mp_start : std_logic;
  signal prep_mp_a     : std_logic_vector(C_block_size-1 downto 0);
  signal prep_mp_b     : std_logic_vector(C_block_size-1 downto 0);

  -- POST (postconv_micro) -> MonPro
  signal post_mp_start : std_logic;
  signal post_mp_a     : std_logic_vector(C_block_size-1 downto 0);
  signal post_mp_b     : std_logic_vector(C_block_size-1 downto 0);

  -- EXP (VLNW) -> MonPro
  signal vlnw_mp_start : std_logic;
  signal vlnw_mp_a     : std_logic_vector(C_block_size-1 downto 0);
  signal vlnw_mp_b     : std_logic_vector(C_block_size-1 downto 0);

  --------------------------------------------------------------------------
  -- Phase gating for the arbiter
  --------------------------------------------------------------------------
  signal in_pre_prep : std_logic; -- precompute_table phase
  signal in_pre_post : std_logic; -- postconv_micro phase
  signal in_exp      : std_logic; -- VLNW phase

  --------------------------------------------------------------------------
  -- VLNW sideband
  --------------------------------------------------------------------------
  signal vlnw_load : std_logic := '0';
  signal vlnw_done : std_logic := '0';
  signal vlnw_op   : std_logic_vector(1 downto 0); -- "01"=square, "10"=mul

  -- two 256-bit schedule words (tie to SW regs later)
  signal sched0, sched1 : std_logic_vector(255 downto 0) := (others=>'0');

  -- precompute table read port (VLNW outputs 4 bits; table has 8 entries -> use [2:0])
  signal tbl_raddr : std_logic_vector(3 downto 0);
  signal tbl_rdata : std_logic_vector(C_block_size-1 downto 0);

  --------------------------------------------------------------------------
  -- Precompute / Postconv control
  --------------------------------------------------------------------------
  signal start_precompute : std_logic := '0';
  signal precompute_done  : std_logic := '0';

  signal start_postconv   : std_logic := '0';
  signal postconv_done    : std_logic := '0';

  --------------------------------------------------------------------------
  -- Top-level FSM
  --------------------------------------------------------------------------
  type state_t is (
    S_IDLE, S_LATCH,
    S_PREP_START, S_PREP_WAIT,
    S_VLNW_LOAD, S_VLNW_RUN,
    S_POST_START, S_POST_WAIT,
    S_OUT
  );
  signal st, st_n : state_t := S_IDLE;

begin
  ----------------------------------------------------------------------------
  -- Ready/valid policy & result
  ----------------------------------------------------------------------------
  ready_in  <= '1' when st = S_IDLE else '0';
  valid_out <= '1' when st = S_OUT  else '0';
  result    <= Acc_reg when st = S_OUT else (others => '0');

  ----------------------------------------------------------------------------
  -- Phase gating
  ----------------------------------------------------------------------------
  in_pre_prep <= '1' when st in (S_PREP_START, S_PREP_WAIT) else '0';
  in_pre_post <= '1' when st in (S_POST_START, S_POST_WAIT) else '0';
  in_exp      <= '1' when st = S_VLNW_RUN else '0';

  ----------------------------------------------------------------------------
  -- MonPro signal arbitration (decides which block controls MonPro)
  ----------------------------------------------------------------------------
  mp_n <= N_reg; -- modulus always from N_reg

  mp_start <=
      prep_mp_start when in_pre_prep = '1' else
      post_mp_start when in_pre_post = '1' else
      vlnw_mp_start;

  mp_a <=
      prep_mp_a when in_pre_prep = '1' else
      post_mp_a when in_pre_post = '1' else
      vlnw_mp_a;

  mp_b <=
      prep_mp_b when in_pre_prep = '1' else
      post_mp_b when in_pre_post = '1' else
      vlnw_mp_b;

  ----------------------------------------------------------------------------
  -- VLNW -> MonPro command sequencer (one-cycle start when idle)
  ----------------------------------------------------------------------------
  vlnw_issue : process(clk, reset_n)
    variable fire : std_logic;
  begin
    if reset_n = '0' then
      vlnw_mp_start <= '0';
      vlnw_mp_a     <= (others=>'0');
      vlnw_mp_b     <= (others=>'0');
    elsif rising_edge(clk) then
      vlnw_mp_start <= '0';
      fire := '0';

      if in_exp = '1' and mp_busy = '0' then
        case vlnw_op is
          when "01" =>  -- square
            vlnw_mp_a <= Acc_reg;
            vlnw_mp_b <= Acc_reg;
            fire := '1';
          when "10" =>  -- multiply by table entry
            vlnw_mp_a <= Acc_reg;
            vlnw_mp_b <= tbl_rdata;
            fire := '1';
          when others =>
            null;
        end case;
      end if;

      if fire = '1' then
        vlnw_mp_start <= '1';
      end if;

      -- capture running accumulator on each completed op during EXP
      if in_exp = '1' and mp_done = '1' then
        Acc_reg <= mp_r;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- MonPro submodule
  ----------------------------------------------------------------------------
  i_monpro : entity work.monpro
    generic map ( W => W, K => K )
    port map (
      clk      => clk,
      reset_n  => reset_n,
      start    => mp_start,
      busy     => mp_busy,
      done     => mp_done,
      a        => mp_a,
      b        => mp_b,
      n        => mp_n,
      n_prime  => n_prime,
      r        => mp_r
    );

  ----------------------------------------------------------------------------
  -- Precompute table (OLD PORTS: start/done). Builds odd-powers table in Mont.
  ----------------------------------------------------------------------------
  i_precompute_tbl : entity work.precompute_table
    generic map ( W => W, K => K )
    port map(
      clk           => clk,
      reset_n       => reset_n,
      start_all     => start_precompute,
      all_done      => precompute_done,
      
      start_from_mont => start_postconv,
      from_mont_done  => postconv_done,

      base_in       => M_reg,      -- raw M (entity should convert to Mont then build table)
      modulus       => N_reg,
      n_prime       => n_prime,

      -- share MonPro (arbiter selects in PREP phase)
      monpro_start  => prep_mp_start,
      monpro_busy   => mp_busy,
      monpro_done   => mp_done,
      monpro_a      => prep_mp_a,
      monpro_b      => prep_mp_b,
      monpro_result => mp_r,

      -- table read (VLNW gives 4 bits; table implements 8 entries => use [2:0])
      tbl_raddr     => tbl_raddr(2 downto 0),
      tbl_rdata     => tbl_rdata
    );

  ----------------------------------------------------------------------------
  -- Post-conversion micro: performs MonPro(Acc, 1) at the end
  ----------------------------------------------------------------------------
  i_post : entity work.postconv_micro
    generic map ( WIDTH => C_block_size )
    port map(
      clk         => clk,
      reset_n     => reset_n,
      start       => start_postconv,
      done        => postconv_done,

      acc_in      => Acc_reg,
      one_literal => (others => '0'),  -- we'll set bit 0 inside the micro
      -- MonPro shared lines (arbiter selects in POST phase)
      monpro_busy => mp_busy,
      monpro_done => mp_done,
      monpro_start=> post_mp_start,
      monpro_a    => post_mp_a,
      monpro_b    => post_mp_b
      -- result is read as mp_r by the top; we'll latch Acc_reg on done
    );

  ----------------------------------------------------------------------------
  -- VLNW controller
  ----------------------------------------------------------------------------
  i_vlnw : entity work.vlnw_controller
    port map(
      clk                 => clk,
      reset               => reset_n,        -- your design uses active-low reset upstream
      load                => vlnw_load,      -- pulse for 1 cycle
      monpro_done         => mp_done,
      vlnw_schedule_0     => sched0,
      vlnw_schedule_1     => sched1,
      read_precompute_adr => tbl_raddr,      -- 4-bit window index (0..15). Table uses [2:0].
      done                => vlnw_done,
      monpro_op           => vlnw_op
    );

  ----------------------------------------------------------------------------
  -- Next-state logic
  ----------------------------------------------------------------------------
  ns: process(st, valid_in, precompute_done, vlnw_done, postconv_done, ready_out)
  begin
    st_n <= st;
    case st is
      when S_IDLE =>
        if valid_in = '1' then
          st_n <= S_LATCH;
        end if;

      when S_LATCH =>
        st_n <= S_PREP_START;

      when S_PREP_START =>
        st_n <= S_PREP_WAIT;

      when S_PREP_WAIT =>
        if precompute_done = '1' then
          st_n <= S_VLNW_LOAD;
        end if;

      when S_VLNW_LOAD =>
        st_n <= S_VLNW_RUN;

      when S_VLNW_RUN =>
        if vlnw_done = '1' then
          st_n <= S_POST_START;
        end if;

      when S_POST_START =>
        st_n <= S_POST_WAIT;

      when S_POST_WAIT =>
        if postconv_done = '1' then
          st_n <= S_OUT;
        end if;

      when S_OUT =>
        if ready_out = '1' then
          st_n <= S_IDLE;
        end if;

      when others =>
        st_n <= S_IDLE;
    end case;
  end process;

  ----------------------------------------------------------------------------
  -- Registers / datapath control
  ----------------------------------------------------------------------------
  -- ADD STATE TRANSITIONS HERE
  regs: process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        st               <= S_IDLE;
        M_reg            <= (others => '0');
        E_reg            <= (others => '0');
        N_reg            <= (others => '0');
        Base_reg         <= (others => '0');
        Acc_reg          <= (others => '0');

        start_precompute <= '0';
        vlnw_load        <= '0';
        start_postconv   <= '0';
      else
        st <= st_n;

        -- default: deassert one-shot strobes
        start_precompute <= '0';
        vlnw_load        <= '0';
        start_postconv   <= '0';

        case st is
          when S_IDLE =>
            null;

          when S_LATCH =>
            M_reg <= message;
            E_reg <= key;
            N_reg <= modulus;

          when S_PREP_START =>
            start_precompute <= '1';  -- let precompute_table run

          when S_PREP_WAIT =>
            null;

          when S_VLNW_LOAD =>
            vlnw_load <= '1';  -- load VLNW schedules

          when S_VLNW_RUN =>
            null;              -- Acc_reg captured in vlnw_issue on mp_done

          when S_POST_START =>
            start_postconv <= '1';

          when S_POST_WAIT =>
            -- when postconv finishes, the mp_r holds the de-Mont result
            if postconv_done = '1' then
              Acc_reg <= mp_r;
            end if;

          when S_OUT =>
            null;

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

end rtl;
