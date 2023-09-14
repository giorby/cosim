GHDLROOT  := /tmp/test/GHDL
GHDLFLAGS := --std=08 -frelaxed -fsynopsys
GHDL      := $(GHDLROOT)/bin/ghdl
TARGET    := /tmp/test/vhdl.run

# Elaboration target
$(TARGET): cosim_tb.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ testbench

%.o : %.vhdl
	$(GHDL) -a $(GHDLFLAGS) $<

# Files dependences:
#
cosim_tb.o: libs serial.o pwm.o daq.o dpram.o ramc.o intc.o lowpass.o

libs:
	$(GHDL) -a --std=08 --work=math   axi_xbar/math_pkg.vhd 
	$(GHDL) -a --std=08 --work=common axi_xbar/types_pkg.vhd
	$(GHDL) -a --std=08 --work=common axi_xbar/addr_pkg.vhd 
	$(GHDL) -a --std=08 --work=axi    axi_xbar/axi_pkg.vhd
	$(GHDL) -a --std=08 --work=axi    axi_xbar/axi_lite_pkg.vhd
	$(GHDL) -a --std=08 --work=axi    axi_xbar/axi_lite_mux.vhd

