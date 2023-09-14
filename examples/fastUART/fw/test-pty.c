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

#include <string.h>

static char    rxbuf[256];
static uint8_t rxcnt;

#define TTY_TITLE   "FastUART FPGA Demo Interface"
#define TTY_WELCOME "  Welcome to the " TTY_TITLE

static const char welcome_msg[] =
//	"\e[H\e[J\e[3J"                // clear screen (and backscrolling)
	"\e]0;"    TTY_TITLE   "\e\\"  // set terminal window title
	"\e[93m"                       // set welcome text color
		"\e#3" TTY_WELCOME "\r\n"
		"\e#4" TTY_WELCOME "\r\n"
	"\e[m\r\n";

static const char version_msg[] =
	"Firmware version: ";

static const char help_msg[] =
	"This is the help message\r\n"
	"that should be written to guide the user\r\n"
	"on what the available commands are.\r\n";

static const char exit_msg[] =
	"Bye!\r\n";

static const char prompt[] = "\e[32m>\e[97m ";


static const uint32_t BACK = 0x4B5B1B08; // ␈␛[K
static const uint32_t ESC0 = 0x6D305B1B; // ␛[0m
static const uint16_t CRLF = 0x0A0D;     // ␍␊


void show_version (void)
{
	uart_send(version_msg, sizeof version_msg - 1);
	uart_send(build_timestamp_str, build_timestamp_len);
	uart_data->half = CRLF;
}

void show_enquiry (void)
{
	// Send ID: TTY_TITLE
	uart_data->byte = 0x01;   // ␁
	uart_data->half = *(uint16_t const *) "ID";
	uart_data->half = 0x0209; // ␉␂
	uart_send(TTY_TITLE, __builtin_strlen(TTY_TITLE));
	uart_data->half = CRLF;
	// Send FW: build_timestamp
	uart_data->byte = 0x01;   // ␁
	uart_data->half = *(uint16_t const *) "FW";
	uart_data->half = 0x0209; // ␉␂
	uart_send(build_timestamp_str, build_timestamp_len);
	uart_data->half = CRLF;
	// That's all!
	uart_data->byte = 0x03;   // ␃
}

void show_control (uint8_t c)
{
	char fmt[] = "\e[96m␀\e[m\r\n";
	size_t len = 13;
	fmt[7] += c;
	uart_send(fmt, len);
}

void show_prompt (void)
{
	uart_send(prompt, sizeof prompt - 1);
	if (rxcnt) uart_post(rxbuf, rxcnt);
}

void show_welcome_msg (void)
{
	uart_post(welcome_msg, sizeof welcome_msg - 1);
	wait_for_event(uart_tx_done);
	show_version();
	uart_post(prompt, sizeof prompt - 1);
	wait_for_event(uart_tx_done);
}

void process_input (void)
{
	if (rxcnt == 4 && strncmp(rxbuf, "help", rxcnt) == 0) {
		uart_post(help_msg, sizeof help_msg - 1);
		wait_for_event(uart_tx_done);
	}
	rxcnt = 0;
	uart_post(prompt, sizeof prompt - 1);
	wait_for_event(uart_tx_done);
}

int main (void)
{
	uart_control->rx_fifo.enable = 1;
	uart_control->tx_fifo.enable = 1;

	int escape = 0;
	bool connected = false;
	while (true) {
		uart_recv(true);
		wait_for_event(uart_rx_ready);
		for (uint16_t value; (value = uart_data->read) != uart_fifo_empty; ) {
			if (value == uart_recv_break) connected = false;
			if (value == uart_recv_idle && !connected) {
				show_welcome_msg();
				connected = true;
			}
			if (value < 0x100) {
				if (escape) {
					if (value == 24) escape = 0; // CAN
					switch (escape) {
						case 1:
							switch (value) {
								case '[': escape = 2; break;
								case '#': escape = 3; break;
								case ']': escape = 4; break;
								default : escape = 0;
							} break;
						case 2:
							// ignore all escape sequences for now.
							if (value > 0x40) escape = 0;
							break;
						case 3:
							switch (value) {
								case '+': break; // TODO: ECHO ON
								case '-': break; // TODO: ECHO OFF
							}
							escape = 0;
							break;
						case 4:
							if (value == '\e') escape = 5;
							break;
						case 5:
							if (value == '\\') escape = 0; else escape = 4;
							break;
					}
					continue;
				}
				if (value == 0) { // ␀
					// do nothing
				} else if (value == 3) { // ␃
					rxcnt = 0;
					show_control(value);
					show_prompt();
				} else if (value == 4) { // ␄
					show_control(value);
					uart_data->word = ESC0;
					uart_data->half = CRLF;
					uart_post(exit_msg, sizeof exit_msg - 1);
					wait_for_event(uart_tx_done);
					return 0;
				} else if (value == 5) { // ␅
					show_control(value);
					show_enquiry();
					show_prompt();
				} else if (value == 7) { // ␇
					// blink LED.
				} else if (value == 8   || // ␈
				           value == 127) { // ␡
					if (rxcnt) {
						while (rxcnt) {
							// handle UTF-8 codepoints... sort of...
							uint8_t v = rxbuf[--rxcnt];
							if ((v & 0xC0) != 0x80) break;
						}
						uart_data->word = BACK;
					}
				} else if (value == 13) {
					uart_data->word = ESC0;
					uart_data->half = CRLF;
					process_input();
				} else if (value == 27) {
					escape = 1;
				} else if (value >= 0x20) {
					rxbuf[rxcnt++] = value;
					uart_data->byte = value;
				}
			}
		}
	}
	return 0;
}

