# GShare comparison: identical scope/library/SDC/Ultra/cap90; only BPU mode differs.
source [file join [file dirname [info script]] npc_soc_cpu.tcl]
dict set cfg defines {SYNTHESIS NPC_FLASH_BOOT NPC_BPU_MODE=0}
