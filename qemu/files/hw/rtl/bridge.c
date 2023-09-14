/*
 * RTL bridge to co-simulate VHDL code
 *
 * Author:
 *	Giorgio Biagetti <g.biagetti@staff.univpm.it>
 *	Department of Information Engineering
 *	Università Politecnica delle Marche (ITALY)
 *
 * Code structure inspired by remote-port.c, which is Copyright © 2013 Xilinx Inc,
 * released under the GNU GPL, and written by Edgar E. Iglesias <edgar.iglesias@xilinx.com>
 * https://github.com/Xilinx/qemu/
 *
 * This file Copyright © 2023 Giorgio Biagetti
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "qemu/osdep.h"
#include "qemu/module.h"
#include "qemu/log.h"
#include "qemu/timer.h"
#include "qemu/thread.h"
#include "sysemu/runstate.h"
#include "hw/irq.h"
#include "hw/sysbus.h"
#include "hw/qdev-properties.h"
#include "hw/qdev-properties-system.h"
#include "qom/object.h"
#include "chardev/char-fe.h"

#include "qemu/error-report.h"
#include "qemu/sockets.h"

struct RTLBridge {
	SysBusDevice        parent;
	VMChangeStateEntry *vmstate;

	CharBackend         comm;
	uint32_t            base;
	uint32_t            span;
	char               *name;
	uint32_t            sync;

	MemoryRegion        iomem;
	qemu_irq            irq;
	uint32_t            irq_level;
	char                reply[12];
	char                guard[4];
	QemuCond            reply_wait;
	QemuMutex           reply_mutex;
	QemuThread          thread;
	QEMUTimer          *timer;
	int pipes[2];
};

#define TYPE_RTL_BRIDGE "RTL-bridge"
OBJECT_DECLARE_SIMPLE_TYPE(RTLBridge, RTL_BRIDGE)

static uint64_t rtl_read (void *opaque, hwaddr addr, unsigned size)
{
	RTLBridge *rtl = opaque;
	uint32_t   reg = addr;
	uint64_t   val = 0;
	char cmd[32];

//	int64_t now1 = qemu_clock_get_ns(QEMU_CLOCK_REALTIME);

	// Send read command:
	int n = snprintf(cmd, sizeof cmd - 1, "R:%08X\r\n", reg);
	if (n < sizeof cmd - 1) {
		qemu_chr_fe_write_all(&rtl->comm, (uint8_t const *) cmd, n);
	} else {
	    return val;
	}
	// Read back reply:
	qemu_cond_wait(&rtl->reply_wait, &rtl->reply_mutex);
	if (sscanf(rtl->reply, "R=%"PRIx64"\r\n", &val) == 1) {
		// align byte lines:
		val >>= (reg & 3) * 8;
		// and also check if IRQ level has changed because of read operation:
		qemu_set_irq(rtl->irq, rtl->irq_level);
	} else {
		qemu_log_mask(LOG_GUEST_ERROR, "Wrong reply!\n");
	}

//	int64_t now2 = qemu_clock_get_ns(QEMU_CLOCK_REALTIME);
//	printf("Read took %ld ns\n", now2 - now1);

	return val;
}

static void rtl_write (void *opaque, hwaddr addr, uint64_t val, unsigned size)
{
	RTLBridge *rtl = opaque;
	uint32_t   reg = addr;
	char cmd[32];
	int n;

//	int64_t now1 = qemu_clock_get_ns(QEMU_CLOCK_REALTIME);

    if (reg == rtl->span - 0x10) { // TODO: use a different iospace?
		if (!val) {
			// stop VHDL side:
			n = snprintf(cmd, sizeof cmd - 1, "X:STOP    \r\n");
			qemu_chr_fe_write_all(&rtl->comm, (uint8_t const *) cmd, n);
			// stop QEMU side:
			qemu_system_shutdown_request(SHUTDOWN_CAUSE_GUEST_SHUTDOWN);
			return;
		} else {
			// advance RTL simulation by some time:
			n = snprintf(cmd, sizeof cmd - 1, "T:%08X\r\n", (uint32_t) val);
		}
	} else {
		// Properly align byte lanes:
		uint32_t data = val << (reg & 3) * 8;
		uint8_t  mask = ((1 << size) - 1) << (reg & 3);
		// Send write command:
		n = snprintf(cmd, sizeof cmd - 1, "W:%08X<=%08X|%01X\r\n", reg, data, mask);
	}
	if (n < sizeof cmd - 1) {
		qemu_chr_fe_write_all(&rtl->comm, (uint8_t const *) cmd, n);
	} else {
		return;
	}
	// Read back reply:
	qemu_cond_wait(&rtl->reply_wait, &rtl->reply_mutex);
	if (strncmp(rtl->reply, "W=OK      \r\n", 12) == 0 || strncmp(rtl->reply, "T=", 2) == 0) {
		// all good, but check if IRQ level has changed because of write:
		qemu_set_irq(rtl->irq, rtl->irq_level);
	} else {
		qemu_log_mask(LOG_GUEST_ERROR, "Wrong reply!\n");
	}

//	int64_t now2 = qemu_clock_get_ns(QEMU_CLOCK_REALTIME);
//	printf("Write took %ld ns\n", now2 - now1);
}

static void rtl_reset (DeviceState *d)
{
	RTLBridge *rtl = RTL_BRIDGE(d);
	rtl->irq_level = 0;
	qemu_set_irq(rtl->irq, rtl->irq_level);
	qemu_chr_fe_write_all(&rtl->comm, (uint8_t const *) "X:RESET   \r\n", 12);
	// wait for reply:
	do
		qemu_cond_wait(&rtl->reply_wait, &rtl->reply_mutex);
	while (strncmp(rtl->reply, "X=RUNNING \r\n", 12) != 0);
	int64_t now = qemu_clock_get_us(QEMU_CLOCK_VIRTUAL);
	timer_mod(rtl->timer, now + rtl->sync);
}

static void rtl_incoming_notification (void *opaque)
{
	RTLBridge *rtl = opaque;
	ssize_t r;
	do {
		r = read(rtl->pipes[0], &rtl->irq_level, sizeof rtl->irq_level);
		if (r == 0) return;
	} while (r < 0 && errno == EINTR);

	qemu_set_irq(rtl->irq, rtl->irq_level);
}

static void *rtl_thread (void *opaque)
{
	RTLBridge *rtl = opaque;

	uint8_t buf[12];
	qemu_chr_fe_accept_input(&rtl->comm);
	while (true) {
		ssize_t r = qemu_chr_fe_read_all(&rtl->comm, buf, sizeof buf);
		if (r == sizeof rtl->reply) {
			// Full reply packet received, process it:
			memcpy(rtl->reply, buf, 12);
			if (rtl->reply[0] == 'I') {
				if (1 == sscanf(rtl->reply, "I=%X", &rtl->irq_level)) {
					int n = qemu_write_full(rtl->pipes[1], &rtl->irq_level, sizeof rtl->irq_level);
					if (n != sizeof rtl->irq_level) break;
				}
			} else {
				qemu_mutex_lock(&rtl->reply_mutex);
				qemu_cond_signal(&rtl->reply_wait);
				qemu_mutex_unlock(&rtl->reply_mutex);
			}
			// TODO: proper queue.
		} else {
			break;
		}
	}
	return NULL;
}

static void rtl_timer_cb (void *opaque)
{
	RTLBridge *rtl = opaque;
	int64_t now = qemu_clock_get_us(QEMU_CLOCK_VIRTUAL);
	timer_mod(rtl->timer, now + rtl->sync);

	char cmd[32];
	int n = snprintf(cmd, sizeof cmd - 1, "T:%08X\r\n", (uint32_t) 1);
	qemu_chr_fe_write_all(&rtl->comm, (uint8_t const *) cmd, n);
	qemu_cond_wait(&rtl->reply_wait, &rtl->reply_mutex);
//	uint32_t t;
//	if (1 == sscanf(rtl->reply, "T=%X", &t)) {
//		printf("SYNC: QEMU=%ld VHDL=%u\n", now, t);
//	}
}

static const MemoryRegionOps rtl_ops = {
	.read  = rtl_read,
	.write = rtl_write,
	.endianness = DEVICE_NATIVE_ENDIAN,
};

static void rtl_realize (DeviceState *dev, Error **errp)
{
	SysBusDevice *bus = SYS_BUS_DEVICE(dev);
	RTLBridge    *rtl = RTL_BRIDGE(dev);
	Object       *cpu = object_resolve_path_type("", "arm-cpu", NULL);

	qemu_mutex_init(&rtl->reply_mutex);
	qemu_cond_init(&rtl->reply_wait);
	*(uint32_t *) &rtl->guard = 0;

	qemu_thread_create(&rtl->thread, "RTL-bridge", rtl_thread, rtl, QEMU_THREAD_JOINABLE);

	if (!g_unix_open_pipe(rtl->pipes, FD_CLOEXEC, NULL)) {
		error_report("Unable to create RTL-bridge pipes\n");
		exit(EXIT_FAILURE);
	}
	qemu_socket_set_nonblock(rtl->pipes[0]);
	qemu_set_fd_handler(rtl->pipes[0], rtl_incoming_notification, NULL, rtl);

	memory_region_init_io(&rtl->iomem, OBJECT(rtl), &rtl_ops, rtl, "RTL-bridge", rtl->span);
	sysbus_init_mmio(bus, &rtl->iomem);
	sysbus_init_irq(bus, &rtl->irq);
	sysbus_mmio_map(bus, 0, rtl->base);
	sysbus_connect_irq(bus, 0, qdev_get_gpio_in(DEVICE(cpu), 0 /*ARM_CPU_IRQ*/));

	rtl->timer = timer_new_us(QEMU_CLOCK_VIRTUAL, rtl_timer_cb, rtl);
}

