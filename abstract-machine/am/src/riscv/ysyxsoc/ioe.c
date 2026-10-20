#include <am.h>
#include <stdint.h>

bool ioe_init(void) { return true; }
void ioe_read(int reg, void *buf) {
  switch (reg) {
    case AM_TIMER_CONFIG:
      *(AM_TIMER_CONFIG_T *)buf = (AM_TIMER_CONFIG_T){ .present=true, .has_rtc=false };
      return;
    case AM_TIMER_UPTIME: {
      volatile uint32_t *mtime = (volatile uint32_t *)0x0200bff8;
      uint32_t hi, lo, hi2;
      do { hi=mtime[1]; lo=mtime[0]; hi2=mtime[1]; } while (hi != hi2);
      // One tick per CPU clock; current simulation clock is 100 MHz.
      ((AM_TIMER_UPTIME_T *)buf)->us = (((uint64_t)hi << 32) | lo) / 100;
      return;
    }
    case AM_TIMER_RTC:
      *(AM_TIMER_RTC_T *)buf = (AM_TIMER_RTC_T){ .year=1900 }; return;
    case AM_INPUT_CONFIG:
      *(AM_INPUT_CONFIG_T *)buf = (AM_INPUT_CONFIG_T){ .present=false }; return;
    case AM_UART_CONFIG:
      *(AM_UART_CONFIG_T *)buf = (AM_UART_CONFIG_T){ .present=false }; return;
    default: halt(2);
  }
}
void ioe_write(int reg, void *buf) { (void)reg; (void)buf; halt(2); }
