----------------------------------------------------------------------------------
-- Company: 
-- Engineer:  
--  fem
-- Create Date: 23.10.2025 15:48:22
-- Design Name: 
-- Module Name: vlnw_controller - rtl
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


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.std_logic_misc.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity vlnw_controller is
  port(
        clk                      : in  std_logic;
        reset                    : in  std_logic;
        load                     : in  std_logic;
        monpro_done              : in  std_logic;        
        vlnw_schedule_0          : in  std_logic_vector(255 downto 0); 
        vlnw_schedule_1          : in  std_logic_vector(255 downto 0);

        read_precompute_adr      : out std_logic_vector(3 downto 0);
        done                     : out std_logic;
        monpro_op                : out std_logic_vector(1 downto 0)

    );
end vlnw_controller;

architecture rtl of vlnw_controller is
    signal vlnw_schedule      : std_logic_vector(501 downto 0); -- 502 long, first seven bits of vlnw_schedule0 are length, last 3 bits of vlnw_schedule0 is 0
    signal shift              : std_logic;
    signal mult               : std_logic;
    signal counter_done       : std_logic;

    
begin

    vlnw_schedule_shift_register : process(clk)
    begin
        if rising_edge(clk) then
            if load = '1' then
                vlnw_schedule <= vlnw_schedule_0(248 downto 3) & vlnw_schedule_1;
            elsif shift = '1' then
                vlnw_schedule <=  vlnw_schedule(495 downto 0) & "000000";
            end if;
        end if;
    end process vlnw_schedule_shift_register;
          
    i_fsm: entity work.fsm
    port map(
        clk          => clk,
        load         => load,
        done         => counter_done,
        monpro_done  => monpro_done,
        square_count => vlnw_schedule(497 downto 496),
        mult         => mult, 
        shift        => shift,
        op           => monpro_op
    );    
    
    i_entry_counter: entity work.entry_counter
        port map (
            clk               => clk,
            shift             => shift,
            number_of_entries => vlnw_schedule_0(255 downto 249),
            write             => load,
            done              => counter_done
        );
        
    read_precompute_adr <= vlnw_schedule(501 downto 498);
    mult <= or_reduce(vlnw_schedule(501 downto 498));
    done <= counter_done;
end rtl;
