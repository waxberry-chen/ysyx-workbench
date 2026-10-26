#include <am.h>
#include <stdint.h>
static volatile uint32_t initialized[]={0x12345678,0x89abcdef};
static volatile uint32_t zeros[17];
static void check(int ok) { if(!ok)halt(1); }
__attribute__((noinline)) static int stack_test(int depth) {
  volatile int saved=depth;
  int sum=depth?stack_test(depth-1):0;
  check(saved==depth);return sum+saved;
}
int main(void) {
  check(initialized[0]==0x12345678 && initialized[1]==0x89abcdef);
  for(unsigned i=0;i<17;i++)check(zeros[i]==0);
  zeros[16]=initialized[0];check(zeros[16]==0x12345678);
  check(stack_test(12)==78);
  check((uintptr_t)heap.end-(uintptr_t)heap.start>256);
  volatile uint32_t *lo=heap.start,*hi=(uint32_t *)heap.end-1;
  *lo=0x11223344;*hi=0x88776655;
  check(*lo==0x11223344 && *hi==0x88776655);
  putch('B'); putch('\n');return 0;
}
