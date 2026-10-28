#pragma once
#include <cstdint>
#include <stdexcept>

// Independent clock/register model. It observes accepted CLINT accesses, not
// the DUT's interrupt decision or returned load value, to predict time/MTIP.
struct SocTimer {
  uint64_t time=0, compare=UINT64_MAX, checks=0;
  bool pre=false, post=false;
  uint32_t read=0;
  uint64_t accesses=0;
  uint32_t access_addr=0,access_data=0;
  bool access_write=false;
  void edge(bool reset,uint64_t dut_time,uint64_t dut_compare,bool dut_irq,
            bool valid,bool write,uint32_t addr,unsigned size,uint32_t data,unsigned strb,
            uint32_t response) {
    if(reset) {time=0;compare=UINT64_MAX;pre=post=false;accesses=0;return;}
    pre=time>=compare;
    if(time!=dut_time || compare!=dut_compare || pre!=dut_irq)
      throw std::runtime_error("CLINT oracle counter/compare/MTIP mismatch");
    ++checks;
    bool mt=addr==0x0200bff8 || addr==0x0200bffc;
    bool cmp=addr==0x02004000 || addr==0x02004004;
    bool legal=(mt||cmp) && size==2 && (!write || strb==15);
    if(valid && legal && !write) {
      uint64_t value=mt?time:compare;
      read=uint32_t(value>>((addr&4)?32:0));
      if(read!=response)throw std::runtime_error("CLINT oracle read mismatch");
    }
    if(valid && legal) {
      ++accesses;access_addr=addr;access_write=write;access_data=write?data:read;
    }
    uint64_t next=time+1;
    if(valid && legal && write) {
      uint64_t &value=mt?time:compare;
      value=(addr&4) ? (value&UINT32_MAX)|(uint64_t(data)<<32)
                     : (value&0xffffffff00000000ULL)|data;
      if(mt)next=time; // half write wins over the complete counter tick
    }
    time=next;post=time>=compare;
  }
};
