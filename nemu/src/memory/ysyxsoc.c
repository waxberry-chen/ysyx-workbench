// Fixed S0/S2 platform map. The interpreter and CPU state remain NEMU's.
#include <common.h>
#ifdef CONFIG_YSYXSOC
#include <memory/paddr.h>
#include <memory/host.h>
#include <memory/ysyxsoc.h>
#include <isa.h>
#include <cpu/cpu.h>
#include <utils.h>
#include <difftest-def.h>

static uint8_t rom[4096], ram[8192];
static bool span(uint32_t a, size_t n, uint32_t base, size_t size) {
  return a >= base && n <= size && (uint64_t)a - base <= size - n;
}
bool soc_memory_span(paddr_t a, size_t n) {
  return span(a,n,0x20000000,sizeof rom) || span(a,n,0x0f000000,sizeof ram);
}
bool soc_memory_writable(paddr_t a, size_t n) { return span(a,n,0x0f000000,sizeof ram); }
bool soc_device_access(paddr_t a, int len, bool write) {
  // Only implemented S3 device operations can consume external data.
  return (a >= 0x10000000 && a <= 0x10000007 && len == 1) ||
         ((a == 0x0200bff8 || a == 0x0200bffc) && len == 4 && !write);
}
uint8_t *guest_to_host(paddr_t a) {
  assert(soc_memory_span(a,1));
  return a >= 0x20000000 ? rom + a-0x20000000 : ram + a-0x0f000000;
}
paddr_t host_to_guest(uint8_t *h) {
  uintptr_t p=(uintptr_t)h, r=(uintptr_t)rom, s=(uintptr_t)ram;
  if (p>=r && p-r<sizeof rom) return 0x20000000 + (p-r);
  assert(p>=s && p-s<sizeof ram);
  return 0x0f000000 + (p-s);
}
void init_mem(void) { memset(rom,0,sizeof rom); memset(ram,0,sizeof ram); }

// One-use device input, never a whole-register-state skip. Normal ROM/SRAM
// instructions cannot consume this token. Store values are checked as well.
static struct { bool pending,write; paddr_t addr; int len; word_t data; } io;
__EXPORT void difftest_soc_feed(paddr_t a, int len, bool write, word_t data) {
  assert(!io.pending && soc_device_access(a,len,write));
  io.pending=true; io.addr=a; io.len=len; io.write=write; io.data=data;
}
static word_t device(paddr_t a, int len, bool write, word_t data) {
  assert(io.pending && io.addr==a && io.len==len && io.write==write);
  word_t mask = len==4 ? UINT32_MAX : ((1u<<(len*8))-1);
  if (write) assert((data & mask)==(io.data & mask));
  io.pending=false;
  return io.data & mask;
}
word_t paddr_read(paddr_t a, int len) {
  if (soc_memory_span(a,len)) return host_read(guest_to_host(a),len);
  assert(soc_device_access(a,len,false));
  return device(a,len,false,0);
}
void paddr_write(paddr_t a, int len, word_t data) {
  if (soc_memory_writable(a,len)) { host_write(guest_to_host(a),len,data); return; }
  assert(soc_device_access(a,len,true));
  device(a,len,true,data);
}
__EXPORT uint32_t difftest_soc_abi(void) {
  _Static_assert(sizeof(CPU_state)==21*4, "SoC DiffTest ABI: 16 GPR + PC + 4 CSR");
  return 0x534f4315; // SOC + word count; reject an unrelated NEMU .so early
}
__EXPORT int difftest_soc_status(void) {
  assert(!io.pending);
  return nemu_state.state == NEMU_ABORT ? -1 : 0;
}
#endif
