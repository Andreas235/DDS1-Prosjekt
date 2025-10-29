----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 24.10.2025 11:46:06
-- Design Name: 
-- Module Name: entry_counter_tb - rtl
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

entity entry_counter_tb is
end entry_counter_tb;

architecture tb of entry_counter_tb is

    -- DUT signals
    signal clk               : std_logic := '0';
    signal shift             : std_logic := '0';
    signal number_of_entries : std_logic_vector(6 downto 0) := (others => '0');
    signal write             : std_logic := '1';
    signal done              : std_logic;

    constant CLK_PERIOD : time := 10 ns;

begin
    --------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------
    uut: entity work.entry_counter
        port map (
            clk               => clk,
            shift             => shift,
            number_of_entries => number_of_entries,
            write             => write,
            done              => done
        );

    --------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    --------------------------------------------------------------------
    -- Stimulus process
    --------------------------------------------------------------------
    stim_proc : process
    begin
        report "Starting entry_counter testbench";

        -- Initialize
        number_of_entries <= "0000101";  -- 5 entries
        write <= '1';                    -- Load count
        wait for CLK_PERIOD;
        write <= '0';
        wait for CLK_PERIOD * 2;

        for i in 0 to 5 loop
            wait for CLK_PERIOD * 5;
            shift <= '1';
            wait for CLK_PERIOD;
            shift <= '0';
        end loop;
        
        wait for CLK_PERIOD;
        number_of_entries <= "0001000";
        write <= '1';                    -- Load count
        wait for CLK_PERIOD;
        write <= '0';
        wait for CLK_PERIOD * 2;
        
        for i in 0 to 7 loop
            shift <= '1';
            wait for CLK_PERIOD;
            shift <= '0';
            wait for CLK_PERIOD * 5;
        end loop;
        
        wait for 20 ns;
        report "Simulation complete.";
        wait;
    end process;

end tb;
