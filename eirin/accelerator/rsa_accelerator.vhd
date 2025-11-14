library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rsa_accelerator is
  generic (
    C_BLOCK_SIZE              : integer := 256;

    -- AXI-Lite S00_AXI
    C_S00_AXI_DATA_WIDTH      : integer := 32;
    C_S00_AXI_ADDR_WIDTH      : integer := 8;

    -- AXI-Stream S00_AXIS (slave in)
    C_S00_AXIS_TDATA_WIDTH    : integer := 32;

    -- AXI-Stream M00_AXIS (master out)
    C_M00_AXIS_TDATA_WIDTH    : integer := 32;
    C_M00_AXIS_START_COUNT    : integer := 32
  );
  port (
    -- user clock/reset
    clk                       : in  std_logic;
    reset_n                   : in  std_logic;

    -- AXI-Lite
    s00_axi_awaddr            : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
    s00_axi_awprot            : in  std_logic_vector(2 downto 0);
    s00_axi_awvalid           : in  std_logic;
    s00_axi_awready           : out std_logic;
    s00_axi_wdata             : in  std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
    s00_axi_wstrb             : in  std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
    s00_axi_wvalid            : in  std_logic;
    s00_axi_wready            : out std_logic;
    s00_axi_bresp             : out std_logic_vector(1 downto 0);
    s00_axi_bvalid            : out std_logic;
    s00_axi_bready            : in  std_logic;
    s00_axi_araddr            : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
    s00_axi_arprot            : in  std_logic_vector(2 downto 0);
    s00_axi_arvalid           : in  std_logic;
    s00_axi_arready           : out std_logic;
    s00_axi_rdata             : out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
    s00_axi_rresp             : out std_logic_vector(1 downto 0);
    s00_axi_rvalid            : out std_logic;
    s00_axi_rready            : in  std_logic;

    -- AXI-Stream IN (message in)
    s00_axis_tready           : out std_logic;
    s00_axis_tdata            : in  std_logic_vector(C_S00_AXIS_TDATA_WIDTH-1 downto 0);
    s00_axis_tstrb            : in  std_logic_vector((C_S00_AXIS_TDATA_WIDTH/8)-1 downto 0);
    s00_axis_tlast            : in  std_logic;
    s00_axis_tvalid           : in  std_logic;

    -- AXI-Stream OUT (message out)
    m00_axis_tvalid           : out std_logic;
    m00_axis_tdata            : out std_logic_vector(C_M00_AXIS_TDATA_WIDTH-1 downto 0);
    m00_axis_tstrb            : out std_logic_vector((C_M00_AXIS_TDATA_WIDTH/8)-1 downto 0);
    m00_axis_tlast            : out std_logic;
    m00_axis_tready           : in  std_logic
  );
end rsa_accelerator;

architecture rtl of rsa_accelerator is

  -----------------------------------------------------------------------------
  -- msgin-core interface
  -----------------------------------------------------------------------------
  signal msgin_valid          : std_logic;
  signal msgin_ready          : std_logic;
  signal msgin_data           : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal msgin_last           : std_logic;

  -----------------------------------------------------------------------------
  -- core-msgout interface
  -----------------------------------------------------------------------------
  signal msgout_valid         : std_logic;
  signal msgout_ready         : std_logic;
  signal msgout_data          : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal msgout_last          : std_logic;

  -----------------------------------------------------------------------------
  -- From rsa_regio → to rsa_core
  -----------------------------------------------------------------------------
  signal key_e_d_s            : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal key_n_s              : std_logic_vector(C_BLOCK_SIZE-1 downto 0);
  signal r2_mod_n_s           : std_logic_vector(255 downto 0);
  signal vlnw0_s              : std_logic_vector(255 downto 0);
  signal vlnw1_s              : std_logic_vector(255 downto 0);
  signal vlnw2_s              : std_logic_vector(255 downto 0);
  signal n_prime_s            : std_logic_vector(31 downto 0);

