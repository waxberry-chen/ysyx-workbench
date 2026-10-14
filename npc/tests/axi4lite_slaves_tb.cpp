#include "Vaxi4lite_slaves_test_top.h"
#include "Vaxi4lite_slaves_test_top___024root.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef TEST_SRAM_BYTES
#define TEST_SRAM_BYTES 1048576
#endif
struct Tx {
    bool write=false;
    uint32_t addr=0,data=0x76543210,expected_data=0;
    int prot=1,strb=15,order=0,gap=7,hold=0,expected_resp=0,overtakes=0;
    long ar=-1,aw=-1,w=-1,visible=-1;
    uint64_t sample_tick=0;
    std::string label;
};
struct Bench {
    Vaxi4lite_slaves_test_top d;
    std::vector<uint8_t> memory=std::vector<uint8_t>(TEST_SRAM_BYTES);
    std::deque<Tx> q[2];
    Tx *active=nullptr,last;
    int device=0;
    long cycle=0,accepted=0,completed=0,aborted=0,uart_events=0,sram_writes=0;
    uint64_t timer=0;
    std::map<std::string,long> bins;
    std::vector<uint8_t> output;
    void check(bool ok,const std::string& msg) {
        if(!ok) throw std::runtime_error("cycle="+std::to_string(cycle)+" device="+std::to_string(device)+": "+msg);
    }
    auto& dut_mem() { return d.rootp->axi4lite_slaves_test_top__DOT__sram__DOT__mem; }
    auto& dut_time() { return d.rootp->axi4lite_slaves_test_top__DOT__clint__DOT__mtime_q; }
    uint32_t word(unsigned offset) const {
        return uint32_t(memory[offset])|(uint32_t(memory[offset+1])<<8)|
               (uint32_t(memory[offset+2])<<16)|(uint32_t(memory[offset+3])<<24);
    }
    bool in_sram(uint32_t a) const { return a>=0x80000000u&&uint64_t(a)<0x80000000ull+TEST_SRAM_BYTES&&!(a&3); }
    int response(const Tx& t) const {
        if(device==0) return in_sram(t.addr)&&(!t.write||!(t.prot&4))?0:2;
        if(device==1) return t.write&&t.addr==0xa00003f8&&!(t.prot&4)&&(t.strb==0||t.strb==1)?0:2;
        return !t.write&&!(t.prot&4)&&(t.addr==0xa0000048||t.addr==0xa000004c)?0:2;
    }
    void tick() {
        d.clk=1;d.eval();Verilated::timeInc(1);
        if(d.rst_n) ++timer;else timer=0;
        check(dut_time()==timer,"mtime does not advance/reset modulo 2^64");
        d.clk=0;d.eval();Verilated::timeInc(1);++cycle;
    }
    void clear() {
        d.s_axi_arvalid=d.s_axi_awvalid=d.s_axi_wvalid=0;
        d.s_axi_araddr=0xdeaddead;d.s_axi_awaddr=0x80000000;
        d.s_axi_arprot=d.s_axi_awprot=7;d.s_axi_wdata=0xdeadbeef;d.s_axi_wstrb=0;
        d.s_axi_rready=d.s_axi_bready=0;
    }
    void check_memory() {
        for(unsigned i=0;i<TEST_SRAM_BYTES/4;i++)
            check(dut_mem()[i]==word(i*4),"memory mismatch/illegal side effect at byte "+std::to_string(i*4));
    }
    void reset(bool initialize=false) {
        if(active) ++aborted;
        active=nullptr;q[0].clear();q[1].clear();clear();d.select_slave=device;d.rst_n=0;d.eval();
        check(!(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready||d.s_axi_rvalid||d.s_axi_bvalid||d.tx_valid),"reset controls/events");
        tick();tick();
        if(initialize) {
            // Host preload only, while all bus participants are held in reset.
            for(unsigned i=0;i<TEST_SRAM_BYTES;i++) memory[i]=uint8_t((i*73u)^(i>>8)^0xa5);
            for(unsigned i=0;i<TEST_SRAM_BYTES/4;i++) dut_mem()[i]=word(i*4);
        }
        check_memory();d.rst_n=1;d.eval();
        for(int i=0;i<3;i++) step();
        check(accepted==completed+aborted,"reset epoch accounting");
    }
    void select(int p) {
        check(!active&&q[0].empty()&&q[1].empty(),"device switch while busy");
        device=p;d.select_slave=p;d.eval();
    }
    void preset_time(uint64_t value) {
        check(!active&&q[0].empty()&&q[1].empty(),"timer preset while busy");
        // Test-only shortcut, not an MMIO write or production timer input.
        dut_time()=value;timer=value;d.eval();
    }
    void push(Tx t) {t.expected_resp=response(t);q[t.write].push_back(t);}
    bool publish(const Tx& t,bool aw) {
        if(t.order==0||(aw?t.order<0:t.order>0)) return true;
        long other=aw?t.w:t.aw;return other>=0&&cycle>other+t.gap;
    }
    void step() {
        clear();
        if(!q[0].empty()) {
            Tx& t=q[0].front();d.s_axi_arvalid=t.ar<0;
            if(t.ar<0) {d.s_axi_araddr=t.addr;d.s_axi_arprot=t.prot;}
        }
        if(!q[1].empty()) {
            Tx& t=q[1].front();d.s_axi_awvalid=t.aw<0&&publish(t,true);d.s_axi_wvalid=t.w<0&&publish(t,false);
            if(t.aw<0) {d.s_axi_awaddr=t.addr;d.s_axi_awprot=t.prot;}
            if(t.w<0) {d.s_axi_wdata=t.data;d.s_axi_wstrb=t.strb;}
        }
        if(active&&active->visible>=0&&cycle>=active->visible+active->hold) {
            d.s_axi_rready=!active->write;d.s_axi_bready=active->write;
        }
        d.eval();
        bool ar=d.s_axi_arvalid&&d.s_axi_arready,aw=d.s_axi_awvalid&&d.s_axi_awready,w=d.s_axi_wvalid&&d.s_axi_wready;
        check(!(ar&&(aw||w)),"simultaneous read/write accepted");
        if(ar||aw||w) {
            Tx* t=&q[ar?0:1].front();
            if(!active) {active=t;++accepted;}
            check(t==active,"new request before prior response completed");
            if(ar) {
                check(t->ar<0,"duplicate AR");t->ar=cycle;t->sample_tick=timer;
                if(t->expected_resp) t->expected_data=0;
                else if(device==0) t->expected_data=word(t->addr-0x80000000u);
                else t->expected_data=t->addr==0xa0000048?uint32_t(timer):uint32_t(timer>>32);
            }
            if(aw) {check(t->aw<0,"duplicate AW");t->aw=cycle;}
            if(w) {check(t->w<0,"duplicate W");t->w=cycle;}
        }
        bool done=(d.s_axi_rvalid&&d.s_axi_rready)||(d.s_axi_bvalid&&d.s_axi_bready);
        int type=active?active->write:0;
        if(done) {
            check(active&&active->visible>=0,"phantom response");++completed;last=*active;
            Tx& t=*active;
            bins["response/"+std::to_string(device)+"/"+std::to_string(type)+"/"+std::to_string(t.expected_resp)]++;
            bins["hold/"+std::to_string(device)+"/"+std::to_string(type)+"/"+(t.hold==0?"none":t.hold<64?"short":"long")]++;
            if(t.write) {
                int order=(t.aw>t.w)-(t.aw<t.w);
                bins["order/"+std::to_string(device)+"/"+std::to_string(order)]++;
                bins["strb/"+std::to_string(device)+"/"+std::to_string(t.strb)]++;
            }
            if(!t.label.empty()) ++bins[t.label];
            if(!q[!type].empty()) {check(++q[!type].front().overtakes<=1,"RR starvation");++bins["contention/"+std::to_string(device)+"/"+std::to_string(!type)];}
        }
        tick();
        bool effect=false;
        check(!(d.s_axi_rvalid&&d.s_axi_bvalid),"dual response");
        if(d.s_axi_rvalid||d.s_axi_bvalid) {
            check(active!=nullptr,"response without accepted request");Tx& t=*active;
            check(bool(d.s_axi_bvalid)==t.write,"wrong response type");
            check((t.write?d.s_axi_bresp:d.s_axi_rresp)==t.expected_resp,"wrong response code");
            check(!(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready),"response does not block new request");
            if(!t.write) {
                check(t.ar>=0&&cycle>t.ar,"read before AR");check(d.s_axi_rdata==t.expected_data,"read data/sample mismatch");
            } else check(t.aw>=0&&t.w>=0&&cycle>std::max(t.aw,t.w)+1,"write response before execution edge");
            if(t.visible<0) {
                t.visible=cycle;
                if(t.write&&t.expected_resp==0) {
                    if(device==0) {
                        unsigned off=t.addr-0x80000000u;
                        for(int lane=0;lane<4;lane++) if(t.strb&(1<<lane)) memory[off+lane]=uint8_t(t.data>>(8*lane));
                        if(t.strb) ++sram_writes;
                        check(dut_mem()[off/4]==word(off),"byte-write mask mismatch");
                    } else if(device==1&&t.strb==1) effect=true;
                }
            }
        }
        check(bool(d.tx_valid)==effect,"UART missing/duplicate/illegal event");
        if(effect) {check(d.tx_data==uint8_t(active->data),"UART byte mismatch");++uart_events;output.push_back(d.tx_data);}
        if(done) {q[type].pop_front();active=nullptr;}
    }
    template<class F> void until(F pred) {for(int i=0;i<4096;i++){if(pred()) return;step();}check(false,"phase watchdog");}
    void drain() {
        long last_completed=completed,progress=cycle;
        while(!q[0].empty()||!q[1].empty()) {
            check(cycle-progress<4096,"transaction watchdog");step();
            if(completed!=last_completed){last_completed=completed;progress=cycle;}
        }
        for(int i=0;i<3;i++)step();
        check(accepted==completed+aborted,"drain epoch accounting");
    }
    Tx run(Tx t) {push(t);drain();return last;}
};
Tx tx(int p,bool write) {Tx t;t.write=write;t.addr=p==0?0x80000000:p==1?0xa00003f8:0xa0000048;t.strb=p==1?1:15;return t;}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    try {
        Bench b;b.reset(true);
        // SRAM full mask cross at first/last word, preserving adjacent bytes.
        for(int edge=0;edge<2;edge++) for(int mask=0;mask<16;mask++) {
            uint32_t addr=0x80000000u+(edge?TEST_SRAM_BYTES-4:0);
            Tx t=tx(0,true);t.addr=addr;t.strb=mask;t.order=mask%3-1;t.hold=64;t.data=0xfedcba98u^unsigned(mask);
            t.label="sram/mask_boundary/"+std::to_string(edge)+"/"+std::to_string(mask);b.run(t);
            t=tx(0,false);t.addr=addr;t.prot=5;b.run(t);
        }
        // Direct slave address protection, including unaligned and would-be aliases.
        for(int p=0;p<3;p++) {
            b.select(p);
            std::vector<uint32_t> addresses=p==0?std::vector<uint32_t>{0x7ffffffc,0x80000001,0x80000000u+TEST_SRAM_BYTES-1,0x80000000u+TEST_SRAM_BYTES,0x90000000,0xffffffff}:
                p==1?std::vector<uint32_t>{0xa00003f4,0xa00003f8,0xa00003f9,0xa00003fc,0xa0000400}:
                std::vector<uint32_t>{0xa0000044,0xa0000048,0xa0000049,0xa000004c,0xa0000050};
            for(uint32_t addr:addresses) for(int wr=0;wr<2;wr++) for(int prot=0;prot<8;prot++)
                for(int strb : wr?std::vector<int>{0,1,15}:std::vector<int>{15}) {
                Tx t=tx(p,wr);t.addr=addr;t.prot=prot;t.strb=strb;t.hold=7;t.order=1;
                t.label="address/"+std::to_string(p)+"/"+std::to_string(addr)+"/"+std::to_string(wr)+"/"+std::to_string(prot);b.run(t);
            }
            for(int strb=0;strb<16;strb++) for(int order=-1;order<=1;order++) for(int delay:{0,1,7,64,257}) {
                Tx t=tx(p,true);t.strb=strb;t.order=order;t.gap=delay;t.hold=delay;b.run(t);
                t=tx(p,false);t.hold=delay;b.run(t);
            }
            b.check_memory();
        }
        // Continuous UART output is an event stream, not a B-handshake side effect.
        b.select(1);auto before=b.output.size();
        std::string message="I-love-ysyx\n";
        for(unsigned char c:message) {Tx t=tx(1,true);t.data=c;t.hold=64;b.run(t);}
        b.check(std::string(b.output.begin()+before,b.output.end())==message,"UART stream mismatch");++b.bins["uart/exact_stream"];
        // Every device must serve both continuously offered types, starting with read after reset.
        for(int p=0;p<3;p++) {
            b.select(p);b.reset();
            for(int i=0;i<4;i++){b.push(tx(p,false));b.push(tx(p,true));}
            b.until([&]{return b.active!=nullptr;});b.check(!b.active->write,"reset read priority");b.drain();
        }
        const char* phases[]={"idle","reserved","aw_only","w_only","write_collected","write_effect","r_hold","b_hold"};
        for(int p=0;p<3;p++) for(int phase=0;phase<8;phase++) {
            b.select(p);b.reset();
            if(phase) {
                bool wr=phase!=1&&phase!=6;
                Tx t=tx(p,wr);t.hold=64;t.gap=64;
                if(p==0&&wr)t.data=~b.word(0); // distinguish aborted writes from retained contents
                if(phase==2)t.order=-1;
                if(phase==3)t.order=1;
                b.push(t);
                b.until([&]{
                    if(phase==1)return bool(b.d.s_axi_arready);
                    if(!b.active)return false;
                    const Tx& a=*b.active;
                    if(phase==2)return a.aw>=0&&a.w<0;
                    if(phase==3)return a.w>=0&&a.aw<0;
                    if(phase==4)return a.aw>=0&&a.w>=0&&a.visible<0;
                    if(phase==5||phase==6)return a.visible>=0;
                    return a.visible>=0&&b.cycle>=a.visible+7;
                });
            }
            b.reset();b.run(tx(p,true));b.run(tx(p,false));b.check_memory();
            ++b.bins["reset/"+std::to_string(p)+"/"+phases[phase]];
        }
        // Timer low-word rollover between separate software reads forces a retry.
        b.select(2);b.preset_time(0xfffffff8ull);int retries=0;
        for(int attempt=0;attempt<8;attempt++) {
            Tx h=tx(2,false);h.addr=0xa000004c;
            Tx high1=b.run(h),low=b.run(tx(2,false)),high2=b.run(h);
            if(high1.expected_data!=high2.expected_data){++retries;continue;}
            uint64_t value=(uint64_t(high1.expected_data)<<32)|low.expected_data;
            b.check(value==low.sample_tick,"high-low-high returns torn value");break;
        }
        b.check(retries>0&&retries<8,"rollover retry not exercised");b.bins["clint/high_low_high_retry"]+=retries;
        std::cout<<"CLINT high-low-high retries="<<retries<<" PASS\n";
        b.preset_time(UINT64_MAX-2);Tx t=tx(2,false);t.hold=64;b.run(t);
        b.check(b.timer<100,"64-bit rollover missing");++b.bins["clint/full_wrap"];
        b.reset();b.check(b.timer==3,"reset timer epoch");
        for(unsigned seed=1;seed<=10;seed++) {
            std::mt19937 rng(seed);
            for(int p=0;p<3;p++) {
                b.select(p);long before_count=b.completed;
                for(int i=0;i<1000;i++) {
                    Tx t=tx(p,rng()%2);t.data=rng();t.strb=rng()%16;t.prot=rng()%8;
                    t.order=int(rng()%3)-1;t.gap=rng()%8;t.hold=rng()%8;
                    if(p==0)t.addr=0x80000000u+4*(rng()%(TEST_SRAM_BYTES/4));
                    else t.addr+=(rng()%3)*4;
                    if(rng()%11==0)++t.addr;
                    b.push(t);
                }
                b.drain();b.check_memory();b.check(b.completed-before_count==1000,"random transaction count");
                ++b.bins["seed/"+std::to_string(seed)+"/"+std::to_string(p)];
            }
            std::cout<<"seed="<<seed<<" 3 slaves x 1000 completed PASS\n";
        }
        for(int p=0;p<3;p++) {
            for(int type=0;type<2;type++)
                b.check(b.bins["contention/"+std::to_string(p)+"/"+std::to_string(type)]>0,"contention hole");
            for(int s=0;s<16;s++)b.check(b.bins["strb/"+std::to_string(p)+"/"+std::to_string(s)]>0,"strobe hole");
            for(int o=-1;o<=1;o++)b.check(b.bins["order/"+std::to_string(p)+"/"+std::to_string(o)]>0,"order hole");
            for(auto phase:phases)b.check(b.bins["reset/"+std::to_string(p)+"/"+phase]>0,"reset hole");
            for(int w=0;w<2;w++)for(auto hold:{"none","short","long"})
                b.check(b.bins["hold/"+std::to_string(p)+"/"+std::to_string(w)+"/"+hold]>0,"hold hole");
        }
        for(int edge=0;edge<2;edge++)for(int mask=0;mask<16;mask++)
            b.check(b.bins["sram/mask_boundary/"+std::to_string(edge)+"/"+std::to_string(mask)]>0,"mask/boundary hole");
        b.check_memory();
        std::ofstream csv(argc>1?argv[1]:"coverage.csv");csv<<"bin,hits\n";
        for(auto entry:b.bins)csv<<entry.first<<','<<entry.second<<'\n';
        b.check(bool(csv),"CSV output");
        std::cout<<"SLAVES PASS accepted="<<b.accepted<<" completed="<<b.completed<<" aborted="<<b.aborted
                 <<" uart_events="<<b.uart_events<<" sram_write_effects="<<b.sram_writes
                 <<" bins="<<b.bins.size()<<" cycles="<<b.cycle<<'\n';
    } catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}
}
