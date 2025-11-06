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
    -- Datapath registers
    signal mul_A    : std_logic_vector(31 downto 0)  := (others  => '0');
    signal mul_B    : std_logic_vector(255 downto 0) := (others  => '0');
    signal p        : std_logic_vector(287 downto 0) := (others  => '0');
    signal sum_LO   : std_logic_vector(144 downto 0) := (others  => '0');
    signal add_A_HI : std_logic_vector(143 downto 0) := (others  => '0');
    signal add_B_HI : std_logic_vector(143 downto 0) := (others  => '0');
    signal u        : std_logic_vector(287 downto 0) := (others  => '0');
    
    -- Control signals
    signal index_op    : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Reset, 10: Increment
    signal mul_sel     : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Ai*B,  10: u0*n_prime, 11: m*n
    signal multiply    : std_logic                    := '0';
    signal add_stage_1 : std_logic                    := '0';
    signal write_u     : std_logic_vector(1 downto 0) := (others => '0');  -- 00: Nothing, 01: u+p,   10: >> 32
    signal reset_regs  : std_logic := '0';
      
    constant none : std_logic_vector(1 downto 0) := "00";
    constant AiB  : std_logic_vector(1 downto 0) := "01";
    constant u0np : std_logic_vector(1 downto 0) := "10";
    constant mn   : std_logic_vector(1 downto 0) := "11";
    
    constant adder      : std_logic_vector(1 downto 0) := "01";
    constant u_rshift32 : std_logic_vector(1 downto 0) := "10";
    
    constant hold      : std_logic_vector(1 downto 0) := "00";
    constant zero      : std_logic_vector(1 downto 0) := "01";
    constant increment : std_logic_vector(1 downto 0) := "10";
    
    type state_t is (
        idle,
        finished,
        load_mul_AB_shift_u,
        wait_mulAB,
        add_uAB_1, 
        add_uAB_2, 
        load_mul_u0np, 
        wait_mulu0np,
        load_mul_mn,
        wait_mulmn,
        add_umn_1,
        add_umn_2,
        final_shift
        );
        
    -- Control registers
    signal state, state_next : state_t := idle;
    signal index    : integer range 0 to 7 := 0;
    
begin
    r <= u(255 downto 0);
    
    fsm : process(state, start)    
    begin
        busy        <= '0';
        done        <= '0';
        mul_sel     <= none;
        multiply    <= '0';
        add_stage_1 <= '0';
        write_u     <= none;
        index_op    <= hold;
        reset_regs  <= '0';
        state_next  <= state;
               
        case state is
            when idle =>
                reset_regs <= '1';
                if start = '1' then
                    state_next <= load_mul_AB_shift_u;
                else
                    state_next <= idle;
                end if;
                
            when finished =>
                done       <= '1';
                state_next <= idle;
                                
            when load_mul_AB_shift_u =>
                busy       <= '1';
                mul_sel    <= AiB;   
                write_u    <= u_rshift32;
                state_next <= wait_mulAB;
                
            when wait_mulAB =>
                busy       <= '1';
                multiply   <= '1';
                state_next <= add_uAB_1;
          
            when add_uAB_1 =>
                busy        <= '1';
                add_stage_1 <= '1';  
                state_next  <= add_uAB_2;
                
            when add_uAB_2 =>
                busy       <= '1';
                write_u    <= adder;  
                state_next <= load_mul_u0np;
            
            when load_mul_u0np =>
                busy       <= '1';
                mul_sel    <= u0np;
                state_next <= wait_mulu0np; 
               
            when wait_mulu0np =>
                busy       <= '1';
                multiply   <= '1';
                state_next <= load_mul_mn;
                
            when load_mul_mn =>
                busy       <= '1';
                mul_sel    <= mn;
                state_next <= wait_mulmn;
                
            when wait_mulmn =>
                busy       <= '1';
                multiply   <= '1';
                state_next <= add_umn_1;
                       
            when add_umn_1 =>
                busy        <= '1';
                add_stage_1 <= '1';  
                state_next  <= add_umn_2;    
                 
            when add_umn_2 =>
                busy    <= '1';
                write_u <= adder;  
                if index = 7 then
                    index_op   <= zero;
                    state_next <= final_shift;
                else
                   index_op   <= increment;
                   state_next <= load_mul_AB_shift_u;
               end if; 
            
            when final_shift =>
                busy       <= '1';
                write_u    <= u_rshift32;  
                state_next <= finished;
                                                              
        end case;
    end process fsm;
    
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
            if reset = '0' or reset_regs = '1' then
                mul_A    <= (others => '0');
                mul_B    <= (others => '0');
                p        <= (others => '0');
                sum_LO   <= (others => '0');
                add_A_HI <= (others => '0');
                add_B_HI <= (others => '0');
                u        <= (others => '0');
                index    <= 0;
            else             
                case mul_sel is
                    when AiB =>
                        mul_A <= A(32*(index+1) - 1 downto 32*index);
                        mul_B <= B;
                    when u0np =>
                        mul_A <= u(31 downto 0);
                        mul_B <= (255 downto 32 => '0') & n_prime;
                    when mn =>
                        mul_A <= p(31 downto 0);
                        mul_B <= n;
                    when others =>
                        mul_A <= mul_A;
                        mul_B <= mul_B; 
                   end case;
                
                case multiply is
                    when '1' =>
                        p <= std_logic_vector(unsigned(mul_A) * unsigned(mul_B));
                    when others =>
                        p <= p;
                end case;
                
                case add_stage_1 is
                    when '1' =>
                        sum_LO <= std_logic_vector(resize(unsigned(p(143 downto 0)), 145) + resize(unsigned(u(143 downto 0)), 145));
                        add_A_HI <= p(287 downto 144);
                        add_B_HI <= u(287 downto 144);
                    when others =>
                        sum_LO <= sum_LO;
                        add_A_HI <= add_A_HI;
                        add_B_HI <= add_B_HI;
                end case;
                
                case write_u is
                    when adder =>
                        u(287 downto 144) <= std_logic_vector(unsigned(sum_LO(144 downto 144)) + unsigned(add_A_HI) + unsigned(add_B_HI));
                        u(143 downto 0)   <= sum_LO(143 downto 0);
                    when u_rshift32 =>
                        u <= std_logic_vector(unsigned(u) srl 32);
                    when others =>
                        u <= u;
                end case;
                
                case index_op is
                    when zero =>
                        index <= 0;
                    when increment =>
                        index <= index + 1;
                    when others =>
                        index <= index;
                end case;
            end if;
        end if;
	end process update_regs;
end rtl;
