----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.10.2025 19:06:06
-- Design Name: 
-- Module Name: shift_register - rtl
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;
use ieee.std_logic_misc.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity shift_register is
  port(
        clk                      : in  std_logic;
        reset                    : in  std_logic;
        load                     : in  std_logic;
        shift                    : in  std_logic;
        vlnw_schedule_0          : in  std_logic_vector(255 downto 0); 
        vlnw_schedule_1          : in  std_logic_vector(255 downto 0);

        start                    : out std_logic;   
        number_of_entries        : out std_logic_vector(6 downto 0); 
        read_precompute_adr      : out std_logic_vector(3 downto 0);
        square_count             : out std_logic_vector(1 downto 0);
        mult                     : out std_logic
   
    );
end shift_register;

architecture rtl of shift_register is
    signal vlnw_schedule      : std_logic_vector(501 downto 0); -- 502 long, first seven bits of vlnw_schedule0 are length, last 3 bits of vlnw_schedule0 is 0
begin
    vlnw_schedule_shift_register : process(clk, reset, load, shift, vlnw_schedule_0, vlnw_schedule_1)
    begin
        if reset = '0' then
            vlnw_schedule <= (others => '0');
            start <= '1';
        elsif rising_edge(clk) then
            if load = '1' then
                start <= '1';
                number_of_entries <= vlnw_schedule_0(255 downto 249);
                vlnw_schedule     <= vlnw_schedule_0(248 downto 3) & vlnw_schedule_1;
            elsif shift = '1' then
                vlnw_schedule <=  vlnw_schedule(495 downto 0) & "000000";
            end if;
        end if;
    end process vlnw_schedule_shift_register;
    
    read_precompute_adr <= vlnw_schedule(501 downto 498);
    mult <= or_reduce(vlnw_schedule(501 downto 498));
    square_count <= vlnw_schedule(497 downto 496);
    
end rtl;
