#ifndef __COMMIT_TRACE_H__
#define __COMMIT_TRACE_H__

#include <stdint.h>

#include "common.h"

void commit_trace_init(const char *path);
void commit_trace_record(uint64_t nr_inst, uint32_t pc, uint32_t inst,
                         const CPU_state *state, const CommitInfo *info);
void commit_trace_close();

#endif
