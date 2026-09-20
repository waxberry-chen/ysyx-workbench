#include "sim_stats.h"

#include <inttypes.h>
#include <stdio.h>

#include "debug.h"

namespace {

struct SimStats {
  uint64_t cycles;
  uint64_t commits;
  uint64_t if_request_stall_cycles;
  uint64_t if_response_wait_cycles;
  uint64_t if_response_stall_cycles;
  uint64_t data_request_stall_cycles;
  uint64_t data_response_wait_cycles;
  uint64_t data_response_stall_cycles;
  uint64_t redirects;
};

SimStats stats = {};

}  // namespace

void sim_stats_reset() {
  stats = {};
}

void sim_stats_sample_cycle(bool rstn, bool if_req_valid, bool if_req_ready,
                            bool if_rsp_valid, bool if_rsp_ready,
                            bool d_req_valid, bool d_req_ready,
                            bool d_rsp_valid, bool d_rsp_ready) {
  if (!rstn) {
    return;
  }

  stats.cycles++;
  stats.if_request_stall_cycles += if_req_valid && !if_req_ready;
  stats.if_response_wait_cycles += if_rsp_ready && !if_rsp_valid;
  stats.if_response_stall_cycles += if_rsp_valid && !if_rsp_ready;
  stats.data_request_stall_cycles += d_req_valid && !d_req_ready;
  stats.data_response_wait_cycles += d_rsp_ready && !d_rsp_valid;
  stats.data_response_stall_cycles += d_rsp_valid && !d_rsp_ready;
}

void sim_stats_record_commit(uint32_t pc, uint32_t npc) {
  stats.commits++;
  stats.redirects += npc != pc + 4u;
}

void sim_stats_report() {
  const double cpi = stats.commits == 0
                         ? 0.0
                         : (double)stats.cycles / (double)stats.commits;

  Log("simulation statistics:");
  Log("  cycles                  = %" PRIu64, stats.cycles);
  Log("  committed instructions = %" PRIu64, stats.commits);
  Log("  CPI                     = %.3f", cpi);
  Log("  IF request stall cycles = %" PRIu64,
      stats.if_request_stall_cycles);
  Log("  IF response wait cycles = %" PRIu64,
      stats.if_response_wait_cycles);
  Log("  IF response stall cycles= %" PRIu64,
      stats.if_response_stall_cycles);
  Log("  redirects               = %" PRIu64, stats.redirects);
  Log("  data request stall cycles = %" PRIu64,
      stats.data_request_stall_cycles);
  Log("  data response wait cycles = %" PRIu64,
      stats.data_response_wait_cycles);
  Log("  data response stall cycles= %" PRIu64,
      stats.data_response_stall_cycles);
  Log("  frontend flushes        = N/A (no buffered frontend yet)");
}
