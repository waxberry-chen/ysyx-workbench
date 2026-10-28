#include <am.h>
#include <riscv/riscv.h>
#include <klib.h>

static Context* (*user_handler)(Event, Context*) = NULL;

Context* __am_irq_handle(Context *c) {
  if (user_handler) {
    Event ev = {0};
    switch (c->mcause) {
      // An interrupt suspends the next instruction. Unlike ECALL, its saved
      // PC must not advance: MRET must execute that instruction exactly once.
      case 0x80000007u: ev.event = EVENT_IRQ_TIMER; break;
      case 11: if((intptr_t)c->GPR1 == -1) {ev.event = EVENT_YIELD;} else {ev.event = EVENT_SYSCALL;}; c->mepc += 4; break;
      default: ev.event = EVENT_ERROR; break;
    }

    c = user_handler(ev, c);
    // Keep the minimal trap runtime usable in the 4 KiB MROM profile without
    // pulling the formatted-printing implementation into every CTE program.
    if (c == NULL) halt(1);
  }

  return c;
}

extern void __am_asm_trap(void);

bool cte_init(Context*(*handler)(Event, Context*)) {
  // initialize exception entry
  asm volatile("csrw mtvec, %0" : : "r"(__am_asm_trap));

  // register event handler
  user_handler = handler;

  return true;
}

Context *kcontext(Area kstack, void (*entry)(void *), void *arg) {
  uintptr_t stack_top = (uintptr_t) kstack.end & ~0xfu; // downward 16 byte alignment

  Context *context = (Context *)(stack_top - sizeof(Context));
  memset(context, 0, sizeof(Context));

  context->mepc = (uintptr_t)entry;
  context->gpr[10] = (uintptr_t)arg;  // a0 pass first param
  context->mstatus = 3u << 11;

  return context;
}

void yield() {
#ifdef __riscv_e
  asm volatile("li a5, -1; ecall");
#else
  asm volatile("li a7, -1; ecall");
#endif
}

bool ienabled() {
  uintptr_t status;
  asm volatile("csrr %0, mstatus" : "=r"(status));
  return (status & 8u) != 0;
}

void iset(bool enable) {
  if (enable) asm volatile("csrsi mstatus, 8" ::: "memory");
  else asm volatile("csrci mstatus, 8" ::: "memory");
}
