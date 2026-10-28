#ifndef AM_YSYXSOC_H
#define AM_YSYXSOC_H
#include <stdint.h>

// Platform timer, 100 MHz in this SoC simulation. AM's portable iset() only
// controls global MIE; these helpers explicitly control the timer source.
#define YSYXSOC_TIMER_HZ 100000000u
static inline uint64_t ysyxsoc_mtime(void) {
  volatile uint32_t *p=(volatile uint32_t *)0x0200bff8;
  uint32_t hi,lo,again;
  do {hi=p[1];lo=p[0];again=p[1];} while(hi!=again);
  return ((uint64_t)hi<<32)|lo;
}
static inline void ysyxsoc_timer_deadline(uint64_t deadline) {
  volatile uint32_t *p=(volatile uint32_t *)0x02004000;
  // RV32 safe update: temporary maximum low half avoids a transient earlier
  // deadline while replacing the two halves. MMIO is strongly ordered here.
  p[0]=UINT32_MAX;p[1]=(uint32_t)(deadline>>32);p[0]=(uint32_t)deadline;
  asm volatile("" ::: "memory");
}
static inline void ysyxsoc_timer_enable(int enabled) {
  uintptr_t mask=0x80;
  if(enabled) asm volatile("csrs mie, %0" :: "r"(mask) : "memory");
  else asm volatile("csrc mie, %0" :: "r"(mask) : "memory");
}
#endif
