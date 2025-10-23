library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

entity shift_register_tb is
end shift_register_tb;

architecture sim of shift_register_tb is

    -- DUT signals
    signal clk                : std_logic := '0';
    signal reset              : std_logic := '0';  -- active low
    signal load               : std_logic := '0';
    signal shift              : std_logic := '0';
    signal vlnw_schedule_0    : std_logic_vector(255 downto 0) := (others => '0');
    signal vlnw_schedule_1    : std_logic_vector(255 downto 0) := (others => '0');

    -- DUT outputs
    signal start              : std_logic;
    signal number_of_entries  : std_logic_vector(6 downto 0);
    signal read_precompute_adr: std_logic_vector(3 downto 0);
    signal square_count       : std_logic_vector(1 downto 0);
    signal mult               : std_logic;

    constant CLK_PERIOD : time := 10 ns;

begin
    --------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------
    uut: entity work.shift_register
        port map(
            clk                 => clk,
            reset               => reset,
            load                => load,
            shift               => shift,
            vlnw_schedule_0     => vlnw_schedule_0,
            vlnw_schedule_1     => vlnw_schedule_1,
            start               => start,
            number_of_entries   => number_of_entries,
            read_precompute_adr => read_precompute_adr,
            square_count        => square_count,
            mult                => mult
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
        -- Apply reset
        ----------------------------------------------------------------
        reset <= '0';
        wait for 25 ns;
        reset <= '1';
        wait for 20 ns;

        ----------------------------------------------------------------
        -- Load an example schedule
        ----------------------------------------------------------------
        report "Loading schedule";

        -- Example data: length = 8 entries ("0001000")
        vlnw_schedule_0(255 downto 249) <= "0000010";
        vlnw_schedule_0(248 downto 3)  <= (others => '0');
        vlnw_schedule_1                <= (others => '0');
        vlnw_schedule_0(248 downto 243) <= "111111";
        vlnw_schedule_0(242 downto 237) <= "000000";


        load <= '1';
        wait for CLK_PERIOD;
        load <= '0';
        wait for CLK_PERIOD * 2;

        ----------------------------------------------------------------
        -- Shift sequence to move through entries
        ----------------------------------------------------------------
--        report "Starting shift sequence";

--        for i in 0 to 4 loop
--            shift <= '1';
--            wait for CLK_PERIOD;
--            shift <= '0';
--            wait for CLK_PERIOD * 2;

--            -- Optional: print current entry for debug
--            report "Current entry (MSBs): " & 
--                integer'image(to_integer(unsigned(read_precompute_adr))) &
--                ", square_count: " & integer'image(to_integer(unsigned(square_count))) &
--                ", mult: " & std_logic'image(mult);
--        end loop;

        ----------------------------------------------------------------
        -- Finish simulation
        ----------------------------------------------------------------
        wait for 100 ns;
        report "Simulation finished";
        wait;
    end process;

end sim;
