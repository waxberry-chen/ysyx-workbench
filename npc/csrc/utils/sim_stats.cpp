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

void sim_stats_sample_cycle(bool rst_n,
                            bool imem_req_valid, bool imem_req_ready,
                            bool imem_rsp_valid, bool imem_rsp_ready,
                            bool dmem_req_valid, bool dmem_req_ready,
                            bool dmem_rsp_valid, bool dmem_rsp_ready) {
  if (!rst_n) {
    return;
  }

  stats.cycles++;
  stats.if_request_stall_cycles += imem_req_valid && !imem_req_ready;
  stats.if_response_wait_cycles += imem_rsp_ready && !imem_rsp_valid;
  stats.if_response_stall_cycles += imem_rsp_valid && !imem_rsp_ready;
  stats.data_request_stall_cycles += dmem_req_valid && !dmem_req_ready;
  stats.data_response_wait_cycles += dmem_rsp_ready && !dmem_rsp_valid;
  stats.data_response_stall_cycles += dmem_rsp_valid && !dmem_rsp_ready;
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
