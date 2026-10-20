#include <am.h>
#include <klib-macros.h>

extern char _heap_start, _heap_end;
Area heap = RANGE(&_heap_start, &_heap_end);
static const char mainargs[MAINARGS_MAX_LEN] = MAINARGS_PLACEHOLDER;
int main(const char *);

// UART16550 byte registers, 100 MHz clock / (16 * divisor=1).
#define UART ((volatile uint8_t *)0x10000000)
void putch(char ch) {
  while (!(UART[5] & 0x20)) {}  // THRE: do not overwrite a busy holding register
  UART[0] = ch;
}
void halt(int code) {
  while (!(UART[5] & 0x40)) {}  // TEMT: include the final serial stop bit
  asm volatile("mv a0, %0; ebreak" : : "r"(code) : "a0");
  while (1) {}
}
void _trm_init(void) {
  UART[3] = 0x80;              // DLAB: offsets 0/1 select divisor latches
  UART[0] = 1;
  UART[1] = 0;
  UART[3] = 3;                 // 8N1, DLAB=0
  UART[1] = 0;                 // interrupts disabled until M5 S5
  halt(main(mainargs));
}
