-- Fast UART serial port implementation.
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

-- This is a FIFO-based UART that operates at a fixed baud rate of 1/10 of the clock frequency.
-- Up to 4 bytes of data can be enqueued at a time with a single 32-bit write.
-- Reads always return 9 bits of data, with the ninth bit denoting a special event.


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

library unisim;
	use unisim.vcomponents.all;

library unimacro;
	use unimacro.vcomponents.all;


entity UART_transmitter is
	port (
	-- timing signals:
		reset   : in  std_logic;
		clk     : in  std_logic;
		enable  : in  std_logic;
	-- FIFO input:
		data    : in  std_logic_vector(8 downto 0);
		write   : in  std_logic;
	-- FIFO status:
		empty   : out std_logic;
		half    : out std_logic;
		full    : out std_logic;
		active  : out std_logic;
	-- output:
		uart_tx : out std_logic
	);
end entity;

architecture mixed of UART_transmitter is
	signal fifo_empty : std_logic;
	signal fifo_out   : std_logic_vector(8 downto 0);
	signal fifo_rd    : std_logic_vector(1 downto 0);
	signal shifter    : std_logic_vector(11 downto 0);
	signal txcnt      : unsigned(3 downto 0);
begin

	FIFO : FIFO_SYNC_MACRO
	generic map (
		DEVICE => "7SERIES",
		ALMOST_FULL_OFFSET  => X"0200",  -- asserts        if at >= 75% capacity [unused]
		ALMOST_EMPTY_OFFSET => X"0400",  -- asserts "half" if at <= 50% capacity [IRQ]
		DATA_WIDTH => 9,
		FIFO_SIZE => "18Kb")             -- Target BRAM, "18Kb" or "36Kb"
	port map (
		ALMOSTEMPTY => half,
		ALMOSTFULL  => open,
		EMPTY       => fifo_empty,
		FULL        => full,
		RDCOUNT     => open,
		RDERR       => open,
		WRCOUNT     => open,
		WRERR       => open,
		CLK         => clk,
		DI          => data,
		DO          => fifo_out,
		RDEN        => fifo_rd(0),
		WREN        => write,
		RST         => reset
	);

	tx : process (clk) is
		variable txdiv : unsigned(3 downto 0);
	begin
		if rising_edge(clk) then
			if reset = '1' then
				empty   <= '0';
				active  <= '0';
				uart_tx <= '0';
				fifo_rd <= B"00";
				shifter <= X"800";
				txcnt   <= X"F";
				txdiv   := X"0";
			else

				if txdiv = 9 then
					txdiv := X"0";
					empty   <= fifo_empty;
					uart_tx <= shifter(0);
					shifter <= shifter(11) & shifter(11 downto 1);
					if txcnt > 0 then
						txcnt  <= txcnt - 1;
					else
						active <= '0';
					end if;
				else
					if enable = '1' then
						txdiv := txdiv + 1;
					else
						txdiv := X"0";
					end if;
				end if;

				fifo_rd <= fifo_rd(0) & B"0";
				if txcnt = 0 then
					if fifo_rd = B"00" then
						if fifo_empty = '0' then
							fifo_rd <= B"01";
						end if;
					end if;
				end if;

				if fifo_rd(1) = '1' then
					active <= '1';
					if fifo_out(8) = '0' then
						-- regular byte to send:
						shifter <= B"111" & fifo_out(7 downto 0) & B"0";
						txcnt   <= X"A";
					elsif fifo_out(7 downto 0) = X"FE" then
						-- framing error:
						shifter <= X"CCC";
						txcnt   <= X"B";
					elsif fifo_out(7 downto 1) & B"0" = X"C0" then
						-- idle or break:
						shifter <= (others => fifo_out(0));
						txcnt   <= X"C";
					end if;
				end if;

			end if;
		end if;
	end process;
end architecture;

---------------------------------------------------------------


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

library unisim;
	use unisim.vcomponents.all;

library unimacro;
	use unimacro.vcomponents.all;

