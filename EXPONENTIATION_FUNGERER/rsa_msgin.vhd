--------------------------------------------------------------------------------
-- Author       : Oystein Gjermundnes
-- Organization : Norwegian University of Science and Technology (NTNU)
--                Department of Electronic Systems
--                https://www.ntnu.edu/ies
-- Course       : TFE4141 Design of digital systems 1 (DDS1)
-- Year         : 2018-2019
-- Project      : RSA accelerator
-- License      : This is free and unencumbered software released into the
--                public domain (UNLICENSE)
--------------------------------------------------------------------------------
-- Purpose:
--   The purpose of this unit is to collect 32 bit transfers on the AXI stream
--   slave interface and assemble these into 256 bit messages that will
--   be sent to the encryption core.s
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_msgin is
	generic (
		-- Users to add parameters here
			C_BLOCK_SIZE          : integer := 256;

		-- AXI4Stream sink: Data Width
			C_S_AXIS_TDATA_WIDTH  : integer := 32
	);
	port (
		----------------------------------------------------------------------------
		-- AXI Slave stream interface
		-- Masters connected to the AXI Slave stream interface of the msgin module
		-- will use the interface to transfer 32 bit chunks of data to the rsa_msgin
		-- module.
		----------------------------------------------------------------------------
		-- AXI4Stream sink: Clock
		S_AXIS_ACLK             :  in std_logic;
		-- AXI4Stream sink: Reset
		S_AXIS_ARESETN          :  in std_logic;
		-- Ready to accept data in
		S_AXIS_TREADY           : out std_logic;
		-- Data in
		S_AXIS_TDATA            :  in std_logic_vector(C_S_AXIS_TDATA_WIDTH-1 downto 0);
		-- Byte qualifier
		S_AXIS_TSTRB            :  in std_logic_vector((C_S_AXIS_TDATA_WIDTH/8)-1 downto 0);
		-- Indicates boundary of last packet
		S_AXIS_TLAST            :  in std_logic;
		-- Data in is valid
		S_AXIS_TVALID           :  in std_logic;

		-----------------------------------------------------------------------------
		-- Master msgin interface
		-- Once eight 32-bit chunks have been received, these chunks will be
		-- assembled into a 256 bit message and sent out to the slave connected
		-- to the msgin interface.
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgin_valid             : out std_logic;
			-- Slave ready to accept a new message
		msgin_ready             :  in std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgin_data              : out std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgin_last              : out std_logic

	);
end rsa_msgin;

architecture rtl of rsa_msgin is
	-- Number of chunks needed to form a message of C_BLOCK_SIZE bits.
	constant C_CHUNK_SIZE       : integer := C_S_AXIS_TDATA_WIDTH;
	constant MSG_BUFLEN         : integer := C_BLOCK_SIZE/C_CHUNK_SIZE;

	type CHUNK_ARRAY is array (0 to (MSG_BUFLEN-1)) of std_logic_vector(C_CHUNK_SIZE-1 downto 0);
	signal msgbuf_r             : CHUNK_ARRAY;
	signal msgbuf_slot_valid_r  : std_logic_vector(MSG_BUFLEN-1 downto 0);
	signal msgbuf_slot_valid_nxt: std_logic_vector(MSG_BUFLEN-1 downto 0);
	signal msgbuf_slot_valid_en : std_logic;
	signal msgbuf_last_nxt      : std_logic;
	signal msgbuf_last_r        : std_logic;

	signal input_message        : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
	signal msgin_accept         : std_logic;
	signal msgin_valid_i        : std_logic;

	signal s_axis_accept        : std_logic;
	signal s_axis_tready_i      : std_logic;
	
	    --------------------------------------------------------------------------
    -- 2-entry message FIFO towards rsa_core
    --------------------------------------------------------------------------
    type MSG_FIFO_ARRAY is array (0 to 1) of std_logic_vector(C_BLOCK_SIZE-1 downto 0);

    signal fifo_msg_r      : MSG_FIFO_ARRAY;
    signal fifo_last_r     : std_logic_vector(1 downto 0);
    signal fifo_valid_r    : std_logic_vector(1 downto 0);
    signal fifo_wr_ptr     : integer range 0 to 1;
    signal fifo_rd_ptr     : integer range 0 to 1;

    signal fifo_full       : std_logic;
    signal fifo_empty      : std_logic;

    -- Local "message complete" and push control
    signal msg_complete    : std_logic;
    signal msg_push        : std_logic;
