-- Behavioral model of a dual-port RAM
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity DPRAM is
	port (
		-- port 1:
		Arst  : in  std_logic;
		Aclk  : in  std_logic;
		Aaddr : in  std_logic_vector (15 downto 0);
		Adout : out std_logic_vector (31 downto 0);
		Adin  : in  std_logic_vector (31 downto 0);
		Awe   : in  std_logic_vector (3 downto 0);
		Aen   : in  std_logic;
		-- port 2:
		Brst  : in  std_logic;
		Bclk  : in  std_logic;
		Baddr : in  std_logic_vector (15 downto 0);
		Bdout : out std_logic_vector (31 downto 0);
		Bdin  : in  std_logic_vector (31 downto 0);
		Bwe   : in  std_logic_vector ( 3 downto 0);
		Ben   : in  std_logic
	);
end DPRAM;

architecture behavioural of DPRAM is
	constant size : natural := 65536; -- bytes
	type   ram_type is array(0 to size/4 - 1) of std_logic_vector(31 downto 0);
	signal ram : ram_type := (others => X"DEADBEEF");
	procedure write (
		signal mask : in  std_logic_vector ( 3 downto 0);
		signal data : in  std_logic_vector (31 downto 0);
		signal addr : in  std_logic_vector (15 downto 0);
		signal mem  : out ram_type
	) is
	begin
		for x in mask'range loop
			mem(to_integer(unsigned(addr(15 downto 2))))(x*8 + 7 downto x*8) <= data(x*8 + 7 downto x*8);
		end loop;
	end procedure write;
begin

	ports : process(Aclk, Bclk) is
	begin
		if rising_edge(Aclk) and Aen = '1' then
			if Awe /= B"0000" then
				write(Awe, Adin, Aaddr, ram);
			end if;
			Adout <= ram(to_integer(unsigned(Aaddr(15 downto 2))));
		end if;
		if rising_edge(Bclk) and Ben = '1' then
			if Bwe /= B"0000" then
				write(Bwe, Bdin, Baddr, ram);
			end if;
			Bdout <= ram(to_integer(unsigned(Baddr(15 downto 2))));
		end if;
	end process;

end behavioural;
