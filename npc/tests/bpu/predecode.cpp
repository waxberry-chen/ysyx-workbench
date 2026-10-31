#include "Vysyx_predecode.h"
#include "verilated.h"
#include <stdexcept>
#include <iostream>
static unsigned branch(int offset,unsigned f,unsigned r1,unsigned r2) {
    unsigned u=unsigned(offset)&8191;
    return ((u>>12)<<31)|(((u>>5)&63)<<25)|(r2<<20)|(r1<<15)|(f<<12)|(((u>>1)&15)<<8)|(((u>>11)&1)<<7)|0x63;
}
static unsigned jal(int offset,unsigned rd) {
    unsigned u=unsigned(offset)&0x1fffff;
    return ((u>>20)<<31)|(((u>>1)&1023)<<21)|(((u>>11)&1)<<20)|(((u>>12)&255)<<12)|(rd<<7)|0x6f;
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    try {
        Vysyx_predecode d;unsigned tests=0;
        auto test=[&](unsigned ins,int offset,bool b,bool j){
            for(unsigned err=0;err<2;++err){
                d.pc=0x30000100;d.inst=ins;d.error=err;d.eval();++tests;
                if(d.is_branch!=(b&&!err)||d.is_jal!=(j&&!err)||
                   (!err&&(b||j)&&d.target!=uint32_t(d.pc+offset)))
                    throw std::runtime_error("PREDECODE: legality/target mismatch");
            }
        };
        for(unsigned f=0;f<8;++f)for(unsigned r1:{0u,15u,16u,31u})for(unsigned r2:{0u,15u,16u,31u})
            for(int offset:{-4096,-20,-2,0,2,4,4094})test(branch(offset,f,r1,r2),offset,f!=2&&f!=3&&r1<16&&r2<16,false);
        for(unsigned rd:{0u,15u,16u,31u})for(int offset:{-1048576,-16,-2,0,2,4,1048574})test(jal(offset,rd),offset,false,rd<16);
        for(unsigned ins:{0x13u,0x8067u,0xffffffffu,0x00000073u,0x30200073u})test(ins,0,false,false);
        std::cout<<"PREDECODE PASS cases="<<tests<<'\n';
    }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}
}
