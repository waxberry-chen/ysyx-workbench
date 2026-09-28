#ifndef __SIM_STATS_H__
#define __SIM_STATS_H__

#include <stdbool.h>
#include <stdint.h>

typedef struct {
  uint32_t cycles;
  uint32_t stall_mask;
} CommitCycleObservation;

enum {
  STALL_IF_REQUEST = 1u << 0,
  STALL_IF_RESPONSE = 1u << 1,
  STALL_IF_RSP_BACKPRESSURE = 1u << 2,
  STALL_D_REQUEST = 1u << 3,
  STALL_D_RESPONSE = 1u << 4,
  STALL_D_RSP_BACKPRESSURE = 1u << 5,
};

void sim_stats_reset();
void sim_stats_sample_cycle(bool rst_n,
                            bool if_arvalid, bool if_arready,
                            bool if_rvalid, bool if_rready,
                            bool d_arvalid, bool d_arready,
                            bool d_rvalid, bool d_rready,
                            bool d_awvalid, bool d_awready,
                            bool d_wvalid, bool d_wready,
                            bool d_bvalid, bool d_bready);
void sim_stats_record_commit(uint32_t pc, uint32_t npc);
CommitCycleObservation sim_stats_take_commit_observation();
void sim_stats_report();

#endif
