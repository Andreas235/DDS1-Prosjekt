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

entity monpro5_1 is
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
end monpro5_1;

architecture rtl of monpro5_1 is
       
    -- Datapath registers
    -- Pipeline stage 0
    signal A_in       : std_logic_vector(31 downto 0)  := (others  => '0');
    signal B_in       : std_logic_vector(255 downto 0)  := (others  => '0');
    signal C_in       : std_logic_vector(287 downto 0)  := (others  => '0');
    --Pipeline stage 1
    signal P          : std_logic_vector(287 downto 0)  := (others  => '0');
    signal C          : std_logic_vector(287 downto 0)  := (others  => '0');
    --Pipeline stage 2
    signal P2         : std_logic_vector(287 downto 0)  := (others  => '0');
    signal C2         : std_logic_vector(287 downto 0)  := (others  => '0');    
    signal sum_73_LO  : std_logic_vector(72 downto 0) := (others  => '0');
    -- Pipeline stage 3
    signal P3         : std_logic_vector(287 downto 0)  := (others  => '0');
    signal C3         : std_logic_vector(287 downto 0)  := (others  => '0');    
    signal sum_145_LO : std_logic_vector(144 downto 0) := (others  => '0');    
    -- Pipeline stage 4
    signal P4         : std_logic_vector(287 downto 0)  := (others  => '0');
    signal C4         : std_logic_vector(287 downto 0)  := (others  => '0');    
    signal sum_73_HI  : std_logic_vector(72 downto 0) := (others  => '0'); 
    -- Pipeline stage 5    
    signal MAC     : std_logic_vector(287 downto 0)  := (others  => '0');
    -- Pipeline stage 6
    signal M          : std_logic_vector(31 downto 0)  := (others  => '0');
    signal U          : std_logic_vector(287 downto 0) := (others  => '0');
   
    -- Datapath wires
    signal A_next       : std_logic_vector(31 downto 0)  := (others  => '0');
    signal B_next       : std_logic_vector(255 downto 0)  := (others  => '0');
    signal C_next       : std_logic_vector(287 downto 0)  := (others  => '0');
    signal U_next           : std_logic_vector(287 downto 0)  := (others  => '0');

    -- Control signals
    signal index_op    : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Reset, 10: Increment
    signal mux_1_2_sel     : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Ai*B,  10: u0*n_prime, 11: M*n
    signal mux_3_sel    : std_logic := '0';
    signal shift_enable    : std_logic := '0';
  
    signal write_A_in       : std_logic := '0';
    signal write_B_in       : std_logic := '0';    
    signal write_C_in       : std_logic := '0';   
    
    signal write_P          : std_logic := '0';    
    signal write_C          : std_logic := '0';
     
    signal write_P2         : std_logic := '0';    
    signal write_C2         : std_logic := '0';  
    signal write_sum_73_LO  : std_logic := '0';   
    
    signal write_P3         : std_logic := '0';    
    signal write_C3         : std_logic := '0';      
    signal write_sum_145_LO : std_logic := '0'; 
      
    signal write_P4         : std_logic := '0';    
    signal write_C4         : std_logic := '0'; 
    signal write_sum_73_HI  : std_logic := '0';   
    
    signal write_MAC        : std_logic := '0';  
      
    signal write_M          : std_logic := '0';
    signal write_U          : std_logic := '0';
    
    signal reset_regs       : std_logic := '0';
     
    -- Constants
    constant none : std_logic_vector(1 downto 0) := "00";
    constant AiB  : std_logic_vector(1 downto 0) := "01";
    constant u0np : std_logic_vector(1 downto 0) := "10";
    constant mn   : std_logic_vector(1 downto 0) := "11";
    
    constant add_U : std_logic := '1';
    constant add_zero : std_logic := '0';
           
    constant hold      : std_logic_vector(1 downto 0) := "00";
    constant zero      : std_logic_vector(1 downto 0) := "01";
    constant increment : std_logic_vector(1 downto 0) := "10";
    
    type state_t is (
        idle,
        load_operands_1,
        mul_1,
        add_1_1,
        add_1_2,
        add_1_3,
        add_1_4,
        write_U_1,
        load_operands_2,
        mul_2,
        add_2_1,
        add_2_2,
        add_2_3,
        add_2_4,
        write_U_2,
        load_operands_3,
        mul_3,
        add_3_1,
        add_3_2,
        add_3_3,
        add_3_4,        
        write_U_3,
        finished
    );
        
    -- Control registers
    signal state, state_next : state_t := idle;
    signal index    : integer range 0 to 7 := 0;
    
