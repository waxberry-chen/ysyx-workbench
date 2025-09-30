#include <am.h>
#include <nemu.h>
#include <klib.h>

#define KEYDOWN_MASK 0x8000

void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  int keycode_recieve = inl(KBD_ADDR);
  kbd->keydown = (keycode_recieve&KEYDOWN_MASK)?true:false;
  kbd->keycode = keycode_recieve&~KEYDOWN_MASK;
}
