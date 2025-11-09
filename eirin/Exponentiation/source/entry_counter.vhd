----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 24.10.2025 10:08:41
-- Design Name: 
-- Module Name: entry_counter - rtl
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
use ieee.std_logic_misc.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity entry_counter is
    port(
        clk                      : in  std_logic;
        shift                    : in  std_logic;        
        number_of_entries        : in  std_logic_vector(6 downto 0);
        write                    : in  std_logic;        
        
        done                     : out std_logic
    );
end entry_counter;

architecture rtl of entry_counter is
    signal current_count : std_logic_vector(6 downto 0);
begin
    
     
    done <= not or_reduce(current_count);
	
	count : process (clk)
	begin
		if (rising_edge(clk)) then
			if write = '1' then
			     current_count <= number_of_entries;
            elsif shift = '1' then
                current_count <= std_logic_vector(unsigned(current_count) - 1);
            end if;   
		end if;
	end process count;

end rtl;
