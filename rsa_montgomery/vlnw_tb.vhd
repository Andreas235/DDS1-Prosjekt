library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_vlnw_controller_sched is
end tb_vlnw_controller_sched;

architecture sim of tb_vlnw_controller_sched is
    -- DUT ports
    signal clk, rst, start, monpro_done : std_logic := '0';
    signal vlnw_sel, vlnw_done          : std_logic;
    signal read_precompute_reg          : std_logic_vector(3 downto 0);
    signal vlnw_schedule0, vlnw_schedule1 : std_logic_vector(255 downto 0);

    -- Simulation logging
    file log_file : text open write_mode is "vlnw_sim_log.txt";

    -- DUT declaration
    component VLNW_Controller_Sched
        port(
            clk, rst, start, monpro_done : in  std_logic;
            vlnw_schedule0, vlnw_schedule1 : in  std_logic_vector(255 downto 0);
            vlnw_sel, vlnw_done : out std_logic;
            read_precompute_reg : out std_logic_vector(3 downto 0)
        );
    end component;

begin
    -- DUT instantiation
    dut: VLNW_Controller_Sched
        port map(
            clk => clk,
            rst => rst,
            start => start,
            monpro_done => monpro_done,
            vlnw_schedule0 => vlnw_schedule0,
            vlnw_schedule1 => vlnw_schedule1,
            vlnw_sel => vlnw_sel,
            vlnw_done => vlnw_done,
            read_precompute_reg => read_precompute_reg
        );

    -- Clock generation (10 ns period)
    clk <= not clk after 5 ns;

    -- Test process
    process
        variable L : line;
        variable cycle : integer := 0;
    begin
        -- Reset
        rst <= '1';
        write(L, string'("Applying reset...")); writeline(output, L);
        writeline(log_file, L);
        wait for 20 ns;
        rst <= '0';
        wait for 20 ns;

        -- Simple schedule: entry_count = 2, two entries
        -- entry0 = "000100" (precompute index 0001, 1 square)
        -- entry1 = "001011" (precompute index 0010, 4 squares)
        vlnw_schedule0 <= "0000010" & "000100" & "001011" & (236 downto 0 => '0');
        vlnw_schedule1 <= (others => '0');

        -- Start signal
        write(L, string'("Starting controller...")); writeline(output, L);
        writeline(log_file, L);
        start <= '1';
        wait for 10 ns;
        start <= '0';

        -- Generate MonPro done pulses periodically
        while vlnw_done = '0' loop
            wait for 50 ns;
            monpro_done <= '1';
            wait for 10 ns;
            monpro_done <= '0';
            wait for 10 ns;

            cycle := cycle + 1;
            write(L, string'("Cycle "));
            write(L, cycle);
            write(L, string'(": vlnw_sel="));
            write(L, std_logic'image(vlnw_sel));
            write(L, string'(" precompute="));
            write(L, " " & integer'image(to_integer(unsigned(read_precompute_reg))));
            write(L, string'(" done="));
            write(L, std_logic'image(vlnw_done));
            writeline(output, L);
            writeline(log_file, L);
        end loop;

        write(L, string'("VLNW exponentiation complete.")); 
        writeline(output, L);
        writeline(log_file, L);

        wait for 100 ns;
        assert false report "Simulation finished" severity failure;
    end process;
end sim;

