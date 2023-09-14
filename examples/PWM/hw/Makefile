GHDLROOT  := /tmp/test/GHDL
GHDLFLAGS := --std=08 -frelaxed -fsynopsys
GHDL      := $(GHDLROOT)/bin/ghdl
TARGET    := /tmp/test/vhdl.run

# Elaboration target
$(TARGET): cosim_tb.o pwm.o
	$(GHDL) -e $(GHDLFLAGS) -o $@ testbench

%.o : %.vhdl
	$(GHDL) -a $(GHDLFLAGS) $<

# Files dependences:
#
cosim_tb.o: pwm.o
