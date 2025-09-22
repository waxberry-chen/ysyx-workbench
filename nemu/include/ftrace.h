#ifndef FTRACE_H
#define FTRACE_H

#include <stdio.h>
#include <stdlib.h>
#include <debug.h>
#include <elf.h>

typedef struct {
    char *func_name; 
    Elf32_Addr func_addr;
    Elf32_Word func_size;
} FuncInfo;

#endif