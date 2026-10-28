#include <am.h>
#include <ysyxsoc.h>
#define check(c) do {if(!(c))halt(__LINE__);} while(0)
int main(void) {
  volatile uint32_t *time=(volatile uint32_t *)0x0200bff8;
  volatile uint32_t *cmp=(volatile uint32_t *)0x02004000;
  check(cmp[0]==UINT32_MAX && cmp[1]==UINT32_MAX);
  time[1]=7;time[0]=0xfffffff0;
  uint64_t first=ysyxsoc_mtime(),last;
  do {last=ysyxsoc_mtime();} while((last>>32)==7);
  check(last>=first && (last>>32)==8 && (uint32_t)last<10000);
  uint64_t deadline=last+100000;
  ysyxsoc_timer_deadline(deadline);
  check(cmp[0]==(uint32_t)deadline && cmp[1]==(uint32_t)(deadline>>32));
  uint32_t mip;
  asm volatile("csrr %0, mip":"=r"(mip));check(mip==0);
  ysyxsoc_timer_deadline(0);
  asm volatile("csrr %0, mip":"=r"(mip));check(mip==128);
  ysyxsoc_timer_deadline(UINT64_MAX);
  asm volatile("csrr %0, mip":"=r"(mip));check(mip==0);
  return 0;
}
