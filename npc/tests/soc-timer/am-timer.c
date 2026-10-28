#include <am.h>
#include <klib.h>
#include <ysyxsoc.h>
#undef assert
#define assert(c) do {if(!(c))halt(__LINE__);} while(0)

volatile unsigned ticks;
static unsigned yields;
static Context *handler(Event e, Context *c) {
  assert(!ienabled());
  assert(c->gpr[0]==0 && c->gpr[2]==(uintptr_t)(c+1));
  if(e.event==EVENT_IRQ_TIMER) {
    assert(c->mcause==0x80000007u && (c->mstatus&0x88)==0x80);
    ++ticks;
    ysyxsoc_timer_deadline(ysyxsoc_mtime()+10000);
    if(ticks==4) ysyxsoc_timer_enable(0);
  } else {
    assert(e.event==EVENT_YIELD); ++yields;
  }
  return c;
}
extern void timer_register_check(void);
int main(void) {
  cte_init(handler);
  assert(!ienabled());
  ysyxsoc_timer_deadline(ysyxsoc_mtime()+10000);
  ysyxsoc_timer_enable(1);
  iset(1); assert(ienabled());
  timer_register_check();
  iset(0); assert(!ienabled());
  yield();
  assert(ticks==4 && yields==1 && !ienabled());
  putch('T'); putch('\n');
  return 0;
}
