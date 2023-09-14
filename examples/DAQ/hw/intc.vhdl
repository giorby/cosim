-- Interrupt Controller
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

-- Register map:
-- 0 : IRQ inputs (RO) - actual status of IRQ lines
-- 1 : IRQ masked (RO) - masked status of IRQ lines
-- 2 : IRQ enable (RW) - individual IRQ enables


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity IRQ_controller is
	generic (
		C_S_AXI_DATA_WIDTH : integer := 32;
		C_S_AXI_ADDR_WIDTH : integer := 4;
		INTERRUPT_SOURCES  : integer := 8
	);
	port (
		irq_inputs      : in  std_logic_vector(INTERRUPT_SOURCES-1 downto 0);
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      : in  std_logic;
		S_AXI_ARESETN   : in  std_logic;
		S_AXI_AWADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1   downto 0);
		S_AXI_AWPROT    : in  std_logic_vector(2 downto 0);
		S_AXI_AWVALID   : in  std_logic;
		S_AXI_AWREADY   : out std_logic;
		S_AXI_WDATA     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1   downto 0);
		S_AXI_WSTRB     : in  std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);
		S_AXI_WVALID    : in  std_logic;
		S_AXI_WREADY    : out std_logic;
		S_AXI_BRESP     : out std_logic_vector(1 downto 0);
		S_AXI_BVALID    : out std_logic;
		S_AXI_BREADY    : in  std_logic;
		S_AXI_ARADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1   downto 0);
		S_AXI_ARPROT    : in  std_logic_vector(2 downto 0);
		S_AXI_ARVALID   : in  std_logic;
		S_AXI_ARREADY   : out std_logic;
		S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1   downto 0);
		S_AXI_RRESP     : out std_logic_vector(1 downto 0);
		S_AXI_RVALID    : out std_logic;
		S_AXI_RREADY    : in  std_logic;
		------------------------------------------------------------------------
		IRQ             : out std_logic
	);
end IRQ_controller;

architecture behavioural of IRQ_controller is
	-- AXI4LITE signals:
	-- write channels:
	signal axi_waddr   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1   downto 0);
	signal axi_wdata   : std_logic_vector(C_S_AXI_DATA_WIDTH-1   downto 0);
	signal axi_wstrb   : std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);
	signal axi_awready : std_logic;
	signal axi_wready  : std_logic;
	signal axi_bresp   : std_logic_vector(1 downto 0);
	signal axi_bvalid  : std_logic;
	-- read channels:
	signal axi_raddr   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_rdata   : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal axi_arready : std_logic;
	signal axi_rresp   : std_logic_vector(1 downto 0);
	signal axi_rvalid  : std_logic;

	signal got_raddr   : std_logic;
	signal got_waddr   : std_logic;
	signal got_wdata   : std_logic;

	-- controller registers:
	signal irq_enable  : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);

begin
	-- AXI handling:

	S_AXI_AWREADY <= axi_awready;
	S_AXI_WREADY  <= axi_wready;
	S_AXI_BVALID  <= axi_bvalid;
	S_AXI_BRESP   <= axi_bresp;

	S_AXI_ARREADY <= axi_arready;
	S_AXI_RDATA   <= axi_rdata;
	S_AXI_RRESP   <= axi_rresp;
	S_AXI_RVALID  <= axi_rvalid;

	writes : process (S_AXI_ACLK) is
		variable done : boolean;
	begin
		if rising_edge(S_AXI_ACLK) then

			if S_AXI_ARESETN = '0' then
				axi_awready <= '0';
				axi_wready  <= '0';
				axi_bvalid  <= '0';
				got_waddr   <= '0';
				got_wdata   <= '0';
			else

				-- address handshake:
				if S_AXI_AWVALID = '1' and axi_awready = '1' then
					axi_waddr   <= S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH-1 downto 0);
					got_waddr   <= '1';
					axi_awready <= '0';
				else
					axi_awready <= not got_waddr;
				end if;

				-- data handshake:
				if S_AXI_WVALID = '1' and axi_wready = '1' then
					axi_wdata   <= S_AXI_WDATA;
					axi_wstrb   <= S_AXI_WSTRB;
					got_wdata   <= '1';
					axi_wready  <= '0';
				else
					axi_wready  <= not got_wdata;
				end if;

				-- response handshake:
				if S_AXI_BREADY = '1' and axi_bvalid = '1' then
					axi_bvalid <= '0';
				end if;

				-- register write handling:
				done := false;
				if got_waddr = '1' and got_wdata = '1' then
					axi_bresp <= b"00";
					case to_integer(unsigned(axi_waddr(C_S_AXI_ADDR_WIDTH-1 downto 2))) is
					when 2 =>
						if axi_wstrb(3) then irq_enable(31 downto 24) <= axi_wdata(31 downto 24); end if;
						if axi_wstrb(2) then irq_enable(23 downto 16) <= axi_wdata(23 downto 16); end if;
						if axi_wstrb(1) then irq_enable(15 downto  8) <= axi_wdata(15 downto  8); end if;
						if axi_wstrb(0) then irq_enable( 7 downto  0) <= axi_wdata( 7 downto  0); end if;
						done := true;
					when others =>
						axi_bresp <= b"11";
						done := true;
					end case;
					if done then
						axi_bvalid <= '1';
						got_wdata <= '0';
						got_waddr <= '0';
					end if;
				end if;

			end if;
		end if;
	end process;

	reads : process (S_AXI_ACLK) is
		constant pad : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto INTERRUPT_SOURCES) := (others => '0');
	begin
		if rising_edge(S_AXI_ACLK) then

			if S_AXI_ARESETN = '0' then
				axi_arready <= '0';
				axi_rvalid  <= '0';
				got_raddr   <= '0';
			else
				-- address handshake:
				if S_AXI_ARVALID = '1' and axi_arready = '1' then
					axi_raddr   <= S_AXI_ARADDR(C_S_AXI_ADDR_WIDTH-1 downto 0);
					got_raddr   <= '1';
					axi_arready <= '0';
				else
					axi_arready <= not got_raddr;
				end if;

				-- response handshake:
				if S_AXI_RREADY = '1' and axi_rvalid = '1' then
					axi_rvalid <= '0';
					got_raddr <= '0';
				else

				-- register read handling:
				if got_raddr = '1' then
					case to_integer(unsigned(axi_raddr(C_S_AXI_ADDR_WIDTH-1 downto 2))) is
					when 0 =>
						axi_rresp <= b"00";
						axi_rdata <= pad & irq_inputs;
						axi_rvalid <= '1';
					when 1 =>
						axi_rresp <= b"00";
						axi_rdata <= pad & (irq_inputs and irq_enable(INTERRUPT_SOURCES-1 downto 0));
						axi_rvalid <= '1';
					when 2 =>
						axi_rresp <= b"00";
						axi_rdata <= pad & irq_enable(INTERRUPT_SOURCES-1 downto 0);
						axi_rvalid <= '1';
					when others =>
						axi_rresp <= b"11";
						axi_rdata <= X"00000000";
						axi_rvalid <= '1';
					end case;
				end if;
				end if;
			end if;
		end if;
	end process;

	IRQ <= or (irq_inputs and irq_enable(INTERRUPT_SOURCES-1 downto 0));

end architecture;
