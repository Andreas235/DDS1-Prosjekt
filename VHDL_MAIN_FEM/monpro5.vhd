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

entity monpro5 is
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    -- Control
    start     : in  std_logic;
    busy      : out std_logic;
    done      : out std_logic;
    -- Operands
    operand   : in  std_logic_vector(31 downto 0);
    n         : in  std_logic_vector(31 downto 0);
    n_prime   : in  std_logic_vector(31 downto 0); -- -n^{-1} mod 2^32
    new_data  : in  std_logic_vector(1 downto 0)
);
end monpro5;

architecture rtl of monpro5 is

    -- Input registers
    signal A_reg : std_logic_vector(255 downto 0) := (others  => '0');
    signal B_reg : std_logic_vector(255 downto 0) := (others  => '0');
    signal n_reg : std_logic_vector(255 downto 0) := (others  => '0');
    
    -- Output register
    signal r     : std_logic_vector(255 downto 0) := (others  => '0');
       
    -- Datapath registers
    signal m        : std_logic_vector(31 downto 0)  := (others  => '0');
    signal u        : std_logic_vector(287 downto 0) := (others  => '0');
    
    -- Datapath signals
    signal mul_A        : std_logic_vector(31 downto 0) := (others  => '0');
    signal mul_B        : std_logic_vector(255 downto 0) := (others  => '0');
    signal prod         : std_logic_vector(287 downto 0) := (others  => '0');
    signal add_1        : std_logic_vector(287 downto 0) := (others  => '0');
    signal sum          : std_logic_vector(287 downto 0) := (others  => '0');
    signal shifted_u    : std_logic_vector(287 downto 0) := (others  => '0');
    signal u_next       : std_logic_vector(287 downto 0) := (others  => '0');
    signal m_next       : std_logic_vector(31 downto 0) := (others  => '0');
    
    -- Control signals
    signal index_op    : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Reset, 10: Increment
    signal mul_sel     : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Ai*B,  10: u0*n_prime, 11: m*n
    signal write_m_or_u      : std_logic_vector(1 downto 0) := (others => '0');  -- 00: Nothing, 01: m,   10: u
    signal u_shift_or_acc     : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: u = u + product, 10: u >> 32,
    signal reset_regs  : std_logic := '0';
      
    constant none : std_logic_vector(1 downto 0) := "00";
    constant AiB  : std_logic_vector(1 downto 0) := "01";
    constant u0np : std_logic_vector(1 downto 0) := "10";
    constant mn   : std_logic_vector(1 downto 0) := "11";
    
    constant wr_u      : std_logic_vector(1 downto 0) := "01";
    constant wr_m      : std_logic_vector(1 downto 0) := "10";
    
    constant acc      : std_logic_vector(1 downto 0) := "01";
    constant shift    : std_logic_vector(1 downto 0) := "10";
    
    constant hold      : std_logic_vector(1 downto 0) := "00";
    constant zero      : std_logic_vector(1 downto 0) := "01";
    constant increment : std_logic_vector(1 downto 0) := "10";
    
    type state_t is (
        idle,
        finished,
        step_1,
        step_2,
        step_3,
        step_4
    );
        
    -- Control registers
    signal state, state_next : state_t := idle;
    signal index    : integer range 0 to 7 := 0;
    
begin

    update_input_regs : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '0' then
                A_reg <= (others => '0');
                B_reg <= (others => '0');
                n_reg <= (others => '0');
            else    
                case new_data is
                    when "01" =>
                        A_reg <= A_reg(223 downto 0) & operand;
                        n_reg <= n_reg(223 downto 0) & n;
                    when "10" =>
                        B_reg <= B_reg(223 downto 0) & operand;
                    when others =>
                        A_reg <= A_reg;
                        B_reg <= B_reg;
                        n_reg <= n_reg;
                end case;
            end if;
        end if;     
    end process update_input_regs;

    prod <= std_logic_vector(unsigned(mul_A) * unsigned(mul_B));
    sum  <= std_logic_vector(unsigned(add_1) + unsigned(prod));
    shifted_u <= std_logic_vector(unsigned(u) srl 32);
    r <= u(255 downto 0);
    
    datapath_combinatorial : process(all)
    begin
    mul_A   <= (others => '0');
    mul_B   <= (others => '0');
    add_1   <= (others => '0');
    m_next  <= m;
    u_next  <= u;
    
        case mul_sel is
            when AiB =>
                mul_A <= A_reg(32*(index+1) - 1 downto 32*index);
                mul_B <= B_reg;
            when u0np =>
                mul_A <= u(31 downto 0);
                mul_B <= (255 downto 32 => '0') & n_prime;
            when mn =>
                mul_A <= m;
                mul_B <= n_reg;
            when others =>
                null;
        end case;    
        
        case write_m_or_u is
            when wr_m =>
                add_1 <= (others => '0');
                m_next <= sum(31 downto 0);
            when wr_u =>
                add_1 <= u;
                case u_shift_or_acc is
                    when acc =>
                        u_next <= sum;
                    when shift =>
                        u_next <= shifted_u;
                    when others =>
                        null;
                end case;
            when others =>
                null;
        end case;
        
    end process datapath_combinatorial;
        
    fsm : process(state, start)    
    begin
        busy        <= '0';
        done        <= '0';
        mul_sel     <= none;
        write_m_or_u <= none;
        u_shift_or_acc <= none;
        index_op    <= hold;
        reset_regs  <= '0';
        state_next  <= state;
               
        case state is
            when idle =>
                reset_regs <= '1';
                if start = '1' then
                    state_next <= step_1;
                else
                    state_next <= idle;
                end if;
                                               
            when step_1 =>
                busy       <= '1';
                mul_sel    <= AiB;   
                write_m_or_u <= wr_u;
                u_shift_or_acc <= acc;
                state_next <= step_2;
                
            when step_2 =>
                busy       <= '1';
                mul_sel    <= u0np;   
                write_m_or_u <= wr_m;
                u_shift_or_acc <= none;
                state_next <= step_3;
                
            when step_3 =>
                busy       <= '1';
                mul_sel    <= mn;   
                write_m_or_u <= wr_u;
                u_shift_or_acc <= acc;
                state_next <= step_4;
                
            when step_4 =>
                busy       <= '1';
                mul_sel    <= none;   
                write_m_or_u <= wr_u;
                u_shift_or_acc <= shift;
                if index = 7 then
                    index_op   <= zero;
                    state_next <= finished;
                else
                   index_op   <= increment;
                   state_next <= step_1;
               end if;    
               
            when finished =>
                done       <= '1';
                state_next <= idle;
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
                m        <= (others => '0');
                u        <= (others => '0');
                index    <= 0;
            else      
                u <= u_next;
                m <= m_next;                
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
