library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exponentiation is
  generic (
    C_block_size : integer := 256;
    DEBUG        : boolean := false
  );
  port (
    -- input control
    valid_in  : in  std_logic;
    ready_in  : out std_logic;
    last_in   : in  std_logic;  -- NEW

    -- input data
    message   : in  std_logic_vector(C_block_size-1 downto 0);
    key       : in  std_logic_vector(C_block_size-1 downto 0);
    r2_mod_n  : in  std_logic_vector(C_block_size-1 downto 0);
    n_prime   : in  std_logic_vector(31 downto 0);

    -- VLNW schedules provided by software
    vlnw_schedule_0 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_1 : in  std_logic_vector(255 downto 0);
    vlnw_schedule_2 : in  std_logic_vector(255 downto 0);

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
  
  constant LANES : integer := 5;

  type vec256_t   is array (0 to LANES-1) of std_logic_vector(C_block_size-1 downto 0);
  type table_t    is array (0 to 7) of std_logic_vector(C_block_size-1 downto 0);
  type table5_t   is array (0 to LANES-1) of table_t;

  component monpro
    --generic (
      --W : integer := 32; -- word size
      --K : integer := 8   -- number of limbs (256/W)
    --);
    port (
      clk       : in  std_logic;
      reset_n     : in  std_logic;
      start     : in  std_logic;
      busy      : out std_logic;
      done      : out std_logic;
      A         : in  std_logic_vector(255 downto 0);
      B         : in  std_logic_vector(255 downto 0);
      n         : in  std_logic_vector(255 downto 0);
      n_prime   : in  std_logic_vector(31 downto 0);
      r         : out std_logic_vector(255 downto 0)
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
      vlnw_schedule_2     : in  std_logic_vector(255 downto 0);
      read_precompute_adr : out std_logic_vector(3 downto 0);
      done                : out std_logic;
      monpro_op           : out std_logic_vector(1 downto 0)  -- "01"=square, "10"=multiply
    );
  end component;

  

  type state_t is (
    S_IDLE,
    --S_LATCH,
    S_TO_MONT_A, S_WAIT_TO_MONT_A,
    S_TO_MONT_ONE, S_WAIT_TO_MONT_ONE,
    S_A2, S_WAIT_A2,
    S_WAIT_A3,
    S_PRECOMP_GEN,
    S_GEN_ODD, S_WAIT_ODD,
    S_LOAD_VLNW,
    S_VLNW_ARM,
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
  
  -- One start, then 5 inputs (one per cycle), then capture 5 outputs
  type mpb_state_t is (MPB_IDLE, MPB_KICK, MPB_ISSUE, MPB_WAIT_DONE, MPB_GRAB);
  signal mpb_st       : mpb_state_t := MPB_IDLE;
  signal issue_idx    : integer range 0 to LANES := 0;  -- 0..4
  signal grab_idx     : integer range 0 to LANES := 0;  -- 0..4
  signal mp_done_z    : std_logic := '0';               -- edge detect
  
  -- short-batch control
  signal cur_lanes    : integer range 1 to LANES := LANES; -- 1..5 active lanes this batch
  signal tail_pending : std_logic := '0';                   -- saw a 'last_in' while filling
 

  -- One operation's per-lane operands/result buffers
  signal batchA, batchB, batchR : vec256_t := (others => (others => '0'));

  -- "Operation complete for all 5" pulse
  signal mp_batch_done : std_logic := '0';
  -- add alongside your signals
  signal mp_batch_done_d : std_logic := '0';

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

  signal obs_sq    : integer := 0;
  signal obs_mul   : integer := 0;
  signal obs_total : integer := 0;  -- alle MonPro-kall (inkl. precompute + to/from Mont)
  
  -- declarations
  signal message_r  : std_logic_vector(C_block_size-1 downto 0);
  signal key_r      : std_logic_vector(C_block_size-1 downto 0);
  signal r2_mod_n_r : std_logic_vector(C_block_size-1 downto 0);
  signal n_prime_r  : std_logic_vector(31 downto 0);
  signal modulus_r  : std_logic_vector(C_block_size-1 downto 0);
  -- Per-lane contexts
  signal msg      : vec256_t := (others => (others => '0'));
  signal acc5     : vec256_t := (others => (others => '0'));  -- accumulator (Montgomery domain)
  signal oneM5    : vec256_t := (others => (others => '0'));
  signal A2_5     : vec256_t := (others => (others => '0'));
  signal tbl5     : table5_t;                                  -- per lane, odd powers A^1..A^15 (Mont)
  
  -- add latched schedules
  signal vlnw_schedule_0_r : std_logic_vector(255 downto 0);
  signal vlnw_schedule_1_r : std_logic_vector(255 downto 0);
  signal vlnw_schedule_2_r : std_logic_vector(255 downto 0);
  
  -- to take in 5 messages
  signal in_count    : integer range 0 to LANES := 0;
  signal out_count   : integer range 0 to LANES := 0;
  signal batch_ready : std_logic := '0';
  
  

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
    --generic map ( W => W, K => K )
    port map (
      clk       => clk,
      reset_n     => reset_n,
      start     => mp_start,
      busy      => mp_busy,
      done      => mp_done,
      a         => a_in,
      b         => b_in,
      n         => n_reg,
      n_prime   => n_prime_r,     -- CHANGED: was n_prime
      r         => mp_r
    );

  u_vlnw : vlnw_controller
    port map (
      clk                 => clk,
      reset               => not reset_n,
      load                => vlnw_load,
      monpro_done         => mp_batch_done,
      read_precompute_adr => vlnw_addr,
      vlnw_schedule_0     => vlnw_schedule_0_r,
      vlnw_schedule_1     => vlnw_schedule_1_r,
      vlnw_schedule_2     => vlnw_schedule_2_r,
      done                => vlnw_done,
      monpro_op           => vlnw_op
    );

  process(clk, reset_n)
    variable i  : integer;
    variable idx: integer;
    -- NEW: local pulse variable visible to both MPB and FSM in this cycle
    variable v_mp_batch_done : std_logic := '0';
    
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
      cur_lanes    <= LANES;
      tail_pending <= '0';
       
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
      obs_sq      <= 0;
      obs_mul     <= 0;
      obs_total   <= 0;
      
      -- NEW: clear latched inputs
      message_r     <= (others => '0');
      key_r         <= (others => '0');
      r2_mod_n_r    <= (others => '0');
      n_prime_r     <= (others => '0');
      modulus_r     <= (others => '0');
      
      vlnw_schedule_0_r <= (others => '0');
      vlnw_schedule_1_r <= (others => '0');
      vlnw_schedule_2_r <= (others => '0');
      for i in 0 to LANES-1 loop
        msg(i)   <= (others => '0');
        acc5(i)  <= (others => '0');
        oneM5(i) <= (others => '0');
        A2_5(i)  <= (others => '0');
        for tbl_i in 0 to 7 loop
          tbl5(i)(tbl_i) <= (others => '0');
        end loop;
      end loop;
      issue_idx <= 0;
      --capt_idx  <= 0;
      mpb_st    <= MPB_IDLE;
      in_count  <= 0;
      out_count <= 0;

    elsif rising_edge(clk) then
      mp_start <= '0';
      -- DO NOT force mp_batch_done <= '0' here anymore
      mp_done_z <= mp_done;
      v_mp_batch_done := '0';
      
    
      case mpb_st is
      when MPB_IDLE =>
        null;
    
      -- 1) Pulse start (NO operands this cycle)
      when MPB_KICK =>
        mp_start   <= '1';
        issue_idx  <= 0;
        mpb_st     <= MPB_ISSUE;
    
      -- 2) Stream 5 operand beats on the NEXT cycles
      when MPB_ISSUE =>
        a_in <= batchA(issue_idx);
        b_in <= batchB(issue_idx);
        if issue_idx = cur_lanes-1 then           -- CHANGED (LANES-1 -> cur_lanes-1)
          mpb_st    <= MPB_WAIT_DONE;
        else
          issue_idx <= issue_idx + 1;
        end if;
        
        
    
      -- 3) Wait for the first done↑; r is valid on this same cycle
      when MPB_WAIT_DONE =>
        if (mp_done = '1') and (mp_done_z = '0') then
          batchR(0) <= mp_r;    -- capture result #0 immediately
          grab_idx  <= 1;       -- next to grab will be #1
          mpb_st    <= MPB_GRAB;
        end if;
    
      -- 4) Grab the remaining beats on the next 4 cycles
      when MPB_GRAB =>
          if grab_idx < cur_lanes then               -- CHANGED (LANES -> cur_lanes)
            batchR(grab_idx) <= mp_r;
            grab_idx         <= grab_idx + 1;
          end if;
          if grab_idx = cur_lanes then               -- CHANGED (LANES -> cur_lanes)
            grab_idx   <= 0;
            mpb_st     <= MPB_IDLE;
            v_mp_batch_done := '1';
          end if;
    end case;
    
    mp_batch_done_d <= v_mp_batch_done;
    mp_batch_done   <= mp_batch_done_d;
    
      if mp_done = '1' then
        obs_total <= obs_total + 1;
      end if;

      case st is
        when S_IDLE =>
          valid_out_r <= '0';
        
          if valid_in='1' and ready_in_r='1' then
            -- store message
            msg(in_count) <= message;
        
            -- remember if stream last arrived while filling
            if last_in='1' then
              tail_pending <= '1';
            end if;
        
            -- how many msgs will we have after this handshake?
            i := in_count + 1;
        
            if (i = LANES) or (tail_pending = '1') then
              -- decide short vs full batch
              if i = LANES then
                cur_lanes <= LANES;
              else
                cur_lanes <= i;           -- 1..4 (short batch)
              end if;
        
              -- stop intake during processing
              ready_in_r <= '0';
        
              -- latch shared params for this batch
              key_r         <= key;
              r2_mod_n_r    <= r2_mod_n;
              n_prime_r     <= n_prime;
              modulus_r     <= modulus;
              vlnw_schedule_0_r <= vlnw_schedule_0;
              vlnw_schedule_1_r <= vlnw_schedule_1;
              vlnw_schedule_2_r <= vlnw_schedule_2;
        
              -- start pipeline on msg(0..cur_lanes-1)
              st        <= S_TO_MONT_A;
              in_count  <= 0;
              tail_pending <= '0';        -- consumed the tail marker for this batch
        
            else
              -- keep filling
              in_count <= i;
            end if;
        
          else
            -- ready to accept next input when producer has one
            ready_in_r <= '1';
          end if;

        -- toMont(A) = MonPro(A, R^2 mod n)
        when S_TO_MONT_A =>
          n_reg <= modulus_r;  -- shared
          -- Prepare batch operands: MonPro(msg[i], R2)
          -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL active lanes
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= msg(i);
                batchB(i) <= r2_mod_n_r;
              end if;
            end loop;
          issue_idx <= 0;
          mpb_st <= MPB_KICK;
          st     <= S_WAIT_TO_MONT_A;
        
        when S_WAIT_TO_MONT_A =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                acc5(i) <= batchR(i);
              end if;
            end loop;
            st <= S_TO_MONT_ONE;
          end if;

        when S_TO_MONT_ONE =>
          -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= (others => '0'); batchA(i)(0) <= '1';
                batchB(i) <= r2_mod_n_r;
              end if;
            end loop;
          issue_idx <= 0;
          mpb_st <= MPB_KICK;
          st     <= S_WAIT_TO_MONT_ONE;
        
        when S_WAIT_TO_MONT_ONE =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                oneM5(i) <= batchR(i);
              end if;
            end loop;
            st <= S_A2;  -- next precompute rounds
          end if;

        when S_A2 =>
          -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= acc5(i);
                batchB(i) <= acc5(i);
              end if;
            end loop;
          issue_idx <= 0;
          mpb_st <= MPB_KICK;
          st     <= S_WAIT_A2;
        
        when S_WAIT_A2 =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                A2_5(i)  <= batchR(i);
              end if;
            end loop;
            -- A^3 = A^2 * A
            -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL (A^3 = A^2 * A)
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= batchR(i);  -- A^2
                batchB(i) <= acc5(i);    -- A
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st    <= MPB_KICK;
            st     <= S_WAIT_A3;
          end if;

        when S_WAIT_A3 =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                tbl5(i)(1) <= batchR(i);     -- A^3
                tbl5(i)(0) <= acc5(i);       -- A^1
              end if;
            end loop;
            tbl_idx <= 2;  -- next odd power slot: 5..15
            -- seed next: A^5 = A^3 * A^2
            -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL (A^5 = A^3 * A^2)
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= batchR(i);      -- A^3
                batchB(i) <= A2_5(i);        -- A^2
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st <= MPB_KICK;
            st     <= S_PRECOMP_GEN;
          end if;
          
        when S_PRECOMP_GEN =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                tbl5(i)(tbl_idx) <= batchR(i);
              end if;
            end loop;
            if tbl_idx = 7 then
              st <= S_LOAD_VLNW;   -- done with precompute for all 5
            else
              tbl_idx <= tbl_idx + 1;
              -- Next odd = prev_odd * A^2
              -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL (next odd = prev_odd * A^2)
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= batchR(i);
                batchB(i) <= A2_5(i);
              end if;
            end loop;
              issue_idx <= 0;
              mpb_st <= MPB_KICK;
            end if;
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
          for i in 0 to LANES-1 loop
            if i < cur_lanes then
              acc5(i) <= oneM5(i);
            end if;
          end loop;
          vlnw_load <= '1';
          st        <= S_VLNW_ARM;

        -- NEW: arm VLNW, wait until controller has cleared its 'done'
        when S_VLNW_ARM =>
          vlnw_load <= '0';   -- << ADD THIS
          if vlnw_done = '0' then
            st <= S_WAIT_OP;
          end if;

        when S_WAIT_OP =>
          if vlnw_done = '1' then
            -- fromMont for all lanes
            -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= acc5(i);
                batchB(i) <= (others => '0'); batchB(i)(0) <= '1';
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st <= MPB_KICK;
            st     <= S_FROM_MONT;
          elsif vlnw_op = "01" and mpb_st = MPB_IDLE then  -- SQUARE
            -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= acc5(i);
                batchB(i) <= acc5(i);
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st <= MPB_KICK;
            last_op  <= "01";
            st       <= S_WAIT_MP;
        
          elsif vlnw_op = "10" and mpb_st = MPB_IDLE then  -- MULTIPLY
            mul_addr_latched <= vlnw_addr;
            idx := vlnw_code_to_index(vlnw_addr);
            assert idx >= 0 report "VLNW addr invalid/zero for multiply" severity failure;
            -- CLEAR
            for i in 0 to LANES-1 loop
              batchA(i) <= (others => '0');
              batchB(i) <= (others => '0');
            end loop;
            -- FILL
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= acc5(i);
                batchB(i) <= tbl5(i)(idx);
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st <= MPB_KICK;
            last_op <= "10";
            st      <= S_WAIT_MP;
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
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                acc5(i) <= batchR(i);
              end if;
            end loop;
            -- bump counters if you like (squares/multiplies)
            st <= S_CHECK_VLNW_DONE;
          end if;

        when S_CHECK_VLNW_DONE =>
          if vlnw_done = '1' then
            -- fromMont batch (already prepared in S_WAIT_OP when vlnw_done=1)
            -- nothing to do here, we'll move to S_FROM_MONT after the batch completes
            null;
          else
            st <= S_WAIT_OP;
          end if;

        when S_FROM_MONT =>
          if mp_batch_done = '1' then
            -- Present results sequentially, 5 beats, matching intake order
            out_count   <= 0;
            valid_out_r <= '1';
            result_r    <= batchR(0);
            st          <= S_OUT;
          end if;
        
        when S_OUT =>
          if ready_out = '1' then
            if out_count = cur_lanes-1 then
              valid_out_r <= '0';
              out_count   <= 0;
              ready_in_r  <= '1';   -- accept next batch
              st          <= S_IDLE;
            else
              out_count   <= out_count + 1;
              result_r    <= batchR(out_count + 1);
            end if;
          end if;

        when others =>
          st <= S_IDLE;
      end case;
      
    end if;
  end process;
end rtl;
