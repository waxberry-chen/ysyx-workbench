// S6: bounded, self-checking kernel workload. Busy peers never yield; only the
// later sleep phase intentionally blocks. UART reports are emitted at the end.
#include <am.h>
#include <klib.h>
#include <rtthread.h>
#include <rthw.h>
#include <ysyxsoc.h>

static struct rt_thread tasks[2];
unsigned char worker_stacks[2][8192] __attribute__((aligned(16)));
volatile unsigned progress[2];
static volatile unsigned ready[2], done[2], switches[2], irq_switches, idle_runs;
static volatile unsigned wake_ticks[2], sleep_ticks[2];
static rt_size_t heap_before;
static unsigned char *buffers[2];
extern void preempt_registers(unsigned id);
#define CHECK(c) do { if (!(c)) { printf("S6 FAIL line=%d\n", __LINE__); halt(__LINE__); } } while (0)
void rt_hw_console_output(const char *s) { while (*s) putch(*s++); }
static void switched(rt_thread_t from, rt_thread_t to) {
  if (rt_interrupt_get_nest()) ++irq_switches;
  for (unsigned i=0;i<2;i++) if (to==&tasks[i] && from==&tasks[1-i]) {
    ++switches[i];
    // During the rendezvous phase there is no software scheduling request.
    if (!ready[0] && !ready[1]) CHECK(rt_interrupt_get_nest()==1);
  }
}
static void idle(void) { ++idle_runs; }
static void report_stack(const char *name, rt_thread_t t) {
  unsigned char *p=t->stack_addr;
  unsigned untouched=0;
  while (untouched<t->stack_size && p[untouched]=='#') ++untouched;
  CHECK(untouched>=128 && untouched<t->stack_size);
  printf("STACK %s size=%u untouched=%u\n",name,(unsigned)t->stack_size,untouched);
}
static void worker(void *arg) {
  unsigned id=(uintptr_t)arg;
  volatile unsigned local[16];
  CHECK(ienabled());
  for (unsigned i=0;i<16;i++) local[i]=0x13570000u+(id<<8)+i;
  buffers[id]=rt_malloc(256);
  CHECK(buffers[id] && (uintptr_t)buffers[id]>=(uintptr_t)heap.start &&
        (uintptr_t)buffers[id]+256<=(uintptr_t)heap.end);
  for (unsigned i=0;i<256;i++) buffers[id][i]=(unsigned char)(i^id^0x5a);
  preempt_registers(id);
  CHECK(progress[0]==6 && progress[1]==6);
  // One time slice can finish the previous round and publish the next one:
  // six rendezvous rounds therefore require three entries into each peer.
  CHECK(switches[0]>=3 && switches[1]>=3);
  ready[id]=1;
  while (!ready[1-id]) asm volatile("" ::: "memory");
  // Both peers sleep long enough for the idle thread to run. Wakeups must be
  // caused by RT-Thread's timer processing, not a harness/manual resume.
  sleep_ticks[id]=rt_tick_get();
  CHECK(rt_thread_delay(4+id*2)==RT_EOK);
  wake_ticks[id]=rt_tick_get();
  CHECK(wake_ticks[id]-sleep_ticks[id]>=4+id*2);
  CHECK(ienabled() && rt_interrupt_get_nest()==0);
  for (unsigned i=0;i<16;i++) CHECK(local[i]==0x13570000u+(id<<8)+i);
  for (unsigned i=0;i<256;i++) CHECK(buffers[id][i]==(unsigned char)(i^id^0x5a));
  rt_free(buffers[id]);
  done[id]=1;
  while (!done[1-id]) asm volatile("" ::: "memory");
  if (id) { for (;;) asm volatile("" ::: "memory"); }
  iset(false);
  CHECK(idle_runs>0 && irq_switches>=8 && rt_interrupt_get_nest()==0);
  rt_size_t total,used,peak;
  rt_memory_info(&total,&used,&peak);
  CHECK(used==heap_before && peak>used && total>peak);
  printf("PREEMPT progress=%u,%u switches=%u,%u irq_switches=%u\n",
         progress[0],progress[1],switches[0],switches[1],irq_switches);
  printf("WAKE elapsed=%u,%u idle_runs=%u\n",
         wake_ticks[0]-sleep_ticks[0],wake_ticks[1]-sleep_ticks[1],idle_runs);
  printf("HEAP total=%u before=%u used=%u peak=%u\n",
         (unsigned)total,(unsigned)heap_before,(unsigned)used,(unsigned)peak);
  report_stack("worker0",&tasks[0]); report_stack("worker1",&tasks[1]);
  report_stack("idle",rt_thread_idle_gethandler());
  printf("RTT SYSTEM PASS\n"); halt(0);
}
int main(void) {
  extern void __am_cte_init(void),__am_timer_init(void);
  __am_cte_init(); rt_system_timer_init(); rt_system_scheduler_init();
  rt_system_heap_init(heap.start,heap.end); rt_thread_idle_init();
  rt_size_t total,peak;
  rt_memory_info(&total,&heap_before,&peak); CHECK(total>32768);
  CHECK(rt_thread_idle_sethook(idle)==RT_EOK);
  rt_scheduler_sethook(switched);
  for (unsigned i=0;i<2;i++) CHECK(rt_thread_init(&tasks[i],i?"B":"A",worker,
       (void *)(uintptr_t)i,worker_stacks[i],sizeof worker_stacks[i],10,1)==RT_EOK);
  CHECK(rt_thread_startup(&tasks[1])==RT_EOK);
  CHECK(rt_thread_startup(&tasks[0])==RT_EOK);
  __am_timer_init(); rt_system_scheduler_start();
  return 1;
}
