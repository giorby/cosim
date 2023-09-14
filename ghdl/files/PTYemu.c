/*
 * GHDL VHPIDIRECT interface to connect to a Linux pseudoterminal port
 * (developed for and tested with GHDL v3.0)
 *
 * Author:
 *      Giorgio Biagetti <g.biagetti@staff.univpm.it>
 *      Department of Information Engineering
 *      Università Politecnica delle Marche (ITALY)
 *
 * Copyright © 2023 Giorgio Biagetti
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#define _XOPEN_SOURCE 700
#define _DEFAULT_SOURCE
#define _GNU_SOURCE
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

#define VERBOSE false

static struct pollfd ptm = {.fd = -1, .events = POLLIN};
static const char *ln;

static void pty_stop (void)
{
	if (ln) unlink(ln);
}

static void pty_init (void)
{
	// this function can only be called once:
	if (ptm.fd > 0) return;

	// try to open a posix pseudoterminal:
	ptm.fd = posix_openpt(O_RDWR | O_NOCTTY);
	if (ptm.fd == -1) {
		perror("openpt");
		exit(1);
	}
	// get its name:
	char *name = ptsname(ptm.fd);
	if (!name) {
		perror("ptsname");
		exit(1);
	}
	// and link it to a predictable name:
	if (ln) unlink(ln); // remove symlink if already present.
	if (ln && symlink(name, ln) == -1) {
		perror("symlink");
		exit(1);
	}
	atexit(pty_stop);

	// disable echo:
	struct termios tmios;
	if (tcgetattr(ptm.fd, &tmios) == -1) {
		perror("tcgetattr");
		exit(1);
	}
	cfmakeraw(&tmios);
	if (tcsetattr(ptm.fd, TCSANOW, &tmios) == -1) {
		perror("tcsetattr");
		exit(1);
	}

	// finally enable the pty:
	if (grantpt(ptm.fd) == -1) {
		perror("grantpt");
		exit(1);
	}
	if (unlockpt(ptm.fd) == -1) {
		perror("unlockpt");
		exit(1);
	}
	// pre-set the HUP flag:
	close(open(name, O_RDWR | O_NOCTTY));
}


// data types used to interface with GHDL arrays:

typedef struct {
	int32_t  left;
	int32_t  right;
	int32_t  dir;
	int32_t  len;
} range_t;

typedef struct {
	void    *data;
	range_t *bounds;
} array_t;


// GHLD VHPIDIRECT interface:

void pty_start (const array_t *name)
{
	// this function can only be called once:
	if (ln) return;

	// get PTY link name from VHDL side:
	int32_t len = name->bounds->len;
	char *str = malloc(len + 1);
	if (!str) exit(1);
	memcpy(str, name->data, len);
	str[len] = '\0';
	// store it for future reference:
	ln = str;
	// and open the PTY:
	pty_init();
	printf("PTYemu pseudo-terminal initialized: %s\n", ln);
}

void pty_write (int data)
{
	if (data < 0) return;
	ssize_t w = 0, n = 1;
	if (VERBOSE) printf("PTY write: %03X ", data);
	if (ptm.fd < 0) {
		if (VERBOSE) printf("[ NO PTY! ]\n");
		return;
	}
	if (data & 1) {
		if (VERBOSE) printf("[ NOISE ]\n");
		return;
	} else {
		data >>= 1;
		if (data < 0x100) {
			uint8_t escape[3] = {0xFF, 0x00, data ? 0x15 : 0x00};
			if (VERBOSE) printf("(%s)\n", escape[2] ? "NAK" : "NUL");
			w = write(ptm.fd, escape, n = 3);
		} else {
			data &= 0xFF;
			uint8_t buffer[2] = {data, data};
			if (VERBOSE) printf("(%02X)\n", data);
			if (data == 0xFF) ++n; // need to escape this for PARMRK
			w = write(ptm.fd, buffer, n);
		}
	}
	if (w != n) {
		if (VERBOSE) printf("PTY write error!\n");
		return;
	}
}

int pty_read (void)
{
	static bool line_old = false;
	if (ptm.fd < 0) return -1;
	struct timespec timeout = {0, 1000};
	int n = ppoll(&ptm, 1, &timeout, NULL);
	bool line_now = !(ptm.revents & POLLHUP);
	if (line_now != line_old) {
		if (VERBOSE) printf("PTY %sconnected.\n", line_now ? "" : "dis");
		line_old = line_now;
		return line_now ? 0x100 : 0x104;
	}
	if (!line_now) nanosleep(&timeout, NULL);
	if (n > 0 && ptm.revents & POLLIN) {
		unsigned char x;
		if (read(ptm.fd, &x, 1) == 1) {
			if (VERBOSE) printf("PTY read: %02X\n", x);
			return x;
		} else {
			if (VERBOSE) printf("PTY read error!\n");
		}
	}
	return -1;
}

