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
    last_in   : in  std_logic;

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

  constant W      : integer := 32;
  constant K      : integer := C_block_size / W;
  constant LANES  : integer := 5;

  type vec256_t   is array (0 to LANES-1) of std_logic_vector(C_block_size-1 downto 0);

  -- RAM interface for precompute tables (per lane)
  signal pre_we    : std_logic_vector(LANES-1 downto 0) := (others => '0');
  signal pre_waddr : std_logic_vector(2 downto 0)       := (others => '0');
  signal pre_raddr : std_logic_vector(2 downto 0)       := (others => '0');
  signal pre_din   : vec256_t                           := (others => (others => '0'));
  signal pre_dout  : vec256_t                           := (others => (others => '0'));

  ---------------------------------------------------------------------------
  -- Subcomponents
  ---------------------------------------------------------------------------
  component monpro
    port (
      clk       : in  std_logic;
      reset_n   : in  std_logic;
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

  component precomp_ram is
    generic (
      C_block_size : integer := 256
    );
    port (
      clk   : in  std_logic;
      we    : in  std_logic;
      waddr : in  std_logic_vector(2 downto 0);  -- 0..7
      din   : in  std_logic_vector(C_block_size-1 downto 0);
      raddr : in  std_logic_vector(2 downto 0);  -- 0..7
      dout  : out std_logic_vector(C_block_size-1 downto 0)
    );
  end component;

  ---------------------------------------------------------------------------
  -- FSM / batching
  ---------------------------------------------------------------------------
  type state_t is (
    S_IDLE,
    S_TO_MONT_A, S_WAIT_TO_MONT_A,
    S_TO_MONT_ONE, S_WAIT_TO_MONT_ONE,
    S_A2, S_WAIT_A2,
    S_WAIT_A3,
    S_PRECOMP_GEN,
    S_LOAD_VLNW,
    S_VLNW_ARM,
    S_WAIT_OP,
    S_WAIT_PRE_READ,
    S_WAIT_PRE_USE,
    S_WAIT_MP,
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

  -- MonPro batch micro-engine (5 beats)
  type mpb_state_t is (MPB_IDLE, MPB_KICK, MPB_ISSUE, MPB_WAIT_DONE, MPB_GRAB);
  signal mpb_st       : mpb_state_t := MPB_IDLE;
  signal issue_idx    : integer range 0 to LANES := 0;
  signal grab_idx     : integer range 0 to LANES := 0;
  signal mp_done_z    : std_logic := '0';

  -- short-batch control
  signal cur_lanes    : integer range 1 to LANES := LANES; -- 1..5 active lanes this batch

  -- One operation's per-lane operands/result buffers
  signal batchA, batchB, batchR : vec256_t := (others => (others => '0'));

  -- "Operation complete for all lanes" pulse
  signal mp_batch_done   : std_logic := '0';
  signal mp_batch_done_d : std_logic := '0';

  signal tbl_idx       : integer range 0 to 7 := 0;
  --signal last_op    : std_logic_vector(1 downto 0) := "00";

  -- VLNW
  signal vlnw_load     : std_logic := '0';
  signal vlnw_done     : std_logic;
  signal vlnw_op       : std_logic_vector(1 downto 0);
  signal vlnw_addr     : std_logic_vector(3 downto 0);

  -- I/O handshake
  signal ready_in_r    : std_logic := '1';
  signal valid_out_r   : std_logic := '0';
  signal result_r      : std_logic_vector(C_block_size-1 downto 0) := (others => '0');

  -- Multiply / table
  signal mul_addr_latched : std_logic_vector(3 downto 0);
  signal mul_idx_reg      : integer range 0 to 7;

  -- Observability (optional)
  signal obs_total : integer := 0;

  -- Latched shared params
  signal r2_mod_n_r : std_logic_vector(C_block_size-1 downto 0);
  signal n_prime_r  : std_logic_vector(31 downto 0);
  signal modulus_r  : std_logic_vector(C_block_size-1 downto 0);

  -- Per-lane contexts
  signal msg      : vec256_t := (others => (others => '0'));
  signal acc5     : vec256_t := (others => (others => '0'));  -- accumulator (Montgomery domain)
  signal oneM5    : vec256_t := (others => (others => '0'));
  signal A2_5     : vec256_t := (others => (others => '0'));

  -- Latched schedules
  signal vlnw_schedule_0_r : std_logic_vector(255 downto 0);
  signal vlnw_schedule_1_r : std_logic_vector(255 downto 0);
  signal vlnw_schedule_2_r : std_logic_vector(255 downto 0);

  -- to take in up to 5 messages
  signal in_count    : integer range 0 to LANES := 0;
  signal out_count   : integer range 0 to LANES := 0;

  ---------------------------------------------------------------------------
  -- Helper: VLNW nibble → index 0..7
  ---------------------------------------------------------------------------
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

begin
  ---------------------------------------------------------------------------
  -- External ports
  ---------------------------------------------------------------------------
  ready_in  <= ready_in_r;
  valid_out <= valid_out_r;
  result    <= result_r;

  ---------------------------------------------------------------------------
  -- MonPro instance
  ---------------------------------------------------------------------------
  u_monpro : monpro
    port map (
      clk       => clk,
      reset_n   => reset_n,
      start     => mp_start,
      busy      => mp_busy,
      done      => mp_done,
      A         => a_in,
      B         => b_in,
      n         => n_reg,
      n_prime   => n_prime_r,
      r         => mp_r
    );

  ---------------------------------------------------------------------------
  -- VLNW controller instance
  ---------------------------------------------------------------------------
  u_vlnw : vlnw_controller
    port map (
      clk                 => clk,
      reset               => not reset_n,
      load                => vlnw_load,
      monpro_done         => mp_batch_done,
      vlnw_schedule_0     => vlnw_schedule_0_r,
      vlnw_schedule_1     => vlnw_schedule_1_r,
      vlnw_schedule_2     => vlnw_schedule_2_r,
      read_precompute_adr => vlnw_addr,
      done                => vlnw_done,
      monpro_op           => vlnw_op
    );

  ---------------------------------------------------------------------------
  -- 5 small RAMs: one per lane, 8 entries of 256 bits
  ---------------------------------------------------------------------------
  gen_precomp_ram : for l in 0 to LANES-1 generate
    u_precomp_ram : precomp_ram
      generic map (
        C_block_size => C_block_size
      )
      port map (
        clk   => clk,
        we    => pre_we(l),
        waddr => pre_waddr,
        din   => pre_din(l),
        raddr => pre_raddr,
        dout  => pre_dout(l)
      );
  end generate;

  ---------------------------------------------------------------------------
  -- Main process: FSM + MonPro batch engine
  ---------------------------------------------------------------------------
  process(clk, reset_n)
    variable i   : integer;
    variable idx : integer;
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

      cur_lanes   <= LANES;

      tbl_idx     <= 0;
      vlnw_load   <= '0';
      mul_addr_latched <= (others => '0');
      mul_idx_reg <= 0;
      obs_total   <= 0;

      r2_mod_n_r  <= (others => '0');
      n_prime_r   <= (others => '0');
      modulus_r   <= (others => '0');

      vlnw_schedule_0_r <= (others => '0');
      vlnw_schedule_1_r <= (others => '0');
      vlnw_schedule_2_r <= (others => '0');

      for i in 0 to LANES-1 loop
        msg(i)   <= (others => '0');
        acc5(i)  <= (others => '0');
        oneM5(i) <= (others => '0');
        A2_5(i)  <= (others => '0');
      end loop;

      issue_idx <= 0;
      mpb_st    <= MPB_IDLE;
      in_count  <= 0;
      out_count <= 0;
      pre_we    <= (others => '0');
      pre_waddr <= (others => '0');
      pre_raddr <= (others => '0');
      pre_din   <= (others => (others => '0'));
      mp_done_z <= '0';
      mp_batch_done   <= '0';
      mp_batch_done_d <= '0';

    elsif rising_edge(clk) then
      -----------------------------------------------------------------------
      -- Defaults each cycle
      -----------------------------------------------------------------------
      mp_start       <= '0';
      mp_done_z      <= mp_done;
      v_mp_batch_done := '0';
      pre_we         <= (others => '0');

      -----------------------------------------------------------------------
      -- MonPro batch micro-engine (5-lane)
      -----------------------------------------------------------------------
      case mpb_st is
        when MPB_IDLE =>
          null;

        -- 1) Pulse start (no operands this cycle)
        when MPB_KICK =>
          mp_start  <= '1';
          issue_idx <= 0;
          mpb_st    <= MPB_ISSUE;

        -- 2) Stream operands for each active lane
        when MPB_ISSUE =>
          a_in <= batchA(issue_idx);
          b_in <= batchB(issue_idx);
          if issue_idx = cur_lanes-1 then
            mpb_st <= MPB_WAIT_DONE;
          else
            issue_idx <= issue_idx + 1;
          end if;

        -- 3) Wait for first done↑; result #0 is valid on that edge
        when MPB_WAIT_DONE =>
          if (mp_done = '1') and (mp_done_z = '0') then
            batchR(0) <= mp_r;
            grab_idx  <= 1;
            mpb_st    <= MPB_GRAB;
          end if;

        -- 4) Grab remaining results
        when MPB_GRAB =>
          if grab_idx < cur_lanes then
            batchR(grab_idx) <= mp_r;
            grab_idx         <= grab_idx + 1;
          end if;
          if grab_idx = cur_lanes then
            grab_idx         <= 0;
            mpb_st           <= MPB_IDLE;
            v_mp_batch_done  := '1';
          end if;
      end case;

      mp_batch_done_d <= v_mp_batch_done;
      mp_batch_done   <= mp_batch_done_d;

      if mp_done = '1' then
        obs_total <= obs_total + 1;
      end if;

      -----------------------------------------------------------------------
      -- Main FSM
      -----------------------------------------------------------------------
      case st is

        ---------------------------------------------------------------------
        -- Input collection: buffer up to 5 messages
        ---------------------------------------------------------------------
        when S_IDLE =>
          valid_out_r <= '0';

          if valid_in = '1' and ready_in_r = '1' then
            msg(in_count) <= message;
            i := in_count + 1;

            if (i = LANES) or (last_in = '1') then
              if i = LANES then
                cur_lanes <= LANES;
              else
                cur_lanes <= i;  -- 1..4
              end if;

              ready_in_r <= '0';

              -- latch shared params for this batch
              r2_mod_n_r        <= r2_mod_n;
              n_prime_r         <= n_prime;
              modulus_r         <= modulus;
              vlnw_schedule_0_r <= vlnw_schedule_0;
              vlnw_schedule_1_r <= vlnw_schedule_1;
              vlnw_schedule_2_r <= vlnw_schedule_2;

              st        <= S_TO_MONT_A;
              in_count  <= 0;

            else
              in_count <= i;
            end if;

          else
            ready_in_r <= '1';
          end if;

        ---------------------------------------------------------------------
        -- toMont(A) = MonPro(A, R^2 mod n)
        ---------------------------------------------------------------------
        when S_TO_MONT_A =>
          n_reg <= modulus_r;
          for i in 0 to LANES-1 loop
            if i < cur_lanes then
              batchA(i) <= msg(i);
              batchB(i) <= r2_mod_n_r;
            end if;
          end loop;
          issue_idx <= 0;
          mpb_st    <= MPB_KICK;
          st        <= S_WAIT_TO_MONT_A;

        when S_WAIT_TO_MONT_A =>
          if mp_batch_done = '1' then
            -- A^1_M: store in acc5 AND in RAM address 0
            pre_waddr <= "000";
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                acc5(i)     <= batchR(i);
                pre_we(i)   <= '1';
                pre_din(i)  <= batchR(i);  -- A^1
              end if;
            end loop;
            st <= S_TO_MONT_ONE;
          end if;

        ---------------------------------------------------------------------
        -- toMont(1) for each lane
        ---------------------------------------------------------------------
        when S_TO_MONT_ONE =>
          for i in 0 to LANES-1 loop
            if i < cur_lanes then
              batchA(i)        <= (others => '0');
              batchA(i)(0)     <= '1';
              batchB(i)        <= r2_mod_n_r;
            end if;
          end loop;
          issue_idx <= 0;
          mpb_st    <= MPB_KICK;
          st        <= S_WAIT_TO_MONT_ONE;

        when S_WAIT_TO_MONT_ONE =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                oneM5(i) <= batchR(i);
              end if;
            end loop;
            st <= S_A2;
          end if;

        ---------------------------------------------------------------------
        -- A^2, then A^3, then build table up to A^15
        ---------------------------------------------------------------------
        when S_A2 =>
          for i in 0 to LANES-1 loop
            if i < cur_lanes then
              batchA(i) <= acc5(i);
              batchB(i) <= acc5(i);
            end if;
          end loop;
          issue_idx <= 0;
          mpb_st    <= MPB_KICK;
          st        <= S_WAIT_A2;

        when S_WAIT_A2 =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                A2_5(i) <= batchR(i);   -- A^2
              end if;
            end loop;
            -- A^3 = A^2 * A
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= batchR(i);  -- A^2
                batchB(i) <= acc5(i);    -- A^1
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st    <= MPB_KICK;
            st        <= S_WAIT_A3;
          end if;

        when S_WAIT_A3 =>
          if mp_batch_done = '1' then
            -- Write A^3 to RAM index 1
            pre_waddr <= "001";
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                pre_we(i)  <= '1';
                pre_din(i) <= batchR(i);  -- A^3
              end if;
            end loop;

            tbl_idx <= 2;  -- next slot: 5..15 -> indices 2..7

            -- seed next: A^5 = A^3 * A^2
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= batchR(i);   -- A^3
                batchB(i) <= A2_5(i);     -- A^2
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st    <= MPB_KICK;
            st        <= S_PRECOMP_GEN;
          end if;

        when S_PRECOMP_GEN =>
          if mp_batch_done = '1' then
            -- Store A^5..A^15 at indices 2..7
            pre_waddr <= std_logic_vector(to_unsigned(tbl_idx, 3));
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                pre_we(i)  <= '1';
                pre_din(i) <= batchR(i);
              end if;
            end loop;

            if tbl_idx = 7 then
              st <= S_LOAD_VLNW;
            else
              tbl_idx <= tbl_idx + 1;
              -- Next odd = prev_odd * A^2
              for i in 0 to LANES-1 loop
                if i < cur_lanes then
                  batchA(i) <= batchR(i);
                  batchB(i) <= A2_5(i);
                end if;
              end loop;
              issue_idx <= 0;
              mpb_st    <= MPB_KICK;
            end if;
          end if;

        ---------------------------------------------------------------------
        -- Initialize VLNW, set acc = 1_M
        ---------------------------------------------------------------------
        when S_LOAD_VLNW =>
          for i in 0 to LANES-1 loop
            if i < cur_lanes then
              acc5(i) <= oneM5(i);
            end if;
          end loop;
          vlnw_load <= '1';
          st        <= S_VLNW_ARM;

        when S_VLNW_ARM =>
          vlnw_load <= '0';
          if vlnw_done = '0' then
            st <= S_WAIT_OP;
          end if;

        ---------------------------------------------------------------------
        -- Main exponentiation loop driven by VLNW
        ---------------------------------------------------------------------
        when S_WAIT_OP =>
          if vlnw_done = '1' then
            -- done with schedule: fromMont for all lanes
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i)        <= acc5(i);
                batchB(i)        <= (others => '0');
                batchB(i)(0)     <= '1';
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st    <= MPB_KICK;
            st        <= S_FROM_MONT;

          elsif vlnw_op = "01" and mpb_st = MPB_IDLE then
            -- SQUARE
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i) <= acc5(i);
                batchB(i) <= acc5(i);
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st    <= MPB_KICK;
            st        <= S_WAIT_MP;

          elsif vlnw_op = "10" and mpb_st = MPB_IDLE then
            -- MULTIPLY by A^(odd)
            mul_addr_latched <= vlnw_addr;
            idx := vlnw_code_to_index(vlnw_addr);
            assert idx >= 0 report "VLNW addr invalid/zero for multiply" severity failure;
            mul_idx_reg <= idx;

            -- read A^(2*idx+1) from RAM next cycle (including idx=0 => A^1)
            pre_raddr <= std_logic_vector(to_unsigned(idx, 3));
            st        <= S_WAIT_PRE_READ;
          end if;

        when S_WAIT_PRE_READ =>
          -- Her gjør vi ingenting annet enn å vente én klokke slik at
          -- precomp_ram får tid til å oppdatere qreg/pre_dout.
          st <= S_WAIT_PRE_USE;
          
        when S_WAIT_PRE_USE =>
          -- Nå er pre_dout(lane) stabilt for adressen vi satte to klokker siden
          for lane in 0 to LANES-1 loop
            if lane < cur_lanes then
              batchA(lane) <= acc5(lane);
              batchB(lane) <= pre_dout(lane);
            end if;
          end loop;
          issue_idx <= 0;
          mpb_st    <= MPB_KICK;
          --last_op   <= "10";
          st        <= S_WAIT_MP;

        when S_WAIT_MP =>
          if mp_batch_done = '1' then
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                acc5(i) <= batchR(i);
              end if;
            end loop;
            st <= S_CHECK_VLNW_DONE;
          end if;

        when S_CHECK_VLNW_DONE =>
          if vlnw_done = '1' then
            -- schedule finished: prepare final fromMont if not already
            for i in 0 to LANES-1 loop
              if i < cur_lanes then
                batchA(i)        <= acc5(i);
                batchB(i)        <= (others => '0');
                batchB(i)(0)     <= '1';
              end if;
            end loop;
            issue_idx <= 0;
            mpb_st    <= MPB_KICK;
            st        <= S_FROM_MONT;
          else
            st <= S_WAIT_OP;
          end if;

        ---------------------------------------------------------------------
        -- fromMont and output streaming
        ---------------------------------------------------------------------
        when S_FROM_MONT =>
          if mp_batch_done = '1' then
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
              ready_in_r  <= '1';
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity precomp_ram is
  generic (
    C_block_size : integer := 256
  );
  port (
    clk   : in  std_logic;
    we    : in  std_logic;
    waddr : in  std_logic_vector(2 downto 0);  -- 0..7
    din   : in  std_logic_vector(C_block_size-1 downto 0);
    raddr : in  std_logic_vector(2 downto 0);  -- 0..7
    dout  : out std_logic_vector(C_block_size-1 downto 0)
  );
end precomp_ram;

architecture rtl of precomp_ram is
  type ram_t is array (0 to 7) of std_logic_vector(C_block_size-1 downto 0);
  signal ram  : ram_t := (others => (others => '0'));
  signal qreg : std_logic_vector(C_block_size-1 downto 0);

  -- Hint for Vivado: infer block RAM
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
begin
  process(clk)
  begin
    if rising_edge(clk) then
      -- write
      if we = '1' then
        ram(to_integer(unsigned(waddr))) <= din;
      end if;
      -- synchronous read
      qreg <= ram(to_integer(unsigned(raddr)));
    end if;
  end process;

  dout <= qreg;
end rtl;
