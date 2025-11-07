library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exponentiation is
    generic (
        C_block_size : integer := 256 -- datapath width
    );
    port (
        -- Input control
        valid_in  : in std_logic;
        ready_in  : out std_logic;
        
        -- Input data
        message   : in std_logic_vector(C_block_size-1 downto 0); -- M
        key       : in std_logic_vector(C_block_size-1 downto 0); -- e or d
        modulus   : in std_logic_vector(C_block_size-1 downto 0); -- n
        
        -- Precomputed Montgomery constants
        r2_mod_n  : in std_logic_vector(C_block_size-1 downto 0);
        n_prime   : in std_logic_vector(31 downto 0);
        
        -- Output control
        valid_out : out std_logic;
        ready_out : in std_logic;
        
        -- Output data
        result    : out std_logic_vector(C_block_size-1 downto 0);
        
        -- Utilities
        clk       : in std_logic;
        reset_n   : in std_logic
    );
end exponentiation;

architecture rtl of exponentiation is

    -----------------------------------------------------------------------------
    -- Constants / parameters
    -----------------------------------------------------------------------------
    constant W : integer := 32;                -- word size fed to monpro
    constant K : integer := C_block_size / W;  -- number of words
    
    -----------------------------------------------------------------------------  
    -- VLNW operation codes (for vlnw_op)  
    -----------------------------------------------------------------------------  
    constant OP_WAIT : std_logic_vector(1 downto 0) := "00";  -- no operation  
    constant OP_SQR  : std_logic_vector(1 downto 0) := "01";  -- square (Acc*Acc)  
    constant OP_MUL  : std_logic_vector(1 downto 0) := "10";  -- multiply (Acc*Table)
    
    constant SCHED0_CONST : std_logic_vector(255 downto 0)
    := x"0420800000000000000000000000000000000000000000000000000000000000";

    constant SCHED1_CONST : std_logic_vector(255 downto 0)
    := (others => '0');
    
    -----------------------------------------------------------------------------
    -- Latched inputs + main accumulators (Montgomery domain)
    -----------------------------------------------------------------------------
    signal M_reg, E_reg, N_reg : std_logic_vector(C_block_size-1 downto 0);
    signal Acc_reg, Acc_next   : std_logic_vector(C_block_size-1 downto 0);
    
    -- INIT-ACC (one_bar) → MonPro
    signal in_init             : std_logic;  -- owns MonPro while seeding Acc
    signal init_mp_start       : std_logic := '0';
    signal init_mp_a           : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
    signal init_mp_b           : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
    
    -----------------------------------------------------------------------------
    -- Shared MonPro interface + arbiter input busses
    -----------------------------------------------------------------------------
    signal mp_start      : std_logic;
    signal mp_busy       : std_logic;
    signal mp_done       : std_logic;
    signal mp_a          : std_logic_vector(C_block_size-1 downto 0);
    signal mp_b          : std_logic_vector(C_block_size-1 downto 0);
    signal mp_n          : std_logic_vector(C_block_size-1 downto 0);
    signal mp_r          : std_logic_vector(C_block_size-1 downto 0);
    signal mp_done_q     : std_logic := '0';
    signal mp_r_q        : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
    
    signal mp_done_d     : std_logic := '0';  -- 1-cycle delay of mp_done
    signal mp_done_rise  : std_logic := '0';  -- single-cycle pulse on rising edge
    
    -- who launched the current MonPro op
    -- 00 = NONE, 01 = INIT, 10 = EXP, 11 = POST (you can treat PREP as INIT/NONE)
    signal mp_owner      : std_logic_vector(1 downto 0) := "00";
    signal owner_exp     : std_logic := '0';  -- convenience
  
    -- PREP (precompute_table) → MonPro
    signal prep_mp_start : std_logic;
    signal prep_mp_a     : std_logic_vector(C_block_size-1 downto 0);
    signal prep_mp_b     : std_logic_vector(C_block_size-1 downto 0);
  
    -- POST (postconv_micro) → MonPro
    signal post_mp_start : std_logic;
    signal post_mp_a     : std_logic_vector(C_block_size-1 downto 0);
    signal post_mp_b     : std_logic_vector(C_block_size-1 downto 0);
    
    -- EXP (VLNW) → MonPro
    signal vlnw_mp_start : std_logic;
    signal vlnw_mp_a     : std_logic_vector(C_block_size-1 downto 0);
    signal vlnw_mp_b     : std_logic_vector(C_block_size-1 downto 0);

    -----------------------------------------------------------------------------
    -- Phase gating based on state (which block currently owns MonPro)
    -----------------------------------------------------------------------------
    signal in_prep : std_logic; -- PREP owns MonPro
    signal in_post : std_logic; -- POST owns MonPro
    signal in_exp  : std_logic; -- EXP owns MonPro
  
    -----------------------------------------------------------------------------
    -- Strobes for sub-blocks (on-entry pulses)
    -----------------------------------------------------------------------------
    signal start_precompute : std_logic := '0';
    signal precompute_done  : std_logic := '0';

    signal start_postconv   : std_logic := '0';
    signal postconv_done    : std_logic := '0';
  
    signal one_lit          : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
    
    -----------------------------------------------------------------------------
    -- VLNW sideband (schedule + op + table read)
    -----------------------------------------------------------------------------
    signal vlnw_load      : std_logic := '0';             -- pulse on-entry to VLNW
    signal vlnw_done      : std_logic := '0';
    signal vlnw_op        : std_logic_vector(1 downto 0); -- "01"=square, "10"=mul
    signal op_at_start    : std_logic_vector(1 downto 0) := "00";

    -- Two 256-bit schedule words from SW
    signal sched0, sched1 : std_logic_vector(255 downto 0) := (others => '0');

    -- Precompute table read port (VLNW issues 4-bit address; table uses [2:0])
    signal tbl_raddr      : std_logic_vector(3 downto 0);
    signal tbl_rdata      : std_logic_vector(C_block_size-1 downto 0);
    
    signal exp_armed : std_logic := '0';
  
    -----------------------------------------------------------------------------
    -- FSM: single-process with on-entry strobes
    -----------------------------------------------------------------------------
    type state_t is (
      S_IDLE,     -- wait for valid_in
      S_LATCH,    -- latch M/E/N
      S_PREP,     -- precompute odd powers (on-entry pulse → run)
      S_INIT_ACC, 
      S_WAIT_ACC,
      S_VLNW,     -- run square/multiply schedule until done
      S_POST,     -- final MonPro(Acc,1) to de-Montgomery (on-entry pulse)
      S_OUT       -- hold result until ready_out
    );
    signal st, st_prev : state_t := S_IDLE;
  
    -- on-entry helper: '1' exactly in the cycle we *enter* the current state
    signal on_entry : std_logic;
    
