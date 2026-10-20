// S1 CPU regression responder. This is deliberately not the S2 SoC harness:
// sparse device semantics and fault injection are controlled by the test oracle.
#include "Vaxi4_cpu_test_top.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

static void check(bool yes, const char *why) { if (!yes) throw std::runtime_error(why); }
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    try {
        check(argc >= 3, "usage: cpu-test image trace [seed] [error-response]");
        std::vector<uint8_t> mem(1<<20);
        std::ifstream image(argv[1], std::ios::binary);
        check(bool(image), "image open"); image.read(reinterpret_cast<char*>(mem.data()), mem.size());
        check(image.eof(), "oversized image");
        std::ofstream trace(argv[2]); check(bool(trace), "trace open");
        std::mt19937 rng(argc>3 ? std::stoul(argv[3]) : 1);
        unsigned fault_resp = argc>4 ? std::stoul(argv[4]) : 3;
        Verilated::traceEverOn(argc>5);
        Vaxi4_cpu_test_top d;
        VerilatedFstC wave;
        if(argc>5) {d.trace(&wave,99);wave.open(argv[5]);}
        auto dump=[&]() {if(argc>5) wave.dump(Verilated::time());};
        bool ar=false,aw=false,w=false,reply=false,write=false;
        uint32_t addr=0,wd=0; unsigned size=0,strb=0,delay=0;
        uint64_t reads=0,writes=0,commits=0,device_reads=0,device_writes=0;
        uint64_t data_reads=0;
        d.clk=0;d.rst_n=0;d.m_axi_rvalid=d.m_axi_bvalid=0;
        d.m_axi_arready=d.m_axi_awready=d.m_axi_wready=0;
        d.m_axi_rid=d.m_axi_bid=0;d.m_axi_rlast=1;
        for(int i=0;i<20;++i) {d.clk=1;d.eval();dump();Verilated::timeInc(5);d.clk=0;d.eval();dump();Verilated::timeInc(5);}
        d.rst_n=1;
        for(uint64_t cycle=0;cycle<2000000;++cycle) {
            d.m_axi_arready=!ar&&!aw&&!w&&!reply && rng()%4!=0;
            d.m_axi_awready=!ar&&!aw&&!reply && rng()%4!=0;
            d.m_axi_wready=!ar&&!w&&!reply && rng()%4!=0;
            d.m_axi_rvalid=reply&&!write&&delay==0;
            d.m_axi_bvalid=reply&&write&&delay==0;
            d.clk=0;d.eval();
            if(d.commit_valid) {
                ++commits;
                trace<<std::dec<<cycle<<' '<<std::hex<<d.commit_pc<<' '<<d.commit_inst
                     <<" 0 0 "<<unsigned(d.commit_exception)<<' '<<d.commit_exception_cause
                     <<' '<<unsigned(d.commit_redirect_valid)<<' '<<unsigned(d.commit_redirect_reason)
                     <<' '<<unsigned(d.commit_mem_valid)<<' '<<unsigned(d.commit_mem_write)<<' '<<d.commit_mem_addr<<'\n';
                if(d.commit_inst==0x00100073) {
                    check(d.test_a0==0,"program ended with a0 != 0");
                    check(!d.commit_exception,"unexpected ebreak exception");
                    std::cout<<"HIT GOOD TRAP commits="<<commits<<" reads="<<reads<<" writes="<<writes
                             <<" data_reads="<<data_reads<<" device_reads="<<device_reads<<" device_writes="<<device_writes<<"\n";
                    if(argc>5) wave.close();
                    return 0;
                }
            }
            bool rf=d.m_axi_rvalid&&d.m_axi_rready,bf=d.m_axi_bvalid&&d.m_axi_bready;
            bool af=d.m_axi_arvalid&&d.m_axi_arready,awf=d.m_axi_awvalid&&d.m_axi_awready,wf=d.m_axi_wvalid&&d.m_axi_wready;
            if(af) {
                check(!aw&&!w&&!ar&&!reply,"multiple outstanding/overlap AR");
                check(d.m_axi_arid==0&&d.m_axi_arlen==0&&d.m_axi_arburst==1,"AR shape");
                ar=true;addr=d.m_axi_araddr;size=d.m_axi_arsize;write=false;++reads;
                if(!(d.m_axi_arprot&4)) ++data_reads;
            }
            if(awf) {
                check(!aw&&!ar&&!reply,"duplicate/overlap AW");
                check(d.m_axi_awid==0&&d.m_axi_awlen==0&&d.m_axi_awburst==1,"AW shape");
                aw=true;addr=d.m_axi_awaddr;size=d.m_axi_awsize;write=true;
            }
            if(wf) {check(!w&&!ar&&!reply&&d.m_axi_wlast,"duplicate/overlap W or missing LAST");w=true;wd=d.m_axi_wdata;strb=d.m_axi_wstrb;}
            if(!reply && (ar || (aw&&w))) {
                check(size<=2 && !(addr&((1u<<size)-1)),"invalid AXI size/alignment");
                bool ram=addr>=0x80000000 && uint64_t(addr)+(1u<<size)<=0x80100000;
                bool dev=addr>=0x10000000 && addr<0x10000008;
                unsigned response=(ram||dev)?0:fault_resp;
                uint32_t rd=0; unsigned lane=addr&3;
                if(dev) {check(size==0,"MMIO must remain narrow"); if(write)++device_writes;else{++device_reads;rd=(0xa0u+(addr&7))<<(8*lane);}}
                if(ram) {
                    unsigned base=(addr-0x80000000)&~3u;
                    if(write) {
                        unsigned mask=((1u<<(1u<<size))-1)<<lane;
                        check(strb==mask,"WSTRB/size/address disagree");
                        for(unsigned i=0;i<4;++i) if(strb&(1u<<i)) mem[base+i]=wd>>(8*i);
                    } else for(unsigned i=0;i<(1u<<size);++i) rd|=uint32_t(mem[base+lane+i])<<(8*(lane+i));
                }
                if(write) {++writes;d.m_axi_bresp=response;}
                else {d.m_axi_rdata=rd;d.m_axi_rresp=response;}
                reply=true;delay=1+rng()%8;
            }
            d.clk=1;d.eval();dump();Verilated::timeInc(5);
            d.clk=0;d.eval();dump();Verilated::timeInc(5);
            if(rf||bf) {ar=aw=w=reply=false;}
            else if(reply&&delay) --delay;
        }
        throw std::runtime_error("CPU watchdog expired");
    } catch(const std::exception &e) {std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}
