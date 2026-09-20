#include "commit_trace.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {

FILE *trace_file = nullptr;

uint64_t fnv1a_word(uint64_t hash, uint32_t value) {
  for (unsigned int shift = 0; shift < 32; shift += 8) {
    hash ^= (value >> shift) & 0xffu;
    hash *= UINT64_C(1099511628211);
  }
  return hash;
}

uint64_t architectural_state_hash(const CPU_state *state) {
  uint64_t hash = UINT64_C(14695981039346656037);
  for (const uint32_t reg : state->gpr) {
    hash = fnv1a_word(hash, reg);
  }
  hash = fnv1a_word(hash, state->pc);
  hash = fnv1a_word(hash, state->csr.mstatus);
  hash = fnv1a_word(hash, state->csr.mtvec);
  hash = fnv1a_word(hash, state->csr.mepc);
  hash = fnv1a_word(hash, state->csr.mcause);
  return hash;
}

}  // namespace

void commit_trace_init(const char *path) {
  if (path == nullptr) {
    return;
  }

  trace_file = fopen(path, "w");
  if (trace_file == nullptr) {
    fprintf(stderr, "Cannot open commit trace '%s': %s\n", path,
            strerror(errno));
    exit(1);
  }

  fprintf(trace_file, "# NPC commit trace v1\n");
  fprintf(trace_file, "# nr pc inst npc architectural_state_hash\n");
}

void commit_trace_record(uint64_t nr_inst, uint32_t pc, uint32_t inst,
                         const CPU_state *state) {
  if (trace_file == nullptr) {
    return;
  }

  fprintf(trace_file, "%" PRIu64 " %08x %08x %08x %016" PRIx64 "\n",
          nr_inst, pc, inst, state->pc, architectural_state_hash(state));
}

void commit_trace_close() {
  if (trace_file == nullptr) {
    return;
  }
  fclose(trace_file);
  trace_file = nullptr;
}
