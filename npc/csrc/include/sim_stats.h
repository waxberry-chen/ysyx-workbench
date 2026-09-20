#ifndef __SIM_STATS_H__
#define __SIM_STATS_H__

#include <stdbool.h>
#include <stdint.h>

void sim_stats_reset();
void sim_stats_sample_cycle(bool rstn, bool if_req_valid, bool if_req_ready,
                            bool if_rsp_valid, bool if_rsp_ready);
void sim_stats_record_commit(uint32_t pc, uint32_t npc);
void sim_stats_report();

#endif
