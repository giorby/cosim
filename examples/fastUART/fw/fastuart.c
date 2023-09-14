/* Fast UART Driver */
/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#define BASE_ADDR 0xE0000000
#include "fastuart.h"
#include "platform.h"
#include <errno.h>

static void const *uart_background_send_ptr;
static size_t      uart_background_send_len;

void uart_isr (void)
{
	// Read UART status register to determine IRQ cause:
	ser_control_t c = *uart_control;

	// Handle TX interrupts:
	if (c.tx_fifo.empty && c.irq.tx_empty) {
		c.irq.tx_empty = 0;
		event_set_nolock(uart_tx_done);
	}
	if (c.tx_fifo.half && c.irq.tx_half) {
		size_t len = uart_fifo_half;
		if (len > uart_background_send_len)
			len = uart_background_send_len;
		uart_background_send_ptr = uart_send(uart_background_send_ptr, len);
		uart_background_send_len -= len;
		if (!uart_background_send_len) {
			uart_control->tx = send_idle;
			c.irq.tx_empty = !!len;
			c.irq.tx_half  = 0;
		}
	}

	// Handle RX interrupts:
	if (
		(!c.rx_fifo.empty && c.irq.rx_not_empty) ||
		( c.rx_fifo.half  && c.irq.rx_half     ) ||
		( c.rx_fifo.pause && c.irq.rx_pause    )
	) {
		event_set_nolock(uart_rx_ready);
		c.irq.rx_not_empty = 0;
		c.irq.rx_half      = 0;
		c.irq.rx_pause     = 0;
	}

	uart_control->irq = c.irq;
}

const void *uart_send (const void *data, size_t len)
{
	size_t words = len / 4;
	size_t bytes = len % 4;

	const uint32_t *p = data;
	while (words--) uart_data->word = *p++;
	data = p;

	const uint8_t  *c = data;
	while (bytes--) uart_data->byte = *c++;
	data = p;

	return data;
}

int uart_post (const void *data, size_t len)
{
	if (uart_background_send_len) return -EBUSY;
	uart_background_send_ptr  = data;
	uart_background_send_len  = len;
	disable_interrupts();
	uart_control->irq.tx_half = 1;
	enable_interrupts();
	return 0;
}

void uart_recv (bool enable)
{
	disable_interrupts();
	ser_control_t c = *uart_control;
	c.irq.rx_not_empty = 0; // this is not enabled by default as it is only needed for a FIFO-bypass usage style, which is not what this driver does.
	c.irq.rx_half  = enable;
	c.irq.rx_pause = enable;
	uart_control->irq = c.irq;
	enable_interrupts();
}
