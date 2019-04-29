--
-- piano.vhd - FPGA Piano
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity piano is
    port ( CLK_IN       : in std_logic;
           pb_in        : in std_logic_vector(3 downto 0);
           switch_in    : in std_logic_vector(7 downto 0);
           SPK_N        : out std_logic; 
           SPK_P        : out std_logic;
           led_out      : out std_logic_vector(7 downto 0);
           digit_out    : out std_logic_vector(3 downto 0);
           seg_out      : out std_logic_vector(7 downto 0)
         );
end piano;

architecture Behavioral of piano is
   -- Xilinx Native Components
   component BUFG  port ( I : in std_logic; O : out std_logic); end component;
   component IBUFG port ( I : in std_logic; O : out std_logic); end component;
   component IBUF  port ( I : in std_logic; O : out std_logic); end component;
   component OBUF  port ( I : in std_logic; O : out std_logic); end component;
   component MMCME2_BASE
      generic( CLKFBOUT_MULT_F : real;
                DIVCLK_DIVIDE :  integer;
                CLKOUT0_DIVIDE_F  :  real
              );
      port ( CLKIN1     : in    std_logic; 
             CLKFBIN    : in    std_logic; 
             RST        : in    std_logic; 
             PWRDWN     : in    std_logic; 
             CLKOUT0    : out   std_logic; 
             CLKOUT0B   : out   std_logic;
             CLKOUT1    : out   std_logic;
             CLKOUT1B   : out   std_logic;
             CLKOUT2    : out   std_logic;
             CLKOUT2B   : out   std_logic;
             CLKOUT3    : out   std_logic;
             CLKOUT3B   : out   std_logic;
             CLKOUT4    : out   std_logic;
             CLKOUT5    : out   std_logic;
             CLKOUT6    : out   std_logic;
             CLKFBOUT   : out   std_logic; 
             CLKFBOUTB  : out   std_logic; 
             LOCKED     : out   std_logic);
   end component;

    -- My Components:

    --  Clock Divider
    component clk_dvd
    port (
          CLK     : in std_logic;
          RST     : in std_logic;
          DIV     : in std_logic_vector(15 downto 0);
          EN      : in std_logic;
          CLK_OUT : out std_logic;
          ONE_SHOT: out std_logic
         );
    end component;

    -- Note decoder
    component note_gen
    port (
          CLK       : in  std_logic;
          RST       : in  std_logic;
          NOTE_IN   : in  std_logic_vector(4 downto 0);
          DIV       : out std_logic_vector(15 downto 0)
         );
    end component;
    
    -- 7-Segment Display for Notes
    component seven_seg
        port ( CLK      : in std_logic;
               RST      : in std_logic;
               NOTE_IN  : in std_logic_vector(4 downto 0);
               SCAN_EN  : in std_logic; 
               DIGIT    : out std_logic_vector(3 downto 0);
               SEG      : out std_logic_vector(7 downto 0) 
             );
   end component;

   -- Signals
   signal CLK         : std_logic;                      -- 50MHz clock after DCM and BUFG
   signal CLK0        : std_logic;                      -- 50MHz clock from pad
   signal CLK_BUF     : std_logic;                      -- 50MHz clock after IBUF
   signal GND         : std_logic;                      
   signal RST         : std_logic;              
   signal PB          : std_logic_vector(3 downto 0);   -- Pushbuttons after ibufs
   signal digit_l     : std_logic_vector(3 downto 0);   -- 7-seg digit MUX before obuf
   signal switch      : std_logic_vector(7 downto 0);   -- Toggle switches after ibufs
   signal led         : std_logic_vector(7 downto 0);   -- LEDs after ibufs
   signal seg_l       : std_logic_vector(7 downto 0);   -- 7-seg segment select before obuf.
  
   signal one_mhz     : std_logic;                      -- 1MHz Clock
   signal one_mhz_1   : std_logic;                      -- pulse with f=1 MHz created by divider
   signal clk_10k_1   : std_logic;                      -- pulse with f=10kHz created by divider
   signal div         : std_logic_vector(15 downto 0);  -- variable clock divider for loadable counter
   signal note_in     : std_logic_vector(4 downto 0);   -- output of user interface. Current Note
   signal note_next   : std_logic_vector(4 downto 0);   -- Buffer holding current Note
   signal note_sel    : std_logic_vector(3 downto 0);   -- Encoding of switches.
   signal div_1       : std_logic;                      -- 1MHz pulse
   signal sound       : std_logic;                      -- Output of Loadable Clock Divider. Sent to Speaker if note is playing.
   signal SPK         : std_logic;                      -- Output for Speaker fed to OBUF
   signal small_count         : std_logic_vector(15 downto 0);
   signal large_count         : std_logic_vector(15 downto 0);
   signal note_count         : std_logic_vector(15 downto 0);
   
