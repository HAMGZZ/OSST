-- Serial Interface file
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity serial_driver is
    port (
        -- Clock and reset pins
        i_clk           : in std_logic;
        i_rst           : in std_logic;
        -- Physical tx and rx pins
        i_rx_pin        : in std_logic;
        o_tx_pin        : out std_logic;
		-- Tx and Rx flags
        o_rx_busy       : out std_logic;
        o_tx_busy       : out std_logic;
        -- RX Avalon Stream
        i_rx_avst_sop   : in std_logic;
        i_rx_avst_eop   : in std_logic;
        i_rx_avst_data  : in std_logic_vector(7 downto 0);
        i_rx_avst_valid : in std_logic;
        o_rx_avst_rdy   : out std_logic;
        -- TX Avalon Stream
        o_tx_avst_sop   : out std_logic;
        o_tx_avst_eop   : out std_logic;
        o_tx_avst_data  : out std_logic_vector(7 downto 0);
        o_tx_avst_vld   : out std_logic;
        i_tx_avst_rdy   : in std_logic;
    );
end entity serial_driver;

architecture serial_driver_arch of serial_driver is
	type tx_machine is(idle, transmit);         -- TX State machine
    type rx_machine is(idle, receive);          -- RX State machine
    signal tx_state     : tx_machine;           -- TX State
    signal rx_state     : rx_state;             -- RX State
    signal parity_error : std_logic;

begin
    -- receive state machine
    process(i_rst, i_clk)
        variable rx_count   : integer range 0 to 
end architecture serial_driver_arch;
