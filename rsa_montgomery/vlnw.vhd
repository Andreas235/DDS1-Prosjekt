library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity VLNW_Controller_Sched is
    port(
        clk                      : in  std_logic;
        rst                      : in  std_logic;
        start                    : in  std_logic;         -- Start exponentiation
        monpro_done              : in  std_logic;         -- MonPro handshake
        vlnw_schedule0           : in  std_logic_vector(255 downto 0); -- first 256-bit word
        vlnw_schedule1           : in  std_logic_vector(255 downto 0); -- second 256-bit word

        vlnw_sel                 : out std_logic;         -- 1=square, 0=multiply
        read_precompute_reg      : out std_logic_vector(3 downto 0);
        vlnw_done                : out std_logic

    );
end VLNW_Controller_Sched;

architecture rtl of VLNW_Controller_Sched is

    type state_type is (IDLE, FETCH, SQUARING, MULTIPLY, DONE);
    signal state, next_state : state_type;

    signal entry_count  : std_logic_vector(6 downto 0); -- total number of entries
    signal entry_index  : std_logic_vector(6 downto 0); -- current entry index (max 128 entries)
    signal sq_count     : std_logic_vector(1 downto 0); -- countdown squaring
    signal precompute_index    : std_logic_vector(3 downto 0);
    signal num_squares  : std_logic_vector(1 downto 0);

    -- Registers to hold current entry
    signal entry_word   : std_logic_vector(5 downto 0);

    -- Temporary storage for schedule
    signal vlnw_schedule: std_logic_vector(508 downto 0);

begin

    -- Combine schedule words into one 512-bit vector
    vlnw_schedule <= vlnw_schedule0(255 downto 3) & vlnw_schedule1;

    -- Sequential process: state and counters
    process(clk, rst)
    begin
        if rst = '1' then
            state       <= IDLE;
            entry_index <= (others => '0');
            sq_count    <= (others => '0');
            entry_count <= (others => '0');
            vlnw_done   <= '0';
            read_precompute_reg <= "0000";
        elsif rising_edge(clk) then
            state <= next_state;

            -- Squaring countdown
            if state = SQUARING and monpro_done = '1' then
                if unsigned(sq_count) > 0 then
                    sq_count <= std_logic_vector(unsigned(sq_count) - 1);
                end if;
            end if;

            -- Move to next entry
            if state = MULTIPLY and monpro_done = '1' then
                entry_index <= std_logic_vector(unsigned(entry_index) + 1);
            end if;

            -- Start: read schedule length
            if state = IDLE and start = '1' then
                entry_index <= "0000000";
                entry_count <= vlnw_schedule(508 downto 502); -- first 7 bits
            end if;

            -- Load new entry on FETCH
            if state = FETCH then
                -- Each entry is 6 bits
                entry_word <= vlnw_schedule(
                    508 - 7 - to_integer(unsigned(entry_index)) * 6 downto
                    508 - 7 - to_integer(unsigned(entry_index)) * 6 - 5
                );                
                precompute_index  <= entry_word(5 downto 2);
                num_squares <= std_logic_vector(unsigned(entry_word(1 downto 0)) + 1);
                sq_count   <= num_squares;
            end if;
            
            
        end if;
    end process;

    -- Combinational next-state and outputs
    process(state, entry_index, entry_count, sq_count, monpro_done)
    begin
        -- Default outputs
        next_state <= state;
        vlnw_sel   <= '1';
        vlnw_done  <= '0';
        read_precompute_reg <= "0000";
        
        case state is
            when IDLE =>
                vlnw_sel   <= '1';
                vlnw_done  <= '0';
                read_precompute_reg <= "0000";

                if start = '1' then
                    next_state <= FETCH;
                end if;

            when FETCH =>
                next_state <= SQUARING;
                vlnw_sel   <= '1'; -- first operation is square
                vlnw_done <= '0';
                read_precompute_reg <= precompute_index;
                
            when SQUARING =>
                vlnw_sel <= '1';
                vlnw_done <= '0';
                read_precompute_reg <= precompute_index;
                if monpro_done = '1' then
                    if unsigned(sq_count) = 0 then
                        if precompute_index = "0000" then
                            if unsigned(entry_index) = unsigned(entry_count) - 1 then
                                next_state <= DONE; -- done
                            else
                                next_state <= FETCH;
                            end if;
                        else
                            next_state <= MULTIPLY;
                        end if;
                    end if;
                end if;

            when MULTIPLY =>
                vlnw_sel <= '0';
                vlnw_done <= '0';
                read_precompute_reg <= precompute_index;
                if monpro_done = '1' then
                    if unsigned(entry_index) = unsigned(entry_count) - 1 then
                        next_state <= DONE;
                    else
                        next_state <= FETCH;
                    end if;
                end if;
             
           when DONE =>
                vlnw_done <= '1';
                vlnw_sel <= '0';
                read_precompute_reg <= precompute_index;              
                
                next_state <= IDLE;
    
        end case;
    end process;

end rtl;

