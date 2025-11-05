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
    -- Registers
    signal p     : std_logic_vector(287 downto 0) := (others  => '0');
    signal u     : std_logic_vector(287 downto 0) := (others  => '0');
    signal index    : integer range 0 to 7 := 0;
    
    -- Signals
    signal index_op : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Reset, 10: Increment
    signal mult_sel : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Ai*B,  10: u0*n_prime, 11: m*n
    signal write_u : std_logic_vector(1 downto 0) := (others => '0');  -- 00: Nothing, 01: u+p,   10: >> 32
    signal idle_reset : std_logic := '0';
    
    type state_t is (
        idle,
        finished,
        mult_AB_shift_u, 
        add_uAB, 
        mult_u0np, 
        mult_mn,
        add_umn,
        final_shift
        );
    signal state, state_next : state_t := idle;
    
begin
    r <= u(255 downto 0);
    
    process(state, start)    
    begin
        case state is
            when idle =>
                busy <= '0';
                done <= '0';     
                mult_sel <= "00";   
                write_u <= "10";
                index_op <= "00";
                idle_reset <= '1';
                if start = '1' then
                    state_next <= mult_AB_shift_u;
                else
                    state_next <= idle;
                end if;
                
            when finished =>
                busy <= '0';
                done <= '1';
                mult_sel <= "00"; 
                write_u <= "00";  
                idle_reset <= '0';
                state_next <= idle;
                                
            when mult_AB_shift_u =>
                busy <= '1';
                done <= '0';     
                mult_sel <= "01";   
                write_u <= "10";
                index_op <= "00";
                idle_reset <= '0';
                state_next <= add_uAB;

            when add_uAB =>
                busy <= '1';
                done <= '0';
                mult_sel <= "00";  
                write_u <= "01";  
                idle_reset <= '0';
                index_op <= "00"; 
                state_next <= mult_u0np; 
            
            when mult_u0np =>
                busy <= '1';
                done <= '0';
                mult_sel <= "10";
                write_u <= "00";  
                index_op <= "00"; 
                idle_reset <= '0';
                state_next <= mult_mn; 
                
            when mult_mn =>
                busy <= '1';
                done <= '0';
                mult_sel <= "11";
                write_u <= "00";  
                index_op <= "00"; 
                idle_reset <= '0';
                state_next <= add_umn;
            
            when add_umn =>
                busy <= '1';
                done <= '0';
                mult_sel <= "00";
                write_u <= "01";  
                idle_reset <= '0';
                if index = 7 then
                    index_op <= "01"; -- Reset
                    state_next <= final_shift;
                else
                   index_op <= "10"; -- Inc
                   state_next <= mult_AB_shift_u;
               end if; 
            
            when final_shift =>
                busy <= '1';
                done <= '0';  
                mult_sel <= "00";
                write_u <= "10";  
                idle_reset <= '0';                
                index_op <= "00";  -- Nothing
                idle_reset <= '0';
                state_next <= finished;
                                                              
        end case;
    end process;
    
	update_state : process (clk)
	begin
        if (rising_edge(clk)) then
            state <= state_next;
                if reset = '0' then
                    state <= idle;
                end if;			
		end if;
	end process update_state;
	
	update_regs : process (clk)
	begin
        if (rising_edge(clk)) then
            if reset = '0' or idle_reset = '1' then
                p <= (others => '0');
                u <= (others => '0');
                index <= 0;
            else             
                case mult_sel is
                    when "01" =>
                        p <= std_logic_vector(unsigned(A(32*(index+1) - 1 downto 32*index)) * unsigned(B));
                    when "10" =>
                        p <= std_logic_vector(unsigned(u(31 downto 0)) * unsigned((255 downto 32 => '0') & n_prime));
                    when "11" =>
                        p <= std_logic_vector(unsigned(p(31 downto 0)) * unsigned(n));   
                    when others =>
                        p <= p;         
                end case;
                
                case write_u is
                    when "01" =>
                        u <= std_logic_vector(unsigned(u) + unsigned(p));
                    when "10" =>
                        u <= std_logic_vector(unsigned(u) srl 32);
                    when others =>
                        u <= u;
                end case;
                
                case index_op is
                    when "01" =>
                        index <= 0;
                    when "10" =>
                        index <= index + 1;
                    when others =>
                        index <= index;
                end case;
            end if;
        end if;
	end process update_regs;
end rtl;
