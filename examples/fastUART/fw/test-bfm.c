// Cosimulation Fast UART example.
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
#include "fastuart.h"


static volatile char    rxbuf[256];
static volatile uint8_t rxcnt;

void loopback_test (void)
{
	// enqueue some test signals on the TX FIFO:
	uart_data->word = 0x78563412;  // basic 32-bit access
	uart_data->half = 0xCDAB;      // basic 16-bit access
	uart_data->byte = 0xEF;        // basic  8-bit access
	uart_data->test = 0x9291;      // high-half 16-bit access (no need to use, just a test)
	uart_data->bytes[0] = 0xB0;    // individual byte lane access (unneeded... just a test)
	uart_data->bytes[1] = 0xB1;    // individual byte lane access (unneeded... just a test)
	uart_data->bytes[2] = 0xB2;    // individual byte lane access (unneeded... just a test)
	uart_data->bytes[3] = 0xB3;    // individual byte lane access (unneeded... just a test)
	uart_control->tx = send_error; // special symbol: writes 0xF0, queues 0x1FE.
	uart_control->tx = send_break; // special symbol: writes 0x90, queues 0x1C0.
	uart_control->tx = send_idle;  // special symbol: writes 0xB0, queues 0x1C1.

	uart_control->loopback       = 1;
	uart_control->irq.tx_empty   = 1;
	uart_control->rx_fifo.enable = 1;
	wait_for_event(uart_tx_done);

	// read back the characters received so far:
	for (uint16_t value; (value = uart_data->read) != uart_fifo_empty; )
		rxbuf[rxcnt++] = value; // also stores control characters!

	// now start interrupt-based transmission test:
	uart_recv(true);        // enables rx_half and rx_pause interrupts
	uart_post("Hi\r\n", 4); // enables tx_half interrupt, actual loading of FIFO is in ISR
	wait_for_event(uart_rx_ready);

	// and read the remaining received characters:
	for (uint16_t value; (value = uart_data->read) != uart_fifo_empty; )
		if (value < 0x100) rxbuf[rxcnt++] = value;
}


int main (void)
{
	loopback_test();
	return 0;
}
