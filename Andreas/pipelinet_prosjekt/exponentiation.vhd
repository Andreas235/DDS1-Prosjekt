library ieee;
use ieee.std_logic_1164.all;

entity exponentiation is
	generic (
		C_block_size : integer := 256
	);
	port (
        -- Control stuff
		valid_in	: in std_logic;
		ready_out	: in std_logic;
		valid_out	: out std_logic;
        ready_in	: out std_logic;
        
		-- Input data
		message 	: in std_logic_vector(255 downto 0);
		
		--Encrypt/decrypt stuff
		modulus 	: in  std_logic_vector(255 downto 0);
		key 		: in  std_logic_vector(255 downto 0);
        r2_mod_n    : in  std_logic_vector(255 downto 0);
        n_prime     : in  std_logic_vector(31 downto 0);
        
		-- Output data
		result 		: out STD_LOGIC_VECTOR(C_block_size-1 downto 0);

		-- Clock stuff
		clk 		: in std_logic;
		reset_n 	: in std_logic
	);
end exponentiation;


architecture stfu of exponentiation is     
    signal message_r1    : std_logic_vector(255 downto 0);
    signal message_r2    : std_logic_vector(255 downto 0);
    signal message_r3    : std_logic_vector(255 downto 0);
    signal message_r4    : std_logic_vector(255 downto 0);
    signal message_r5    : std_logic_vector(255 downto 0);
    
    signal modulus_r     : std_logic_vector(255 downto 0);
    signal key_r         : std_logic_vector(255 downto 0);
    signal r2_mod_n_r    : std_logic_vector(255 downto 0);
    signal n_prime_r     : std_logic_vector(31 downto 0);
    
    signal acc1 : std_logic_vector(255 downto 0);
    signal acc2 : std_logic_vector(255 downto 0);
    signal acc3 : std_logic_vector(255 downto 0);
    signal acc4 : std_logic_vector(255 downto 0);
    signal acc5 : std_logic_vector(255 downto 0);
        
    signal monproDone    : std_logic := '0';
    signal monproBusy    : std_logic := '0';
    signal monproStart   : std_logic := '0';
    
    type state_t is (
        idle_st,
        load_messages_st,
        one_bar_st,
        msg_bar_st,
        exp_st,
        finished_st
    );
    signal state, state_next : state_t := idle_st;
    
begin
	
	process
	
	fsm : process(state, start)
	begin
	
	case state_t is
	   when idle_st =>
	       if
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
end stfu;
