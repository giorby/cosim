This is an AXI Lite mux coded in VHDL, forked from https://gitlab.com/hdl_modules/hdl_modules on Sept. 6, 2023.
An AXI mux is a simplified crossbar for the common 1:N case of a single manager and N subordinates.

Original code written by Lukas Vik: https://www.truestream.se/products/ 
On-line documentation at:           https://hdl-modules.com/
Licensed under the license:         BSD-3-Clause

This is a stripped-down version with the bare minimum to compile the AXI mux.
Minor modifications made by Giorgio Biagetti to simplify usage with the CPUemu co-simulation package:
 - limit data and address size to 32 bit.
 - library reorganization (put the mux-related code into its own "axi" VHDL library).

