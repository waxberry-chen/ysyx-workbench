#include "map.h"

#define IO_SPACE_MAX (32 * 1024 * 1024)

static uint8_t *io_space = NULL;
static uint8_t *p_space = NULL;

uint8_t* new_space(int size) {
  uint8_t *p = p_space;
  // page aligned;
  size = (size + (PAGE_SIZE - 1)) & ~PAGE_MASK;
  p_space += size;
  assert(p_space - io_space < IO_SPACE_MAX);
  return p;
}

static bool check_bound(IOMap *map, paddr_t addr, int len) {
  if (map == NULL) {
    fflush(stdout);
    fprintf(stderr, "address (" FMT_PADDR ") does not match any MMIO map at pc = " FMT_WORD "\n",
        addr, sim_cpu.pc);
  } else if (addr < map->low || addr > map->high || (paddr_t)(len - 1) > map->high - addr) {
    fflush(stdout);
    fprintf(stderr,
        "%d-byte access at address " FMT_PADDR " is out of bound {%s} "
        "[" FMT_PADDR ", " FMT_PADDR "] at pc = " FMT_WORD "\n",
        len, addr, map->name, map->low, map->high, sim_cpu.pc);
  } else {
    return true;
  }

  sim_state.halt_pc = sim_cpu.pc;
  sim_state.halt_ret = 1;
  sim_state.state = SIM_END;
  return false;
}

static void invoke_callback(io_callback_t c, paddr_t offset, int len, bool is_write) {
  if (c != NULL) { c(offset, len, is_write); }
}

void init_map() {
  io_space = (uint8_t *)malloc(IO_SPACE_MAX);
  assert(io_space);
  p_space = io_space;
}

/* Check map and invoke callback function */
word_t map_read(paddr_t addr, int len, IOMap *map) {
  assert(len >= 1 && len <= 8);
  if (!check_bound(map, addr, len)) return 0;
  // offset here, once read 8 bytes
  paddr_t offset = addr - map->low;
  invoke_callback(map->callback, offset, len, false); // prepare data to read
  word_t ret = host_read(map->space + offset, len);
  return ret;
}

void map_write(paddr_t addr, int len, word_t data, IOMap *map) {
  assert(len >= 1 && len <= 8);
  if (!check_bound(map, addr, len)) return;
  paddr_t offset = addr - map->low;
  host_write(map->space + offset, len, data);
  invoke_callback(map->callback, offset, len, true);
}