begin
    GND    <= '0';     
    RST    <= PB(0);    -- push button one is the reset
    led(1) <= RST;      -- This is just to make sure our design is running.

    -- Combinational logic to turn the sound on and off
    process (div, sound) begin
        if (div = x"0000") then
            SPK <= GND;
        else
            SPK <= sound;
        end if;
    end process;
    
    -- Speaker output
    SPK_OBUF_INST : OBUF port map (I=>SPK, O=>SPK_N);
    SPK_P <= GND; 

    -- Input/Output Buffers
    loop0 : for i in 0 to 3 generate
        pb_ibuf  : IBUF  port map(I => pb_in(i),   O => PB(i));
        dig_obuf : OBUF  port map(I => digit_l(i), O => digit_out(i));
    end generate ;
    loop1 : for i in 0 to 7 generate
        swt_obuf : IBUF  port map(I => switch_in(i), O => switch(i));
        led_obuf : OBUF  port map(I => led(i),   O => led_out(i));
        seg_obuf : OBUF  port map(I => seg_l(i), O => seg_out(i));
    end generate ;

    -- Global Clock Buffers

    -- Pad -> DCM
    CLKIN_IBUFG_INST : IBUFG
      port map (I=>CLK_IN,      
                O=>CLK0);

    -- DCM -> CLK
    CLK0_BUFG_INST : BUFG
      port map (I=>CLK_BUF,      
                O=>CLK);

   
    -- MMCM for Clock deskew and frequency synthesis
    MMCM_INST : MMCME2_BASE
      generic map(
        CLKFBOUT_MULT_F =>10.0,
        DIVCLK_DIVIDE=>1,
        CLKOUT0_DIVIDE_F =>10.0
      )
      port map (CLKIN1=>CLK0,
               CLKFBIN=>CLK, 
               RST=>RST, 
               PWRDWN=>GND, 
               CLKOUT0=>CLK_BUF,
               CLKOUT0B=>open,
               CLKOUT1=>open,
               CLKOUT1B=>open,
               CLKOUT2=>open,
               CLKOUT2B=>open,
               CLKOUT3=>open,
               CLKOUT3B=>open,
               CLKOUT4=>open,
               CLKOUT5=>open,
               CLKOUT6=>open,
               CLKFBOUT=>open, 
               CLKFBOUTB=>open, 
               LOCKED=>led(0)
               );

    -- Divide 100Mhz to 1Mhz clock
    DIV_1M : clk_dvd        
        port map ( CLK      => CLK,
                   RST      => RST,
                   DIV      => x"0032",  -- 50
                   EN       => '1',
                   CLK_OUT  => one_mhz,
                   ONE_SHOT => one_mhz_1
                 );

    -- Divide 1Mhz to Various frequencies for the notes.
    DIV_NOTE : clk_dvd        
        port map ( CLK      => CLK,
                   RST      => RST,
                   DIV      => div,
                   EN       => one_mhz_1,
                   CLK_OUT  => sound,
                   ONE_SHOT => div_1
                 );

    -- Divide 1Mhz to 10k
    DIV_10k : clk_dvd        
        port map ( CLK      => CLK,
                   RST      => RST,
                   DIV      => x"0032", -- 50
                   EN       => one_mhz_1,
                   CLK_OUT  => open,
                   ONE_SHOT => clk_10k_1
                 );

    -- Translate Encoded Note to clock divider for 1MHz clock.
    note_gen_inst : note_gen
        port map ( CLK     => CLK,
                   RST     => RST,
                   NOTE_IN => note_in,
                   DIV     => div
                 );

    -- Wire up seven-seg controller to display current note.
    seven_seg_inst : seven_seg
        port map ( CLK     => CLK,
                   RST     => RST,
                   NOTE_IN => note_in,
                   SCAN_EN => clk_10k_1,
                   DIGIT   => digit_l,
                   SEG     => seg_l
                 );

    -- User Interface
    note_in <= note_next;
    process (CLK,RST) begin
        if (RST = '1') then
            note_next <= (others => '0');
            small_count <= x"0000";
            large_count <= x"0000";
            note_count <= x"0000";
            note_next <= "00000";
        elsif (CLK'event and CLK = '1') then
        
            if (switch = "00000001") then

                -- Heart and Soul
    
                -- 1000000 clock cycles = 0.01 sec, therefore 40000 clock cycles = 0.0004 sec
                -- Therefore, if small_count increases every clock cycle, then large_count increases
                -- every 0.0004 sec
                -- These counters are defined near the top of this file as 15-bit std logic vectors.
                if (small_count = x"9c40") then
                    large_count <= large_count + 1;
                    small_count <= x"0000";
                end if;
    
                -- MEASURE 1
                if (note_count = x"0000" and large_count < x"0190") then
                    note_next <= "10001";  -- C4
                elsif (large_count = x"0190" and note_count = x"0000") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0001") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0002") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0003") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0004") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0005") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0006") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 2
                elsif (large_count = x"0032" and note_count = x"0007") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0008") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0009") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"000a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"000b") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"000c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"000d") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"000e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 3
                elsif (large_count = x"0032" and note_count = x"000f") then
                    note_next <= "00110"; -- F3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0010") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0011") then
                    note_next <= "00110"; -- F3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0012") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0013") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0014") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0015") then
                   note_next <= "01010"; -- A3
                   large_count <= x"0000";
                   small_count <= x"0000";
                   note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0016") then
                   note_next <= "00000"; -- off
                   large_count <= x"0000";
                   small_count <= x"0000";
                   note_count <= note_count + 1;
    
            -- MEASURE 4
                elsif (large_count = x"0032" and note_count = x"0017") then
                    note_next <= "01000"; -- G3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0018") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0019") then
                    note_next <= "01000"; -- G3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"001a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"001b") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"001c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"001d") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"001e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 5
                elsif (large_count = x"0032" and note_count = x"001f") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0020") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0021") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0022") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 6 (and beginning of 7 - tie on C4)
                elsif (large_count = x"0032" and note_count = x"0023") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0640" and note_count = x"0024") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 7
                elsif (large_count = x"0032" and note_count = x"0025") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0026") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0027") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0028") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0029") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"002a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 8
                elsif (large_count = x"0032" and note_count = x"002b") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"002c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"002d") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"002e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"002f") then
                    note_next <= "10011"; -- D4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0030") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 9
                elsif (large_count = x"0032" and note_count = x"0031") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0032") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0033") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0034") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 10 (and beginning of 11 - tie on E4)
                elsif (large_count = x"0032" and note_count = x"0035") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0640" and note_count = x"0036") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 11
                elsif (large_count = x"0032" and note_count = x"0037") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0038") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0039") then
                    note_next <= "10011"; -- D4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"003a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"003b") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"003c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 12
                elsif (large_count = x"0032" and note_count = x"003d") then
                    note_next <= "10011"; -- D4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"003e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"003f") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0040") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0041") then
                    note_next <= "10110"; -- F4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0042") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 13
                elsif (large_count = x"0032" and note_count = x"0043") then
                    note_next <= "11000"; -- G4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"04b0" and note_count = x"0044") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 14 (and beginning of 15 - tie on C4)
                elsif (large_count = x"0032" and note_count = x"0045") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0640" and note_count = x"0046") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 15
                elsif (large_count = x"0032" and note_count = x"0047") then
                    note_next <= "11010"; -- A4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0048") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0049") then
                    note_next <= "11000"; -- G4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"004a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"004b") then
                    note_next <= "10110"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"004c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 16
                elsif (large_count = x"0032" and note_count = x"004d") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"004e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"004f") then
                    note_next <= "10011"; -- D4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0258" and note_count = x"0050") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 17
                elsif (large_count = x"0032" and note_count = x"0051") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0682" and note_count = x"0052") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0053") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0054") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 18
                elsif (large_count = x"0032" and note_count = x"0055") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0682" and note_count = x"0056") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0057") then
                    note_next <= "01000"; -- G3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0058") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 19
                elsif (large_count = x"0032" and note_count = x"0059") then
                    note_next <= "00110"; -- F3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0682" and note_count = x"005a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"005b") then
                    note_next <= "00101"; -- E3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"005c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 20
                elsif (large_count = x"0032" and note_count = x"005d") then
                    note_next <= "00110"; -- F3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"005e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"005f") then
                    note_next <= "01000"; -- G3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0060") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0061") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0062") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0063") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0064") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 21
                elsif (large_count = x"0032" and note_count = x"0065") then
                    note_next <= "10001"; -- C3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0066") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0067") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0068") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0069") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"006a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"006b") then
                    note_next <= "10101"; -- E4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"006c") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 22
                elsif (large_count = x"0032" and note_count = x"006d") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"006e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"006f") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0070") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0071") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0072") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0073") then
                    note_next <= "10001"; -- C4
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0074") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
    
            -- MEASURE 23
                elsif (large_count = x"0032" and note_count = x"0075") then
                    note_next <= "00110"; -- F3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0076") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0077") then
                    note_next <= "00110"; -- F3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0078") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0079") then
                    note_next <= "01010"; -- A3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"007a") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"007b") then
                   note_next <= "01010"; -- A3
                   large_count <= x"0000";
                   small_count <= x"0000";
                   note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"007c") then
                   note_next <= "00000"; -- off
                   large_count <= x"0000";
                   small_count <= x"0000";
                   note_count <= note_count + 1;
    
            -- MEASURE 24
                elsif (large_count = x"0032" and note_count = x"007d") then
                    note_next <= "01000"; -- G3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"007e") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"007f") then
                    note_next <= "01000"; -- G3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0080") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0081") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0190" and note_count = x"0082") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"0032" and note_count = x"0083") then
                    note_next <= "01100"; -- B3
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                elsif (large_count = x"00c8" and note_count = x"0084") then
                    note_next <= "00000"; -- off
                    large_count <= x"0000";
                    small_count <= x"0000";
                    note_count <= note_count + 1;
                end if;
    
                small_count <= small_count + 1;
                
            else
                            
                case switch is 
                    when "10000000" => note_sel <= "0001"; -- C
                    when "01000000" => note_sel <= "0011"; -- D
                    when "00100000" => note_sel <= "0101"; -- E
                    when "00010000" => note_sel <= "0110"; -- F
                    when "00001000" => note_sel <= "1000"; -- G
                    when "00000100" => note_sel <= "1010"; -- A
                    when "00000010" => note_sel <= "1100"; -- B
                    when others     => note_sel <= "0000"; 
                end case;
    
                -- Sharp -- Add one.  PB(3) is the octave key.
                if (PB(2) = '1') then
                    note_next <= PB(3) & note_sel + 1;
                -- Flat --  Minus one.
                elsif (PB(1) = '1') then
                    note_next <= PB(3) & note_sel - 1;
                else 
                    note_next <= PB(3) & note_sel;
                end if;
                
            end if;

        end if;
    end process; 
    
end Behavioral;
