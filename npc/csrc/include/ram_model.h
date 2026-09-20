#ifndef __RAM_MODEL_H__
#define __RAM_MODEL_H__

#include <stdint.h>

void init_ram_model(uint32_t seed, uint32_t max_latency,
                    uint32_t ready_percent);
void ram_model_drive();
void ram_model_sample();
void ram_model_tick();
void ram_model_report();

#endif
