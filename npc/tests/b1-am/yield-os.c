// Finite version of am-kernels/kernels/yield-os: real AM trap/context path.
#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#define ROUNDS 100
typedef union { uint8_t stack[32768]; struct { Context *cp; }; } PCB;
static PCB pcb[2], boot, *current = &boot;
static volatile unsigned done[2];
static unsigned switches;
static Context *schedule(Event ev, Context *prev) {
  assert(ev.event == EVENT_YIELD);
  current->cp = prev;
  current = current == &pcb[0] ? &pcb[1] : &pcb[0];
  switches++;
  return current->cp;
}
static void task(void *arg) {
  unsigned id = (uintptr_t)arg;
  unsigned state = 17 + id;
  for (unsigned i = 0; i < ROUNDS; i++) {
    assert(state == 17 + id + i * 3);
    putch('A' + id);
    done[id]++;
    state += 3;
    yield();
  }
  assert(done[0] == ROUNDS && done[1] == ROUNDS);
  assert(switches == ROUNDS * 2 + 1);
  putstr("\nyield-os PASS\n");
  halt(0);
}
int main(void) {
  cte_init(schedule);
  for (int i = 0; i < 2; i++)
    pcb[i].cp = kcontext((Area){pcb[i].stack, &pcb[i] + 1}, task, (void *)(uintptr_t)i);
  yield();
  panic("boot context resumed");
}
