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
                            bool if_arvalid, bool if_arready,
                            bool if_rvalid, bool if_rready,
                            bool d_arvalid, bool d_arready,
                            bool d_rvalid, bool d_rready,
                            bool d_awvalid, bool d_awready,
                            bool d_wvalid, bool d_wready,
                            bool d_bvalid, bool d_bready) {
  if (!rst_n) {
    return;
  }

  stats.cycles++;
  stats.interval_cycles++;
  const bool if_request_stall = if_arvalid && !if_arready;
  const bool if_response_wait = if_rready && !if_rvalid;
  const bool if_response_stall = if_rvalid && !if_rready;
  const bool data_request_stall =
      (d_arvalid && !d_arready) || (d_awvalid && !d_awready) ||
      (d_wvalid && !d_wready);
  const bool data_response_wait =
      (d_rready && !d_rvalid) || (d_bready && !d_bvalid);
  const bool data_response_stall =
      (d_rvalid && !d_rready) || (d_bvalid && !d_bready);

  stats.if_request_stall_cycles += if_request_stall;
  stats.if_response_wait_cycles += if_response_wait;
  stats.if_response_stall_cycles += if_response_stall;
  stats.data_request_stall_cycles += data_request_stall;
  stats.data_response_wait_cycles += data_response_wait;
  stats.data_response_stall_cycles += data_response_stall;

  if (if_request_stall)
    stats.interval_stall_mask |= STALL_IF_REQUEST;
  if (if_response_wait)
    stats.interval_stall_mask |= STALL_IF_RESPONSE;
  if (if_response_stall)
    stats.interval_stall_mask |= STALL_IF_RSP_BACKPRESSURE;
  if (data_request_stall)
    stats.interval_stall_mask |= STALL_D_REQUEST;
  if (data_response_wait)
    stats.interval_stall_mask |= STALL_D_RESPONSE;
  if (data_response_stall)
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
