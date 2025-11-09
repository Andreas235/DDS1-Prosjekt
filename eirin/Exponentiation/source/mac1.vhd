----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08.11.2025 18:22:21
-- Design Name: 
-- Module Name: mac1 - rtl
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

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity mac1 is
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    -- Control
    start     : in  std_logic;
    done      : out std_logic;
    -- Operands
    A   : in  std_logic_vector(17 downto 0);
    B   : in  std_logic_vector(17 downto 0);
    C   : in  std_logic_vector(36 downto 0);
    r   : out std_logic_vector(36 downto 0)
);
end mac1;

architecture rtl of mac1 is
signal mult_result : std_logic_vector(35 downto 0);
signal mac_result  : std_logic_vector(36 downto 0);

begin
process(clk)
begin
    if rising_edge(clk) then
        mult_result <= std_logic_vector(unsigned(A) * unsigned(B));  -- stage 1
        mac_result  <= std_logic_vector(unsigned(mult_result) + unsigned(C));      -- stage 2
        r           <= mac_result;
    end if;
end process;

end rtl;
