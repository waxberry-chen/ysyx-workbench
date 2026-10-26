#include <am.h>
#include <stdint.h>
static void check(int ok) { if(!ok)halt(1); }
static uint8_t expected[64];
static void lanes(uintptr_t addr) {
  volatile uint32_t *w=(void *)addr;
  volatile uint8_t *b=(void *)addr;
  volatile uint16_t *h=(void *)addr;
  *w=0x44332211;
  check(b[0]==0x11 && b[1]==0x22 && b[2]==0x33 && b[3]==0x44);
  for(unsigned i=0;i<4;i++)b[i]=(uint8_t)(0x80+i);
  check(*w==0x83828180);
  h[0]=0xabcd; h[1]=0x9876; check(*w==0x9876abcd);
  check(*(volatile int8_t *)b==-51 && *(volatile int16_t *)h==-21555);
}
int main(void) {
  lanes(0x80000000); lanes(0x803ffffc);
  // Separated address bits must not alias; words and adjacent bytes survive.
  volatile uint32_t *p=(void *)0x80001000;
  for(unsigned i=0;i<256;i++)p[i]=0xa5a50000^i;
  for(unsigned i=0;i<256;i++)check(p[i]==(0xa5a50000^i));
  for(unsigned bit=12;bit<22;bit++)*(volatile uint32_t *)(0x80000000u+(1u<<bit))=bit;
  for(unsigned bit=12;bit<22;bit++)check(*(volatile uint32_t *)(0x80000000u+(1u<<bit))==bit);
  check(*(volatile uint32_t *)0x80000000==0x9876abcd);
  check(*(volatile uint32_t *)0x803ffffc==0x9876abcd);
  // Fixed-seed, independent byte-array oracle. Interleave byte/half/word
  // writes and check the containing word after each access.
  volatile uint8_t *b=(void *)0x80002000;
  for(unsigned i=0;i<64;i++)b[i]=0;
  uint32_t rng=0x51a4;
  for(unsigned i=0;i<300;i++) {
    rng^=rng<<13; rng^=rng>>17; rng^=rng<<5;
    unsigned size=1u<<(i%3),off=(rng>>16)&(64-size);
    if(size==1)b[off]=(uint8_t)rng;
    else if(size==2)*(volatile uint16_t *)(b+off)=(uint16_t)rng;
    else *(volatile uint32_t *)(b+off)=rng;
    for(unsigned j=0;j<size;j++)expected[off+j]=(uint8_t)(rng>>(8*j));
    unsigned aligned=off&~3u;
    uint32_t want=0;
    for(unsigned j=0;j<4;j++)want|=(uint32_t)expected[aligned+j]<<(8*j);
    check(*(volatile uint32_t *)(b+aligned)==want);
  }
  putch('P'); putch('\n'); return 0;
}
