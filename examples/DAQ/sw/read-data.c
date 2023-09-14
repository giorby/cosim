// DAQ Cosimulation example: data parser.
/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include <termios.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <fcntl.h>
#include <sys/select.h>
#include <signal.h>
#include <poll.h>
#include <time.h>


static int serial_fd = -1;

static bool serial_open (const char *filename)
{
	serial_fd = open(filename, O_RDWR | O_NOCTTY);
	if (serial_fd == -1) {
		perror("open");
		return false;
	}

	// disable all termios processing:
	struct termios tmios;
	if (tcgetattr(serial_fd, &tmios) == -1) {
		perror("tcgetattr");
		return false;
	}
	cfmakeraw(&tmios);
	if (tcsetattr(serial_fd, TCSANOW, &tmios) == -1) {
		perror("tcsetattr");
		return false;
	}

	return true;
}

static int lines = 0;

static void process (uint32_t const *data)
{
	++lines;
	printf("%d\t%d\t%d\t%d\n", data[0], data[1], data[2], data[3]);
}

static uint8_t buffer[256];
static const size_t buflen = sizeof buffer;

static uint8_t outbuf[16];
static size_t  outlen = 0;

static bool serial_read (void)
{
	ssize_t r;
	if ((r = read(serial_fd, buffer, buflen)) <= 0) {
		fprintf(stderr, "PTY closed, exiting...\n");
		return false;
	}

	static int e = 0;
	for (int i = 0; i < r; ++i) {
		int c = buffer[i];
		if (e == 0 && c == 0xFF) {
			e = 1;
			continue;
		} else if (e == 1 && c == 0xFF) {
			e = 0;
		} else if (e == 1) {
			e = 2;
			continue;
		} else if (e == 2) {
			e = 0;
			if (!lines) continue;
			fprintf(stderr, "Break detected, exiting...\n");
			return false;
		}
		outbuf[outlen++] = c;
		if (outlen == sizeof outbuf) {
			process((uint32_t *) outbuf);
			outlen = 0;
		}
	}
	return true;
}


int main (int argc, const char *argv[])
{
	if (argc < 2) {
		fprintf(stderr, "Missing PTY file name.\n");
		return 1;
	}
	if (!serial_open(argv[1])) {
		fprintf(stderr, "Cannot open port.\n");
		return 1;
	}

	// read data from the serial port until a break is detected or the port is closed:
	while (serial_read()) ;

	return 0;
}

