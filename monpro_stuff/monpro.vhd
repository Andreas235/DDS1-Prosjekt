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

entity monpro is
  port (
    clk       : in  std_logic;
    reset_n     : in  std_logic;
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
end monpro;

architecture rtl of monpro is
       
    -- Datapath registers
    -- Pipeline stage 0
    signal A_reg       : std_logic_vector(31 downto 0)  := (others  => '0');
    signal B_reg       : std_logic_vector(255 downto 0)  := (others  => '0');
    signal C_reg       : std_logic_vector(287 downto 0)  := (others  => '0');
    
    --Pipeline stage 1
    signal P_reg       : std_logic_vector(287 downto 0)  := (others  => '0');
    signal C2_reg      : std_logic_vector(287 downto 0)  := (others  => '0');
    
    --Pipeline stage 2
    signal P_HI        : std_logic_vector(143 downto 0) := (others  => '0');
    signal C2_HI       : std_logic_vector(143 downto 0) := (others  => '0');    
    signal sum_LO      : std_logic_vector(144 downto 0) := (others  => '0');
    
    -- Pipeline stage 3
    signal MAC_reg     : std_logic_vector(287 downto 0)  := (others  => '0');
    
    -- Pipeline stage 4
    signal M_reg       : std_logic_vector(31 downto 0)  := (others  => '0');
    signal U_reg       : std_logic_vector(287 downto 0) := (others  => '0');
    
    -- Result reg
    signal r_reg       : std_logic_vector(255 downto 0) := (others  => '0');
   
    -- Datapath wires
    signal A_next       : std_logic_vector(31 downto 0)  := (others  => '0');
    signal B_next       : std_logic_vector(255 downto 0)  := (others  => '0');
    signal C_next       : std_logic_vector(287 downto 0)  := (others  => '0');
    signal m_next       : std_logic_vector(31 downto 0)  := (others  => '0');
    signal u_next       : std_logic_vector(287 downto 0)  := (others  => '0');
    signal r_next       : std_logic_vector(255 downto 0)  := (others  => '0');

    -- Control signals
    signal index_op     : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Reset, 10: Increment
    signal mux_1_2_sel  : std_logic_vector(1 downto 0) := (others => '0'); -- 00: Nothing, 01: Ai*B,  10: u0*n_prime, 11: M_reg*n
    signal mux_3_sel    : std_logic := '0';
    signal mux_4_sel    : std_logic := '0';
    signal shift_enable : std_logic := '0';
    
    -- Pipeline stage 0
    signal write_A      : std_logic := '0';
    signal write_B      : std_logic := '0';    
    signal write_C      : std_logic := '0';   
    
    -- Pipeline stage 1
    signal write_P      : std_logic := '0';    
    signal write_C2     : std_logic := '0';  
    
    -- Pipeline stage 2
    signal write_sum_LO : std_logic := '0';   
    signal write_P_HI   : std_logic := '0';    
    signal write_C2_HI  : std_logic := '0';   
      
    -- Pipeline stage 3
    signal write_MAC    : std_logic := '0'; 
       
    -- Pipeline stage 4
    signal write_M      : std_logic := '0';
    signal write_U      : std_logic := '0';
    
    -- Other
    signal write_r      : std_logic := '0';    
    signal reset_regs   : std_logic := '0';
    
    -- Constants
    constant none      : std_logic_vector(1 downto 0) := "00";
    constant AiB       : std_logic_vector(1 downto 0) := "01";
    constant u0np      : std_logic_vector(1 downto 0) := "10";
    constant mn        : std_logic_vector(1 downto 0) := "11";
    
    constant add_U     : std_logic := '1';
    constant add_zero  : std_logic := '0';
    
    constant U_minus_n : std_logic := '1';
    constant U_value   : std_logic := '0';
               
    constant hold      : std_logic_vector(1 downto 0) := "00";
    constant zero      : std_logic_vector(1 downto 0) := "01";
    constant increment : std_logic_vector(1 downto 0) := "10";
    
    type state_t is (
        idle,
        load_operands_1,
        mul_1,
        add_1_1,
        add_1_2,
        write_U_1,
        load_operands_2,
        mul_2,
        add_2_1,
        add_2_2,
        write_U_2,
        load_operands_3,
        mul_3,
        add_3_1,
        add_3_2,
        write_U_3,
        wait_shift_U,
        compare_and_subtract,
        finished
    );
        
    -- Control registers
    signal state, state_next : state_t := idle;
    signal index    : integer range 0 to 7 := 0;
    
begin
    r <= r_reg;
    
    fsm : process(state, start)    
    begin
        -- Output signals
        busy        <= '0';
        done        <= '0';
        -- Control signals
        index_op        <= hold;
        mux_1_2_sel     <= none;
        mux_3_sel       <= '0';
        mux_4_sel       <= '0';
        shift_enable    <= '0';
        -- Pipeline stage 0
        write_A         <= '0';
        write_B         <= '0';        
        write_C         <= '0';
        -- Pipeline stage 1
        write_P         <= '0';
        write_C2        <= '0';
        -- Pipeline stage 2
        write_sum_LO    <= '0';
        write_P_HI      <= '0';        
        write_C2_HI     <= '0';
        -- Pipeline stage 3
        write_MAC       <= '0';
        -- Pipeline stage 4
        write_M         <= '0';
        write_U         <= '0';
        -- Result regs
        write_r <= '0';
                
        reset_regs      <= '0';
        state_next      <= state;
               
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
                write_A     <= '1';
                write_B     <= '1';        
                write_C     <= '1';
                state_next  <= mul_1;
                
            when mul_1 =>
                busy <= '1';
                write_P <= '1';
                write_C2 <= '1';
                state_next  <= add_1_1;
           
            when add_1_1 =>
                busy       <= '1';
                write_P_HI  <= '1';
                write_C2_HI  <= '1';
                write_sum_LO  <= '1';
                state_next <= add_1_2;
                                
            when add_1_2 =>
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
                write_A     <= '1';
                write_B     <= '1';        
                write_C     <= '1';
                state_next  <= mul_2;
                
            when mul_2 =>
                busy <= '1';
                write_P <= '1';
                write_C2 <= '1';
                state_next  <= add_2_1;
                
            when add_2_1 =>
                busy       <= '1';
                write_P_HI  <= '1';
                write_C2_HI  <= '1';
                write_sum_LO  <= '1';
                state_next <= add_2_2;
                                
            when add_2_2 =>
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
                write_A     <= '1';
                write_B     <= '1';        
                write_C     <= '1';
                state_next  <= mul_3;
                
            when mul_3 =>
                busy <= '1';
                write_P <= '1';
                write_C2 <= '1';
                state_next  <= add_3_1;
                
            when add_3_1 =>
                busy       <= '1';
                write_P_HI  <= '1';
                write_C2_HI  <= '1';
                write_sum_LO  <= '1';
                state_next <= add_3_2;
                                
            when add_3_2 =>
                busy       <= '1';
                write_MAC  <= '1';
                state_next <= write_U_3;
                
            when write_U_3 =>
                busy       <= '1';
                shift_enable <= '1';
                write_U    <= '1';
                if index = 7 then
                    index_op   <= zero;
                    state_next <= compare_and_subtract;
                else
                   index_op   <= increment;
                   state_next <= load_operands_1;
               end if;
            -- End of main loop
            
            -- After 8 iterations
            when wait_shift_U =>
                busy       <= '1';
                state_next <= compare_and_subtract;
                
            when compare_and_subtract =>
                busy       <= '1';
                write_r    <= '1';
                if unsigned(U_reg) >= unsigned(n) then
                    mux_4_sel <= U_minus_n;
                else
                    mux_4_sel <= U_value;
                end if;
                state_next <= finished;
                                           
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
                    A_next <= U_reg(31 downto 0);
                    B_next <= (255 downto 32 => '0') & n_prime;
                when mn =>
                    A_next <= M_reg;
                    B_next <= n;
                when others =>
                    A_next <= A_reg;
                    B_next <= B_reg;                
        end case;        
    end process mux_1_2 ;
    
    mux_3 : process(all)
    begin
        case mux_3_sel is
                when add_zero =>
                    C_next <= (others => '0');
                when add_U =>
                    C_next <= U_reg;
                when others =>
                    C_next <= C_reg;
        end case;        
    end process mux_3;
    
    shifter : process(all)
    begin
        case shift_enable is
            when '0' =>
                u_next <= MAC_reg;
            when '1' =>
                u_next <= std_logic_vector(unsigned(MAC_reg) srl 32);
            when others =>
                u_next <= U_reg;
        end case;       
    end process shifter;
    
    mux_4 : process(all)
    begin
        case mux_4_sel is
                when U_minus_n =>
                    r_next <= std_logic_vector(unsigned(U_reg(255 downto 0)) - unsigned(n));
                when U_value =>
                    r_next <= U_reg(255 downto 0);
                when others =>
                    r_next <= U_reg(255 downto 0);
        end case;        
    end process mux_4;
                   
	update_state : process (clk)
	begin
        if (rising_edge(clk)) then
            state <= state_next;
                if reset_n = '0' then
                    state <= idle;
                end if;			
		end if;
	end process update_state;
	
	update_regs : process (clk)
	begin
        if (rising_edge(clk)) then
            if reset_n = '0' or reset_regs = '1' then
                -- Pipeline stage 0
                A_reg      <= (others => '0');
                B_reg      <= (others => '0');
                C_reg      <= (others => '0');
                -- Pipeline stage 1
                P_reg      <= (others => '0');
                C2_reg     <= (others => '0');
                -- Pipeline stage 2
                P_HI       <= (others => '0');
                C2_HI      <= (others => '0');
                sum_LO     <= (others => '0');
                -- Pipeline stage 3
                MAC_reg    <= (others => '0');
                -- Pipeline stage 4
                M_reg      <= (others => '0');
                U_reg      <= (others => '0');
                -- Other
                r_reg      <= (others => '0');
                index      <= 0;
            else     
                -- Pipeline stage 0
                if write_A = '1' then
                    A_reg <= A_next;
                end if;
                if write_B = '1' then
                    B_reg <= B_next;
                end if;                
                if write_C = '1' then
                    C_reg <= C_next;
                end if;              
                
                -- Pipeline stage 1
                if write_P = '1' then
                    P_reg <= std_logic_vector(unsigned(A_reg) * unsigned(B_reg));
                end if;                  
                if write_C2 = '1' then
                    C2_reg <= C_reg;
                end if;   
                
                -- Pipeline stage 2
                if write_P_HI = '1' then
                    P_HI <= P_reg(287 downto 144);
                end if;  
                if write_C2_HI = '1' then
                    C2_HI <= C2_reg(287 downto 144);
                end if; 
                if write_sum_LO = '1' then
                    sum_LO <= std_logic_vector(resize(unsigned(P_reg(143 downto 0)), 145) + resize(unsigned(C2_reg(143 downto 0)), 145));
                end if; 
                
                -- Pipeline stage 3
                if write_MAC = '1' then
                    MAC_reg(287 downto 144)  <= std_logic_vector(unsigned(P_HI) + unsigned(C2_HI) + resize(unsigned(sum_LO(144 downto 144)), 144));
                    MAC_reg(143 downto 0)    <= sum_LO(143 downto 0);
                end if;
                
                -- Pipeline stage 4
                if write_U = '1' then
                    U_reg <= u_next;
                end if;
                if write_M = '1' then
                    M_reg <= MAC_reg(31 downto 0);
                end if;
                
                if write_r = '1' then
                    r_reg <= r_next;
                end if;
                
                -- Index counter             
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