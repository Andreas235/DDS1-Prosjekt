----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.11.2025 13:51:07
-- Design Name: 
-- Module Name: multiplier - rtl
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


entity multiplier is
  port (
--    clk       : in  std_logic;
--    reset     : in  std_logic;
--    -- Control
--    start     : in  std_logic;
--    busy      : out std_logic;
--    done      : out std_logic;
    -- Operands
    Ai        : in  std_logic_vector(31 downto 0);
    B         : in  std_logic_vector(255 downto 0);
    -- Result
    r         : out std_logic_vector(287 downto 0)
  );
end multiplier;

architecture rtl of multiplier is
--    signal temp64 : std_logic_vector(63 downto 0);
begin
    
    r <= std_logic_vector(unsigned(Ai) * unsigned(B));

end rtl;






































