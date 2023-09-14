/* Fast UART Interface Registers */
/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INC_FASTUART_H
#define INC_FASTUART_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/**************************************
 ** Serial Port Communication        **
 **************************************/

typedef union ser_data_u
{
	struct {
		uint32_t word;
	};
	struct {
		uint16_t half;
		uint16_t test;             // RESERVED
	};
	struct {
		uint8_t  byte;
		uint8_t  flag;             // RO
		uint8_t               : 8;
		uint8_t               : 8;
	};
	struct {
		uint8_t  bytes[4];         // RESERVED
	};
	enum __attribute__((__packed__)) uart_recv_flags {
		         uart_fifo_empty = 0x119, // EM  : FIFO underrun
		         uart_recv_error = 0x115, // NAK : framing error
		         uart_recv_noise = 0x11A, // SUB : noise in symbol
		         uart_recv_break = 0x104, // EOT : break detected
		         uart_recv_idle  = 0x100, // NUL : idle line detected
	}	         read;
} ser_data_t;

typedef union ser_control_u
{
	struct {
		uint32_t reg;
	};
	struct {
		uint8_t  reg_tx;
		uint8_t  reg_rx;
		uint8_t  reg_hw;
		uint8_t  reg_irq;
	};
	struct {
		enum __attribute__((__packed__)) fifo_control_actions {
		         fifo_reset = 0x01,
		         push_sync  = 0x84, // RX only
		         send_break = 0x90, // TX only
		         send_idle  = 0xB0, // TX only
		         send_error = 0xF0, // TX only
		}
		         tx,
		         rx;
	};
	struct {
	struct fifo_control_s {
		uint8_t  empty        : 1; // W1S       [4]
		uint8_t  half         : 1; // RO        [3]
		uint8_t  full         : 1; // RO
		uint8_t  over         : 1; // W1C
		uint8_t  pause        : 1; // WO/RO     [2]
		uint8_t  line         : 1; // RW/RO     [1]
		uint8_t  active       : 1; // RO
		uint8_t  enable       : 1; // RW
	}
		         tx_fifo,
		         rx_fifo;
	/* Notes:
	 *	[1]: in "tx_fifo", sets the level driven on the TX pin when "enable" is 0;
	 *	     in "rx_fifo", "line" is set as soon as the line goes up after a break, is reset after a long break,
	 *	[2]: in "tx_fifo" writing a 1 enqueues a break if "line" is 0, an idle character if "line" is 1;
	 *	     in "rx_fifo" signals the presence of a special event (idle, break, framing error) in the FIFO.
	 *	[3]: in RX means >= 50% occupancy,
	 *	     in TX means <= 50% occupancy.
	 *	[4]: writing 1 clears the FIFO.
	 */
	struct /* flow_control_s */ {
		uint8_t  cts          : 1; // RO
		uint8_t  rts          : 1; // RW
		uint8_t               : 2;
		uint8_t  enable_cts   : 1; // RW
		uint8_t  enable_rts   : 1; // RW        [1]
		uint8_t               : 1;
		uint8_t  loopback     : 1; // RW
	};
	/* Notes:
	 *	[1]: if set, then "rts" becomes read-only.
	 */
	struct /* irq_control_s */ {
		uint8_t  rx_not_empty : 1; // RW
		uint8_t  rx_half      : 1; // RW
		uint8_t  tx_empty     : 1; // RW
		uint8_t  tx_half      : 1; // RW
		uint8_t  rx_pause     : 1; // RW
		uint8_t  rx_line      : 1; // RW (?)
		uint8_t  rx_active    : 1; // RW
		uint8_t  hw_cts       : 1; // RW
	}            irq;
	};
} ser_control_t;
enum {
	uart_fifo_size  = 2048,
	uart_fifo_half  = uart_fifo_size / 2,
};


/**************************************
 ** Register Memory Map              **
 **************************************/

static volatile ser_data_t    * const uart_data    = (void *) (BASE_ADDR + 0x0000);
static volatile ser_control_t * const uart_control = (void *) (BASE_ADDR + 0x0004);

// UART driver:
enum uart_events {
	uart_tx_done  = 1,
	uart_rx_ready = 2,
};

extern const void *uart_send (const void *data, size_t len);
extern int         uart_post (const void *data, size_t len);
extern void        uart_recv (bool enable);
extern void        uart_isr  (void);

#endif
