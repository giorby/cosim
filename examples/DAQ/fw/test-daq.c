// DAQ Cosimulation example.
/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "build_date.h"
#include "platform.h"
#define BASE_ADDR 0xE0000000

// UART registers:
#include "fastuart.h"

// PWM/timer registers:
typedef struct tmr_s
{
	const uint32_t count;  // RO
	      uint32_t period; // RW - 0 disables timer
	      uint32_t value;  // RW - double buffered
} tmr_t;

// INTC registers:
typedef struct int_s
{
	const uint32_t status; // RO
	const uint32_t masked; // RO
	      uint32_t enable; // RW
} int_t;

enum int_mask {
	irq_uart = 1,
	irq_tmr1 = 2,
	irq_tmr2 = 4,
	irq_daqc = 8,
};

// DAQ registers:
typedef union daq_u
{
	struct {
		uint8_t reg;
	};
	struct {
		uint8_t bank_ready : 2; // RO
		uint8_t            : 2;
		uint8_t irq_flag   : 1; // W1C
		uint8_t irq_enable : 1; // RW
		uint8_t continuous : 1; // RW
		uint8_t enable     : 1; // RW AUTO0
	};
} daq_t;

static volatile    tmr_t * const tmr1 = (void *) (BASE_ADDR +  0x1000);
static volatile    tmr_t * const tmr2 = (void *) (BASE_ADDR +  0x2000);
static volatile    daq_t * const daqc = (void *) (BASE_ADDR +  0x3000);
static volatile    int_t * const intc = (void *) (BASE_ADDR +  0x4000);
static volatile uint32_t * const mem  = (void *) (BASE_ADDR + 0x10000); // 64 KiB shared memory

enum misc_events {
	// 1 & 2 already used by UART.
	pwm_sequence_done = 4,
	daq_capture_done  = 8,
};


// 120-point "sinusoidal" waveform, amplitude = 100, offset = 125:
static const uint8_t pwm_values[] = {
	125, 130, 135, 141, 146, 151, 156, 161, 166, 170, 175, 179, 184, 188, 192,
	196, 199, 203, 206, 209, 212, 214, 216, 218, 220, 222, 223, 224, 224, 225,
	225, 225, 224, 224, 223, 222, 220, 218, 216, 214, 212, 209, 206, 203, 199,
	196, 192, 188, 184, 179, 175, 170, 166, 161, 156, 151, 146, 141, 135, 130,
	125, 120, 115, 109, 104,  99,  94,  89,  84,  80,  75,  71,  66,  62,  58,
	 54,  51,  47,  44,  41,  38,  36,  34,  32,  30,  28,  27,  26,  26,  25,
	 25,  25,  26,  26,  27,  28,  30,  32,  34,  36,  38,  41,  44,  47,  51,
	 54,  58,  62,  66,  71,  75,  80,  84,  89,  94,  99, 104, 109, 115, 120,
};

static const uint8_t num_values = sizeof pwm_values / sizeof *pwm_values;

void tmr1_isr (void)
{
	(void) tmr1->count; // ACK IRQ
}

void tmr2_isr (void)
{
	static unsigned phase = 0, count = 0;
	(void) tmr2->count; // ACK IRQ
	tmr2->value = pwm_values[phase++] + (++count > 960 ? 125 : 0);
	if (count == 962) tmr2->period = 500 - 1;
	if (phase >= num_values) {
		event_set_nolock(pwm_sequence_done);
		phase = 0;
	}
}

void daqc_isr (void)
{
	daq_t status = *daqc;
	*daqc = status; // ACK IRQ
	event_set_nolock(daq_capture_done);
}

void generic_isr (void)
{
	uint32_t irqs = intc->masked;
	if (irqs & irq_uart) uart_isr();
	if (irqs & irq_tmr1) tmr1_isr();
	if (irqs & irq_tmr2) tmr2_isr();
	if (irqs & irq_daqc) daqc_isr();
}

void wait_for_pty_connection (void)
{
	bool connected = false;
	while (!connected) {
		uart_recv(true);
		wait_for_event(uart_rx_ready);
		for (uint16_t value; (value = uart_data->read) != uart_fifo_empty; )
			if (value == uart_recv_idle) connected = true;
	}
}

int main (void)
{
	uart_control->tx_fifo.enable = 1;
	uart_control->rx_fifo.enable = 1;
	intc->enable = irq_uart | irq_tmr2 | irq_daqc;
	tmr1->period = 1000 - 1; // 100 kHz -- DAQ sampling rate
	tmr1->value  =  500;     // 50% duty cycle
	tmr2->period =  250 - 1; // 400 kHz -- PWM frequency
	daqc->reg    = 0xB0;     // single buffer capture
	wait_for_event(daq_capture_done);
	wait_for_pty_connection();
	uart_post((void *) mem, 64 << 10);
	wait_for_event(uart_tx_done);
	return 0;
}
