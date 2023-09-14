HW/SW Co-Simulation using QEMU and GHDL

Copyright (C) 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
SPDX-License-Identifier: CC-BY-4.0


Description:
This package contains what is needed to co-simulate hardware (HW) designs
modeled in VHDL together with the firmware (FW) that controls them.
It uses QEMU (https://www.qemu.org/) to emulate the processor that runs
the FW (currently an ARM Cortex-A9 in the provided example),
and GHDL (https://github.com/ghdl/ghdl) to simulate the HW.
The connection between emulated CPU and HW is made by an AXI-Lite bus,
that is implemented by calling UVVM (https://www.uvvm.org/) BFM methods,
and so can be easily changed according to the design needs.

Building:
To use this software, you must recompile QEMU as it needs to be patched.
GHDL does not need patches but it is easier to also recompile it.
Two scripts are provided to simplify installation:
	qemu/compile
	ghdl/compile
By default they download the required packages, apply the required patches
and configuration, compile, and install everything in /tmp/test.
Feel free to change the variables in the scripts to suit your needs.

Dependencies:
The software was tested on Ubuntu 22.04.2 LTS (Jammy Jellyfish),
it is supposed you already have developer packages and libraries installed,
including "make", and "ninja-build".
In particular, recompiling GHDL also requires "gnat", "clang", and "llvm".
Also, to run the provided "fastUART" and "DAQ" examples,
you must have the Xilinx proprietary FPGA libraries installed
(UNISIM and UNIMACRO) that come with Vivado,
have a look at ghdl/compile for configuring paths.
To compile the firmware of all the examples, the gcc-arm-none-eabi compiler
is needed, and gdb-multiarch can also be useful.

Running:

- PWM example:
Enter the examples/PWM directory and run make in both of its subdirs:
	make -C hw
	make -C fw
These will produce /tmp/test/vhdl.run and /tmp/test/code.elf respectively
(these are the default names for the VHDL and FW executables).
Then start the co-simulation using the generated helper script:
	/tmp/test/run --vcd=pwm.vcd

- UART examples:
Enter the examples/fastUART directory and run make in both of its subdirs:
	make -C hw
	make -C fw
then start the co-simulation using the generated helper script:
	/tmp/test/run --vcd=traces.vcd /tmp/test/loop.elf
for a simple loopback test, or specify the other FW image
for an interactive session:
	/tmp/test/run /tmp/test/user.elf
and open a serial terminal emulator from another shell:
	picocom /tmp/test/pty

- DAQ example:
Enter the examples/DAQ directory and run make in all of its subdirs:
	make -C hw
	make -C fw
	make -C sw
then start the co-simulation using the generated helper script:
	/tmp/test/run /tmp/test/daq.elf
start the PC-side control program to get the data from the DAQ:
	/tmp/test/read.bin /tmp/test/pty > /tmp/test/data.txt
and wait a few minutes for the co-simulation to complete.
Since the DAQ is confgured for 4 channels but only 1 is connected,
the output file will contain only one non-zero column.


Final notes:
All files are encoded in UTF-8 *except* for the VHDL sources,
which are in ISO-8859-1 as originally required by the language.

That's all!