entity UART_receiver is
	port (
	-- timing signals:
		reset   : in  std_logic;
		clk     : in  std_logic;
		enable  : in  std_logic;
	-- FIFO output:
		data    : out std_logic_vector(8 downto 0);
		read    : in  std_logic;
	-- FIFO status:
		empty   : out std_logic;
		near    : out std_logic;
		half    : out std_logic;
		full    : out std_logic;
		active  : out std_logic;
		special : out std_logic;
	-- line status;
		level   : out std_logic;
	-- input:
		uart_rx : in  std_logic
	);
end entity;

architecture mixed of UART_receiver is
	signal fifo_in   : std_logic_vector(8 downto 0);
	signal fifo_wr   : std_logic;
	signal shifter   : std_logic_vector(9 downto 0);
	signal rxcnt     : unsigned(3 downto 0);
	signal timer     : unsigned(7 downto 0) := (others => '0'); -- for idle detection
	signal specials  : unsigned(9 downto 0) := (others => '0'); -- to count special characters in FIFO
	signal rx_now    : std_logic; -- synchronized RX line
	signal rx_old    : std_logic; -- delayed version of rx_now
begin

	synchonizer : process (clk) is
		variable rx_syn : std_logic;
	begin
		if rising_edge(clk) then
			rx_old <= rx_now;
			rx_now <= rx_syn;
			rx_syn := uart_rx;
		end if;
	end process;

	FIFO : FIFO_SYNC_MACRO
	generic map (
		DEVICE => "7SERIES",
		ALMOST_FULL_OFFSET  => X"0400",  -- asserts "half" if at >= 50% capacity [IRQ]
		ALMOST_EMPTY_OFFSET => X"0600",  -- asserts "near" if at <= 75% capacity [RTS]
		DATA_WIDTH => 9,
		FIFO_SIZE => "18Kb")
	port map (
		ALMOSTEMPTY => near,
		ALMOSTFULL  => half,
		EMPTY       => empty,
		FULL        => full,
		RDCOUNT     => open,
		RDERR       => open,
		WRCOUNT     => open,
		WRERR       => open,
		CLK         => clk,
		DI          => fifo_in,
		DO          => data,
		RDEN        => read,
		WREN        => fifo_wr,
		RST         => reset
	);

	rx : process (clk) is
		variable rxdiv : unsigned(3 downto 0);
		variable noise : boolean;
	begin
		if rising_edge(clk) then
			fifo_wr <= '0';
			if reset = '1' or enable = '0' then
				active  <= '0';
				shifter <= B"00" & X"00";
				timer   <= X"00";
				rxcnt   <= X"0";
				rxdiv   := X"0";
				noise   := false;
			else
				if active = '1' or rx_now = '0' then
					timer <= X"00";
				else
					if timer < 255 then
						timer <= timer + 1;
					end if;
					if timer = 100 then
						fifo_in <=     B"1_00000000"; -- FLAG NUL (idle)
						fifo_wr <= '1';
					end if;
				end if;
				if rxcnt = 0 then
					if rxdiv > 0 then
						rxdiv := X"0";
						-- add to fifo:
						if noise then
							fifo_in <= B"1_00011010"; -- FLAG SUB (noise)
						elsif shifter = B"0000000000" then
							fifo_in <= B"1_00000100"; -- FLAG EOT (break)
						elsif shifter(0) /= '0' or shifter(9) /= '1' then
							fifo_in <= B"1_00010101"; -- FLAG NAK (framing)
						else
							fifo_in <= B"0" & shifter(8 downto 1);
						end if;
						fifo_wr <= '1';
					else
						active <= '0';
					end if;
					if rx_now = '0' and rx_old = '1' then
						active <= '1';
						rxcnt <= X"A";
						rxdiv := X"1";
						noise := false;
					end if;
				else
					if rxdiv = 5 then
						if rx_now /= rx_old then
							noise := true;
						end if;
						shifter <= rx_now & shifter(9 downto 1);
						rxcnt <= rxcnt - 1;
					end if;
					if rxdiv = 9 then
						rxdiv := X"0";
					else
						rxdiv := rxdiv + 1;
					end if;
				end if;
			end if;
		end if;
	end process;

	special_detection : process (clk)
		variable last_read : std_logic;
		variable increment : integer range -1 to +1;
	begin
		if rising_edge(clk) then
			if reset = '1' then
				last_read := '0';
				specials  <= (others => '0');
			else
				if fifo_wr = '1' and fifo_in(8) = '1' then
					increment := +1;
				else
					increment :=  0;
				end if;
				if last_read = '1' and data(8) = '1' then
					increment := increment - 1;
				end if;
				if increment > 0 then
					specials <= specials + 1;
				elsif increment < 0 then
					specials <= specials - 1;
				end if;
				last_read := read;
			end if;
		end if;
	end process;
	special <= '0' when specials = 0 else '1';
	level <= rx_old or active;
