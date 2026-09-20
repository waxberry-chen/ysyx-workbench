#ifndef __SIM_STATS_H__
#define __SIM_STATS_H__

#include <stdbool.h>
#include <stdint.h>

void sim_stats_reset();
void sim_stats_sample_cycle(bool rst_n,
                            bool imem_req_valid, bool imem_req_ready,
                            bool imem_rsp_valid, bool imem_rsp_ready,
                            bool dmem_req_valid, bool dmem_req_ready,
                            bool dmem_rsp_valid, bool dmem_rsp_ready);
void sim_stats_record_commit(uint32_t pc, uint32_t npc);
void sim_stats_report();

#endif
