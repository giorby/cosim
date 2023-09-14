-- Fast UART serial port testbench for QEMU co-simulation.
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: Apache-2.0


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

library uvvm_util;
	context uvvm_util.uvvm_util_context;

library bitvis_vip_axilite;
	use bitvis_vip_axilite.axilite_bfm_pkg.all;

library work;
	use work.all;

library cosim;
	use cosim.all;

entity testbench is
end entity;

architecture functional of testbench is
	-- CPU interface:
	signal clk      : std_logic;
	signal rst      : std_logic;
	signal irq      : std_logic_vector(0 downto 0) := b"0";
	signal axi      : t_axilite_if(
		write_address_channel(awaddr(31 downto 0)),
		write_data_channel(wdata(31 downto 0), wstrb(3 downto 0)),
		read_address_channel(araddr(31 downto 0)),
		read_data_channel(rdata(31 downto 0))
	);
	-- serial lines:
	signal host_rx  : std_logic;
	signal host_tx  : std_logic;
begin

	dut : entity UART_interface
	port map (
		------------------------------------------------------------------------
		-- AXI slave bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi.write_address_channel.awaddr(4 downto 0),
		S_AXI_AWPROT    => axi.write_address_channel.awprot,
		S_AXI_AWVALID   => axi.write_address_channel.awvalid,
		S_AXI_AWREADY   => axi.write_address_channel.awready,
		S_AXI_WDATA     => axi.write_data_channel.wdata,
		S_AXI_WSTRB     => axi.write_data_channel.wstrb,
		S_AXI_WVALID    => axi.write_data_channel.wvalid,
		S_AXI_WREADY    => axi.write_data_channel.wready,
		S_AXI_BRESP     => axi.write_response_channel.bresp,
		S_AXI_BVALID    => axi.write_response_channel.bvalid,
		S_AXI_BREADY    => axi.write_response_channel.bready,
		S_AXI_ARADDR    => axi.read_address_channel.araddr(4 downto 0),
		S_AXI_ARPROT    => axi.read_address_channel.arprot,
		S_AXI_ARVALID   => axi.read_address_channel.arvalid,
		S_AXI_ARREADY   => axi.read_address_channel.arready,
		S_AXI_RDATA     => axi.read_data_channel.rdata,
		S_AXI_RRESP     => axi.read_data_channel.rresp,
		S_AXI_RVALID    => axi.read_data_channel.rvalid,
		S_AXI_RREADY    => axi.read_data_channel.rready,
		------------------------------------------------------------------------
		uart_tx         => host_rx,
		uart_rx         => host_tx,
		irq             => irq(0)
	);

	cpu : entity CPUemu
	generic map (fifo_path => "/tmp/test/fifo")
	port map (
		M_AXI_ACLK      => clk,
		M_AXI_ARESETN   => rst,
		M_AXI_AWADDR    => axi.write_address_channel.awaddr,
		M_AXI_AWPROT    => axi.write_address_channel.awprot,
		M_AXI_AWVALID   => axi.write_address_channel.awvalid,
		M_AXI_AWREADY   => axi.write_address_channel.awready,
		M_AXI_WDATA     => axi.write_data_channel.wdata,
		M_AXI_WSTRB     => axi.write_data_channel.wstrb,
		M_AXI_WVALID    => axi.write_data_channel.wvalid,
		M_AXI_WREADY    => axi.write_data_channel.wready,
		M_AXI_BRESP     => axi.write_response_channel.bresp,
		M_AXI_BVALID    => axi.write_response_channel.bvalid,
		M_AXI_BREADY    => axi.write_response_channel.bready,
		M_AXI_ARADDR    => axi.read_address_channel.araddr,
		M_AXI_ARPROT    => axi.read_address_channel.arprot,
		M_AXI_ARVALID   => axi.read_address_channel.arvalid,
		M_AXI_ARREADY   => axi.read_address_channel.arready,
		M_AXI_RDATA     => axi.read_data_channel.rdata,
		M_AXI_RRESP     => axi.read_data_channel.rresp,
		M_AXI_RVALID    => axi.read_data_channel.rvalid,
		M_AXI_RREADY    => axi.read_data_channel.rready,
		M_IRQ_LEVEL     => irq
	);

	host : entity PTYemu
	generic map (pty_path => "/tmp/test/pty")
	port map (
		rx => host_rx,
		tx => host_tx
	);

end architecture;
