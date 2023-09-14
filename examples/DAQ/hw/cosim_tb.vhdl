-- DAQ testbench for QEMU co-simulation.
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

library axi;
	use axi.all;
	use axi.axi_lite_pkg.all;
	use axi.axi_pkg.all;

library common;
	use common.addr_pkg.all;

library cosim;
	use cosim.all;

use work.all;

entity testbench is
end entity;

architecture functional of testbench is
	-- CPU interface:
	signal clk : std_logic;
	signal rst : std_logic;
	signal irq_cpu : std_logic_vector(0 downto 0) := b"0";
	signal axi_cpu : t_axilite_if(
		write_address_channel(awaddr(31 downto 0)),
		write_data_channel(wdata(31 downto 0), wstrb(3 downto 0)),
		read_address_channel(araddr(31 downto 0)),
		read_data_channel(rdata(31 downto 0))
	);

	-- Peripheral interfaces:
	subtype peripherals is integer range 0 to 5;
	type axi_peripheral_buses_t is array (integer range <>) of t_axilite_if(
		write_address_channel(awaddr(31 downto 0)),
		write_data_channel(wdata(31 downto 0), wstrb(3 downto 0)),
		read_address_channel(araddr(31 downto 0)),
		read_data_channel(rdata(31 downto 0))
	);
	signal axi_peripheral_buses : axi_peripheral_buses_t(peripherals);

	-- AXI xbar:
	constant peripheral_addrs : addr_and_mask_vec_t(peripherals) := (
		0 => ( addr => X"00000000", mask => X"FFFFF000" ), -- UART
		1 => ( addr => X"00001000", mask => X"FFFFF000" ), -- PWM1
		2 => ( addr => X"00002000", mask => X"FFFFF000" ), -- PWM2
		3 => ( addr => X"00003000", mask => X"FFFFF000" ), -- DAQ
		4 => ( addr => X"00004000", mask => X"FFFFF000" ), -- INTC
		5 => ( addr => X"00010000", mask => X"FFFF0000" )  -- MEM  (64 KiB)
	);
	signal xbar_outputs_m2s : axi_lite_m2s_vec_t(peripherals);
	signal xbar_outputs_s2m : axi_lite_s2m_vec_t(peripherals);

	-- UART signals:
	signal host_rx : std_logic;
	signal host_tx : std_logic;

	-- INTC inputs:
	signal irqs : std_logic_vector(3 downto 0) := (others => '0');

	-- RAM signals:
	signal Aaddr : std_logic_vector (15 downto 0);
	signal Adout : std_logic_vector (31 downto 0);
	signal Adin  : std_logic_vector (31 downto 0);
	signal Awe   : std_logic_vector (3 downto 0);
	signal Aen   : std_logic;
	signal Baddr : std_logic_vector (15 downto 0);
	signal Bdout : std_logic_vector (31 downto 0);
	signal Bdin  : std_logic_vector (31 downto 0);
	signal Bwe   : std_logic_vector ( 3 downto 0);
	signal Ben   : std_logic;

	-- PWM signals:
	signal pwm1  : std_logic;
	signal pwm2  : std_logic;

	-- DAQ signals:
	signal mem_enable : std_logic;
	signal pwm_real, analog : real := 0.0;
	signal data : signed(31 downto 0);

