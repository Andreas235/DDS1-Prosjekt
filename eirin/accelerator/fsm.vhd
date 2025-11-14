----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.10.2025 13:09:48
-- Design Name: 
-- Module Name: fsm - rtl
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

entity fsm is
    port(
        clk                      : in  std_logic;
        monpro_done              : in  std_logic;        
        square_count             : in  std_logic_vector(1 downto 0);
        mult                     : in  std_logic;        
        load                     : in  std_logic;        
        done                     : in  std_logic;        
        
        shift                    : out std_logic;
        op                       : out std_logic_vector(1 downto 0)
    );
end fsm;

architecture rtl of fsm is

    constant monpro_wait        : std_logic_vector(1 downto 0) := "00";
    constant monpro_square      : std_logic_vector(1 downto 0) := "01";
    constant monpro_multiply    : std_logic_vector(1 downto 0) := "10";
    
    type state_type is (
        STOP, READ, 
        SQUARE_4, SQUARE_3, SQUARE_2, SQUARE_1,
        MULTIPLY,
        SHIFT_state
    );
    signal state, state_next : state_type;

begin

    main_statemachine_process : process (state, load, done, monpro_done, square_count, mult)
    begin
    
        case(state) is
            when STOP =>
                shift <= '0';
                op <= monpro_wait;
                if load = '1' then
                    state_next <= READ;
                else
                    state_next <= STOP;
                end if;
                                
            when READ =>
                shift <= '0';
                op <= monpro_wait;
                if done = '1' then
                    state_next <= STOP;
                else
                    if square_count = "11" then
                        state_next <= SQUARE_4;
                    elsif square_count = "10" then
                        state_next <= SQUARE_3;
                    elsif square_count = "01" then
                        state_next <= SQUARE_2;
                    else
                        state_next <= SQUARE_1;
                    end if;
                end if;
                
            when SQUARE_4 =>
                shift <= '0';
                op <= monpro_square; 
                
                if monpro_done = '1' then
                    state_next <= SQUARE_3;
                else
                    state_next <= SQUARE_4;
                end if;
 
             when SQUARE_3 =>
                shift <= '0';
                op <= monpro_square; 
                if monpro_done = '1' then
                    state_next <= SQUARE_2;
                else
                    state_next <= SQUARE_3;
                end if;
              
             when SQUARE_2 =>
                shift <= '0';
                op <= monpro_square; 
                if monpro_done = '1' then
                    state_next <= SQUARE_1;
                else
                    state_next <= SQUARE_2;
                end if;
             
             when SQUARE_1 =>
                shift <= '0';
                op <= monpro_square; 
                if monpro_done = '1' then
                    if mult = '1' then
                        state_next <= MULTIPLY;
                    else
                        state_next <= SHIFT_state;
                    end if;
                else
                    state_next <= SQUARE_1;
                end if;
             
             when MULTIPLY =>
                shift <= '0';
                op <= monpro_multiply; 
                if monpro_done = '1' then
                    state_next <= SHIFT_state;
                else
                    state_next <= MULTIPLY;
                end if;   
                    
            when SHIFT_state =>
                shift <= '1';
                op <= monpro_wait; 
                state_next <= READ;
                
		end case;
	end process main_statemachine_process;


	update_state : process (clk)
	begin
		if (rising_edge(clk)) then
			state <= state_next;
		end if;
	end process update_state;

end rtl;