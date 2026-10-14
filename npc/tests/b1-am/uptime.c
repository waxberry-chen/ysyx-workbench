#include <am.h>
#include <klib.h>
#include <klib-macros.h>

static uint64_t ticks(void) {
  volatile uint32_t *timer = (void *)0xa0000048;
  uint32_t hi, lo, again;
  do { hi = timer[1]; lo = timer[0]; again = timer[1]; } while (hi != again);
  return ((uint64_t)hi << 32) | lo;
}
static uint64_t micros(uint64_t t) {
  return t / MTIME_HZ * 1000000ull + t % MTIME_HZ * 1000000ull / MTIME_HZ;
}
int main(void) {
  ioe_init();
  AM_TIMER_CONFIG_T cfg = io_read(AM_TIMER_CONFIG);
  assert(cfg.present && !cfg.has_rtc);
  AM_TIMER_RTC_T rtc = io_read(AM_TIMER_RTC);
  assert(rtc.year == 1900 && rtc.month == 0 && rtc.day == 0 &&
         rtc.hour == 0 && rtc.minute == 0 && rtc.second == 0);
  uint64_t prev = 0;
  for (int i = 0; i < 100; i++) {
    uint64_t before = micros(ticks());
    uint64_t now = io_read(AM_TIMER_UPTIME).us;
    uint64_t after = micros(ticks());
    assert(before <= now && now <= after && now > prev);
    prev = now;
  }
  putstr("uptime PASS\n");
  return 0;
}
