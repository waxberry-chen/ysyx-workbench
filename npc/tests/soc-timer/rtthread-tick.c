// Small S5 BSP tick/critical-section check. S6 owns the full two-thread
// preemption + blocking/wakeup and stack/heap-watermark acceptance workload.
#include <am.h>
#include <klib.h>
#include <rtthread.h>
#include <rthw.h>
static struct rt_thread task;
static unsigned char stack[8192] __attribute__((aligned(16)));
void rt_hw_console_output(const char *s) {while(*s)putch(*s++);}
static void worker(void *unused) {
  (void)unused;
  assert(ienabled());
  rt_base_t a=rt_hw_interrupt_disable(),b=rt_hw_interrupt_disable();
  assert(a==1 && b==0 && !ienabled());
  rt_hw_interrupt_enable(b);assert(!ienabled());
  rt_hw_interrupt_enable(a);assert(ienabled());
  rt_tick_t start=rt_tick_get();
  while(rt_tick_get()-start<3) asm volatile("" ::: "memory");
  iset(0);
  assert(rt_interrupt_get_nest()==0);
  printf("RTT TICK PASS\n");halt(0);
}
int main(void) {
  extern void __am_cte_init(void),__am_timer_init(void);
  __am_cte_init();rt_system_timer_init();rt_system_scheduler_init();
  rt_system_heap_init(heap.start,heap.end);rt_thread_idle_init();
  assert(rt_thread_init(&task,"tick",worker,0,stack,sizeof stack,10,1)==RT_EOK);
  assert(rt_thread_startup(&task)==RT_EOK);
  __am_timer_init();rt_system_scheduler_start();
  return 1;
}