begin
    -----------------------------------------------------------------------------
    -- Ready/valid & result
    -----------------------------------------------------------------------------
    ready_in  <= '1' when st = S_IDLE else '0';
    valid_out <= '1' when st = S_OUT  else '0';
    result    <= Acc_reg when st = S_OUT else (others => '0');
    
    -----------------------------------------------------------------------------
    -- Phase gating from state (who owns the MonPro this cycle)
    -----------------------------------------------------------------------------
    in_init <= '1' when (st = S_INIT_ACC or st = S_WAIT_ACC) else '0';
    in_prep <= '1' when st = S_PREP else '0';
    in_post <= '1' when st = S_POST else '0';
    in_exp  <= '1' when st = S_VLNW else '0';
  
    
    sched0 <= SCHED0_CONST;
    sched1 <= SCHED1_CONST;
    
    -----------------------------------------------------------------------------
    -- MonPro arbitration (mux producer → shared MonPro)
    -----------------------------------------------------------------------------
    mp_n <= N_reg;

    mp_start <=
      init_mp_start when in_init = '1' else
      prep_mp_start when in_prep = '1' else
      post_mp_start when in_post = '1' else
      vlnw_mp_start;

    mp_a <=
      init_mp_a     when in_init = '1' else
      prep_mp_a     when in_prep = '1' else
      post_mp_a     when in_post = '1' else
      vlnw_mp_a;

    mp_b <=
      init_mp_b     when in_init = '1' else
      prep_mp_b     when in_prep = '1' else
      post_mp_b     when in_post = '1' else
      vlnw_mp_b;
    
    -----------------------------------------------------------------------------
    -- VLNW → MonPro issuer
    --  - Starts next op when in EXP phase and MonPro is idle.
    --  - Captures mp_r into Acc_reg upon each completed op.
    -----------------------------------------------------------------------------
    vlnw_issue : process(clk)
      variable fire : std_logic;
    begin
      if rising_edge(clk) then
        if reset_n = '0' then
          vlnw_mp_start <= '0';
          vlnw_mp_a     <= (others => '0');
          vlnw_mp_b     <= (others => '0');
        else
          vlnw_mp_start <= '0';
          fire := '0';

          if in_exp = '1' and mp_busy = '0' then
            case vlnw_op is
              when OP_SQR =>
                vlnw_mp_a <= Acc_reg;
                vlnw_mp_b <= Acc_reg;
                fire      := '1';
              when OP_MUL =>
                vlnw_mp_a <= Acc_reg;
                vlnw_mp_b <= tbl_rdata;
                fire      := '1';
              when others =>
                null;
            end case;
          end if;

          if fire = '1' then
            vlnw_mp_start <= '1';
            op_at_start   <= vlnw_op;   -- remember what we launched
          end if;

        end if;
      end if;
    end process;
    
    -----------------------------------------------------------------------------
    -- MonPro submodule (high-radix Montgomery multiply)
    -----------------------------------------------------------------------------
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
      
      process(clk)
      begin
        if rising_edge(clk) then
          if reset_n = '0' then
            mp_done_d    <= '0';
            mp_done_rise <= '0';
            mp_r_q       <= (others => '0');
          else
            mp_done_d    <= mp_done;
            mp_done_rise <= '1' when (mp_done = '1' and mp_done_d = '0') else '0';
    
            if (mp_done = '1' and mp_done_d = '0') then  -- rising edge only
              mp_r_q <= mp_r;
            end if;
          end if;
        end if;
      end process;
      
      process(clk)
      begin
        if rising_edge(clk) then
          if reset_n = '0' then
            mp_owner <= "00";
          else
            -- set owner on the same cycle we pulse mp_start
            if init_mp_start = '1' then
              mp_owner <= "01";      -- INIT (seed 1̄)
            elsif vlnw_mp_start = '1' then
              mp_owner <= "10";      -- EXP (VLNW)
            elsif post_mp_start = '1' then
              mp_owner <= "11";      -- POST (de-Mont)
            elsif mp_start = '0' and mp_done_rise = '1' then
              -- clear owner after completion (optional but clean)
              mp_owner <= "00";
            end if;
          end if;
        end if;
      end process;


      
    -----------------------------------------------------------------------------
    -- Precompute table
    --  - Builds odd powers of base in Montgomery domain (e.g., B, B^3, B^5,...).
    --  - Shares MonPro through the arbiter during S_PREP.
    --  - Exposes a read port for VLNW (table entry selection).
    -----------------------------------------------------------------------------
    i_precompute_tbl : entity work.precompute_table
    generic map ( W => W, K => K )
    port map(
      clk             => clk,
      reset_n         => reset_n,

      start_all       => start_precompute,
      all_done        => precompute_done,

      base_in         => M_reg,
      modulus         => N_reg,
      n_prime         => n_prime,
      r2_mod_n        => r2_mod_n,

      -- Share MonPro in PREP phase
      monpro_start    => prep_mp_start,
      monpro_busy     => mp_busy,
      monpro_done     => mp_done,
      monpro_a        => prep_mp_a,
      monpro_b        => prep_mp_b,
      monpro_result   => mp_r,

      tbl_raddr       => tbl_raddr(2 downto 0),
      tbl_rdata       => tbl_rdata,

      acc_in          => Acc_reg,
      acc_out         => open
    );


      
    -----------------------------------------------------------------------------
    -- Post-conversion micro
    --  - Performs MonPro(Acc, 1) to convert from Montgomery back to standard domain.
    --  - Triggered by an on-entry pulse to S_POST.
    -----------------------------------------------------------------------------
    i_post : entity work.postconv_micro
      generic map ( WIDTH => C_block_size )
      port map(
        clk           => clk,
        reset_n       => reset_n,
        start         => start_postconv, -- pulse on entry to S_POST
        done          => postconv_done,

        acc_in        => Acc_reg,
        one_literal   => one_lit,

        -- Shared MonPro lines during S_POST
        monpro_busy   => mp_busy,
        monpro_done   => mp_done,
        monpro_start  => post_mp_start,
        monpro_a      => post_mp_a,
        monpro_b      => post_mp_b
      );
      
    -----------------------------------------------------------------------------
    -- VLNW controller
    --  - Generates the square/multiply sequence and table read addresses.
    --  - Asserts 'done' when the schedule is complete.
    -----------------------------------------------------------------------------
    i_vlnw : entity work.vlnw_controller
      port map(
        clk                 => clk,
        reset               => reset_n,      -- active-low upstream (keep consistent)
        load                => vlnw_load,    -- one-cycle pulse on entry to S_VLNW
        monpro_done         => mp_done,
        vlnw_schedule_0     => sched0,
        vlnw_schedule_1     => sched1,
        read_precompute_adr => tbl_raddr,    -- 4-bit window (0..15). Table uses [2:0].
        done                => vlnw_done,
        monpro_op           => vlnw_op
      );
    
    -----------------------------------------------------------------------------
    -- FSM (single-process): state, on-entry detection, strobes, and datapath
    -----------------------------------------------------------------------------
    fsm: process(clk)
      variable st_n : state_t;
    begin
      if rising_edge(clk) then
        -- Async reset (active-low)
        if reset_n = '0' then
          st               <= S_IDLE;
          st_prev          <= S_IDLE;

          M_reg            <= (others => '0');
          E_reg            <= (others => '0');
          N_reg            <= (others => '0');
          Acc_reg          <= (others => '0');
          Acc_next <= (others => '0');

          start_precompute <= '0';
          vlnw_load        <= '0';
          start_postconv   <= '0';
        
          init_mp_start <= '0';
          init_mp_a     <= (others => '0');
          init_mp_b     <= (others => '0');
        
          one_lit <= (others => '0');
          one_lit(0) <= '1';
 
       else
          ----------------------------------------------------------------------
          -- Default: deassert one-shot strobes each cycle
          ----------------------------------------------------------------------
          start_precompute <= '0';
          vlnw_load        <= '0';
          start_postconv   <= '0';
          init_mp_start    <= '0'; -- one-cycle pulse when we kick MonPro

          st_n := st;              -- default hold state
          Acc_next <= Acc_reg;
          
      case st is
      --------------------------------------------------------------------
      when S_IDLE =>
        -- Accept a new transaction
        if valid_in = '1' then
          st_n := S_LATCH;
        end if;
      
      --------------------------------------------------------------------
      when S_LATCH =>
        -- Latch inputs (register crossing)
        M_reg <= message;
        E_reg <= key;
        N_reg <= modulus;
        -- Optionally: Base_reg <= message;
        st_n  := S_INIT_ACC;

      --------------------------------------------------------------------
      when S_INIT_ACC =>
        -- On entry: prepare MonPro(1, R^2 mod n)  → produces 1 in Montgomery domain (1̄)
        if on_entry = '1' then
          init_mp_a        <= (others => '0');  -- literal 1
          init_mp_a(0)     <= '1';
          init_mp_b        <= r2_mod_n;         -- R^2 mod n
        end if;

        -- Fire start exactly once when engine is idle
        if on_entry = '1' and mp_busy = '0' then
          init_mp_start    <= '1';              -- one-cycle pulse
        end if;

        if (mp_done_rise = '1') and (mp_owner = "01") then
          Acc_next <= mp_r_q;
          st_n     := S_PREP;
        else
          st_n     := S_WAIT_ACC;
        end if;

      --------------------------------------------------------------------
      when S_WAIT_ACC =>
        if (mp_done_rise = '1') and (mp_owner = "01") then
          Acc_next <= mp_r_q;
          st_n     := S_PREP;
        end if;

      --------------------------------------------------------------------
      when S_PREP =>
        -- On-entry: kick off the precompute table builder
        if on_entry = '1' then
          start_precompute <= '1';              -- one-cycle pulse
        end if;

        -- Wait for precompute to complete
        if precompute_done = '1' then
          st_n := S_VLNW;
        end if;

      --------------------------------------------------------------------
      when S_VLNW =>
      -- on entry: load schedule, disarm for exactly one cycle
        if on_entry = '1' then
          vlnw_load <= '1';    -- 1-cycle pulse into controller
          exp_armed <= '0';    -- disarm this cycle
        else
          exp_armed <= '1';    -- arm from the next cycle onward
        end if;

        if (mp_done_rise = '1') and (mp_owner = "10") and
        (op_at_start = OP_SQR or op_at_start = OP_MUL) then
          Acc_next <= mp_r_q;
        end if;

       -- done with schedule?
       if vlnw_done = '1' then
         st_n := S_POST;
       end if;

      --------------------------------------------------------------------
      when S_POST =>
        if on_entry = '1' then
          start_postconv <= '1';
        end if;
        if (mp_done_rise = '1') and (mp_owner = "11") then
          Acc_next <= mp_r_q;
          st_n     := S_OUT;
        end if;

      --------------------------------------------------------------------
      when S_OUT =>
        -- Present result until downstream is ready
        if ready_out = '1' then
          st_n := S_IDLE;
        end if;

      when others =>
        st_n := S_IDLE;
    end case;

    -- Update state / previous state for on-entry detection
    st_prev <= st;
    st      <= st_n;
    
    --Commit accumulator for this cycle
    Acc_reg <= Acc_next;

    end if; -- reset
    end if; -- rising_edge
  end process;

  -- on-entry = 1 exactly when we just entered st (st changed this cycle)
  on_entry <= '1' when st /= st_prev else '0';

end rtl;
    
    
    
    
    
    
    
    
  
  
  
  
  
  