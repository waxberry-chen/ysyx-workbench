#include "Vaxi4lite_xbar_test_top.h"
#include "verilated.h"
#include <array>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
#include <random>
#include <stdexcept>
#include <string>

#ifndef TEST_SRAM_BYTES
#define TEST_SRAM_BYTES 0x100000u
#endif
struct Tx {
    bool write = false;
    uint32_t addr = 0, data = 0x87654321;
    int route = 0, prot = 1, strb = 15, resp = 0;
    int order = 0, out_order = 0, gap = 3, out_gap = 3;
    int stall = 0, latency = 0, hold = 0;
    long ar = -1, aw = -1, w = -1, dar = -1, daw = -1, dw = -1, rsp = -1, visible = -1;
    int overtakes = 0;
    std::string label;
    bool accepted() const { return ar >= 0 || aw >= 0 || w >= 0; }
    long complete() const { return write ? (daw >= 0 && dw >= 0 ? std::max(daw,dw) : -1) : dar; }
    uint32_t result() const { return (addr ^ 0x1234abcdU) + uint32_t(route * 71 + prot); }
};
struct Bench {
    Vaxi4lite_xbar_test_top d;
    std::deque<Tx> q[2];
    Tx* active = nullptr;
    long cycle = 0, accepted = 0, completed = 0, aborted = 0, effects = 0;
    bool real = false;
    std::map<std::string,long> bins;
    void check(bool ok, const std::string& msg) {
        if (!ok) throw std::runtime_error("cycle " + std::to_string(cycle) + ": " + msg);
    }
    void hit(const std::string& s) { ++bins[s]; }
    void tick() { d.clk=1; d.eval(); Verilated::timeInc(1); d.clk=0; d.eval(); Verilated::timeInc(1); ++cycle; }
    void clear_inputs() {
        d.s_axi_arvalid=d.s_axi_awvalid=d.s_axi_wvalid=0;
        d.s_axi_araddr=0xa00003f8; d.s_axi_awaddr=0xa0000048;
        d.s_axi_arprot=d.s_axi_awprot=7; d.s_axi_wdata=0xdeadbeef; d.s_axi_wstrb=0;
        d.s_axi_rready=d.s_axi_bready=0;
        for(int p=0;p<4;p++) {
            d.m_axi_arready[p]=d.m_axi_awready[p]=d.m_axi_wready[p]=0;
            // Unselected response noise must never leak upstream or be consumed.
            d.m_axi_rvalid[p]=d.m_axi_bvalid[p]=1;
            d.m_axi_rdata[p]=0xbad00000U+unsigned(p); d.m_axi_rresp[p]=d.m_axi_bresp[p]=2;
        }
    }
    void reset() {
        if(active) ++aborted;
        active=nullptr; q[0].clear(); q[1].clear(); clear_inputs();
        d.rst_n=0; d.real_decerr=real; d.eval();
        for(int i=0;i<2;i++) {
            check(!(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready||d.s_axi_rvalid||d.s_axi_bvalid),"reset upstream controls");
            for(int p=0;p<4;p++) check(!(d.m_axi_arvalid[p]||d.m_axi_awvalid[p]||d.m_axi_wvalid[p]||d.m_axi_rready[p]||d.m_axi_bready[p]),"reset downstream controls");
            tick();
        }
        d.rst_n=1; d.eval(); for(int i=0;i<3;i++) step();
        check(accepted==completed+aborted,"reset epoch accounting");
    }
    void push(Tx t) { q[t.write].push_back(t); }
    bool publish(const Tx& t, bool aw) {
        if(t.order==0 || (aw ? t.order<0 : t.order>0)) return true;
        long other=aw?t.w:t.aw;
        return other>=0 && cycle>other+t.gap;
    }
    bool down_ready(const Tx& t, bool aw) {
        long collected=std::max(t.aw,t.w);
        if(collected<0 || cycle<=collected+t.stall) return false;
        if(t.out_order==0 || (aw?t.out_order<0:t.out_order>0)) return true;
        long other=aw?t.dw:t.daw;
        return other>=0 && cycle>other+t.out_gap;
    }
    void step() {
        clear_inputs();
        if(!q[0].empty()) {
            Tx& t=q[0].front();
            d.s_axi_arvalid=t.ar<0;
            if(t.ar<0) { d.s_axi_araddr=t.addr; d.s_axi_arprot=t.prot; }
        }
        if(!q[1].empty()) {
            Tx& t=q[1].front();
            d.s_axi_awvalid=t.aw<0 && publish(t,true);
            d.s_axi_wvalid=t.w<0 && publish(t,false);
            if(t.aw<0) { d.s_axi_awaddr=t.addr; d.s_axi_awprot=t.prot; }
            if(t.w<0) { d.s_axi_wdata=t.data; d.s_axi_wstrb=t.strb; }
        }
        if(active) {
            Tx& t=*active; int p=t.route;
            d.m_axi_arready[p]=t.ar>=0 && cycle>t.ar+t.stall;
            d.m_axi_awready[p]=down_ready(t,true); d.m_axi_wready[p]=down_ready(t,false);
            bool available=t.complete()>=0 && cycle>t.complete()+t.latency && t.rsp<0;
            d.m_axi_rvalid[p]=!t.write && available;
            d.m_axi_bvalid[p]=t.write && available;
            d.m_axi_rdata[p]=t.result(); d.m_axi_rresp[p]=d.m_axi_bresp[p]=t.resp;
            d.s_axi_rready=!t.write && t.visible>=0 && cycle>=t.visible+t.hold;
            d.s_axi_bready=t.write && t.visible>=0 && cycle>=t.visible+t.hold;
        }
        d.eval();
        bool ua=d.s_axi_arvalid&&d.s_axi_arready, uw=d.s_axi_wvalid&&d.s_axi_wready, uaw=d.s_axi_awvalid&&d.s_axi_awready;
        check(!(ua&&(uw||uaw)),"read/write accepted simultaneously");
        if(ua||uw||uaw) {
            Tx* t=&q[ua?0:1].front();
            if(!active) { active=t; ++accepted; }
            check(active==t,"new transaction accepted while slot occupied");
            if(ua) { check(t->ar<0,"duplicate AR"); t->ar=cycle; }
            if(uaw) { check(t->aw<0,"duplicate AW"); t->aw=cycle; }
            if(uw) { check(t->w<0,"duplicate W"); t->w=cycle; }
        }
        for(int p=0;p<4;p++) {
            bool controls=d.m_axi_arvalid[p]||d.m_axi_awvalid[p]||d.m_axi_wvalid[p]||d.m_axi_rready[p]||d.m_axi_bready[p];
            if(!active || p!=active->route) { check(!controls,"wrong target activity"); continue; }
            Tx& t=*active;
            if(t.write && (t.aw<0||t.w<0)) check(!controls,"forward before both AW/W and target");
            if(d.m_axi_arvalid[p]) {
                check(!t.write&&t.ar>=0&&t.dar<0,"unexpected downstream AR");
                check(d.m_axi_araddr[p]==t.addr&&d.m_axi_arprot[p]==t.prot,"AR payload/unaligned address altered");
                if(d.tap_arready[p]) t.dar=cycle;
                else hit("stall/ar");
            }
            if(d.m_axi_awvalid[p]) {
                check(t.write&&t.aw>=0&&t.daw<0,"unexpected downstream AW");
                check(d.m_axi_awaddr[p]==t.addr&&d.m_axi_awprot[p]==t.prot,"AW payload altered");
                if(d.tap_awready[p]) t.daw=cycle;
                else hit("stall/aw");
            }
            if(d.m_axi_wvalid[p]) {
                check(t.write&&t.w>=0&&t.dw<0,"unexpected downstream W");
                check(d.m_axi_wdata[p]==t.data&&d.m_axi_wstrb[p]==t.strb,"W payload altered");
                if(d.tap_wready[p]) t.dw=cycle;
                else hit("stall/w");
            }
            if(t.write&&t.complete()==cycle&&t.resp==0&&!(real&&p==3)) ++effects;
            bool rf=d.m_axi_rready[p]&&d.tap_rvalid[p], bf=d.m_axi_bready[p]&&d.tap_bvalid[p];
            if(rf||bf) {
                check(t.complete()>=0&&t.complete()<cycle&&t.rsp<0,"premature/duplicate downstream response");
                check(bf==t.write,"response type"); t.rsp=cycle;
            }
        }
        bool rv=d.s_axi_rvalid, bv=d.s_axi_bvalid;
        check(!(rv&&bv),"two responses");
        bool done=false; int type=0;
        if(rv||bv) {
            check(active!=nullptr,"phantom upstream response"); Tx& t=*active;
            check(t.rsp>=0&&t.rsp<cycle&&bv==t.write,"premature/wrong upstream response");
            bool err=real&&t.route==3;
            check((bv?d.s_axi_bresp:d.s_axi_rresp)==(err?3:t.resp),"response code mismatch");
            if(rv) check(d.s_axi_rdata==(err?0:t.result()),"response data mismatch");
            if(t.visible<0) t.visible=cycle;
            done=bv?d.s_axi_bready:d.s_axi_rready; type=t.write;
            check(!(d.s_axi_arready||d.s_axi_awready||d.s_axi_wready),"slot released before response completion");
            if(!done) hit(bv?"stall/b":"stall/r");
            if(done) {
                ++completed;
                hit("route/"+std::to_string(t.route)+(t.write?"/w":"/r")+"/resp/"+std::to_string(err?3:t.resp));
                if(!t.label.empty()) hit(t.label);
                if(t.write) {
                    hit("strb/"+std::to_string(t.strb));
                    int in=(t.aw>t.w)-(t.aw<t.w),out=(t.daw>t.dw)-(t.daw<t.dw);
                    hit("order/"+std::to_string(t.route)+"/"+std::to_string(in)+"/"+std::to_string(out));
                }
                if(!q[!type].empty()) {
                    check(++q[!type].front().overtakes<=1,"type starvation"); hit("fairness/"+std::to_string(!type));
                }
            }
        }
        tick();
        if(done) { q[type].pop_front(); active=nullptr; }
    }
    void drain() {
        long limit=cycle+2000000;
        while(!q[0].empty()||!q[1].empty()) { check(cycle<limit,"watchdog"); step(); }
        for(int i=0;i<3;i++) step();
        check(accepted==completed+aborted,"drain accounting");
    }
    template<class F> void until(F pred) { for(int n=0;n<4096;n++) { if(pred()) return; step(); } check(false,"phase watchdog"); }
};
static uint32_t addr_for(int p) {
    const uint32_t a[]={0x80000000,0xa00003f8,0xa0000048,0x40000000}; return a[p];
}
static Tx transaction(int p,bool w) { Tx t; t.route=p; t.addr=addr_for(p); t.write=w; return t; }
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    try {
        Bench b; b.reset();
        // Boundary oracle is an explicit table independent of the DUT decoder.
        struct Boundary { uint32_t addr; int route; const char* name; };
        const Boundary boundaries[]={
            {0x7fffffff,3,"sram_before"},{0x80000000,0,"sram_first"},
            {0x80000000+TEST_SRAM_BYTES-4,0,"sram_last_word"},
            {0x80000000+TEST_SRAM_BYTES-1,0,"sram_last_byte"},
            {0x80000000+TEST_SRAM_BYTES,3,"sram_after"},
            {0xa00003f7,3,"uart_before"},{0xa00003f8,1,"uart_first"},{0xa00003fc,1,"uart_last_word"},
            {0xa00003ff,1,"uart_last_byte"},{0xa0000400,3,"uart_after"},
            {0xa0000047,3,"clint_before"},{0xa0000048,2,"clint_first"},{0xa000004c,2,"clint_last_word"},
            {0xa000004f,2,"clint_last_byte"},{0xa0000050,3,"clint_after"},
            {0,3,"zero"},{0xffffffff,3,"max"},{0x80100004,3,"no_alias"}};
        for(auto x:boundaries) for(int wr=0;wr<2;wr++) for(int prot:{1,5}) {
            Tx t=transaction(x.route,wr); t.addr=x.addr; t.prot=prot; t.order=1; t.stall=7; t.hold=7;
            t.label="boundary/"+std::string(x.name)+"/"+std::to_string(wr)+"/"+std::to_string(prot);
            b.push(t); b.drain();
        }
        for(int p=0;p<4;p++) {
            for(int in=-1;in<=1;in++) for(int out=-1;out<=1;out++) {
                Tx t=transaction(p,true); t.order=in; t.out_order=out; t.hold=7; b.push(t); b.drain();
            }
            for(int wr=0;wr<2;wr++) for(int resp:{0,2,3}) {
                Tx t=transaction(p,wr); t.resp=resp; t.stall=64; t.latency=64; t.hold=64; b.push(t); b.drain();
            }
        }
        for(int strb=0;strb<16;strb++) { Tx t=transaction(strb%4,true); t.strb=strb; b.push(t); b.drain(); }
        // Both types continuously offered. Reset gives read priority, then alternate.
        b.reset();
        for(int i=0;i<4;i++) { b.push(transaction(i,false)); b.push(transaction(3-i,true)); }
        b.until([&]{return b.active!=nullptr;}); b.check(!b.active->write,"reset read priority"); b.drain();
        // Reset each externally observable phase at every target; restart fresh traffic.
        const char* phases[]={"idle","reserved","ar_buffered","aw_only","w_only","both_buffered","down_aw_only","down_w_only","wait_r","wait_b","hold_r","hold_b"};
        for(int p=0;p<4;p++) for(int phase=0;phase<12;phase++) {
            b.reset();
            if(phase) {
                bool wr=phase==3||phase==4||phase==5||phase==6||phase==7||phase==9||phase==11;
                Tx t=transaction(p,wr); t.stall=3; t.hold=64; t.latency=64;
                if(phase==3) {t.order=-1;t.gap=64;}
                if(phase==4) {t.order=1;t.gap=64;}
                if(phase==6) {t.out_order=-1;t.out_gap=64;}
                if(phase==7) {t.out_order=1;t.out_gap=64;}
                b.push(t);
                b.until([&]{
                    if(phase==1) return bool(b.d.s_axi_arready);
                    if(!b.active) return false;
                    const Tx& a=*b.active;
                    switch(phase) {
                    case 2:return a.ar>=0&&a.dar<0;
                    case 3:return a.aw>=0&&a.w<0;
                    case 4:return a.w>=0&&a.aw<0;
                    case 5:return a.aw>=0&&a.w>=0&&a.daw<0&&a.dw<0;
                    case 6:return a.daw>=0&&a.dw<0;
                    case 7:return a.dw>=0&&a.daw<0;
                    case 8:case 9:return a.complete()>=0&&a.rsp<0;
                    case 10:case 11:return a.visible>=0;
                    default:return false;
                    }
                });
            }
            b.reset(); b.push(transaction(p,true)); b.push(transaction((p+1)%4,false)); b.drain();
            b.hit("reset/"+std::to_string(p)+"/"+phases[phase]);
        }
        for(unsigned seed=1;seed<=10;seed++) {
            b.reset(); std::mt19937 rng(seed); long before=b.completed;
            for(int i=0;i<1000;i++) {
                Tx t=transaction(rng()%4,rng()%2); t.addr+=rng()%4;
                t.data=rng();t.prot=rng()%8;t.strb=rng()%16;t.resp=std::array<int,3>{{0,2,3}}[rng()%3];
                t.order=int(rng()%3)-1;t.out_order=int(rng()%3)-1;t.gap=rng()%8;t.out_gap=rng()%8;
                t.stall=rng()%8;t.latency=rng()%8;t.hold=rng()%8; b.push(t);
            }
            b.drain(); b.check(b.completed-before==1000,"random count"); b.hit("seed/"+std::to_string(seed));
            std::cout<<"seed="<<seed<<" completed=1000 PASS\n";
        }
        // Actual Xbar + RTL DECERR connection, then mapped recovery.
        b.real=true;b.reset();
        for(int wr=0;wr<2;wr++) for(int order=-1;order<=1;order++) for(int strb=0;strb<16;strb++) {
            Tx t=transaction(3,wr);t.order=order;t.strb=strb;t.hold=64;t.prot=5;t.addr+=strb;
            b.push(t);b.drain(); b.push(transaction(0,!wr));b.drain();
        }
        for(int wr=0;wr<2;wr++) {
            b.push(transaction(3,wr));
            b.until([&]{return b.active&&b.active->rsp>=0;}); b.reset();
            b.push(transaction(3,wr));b.drain();b.hit("integrated/reset/"+std::to_string(wr));
        }
        for(int p=0;p<4;p++) for(int in=-1;in<=1;in++) for(int out=-1;out<=1;out++)
            b.check(b.bins["order/"+std::to_string(p)+"/"+std::to_string(in)+"/"+std::to_string(out)]>0,"missing ordering bin");
        for(int p=0;p<4;p++) for(auto phase:phases) b.check(b.bins["reset/"+std::to_string(p)+"/"+phase]>0,"missing reset bin");
        for(int p=0;p<4;p++) for(auto wr:{"/r","/w"}) for(int resp:{0,2,3})
            b.check(b.bins["route/"+std::to_string(p)+wr+"/resp/"+std::to_string(resp)]>0,"missing route/response bin");
        for(auto channel:{"ar","aw","w","r","b"}) b.check(b.bins["stall/"+std::string(channel)]>0,"missing channel stall");
        for(int s=0;s<16;s++) b.check(b.bins["strb/"+std::to_string(s)]>0,"missing strobe");
        for(int type=0;type<2;type++) b.check(b.bins["fairness/"+std::to_string(type)]>0,"missing contention");
        std::ofstream csv(argc>1?argv[1]:"coverage.csv"); csv<<"bin,hits\n";
        for(auto x:b.bins) csv<<x.first<<','<<x.second<<'\n';
        if(!csv) throw std::runtime_error("coverage output failed");
        std::cout<<"XBAR PASS accepted="<<b.accepted<<" completed="<<b.completed<<" aborted="<<b.aborted<<" effects="<<b.effects<<" bins="<<b.bins.size()<<" cycles="<<b.cycle<<'\n';
    } catch(const std::exception& e) {std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}
}
