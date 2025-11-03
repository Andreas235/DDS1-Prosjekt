library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;             -- for output
use ieee.std_logic_textio.all;  -- to print std_logic_vector

entity tb_multiplier is
end entity;

architecture sim of tb_multiplier is

    -- Signals to drive the DUT
    signal Ai : std_logic_vector(31 downto 0);
    signal B  : std_logic_vector(255 downto 0);
    signal r  : std_logic_vector(287 downto 0);

begin
    -- Instantiate DUT
    i_multiplier : entity work.multiplier
        port map (
            Ai => Ai,
            B  => B,
            r  => r
        );

    -- Stimulus process
    stim_proc : process

    begin
        B <= (others => '0');

        Ai <= x"facd3555";
        B <= x"4FD5F0B910B12F3310DC4044C56C4A36693F0E82746C497BC74178EB6E326376";
        wait for 10 ns;
        
        B <= (others => '0');
        Ai <= x"ffffffff";
        B(31 downto 0) <= x"ffffffff";
        wait for 10 ns;

        B <= (others => '0');
        Ai <= x"ffffffff";
        B <= x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        wait for 10 ns;
            
        wait;
    end process;
end architecture;
