#include "map.h"
#include <sys/time.h>
#include <time.h>

static uint32_t *rtc_port_base = NULL;

static uint64_t boot_time = 0;

/* Use gettimeofday to get time */
static uint64_t get_time_internal() {
  struct timeval now;
  gettimeofday(&now, NULL);
  uint64_t us = now.tv_sec * 1000000 + now.tv_usec;
  return us;
}

/* mu second relative time */
uint64_t get_time() {
  if (boot_time == 0) boot_time = get_time_internal();
  uint64_t now = get_time_internal();
  return now - boot_time;
}

/* get struct time */
struct tm *get_time_tm() {
  time_t now = time(NULL);
  return localtime(&now);
}


// Timer callback function:
// Only offset == 4 will get time, stored time in rtc_port_base[0] and [1]
// So we need first RTC_ADDR+4 then RTC_ADDR
static void rtc_io_handler(uint32_t offset, int len, bool is_write) {
  // offset = addr - map->low
  assert(offset > 0 || offset < 32);
  if (!is_write && offset == 4) {
    uint64_t us = get_time();
    rtc_port_base[0] = (uint32_t)us;
    rtc_port_base[1] = us >> 32;
  }
  struct tm* rtc = get_time_tm();
  rtc_port_base[2] = rtc->tm_sec;
  rtc_port_base[3] = rtc->tm_min;
  rtc_port_base[4] = rtc->tm_hour;
  rtc_port_base[5] = rtc->tm_mday;
  rtc_port_base[6] = rtc->tm_mon + 1;
  rtc_port_base[7] = rtc->tm_year + 1900;
}

void init_timer() {
  rtc_port_base = (uint32_t *)new_space(32);  // 8 word, 32 byte
// Register peripheral (const char *name, paddr_t addr, void *space, uint32_t len, io_callback_t callback)
  add_mmio_map("rtc", CONFIG_RTC_MMIO, rtc_port_base, 32, rtc_io_handler);
}
