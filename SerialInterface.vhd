-- Based off digikey example code https://forum.digikey.com/t/uart-vhdl/12670

library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity SerialInterface is
    generic (
        clk_freq        :  integer    := 50_000_000;    --frequency of system clock in Hertz
        baud_rate       :  integer    := 300;        --data link baud rate in bits/second
        os_rate         :  integer    := 16;            --oversampling rate to find center of receive bits (in samples per baud period)
        d_width         :  integer    := 8;             --data bus width
        parity          :  integer    := 1;             --0 for no parity, 1 for parity
        parity_odd_even :  std_logic  := '0'           --'0' for even, '1' for odd parity
    );
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

        -- RX Simple Stream (for now)
        o_rx_error      : out std_logic;                            --Error flag
        o_rx_data       : out std_logic_vector(d_width-1 downto 0); --Data received

        -- TX Simple Stream (for now)

        i_tx_init_tran  : in std_logic;                             --Start transmission (after shifiting data in)
        i_tx_data       : in std_logic_vector(d_width-1 downto 0)  --Data to transmit

        -- -- RX Avalon Stream
        -- i_rx_avst_sop   : in std_logic;
        -- i_rx_avst_eop   : in std_logic;
        -- i_rx_avst_data  : in std_logic_vector(7 downto 0);
        -- i_rx_avst_valid : in std_logic;
        -- o_rx_avst_rdy   : out std_logic;
        -- -- TX Avalon Stream
        -- o_tx_avst_sop   : out std_logic;
        -- o_tx_avst_eop   : out std_logic;
        -- o_tx_avst_data  : out std_logic_vector(7 downto 0);
        -- o_tx_avst_vld   : out std_logic;
        -- i_tx_avst_rdy   : in std_logic
    );
end entity SerialInterface;

architecture serial_driver_arch of SerialInterface is
	type tx_machine is(idle, transmit);                                                     -- TX State machine
    type rx_machine is(idle, receive);                                                      -- RX State machine
    signal tx_state     : tx_machine;                                                       -- TX State
    signal rx_state     : rx_machine;                                                         -- RX State
    signal baud_pulse   : std_logic := '0';                                                --periodic pulse that occurs at the baud rate
    signal os_pulse     : std_logic := '0';                                                --periodic pulse that occurs at the oversampling rate
    signal parity_error : std_logic;                                                       --receive parity error flag
    signal rx_parity    : std_logic_vector(d_width DOWNTO 0);                              --calculation of receive parity
    signal tx_parity    : std_logic_vector(d_width DOWNTO 0);                              --calculation of transmit parity
    signal rx_buffer    : std_logic_vector(parity+d_width DOWNTO 0) := (OTHERS => '0');    --values received
    signal tx_buffer    : std_logic_vector(parity+d_width+1 DOWNTO 0) := (OTHERS => '1');  --values to be transmitted