begin

  -----------------------------------------------------------------------------
  -- AXI-Lite register block
  -----------------------------------------------------------------------------
  u_rsa_regio : entity work.rsa_regio
    generic map (
      C_S_AXI_DATA_WIDTH      => C_S00_AXI_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH      => C_S00_AXI_ADDR_WIDTH,
      C_BLOCK_SIZE            => C_BLOCK_SIZE
      -- If your rsa_regio has C_register_count generic, set it here (e.g. => 49)
    )
    port map (
      -- to core
      key_e_d                 => key_e_d_s,
      key_n                   => key_n_s,
      r2_mod_n                => r2_mod_n_s,
      vlnw_schedule_0         => vlnw0_s,
      vlnw_schedule_1         => vlnw1_s,
      vlnw_schedule_2         => vlnw2_s,
      n_prime                 => n_prime_s,

      -- AXI-Lite
      S_AXI_ACLK              => clk,
      S_AXI_ARESETN           => reset_n,
      S_AXI_AWADDR            => s00_axi_awaddr,
      S_AXI_AWPROT            => s00_axi_awprot,
      S_AXI_AWVALID           => s00_axi_awvalid,
      S_AXI_AWREADY           => s00_axi_awready,
      S_AXI_WDATA             => s00_axi_wdata,
      S_AXI_WSTRB             => s00_axi_wstrb,
      S_AXI_WVALID            => s00_axi_wvalid,
      S_AXI_WREADY            => s00_axi_wready,
      S_AXI_BRESP             => s00_axi_bresp,
      S_AXI_BVALID            => s00_axi_bvalid,
      S_AXI_BREADY            => s00_axi_bready,
      S_AXI_ARADDR            => s00_axi_araddr,
      S_AXI_ARPROT            => s00_axi_arprot,
      S_AXI_ARVALID           => s00_axi_arvalid,
      S_AXI_ARREADY           => s00_axi_arready,
      S_AXI_RDATA             => s00_axi_rdata,
      S_AXI_RRESP             => s00_axi_rresp,
      S_AXI_RVALID            => s00_axi_rvalid,
      S_AXI_RREADY            => s00_axi_rready
    );

  -----------------------------------------------------------------------------
  -- Stream input frontend
  -----------------------------------------------------------------------------
  u_rsa_msgin : entity work.rsa_msgin
    generic map (
      C_S_AXIS_TDATA_WIDTH    => C_S00_AXIS_TDATA_WIDTH
    )
    port map (
      S_AXIS_ACLK             => clk,
      S_AXIS_ARESETN          => reset_n,
      S_AXIS_TREADY           => s00_axis_tready,
      S_AXIS_TDATA            => s00_axis_tdata,
      S_AXIS_TSTRB            => s00_axis_tstrb,
      S_AXIS_TLAST            => s00_axis_tlast,
      S_AXIS_TVALID           => s00_axis_tvalid,

      msgin_valid             => msgin_valid,
      msgin_ready             => msgin_ready,
      msgin_data              => msgin_data,
      msgin_last              => msgin_last
    );

  -----------------------------------------------------------------------------
  -- Stream output backend
  -----------------------------------------------------------------------------
  u_rsa_msgout : entity work.rsa_msgout
    generic map (
      C_M_AXIS_TDATA_WIDTH    => C_M00_AXIS_TDATA_WIDTH,
      C_M_START_COUNT         => C_M00_AXIS_START_COUNT
    )
    port map (
      M_AXIS_ACLK             => clk,
      M_AXIS_ARESETN          => reset_n,
      M_AXIS_TVALID           => m00_axis_tvalid,
      M_AXIS_TDATA            => m00_axis_tdata,
      M_AXIS_TSTRB            => m00_axis_tstrb,
      M_AXIS_TLAST            => m00_axis_tlast,
      M_AXIS_TREADY           => m00_axis_tready,

      msgout_valid            => msgout_valid,
      msgout_ready            => msgout_ready,
      msgout_data             => msgout_data,
      msgout_last             => msgout_last
    );

  -----------------------------------------------------------------------------
  -- Core (passes regio signals to exponentiation)
  -----------------------------------------------------------------------------
  u_rsa_core : entity work.rsa_core
    generic map (
      C_BLOCK_SIZE            => C_BLOCK_SIZE
    )
    port map (
      clk                     => clk,
      reset_n                 => reset_n,

      -- stream
      msgin_valid             => msgin_valid,
      msgin_ready             => msgin_ready,
      msgin_data              => msgin_data,
      msgin_last              => msgin_last,

      msgout_valid            => msgout_valid,
      msgout_ready            => msgout_ready,
      msgout_data             => msgout_data,
      msgout_last             => msgout_last,

      -- from regio (keys + precomputed + schedules)
      key_e_d                 => key_e_d_s,
      key_n                   => key_n_s,
      r2_mod_n                => r2_mod_n_s,
      n_prime                 => n_prime_s,
      vlnw_schedule_0         => vlnw0_s,
      vlnw_schedule_1         => vlnw1_s,
      vlnw_schedule_2         => vlnw2_s
    );

end rtl;

