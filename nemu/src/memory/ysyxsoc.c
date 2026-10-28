// S4 platform map. The interpreter and architectural state remain NEMU's.
#include <common.h>
#ifdef CONFIG_YSYXSOC
#include <memory/paddr.h>
#include <memory/host.h>
#include <memory/ysyxsoc.h>
#include <isa.h>
#include <cpu/cpu.h>
#include <utils.h>
#include <difftest-def.h>

static uint8_t rom[4096], ram[8192], flash[16*1024*1024], psram[4*1024*1024];
static bool span(uint32_t a, size_t n, uint32_t base, size_t size) {
  return a >= base && n <= size && (uint64_t)a - base <= size - n;
}
bool soc_memory_span(paddr_t a, size_t n) {
  return span(a,n,0x20000000,sizeof rom) || span(a,n,0x0f000000,sizeof ram) ||
         span(a,n,0x30000000,sizeof flash) || span(a,n,0x80000000,sizeof psram);
}
bool soc_memory_writable(paddr_t a, size_t n) { return span(a,n,0x0f000000,sizeof ram) || span(a,n,0x80000000,sizeof psram); }
bool soc_device_access(paddr_t a, int len, bool write) {
  (void)write;
  // Explicit register operations only: Flash/PSRAM never consume MMIO tokens.
  return (a >= 0x10000000 && a <= 0x10000007 && len == 1) ||
         (a >= 0x10001000 && a <= 0x10001018 && !(a & 3) && len == 4) ||
         ((a == 0x0200bff8 || a == 0x0200bffc || a == 0x02004000 || a == 0x02004004) && len == 4);
}
uint8_t *guest_to_host(paddr_t a) {
  assert(soc_memory_span(a,1));
  if(a >= 0x80000000) return psram + a-0x80000000;
  if(a >= 0x30000000) return flash + a-0x30000000;
  if(a >= 0x20000000) return rom + a-0x20000000;
  return ram + a-0x0f000000;
}
paddr_t host_to_guest(uint8_t *h) {
  uintptr_t p=(uintptr_t)h, r=(uintptr_t)rom, s=(uintptr_t)ram;
  if(p >= (uintptr_t)flash && p-(uintptr_t)flash<sizeof flash) return 0x30000000+p-(uintptr_t)flash;
  if(p >= (uintptr_t)psram && p-(uintptr_t)psram<sizeof psram) return 0x80000000+p-(uintptr_t)psram;
  if (p>=r && p-r<sizeof rom) return 0x20000000 + (p-r);
  assert(p>=s && p-s<sizeof ram);
  return 0x0f000000 + (p-s);
}
void init_mem(void) { memset(rom,0,sizeof rom); memset(ram,0,sizeof ram); memset(flash,0xff,sizeof flash); memset(psram,0,sizeof psram); }

// One-use device input, never a whole-register-state skip. Normal memory
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
  _Static_assert(sizeof(CPU_state)==23*4, "SoC DiffTest ABI: 16 GPR + PC + 6 CSR");
  _Static_assert(DIFFTEST_REG_SIZE==sizeof(CPU_state), "regcpy must include every SoC CSR");
  return 0x534f4317; // SOC + word count; reject an unrelated NEMU .so early
}
// Synchronize a peripheral input, never copy DUT trap CSR/GPR state. The
// cycle-counted timer oracle supplies pre-edge MTIP for CSR reads/entry and
// post-edge MTIP for the architectural snapshot.
__EXPORT void difftest_soc_timer(bool pending) { cpu.csr.mip=pending ? 0x80u : 0; }
__EXPORT int difftest_soc_interrupt(void) {
  if (!(cpu.csr.mstatus & 8) || !(cpu.csr.mie & cpu.csr.mip & 0x80)) return -1;
  cpu.pc=isa_raise_intr(0x80000007u,cpu.pc);
  cpu.csr.mstatus=(cpu.csr.mstatus & ~0x88u) | ((cpu.csr.mstatus & 8u)<<4) | 0x1800u;
  return 0;
}
__EXPORT int difftest_soc_status(void) {
  assert(!io.pending);
  return nemu_state.state == NEMU_ABORT ? -1 : 0;
}
#endif
