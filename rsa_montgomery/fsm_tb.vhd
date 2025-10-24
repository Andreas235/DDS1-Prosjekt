library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fsm_tb is
end fsm_tb;

architecture sim of fsm_tb is

    -- DUT signals
    signal clk          : std_logic := '0';
    signal mult         : std_logic := '0';
    signal mult         : std_logic := '0';
    signal monpro_done  : std_logic := '0';
    signal square_count : std_logic_vector(1 downto 0) := "00";
    signal mult         : std_logic := '0';
    signal shift        : std_logic;
    signal op           : std_logic_vector(1 downto 0);

    constant CLK_PERIOD  : time := 10 ns;
    constant MONPRO_TIME : time := 30 ns;
    
begin
    -- DUT instantiation
    uut: entity work.fsm
        port map(
            clk          => clk,
            start        => start,
            monpro_done  => monpro_done,
            square_count => square_count,
            mult         => mult,
            shift        => shift,
            op           => op
        );

    -- Clock
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Stimulus
    stim_proc : process
    begin
        -- Ensure everything starts known
        start <= '0';
        monpro_done <= '0';
        square_count <= "00";
        mult <= '0';



        -- Case 1: square_count = "11" (SQUARE_4 path)
        report "Starting test: square_count = 11";
        start <= '1';
        square_count <= "11";
        mult <= '1';
        wait for CLK_PERIOD;

        -- Pulse monpro_done to let FSM advance through squares
        -- pulse timings chosen so the combinational logic and regs update
        wait for MONPRO_TIME;
        monpro_done <= '1';
        start <= '0';

        wait for CLK_PERIOD;
        monpro_done <= '0';
        start <= '1';

        wait for MONPRO_TIME;
        monpro_done <= '1';
        start <= '0';

        wait for CLK_PERIOD;
        monpro_done <= '0';

        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
       
        start <= '1';

        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';

        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
      
        report "Starting test: square_count = 01";
        square_count <= "01";
        mult <= '0';
        
        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
        
        start <= '0';

        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
    
        report "Starting test: square_count = 10";
        square_count <= "10";
        mult <= '1';
        
        wait for 20 ns;
        start <= '1';
        
        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
        
        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';  
        
        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
        
        wait for MONPRO_TIME;
        monpro_done <= '1';
        wait for CLK_PERIOD;
        monpro_done <= '0';
        
        square_count <= "00";
        mult <= '0';       
        start <= '0';
        
        wait for MONPRO_TIME;

        report "Testbench finished";
        wait;
    end process;

end sim;


