#include <am.h>
#include <stdint.h>
static volatile uint32_t *const spi=(void *)0x10001000;
static void check(int ok) { if(!ok)halt(1); }
int main(void) {
  // command 03, 24-bit byte address, then receive 32 bits; MSB first.
  spi[5]=1; spi[6]=1; spi[1]=0x03012340; spi[0]=0;
  spi[4]=0x2540;
  while(spi[4]&0x100) {}
  check(spi[0]==0x12345678);
  volatile uint32_t *p=(void *)0x30012340;
  check(*p==0x78563412); // XIP converts serial byte order to RV32 little endian
  volatile uint8_t *b=(void *)p;
  check(b[0]==0x12 && b[1]==0x34 && b[2]==0x56 && b[3]==0x78);
  check(*(volatile uint16_t *)(b+2)==0x7856);
  check(*(volatile uint32_t *)0x30fffffc==0xffffffff);
  // Direct register access still works after an XIP transfer.
  spi[1]=0x03012344; spi[0]=0; spi[4]=0x2540;
  while(spi[4]&0x100) {}
  check(spi[0]==0x89abcdef);
  putch('F'); putch('\n');
  return 0;
}
