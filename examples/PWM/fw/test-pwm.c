// Cosimulation PWM/timer example.
/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "platform.h"
#define BASE_ADDR 0xE0000000
#define TMR_SEQUENCE_FINISHED 1

// PWM/timer registers:
typedef struct tmr_s
{
	const uint32_t count;  // RO
	      uint32_t period; // RW - 0 disables timer
	      uint32_t value;  // RW - double buffered
} tmr_t;
static volatile tmr_t * const tmr = (void *) (BASE_ADDR + 0x0000);

unsigned count_events (uint32_t time)
{
	static uint32_t n;
	// TODO: compute running statistics of "time": mean, stddev, ...
	return ++n;
}

// 12-point "sinusoidal" waveform, amplitude = 100, offset = 125:
static const uint8_t pwm_values[] = {125, 174, 211, 224, 211, 174, 125, 76, 39, 26, 39, 76};
static const uint8_t num_values   = sizeof pwm_values / sizeof *pwm_values;

void timer_isr (void)
{
	static unsigned phase = 0;
	uint32_t time = tmr->count;
	tmr->value = pwm_values[phase++];
	if (phase >= num_values) phase = 0;
	if (count_events(time) > 26) event_set_nolock(TMR_SEQUENCE_FINISHED);
}

int main (void)
{
	tmr->period = 250 - 1;
	wait_for_event(TMR_SEQUENCE_FINISHED);
	return 0;
}
