#ifndef NPC_DUT_H
#define NPC_DUT_H
#ifdef NPC_B1
#include "Vysyx_b1_top.h"
using NpcDut = Vysyx_b1_top;
#else
#include "Vysyx_core.h"
using NpcDut = Vysyx_core;
#endif
extern NpcDut *dut;
#endif
