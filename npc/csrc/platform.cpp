#include "common.h"
#include "debug.h"
#include "dut.h"
#include "platform.h"
#include "sim_stats.h"
#include "ram_model.h"
#include "memory/paddr.h"
#include <inttypes.h>
#include <stdlib.h>
#ifdef NPC_B1
#include "Vysyx_b1_top___024root.h"
static_assert(NPC_MTIME_HZ > 0 && NPC_MTIME_HZ <= UINT32_MAX, "MTIME_HZ must fit a positive uint32_t");
// The current NEMU reference has 128 MiB PMEM and its ABI has no size query.
// Refuse larger DUT preloads instead of overrunning the reference's memory.
static_assert(NPC_SRAM_BYTES <= 0x08000000, "B1 harness requires SRAM_BYTES <= current 128 MiB NEMU reference memory");
extern uint8_t pmem[];
namespace {
uint64_t cycles=0, uart_events=0, limit=50000000;
uint64_t if_accept=0,if_done=0,lsu_ar=0,lsu_aw=0,lsu_w=0,lsu_done=0;
struct Route {uint64_t ar=0,aw=0,w=0,r=0,b=0,rerr=0,berr=0;} routes[4];
FILE *uart_file=nullptr;
auto& memory() {return dut->rootp->ysyx_b1_top__DOT__sram__DOT__mem;}
}
#endif
void platform_init() {
#ifdef NPC_B1
  const char *max_cycles=getenv("NPC_MAX_CYCLES");
  if(max_cycles) {
    char *end=nullptr;limit=strtoull(max_cycles,&end,0);
    Assert(max_cycles[0] && end && !*end && limit,"Invalid NPC_MAX_CYCLES");
  }
  const char *path=getenv("NPC_UART_LOG");
  if(path) {uart_file=fopen(path,"wb");Assert(uart_file,"Cannot open UART log %s",path);}
  Log("NPC profile=b1 SRAM_BYTES=%u MTIME_HZ=%u timing=rtl-fixed max_cycles=%" PRIu64,
      (unsigned)NPC_SRAM_BYTES,(unsigned)NPC_MTIME_HZ,limit);
#else
  init_ram_model(sdb_args.ram_seed,sdb_args.ram_max_latency,sdb_args.ram_ready_percent);
#endif
}
void platform_load(size_t size) {
#ifdef NPC_B1
  Assert(size<=CONFIG_MSIZE,"Image exceeds SRAM capacity");
  dut->clk=0;dut->rst_n=0;dut->eval();
  // Explicit host initialization: image + zero-filled remainder, same as REF.
  for(size_t i=0;i<CONFIG_MSIZE;i+=4)
    memory()[i/4]=uint32_t(pmem[i])|(uint32_t(pmem[i+1])<<8)|
                 (uint32_t(pmem[i+2])<<16)|(uint32_t(pmem[i+3])<<24);
#else
  (void)size;
#endif
}
uint32_t platform_read(uint32_t addr,int size) {
#ifdef NPC_B1
  if((size!=1&&size!=2&&size!=4)||!in_pmem_range(addr,size)) {
    fprintf(stderr,"B1 debugger read outside SRAM/unsupported width: %08x size=%d\n",addr,size);
    return 0;
  }
  uint32_t value=0;
  for(int i=0;i<size;i++) {unsigned off=addr-CONFIG_MBASE+i;value|=((memory()[off/4]>>(8*(off%4)))&255u)<<(8*i);}
  return value;
#else
  return paddr_read(addr,size);
#endif
}
void platform_write(uint32_t addr,int size,uint32_t data) {
#ifdef NPC_B1
  (void)addr;(void)size;(void)data;
  fprintf(stderr,"B1 debugger writes are unsupported; runtime writes must use AXI\n");
#else
  paddr_write(addr,size,data);
#endif
}
void platform_sample() {
#ifdef NPC_B1
  const unsigned m=dut->monitor_bus;
  bool v[14];for(int i=0;i<14;i++)v[i]=(m>>i)&1;
  sim_stats_sample_cycle(dut->rst_n,v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9],v[10],v[11],v[12],v[13]);
  if(!dut->rst_n)return;
  if_accept+=v[0]&&v[1];if_done+=v[2]&&v[3];lsu_ar+=v[4]&&v[5];
  lsu_aw+=v[8]&&v[9];lsu_w+=v[10]&&v[11];lsu_done+=(v[6]&&v[7])||(v[12]&&v[13]);
  for(int i=0;i<4;i++) {
    auto& r=routes[i];r.ar+=(dut->monitor_ar>>i)&1;r.aw+=(dut->monitor_aw>>i)&1;
    r.w+=(dut->monitor_w>>i)&1;r.r+=(dut->monitor_r>>i)&1;r.b+=(dut->monitor_b>>i)&1;
    r.rerr+=((dut->monitor_r>>i)&1)&&((dut->monitor_rresp>>(i*2))&3);
    r.berr+=((dut->monitor_b>>i)&1)&&((dut->monitor_bresp>>(i*2))&3);
    Assert(r.r<=r.ar&&r.b<=r.aw&&r.b<=r.w,"B1 response without request route=%d",i);
  }
#else
  sim_stats_sample_cycle(dut->rst_n,dut->ifu_axi_arvalid,dut->ifu_axi_arready,dut->ifu_axi_rvalid,dut->ifu_axi_rready,
      dut->lsu_axi_arvalid,dut->lsu_axi_arready,dut->lsu_axi_rvalid,dut->lsu_axi_rready,
      dut->lsu_axi_awvalid,dut->lsu_axi_awready,dut->lsu_axi_wvalid,dut->lsu_axi_wready,dut->lsu_axi_bvalid,dut->lsu_axi_bready);
  ram_model_sample();
#endif
}
void platform_tick() {
#ifdef NPC_B1
  if(!dut->rst_n)return;
  if(dut->tx_valid) {
    ++uart_events;putchar(dut->tx_data);fflush(stdout);
    if(uart_file){fputc(dut->tx_data,uart_file);fflush(uart_file);}
  }
  if(++cycles>=limit) {
    fprintf(stderr,"B1 cycle limit reached: %" PRIu64 "\n",limit);
    sim_state.state=SIM_ABORT;sim_state.halt_pc=dut->commit_pc;
  }
#else
  ram_model_tick();
#endif
}
void platform_report() {
#ifdef NPC_B1
  const char *names[]={"sram","uart","clint","default"};
  Log("B1 master IF accepted=%" PRIu64 " completed=%" PRIu64 " outstanding=%" PRIu64,if_accept,if_done,if_accept-if_done);
  Log("B1 master LSU ar=%" PRIu64 " aw=%" PRIu64 " w=%" PRIu64 " completed=%" PRIu64,lsu_ar,lsu_aw,lsu_w,lsu_done);
  for(int i=0;i<4;i++){const auto& r=routes[i];
    Log("B1 route=%s ar=%" PRIu64 " aw=%" PRIu64 " w=%" PRIu64 " r=%" PRIu64 " b=%" PRIu64 " rerr=%" PRIu64 " berr=%" PRIu64,
        names[i],r.ar,r.aw,r.w,r.r,r.b,r.rerr,r.berr);
  }
  Log("B1 uart_events=%" PRIu64 " cycles=%" PRIu64 " (commit-stop; speculative requests may remain)",uart_events,cycles);
  if(uart_file)fflush(uart_file);
#else
  ram_model_report();
#endif
}