begin
     --generate clock enable pulses at the baud rate and the oversampling rate
    process(i_rst, i_clk)
        variable count_baud : integer range 0 to clk_freq/baud_rate-1 := 0;         --counter to determine baud rate period
        variable count_os   : integer range 0 to clk_freq/baud_rate/os_rate-1 := 0; --counter to determine oversampling period
    begin
        if(i_rst = '0') then                            --asynchronous reset asserted
            baud_pulse <= '0';                                --reset baud rate pulse
            os_pulse <= '0';                                  --reset oversampling rate pulse
            count_baud := 0;                                  --reset baud period counter
            count_os := 0;                                    --reset oversampling period counter
        elsif(i_clk'event and i_clk = '1') then
          --create baud enable pulse
            if(count_baud < clk_freq/baud_rate-1) then        --baud period not reached
                count_baud := count_baud + 1;                     --increment baud period counter
                baud_pulse <= '0';                                --deassert baud rate pulse
            else                                              --baud period reached
                count_baud := 0;                                  --reset baud period counter
                baud_pulse <= '1';                                --assert baud rate pulse
                count_os := 0;                                    --reset oversampling period counter to avoid cumulative error
            end if;
          --create oversampling enable pulse
            if(count_os < clk_freq/baud_rate/os_rate-1) then  --oversampling period not reached
                count_os := count_os + 1;                         --increment oversampling period counter
                os_pulse <= '0';                                  --deassert oversampling rate pulse    
            else                                              --oversampling period reached
                count_os := 0;                                    --reset oversampling period counter
                os_pulse <= '1';                                  --assert oversampling pulse
            end if;
        end if;
    end process;

    -- RX State machine
    process(i_rst, i_clk)
        variable rx_count   : integer range 0 to parity+d_width+2 := 0;     --Counter for received bits
        variable os_count   : integer range 0 to os_rate-1        := 0;     --counter for oversample pulses
    begin
        if(i_rst = '0') then                                                      -- if rst then reset all the flags and counters
            os_count    := 0;
            rx_count    := 0;
            o_rx_busy   <= '0';
            o_rx_error  <= '0';
            o_rx_data   <= (OTHERS => '0');
            rx_state    <= idle;                                            -- set state to idle
        elsif(i_clk'event and i_clk = '1' and os_pulse = '1') then          -- if clock pulse and over sample pulse start rx
            case rx_state is
                when idle =>
                    o_rx_busy <= '0';
                    if(i_rx_pin = '0') then                                 -- there is something, lets keep sampling
                        if(os_count < os_rate/2) then
                            os_count := os_count +1;
                            rx_state <= idle;
                        else                                                -- we are sure now there is something, its the start bit lets save it
                            os_count    := 0;
                            rx_count    := 0;
                            o_rx_busy   <= '1';
                            rx_buffer   <= i_rx_pin & rx_buffer(parity+d_width downto 1);
                            rx_state    <= receive;
                        end if;
                    else
                        os_count := 0;                                      -- nothing is hapenning lets just wait....
                        rx_state <= idle;
                    end if;
                when receive =>
                    if(os_count < os_rate-1) then           -- start of bit, keep sampling
                        os_count    := os_count + 1;
                        rx_state    <= receive;
                    elsif(rx_count < parity+d_width) then   -- middle of bit, save to buffer
                        os_count    := 0;
                        rx_count    := rx_count +1;
                        rx_buffer   <= i_rx_pin & rx_buffer(parity+d_width downto 1);
                        rx_state    <= receive;
                    else                                    -- must be stop bit, lets save it, push it to data and go back to idle
                        o_rx_data   <= rx_buffer(d_width downto 1);
                        o_rx_error    <= rx_buffer(0) or parity_error or not i_rx_pin;
                        o_rx_busy     <= '0';
                        rx_state    <= idle;
                    end if;
            end case;
        end if;
    end process;

    -- RX parity calcs  XOR parity
    rx_parity(0)    <= parity_odd_even;
    rx_parity_logic: for i in 0 to d_width-1 generate 
        rx_parity(i+1)  <= rx_parity(i) xor rx_buffer(i+1);
    end generate;
    with parity select
        parity_error    <= rx_parity(d_width) xor rx_buffer(parity+d_width) when 1, '0' when others;

    -- TX State machine
    process(i_rst, i_clk)
        variable tx_count   : integer range 0 to parity+d_width+3 := 0;
    begin
        if(i_rst = '0') then
            tx_count    := 0;
            o_tx_pin    <= '1';
            o_tx_busy   <= '1';
            tx_state    <= idle;
        elsif(i_clk'event and i_clk = '1') then
            case tx_state is
                when idle =>
                    if(i_tx_init_tran = '1') then
                        tx_buffer(d_width+1 downto 0)   <= i_tx_data & '0' & '1';
                        if(parity = 1) then
                            tx_buffer(parity+d_width+1) <= tx_parity(d_width);
                        end if;
                        o_tx_busy   <= '1';
                        tx_count    := 0;
                        tx_state    <= transmit;
                    else
                        o_tx_busy   <= '0';
                        tx_state    <= idle;
                    end if;
                when transmit =>
                    if(baud_pulse = '1') then
                        tx_count    := tx_count+1;
                        tx_buffer   <= '1' & tx_buffer(parity+d_width+1 downto 1);
                    end if;
                    if(tx_count < parity+d_width+3) then
                        tx_state <= transmit;
                    else
                        tx_state <= idle;
                    end if;
            end case;
            o_tx_pin <= tx_buffer(0);
        end if;
    end process;

    -- Transmit parit xor calc
    tx_parity(0)    <= parity_odd_even;
    tx_parity_logic: for i in 0 to d_width -1 generate
        tx_parity(i+1)  <= tx_parity(i) xor i_tx_data(i);
    end generate;
end serial_driver_arch;
                