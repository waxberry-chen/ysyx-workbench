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
  uint32_t interval_cycles;
  uint32_t interval_stall_mask;
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
  stats.interval_cycles++;
  stats.if_request_stall_cycles += imem_req_valid && !imem_req_ready;
  stats.if_response_wait_cycles += imem_rsp_ready && !imem_rsp_valid;
  stats.if_response_stall_cycles += imem_rsp_valid && !imem_rsp_ready;
  stats.data_request_stall_cycles += dmem_req_valid && !dmem_req_ready;
  stats.data_response_wait_cycles += dmem_rsp_ready && !dmem_rsp_valid;
  stats.data_response_stall_cycles += dmem_rsp_valid && !dmem_rsp_ready;

  if (imem_req_valid && !imem_req_ready)
    stats.interval_stall_mask |= STALL_IF_REQUEST;
  if (imem_rsp_ready && !imem_rsp_valid)
    stats.interval_stall_mask |= STALL_IF_RESPONSE;
  if (imem_rsp_valid && !imem_rsp_ready)
    stats.interval_stall_mask |= STALL_IF_RSP_BACKPRESSURE;
  if (dmem_req_valid && !dmem_req_ready)
    stats.interval_stall_mask |= STALL_D_REQUEST;
  if (dmem_rsp_ready && !dmem_rsp_valid)
    stats.interval_stall_mask |= STALL_D_RESPONSE;
  if (dmem_rsp_valid && !dmem_rsp_ready)
    stats.interval_stall_mask |= STALL_D_RSP_BACKPRESSURE;
}

void sim_stats_record_commit(uint32_t pc, uint32_t npc) {
  stats.commits++;
  stats.redirects += npc != pc + 4u;
}

CommitCycleObservation sim_stats_take_commit_observation() {
  const CommitCycleObservation observation = {
      .cycles = stats.interval_cycles,
      .stall_mask = stats.interval_stall_mask,
  };
  stats.interval_cycles = 0;
  stats.interval_stall_mask = 0;
  return observation;
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
  Log("  frontend flushes        = %" PRIu64, stats.redirects);
}
