/* platform.c: Useful but platform-dependent functions to handle low-level CPU chores. */
/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


// This file is for ARMv7-A
#include "platform.h"

static volatile uint32_t events;

void wait_for_events (uint32_t mask)
{
	while (1) {
		disable_interrupts();
		if (events & mask) {
			enable_interrupts();
			return;
		} else {
			__asm("wfi");
			enable_interrupts();
		}
	}
}

void wait_for_event (uint32_t mask)
{
	while (1) {
		disable_interrupts();
		if (events & mask) {
			events &= ~mask;
			enable_interrupts();
			return;
		} else {
			__asm("wfi");
			enable_interrupts();
		}
	}
}

void event_set_nolock (uint32_t mask)
{
	events |= mask;
}

void event_clear_nolock (uint32_t mask)
{
	events &= ~mask;
}

void event_set (uint32_t mask)
{
	disable_interrupts();
	events |= mask;
	enable_interrupts();
}

bool event_test (uint32_t mask)
{
	return !!(events & mask);
}

void event_clear (uint32_t mask)
{
	disable_interrupts();
	events &= ~mask;
	enable_interrupts();
}


void __attribute__ ((interrupt, used)) irq_handler (void);

void __attribute__ ((section(".vectors"), naked, used)) vector_irq (void)
{
	__asm("b _start");
	__asm("b .");
	__asm("b .");
	__asm("b .");
	__asm("b .");
	__asm("b .");
	__asm("b irq_handler");
	__asm("b .");
}

void __attribute__ ((interrupt, used)) irq_handler (void)
{
	extern void uart_isr (void);
	uart_isr();
}

void exit (int code)
{
	*simulator_stop = 0;
	void _exit(int status);
	_exit(code);
}
