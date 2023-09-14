/*
 * Minimal ARM board to include RTL bridge to co-simulate VHDL code
 *
 * Author:
 *	Giorgio Biagetti <g.biagetti@staff.univpm.it>
 *	Department of Information Engineering
 *	Università Politecnica delle Marche (ITALY)
 *
 * Copyright © 2023 Giorgio Biagetti
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "qemu/osdep.h"
#include "qemu/units.h"
#include "qapi/error.h"
#include "cpu.h"
#include "hw/sysbus.h"
#include "net/net.h"
#include "sysemu/sysemu.h"
#include "hw/boards.h"
#include "hw/loader.h"
#include "qemu/error-report.h"
#include "hw/cpu/a9mpcore.h"
#include "hw/qdev-clock.h"
#include "sysemu/reset.h"
#include "qom/object.h"

#define TYPE_FPGA_MACHINE MACHINE_TYPE_NAME("fpga")
OBJECT_DECLARE_SIMPLE_TYPE(FpgaMachineState, FPGA_MACHINE)


struct FpgaMachineState
{
	MachineState parent;
	Clock *clk;
};


static void fpga_init (MachineState *machine)
{
	FpgaMachineState *fpga_machine = FPGA_MACHINE(machine);
	MemoryRegion *mem = get_system_memory();
	MemoryRegion *ext = g_new(MemoryRegion, 1);

	if (machine->ram_size > 256 * MiB) {
		error_report("More than 256 MiB of RAM clashes with external memory");
		exit(EXIT_FAILURE);
	}

	ARMCPU *cpu = ARM_CPU(object_new(machine->cpu_type));
	qdev_realize(DEVICE(cpu), NULL, &error_fatal);

	// internal (BRAM) memory mapped at address 00000000:
	memory_region_add_subregion(mem, 0x00000000, machine->ram);

	// external (SRAM) memory mapped at address 10000000:
	memory_region_init_ram(ext, NULL, "fpga.ext_ram", 256 * KiB, &error_fatal);
	memory_region_add_subregion(mem, 0x10000000, ext);

	fpga_machine->clk = CLOCK(object_new(TYPE_CLOCK));
	object_property_add_child(OBJECT(fpga_machine), "ps_clk", OBJECT(fpga_machine->clk));
	object_unref(OBJECT(fpga_machine->clk));
	clock_set_hz(fpga_machine->clk, 120000000);
}

static void fpga_machine_class_init (ObjectClass *oc, void *data)
{
	MachineClass *mc = MACHINE_CLASS(oc);
	mc->desc = "FPGA-VHDL emulator link";
	mc->init = fpga_init;
	mc->max_cpus = 1;
	mc->ignore_memory_transaction_failures = true;
	mc->default_cpu_type = ARM_CPU_TYPE_NAME("cortex-a9");
	mc->default_ram_id = "fpga.int_ram";
	machine_class_allow_dynamic_sysbus_dev(mc, "RTL-bridge");
}

static const TypeInfo fpga_machine_type = {
	.name = TYPE_FPGA_MACHINE,
	.parent = TYPE_MACHINE,
	.class_init = fpga_machine_class_init,
	.instance_size = sizeof (FpgaMachineState),
};

static void fpga_machine_register_types (void)
{
	type_register_static(&fpga_machine_type);
}

type_init(fpga_machine_register_types)
