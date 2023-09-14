// platform.h
// Useful but platform-dependent functions to handle low-level CPU chores.
//
// This file is for ARMv7-A

#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>
#include <stdbool.h>

static volatile uint32_t * const simulator_stop = (void *) (0xE0000000 + 0x00FFFFF0);

__inline static void enable_interrupts (void)
{
	__asm("cpsie if");
}

__inline static void disable_interrupts (void)
{
	__asm("cpsid if");
}

extern void wait_for_event (uint32_t mask); // Just one event  - autoclears it!
extern void wait_for_events(uint32_t mask); // Multiple events - user must call event_clear afterwards.

extern void event_set      (uint32_t mask);
extern bool event_test     (uint32_t mask);
extern void event_clear    (uint32_t mask);

// only call these when IRQs are already disabled:
extern void event_set_nolock   (uint32_t mask);
extern void event_clear_nolock (uint32_t mask);

#endif
