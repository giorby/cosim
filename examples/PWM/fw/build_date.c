/*
 * Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
 * Department of Information Engineering
 * Università Politecnica delle Marche (ITALY)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#define s(x) #x
#define S(x) s(x)

static const char  build_timestamp_txt[] = S(BUILD_TIMESTAMP) "\r\n";
const char * const build_timestamp_str = build_timestamp_txt;
const unsigned int build_timestamp_len = sizeof build_timestamp_txt - 1;

