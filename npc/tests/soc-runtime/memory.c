#include <am.h>
#include <stdint.h>

static volatile uint32_t initialized[] = {0x01234567, 0x89abcdef, 0x87654321};
static volatile uint8_t zeros[31];
static volatile uint64_t wide = 0x8877665544332211ull;
static volatile uint64_t wide_bss;
extern char _stack_bottom, _stack_top;
static void check(int ok) { if (!ok) halt(1); }
__attribute__((noinline)) static uint32_t stack_test(unsigned n) {
  volatile uint32_t local[8];
  for (unsigned i=0;i<8;i++) local[i]=n+i;
  uint32_t sum = n ? stack_test(n-1) : 0;
  for (unsigned i=0;i<8;i++) { check(local[i]==n+i); sum+=local[i]; }
  return sum;
}
int main(const char *args) {
  (void)args;
  check(initialized[0]==0x01234567 && initialized[1]==0x89abcdef && initialized[2]==0x87654321);
  for (unsigned i=0;i<sizeof zeros;i++) check(zeros[i]==0);
  check(wide==0x8877665544332211ull && wide_bss==0);
  wide_bss=wide+0x100000001ull;
  check(wide_bss==0x8877665644332212ull);
  initialized[1]^=0xffffffff;
  check(initialized[1]==0x76543210);
  // Sweep the linker-defined heap only: globals and the active stack are live.
  volatile uint32_t *p=(volatile uint32_t *)heap.start;
  unsigned n=((uintptr_t)heap.end-(uintptr_t)heap.start)/4;
  check(n>64 && heap.end==&_stack_bottom && &_stack_bottom < &_stack_top);
  for (unsigned i=0;i<n;i++) p[i]=0x5a000000u^i;
  for (unsigned i=0;i<n;i++) check(p[i]==(0x5a000000u^i));
  p[0]=0x44332211;
  volatile uint8_t *b=(volatile uint8_t *)p;
  for (unsigned i=0;i<4;i++) b[i]=(uint8_t)(0x80+i);
  check(p[0]==0x83828180);
  volatile uint16_t *h=(volatile uint16_t *)p;
  h[0]=0xabcd; h[1]=0x9876;
  check(p[0]==0x9876abcd);
  check(*(volatile int8_t *)b==-51 && *(volatile int16_t *)h==-21555);
  check(stack_test(8)==540); // sum_{n=0..8}(8*n+28)
  putch('M'); putch('\n');
  return 0;
}
