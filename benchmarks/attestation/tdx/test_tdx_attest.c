/*
 * Copyright (C) 2011-2021 Intel Corporation. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Intel Corporation nor the names of its
 *     contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include "tdx_attest.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define devname "/dev/tdx-attest"
#define HEX_DUMP_SIZE 16

static void print_hex_dump(const char *title, const char *prefix_str,
                           const uint8_t *buf, int len) {
  const uint8_t *ptr = buf;
  int i, rowsize = HEX_DUMP_SIZE;

  if (!len || !buf)
    return;

  fprintf(stdout, "\t\t%s", title);

  for (i = 0; i < len; i++) {
    if (!(i % rowsize))
      fprintf(stdout, "\n%s%.8x:", prefix_str, i);
    if (ptr[i] <= 0x0f)
      fprintf(stdout, " 0%x", ptr[i]);
    else
      fprintf(stdout, " %x", ptr[i]);
  }

  fprintf(stdout, "\n");
}

void gen_report_data(uint8_t *reportdata) {
  int i;

  srand(time(NULL));

  for (i = 0; i < TDX_REPORT_DATA_SIZE; i++)
    reportdata[i] = rand();
}

double get_time_diff(struct timespec start, struct timespec end) {
  return ((end.tv_sec - start.tv_sec) * 1e3) +
         ((end.tv_nsec - start.tv_nsec) / 1e6);
}

int main(int argc, char *argv[]) {
  uint32_t quote_size = 0;
  tdx_report_data_t report_data = {{0}};
  tdx_report_t tdx_report = {{0}};
  tdx_uuid_t selected_att_key_id = {0};
  uint8_t *p_quote_buf = NULL;
  tdx_rtmr_event_t rtmr_event = {0};
  FILE *fptr = NULL;
  struct timespec start, end;
  double report_time, quote_time;

  gen_report_data(report_data.d);
  print_hex_dump("\n\t\tTDX report data\n", " ", report_data.d,
                 sizeof(report_data.d));

  clock_gettime(CLOCK_MONOTONIC, &start);
  if (TDX_ATTEST_SUCCESS != tdx_att_get_report(&report_data, &tdx_report)) {
    fprintf(stderr, "\nFailed to get the report\n");
    return 1;
  }
  clock_gettime(CLOCK_MONOTONIC, &end);
  report_time = get_time_diff(start, end);

  fptr = fopen("report.dat", "wb");
  if (fptr) {
    fwrite(&tdx_report, sizeof(tdx_report), 1, fptr);
    fclose(fptr);
  }
  fprintf(stdout, "\nWrote TD Report to report.dat\n");

  clock_gettime(CLOCK_MONOTONIC, &start);
  if (TDX_ATTEST_SUCCESS != tdx_att_get_quote(&report_data, NULL, 0,
                                              &selected_att_key_id,
                                              &p_quote_buf, &quote_size, 0)) {
    fprintf(stderr, "\nFailed to get the quote\n");
    return 1;
  }
  clock_gettime(CLOCK_MONOTONIC, &end);
  quote_time = get_time_diff(start, end);

  print_hex_dump("\n\t\tTDX quote data\n", " ", p_quote_buf, quote_size);

  fprintf(stdout, "\nSuccessfully got the TD Quote\n");
  fptr = fopen("quote.dat", "wb");
  if (fptr) {
    fwrite(p_quote_buf, quote_size, 1, fptr);
    fclose(fptr);
  }
  fprintf(stdout, "\nWrote TD Quote to quote.dat\n");

  rtmr_event.version = 1;
  rtmr_event.rtmr_index = 2;
  for (int i = 0; i < sizeof(rtmr_event.extend_data); i++) {
    rtmr_event.extend_data[i] = 1;
  }
  rtmr_event.event_data_size = 0;

  if (TDX_ATTEST_SUCCESS != tdx_att_extend(&rtmr_event)) {
    fprintf(stderr, "\nFailed to extend rtmr[2]\n");
  } else {
    fprintf(stderr, "\nSuccessfully extended rtmr[2]\n");
  }

  rtmr_event.rtmr_index = 3;

  if (TDX_ATTEST_SUCCESS != tdx_att_extend(&rtmr_event)) {
    fprintf(stderr, "\nFailed to extend rtmr[3]\n");
  } else {
    fprintf(stderr, "\nSuccessfully extended rtmr[3]\n");
  }

  tdx_att_free_quote(p_quote_buf);

  printf("Time taken for tdx_att_get_report: %f ms\n", report_time);
  printf("Time taken for tdx_att_get_quote: %f ms\n", quote_time);

  return 0;
}
