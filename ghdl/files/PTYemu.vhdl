-- PTY-based serial port for real-time VHDL-host communication
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: Apache-2.0


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity PTYemu is
	generic (
		baudrate : natural := 10000000;
		pty_path : string
	);
	port (
		rx : in  std_logic;
		tx : out std_logic
	);
end entity;

architecture behavioral of PTYemu is
	constant symbol_time : time := 1 sec / baudrate;
	signal   rx_clock  : std_logic := '0';
	signal   rx_active : boolean := false;

	procedure pty_start (link : string) is
	begin
		report "VHPIDIRECT error" severity failure;
	end;
	attribute foreign of pty_start : procedure is "VHPIDIRECT pty_start";

	procedure pty_write (data : integer) is
	begin
		report "VHPIDIRECT error" severity failure;
	end;
	attribute foreign of pty_write : procedure is "VHPIDIRECT pty_write";

	function pty_read return integer is
	begin
		report "VHPIDIRECT error" severity failure;
	end;
	attribute foreign of pty_read : function is "VHPIDIRECT pty_read";

begin
	pty : process
	begin
		pty_start(pty_path);
		wait;
	end process;

	rx_clock <= '0' when not rx_active else not rx_clock after symbol_time / 2;
	receiver : process (rx_clock, rx)
		variable rxcnt : natural range 0 to 10;
		variable shifter : std_logic_vector(9 downto 0);
	begin
		if not rx_active and falling_edge(rx) then
			rx_active <= true;
			rxcnt := 10;
		end if;
		if rx_active and rising_edge(rx_clock) then
			shifter := rx & shifter(9 downto 1);
			rxcnt := rxcnt - 1;
			if rxcnt = 0 then
				rx_active <= false;
				pty_write(to_integer(unsigned(shifter)));
			end if;
		end if;
	end process;

	transmitter : process
		variable data : integer;
		variable txcnt : natural range 0 to 15;
		variable shifter : std_logic_vector(9 downto 0) := (others => '0');
	begin
		tx <= '1' when shifter(0) = '1' else '0';
		if txcnt = 0 then
			data := pty_read;
			if data >= 0 then
				if data < 256 then
					-- send a regular character:
					shifter := '1' & std_logic_vector(to_unsigned(data, 8)) & '0';
					txcnt := 10;
				elsif data = 256 + character'pos(EOT) then
					-- send a break:
					shifter := (others => '0');
					txcnt := 15;
				elsif data = 256 + character'pos(NUL) then
					-- send an idle condition:
					shifter := (others => '1');
					txcnt := 15;
				end if;
			else
				-- wait some time to avoid clogging the CPU,
				-- polling VHPIDIRECT every "character time":
				wait for 10 * symbol_time;
			end if;
		else
			txcnt := txcnt - 1;
			shifter := shifter(9) & shifter(9 downto 1);
			wait for symbol_time;
		end if;
	end process;

end architecture behavioral;

