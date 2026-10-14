#include <am.h>
#include "./include/npc.h"
#ifdef NPC_B1
_Static_assert(MTIME_HZ > 0 && MTIME_HZ <= UINT32_MAX, "MTIME_HZ must fit a positive uint32_t");
#endif

void __am_timer_init() {
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
#ifdef NPC_B1
  uint32_t high1, low, high2;
  do {
    high1 = inl(RTC_ADDR + 4);
    low = inl(RTC_ADDR);
    high2 = inl(RTC_ADDR + 4);
  } while (high1 != high2);
  uint64_t ticks = ((uint64_t)high1 << 32) | low;
  // Split before scaling to avoid ticks * 1000000 overflowing prematurely.
  uptime->us = (ticks / MTIME_HZ) * 1000000ull +
               ((ticks % MTIME_HZ) * 1000000ull) / MTIME_HZ;
#else
  uint64_t high32 = inl(RTC_ADDR+4);
  uint64_t low32 = inl(RTC_ADDR);
  uptime->us = (high32 << 32) | low32;
#endif
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
#ifdef NPC_B1
  *rtc = (AM_TIMER_RTC_T){ .year = 1900 };
#else
  rtc->second = inl(RTC_ADDR+8);
  rtc->minute = inl(RTC_ADDR+12);
  rtc->hour   = inl(RTC_ADDR+16);
  rtc->day    = inl(RTC_ADDR+20);
  rtc->month  = inl(RTC_ADDR+24);
  rtc->year   = inl(RTC_ADDR+28);
#endif
}
