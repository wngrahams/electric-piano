-- VHDL Test Bench Created from source file piano.vhd -- 01:25:43 12/17/2004
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends 
-- that these types always be used for the top-level I/O of a design in order 
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY piano_tb IS
END piano_tb;

ARCHITECTURE behavior OF piano_tb IS 

	COMPONENT piano
	PORT(
		CLK_IN : IN std_logic;
		pb_in : IN std_logic_vector(3 downto 0);          
        switch_in: in std_logic_vector(7 downto 0);
        SPK_N : OUT std_logic;
		SPK_P : OUT std_logic;
		led_out : OUT std_logic_vector(7 downto 0);
		digit_out : OUT std_logic_vector(3 downto 0);
		seg_out : OUT std_logic_vector(7 downto 0)
		);
	END COMPONENT;

	SIGNAL CLK_IN :  std_logic;
	SIGNAL pb_in :  std_logic_vector(3 downto 0);
	SIGNAL SPK_N :  std_logic;
	SIGNAL SPK_P :  std_logic;
	SIGNAL led_out :  std_logic_vector(7 downto 0);
    	SIGNAL switch_in: std_logic_vector(7 downto 0);
	SIGNAL digit_out :  std_logic_vector(3 downto 0);
	SIGNAL seg_out :  std_logic_vector(7 downto 0);

BEGIN

	uut: piano PORT MAP(
		CLK_IN => CLK_IN,
		pb_in => pb_in,
        	switch_in => switch_in,
		SPK_N => SPK_N,
		SPK_P => SPK_P,
		led_out => led_out,
		digit_out => digit_out,
		seg_out => seg_out
	);

clk_gen: PROCESS 
BEGIN
-- 100MHz system Clock Generation
	CLK_IN <= '0';
	wait for 5 ns;
	CLK_IN <= '1';
	wait for 5 ns;               
END PROCESS;

-- *** Test Bench - User Defined Section ***
tb : PROCESS
BEGIN
    -- System Reset
    pb_in(0) <= '1';
    wait for 1 ns;
    pb_in(0) <= '0';
    -- end system reset addition
	
    pb_in(3) <= '0';
    pb_in(2) <= '0';
    pb_in(1) <= '0';
    pb_in(0) <= '0';
    
    switch_in(7) <= '0';
    switch_in(6) <= '0';
    switch_in(5) <= '0';
    switch_in(4) <= '0';
    switch_in(3) <= '0';
    switch_in(2) <= '0';
    switch_in(1) <= '0';
    switch_in(0) <= '0';
            
    wait for 20 ns;
    
    -- test note C3
    switch_in(7) <= '1';
    switch_in(6) <= '0';
    switch_in(5) <= '0';
    switch_in(4) <= '0';
    switch_in(3) <= '0';
    switch_in(2) <= '0';
    switch_in(1) <= '0';
    switch_in(0) <= '0';
        
    wait for 395 us;
    
    
    -- test note D3
    switch_in(7) <= '0';
    switch_in(6) <= '1';
    switch_in(5) <= '0';
    switch_in(4) <= '0';
    switch_in(3) <= '0';
    switch_in(2) <= '0';
    switch_in(1) <= '0';
    switch_in(0) <= '0';
    
    wait for 395 us;
    

--    -- test flat and sharp:
--    -- pb_in(1) and pb_in(2) make the note flat and sharp respectively

--    -- test D3 sharp:
    switch_in(7) <= '0';
    switch_in(6) <= '1';
    switch_in(5) <= '0';
    switch_in(4) <= '0';
    switch_in(3) <= '0';
    switch_in(2) <= '0';
    switch_in(1) <= '0';
    switch_in(0) <= '0';
    pb_in(2) <= '1';

    wait for 395 us;

    -- test D3 flat:
    pb_in(2) <= '0';
    pb_in(1) <= '1';

    wait for 370 us;
    pb_in(1) <= '0';

    -- test octaves:
    -- test D4:
    pb_in(3) <= '1';
    wait for 395 us;
    pb_in(3) <= '0';
    
    -- test note E3
    switch_in(7) <= '0';
    switch_in(6) <= '0';
    switch_in(5) <= '1';
    switch_in(4) <= '0';
    switch_in(3) <= '0';
    switch_in(2) <= '0';
    switch_in(1) <= '0';
    switch_in(0) <= '0';

	
    wait; -- will wait forever

END PROCESS;  
-- *** End Test Bench - User Defined Section ***
END;