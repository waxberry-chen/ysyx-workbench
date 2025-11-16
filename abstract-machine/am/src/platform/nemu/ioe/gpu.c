#include <am.h>
#include <nemu.h>
#include <klib.h>

#define SYNC_ADDR (VGACTL_ADDR + 4)

void __am_gpu_init() {
  int i;
  int w = inw(VGACTL_ADDR+2);
  //printf("W = %d\n", w);
  int h = inw(VGACTL_ADDR);
  //printf("H = %d\n", h);
  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
  for(i = 0; i < w*h; i++) fb[i] = 0;
  outl(SYNC_ADDR, 1);
}

void __am_gpu_config(AM_GPU_CONFIG_T *cfg) {
  *cfg = (AM_GPU_CONFIG_T) {
    .present = true, .has_accel = false,
    .width = inw(VGACTL_ADDR+2), .height = inw(VGACTL_ADDR),
    .vmemsz = 0
  };
}

void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  if(ctl->pixels != NULL) {
    int w=ctl->w, h=ctl->h, x=ctl->x, y=ctl->y;
    int screen_width = inw(VGACTL_ADDR+2);
    uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;
    for(int i=0; i<h; i++) {
      uint32_t *vmem_dst = fb + ((y+i)*screen_width + x);
      uint32_t *pixel_src = (uint32_t *)ctl->pixels+(i*w);
      memcpy(vmem_dst, pixel_src, w*sizeof(uint32_t));
    }
  }
  if (ctl->sync) {
    outl(SYNC_ADDR, 1);
  }
}

void __am_gpu_status(AM_GPU_STATUS_T *status) {
  status->ready = true;
}
