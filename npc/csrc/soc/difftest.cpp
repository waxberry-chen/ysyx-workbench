#include "difftest.h"
#include <dlfcn.h>
#include <sstream>
#include <stdexcept>

namespace {
template<class T> T symbol(void *h,const char *name) {
  auto p=dlsym(h,name);
  if(!p)throw std::runtime_error(std::string("Missing DiffTest symbol: ")+name);
  return reinterpret_cast<T>(p);
}
void mismatch(const char *what,uint32_t pc,unsigned index,uint32_t expected,uint32_t actual) {
  std::ostringstream s;
  s<<"DiffTest mismatch "<<what<<"["<<index<<"] pc=0x"<<std::hex<<pc
   <<" ref=0x"<<expected<<" dut=0x"<<actual;
  throw std::runtime_error(s.str());
}
}
SocDiff::~SocDiff() { if(handle)dlclose(handle); }
void SocDiff::init(const std::string &path,const std::vector<uint8_t> &rom,
                   const std::vector<uint8_t> &flash,uint32_t reset_pc) {
  handle=dlopen(path.c_str(),RTLD_NOW|RTLD_LOCAL);
  if(!handle)throw std::runtime_error(dlerror());
  auto abi=symbol<uint32_t(*)()>(handle,"difftest_soc_abi");
  if(abi()!=0x534f4317)throw std::runtime_error("Incompatible SoC reference ABI");
  copy=symbol<decltype(copy)>(handle,"difftest_memcpy");
  regs=symbol<decltype(regs)>(handle,"difftest_regcpy");
  execute=symbol<decltype(execute)>(handle,"difftest_exec");
  feed=symbol<decltype(feed)>(handle,"difftest_soc_feed");
  status=symbol<decltype(status)>(handle,"difftest_soc_status");
  timer=symbol<decltype(timer)>(handle,"difftest_soc_timer");
  take_interrupt=symbol<decltype(take_interrupt)>(handle,"difftest_soc_interrupt");
  symbol<void(*)(int)>(handle,"difftest_init")(0);
  // Only nonvolatile images are loaded. Both machines execute RAM startup.
  copy(0x20000000,const_cast<uint8_t*>(rom.data()),rom.size(),true);
  if(!flash.empty())copy(0x30000000,const_cast<uint8_t*>(flash.data()),flash.size(),true);
  SocState state{};regs(state.data(),false);state[16]=reset_pc;regs(state.data(),true);
}
void SocDiff::step(const SocCommit &c,const SocState &actual,const SocTimer &clock) {
  SocState before{},expected{};
  timer(clock.pre);
  regs(before.data(),false);
  if(before[16]!=c.pc)mismatch("commit PC",c.pc,16,before[16],c.pc);
  uint32_t ins=0;
  bool fetchable=(c.pc>=0x20000000 && c.pc<=0x20000ffc) ||
                 (c.pc>=0x0f000000 && c.pc<=0x0f001ffc) ||
                 (c.pc>=0x30000000 && c.pc<=0x30fffffc) ||
                 (c.pc>=0x80000000 && c.pc<=0x803ffffc);
  if(fetchable && !(c.pc&3)) {
    copy(c.pc,&ins,4,false);
    if(ins!=c.inst)mismatch("instruction",c.pc,0,ins,c.inst);
    unsigned op=ins&127, f3=(ins>>12)&7, rs1=(ins>>15)&31, rd=(ins>>7)&31;
    if((op==3 || op==0x23) && rs1<16) {
      bool wr=op==0x23;
      int32_t imm=wr ? int32_t((ins&0xfe000000)|((ins>>7&31)<<20))>>20 : int32_t(ins)>>20;
      uint32_t addr=before[rs1]+imm;
      int len=1<<(f3&3);
      bool clint=(addr==0x0200bff8 || addr==0x0200bffc || addr==0x02004000 || addr==0x02004004) && len==4;
      bool device=(addr>=0x10000000 && addr<=0x10000007 && len==1) ||
                  (addr>=0x10001000 && addr<=0x10001018 && len==4) ||
                  clint;
      if(device && !(addr&(len-1))) {
        if(c.flags&1)throw std::runtime_error("Unexpected device access exception");
        if(!(c.flags&8) || !(c.flags&2) || bool(c.flags&4)!=wr || c.addr!=addr)
          throw std::runtime_error("MMIO metadata disagrees with reference decode");
        // Synchronize only a device read's input. NEMU still executes the
        // instruction and independently computes PC, all other GPR and CSR.
        unsigned rs2=(ins>>20)&31;
        if(rd>=16 && !wr)throw std::runtime_error("Invalid RV32E device destination");
        if(rs2>=16 && wr)throw std::runtime_error("Invalid RV32E device source");
        if(clint) {
          if(clock.accesses!=timer_accesses+1 || clock.access_addr!=addr || clock.access_write!=wr)
            throw std::runtime_error("CLINT transaction disagrees with reference instruction");
          ++timer_accesses;
          // Writes use actual bus data; NEMU checks it against its own source
          // register. Feeding before[rs2] here would merely compare REF to REF.
          if(wr && clock.access_data!=before[rs2])
            throw std::runtime_error("CLINT write data disagrees with reference source");
        }
        feed(addr,len,wr,clint ? clock.access_data : wr ? before[rs2] : actual[rd]);
        if(wr)++device_writes;else ++device_reads;
      }
    }
  }
  execute(1);
  if(status())throw std::runtime_error("Reference aborted");
  timer(clock.post);
  regs(expected.data(),false);
  for(unsigned i=0;i<expected.size();++i)
    if(expected[i]!=actual[i])mismatch(i<16?"GPR":i==16?"next PC":"CSR",c.pc,i,expected[i],actual[i]);
  ++steps;
}
void SocDiff::interrupt(uint32_t pc,const SocState &actual,bool pre_mtip,bool post_mtip) {
  SocState before{},expected{};
  timer(pre_mtip); regs(before.data(),false);
  if(before[16]!=pc)mismatch("IRQ boundary PC",pc,16,before[16],pc);
  if(take_interrupt())throw std::runtime_error("Reference rejects masked/unpending timer IRQ");
  timer(post_mtip); regs(expected.data(),false);
  for(unsigned i=0;i<expected.size();++i)
    if(expected[i]!=actual[i])mismatch("IRQ state",pc,i,expected[i],actual[i]);
  ++interrupts;
}
void SocDiff::psram_memory(const std::vector<uint8_t> &actual) {
  std::vector<uint8_t> expected(actual.size());
  copy(0x80000000,expected.data(),expected.size(),false);
  for(unsigned i=0;i<expected.size();++i)
    if(expected[i]!=actual[i])mismatch("PSRAM byte",0x80000000+i,i,expected[i],actual[i]);
  ++psram_checks;
}
void SocDiff::memory(const std::array<uint32_t,2048> &actual) {
  std::array<uint32_t,2048> expected{};
  copy(0x0f000000,expected.data(),sizeof expected,false);
  for(unsigned i=0;i<expected.size();++i)
    if(expected[i]!=actual[i])mismatch("SRAM word",0x0f000000+i*4,i,expected[i],actual[i]);
  ++memory_checks;
}
