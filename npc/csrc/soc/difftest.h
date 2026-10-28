#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>
#include "timer.h"

using SocState = std::array<uint32_t,23>; // x0..x15, next PC, mstatus/mtvec/mepc/mcause/mie/mip
struct SocCommit { uint32_t pc,inst,flags,cause,addr; };
class SocDiff {
 public:
  ~SocDiff();
  void init(const std::string &path,const std::vector<uint8_t> &rom,
            const std::vector<uint8_t> &flash,uint32_t reset_pc);
  void step(const SocCommit &c,const SocState &actual,const SocTimer &clock);
  void interrupt(uint32_t pc,const SocState &actual,bool pre_mtip,bool post_mtip);
  void memory(const std::array<uint32_t,2048> &actual);
  void psram_memory(const std::vector<uint8_t> &actual);
  bool active() const { return handle!=nullptr; }
  uint64_t steps=0, device_reads=0, device_writes=0, memory_checks=0;
  uint64_t psram_checks=0;
  uint64_t interrupts=0;
 private:
  void *handle=nullptr;
  void (*copy)(uint32_t,void*,size_t,bool)=nullptr;
  void (*regs)(void*,bool)=nullptr;
  void (*execute)(uint64_t)=nullptr;
  void (*feed)(uint32_t,int,bool,uint32_t)=nullptr;
  int (*status)()=nullptr;
  void (*timer)(bool)=nullptr;
  int (*take_interrupt)()=nullptr;
  uint64_t timer_accesses=0;
};
