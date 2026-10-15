// Fixed cooperative workload using the local RT-Thread kernel and AM BSP context.c.
#include <am.h>
#include <klib.h>
#include <rtthread.h>
#include <rthw.h>
static struct rt_thread tasks[2];
static unsigned char stacks[2][8192] __attribute__((aligned(16)));
static volatile unsigned done[2];
static rt_size_t heap_before;
rt_base_t rt_hw_interrupt_disable(void) { return 0; }
void rt_hw_interrupt_enable(rt_base_t level) { (void)level; }
void rt_hw_console_output(const char *s) { while (*s) putch(*s++); }
static void task(void *arg) {
  unsigned id = (uintptr_t)arg, state = 0x1357 + id;
  unsigned char *buf = rt_malloc(128);
  assert(buf && (uintptr_t)buf >= (uintptr_t)heap.start && (uintptr_t)buf+128 <= (uintptr_t)heap.end);
  for (unsigned j=0;j<128;j++) buf[j] = j ^ id;
  for (unsigned i=0;i<100;i++) {
    assert(state == 0x1357 + id + 7*i);
    for (unsigned j=0;j<128;j++) assert(buf[j] == (unsigned char)(j^id));
    assert(done[id] == i && done[1-id] == i+id);
    putch('A'+id);
    done[id]++; state += 7;
    rt_thread_yield();
  }
  rt_free(buf);
  rt_thread_yield();
  assert(done[0] == 100 && done[1] == 100);
  rt_size_t total,used,max;
  rt_memory_info(&total,&used,&max);
  assert(used == heap_before && max > used && total > max);
  printf("\nRTTHREAD PASS iterations=100,100 heap_restored=1\n");
  halt(0);
}
int main(void) {
  extern void __am_cte_init(void);
  __am_cte_init();
  rt_system_timer_init();
  rt_system_scheduler_init();
  rt_system_heap_init(heap.start,heap.end);
  rt_thread_idle_init();
  rt_size_t total,max;
  rt_memory_info(&total,&heap_before,&max);
  assert(total > 32768);
  for (unsigned i=0;i<2;i++) {
    assert(rt_thread_init(&tasks[i],i?"B":"A",task,(void *)(uintptr_t)i,stacks[i],sizeof stacks[i],10,10)==RT_EOK);
  }
  // This RT-Thread revision inserts new peers at the head of the ready queue.
  assert(rt_thread_startup(&tasks[1])==RT_EOK);
  assert(rt_thread_startup(&tasks[0])==RT_EOK);
  printf("RTTHREAD BEGIN cooperative\n");
  rt_system_scheduler_start();
  halt(1);
  return 1;
}