begin
	-- I/O Connections assignments

	--------------------------------------------------------------------------------
	-- Store incoming messages. These messages are shifted in usually 32 bit every clock cycle.
	-- After 8 clock cycles a full 256 bit message has been collected.
	-- The code is parameterizable, and it should therefore be easy to increase the message
	-- size if that is desireable.
	--------------------------------------------------------------------------------
	process(S_AXIS_ARESETN, S_AXIS_ACLK)
	begin
		if(S_AXIS_ARESETN='0')then
			-- Reset the message buffer
			for i in 0 to MSG_BUFLEN-1 loop
					msgbuf_r(i) <= (others => '0');
			end loop;
		elsif(S_AXIS_ACLK'event and S_AXIS_ACLK='1') then
			-- Shift data into the message buffer every clock cycle a transfer
			-- happens.
			if(s_axis_accept = '1') then
				for i in 0 to MSG_BUFLEN-2 loop
					msgbuf_r(i) <= msgbuf_r(i+1);
				end loop;
				msgbuf_r(MSG_BUFLEN-1) <= S_AXIS_TDATA;
			end if;
		end if;
	end process;

	--------------------------------------------------------------------------------
	-- Serial to parallel conversion. Assembling 8 32 bit chunks into a 256 bit message
	--------------------------------------------------------------------------------
	process(msgbuf_r)
	begin
		for i in 0 to MSG_BUFLEN-1 loop
			input_message(i*C_CHUNK_SIZE+C_CHUNK_SIZE-1 downto i*C_CHUNK_SIZE) <= msgbuf_r(i);
		end loop;
	end process;

	--------------------------------------------------------------------------------
	-- Flag for each slot in the buffer that indicates whether or not the
	-- a chunk is present and valid in that slot.
	--------------------------------------------------------------------------------
	process(S_AXIS_ARESETN, S_AXIS_ACLK)
	begin
		if(S_AXIS_ARESETN='0')then
			-- Reset the chunk valid bit for each entry in the message buffer
			msgbuf_slot_valid_r <= (others => '0');
			msgbuf_last_r <= '0';
		elsif(S_AXIS_ACLK'event and S_AXIS_ACLK='1') then
			-- Update the slot valid flags
			if(msgbuf_slot_valid_en = '1') then
				msgbuf_slot_valid_r <= msgbuf_slot_valid_nxt;
				msgbuf_last_r <= msgbuf_last_nxt;
			end if;
		end if;
	end process;

    process(msgbuf_slot_valid_r, s_axis_accept, msg_push, S_AXIS_TLAST, msgbuf_last_r)
        variable data_accepted: std_logic_vector(1 downto 0);
    begin
        data_accepted := (s_axis_accept & msg_push);
        case data_accepted is
    
            -- New chunk sent in, but no complete message pushed to FIFO yet
            when "10" =>
                msgbuf_slot_valid_nxt <= '1' & msgbuf_slot_valid_r(MSG_BUFLEN-1 downto 1);
                msgbuf_last_nxt       <= msgbuf_last_r or S_AXIS_TLAST;
    
            -- No new chunk in, complete 256-bit message pushed to FIFO
            -- Clear all flags: msgbuf becomes empty
            when "01" =>
                msgbuf_slot_valid_nxt <= (others => '0');
                msgbuf_last_nxt       <= '0';
    
            -- New chunk in AND complete message pushed in same cycle
            -- (rare, but possible when last chunk completes a message and FIFO not full)
            when "11" =>
                msgbuf_slot_valid_nxt <= ((MSG_BUFLEN-1) => '1', others =>'0');
                msgbuf_last_nxt       <= S_AXIS_TLAST;
    
            -- Neither new chunks in nor any message pushed out
            when others => -- "00"
                msgbuf_slot_valid_nxt <= msgbuf_slot_valid_r;
                msgbuf_last_nxt       <= msgbuf_last_r;
    
        end case;
    end process;


    --------------------------------------------------------------------------
    -- Local "message complete" flag: 8 valid chunks in msgbuf
    --------------------------------------------------------------------------
    msg_complete <= and msgbuf_slot_valid_r;  -- all 8 bits must be '1'

    --------------------------------------------------------------------------
    -- FIFO full/empty status
    --------------------------------------------------------------------------
    fifo_empty <= '1' when fifo_valid_r = "00" else '0';
    fifo_full  <= '1' when fifo_valid_r = "11" else '0';

    --------------------------------------------------------------------------
    -- We push a message into the FIFO when msgbuf is complete and FIFO not full
    --------------------------------------------------------------------------
    msg_push <= msg_complete and (not fifo_full);

    -- Slot valid flags must be updated when:
    --  - a new 32-bit chunk is accepted from AXI (s_axis_accept = '1'), or
    --  - we push a complete 256-bit message into the FIFO (msg_push = '1')
    msgbuf_slot_valid_en <= s_axis_accept or msg_push;

    --------------------------------------------------------------------------
    -- AXI Stream ready: we can accept new chunks when:
    --  - the 256-bit buffer is not yet complete, OR
    --  - it is complete but we can immediately push into FIFO (not full)
    --------------------------------------------------------------------------
    s_axis_tready_i <= (not msg_complete) or (msg_complete and (not fifo_full));
    S_AXIS_TREADY   <= s_axis_tready_i;
    s_axis_accept   <= s_axis_tready_i and S_AXIS_TVALID;

    --------------------------------------------------------------------------
    -- Outputs to rsa_core now come from the FIFO front
    --------------------------------------------------------------------------
    msgin_valid <= '0' when fifo_empty = '1' else '1';
    msgin_data  <= fifo_msg_r(fifo_rd_ptr);
    msgin_last  <= fifo_last_r(fifo_rd_ptr);

    --------------------------------------------------------------------------
    -- 2-entry message FIFO towards rsa_core
    --  - Push when msg_push = '1' (msgbuf complete and FIFO not full)
    --  - Pop  when rsa_core asserts msgin_ready and FIFO not empty
    --------------------------------------------------------------------------
    fifo_proc : process(S_AXIS_ARESETN, S_AXIS_ACLK)
    begin
        if S_AXIS_ARESETN = '0' then
            fifo_valid_r <= (others => '0');
            fifo_wr_ptr  <= 0;
            fifo_rd_ptr  <= 0;
            fifo_msg_r(0) <= (others => '0');
            fifo_msg_r(1) <= (others => '0');
            fifo_last_r   <= (others => '0');
        elsif rising_edge(S_AXIS_ACLK) then

            -- PUSH: store complete 256-bit message from msgbuf
            if (msg_push = '1') and (fifo_full = '0') then
                fifo_msg_r(fifo_wr_ptr)  <= input_message;
                fifo_last_r(fifo_wr_ptr) <= msgbuf_last_r;
                fifo_valid_r(fifo_wr_ptr) <= '1';

                if fifo_wr_ptr = 0 then
                    fifo_wr_ptr <= 1;
                else
                    fifo_wr_ptr <= 0;
                end if;
            end if;

            -- POP: rsa_core consumes current message
            if (msgin_ready = '1') and (fifo_empty = '0') then
                fifo_valid_r(fifo_rd_ptr) <= '0';

                if fifo_rd_ptr = 0 then
                    fifo_rd_ptr <= 1;
                else
                    fifo_rd_ptr <= 0;
                end if;
            end if;

        end if;
    end process fifo_proc;



end rtl;
