----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.11.2025 13:27:23
-- Design Name: 
-- Module Name: monpro2 - rtl
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
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity monpro2 is
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    -- Control
    start     : in  std_logic;
    busy      : out std_logic;
    done      : out std_logic;
    -- Operands
    A         : in  std_logic_vector(255 downto 0);
    B         : in  std_logic_vector(255 downto 0);
    n         : in  std_logic_vector(255 downto 0);
    n_prime   : in  std_logic_vector(31 downto 0); -- -n^{-1} mod 2^32
    -- Result
    r         : out std_logic_vector(255 downto 0)
  );
end monpro2;

architecture rtl of monpro2 is
    signal u    : std_logic_vector(287 downto 0) := (others  => '0');

    signal mul_A    : std_logic_vector(31 downto 0) := (others  => '0');
    signal mul_B    : std_logic_vector(255 downto 0) := (others  => '0');
    signal prod_288 : std_logic_vector(287 downto 0) := (others  => '0');
  
    signal i_idx    : integer range 0 to 7 := 0;
    
    type state_t is (
        idle,
        mult_AB, 
        add_uAB, 
        mult_u0np, 
        mult_mn,
        add_umn,
        shift_r32,
        final
        );
    signal state, state_next : state_t := idle;
    
begin
    prod_288 <= std_logic_vector(unsigned(mul_A) * unsigned(mul_B));   
    r <= u(255 downto 0);
    
    process(state, start)    
    begin
        case state is
        
            when idle =>
                u         <= (others => '0');
                mul_A     <= (others => '0');
                mul_B     <= (others => '0');
                
                busy <= '0';
                done <= '0';
                if start = '1' then
                    state_next <= mult_AB;
                else
                    state_next <= idle;
                end if;
                                
            when mult_AB =>
                busy <= '1';
                done <= '0';            
                mul_A <= A(32*(i_idx+1) - 1 downto 32*i_idx);
                mul_B <= B;
                state_next <= add_uAB;
            
            when add_uAB =>
                busy <= '1';
                done <= '0';
                u <= std_logic_vector(unsigned(u) + unsigned(prod_288));
                state_next <= mult_u0np;
            
            when mult_u0np =>
                busy <= '1';
                done <= '0';
                mul_A <= u(31 downto 0);
                mul_B <= (255 downto 32 => '0') & n_prime;
                state_next <= mult_mn; 
                
            when mult_mn =>
                busy <= '1';
                done <= '0';
                mul_A <= prod_288(31 downto 0);
                mul_B <= n;
                state_next <= add_umn;
            
            when add_umn =>
                busy <= '1';
                done <= '0';
                u <= std_logic_vector(unsigned(u) + unsigned(prod_288));
                state_next <= shift_r32;
             
            when shift_r32 =>
                busy <= '1';
                done <= '0';
                u <= std_logic_vector(unsigned(u) srl 32);
                if i_idx >= 7 then
                    i_idx <= 0;
                    state_next <= final;
                else
                   i_idx <= i_idx + 1;
                   state_next <= mult_AB;
               end if; 
               
            when final =>
                done <= '1';  
                state_next <= idle;          
        end case;
    end process;
    
	update_state : process (clk)
	begin
		if (rising_edge(clk)) then
			state <= state_next;
		end if;
	end process update_state;
end rtl;