begin
    r <= U(255 downto 0);
    
    fsm : process(state, start)    
    begin
        -- Output signals
        busy        <= '0';
        done        <= '0';
        -- Control signals
        index_op         <= hold;
        mux_1_2_sel      <= none;
        mux_3_sel        <= '0';
        shift_enable     <= '0';
        write_A_in       <= '0';
        write_B_in       <= '0';        
        write_C_in       <= '0';
        write_P          <= '0';
        write_C          <= '0';
        write_P2         <= '0';
        write_C2         <= '0';        
        write_sum_73_LO  <= '0';        
        write_P3         <= '0';
        write_C3         <= '0';
        write_sum_145_LO <= '0';
        write_P4         <= '0';
        write_C4         <= '0';        
        write_sum_73_HI  <= '0';       
        write_MAC        <= '0';
        write_M          <= '0';
        write_U          <= '0';
        reset_regs       <= '0';
        state_next       <= state;
               
        case state is
            when idle =>
                reset_regs <= '1';
                if start = '1' then
                    state_next <= load_operands_1;
                else
                    state_next <= idle;
                end if;
            
            -- Step 1 U := Ai * B                                  
            when load_operands_1 =>
                busy        <= '1';
                mux_1_2_sel <= AiB;
                mux_3_sel   <= add_U;
                write_A_in     <= '1';
                write_B_in     <= '1';        
                write_C_in     <= '1';
                state_next  <= mul_1;
                
            when mul_1 =>
                busy <= '1';
                write_P <= '1';
                write_C <= '1';
                state_next  <= add_1_1;
           
            when add_1_1 =>
                busy       <= '1';
                write_P2  <= '1';
                write_C2  <= '1';
                write_sum_73_LO  <= '1';
                state_next <= add_1_2;
                
            when add_1_2 =>
                busy       <= '1';
                write_P3  <= '1';
                write_C3  <= '1';
                write_sum_145_LO  <= '1';
                state_next <= add_1_3;                
                           
            when add_1_3 =>
                busy       <= '1';
                write_P4  <= '1';
                write_C4  <= '1';
                write_sum_73_HI  <= '1';
                state_next <= add_1_4;
                                
            when add_1_4 =>
                busy       <= '1';
                write_MAC  <= '1';
                state_next <= write_U_1;

            when write_U_1 =>
                busy       <= '1';
                write_U    <= '1';
                state_next <= load_operands_2;
                
            -- Step 2 M := U0 * N_prime                                  
            when load_operands_2 =>
                busy        <= '1';
                mux_1_2_sel <= u0np;
                mux_3_sel   <= add_zero;
                write_A_in     <= '1';
                write_B_in     <= '1';        
                write_C_in     <= '1';
                state_next  <= mul_2;
                
            when mul_2 =>
                busy <= '1';
                write_P <= '1';
                write_C <= '1';
                state_next  <= add_2_1;
                
            when add_2_1 =>
                busy       <= '1';
                write_P2  <= '1';
                write_C2  <= '1';
                write_sum_73_LO  <= '1';
                state_next <= add_2_2;
                
            when add_2_2 =>
                busy       <= '1';
                write_P3  <= '1';
                write_C3  <= '1';
                write_sum_145_LO  <= '1';
                state_next <= add_2_3;                
                           
            when add_2_3 =>
                busy       <= '1';
                write_P4  <= '1';
                write_C4  <= '1';
                write_sum_73_HI  <= '1';
                state_next <= add_2_4;
                                
            when add_2_4 =>
                busy       <= '1';
                write_MAC  <= '1';
                state_next <= write_U_2;
             
            when write_U_2 =>
                busy       <= '1';
                write_M    <= '1';
                state_next <= load_operands_3;                
                
            -- Step 3 U := (M*n + U) >> 32 
            when load_operands_3 =>
                busy        <= '1';
                mux_1_2_sel <= mn;
                mux_3_sel   <= add_U;
                write_A_in     <= '1';
                write_B_in     <= '1';        
                write_C_in     <= '1';
                state_next  <= mul_3;
                
            when mul_3 =>
                busy <= '1';
                write_P <= '1';
                write_C <= '1';
                state_next  <= add_3_1;
                
            when add_3_1 =>
                busy       <= '1';
                write_P2  <= '1';
                write_C2  <= '1';
                write_sum_73_LO  <= '1';
                state_next <= add_3_2;
                
            when add_3_2 =>
                busy       <= '1';
                write_P3  <= '1';
                write_C3  <= '1';
                write_sum_145_LO  <= '1';
                state_next <= add_3_3;                
                           
            when add_3_3 =>
                busy       <= '1';
                write_P4  <= '1';
                write_C4  <= '1';
                write_sum_73_HI  <= '1';
                state_next <= add_3_4;
                                
            when add_3_4 =>
                busy       <= '1';
                write_MAC  <= '1';
                state_next <= write_U_3;
                
            when write_U_3 =>
                busy       <= '1';
                shift_enable <= '1';
                write_U    <= '1';
                if index = 7 then
                    index_op   <= zero;
                    state_next <= finished;
                else
                   index_op   <= increment;
                   state_next <= load_operands_1;
               end if;
                           
            when finished =>
                done       <= '1';
                state_next <= idle;
        end case;
    end process fsm;    
    
    mux_1_2 : process(all)
    begin
        case mux_1_2_sel is
                when AiB =>
                    A_next <= A(32*(index+1) - 1 downto 32*index);
                    B_next <= B;
                when u0np =>
                    A_next <= U(31 downto 0);
                    B_next <= (255 downto 32 => '0') & n_prime;
                when mn =>
                    A_next <= M;
                    B_next <= n;
                when others =>
                    A_next <= A_in;
                    B_next <= B_in;                
        end case;        
    end process mux_1_2 ;
    
    mux_3 : process(all)
    begin
        case mux_3_sel is
                when add_zero =>
                    C_next <= (others => '0');
                when add_U =>
                    C_next <= U;
                when others =>
                    C_next <= C_in;
        end case;        
    end process mux_3 ;
    
    mux_4 : process(all)
    begin
        case shift_enable is
            when '0' =>
                U_next <= MAC;
            when '1' =>
                U_next <= std_logic_vector(unsigned(MAC) srl 32);
            when others =>
                U_next <= U;
        end case;       
    end process mux_4;
               
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
                -- Pipeline stage 0
                A_in       <= (others => '0');
                B_in       <= (others => '0');
                C_in       <= (others => '0');
                -- Pipeline stage 1
                P          <= (others => '0');
                C          <= (others => '0');
                -- Pipeline stage 2
                P2         <= (others => '0');
                C2         <= (others => '0');  
                sum_73_LO  <= (others => '0');  
                -- Pipeline stage 3
                P3         <= (others => '0');
                C3         <= (others => '0');  
                sum_145_LO <= (others => '0');  
                -- Pipeline stage 4
                P4         <= (others => '0');
                C4         <= (others => '0');  
                sum_73_HI  <= (others => '0');    
                -- Pipeline stage 5
                MAC        <= (others => '0');
                -- Pipeline stage 6
                M          <= (others => '0');
                U          <= (others => '0');
                index      <= 0;
            else      
                -- Pipeline stage 0
                if write_A_in = '1' then
                    A_in <= A_next;
                end if;
                if write_B_in = '1' then
                    B_in <= B_next;
                end if;                
                if write_C_in = '1' then
                    C_in <= C_next;
                end if;              
                  
                -- Pipeline stage 1
                if write_P = '1' then
                    P <= std_logic_vector(unsigned(A_in) * unsigned(B_in));
                end if;                  
                if write_C = '1' then
                    C <= C_in;
                end if;    
                
                -- Pipeline stage 2
                if write_C2 = '1' then
                    C2 <= C;
                end if;
                if write_P2 = '1' then
                    P2 <= P;
                end if;      
                if write_sum_73_LO = '1' then
                    sum_73_LO <= std_logic_vector(resize(unsigned(P(71 downto 0)), 73) + resize(unsigned(C(71 downto 0)), 73));
                end if;  
                
                -- Pipeline stage 3
                if write_P3 = '1' then
                    P3 <= P2;
                end if;  
                if write_C3 = '1' then
                    C3 <= C2;
                end if; 
                if write_sum_145_LO = '1' then
                    sum_145_LO(144 downto 72) <= std_logic_vector(resize(unsigned(P2(143 downto 72)), 73) + resize(unsigned(C2(143 downto 72)), 73) + resize(unsigned(sum_73_LO(72 downto 72)), 73));
                    sum_145_LO(71 downto 0) <= sum_73_LO(71 downto 0);
                end if; 
                
                -- Pipeline stage 4
                if write_P4 = '1' then
                    P4 <= P3;
                end if;  
                if write_C4 = '1' then
                    C4 <= C3;
                end if; 
                if write_sum_73_HI = '1' then
                    sum_73_HI <= std_logic_vector(resize(unsigned(P3(215 downto 144)), 73) + resize(unsigned(C3(215 downto 144)), 73) + resize(unsigned(sum_145_LO(144 downto 144)), 73));
                end if;   
                
                -- Pipeline stage 5
                if write_MAC = '1' then
                    MAC(287 downto 216)  <= std_logic_vector(unsigned(P4(287 downto 216)) + unsigned(C4(287 downto 216)) + resize(unsigned(sum_73_HI(72 downto 72)), 72));
                    MAC(215 downto 144)  <= sum_73_HI(71 downto 0);
                    MAC(143 downto 0)    <= sum_145_LO(143 downto 0);
                end if;
                
                -- Pipeline stage 6
                if write_U = '1' then
                    U <= U_next;
                end if;
                if write_M = '1' then
                    M <= MAC(31 downto 0);
                end if;
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