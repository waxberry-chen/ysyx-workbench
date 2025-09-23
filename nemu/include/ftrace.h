#ifndef FTRACE_H
#define FTRACE_H

#include <stdio.h>
#include <stdlib.h>
#include <debug.h>
#include <elf.h>

typedef struct {
    char func_name[15]; 
    Elf32_Addr func_addr;
    Elf32_Word func_size;
} FuncInfo;

// NOT PUBLIC
// static char *read_elf_file(const char *file_name);
// static void parse_elf_file(char *elf_name);
void init_ftrace(const char *elf_file);
void ftrace_call(vaddr_t pc, vaddr_t dst);
void ftrace_ret(vaddr_t pc, vaddr_t dst);

#endif