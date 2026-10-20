#include <am.h>
#include <stdint.h>
int main(const char *args) {
  (void)args;
  AM_TIMER_CONFIG_T cfg;
  AM_TIMER_UPTIME_T first, last;
  ioe_init(); ioe_read(AM_TIMER_CONFIG, &cfg);
  if (!cfg.present || cfg.has_rtc) halt(1);
  ioe_read(AM_TIMER_UPTIME, &first);
  for (volatile unsigned n=0;n<100;n++) {}
  ioe_read(AM_TIMER_UPTIME, &last);
  if (!first.us || last.us<=first.us) halt(1);
  return 0;
}
