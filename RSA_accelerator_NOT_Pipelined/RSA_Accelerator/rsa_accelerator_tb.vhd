-- *****************************************************************************
-- Name:     rsa_accelerator_tb.vhd  (adapted for rsa_core + VLNW schedules)
-- Purpose:  Run only DECRYPTION tests (ct3..ct5) using schedule-driven core
-- *****************************************************************************
library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity rsa_accelerator_tb is
end rsa_accelerator_tb;

architecture struct of rsa_accelerator_tb is
  -----------------------------------------------------------------------------
  -- Constants
  -----------------------------------------------------------------------------
  constant C_BLOCK_SIZE       : integer := 256;

  -- Folder: "short_test" or "long_test"
  constant C_TESTCASE_FOLDER  : string  := "long_test";

  -- Only run DECRYPTION testcases (ct3..ct5)
  constant C_TEST_FIRST_ID    : integer := 3;  -- ct3
  constant C_TEST_LAST_ID     : integer := 5;  -- ct5

  -----------------------------------------------------------------------------
  -- Montgomery / schedule constants (FILL IN!)
    ---------------------------------------------------------------------------
  -- Realistic constants (you can replace later)
  -- n is 256-bit odd modulus; R = 2^256; R2 = R^2 mod n
  -- n' = (-n^{-1}) mod 2^32 (depends only on n(31 downto 0); n must be odd)
  ---------------------------------------------------------------------------
  --constant MODULUS_C  : std_logic_vector(C_BLOCK-1 downto 0)
    --:= x"99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D";  --RIKTIG

  --constant R2MODN_C   : std_logic_vector(C_BLOCK-1 downto 0)
    --:= x"56DDF8B43061AD3DBCD1757244D1A19E2E8C849DDE4817E55BB29D1C20C06364"; --RIKTIG

  --constant NPRIME_C   : std_logic_vector(31 downto 0)
    --:= x"8833C3BB"; --RIKTIG

  --constant MESSAGE_C  : std_logic_vector(C_BLOCK-1 downto 0)
    --:= x"47D69AAD3C674409759981524CE494FD331DBE831A4970E6D6AB58052FFF24D0"; --RIKTIG

  ---------------------------------------------------------------------------
  -- Your encoded schedule words (EXACT 256-bit binary strings; MSB-left)
  ---------------------------------------------------------------------------
  -- 0000 001
  --constant SCHED0_BITS : std_logic_vector(255 downto 0) :=
    --x"b6682f00b07782b04f5fb84202b7e189f8427e12c11b781780f00b02f03bfe00";

  --constant SCHED1_BITS : std_logic_vector(255 downto 0) :=
    --x"dc2103340be7fc2780580bc2fc00d601ebc1341341341dc37a703705e9c31019";
    
  --constant SCHED2_BITS : std_logic_vector(255 downto 0) := 
    --x"e7016fff02700000000000000000000000000000000000000000000000000000";
  -----------------------------------------------------------------------------
  constant R2_MOD_N_C : std_logic_vector(255 downto 0) :=
    x"56DDF8B43061AD3DBCD1757244D1A19E2E8C849DDE4817E55BB29D1C20C06364";

  constant N_PRIME_C  : std_logic_vector(31 downto 0) :=
    x"8833C3BB";

  -- Your decryption schedule (three 256-bit words)
  constant VLNW0_C : std_logic_vector(255 downto 0) :=
    x"b6682f00b07782b04f5fb84202b7e189f8427e12c11b781780f00b02f03bfe00";
  constant VLNW1_C : std_logic_vector(255 downto 0) :=
    x"dc2103340be7fc2780580bc2fc00d601ebc1341341341dc37a703705e9c31019";
  constant VLNW2_C : std_logic_vector(255 downto 0) :=
    x"e7016fff02700000000000000000000000000000000000000000000000000000";

  -----------------------------------------------------------------------------
  -- Clocks and reset
  -----------------------------------------------------------------------------
  signal clk              : std_logic;
  signal reset_n          : std_logic;

  -----------------------------------------------------------------------------
  -- Slave msgin interface
  -----------------------------------------------------------------------------
  signal msgin_valid      : std_logic;
  signal msgin_ready      : std_logic;
  signal msgin_data       : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal msgin_last       : std_logic;

  -----------------------------------------------------------------------------
  -- Master msgout interface
  -----------------------------------------------------------------------------
  signal msgout_valid     : std_logic;
  signal msgout_ready     : std_logic;
  signal msgout_data      : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal msgout_last      : std_logic;

  -----------------------------------------------------------------------------
  -- Interface to core
  -----------------------------------------------------------------------------
  signal key_e_d          : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal key_n            : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal rsa_status       : std_logic_vector(31 downto 0);

  -- NEW - Precompute/Schedule signals into rsa_core
  signal r2_mod_n_s       : std_logic_vector(255 downto 0);
  signal n_prime_s        : std_logic_vector(31 downto 0);
  signal vlnw0_s          : std_logic_vector(255 downto 0);
  signal vlnw1_s          : std_logic_vector(255 downto 0);
  signal vlnw2_s          : std_logic_vector(255 downto 0);

  -----------------------------------------------------------------------------
  -- Testcase file handles
  -----------------------------------------------------------------------------
  file tc_inp: text;
  file tc_otp: text;

  -----------------------------------------------------------------------------
  -- Open input/output files (unchanged)
  -----------------------------------------------------------------------------
  procedure open_tc_inp(testcase_id: in integer) is
  begin
    if   testcase_id=0 then file_open(tc_inp, C_TESTCASE_FOLDER & ".inp_messages.hex_pt0_in.txt", read_mode);
    elsif testcase_id=1 then file_open(tc_inp, C_TESTCASE_FOLDER & ".inp_messages.hex_pt1_in.txt", read_mode);
    elsif testcase_id=2 then file_open(tc_inp, C_TESTCASE_FOLDER & ".inp_messages.hex_pt2_in.txt", read_mode);
    elsif testcase_id=3 then file_open(tc_inp, C_TESTCASE_FOLDER & ".inp_messages.hex_ct3_in.txt", read_mode);
    elsif testcase_id=4 then file_open(tc_inp, C_TESTCASE_FOLDER & ".inp_messages.hex_ct4_in.txt", read_mode);
    elsif testcase_id=5 then file_open(tc_inp, C_TESTCASE_FOLDER & ".inp_messages.hex_ct5_in.txt", read_mode);
    end if;
  end open_tc_inp;

  procedure open_tc_otp(testcase_id: in integer) is
  begin
    if   testcase_id=0 then file_open(tc_otp, C_TESTCASE_FOLDER & ".otp_messages.hex_ct0_out.txt", read_mode);
    elsif testcase_id=1 then file_open(tc_otp, C_TESTCASE_FOLDER & ".otp_messages.hex_ct1_out.txt", read_mode);
    elsif testcase_id=2 then file_open(tc_otp, C_TESTCASE_FOLDER & ".otp_messages.hex_ct2_out.txt", read_mode);
    elsif testcase_id=3 then file_open(tc_otp, C_TESTCASE_FOLDER & ".otp_messages.hex_pt3_out.txt", read_mode);
    elsif testcase_id=4 then file_open(tc_otp, C_TESTCASE_FOLDER & ".otp_messages.hex_pt4_out.txt", read_mode);
    elsif testcase_id=5 then file_open(tc_otp, C_TESTCASE_FOLDER & ".otp_messages.hex_pt5_out.txt", read_mode);
    end if;
  end open_tc_otp;

  -----------------------------------------------------------------------------
  -- Hex string conversion helpers (unchanged)
  -----------------------------------------------------------------------------
  -- Reverse 8×32-bit word order in a 256-bit vector
  function swap_words32_256(x : std_logic_vector(255 downto 0))
    return std_logic_vector is
    variable y : std_logic_vector(255 downto 0);
  begin
    for i in 0 to 7 loop
      y(255-32*i downto 224-32*i) := x(32*i+31 downto 32*i);
    end loop;
    return y;
  end function;

  -- Reverse 32×8-bit byte order in a 256-bit vector
  function swap_bytes_256(x : std_logic_vector(255 downto 0))
    return std_logic_vector is
    variable y : std_logic_vector(255 downto 0);
  begin
    for i in 0 to 31 loop
      y(255-8*i downto 248-8*i) := x(8*i+7 downto 8*i);
    end loop;
    return y;
  end function;
  
  function str_to_stdvec(inp: string) return std_logic_vector is
    variable temp: std_logic_vector(4*inp'length-1 downto 0) := (others => 'X');
    variable temp1 : std_logic_vector(3 downto 0);
  begin
    for i in inp'range loop
      case inp(i) is
        when '0' => temp1 := x"0"; when '1' => temp1 := x"1";
        when '2' => temp1 := x"2"; when '3' => temp1 := x"3";
        when '4' => temp1 := x"4"; when '5' => temp1 := x"5";
        when '6' => temp1 := x"6"; when '7' => temp1 := x"7";
        when '8' => temp1 := x"8"; when '9' => temp1 := x"9";
        when 'A'|'a' => temp1 := x"A"; when 'B'|'b' => temp1 := x"B";
        when 'C'|'c' => temp1 := x"C"; when 'D'|'d' => temp1 := x"D";
        when 'E'|'e' => temp1 := x"E"; when 'F'|'f' => temp1 := x"F";
        when others =>  temp1 := "XXXX";
      end case;
      temp(4*(i-1)+3 downto 4*(i-1)) := temp1;
    end loop;
    return temp;
  end function;

  function stdvec_to_string ( a: std_logic_vector) return string is
    variable b : string (a'length/4 downto 1) := (others => NUL);
    variable nibble : std_logic_vector(3 downto 0);
  begin
    for i in b'length downto 1 loop
      nibble := a(i*4-1 downto (i-1)*4);
      case nibble is
        when "0000" => b(i) := '0'; when "0001" => b(i) := '1';
        when "0010" => b(i) := '2'; when "0011" => b(i) := '3';
        when "0100" => b(i) := '4'; when "0101" => b(i) := '5';
        when "0110" => b(i) := '6'; when "0111" => b(i) := '7';
        when "1000" => b(i) := '8'; when "1001" => b(i) := '9';
        when "1010" => b(i) := 'A'; when "1011" => b(i) := 'B';
        when "1100" => b(i) := 'C'; when "1101" => b(i) := 'D';
        when "1110" => b(i) := 'E'; when "1111" => b(i) := 'F';
        when others => b(i) := 'X';
      end case;
    end loop;
    return b;
  end function;

  -----------------------------------------------------------------------------
  -- Read keys/command + I/O messages (unchanged)
  -----------------------------------------------------------------------------
  procedure read_keys_and_command(
    signal kn  : out std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    signal ked : out std_logic_vector(C_BLOCK_SIZE-1 downto 0)
  ) is
    variable line_from_file: line;
    variable s1            : string(1 downto 1);
    variable s64           : string(C_BLOCK_SIZE/4 downto 1);
    variable command       : std_logic;
    variable e             : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    variable d             : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    variable n             : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  begin
    -- Read comments/keys/command (same format as original)
    readline(tc_inp, line_from_file); -- # KEY N
    readline(tc_inp, line_from_file); read(line_from_file, s64); n := str_to_stdvec(s64);
    readline(tc_inp, line_from_file); -- # KEY E
    readline(tc_inp, line_from_file); read(line_from_file, s64); e := str_to_stdvec(s64);
    readline(tc_inp, line_from_file); -- # KEY D
    readline(tc_inp, line_from_file); read(line_from_file, s64); d := str_to_stdvec(s64);
    readline(tc_inp, line_from_file); -- # COMMAND
    readline(tc_inp, line_from_file); read(line_from_file, s1);
    command := str_to_stdvec(s1)(0);
    readline(tc_inp, line_from_file); -- empty line

    -- encryption vs decryption selection (file's command)
    if (command='1') then ked <= e; else ked <= d; end if;
    kn <= n;
  end procedure;

  procedure read_input_message(
    variable input_message  : out std_logic_vector(C_BLOCK_SIZE-1 downto 0)
  ) is
    variable line_from_file: line;
    variable s64           : string(C_BLOCK_SIZE/4 downto 1);
  begin
    readline(tc_inp, line_from_file);
    read(line_from_file, s64);
    input_message := str_to_stdvec(s64);
  end procedure;

  procedure read_output_message(
    variable output_message  : out std_logic_vector(C_BLOCK_SIZE-1 downto 0)
  ) is
    variable line_from_file: line;
    variable s64           : string(C_BLOCK_SIZE/4 downto 1);
  begin
    readline(tc_otp, line_from_file);
    read(line_from_file, s64);
    output_message := str_to_stdvec(s64);
  end procedure;

  -----------------------------------------------------------------------------
  -- Internal TB state
  -----------------------------------------------------------------------------
  type tc_ctrl_state_t is (e_TC_START_TC, e_TC_RUN_TC, e_TC_WAIT_COMPLETED, e_TC_COMPLETED, e_TC_ALL_TESTS_COMPLETED);
  signal tc_ctrl_state : tc_ctrl_state_t;
  signal all_input_messages_sent       : std_logic;
  signal all_output_messages_received  : std_logic;
  signal test_case_id                  : integer;
  signal start_tc                      : std_logic;

  type msgin_state_t  is (e_MSGIN_IDLE, e_MSGIN_SEND, e_MSGIN_COMPLETED);
  signal msgin_state  : msgin_state_t;
  signal msgin_counter: unsigned(15 downto 0);

  type msgout_state_t is (e_MSGOUT_IDLE, e_MSGOUT_RECEIVE, e_MSGOUT_COMPLETED);
  signal msgout_state : msgout_state_t;
  signal msgout_counter: unsigned(15 downto 0);

  signal msgout_valid_prev : std_logic;
  signal msgout_ready_prev : std_logic;

begin
  -----------------------------------------------------------------------------
  -- Clock/reset
  -----------------------------------------------------------------------------
  clk_gen: process begin clk <= '1'; wait for 1 ns; clk <= '0'; wait for 1 ns; end process;
  reset_gen: process begin reset_n <= '0'; wait for 20 ns; reset_n <= '1'; wait; end process;

  -----------------------------------------------------------------------------
  -- Tie constants to core inputs
  -----------------------------------------------------------------------------
  r2_mod_n_s <= R2_MOD_N_C;
  n_prime_s  <= N_PRIME_C;
  vlnw0_s    <= VLNW0_C;
  vlnw1_s    <= VLNW1_C;
  vlnw2_s    <= VLNW2_C;

  -----------------------------------------------------------------------------
  -- Testcase controller (modified to limit to ct3..ct5)
  -----------------------------------------------------------------------------
  testcase_control: process(clk, reset_n)
  begin
    if reset_n = '0' then
      tc_ctrl_state <= e_TC_START_TC;
      key_n         <= (others => '0');
      key_e_d       <= (others => '0');
      test_case_id  <= C_TEST_FIRST_ID;  -- start at ct3
      start_tc      <= '0';
    elsif rising_edge(clk) then
      start_tc <= '0';
      case tc_ctrl_state is
        when e_TC_START_TC =>
          report "********************************************************************************";
          report "STARTING NEW TESTCASE ID=" & integer'image(test_case_id);
          report "********************************************************************************";
          tc_ctrl_state <= e_TC_RUN_TC;
          open_tc_inp(test_case_id);
          open_tc_otp(test_case_id);
          read_keys_and_command(key_n, key_e_d);
          start_tc <= '1';

        when e_TC_RUN_TC =>
          if all_input_messages_sent='1' then
            tc_ctrl_state <= e_TC_WAIT_COMPLETED;
          end if;

        when e_TC_WAIT_COMPLETED =>
          if all_output_messages_received='1' then
            tc_ctrl_state <= e_TC_COMPLETED;
          end if;

        when e_TC_COMPLETED =>
          file_close(tc_inp);
          file_close(tc_otp);
          if test_case_id >= C_TEST_LAST_ID then
            tc_ctrl_state <= e_TC_ALL_TESTS_COMPLETED;
          else
            test_case_id  <= test_case_id + 1;
            tc_ctrl_state <= e_TC_START_TC;
          end if;

        when others =>
          report "********************************************************************************";
          report "ALL (DECRYPTION) TESTS FINISHED SUCCESSFULLY";
          report "********************************************************************************";
          report "ENDING SIMULATION..." severity Failure;
      end case;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- msgin BFM (unchanged)
  -----------------------------------------------------------------------------
  msgin_bfm: process(clk, reset_n)
    variable msgin_valid_ready: std_logic_vector(1 downto 0);
    variable seed1, seed2     : positive;
    variable rand             : real;
    variable wait_one_cycle   : integer;
    variable input_message    : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  begin
    if reset_n='0' then
      msgin_valid   <= '0';
      msgin_data    <= (others => '0');
      msgin_last    <= '0';
      msgin_counter <= (others => '0');
      msgin_state   <= e_MSGIN_IDLE;
    elsif rising_edge(clk) then
      all_input_messages_sent <= '0';
      case msgin_state is
        when e_MSGIN_IDLE =>
          if start_tc='1' then msgin_state <= e_MSGIN_SEND; end if;

        when e_MSGIN_SEND =>
          msgin_valid_ready := msgin_valid & msgin_ready;
          case msgin_valid_ready is
            when "00" | "01" | "11" =>
              uniform(seed1, seed2, rand); wait_one_cycle := integer(rand);
              if endfile(tc_inp) then
                msgin_state <= e_MSGIN_COMPLETED;
                all_input_messages_sent <= '1';
                msgin_valid <= '0'; msgin_data <= (others => '0'); msgin_last <= '0';
              elsif wait_one_cycle=0 then
                msgin_valid <= '0'; msgin_data <= (others => '0'); msgin_last <= '0';
              else
                msgin_valid <= '1';
                read_input_message(input_message);
                msgin_data <= input_message;
                report "DRIVE NEW MSGIN_DATA[" & stdvec_to_string(std_logic_vector(msgin_counter)) & "] RTL: " & stdvec_to_string(input_message);
                msgin_last  <= msgin_counter(1);
                msgin_counter <= msgin_counter + 1;
              end if;
            when others => null;
          end case;

        when others =>
          msgin_state <= e_MSGIN_IDLE;
      end case;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- msgout BFM (unchanged + safety assertion)
  -----------------------------------------------------------------------------
  msgout_bfm: process(clk, reset_n)
    variable msgout_valid_ready    : std_logic_vector(1 downto 0);
    variable seed1, seed2          : positive;
    variable rand                  : real;
    variable wait_one_cycle        : integer;
    variable expected_msgout_data  : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    variable dut_norm : std_logic_vector(255 downto 0);
  begin
    if reset_n='0' then
      msgout_ready   <= '0';
      msgout_counter <= (others => '0');
      msgout_state   <= e_MSGOUT_IDLE;
    elsif rising_edge(clk) then
      all_output_messages_received <= '0';
      msgout_valid_prev <= msgout_valid;
      msgout_ready_prev <= msgout_ready;

      case msgout_state is
        when e_MSGOUT_IDLE =>
          if start_tc='1' then msgout_state <= e_MSGOUT_RECEIVE; end if;

        when e_MSGOUT_RECEIVE =>
          uniform(seed1, seed2, rand); wait_one_cycle := integer(rand);
          if (wait_one_cycle=0) then msgout_ready <= '0'; else msgout_ready <= '1'; end if;

          if ((msgout_valid_prev='1') and (msgout_valid='0') and (msgout_ready_prev='0')) then
            report "Error in AXIS-Handshake. msgout_valid drops while msgout_ready='0'." severity Failure;
          end if;

          msgout_valid_ready := msgout_valid & msgout_ready;
          case msgout_valid_ready is
            when "11" =>
              msgout_counter <= msgout_counter + 1;
              read_output_message(expected_msgout_data);

              -- normalize DUT output for compare (try A: 32-bit word swap)
              dut_norm := msgout_data;

              -- helpful print uses the normalized value
              report "COMPARE MSGOUT_DATA[" & stdvec_to_string(std_logic_vector(msgout_counter)) &
                    "] DUT = " & stdvec_to_string(dut_norm) &
                    "   EXPECTED = " & stdvec_to_string(expected_msgout_data);

              -- single assert on the normalized value
              assert dut_norm = expected_msgout_data
              report "Output message differs from expected result"
              severity Failure;

              assert msgout_counter(1) = msgout_last
                report "msgin_last/msgout_last mismatch"
                severity Failure;
            when others =>
              if endfile(tc_otp) then
                msgout_state <= e_MSGOUT_COMPLETED;
                all_output_messages_received <= '1';
              end if;
          end case;

        when others =>
          msgout_state <= e_MSGOUT_IDLE;
      end case;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- DUT: rsa_core (now with the extra ports connected)
  -----------------------------------------------------------------------------
  u_rsa_core : entity work.rsa_core
    generic map (
      C_BLOCK_SIZE => C_BLOCK_SIZE
    )
    port map (
      clk             => clk,
      reset_n         => reset_n,
      msgin_valid     => msgin_valid,
      msgin_ready     => msgin_ready,
      msgin_data      => msgin_data,
      msgin_last      => msgin_last,
      msgout_valid    => msgout_valid,
      msgout_ready    => msgout_ready,
      msgout_data     => msgout_data,
      msgout_last     => msgout_last,
      -- keys/status
      key_e_d         => key_e_d,
      key_n           => key_n,
      rsa_status      => rsa_status,
      -- NEW: precompute/schedules
      r2_mod_n        => r2_mod_n_s,
      n_prime         => n_prime_s,
      vlnw_schedule_0 => vlnw0_s,
      vlnw_schedule_1 => vlnw1_s,
      vlnw_schedule_2 => vlnw2_s
    );

end struct;
