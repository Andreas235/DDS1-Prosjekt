-- Purpose:
--   RSA encryption core template. This core currently computes
--   C = M xor key_n
--
--   Replace/change this module so that it implements the function
--   C = M**key_e mod key_n.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity rsa_core is
	generic (
		-- Users to add parameters here
		C_BLOCK_SIZE          : integer := 256
	);
	port (
		-----------------------------------------------------------------------------
		-- Clocks and reset
		-----------------------------------------------------------------------------
		clk                    :  in std_logic;
		reset_n                :  in std_logic;

		-----------------------------------------------------------------------------
		-- Slave msgin interface
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgin_valid             : in std_logic;
		-- Slave ready to accept a new message
		msgin_ready             : out std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgin_data              :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgin_last              :  in std_logic;

		-----------------------------------------------------------------------------
		-- Master msgout interface
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgout_valid            : out std_logic;
		-- Slave ready to accept a new message
		msgout_ready            :  in std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgout_data             : out std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgout_last             : out std_logic;
		
		
		-- NEW: precomputed operands and VLNW schedule from software
        r2_mod_n    : in  std_logic_vector(C_BLOCK_SIZE-1 downto 0); -- R^2 mod n
        n_prime     : in  std_logic_vector(31 downto 0);              -- -n^{-1} mod 2^32
        vlnw_schedule_0 : in std_logic_vector(255 downto 0);
        vlnw_schedule_1 : in std_logic_vector(255 downto 0);
        vlnw_schedule_2 : in std_logic_vector(255 downto 0);

		-----------------------------------------------------------------------------
		-- Interface to the register block
		-----------------------------------------------------------------------------
		key_e_d                 :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		key_n                   :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		rsa_status              : out std_logic_vector(31 downto 0)

	);
end rsa_core;

architecture rtl of rsa_core is

begin
	i_exponentiation : entity work.exponentiation
		generic map (
			C_block_size => C_BLOCK_SIZE
		)
		port map (
			message         => msgin_data  , --
			key             => key_e_d     , --
			
			r2_mod_n        => r2_mod_n,
            n_prime         => n_prime,

            -- VLNW schedules provided by software
            vlnw_schedule_0 => vlnw_schedule_0,
            vlnw_schedule_1 => vlnw_schedule_1,
            vlnw_schedule_2 => vlnw_schedule_2,
            
			valid_in        => msgin_valid , --
			ready_in        => msgin_ready , --
			ready_out       => msgout_ready, --
			valid_out       => msgout_valid, --
			result          => msgout_data , --
			modulus         => key_n       , --
			clk             => clk         , --
			reset_n         => reset_n       --
		);

	msgout_last  <= msgin_last;
	rsa_status   <= (others => '0');
end rtl;
