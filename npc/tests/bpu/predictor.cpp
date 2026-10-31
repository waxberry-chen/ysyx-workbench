#include "Vysyx_gshare.h"
#include "verilated.h"
#include <array>
#include <random>
#include <stdexcept>
#include <iostream>
#ifndef INDEX_BITS
#define INDEX_BITS 7
#endif
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);
    try {
        Vysyx_gshare d;
        constexpr unsigned Size=1u<<INDEX_BITS,Mask=Size-1;
        std::array<unsigned,Size> table;table.fill(1);
        std::mt19937 rng(71031);unsigned history=0,states=0;
        auto check=[&](){
            d.eval();unsigned index=((d.query_pc/4)^history)&Mask;
            if(d.query_index!=index || d.query_taken!=(table[index]>=2))
                throw std::runtime_error("BPU_MODEL: index/direction mismatch");
            states|=1u<<table[index];
        };
        d.clk=0;d.rst_n=0;d.train_valid=0;d.eval();d.clk=1;d.eval();
        d.clk=0;d.rst_n=1;
        for(unsigned cycle=0;cycle<20000;++cycle) {
            d.query_pc=0x30000000+4*(rng()%1024);
            d.train_index=cycle<32?0:rng()%Size;
            d.train_valid=cycle<32 || rng()%4!=0;
            d.train_taken=cycle<16 || (cycle>=32 && rng()%2);
            if(cycle>=32 && cycle<512) {
                // Explicit alternating directions, followed by two branches
                // whose outcomes are correlated in pairs (TT, NN, TT, NN).
                d.train_valid=1;
                d.train_taken=cycle<256 ? cycle%2 : (cycle/2)%2;
                d.query_pc=0x30000000+(cycle%2 ? 0x44 : 0x18);
                d.train_index=((d.query_pc/4)^history)&Mask;
            }
            // Periodically collide read and write; also train old saved indices.
            if(cycle%3==0)d.query_pc=4*(d.train_index^history);
            check(); // query BEFORE the edge must not see this training event
            d.clk=1;d.eval();
            if(d.train_valid) {
                auto &v=table[d.train_index];
                if(d.train_taken && v<3)++v;
                if(!d.train_taken && v>0)--v;
                history=(2*history+d.train_taken)&Mask;
            }
            check();d.clk=0;d.eval();
            if(cycle==10000){d.rst_n=0;d.eval();table.fill(1);history=0;check();d.rst_n=1;}
        }
        if(states!=15)throw std::runtime_error("counter state coverage");
        std::cout<<"BPU_MODEL PASS 20000 events INDEX_BITS="<<INDEX_BITS<<" states=0,1,2,3\n";
    }catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}
}
