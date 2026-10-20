#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

using SocState = std::array<uint32_t,21>; // x0..x15, next PC, mstatus/mtvec/mepc/mcause
struct SocCommit { uint32_t pc,inst,flags,cause,addr; };
class SocDiff {
 public:
  ~SocDiff();
  void init(const std::string &path,const std::vector<uint8_t> &rom);
  void step(const SocCommit &c,const SocState &actual);
  void memory(const std::array<uint32_t,2048> &actual);
  bool active() const { return handle!=nullptr; }
  uint64_t steps=0, device_reads=0, device_writes=0, memory_checks=0;
 private:
  void *handle=nullptr;
  void (*copy)(uint32_t,void*,size_t,bool)=nullptr;
  void (*regs)(void*,bool)=nullptr;
  void (*execute)(uint64_t)=nullptr;
  void (*feed)(uint32_t,int,bool,uint32_t)=nullptr;
  int (*status)()=nullptr;
};
