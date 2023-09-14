-- Pipe-controlled AXI bus manager for HW/SW cosimulation.
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: Apache-2.0


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

library std;
	use std.env.all;
	use std.textio.all;

library uvvm_util;
	context uvvm_util.uvvm_util_context;

library bitvis_vip_axilite;
	use bitvis_vip_axilite.axilite_bfm_pkg.all;

entity CPUemu is
	generic (
		clk_period : time       := 10 ns;
		clk_delay  : natural    := 10;
		rst_delay  : natural    := 10;
		fifo_path  : string
	);
	port (
		------------------------------------------------------------------------
		-- AXI manager bus:
		------------------------------------------------------------------------
		M_AXI_ACLK      : out std_logic;
		M_AXI_ARESETN   : out std_logic;
		M_AXI_AWADDR    : out std_logic_vector(31 downto 0);
		M_AXI_AWPROT    : out std_logic_vector( 2 downto 0);
		M_AXI_AWVALID   : out std_logic;
		M_AXI_AWREADY   : in  std_logic;
		M_AXI_WDATA     : out std_logic_vector(31 downto 0);
		M_AXI_WSTRB     : out std_logic_vector( 3 downto 0);
		M_AXI_WVALID    : out std_logic;
		M_AXI_WREADY    : in  std_logic;
		M_AXI_BRESP     : in  std_logic_vector( 1 downto 0);
		M_AXI_BVALID    : in  std_logic;
		M_AXI_BREADY    : out std_logic;
		M_AXI_ARADDR    : out std_logic_vector(31 downto 0);
		M_AXI_ARPROT    : out std_logic_vector( 2 downto 0);
		M_AXI_ARVALID   : out std_logic;
		M_AXI_ARREADY   : in  std_logic;
		M_AXI_RDATA     : in  std_logic_vector(31 downto 0);
		M_AXI_RRESP     : in  std_logic_vector( 1 downto 0);
		M_AXI_RVALID    : in  std_logic;
		M_AXI_RREADY    : out std_logic;
		------------------------------------------------------------------------
		M_IRQ_LEVEL     : in  std_logic_vector
	);
end entity;

architecture behavioral of CPUemu is
	type reply_t is record
		tsid : time;
		data : string(1 to 10);
	end record;
	signal   reply      : reply_t;
	signal   clk_enable : boolean    := false;
	signal   clk        : std_logic  := '0';
	signal   rst        : std_logic  := '0';
	signal   reset      : std_logic  := '1';
	signal   irq        : std_logic_vector(31 downto 0) := (others => '0');
	signal   axi_if     : t_axilite_if(
		write_address_channel(awaddr(31 downto 0)),
		write_data_channel(wdata(31 downto 0), wstrb(3 downto 0)),
		read_address_channel(araddr(31 downto 0)),
		read_data_channel(rdata(31 downto 0))
	) := init_axilite_if_signals(32, 32);

