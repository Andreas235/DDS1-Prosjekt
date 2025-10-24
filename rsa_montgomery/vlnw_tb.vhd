----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.10.2025 18:21:55
-- Design Name: 
-- Module Name: vlnw_tb - rtl
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vlnw_controller_tb is
end vlnw_controller_tb;

architecture sim of vlnw_controller_tb is

    -- DUT signals
    signal clk                : std_logic := '0';
    signal reset              : std_logic := '0';  -- active low
    signal load               : std_logic := '0';
    signal monpro_done        : std_logic := '0';
    signal vlnw_schedule_0    : std_logic_vector(255 downto 0) := (others => '0');
    signal vlnw_schedule_1    : std_logic_vector(255 downto 0) := (others => '0');

    signal read_precompute_adr : std_logic_vector(3 downto 0);
    signal done                : std_logic;
    signal monpro_op           : std_logic_vector(1 downto 0);

    constant CLK_PERIOD : time := 10 ns;
    constant MONPRO_TIME : time := 30 ns;

begin
    --------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------
    uut: entity work.vlnw_controller
        port map(
            clk                 => clk,
            reset               => reset,
            load                => load,
            monpro_done         => monpro_done,
            vlnw_schedule_0     => vlnw_schedule_0,
            vlnw_schedule_1     => vlnw_schedule_1,
            read_precompute_adr => read_precompute_adr,
            done                => done,
            monpro_op           => monpro_op
        );

    --------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    --------------------------------------------------------------------
    -- Stimulus process
    --------------------------------------------------------------------
    stim_proc : process
    begin
        ----------------------------------------------------------------
        -- Initial reset
        ----------------------------------------------------------------
        reset <= '0';
        wait for 25 ns;
        reset <= '1';
        wait for 20 ns;

        ----------------------------------------------------------------
        -- Load an example schedule
        -- Top 7 bits of vlnw_schedule_0 = number_of_entries
        -- Bits (248 downto 3) and vlnw_schedule_1 form the full schedule
        ----------------------------------------------------------------
        report "Loading schedule";

        vlnw_schedule_0(255 downto 249) <= "0000100";
        vlnw_schedule_0(248 downto 3)  <= (others => '0');
        vlnw_schedule_1                <= (others => '0');
        vlnw_schedule_0(248 downto 243) <= "111111";  
        vlnw_schedule_0(242 downto 237) <= "000000";
        vlnw_schedule_0(236 downto 231) <= "101010";
        vlnw_schedule_0(230 downto 225) <= "000011";

        load <= '1';
        wait for CLK_PERIOD;
        load <= '0';
        wait for CLK_PERIOD * 2;

        for i in 0 to 20 loop
            wait for MONPRO_TIME;
            -- The FSM inside will toggle 'shift' internally, so we can 
            -- simulate external activity by toggling monpro_done
            monpro_done <= '1';
            wait for CLK_PERIOD;
            monpro_done <= '0';
        end loop;

        vlnw_schedule_0(255 downto 249) <= "0000100";
        vlnw_schedule_0(248 downto 3)  <= (others => '0');
        vlnw_schedule_1                <= (others => '0');
        vlnw_schedule_0(248 downto 243) <= "111111";  
        vlnw_schedule_0(242 downto 237) <= "000000";
        vlnw_schedule_0(236 downto 231) <= "101010";
        vlnw_schedule_0(230 downto 225) <= "000011";

        load <= '1';
        wait for CLK_PERIOD;
        load <= '0';
--           -- Shift a few times to simulate FSM advancement
        ----------------------------------------------------------------
        report "Starting shift sequence";

        for i in 0 to 20 loop
            wait for MONPRO_TIME;
            -- The FSM inside will toggle 'shift' internally, so we can 
            -- simulate external activity by toggling monpro_done
            monpro_done <= '1';
            wait for CLK_PERIOD;
            monpro_done <= '0';
        end loop;

        ----------------------------------------------------------------
        -- Observe outputs
        ----------------------------------------------------------------
        wait for 100 ns;
        report "Simulation finished";
        wait;     wait for CLK_PERIOD * 2;
  
end process;


end sim;

