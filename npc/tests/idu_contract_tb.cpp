// Independent instruction-mask oracle, deliberately separate from RTL predicates.
#include "Vysyx_idu.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>
struct Encoding { uint32_t mask, value; unsigned operands; }; // rd=1, rs1=2, rs2=4
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vysyx_idu dut;
    std::vector<Encoding> table;
    auto add = [&](uint32_t mask, uint32_t value, unsigned operands) {
        table.push_back({mask,value,operands});
    };
    for (uint32_t f=0; f<8; ++f) add(0xfe00707f, 0x33 | (f<<12), 7);
    add(0xfe00707f,0x40000033,7); add(0xfe00707f,0x40005033,7);
    for (uint32_t f : {0,2,3,4,6,7}) add(0x707f,0x13|(f<<12),3);
    for (uint32_t v : {0x1013,0x5013,0x40005013}) add(0xfe00707f,v,3);
    for (uint32_t f : {0,1,2,4,5}) add(0x707f,0x03|(f<<12),3);
    for (uint32_t f : {0,1,2}) add(0x707f,0x23|(f<<12),6);
    for (uint32_t f : {0,1,4,5,6,7}) add(0x707f,0x63|(f<<12),6);
    for (uint32_t v : {0x37,0x17,0x6f}) add(0x7f,v,1);
    add(0x707f,0x67,3); add(0x707f,0x0f,0);
    for (uint32_t v : {0x73,0x100073,0x30200073}) add(~0u,v,0);
    for (uint32_t addr : {0x300,0x305,0x341,0x342})
        for (uint32_t f : {1,2,3,5,6,7}) add(0xfff0707f,(addr<<20)|(f<<12)|0x73, f<4?3:1);
    uint64_t count=0;
    auto check = [&](uint32_t inst) {
        bool legal=false;
        for (auto e : table) if ((inst&e.mask)==e.value) {
            legal = (!(e.operands&1) || ((inst>>7)&31)<16) &&
                    (!(e.operands&2) || ((inst>>15)&31)<16) &&
                    (!(e.operands&4) || ((inst>>20)&31)<16);
            break;
        }
        dut.inst=inst; dut.eval(); ++count;
        bool trap=!legal || inst==0x73;
        bool csr=legal && (inst&0x7f)==0x73 && ((inst>>12)&3)!=0;
        bool write=csr && (((inst>>12)&3)==1 || ((inst>>15)&31)!=0);
        if (dut.trap_valid!=trap || (trap && dut.trap_cause!=(legal?11u:2u)) ||
            dut.csr_we!=write || (!legal && (dut.rf_we || dut.dm_we_raw || dut.dm_re_raw ||
                dut.br_en || dut.jal || dut.jalr || dut.mret_valid))) {
            std::fprintf(stderr,"decode mismatch %08x legal=%d cause=%u\n",inst,legal,dut.trap_cause);
            std::exit(1);
        }
    };
    // Complete opcode/funct3/funct7 space with valid operands.
    for (uint32_t op=0;op<128;++op) for (uint32_t f=0;f<8;++f)
        for (uint32_t hi=0;hi<128;++hi) check((hi<<25)|(7<<20)|(6<<15)|(f<<12)|(5<<7)|op);
    // Sweep each operand field for every legal encoding; immediate fields must not
    // be mistaken for registers, and both CSR zimm=0 and zimm=16..31 are legal.
    for (auto e:table) for (unsigned shift:{7,15,20}) for (uint32_t r=0;r<32;++r)
        check((e.value & ~(31u<<shift)) | (r<<shift));
    for (uint32_t addr=0;addr<4096;++addr) for (uint32_t f:{1,2,3,5,6,7})
        for (uint32_t rs:{0,1,15,16,31}) check((addr<<20)|(rs<<15)|(f<<12)|(5<<7)|0x73);
    uint32_t random=0x25e;
    for (unsigned n=0;n<100000;++n) { random^=random<<13;random^=random>>17;random^=random<<5;check(random); }
    std::printf("IDU contract: PASS (%llu independent checks)\n",(unsigned long long)count);
}