end architecture;


---------------------------
library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity UART_interface is
	generic (
		C_S_AXI_DATA_WIDTH : integer := 32;
		C_S_AXI_ADDR_WIDTH : integer := 5
	);
	port (
		uart_rx         : in  std_logic := '1';
		uart_tx         : out std_logic;
		uart_cts        : in  std_logic := '1';
		uart_rts        : out std_logic;
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
end UART_interface;

architecture mine of UART_interface is
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

	signal tx_data     : std_logic_vector(8 downto 0);
	signal tx_enable   : std_logic;
	signal tx_push     : std_logic;
	signal tx_empty    : std_logic;
	signal tx_half     : std_logic;
	signal tx_full     : std_logic;
	signal tx_over     : std_logic;
	signal tx_active   : std_logic;
	signal tx_level    : std_logic;
	signal tx_pre      : std_logic;

	signal rx_data     : std_logic_vector(8 downto 0);
	signal rx_enable   : std_logic;
	signal rx_pull     : std_logic;
	signal rx_read     : std_logic;
	signal rx_empty    : std_logic;
	signal rx_half     : std_logic;
	signal rx_full     : std_logic;
	signal rx_over     : std_logic;
	signal rx_active   : std_logic;
	signal rx_ready    : std_logic;
	signal rx_level    : std_logic;
	signal rx_pre      : std_logic;
	signal rx_rts      : std_logic;

	signal loopback    : std_logic;
	signal enable_rts  : std_logic;
	signal enable_cts  : std_logic;
	signal forced_rts  : std_logic;
	signal synced_cts  : std_logic;

	signal irq_mask    : std_logic_vector(7 downto 0);
	signal irq_raw     : std_logic_vector(7 downto 0);

	signal got_raddr : std_logic;
	signal got_waddr : std_logic;
	signal got_wdata : std_logic;

	signal wcount    : natural range 0 to 3;
	signal rcount    : natural range 0 to 3;


begin
	tx : entity work.UART_transmitter
	port map (
		reset   => not S_AXI_ARESETN,
		clk     => S_AXI_ACLK,
		enable  => tx_enable and (synced_cts or not enable_cts),
		data    => tx_data,
		write   => tx_push,
		empty   => tx_empty,
		half    => tx_half,
		full    => tx_full,
		active  => tx_active,
		uart_tx => tx_pre
	);

	rx : entity work.UART_receiver
	port map (
		reset   => not S_AXI_ARESETN,
		clk     => S_AXI_ACLK,
		enable  => rx_enable,
		data    => rx_data,
		read    => rx_pull,
		empty   => rx_empty,
		near    => rx_rts,
		half    => rx_half,
		full    => rx_full,
		special => rx_ready,
		active  => rx_active,
		level   => rx_level,
		uart_rx => rx_pre
	);

	cts_synchronizer : process (S_AXI_ACLK) is
		variable cts : std_logic;
	begin
		if rising_edge(S_AXI_ACLK) then
			synced_cts <= cts;
			cts := uart_cts;
		end if;
	end process;

	-- flow control muxes:
	rx_pre   <= tx_pre when  loopback  else uart_rx;
	uart_tx  <=  '0'   when  loopback  else tx_pre when tx_enable else tx_level;
	uart_rts <= rx_rts when enable_rts else forced_rts;

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
			tx_push <= '0';
			if S_AXI_ARESETN = '0' then
				axi_awready <= '0';
				axi_wready  <= '0';
				axi_bvalid  <= '0';
				got_waddr   <= '0';
				got_wdata   <= '0';
				irq_mask    <= X"00";
				tx_over     <= '0';
				rx_over     <= '0';
				loopback    <= '0';
				enable_rts  <= '0';
				enable_cts  <= '0';
				forced_rts  <= '1';
				rx_enable   <= '0';
				tx_enable   <= '0';
				tx_level    <= '1';
			else

				-- address handshake:
				if S_AXI_AWVALID = '1' and axi_awready = '1' then
					axi_waddr   <= S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH-1 downto 0);
					got_waddr   <= '1';
					axi_awready <= '0';
					wcount      <=  0;
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
					case axi_waddr(4 downto 2) is
					when b"000" => -- DATA register
						if axi_wstrb(wcount) = '1' then
							if tx_full = '1' then
								axi_bresp <= b"10";
								tx_over <= '1';
								done := true;
							else
								tx_data <= b"0" & axi_wdata(wcount * 8 + 7 downto wcount * 8);
								tx_push <= '1';
							end if;
						end if;
						if wcount < 3 then
							wcount <= wcount + 1;
						else
							wcount <= 0;
							done := true;
						end if;
					when b"001" => -- CONTROL register
						if axi_wstrb(0) = '1' then
							-- TX FIFO control register:
							tx_enable <= axi_wdata(7);
							tx_level  <= axi_wdata(5);
							if axi_wdata(6) = '1' then
								tx_data <= X"FF" & B"0";
							else
								tx_data <= X"E0" & axi_wdata(5);
							end if;
							if axi_wdata(4) = '1' then
								tx_push <= '1';
							end if;
							if axi_wdata(3) = '1' then
								tx_over <= '0';
							end if;
							if axi_wdata(0) = '1' then
							--TODO: reset
							end if;
						end if;
						if axi_wstrb(1) = '1' then
							-- RX FIFO control register:
							rx_enable <= axi_wdata(15);
							if axi_wdata(11) = '1' then
								rx_over <= '0';
							end if;
							if axi_wdata(8) = '1' then
							--TODO: reset
							end if;
						end if;
						if axi_wstrb(2) = '1' then
							-- FLOW control register:
							loopback   <= axi_wdata(23);
							enable_rts <= axi_wdata(21);
							enable_rts <= axi_wdata(20);
							forced_rts <= axi_wdata(17);
						end if;
						if axi_wstrb(3) = '1' then
							-- IRQ control register:
							irq_mask <= axi_wdata(31 downto 24);
						end if;
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
	begin
		if rising_edge(S_AXI_ACLK) then
			rx_read <= rx_pull;
			rx_pull <= '0';
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
					case axi_raddr(4 downto 2) is
					when b"000" =>
						if rx_pull = '0' and rx_read = '0' then
							if rx_empty = '1' then
								axi_rresp <= b"00";       -- could signal SLVERR (b"10"), but would make firmware more complicated
								axi_rdata <= X"00000119"; -- FLAG EM
								axi_rvalid <= '1';
							else
								rx_pull <= '1';
							end if;
						elsif rx_pull = '0' and rx_read = '1' then
							axi_rresp <= b"00";
							axi_rdata <= X"0000" & B"0000000" & rx_data;
							axi_rvalid <= '1';
						end if;
					when b"001" =>
						axi_rresp <= b"00";
						axi_rdata <=
							irq_mask &                                                                             -- BYTE 3: IRQ
							loopback & '0' & enable_rts & enable_cts & B"00" & uart_rts & synced_cts &             -- BYTE 2: FLOW
							rx_enable & rx_active & rx_level & rx_ready & rx_over & rx_full & rx_half & rx_empty & -- BYTE 1: RX FIFO
							tx_enable & tx_active & tx_level &  '0'     & tx_over & tx_full & tx_half & tx_empty;  -- BYTE 0: TX FIFO
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

	irq_raw <= synced_cts & rx_active & rx_level & rx_ready & tx_half & (tx_empty and not tx_active) & rx_half & not rx_empty;
	irq <= or (irq_raw and irq_mask);

end architecture;