begin
	-- AXI bus connections:
	M_AXI_ACLK    <= clk;
	M_AXI_ARESETN <= not reset;
	-- write address channel:
	M_AXI_AWADDR  <= axi_if.write_address_channel.awaddr;
	M_AXI_AWPROT  <= axi_if.write_address_channel.awprot;
	M_AXI_AWVALID <= axi_if.write_address_channel.awvalid;
	axi_if.write_address_channel.awready <= M_AXI_AWREADY;
	-- write data channel:
	M_AXI_WDATA   <= axi_if.write_data_channel.wdata;
	M_AXI_WSTRB   <= axi_if.write_data_channel.wstrb;
	M_AXI_WVALID  <= axi_if.write_data_channel.wvalid;
	axi_if.write_data_channel.wready <= M_AXI_WREADY;
	-- response channel:
	axi_if.write_response_channel.bresp  <= M_AXI_BRESP;
	axi_if.write_response_channel.bvalid <= M_AXI_BVALID;
	M_AXI_BREADY  <= axi_if.write_response_channel.bready;
	-- read address channel:
	M_AXI_ARADDR  <= axi_if.read_address_channel.araddr;
	M_AXI_ARPROT  <= axi_if.read_address_channel.arprot;
	M_AXI_ARVALID <= axi_if.read_address_channel.arvalid;
	axi_if.read_address_channel.arready <= M_AXI_ARREADY;
	-- read data channel:
	axi_if.read_data_channel.rdata  <= M_AXI_RDATA;
	axi_if.read_data_channel.rresp  <= M_AXI_RRESP;
	axi_if.read_data_channel.rvalid <= M_AXI_RVALID;
	M_AXI_RREADY  <= axi_if.read_data_channel.rready;
	-- interrupts:
	irq(M_IRQ_LEVEL'range) <= M_IRQ_LEVEL;

	-- clock handling:
	clk_enable    <= true after clk_delay * clk_period;
	clock_generator(clk, clk_enable, clk_period, "CPU clock");

	reset_generator : process(rst, clk)
		variable count : natural := rst_delay;
	begin
		if rst = '1' then
			count := rst_delay;
			reset <= '1';
		elsif rising_edge(clk) then
			if count > 0 then
				count := count - 1;
			else
				reset <= '0';
			end if;
		end if;
	end process;

	command_processor : process
		file     rd_pipe : text open read_mode is fifo_path & ".out";
		variable rd_line : line;
		variable code : character;
		variable addr : unsigned(31 downto 0);
		variable data : std_logic_vector(31 downto 0);
		variable mask : std_logic_vector( 3 downto 0);
	begin
		while not endfile(rd_pipe) loop
			readline(rd_pipe, rd_line);
			--report rd_line(1 to rd_line'length);
			read(rd_line, code);
			case code is

			when 'W' =>
				 read(rd_line, code); assert code = ':';
				hread(rd_line, addr);
				 read(rd_line, code); assert code = '<';
				 read(rd_line, code); assert code = '=';
				hread(rd_line, data);
				 read(rd_line, code); assert code = '|';
				hread(rd_line, mask);
				-- execute write on bus:
				axilite_write(addr, data, mask, "CPUemu", clk, axi_if);
				-- TODO: error handling? axilite_write consumes BRESP internally
				-- and raises an exception for bus errors... same for reads.
				reply.data <= string'("W=OK      ");
				reply.tsid <= now;
				wait for 0 ns;

			when 'R' =>
				 read(rd_line, code); assert code = ':';
				hread(rd_line, addr);
				-- execute read on bus:
				axilite_read(addr, data, "CPUemu", clk, axi_if);
				reply.data <= string'("R=") & to_hstring(to_bit_vector(data));
				reply.tsid <= now;
				wait for 0 ns;

			when 'T' =>
				 read(rd_line, code); assert code = ':';
				hread(rd_line, data);
				-- just allow VHDL simulator to continue for specified time or until interrupt:
				wait on irq for to_integer(unsigned(data)) * 1 us;
				reply.data <= string'("T=") & to_hstring(to_unsigned(now / 1 us, 32));
				reply.tsid <= now;
				wait for 0 ns;

			when 'X' =>
				 read(rd_line, code); assert code = ':';
				 read(rd_line, code);
				-- process special command:
				if code = 'R' then -- RESET
					rst <= '1', '0' after clk_period;
					wait for clk_period;
					wait until reset = '0';
					wait for clk_period;
				end if;
				if code = 'S' then -- STOP
					file_close(rd_pipe);
					std.env.finish;
					exit;
				end if;

			when others =>
				failure("CPUemu interface - unknown command: '" & code & "'");
			end case;
		end loop;

		wait for clk_delay * clk_period; -- allow some extra time for completion
		std.env.stop;
		wait;
	end process;

	-- replies are handled by a different process to serialize access to the output pipe:
	reply_processor : process(reply, irq, reset)
		file     wr_pipe : text open write_mode is fifo_path & ".in";
		variable wr_line : line;
	begin
		if reply'event then
			write(wr_line, reply.data & CR);
			writeline(wr_pipe, wr_line);
			flush(wr_pipe);
		end if;
		if reset'event then
			if reset = '0' then
				write(wr_line, string'("X=RUNNING ") & CR);
			else
				write(wr_line, string'("X=RESET   ") & CR);
			end if;
			writeline(wr_pipe, wr_line);
			flush(wr_pipe);
		end if;
		if irq'event and irq /= irq'last_value then
			write(wr_line, string'("I=") & to_hstring(irq) & CR);
			writeline(wr_pipe, wr_line);
			flush(wr_pipe);
		end if;
	end process;

end architecture behavioral;