begin

	xbar : entity axi_lite_mux
	generic map (slave_addrs => peripheral_addrs)
	port map (
		clk => clk,
		-- xbar port to manager interface (CPU):
		axi_lite_m2s.write.aw.addr   => unsigned(axi_cpu.write_address_channel.awaddr),
		axi_lite_m2s.write.aw.valid  => axi_cpu.write_address_channel.awvalid,
		axi_lite_m2s.write.w.data    => axi_cpu.write_data_channel.wdata,
		axi_lite_m2s.write.w.strb    => axi_cpu.write_data_channel.wstrb,
		axi_lite_m2s.write.w.valid   => axi_cpu.write_data_channel.wvalid,
		axi_lite_m2s.write.b.ready   => axi_cpu.write_response_channel.bready,
		axi_lite_m2s.read.ar.addr    => unsigned(axi_cpu.read_address_channel.araddr),
		axi_lite_m2s.read.ar.valid   => axi_cpu.read_address_channel.arvalid,
		axi_lite_m2s.read.r.ready    => axi_cpu.read_data_channel.rready,
		axi_lite_s2m.write.aw.ready  => axi_cpu.write_address_channel.awready,
		axi_lite_s2m.write.w.ready   => axi_cpu.write_data_channel.wready,
		axi_lite_s2m.write.b.resp    => axi_cpu.write_response_channel.bresp,
		axi_lite_s2m.write.b.valid   => axi_cpu.write_response_channel.bvalid,
		axi_lite_s2m.read.ar.ready   => axi_cpu.read_address_channel.arready,
		axi_lite_s2m.read.r.data     => axi_cpu.read_data_channel.rdata,
		axi_lite_s2m.read.r.resp     => axi_cpu.read_data_channel.rresp,
		axi_lite_s2m.read.r.valid    => axi_cpu.read_data_channel.rvalid,
		-- xbar ports to subordinate interfaces:
		axi_lite_m2s_vec => xbar_outputs_m2s,
		axi_lite_s2m_vec => xbar_outputs_s2m
	);

	subs : for x in peripherals generate
		axi_peripheral_buses(x).write_address_channel.awaddr  <= std_ulogic_vector(xbar_outputs_m2s(x).write.aw.addr);
		axi_peripheral_buses(x).write_address_channel.awvalid <= xbar_outputs_m2s(x).write.aw.valid  ;
		axi_peripheral_buses(x).write_data_channel.wdata      <= xbar_outputs_m2s(x).write.w.data    ;
		axi_peripheral_buses(x).write_data_channel.wstrb      <= xbar_outputs_m2s(x).write.w.strb    ;
		axi_peripheral_buses(x).write_data_channel.wvalid     <= xbar_outputs_m2s(x).write.w.valid   ;
		axi_peripheral_buses(x).write_response_channel.bready <= xbar_outputs_m2s(x).write.b.ready   ;
		axi_peripheral_buses(x).read_address_channel.araddr   <= std_ulogic_vector(xbar_outputs_m2s(x).read.ar.addr);
		axi_peripheral_buses(x).read_address_channel.arvalid  <= xbar_outputs_m2s(x).read.ar.valid   ;
		axi_peripheral_buses(x).read_data_channel.rready      <= xbar_outputs_m2s(x).read.r.ready    ;
		xbar_outputs_s2m(x).write.aw.ready  <= axi_peripheral_buses(x).write_address_channel.awready ;
		xbar_outputs_s2m(x).write.w.ready   <= axi_peripheral_buses(x).write_data_channel.wready     ;
		xbar_outputs_s2m(x).write.b.resp    <= axi_peripheral_buses(x).write_response_channel.bresp  ;
		xbar_outputs_s2m(x).write.b.valid   <= axi_peripheral_buses(x).write_response_channel.bvalid ;
		xbar_outputs_s2m(x).read.ar.ready   <= axi_peripheral_buses(x).read_address_channel.arready  ;
		xbar_outputs_s2m(x).read.r.data     <= axi_peripheral_buses(x).read_data_channel.rdata       ;
		xbar_outputs_s2m(x).read.r.resp     <= axi_peripheral_buses(x).read_data_channel.rresp       ;
		xbar_outputs_s2m(x).read.r.valid    <= axi_peripheral_buses(x).read_data_channel.rvalid      ;
	end generate;

	dev_uart : entity UART_interface
	port map (
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi_peripheral_buses(0).write_address_channel.awaddr(4 downto 0),
		S_AXI_AWPROT    => axi_peripheral_buses(0).write_address_channel.awprot,
		S_AXI_AWVALID   => axi_peripheral_buses(0).write_address_channel.awvalid,
		S_AXI_AWREADY   => axi_peripheral_buses(0).write_address_channel.awready,
		S_AXI_WDATA     => axi_peripheral_buses(0).write_data_channel.wdata,
		S_AXI_WSTRB     => axi_peripheral_buses(0).write_data_channel.wstrb,
		S_AXI_WVALID    => axi_peripheral_buses(0).write_data_channel.wvalid,
		S_AXI_WREADY    => axi_peripheral_buses(0).write_data_channel.wready,
		S_AXI_BRESP     => axi_peripheral_buses(0).write_response_channel.bresp,
		S_AXI_BVALID    => axi_peripheral_buses(0).write_response_channel.bvalid,
		S_AXI_BREADY    => axi_peripheral_buses(0).write_response_channel.bready,
		S_AXI_ARADDR    => axi_peripheral_buses(0).read_address_channel.araddr(4 downto 0),
		S_AXI_ARPROT    => axi_peripheral_buses(0).read_address_channel.arprot,
		S_AXI_ARVALID   => axi_peripheral_buses(0).read_address_channel.arvalid,
		S_AXI_ARREADY   => axi_peripheral_buses(0).read_address_channel.arready,
		S_AXI_RDATA     => axi_peripheral_buses(0).read_data_channel.rdata,
		S_AXI_RRESP     => axi_peripheral_buses(0).read_data_channel.rresp,
		S_AXI_RVALID    => axi_peripheral_buses(0).read_data_channel.rvalid,
		S_AXI_RREADY    => axi_peripheral_buses(0).read_data_channel.rready,
		------------------------------------------------------------------------
		uart_tx         => host_rx,
		uart_rx         => host_tx,
		irq             => irqs(0)
	);

	dev_pwm1 : entity PWMtimer
	port map (
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi_peripheral_buses(1).write_address_channel.awaddr(4 downto 0),
		S_AXI_AWPROT    => axi_peripheral_buses(1).write_address_channel.awprot,
		S_AXI_AWVALID   => axi_peripheral_buses(1).write_address_channel.awvalid,
		S_AXI_AWREADY   => axi_peripheral_buses(1).write_address_channel.awready,
		S_AXI_WDATA     => axi_peripheral_buses(1).write_data_channel.wdata,
		S_AXI_WSTRB     => axi_peripheral_buses(1).write_data_channel.wstrb,
		S_AXI_WVALID    => axi_peripheral_buses(1).write_data_channel.wvalid,
		S_AXI_WREADY    => axi_peripheral_buses(1).write_data_channel.wready,
		S_AXI_BRESP     => axi_peripheral_buses(1).write_response_channel.bresp,
		S_AXI_BVALID    => axi_peripheral_buses(1).write_response_channel.bvalid,
		S_AXI_BREADY    => axi_peripheral_buses(1).write_response_channel.bready,
		S_AXI_ARADDR    => axi_peripheral_buses(1).read_address_channel.araddr(4 downto 0),
		S_AXI_ARPROT    => axi_peripheral_buses(1).read_address_channel.arprot,
		S_AXI_ARVALID   => axi_peripheral_buses(1).read_address_channel.arvalid,
		S_AXI_ARREADY   => axi_peripheral_buses(1).read_address_channel.arready,
		S_AXI_RDATA     => axi_peripheral_buses(1).read_data_channel.rdata,
		S_AXI_RRESP     => axi_peripheral_buses(1).read_data_channel.rresp,
		S_AXI_RVALID    => axi_peripheral_buses(1).read_data_channel.rvalid,
		S_AXI_RREADY    => axi_peripheral_buses(1).read_data_channel.rready,
		------------------------------------------------------------------------
		pwm_out         => pwm1,
		irq             => irqs(1)
	);

	dev_pwm2 : entity PWMtimer
	port map (
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi_peripheral_buses(2).write_address_channel.awaddr(4 downto 0),
		S_AXI_AWPROT    => axi_peripheral_buses(2).write_address_channel.awprot,
		S_AXI_AWVALID   => axi_peripheral_buses(2).write_address_channel.awvalid,
		S_AXI_AWREADY   => axi_peripheral_buses(2).write_address_channel.awready,
		S_AXI_WDATA     => axi_peripheral_buses(2).write_data_channel.wdata,
		S_AXI_WSTRB     => axi_peripheral_buses(2).write_data_channel.wstrb,
		S_AXI_WVALID    => axi_peripheral_buses(2).write_data_channel.wvalid,
		S_AXI_WREADY    => axi_peripheral_buses(2).write_data_channel.wready,
		S_AXI_BRESP     => axi_peripheral_buses(2).write_response_channel.bresp,
		S_AXI_BVALID    => axi_peripheral_buses(2).write_response_channel.bvalid,
		S_AXI_BREADY    => axi_peripheral_buses(2).write_response_channel.bready,
		S_AXI_ARADDR    => axi_peripheral_buses(2).read_address_channel.araddr(4 downto 0),
		S_AXI_ARPROT    => axi_peripheral_buses(2).read_address_channel.arprot,
		S_AXI_ARVALID   => axi_peripheral_buses(2).read_address_channel.arvalid,
		S_AXI_ARREADY   => axi_peripheral_buses(2).read_address_channel.arready,
		S_AXI_RDATA     => axi_peripheral_buses(2).read_data_channel.rdata,
		S_AXI_RRESP     => axi_peripheral_buses(2).read_data_channel.rresp,
		S_AXI_RVALID    => axi_peripheral_buses(2).read_data_channel.rvalid,
		S_AXI_RREADY    => axi_peripheral_buses(2).read_data_channel.rready,
		------------------------------------------------------------------------
		pwm_out         => pwm2,
		irq             => irqs(2)
	);

	dev_daq : entity DAQ
	port map (
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi_peripheral_buses(3).write_address_channel.awaddr(4 downto 0),
		S_AXI_AWPROT    => axi_peripheral_buses(3).write_address_channel.awprot,
		S_AXI_AWVALID   => axi_peripheral_buses(3).write_address_channel.awvalid,
		S_AXI_AWREADY   => axi_peripheral_buses(3).write_address_channel.awready,
		S_AXI_WDATA     => axi_peripheral_buses(3).write_data_channel.wdata,
		S_AXI_WSTRB     => axi_peripheral_buses(3).write_data_channel.wstrb,
		S_AXI_WVALID    => axi_peripheral_buses(3).write_data_channel.wvalid,
		S_AXI_WREADY    => axi_peripheral_buses(3).write_data_channel.wready,
		S_AXI_BRESP     => axi_peripheral_buses(3).write_response_channel.bresp,
		S_AXI_BVALID    => axi_peripheral_buses(3).write_response_channel.bvalid,
		S_AXI_BREADY    => axi_peripheral_buses(3).write_response_channel.bready,
		S_AXI_ARADDR    => axi_peripheral_buses(3).read_address_channel.araddr(4 downto 0),
		S_AXI_ARPROT    => axi_peripheral_buses(3).read_address_channel.arprot,
		S_AXI_ARVALID   => axi_peripheral_buses(3).read_address_channel.arvalid,
		S_AXI_ARREADY   => axi_peripheral_buses(3).read_address_channel.arready,
		S_AXI_RDATA     => axi_peripheral_buses(3).read_data_channel.rdata,
		S_AXI_RRESP     => axi_peripheral_buses(3).read_data_channel.rresp,
		S_AXI_RVALID    => axi_peripheral_buses(3).read_data_channel.rvalid,
		S_AXI_RREADY    => axi_peripheral_buses(3).read_data_channel.rready,
		------------------------------------------------------------------------
		mem_bank        => Baddr(15),
		mem_enable      => mem_enable,
		mem_interrupt   => irqs(3)
	);

	dev_intc : entity IRQ_controller
	generic map (
		INTERRUPT_SOURCES => 4
	)
	port map (
		irq_inputs => irqs,
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi_peripheral_buses(4).write_address_channel.awaddr(3 downto 0),
		S_AXI_AWPROT    => axi_peripheral_buses(4).write_address_channel.awprot,
		S_AXI_AWVALID   => axi_peripheral_buses(4).write_address_channel.awvalid,
		S_AXI_AWREADY   => axi_peripheral_buses(4).write_address_channel.awready,
		S_AXI_WDATA     => axi_peripheral_buses(4).write_data_channel.wdata,
		S_AXI_WSTRB     => axi_peripheral_buses(4).write_data_channel.wstrb,
		S_AXI_WVALID    => axi_peripheral_buses(4).write_data_channel.wvalid,
		S_AXI_WREADY    => axi_peripheral_buses(4).write_data_channel.wready,
		S_AXI_BRESP     => axi_peripheral_buses(4).write_response_channel.bresp,
		S_AXI_BVALID    => axi_peripheral_buses(4).write_response_channel.bvalid,
		S_AXI_BREADY    => axi_peripheral_buses(4).write_response_channel.bready,
		S_AXI_ARADDR    => axi_peripheral_buses(4).read_address_channel.araddr(3 downto 0),
		S_AXI_ARPROT    => axi_peripheral_buses(4).read_address_channel.arprot,
		S_AXI_ARVALID   => axi_peripheral_buses(4).read_address_channel.arvalid,
		S_AXI_ARREADY   => axi_peripheral_buses(4).read_address_channel.arready,
		S_AXI_RDATA     => axi_peripheral_buses(4).read_data_channel.rdata,
		S_AXI_RRESP     => axi_peripheral_buses(4).read_data_channel.rresp,
		S_AXI_RVALID    => axi_peripheral_buses(4).read_data_channel.rvalid,
		S_AXI_RREADY    => axi_peripheral_buses(4).read_data_channel.rready,
		------------------------------------------------------------------------
		irq             => irq_cpu(0)
	);

	dev_ramc : entity SRAM_controller
	port map (
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      => clk,
		S_AXI_ARESETN   => rst,
		S_AXI_AWADDR    => axi_peripheral_buses(5).write_address_channel.awaddr(15 downto 0),
		S_AXI_AWPROT    => axi_peripheral_buses(5).write_address_channel.awprot,
		S_AXI_AWVALID   => axi_peripheral_buses(5).write_address_channel.awvalid,
		S_AXI_AWREADY   => axi_peripheral_buses(5).write_address_channel.awready,
		S_AXI_WDATA     => axi_peripheral_buses(5).write_data_channel.wdata,
		S_AXI_WSTRB     => axi_peripheral_buses(5).write_data_channel.wstrb,
		S_AXI_WVALID    => axi_peripheral_buses(5).write_data_channel.wvalid,
		S_AXI_WREADY    => axi_peripheral_buses(5).write_data_channel.wready,
		S_AXI_BRESP     => axi_peripheral_buses(5).write_response_channel.bresp,
		S_AXI_BVALID    => axi_peripheral_buses(5).write_response_channel.bvalid,
		S_AXI_BREADY    => axi_peripheral_buses(5).write_response_channel.bready,
		S_AXI_ARADDR    => axi_peripheral_buses(5).read_address_channel.araddr(15 downto 0),
		S_AXI_ARPROT    => axi_peripheral_buses(5).read_address_channel.arprot,
		S_AXI_ARVALID   => axi_peripheral_buses(5).read_address_channel.arvalid,
		S_AXI_ARREADY   => axi_peripheral_buses(5).read_address_channel.arready,
		S_AXI_RDATA     => axi_peripheral_buses(5).read_data_channel.rdata,
		S_AXI_RRESP     => axi_peripheral_buses(5).read_data_channel.rresp,
		S_AXI_RVALID    => axi_peripheral_buses(5).read_data_channel.rvalid,
		S_AXI_RREADY    => axi_peripheral_buses(5).read_data_channel.rready,
		------------------------------------------------------------------------
		A    => Aaddr,
		Din  => Adout,
		Dout => Adin,
		WE   => Awe,
		EN   => Aen
	);

	dev_ramw : entity mem_writer
	port map (
		clk => clk,
		A   => Baddr,
		D   => Bdin,
		EN  => Ben,
		WE  => Bwe,
		data_input( 31 downto  0) => std_logic_vector(data),
		data_input(127 downto 32) => (others => '0'),
		data_valid    => pwm1,
		enable        => mem_enable
	);

	mem : entity DPRAM
	port map (
		Arst  => not rst,
		Aclk  => clk,
		Aaddr => Aaddr,
		Adout => Adout,
		Adin  => Adin ,
		Awe   => Awe  ,
		Aen   => Aen  ,
		Brst  => not rst,
		Bclk  => clk,
		Baddr => Baddr,
		Bdout => open ,
		Bdin  => Bdin ,
		Bwe   => Bwe  ,
		Ben   => Ben
	);

	cpu : entity CPUemu
	generic map (fifo_path => "/tmp/test/fifo")
	port map (
		M_AXI_ACLK      => clk,
		M_AXI_ARESETN   => rst,
		M_AXI_AWADDR    => axi_cpu.write_address_channel.awaddr,
		M_AXI_AWPROT    => axi_cpu.write_address_channel.awprot,
		M_AXI_AWVALID   => axi_cpu.write_address_channel.awvalid,
		M_AXI_AWREADY   => axi_cpu.write_address_channel.awready,
		M_AXI_WDATA     => axi_cpu.write_data_channel.wdata,
		M_AXI_WSTRB     => axi_cpu.write_data_channel.wstrb,
		M_AXI_WVALID    => axi_cpu.write_data_channel.wvalid,
		M_AXI_WREADY    => axi_cpu.write_data_channel.wready,
		M_AXI_BRESP     => axi_cpu.write_response_channel.bresp,
		M_AXI_BVALID    => axi_cpu.write_response_channel.bvalid,
		M_AXI_BREADY    => axi_cpu.write_response_channel.bready,
		M_AXI_ARADDR    => axi_cpu.read_address_channel.araddr,
		M_AXI_ARPROT    => axi_cpu.read_address_channel.arprot,
		M_AXI_ARVALID   => axi_cpu.read_address_channel.arvalid,
		M_AXI_ARREADY   => axi_cpu.read_address_channel.arready,
		M_AXI_RDATA     => axi_cpu.read_data_channel.rdata,
		M_AXI_RRESP     => axi_cpu.read_data_channel.rresp,
		M_AXI_RVALID    => axi_cpu.read_data_channel.rvalid,
		M_AXI_RREADY    => axi_cpu.read_data_channel.rready,
		M_IRQ_LEVEL     => irq_cpu
	);

	pty : entity PTYemu
	generic map (pty_path => "/tmp/test/pty")
	port map (
		rx => host_rx,
		tx => host_tx
	);


	-- analog part emulation:

	DA : process (clk, pwm1)
		constant k : real := 1.0E-3;
		variable x : real := 0.0;
		variable a : real := 0.0;
	begin
		if rising_edge(clk) then
			x := +1.0 when pwm2 = '1' else -1.0 when pwm2 = '0' else 0.0;
			a := a + x;
		end if;
		if rising_edge(pwm1) then
			pwm_real <= a * k;
			a := 0.0;
		end if;
	end process;

	LP : entity lowpass
	port map (
		clk => pwm1,
		clk_enable => '1',
		reset => not rst,
		filter_in  => pwm_real,
		filter_out => analog
	);

	AD : process (analog)
	begin
		data <= to_signed(integer(analog * real(2**20)), 32);
	end process;

end architecture;
