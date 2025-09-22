#include <stdio.h>
#include <stdlib.h>
#include <debug.h>
#include <elf.h>

char *read_elf_file(const char *file_name) {
    // 1. Open file use fopen()
    FILE *fp = fopen(file_name, "rb");   // 'b' nowadays has no effect, but portable to non-UNIX environment. 
    if(fp == NULL) {
        panic("ERROR: read_elf_file open failed");
        return NULL;
    }
    // 2. Get file size use fseek() & ftell() - obtains the current value of the "file position indicator"
    fseek(fp, 0, SEEK_END);
    long file_size  = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    // 3. Allocate the memory (file_size + 1) bytes
    char *buffer = (char *)malloc(file_size + 1);
    if(buffer == NULL) {
        panic("ERROR: read_elf_file malloc failed");
        return NULL;
    }
    // 4. Read out using fread()
    size_t size_read = fread(buffer, 1, file_size, fp);
    if(size_read != file_size) {
        free(buffer);
        fclose(fp);
        panic("ERROR: fread size mismatch");
        return NULL;
    }
    // 5. Add tail
    buffer[file_size] = '\0';
    fclose(fp);
    return buffer;
}

void parse_elf_file(char *dst, char *elf_content) {
    // 1. Get elf header
    Elf32_Ehdr *header = (Elf32_Ehdr *)elf_content;
    // Check "MAGIC NUM", 0x7F (\177), 'E', 'L'. 'F'
    if(memcmp(header->e_ident, ELFMAG, SELFMAG) != 0) {
        panic("ERROR: Not a valid ELF file");
        return;
    }
    // 2. Get "Section Header Table" position
    Elf32_Shdr *section_headers = (Elf32_Shdr *)(elf_content + header->e_shoff);
    int section_num = header->e_shnum;

    // 3. Get "Section Header String Table" (.shstrtab)
    Elf32_Shdr *shstrtab_header = &section_headers[header->e_shstrndx];
    char *shstrtab = elf_content + shstrtab_header->sh_offset;

    // 4. Find symbol header & strtab header
    Elf32_Shdr *symtab_header = NULL;
    Elf32_Shdr *strtab_header = NULL;

    for(int i=0; i<section_num; i++) {
        char *section_name = section_headers[i].sh_name;
        if(strcmp(section_name, ".symtab") == 0) {
            symtab_header = &section_headers[i];
        } else if (strcmp(section_name, ".strtab") == 0) {
            strtab_header = &section_headers[i];
        }
    }
    // Check
    if((symtab_header == NULL) || (strtab_header == NULL)) {
        panic("ERROR: Find symtab_header & strtab_header failed");
        return;
    }
}

char *init_ftrace(const char *elf_file) {
    if(elf_file == NULL) {
        panic("ERROR: ftrace recieve null"); 
        return;
    }
    char *elf_buffer = read_elf_file(elf_file);
    if(elf_file == NULL) {
        panic("ERROR: read_elf_file open failed");
        return;
    }

    // parse_elf(elf_buffer);

    free(elf_buffer);   // free the same space but change name
}