static void rtl_unrealize (DeviceState *dev)
{
	RTLBridge *rtl = RTL_BRIDGE(dev);
	qemu_chr_fe_disconnect(&rtl->comm);
	qemu_thread_join(&rtl->thread);
}


static void rtl_bridge_vm_state_change (void *opaque, bool running, RunState state)
{
	RTLBridge *rtl = opaque;
	(void) rtl; // unused;
//	printf("STATE: %d (%d)\n", state, running);
}

static void rtl_bridge_inst_init (Object *obj)
{
	RTLBridge *rtl = RTL_BRIDGE(obj);
	rtl->vmstate = qemu_add_vm_change_state_handler(rtl_bridge_vm_state_change, rtl);
}

static void rtl_bridge_inst_finalize (Object *obj)
{
	RTLBridge *rtl = RTL_BRIDGE(obj);
	qemu_del_vm_change_state_handler(rtl->vmstate);
}

static Property rtl_bridge_properties[] = {
	DEFINE_PROP_CHR("chardev", RTLBridge, comm),              // pipe or socket to use to communicate with the VHDL simulator
	DEFINE_PROP_UINT32("base", RTLBridge, base, 0xE0000000),  // base address of emulated I/O space
	DEFINE_PROP_UINT32("span", RTLBridge, span, 0x01000000),  // span of emulated I/O space: last 16 bytes are reserved for simulation control
	DEFINE_PROP_UINT32("sync", RTLBridge, sync, 1000),        // advance VHDL time by 1 µs every "sync" µs of virtual CPU time
	DEFINE_PROP_STRING("name", RTLBridge, name),
	DEFINE_PROP_END_OF_LIST(),
};

static void rtl_bridge_class_init (ObjectClass *klass, void *data)
{
	DeviceClass *dc = DEVICE_CLASS(klass);

	dc->desc      = "RTL Bridge for VHDL co-simulation";
	dc->reset     = rtl_reset;
	dc->realize   = rtl_realize;
	dc->unrealize = rtl_unrealize;
	dc->hotpluggable = true;
	dc->user_creatable = true;
	device_class_set_props(dc, rtl_bridge_properties);
}

static const TypeInfo rtl_bridge_info = {
	.name              = TYPE_RTL_BRIDGE,
	.parent            = TYPE_SYS_BUS_DEVICE,
	.instance_size     = sizeof (RTLBridge),
	.instance_init     = rtl_bridge_inst_init,
	.instance_finalize = rtl_bridge_inst_finalize,
	.class_init        = rtl_bridge_class_init,
};

static void rtl_bridge_register_info (void)
{
	type_register_static(&rtl_bridge_info);
}

type_init(rtl_bridge_register_info)

