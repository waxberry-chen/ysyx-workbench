// Independent pin-level driver/scoreboard for the M5 S1 arbiter.
// No DUT internal state is read. The slave responds to observed transactions;
// upstream completion must match the original descriptor, exactly once.
#ifdef TEST_ROUTER
#include "Vaxi4_fabric_test_top.h"
using Dut = Vaxi4_fabric_test_top;
#else
#include "Vysyx_axi4_arbiter.h"
using Dut = Vysyx_axi4_arbiter;
#endif
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

static std::string injected_fault;

struct Tx {
    unsigned owner = 0;
    bool write = false;
    uint32_t addr = 0, data = 0;
    unsigned size = 2, prot = 0, strb = 0, resp = 0;
    int order = 0; // -1 AW first, 0 together, +1 W first
    unsigned gap = 0, publish_delay = 0;
    std::array<unsigned, 3> delay{}; // downstream AR/AW/W READY delay
    unsigned response_delay = 0, response_hold = 0;
    int64_t start = -1, up_ar = -1, up_aw = -1, up_w = -1;
    int64_t down_ar = -1, down_aw = -1, down_w = -1, down_complete = -1;
    bool down_response = false;
    std::array<unsigned, 3> stalls{};
    unsigned rsp_stalls = 0, overtakes = 0;
    uint32_t read_data() const { return (addr ^ 0x5a39c6e1u) + (prot << 24); }
};

struct Held {
    bool stalled = false;
    uint64_t payload = 0;
};

class Bench {
public:
    Dut dut;
    std::array<std::deque<Tx>, 2> queue;
    Tx *active = nullptr;
    uint64_t cycle = 0, accepted = 0, completed = 0, aborted = 0, effects = 0;
    std::map<std::string, uint64_t> coverage;
    std::vector<unsigned> completion_order;
    std::map<std::string, Held> held;
    unsigned serial = 0;
    std::string context = "startup";

    void check(bool condition, const std::string &why) {
        if (!condition) throw std::runtime_error(context + " cycle " +
            std::to_string(cycle) + ": " + why);
    }
    Tx transaction(unsigned owner, bool write = false) {
        Tx t;
        t.owner = owner; t.write = write;
        t.addr = 0x80000000u + 4 * ++serial;
        t.data = 0xc37a4200u ^ (serial * 7919u);
        t.size = serial % 3; t.prot = serial % 8; // verify forwarding, not hard-coded IFU/LSU PROT
        t.strb = serial % 16;
        return t;
    }
    void zero_inputs() {
        dut.ifu_axi_arvalid = dut.ifu_axi_rready = 0;
        dut.lsu_axi_arvalid = dut.lsu_axi_awvalid = dut.lsu_axi_wvalid = 0;
        dut.lsu_axi_rready = dut.lsu_axi_bready = 0;
        dut.m_axi_arready = dut.m_axi_awready = dut.m_axi_wready = 0;
        dut.m_axi_rvalid = dut.m_axi_bvalid = 0;
        dut.ifu_axi_araddr = dut.lsu_axi_araddr = dut.lsu_axi_awaddr = 0;
        dut.ifu_axi_arprot = dut.lsu_axi_arprot = dut.lsu_axi_awprot = 0;
        dut.lsu_axi_wdata = dut.lsu_axi_wstrb = 0;
        dut.m_axi_rdata = dut.m_axi_rresp = dut.m_axi_bresp = 0;
        dut.m_axi_rid = injected_fault=="rid" ? 1:0;
        dut.m_axi_bid = injected_fault=="bid" ? 1:0; dut.m_axi_rlast = injected_fault!="rlast";
        dut.ifu_axi_arsize = dut.lsu_axi_arsize = dut.lsu_axi_awsize = 2;
    }
    void reset() {
        if (active) ++aborted;
        active = nullptr;
        for (auto &q : queue) q.clear();
        held.clear();
        zero_inputs();
        dut.clk = 0; dut.rst_n = 0; dut.eval();
        for (int i = 0; i < 2; ++i) {
            check(!(dut.ifu_axi_arready || dut.lsu_axi_arready ||
                dut.lsu_axi_awready || dut.lsu_axi_wready ||
                dut.ifu_axi_rvalid || dut.lsu_axi_rvalid || dut.lsu_axi_bvalid ||
                dut.m_axi_arvalid || dut.m_axi_awvalid || dut.m_axi_wvalid ||
                dut.m_axi_rready || dut.m_axi_bready), "reset must disable handshake controls");
            dut.clk = 1; Verilated::timeInc(1); dut.eval();
            dut.clk = 0; Verilated::timeInc(1); dut.eval(); ++cycle;
        }
        dut.rst_n = 1; dut.eval();
        // No master/slave may return an old epoch response. Empty cycles catch
        // stale DUT requests or buffered upstream responses after reset.
        step(); step();
        check(accepted == completed + aborted, "reset accounting");
    }
    void drive() {
        zero_inputs();
        for (unsigned owner = 0; owner < 2; ++owner) {
            if (queue[owner].empty()) continue;
            Tx &t = queue[owner].front();
            if (t.start < 0) t.start = int64_t(cycle) + t.publish_delay;
            bool publish = int64_t(cycle) >= t.start;
            bool ar = publish && !t.write && t.up_ar < 0;
            bool aw = publish && t.write && t.up_aw < 0 &&
                (t.order <= 0 || (t.up_w >= 0 && int64_t(cycle) >= t.up_w + t.gap));
            bool w = publish && t.write && t.up_w < 0 &&
                (t.order >= 0 || (t.up_aw >= 0 && int64_t(cycle) >= t.up_aw + t.gap));
            if (owner == 0) {
                dut.ifu_axi_arvalid = ar;
                dut.ifu_axi_araddr = t.up_ar < 0 ? t.addr : 0xdead0000;
                dut.ifu_axi_arsize = t.size;
                dut.ifu_axi_arprot = t.up_ar < 0 ? t.prot : 0;
                dut.ifu_axi_rready = t.rsp_stalls >= t.response_hold;
            } else {
                dut.lsu_axi_arvalid = ar;
                dut.lsu_axi_araddr = t.up_ar < 0 ? t.addr : 0xbeef0000;
                dut.lsu_axi_arsize = t.size;
                dut.lsu_axi_arprot = t.up_ar < 0 ? t.prot : 0;
                dut.lsu_axi_awvalid = aw; dut.lsu_axi_wvalid = w;
                dut.lsu_axi_awaddr = t.up_aw < 0 ? t.addr : 0xabad0000;
                dut.lsu_axi_awsize = t.size;
                dut.lsu_axi_awprot = t.up_aw < 0 ? t.prot : 0;
                dut.lsu_axi_wdata = t.up_w < 0 ? t.data : ~t.data;
                dut.lsu_axi_wstrb = t.up_w < 0 ? t.strb : (t.strb ^ 15);
                dut.lsu_axi_rready = !t.write && t.rsp_stalls >= t.response_hold;
                dut.lsu_axi_bready = t.write && t.rsp_stalls >= t.response_hold;
            }
        }
        if (active) {
            Tx &t = *active;
            dut.m_axi_arready = t.stalls[0] >= t.delay[0];
            dut.m_axi_awready = t.stalls[1] >= t.delay[1];
            dut.m_axi_wready = t.stalls[2] >= t.delay[2];
            bool reply = t.down_complete >= 0 && !t.down_response &&
                int64_t(cycle) > t.down_complete + t.response_delay;
            dut.m_axi_rvalid = reply && !t.write;
            dut.m_axi_bvalid = reply && t.write;
            dut.m_axi_rdata = t.read_data();
            dut.m_axi_rresp = dut.m_axi_bresp = t.resp;
        }
    }
    void holding(const std::string &name, bool valid, bool ready, uint64_t payload) {
        Held &h = held[name];
        if (h.stalled) check(valid && payload == h.payload, name + " VALID/payload changed under stall");
        h.stalled = valid && !ready; h.payload = payload;
    }
    void bin(const std::string &name, unsigned stalls) {
        ++coverage[name + "/" + (stalls == 0 ? "none" : stalls <= 7 ? "short" : stalls >= 64 ? "long" : "medium")];
    }
    Tx &accept(unsigned owner) {
        check(!queue[owner].empty(), "accepted request without descriptor");
        Tx *t = &queue[owner].front();
        if (active) check(active == t, "accepted a second owner/transaction before completion");
        else { active = t; ++accepted; }
        return *t;
    }
    void observe() {
        holding("AR",dut.m_axi_arvalid,dut.m_axi_arready,(uint64_t(dut.m_axi_araddr)<<3)|dut.m_axi_arprot);
        holding("AW",dut.m_axi_awvalid,dut.m_axi_awready,(uint64_t(dut.m_axi_awaddr)<<3)|dut.m_axi_awprot);
        holding("W",dut.m_axi_wvalid,dut.m_axi_wready,(uint64_t(dut.m_axi_wdata)<<4)|dut.m_axi_wstrb);
        holding("IFU_R",dut.ifu_axi_rvalid,dut.ifu_axi_rready,(uint64_t(dut.ifu_axi_rdata)<<2)|dut.ifu_axi_rresp);
        holding("LSU_R",dut.lsu_axi_rvalid,dut.lsu_axi_rready,(uint64_t(dut.lsu_axi_rdata)<<2)|dut.lsu_axi_rresp);
        holding("LSU_B",dut.lsu_axi_bvalid,dut.lsu_axi_bready,dut.lsu_axi_bresp);
        // Check the test drivers themselves, including upstream publication gaps.
        holding("in_IFU_AR",dut.ifu_axi_arvalid,dut.ifu_axi_arready,(uint64_t(dut.ifu_axi_araddr)<<3)|dut.ifu_axi_arprot);
        holding("in_LSU_AR",dut.lsu_axi_arvalid,dut.lsu_axi_arready,(uint64_t(dut.lsu_axi_araddr)<<3)|dut.lsu_axi_arprot);
        holding("in_AW",dut.lsu_axi_awvalid,dut.lsu_axi_awready,(uint64_t(dut.lsu_axi_awaddr)<<3)|dut.lsu_axi_awprot);
        holding("in_W",dut.lsu_axi_wvalid,dut.lsu_axi_wready,(uint64_t(dut.lsu_axi_wdata)<<4)|dut.lsu_axi_wstrb);
        holding("in_R",dut.m_axi_rvalid,dut.m_axi_rready,(uint64_t(dut.m_axi_rdata)<<2)|dut.m_axi_rresp);
        holding("in_B",dut.m_axi_bvalid,dut.m_axi_bready,dut.m_axi_bresp);

        if (dut.ifu_axi_arvalid && dut.ifu_axi_arready) {
            Tx &t=accept(0); check(t.up_ar<0 && !t.write,"duplicate IFU AR"); t.up_ar=cycle;
        }
        if (dut.lsu_axi_arvalid && dut.lsu_axi_arready) {
            Tx &t=accept(1); check(t.up_ar<0 && !t.write,"duplicate LSU AR"); t.up_ar=cycle;
        }
        if (dut.lsu_axi_awvalid && dut.lsu_axi_awready) {
            Tx &t=accept(1); check(t.up_aw<0 && t.write,"duplicate AW"); t.up_aw=cycle;
        }
        if (dut.lsu_axi_wvalid && dut.lsu_axi_wready) {
            Tx &t=accept(1); check(t.up_w<0 && t.write,"duplicate W"); t.up_w=cycle;
        }
        check(dut.m_axi_arid==0 && dut.m_axi_awid==0 && dut.m_axi_arlen==0 &&
            dut.m_axi_awlen==0 && dut.m_axi_arburst==1 && dut.m_axi_awburst==1 &&
            dut.m_axi_wlast, "single-beat AXI4 constants");
        bool down_any=dut.m_axi_arvalid || dut.m_axi_awvalid || dut.m_axi_wvalid;
        check(!down_any || active,"forwarded a request without an accepted upstream transaction");
        if (down_any) {
            Tx &t=*active;
            if (dut.m_axi_arvalid) {
                check(!t.write && t.up_ar>=0 && t.down_ar<0,"unexpected downstream AR");
                check(dut.m_axi_araddr==t.addr && dut.m_axi_arprot==t.prot && dut.m_axi_arsize==t.size,"AR payload mismatch");
                if (dut.m_axi_arready) { t.down_ar=cycle; bin("AR",t.stalls[0]); }
                else ++t.stalls[0];
            }
            if (dut.m_axi_awvalid || dut.m_axi_wvalid)
                check(t.write && t.up_aw>=0 && t.up_w>=0,"write forwarded before collecting independent AW/W");
            if (dut.m_axi_awvalid) {
                check(t.down_aw<0 && dut.m_axi_awaddr==t.addr && dut.m_axi_awprot==t.prot && dut.m_axi_awsize==t.size,"AW payload/duplicate");
                if (dut.m_axi_awready) { t.down_aw=cycle; bin("AW",t.stalls[1]); }
                else ++t.stalls[1];
            }
            if (dut.m_axi_wvalid) {
                check(t.down_w<0 && dut.m_axi_wdata==t.data && dut.m_axi_wstrb==t.strb,"W payload/duplicate");
                if (dut.m_axi_wready) { t.down_w=cycle; bin("W",t.stalls[2]); }
                else ++t.stalls[2];
            }
            if (t.down_complete<0 && (t.write ? t.down_aw>=0 && t.down_w>=0 : t.down_ar>=0)) {
                t.down_complete=cycle;
                if (t.write && t.resp==0) ++effects; // scripted slave effect, before B, exactly once
            }
        }
        if ((dut.m_axi_rvalid && dut.m_axi_rready) || (dut.m_axi_bvalid && dut.m_axi_bready)) {
            check(active && !active->down_response,"duplicate downstream response");
            active->down_response=true;
            bin(active->write ? "B_delay" : "R_delay", unsigned(int64_t(cycle)-active->down_complete-1));
        }
        unsigned outputs=dut.ifu_axi_rvalid+dut.lsu_axi_rvalid+dut.lsu_axi_bvalid;
        check(outputs<=1,"response delivered to multiple masters/channels");
        if (outputs) {
            check(active && active->down_response,"upstream response without downstream completion");
            Tx &t=*active;
            check(t.owner==0 ? dut.ifu_axi_rvalid : t.write ? dut.lsu_axi_bvalid : dut.lsu_axi_rvalid,
                  "response routed to wrong owner/type");
            unsigned resp=t.owner==0 ? dut.ifu_axi_rresp : t.write ? dut.lsu_axi_bresp : dut.lsu_axi_rresp;
            check(resp==t.resp,"response code not preserved");
            if (!t.write) check((t.owner==0 ? dut.ifu_axi_rdata : dut.lsu_axi_rdata)==t.read_data(),"RDATA mismatch");
            bool ready=t.owner==0 ? dut.ifu_axi_rready : t.write ? dut.lsu_axi_bready : dut.lsu_axi_rready;
            if (!ready) ++t.rsp_stalls;
            else {
                unsigned owner=t.owner, other=1-owner;
                bool waiting=other==0 ? bool(dut.ifu_axi_arvalid) : bool(dut.lsu_axi_arvalid || dut.lsu_axi_awvalid || dut.lsu_axi_wvalid);
                if (waiting) {
                    check(++queue[other].front().overtakes<=1,"pending master overtaken more than once");
                    ++coverage["fairness/winner_"+std::to_string(owner)];
                }
                std::string kind=owner==0 ? "IFU_R" : t.write ? "LSU_B" : "LSU_R";
                bin(kind,t.rsp_stalls);
                ++coverage["response/"+kind+"/"+std::to_string(t.resp)];
                if (t.write) {
                    int in=(t.up_aw<t.up_w)?-1:(t.up_aw>t.up_w)?1:0;
                    int out=(t.down_aw<t.down_w)?-1:(t.down_aw>t.down_w)?1:0;
                    ++coverage["ordering/"+std::to_string(in)+"/"+std::to_string(out)];
                    ++coverage["strobe/"+std::to_string(t.strb)];
                }
                completion_order.push_back(owner); ++completed;
                active=nullptr; queue[owner].pop_front();
            }
        }
    }
    void step() {
        drive(); dut.clk=0; dut.eval(); observe();
        dut.clk=1; Verilated::timeInc(1); dut.eval();
        dut.clk=0; Verilated::timeInc(1); dut.eval(); ++cycle;
    }
    void drain() {
        uint64_t last=completed, no_progress=0;
        while (!queue[0].empty() || !queue[1].empty()) {
            step();
            if (completed!=last) { last=completed; no_progress=0; }
            check(++no_progress<4096,"bounded driver watchdog");
        }
        for (int i=0;i<3;++i) step();
        check(!active && accepted==completed+aborted,"drained transaction accounting");
    }
    void one(Tx t) { queue[t.owner].push_back(t); drain(); }
    void directed() {
        context="directed"; reset();
        // Contention after reset, and after an IFU-only completion (LSU priority).
        for (bool prime : {false,true}) {
            reset(); if (prime) one(transaction(0));
            size_t base=completion_order.size();
            queue[0].push_back(transaction(0)); queue[1].push_back(transaction(1,true));
            drain();
            check(completion_order[base]==unsigned(prime),"round-robin initial winner");
            check(completion_order[base+1]==unsigned(!prime),"round-robin second winner");
        }
        // Full 3x3 ingress/egress write ordering, with a waiting IFU contender.
        for (int in=-1;in<=1;++in) for (int out=-1;out<=1;++out) {
            reset(); one(transaction(0)); // make LSU the next winner
            Tx w=transaction(1,true); w.order=in; w.gap=7;
            w.delay[1]=out==1?64:0; w.delay[2]=out==-1?64:0;
            w.response_hold=64;
            queue[0].push_back(transaction(0)); queue[1].push_back(w); drain();
        }
        for (unsigned delay : {0u,1u,7u,64u}) {
            for (unsigned kind=0;kind<3;++kind) for (unsigned resp : {0u,2u,3u}) {
                Tx t=transaction(kind?1:0,kind==2); t.resp=resp;
                t.delay={delay,delay,delay}; t.response_delay=delay; t.response_hold=delay;
                one(t);
            }
            for (int order : {-1,1}) {
                Tx w=transaction(1,true); w.order=order; w.gap=delay; one(w);
            }
        }
        for (unsigned s=0;s<16;++s) { Tx w=transaction(1,true); w.strb=s; one(w); }
        // Longer than the standard random stall bound, still a legal AXI wait.
        Tx t=transaction(0); t.delay[0]=257; t.response_hold=257; one(t);
        ++coverage["long_stall/257"];
        std::cout<<"T01-T04 directed scoreboard: PASS\n";
    }
    void reset_cases() {
        const std::vector<std::string> phases={"idle","reserved","ar_buffered","aw_only","w_only",
            "aw_w_buffered","down_aw_only","down_w_only","wait_r","wait_b","hold_ifu_r","hold_lsu_r","hold_b"};
        for (const auto &phase:phases) {
            context="reset/"+phase; reset();
            bool write=phase=="aw_only" || phase=="w_only" || phase=="aw_w_buffered" ||
                phase=="down_aw_only" || phase=="down_w_only" || phase=="wait_b" || phase=="hold_b";
            unsigned owner=write || phase=="hold_lsu_r" ? 1:0;
            if (phase!="idle") {
                Tx t=transaction(owner,write); t.response_hold=64; t.response_delay=64;
                if (phase=="aw_only") { t.order=-1; t.gap=64; }
                if (phase=="w_only") { t.order=1; t.gap=64; }
                if (phase=="down_aw_only") t.delay[2]=64;
                if (phase=="down_w_only") t.delay[1]=64;
                queue[owner].push_back(t);
                bool reached=false;
                for (unsigned i=0;i<1024 && !reached;++i) {
                    step(); Tx &x=queue[owner].front();
                    if (phase=="reserved") reached=!active;
                    else if (phase=="ar_buffered") reached=x.up_ar>=0 && x.down_ar<0;
                    else if (phase=="aw_only") reached=x.up_aw>=0 && x.up_w<0;
                    else if (phase=="w_only") reached=x.up_w>=0 && x.up_aw<0;
                    else if (phase=="aw_w_buffered") reached=x.up_aw>=0 && x.up_w>=0 && x.down_aw<0 && x.down_w<0;
                    else if (phase=="down_aw_only") reached=x.down_aw>=0 && x.down_w<0;
                    else if (phase=="down_w_only") reached=x.down_w>=0 && x.down_aw<0;
                    else if (phase=="wait_r" || phase=="wait_b") reached=x.down_complete>=0 && !x.down_response;
                    else reached=x.rsp_stalls>0;
                }
                check(reached,"reset phase not reached");
            }
            uint64_t old_effects=effects;
            reset(); check(effects==old_effects,"reset replayed slave effect");
            // Fresh successful write + reads exercise all ownership after reset.
            one(transaction(1,true)); one(transaction(0)); one(transaction(1));
            check(effects==old_effects+1,"post-reset write missing or duplicated");
            ++coverage["reset/"+phase];
        }
        std::cout<<"T08 reset epochs (13 phases): PASS\n";
    }
    void random(unsigned seed) {
        context="random seed "+std::to_string(seed); reset(); std::mt19937 rng(seed);
        uint64_t before=completed;
        for (unsigned i=0;i<1000;++i) {
            unsigned owner=i%2; Tx t=transaction(owner,owner && (rng()%2));
            t.addr=(rng() & 0x0ffffffcu) | 0x80000000u; // reserve CLINT for directed checks t.data=rng(); t.prot=rng()%8; t.strb=rng()%16;
            t.resp=std::array<unsigned,3>{0,2,3}[rng()%3];
            t.order=int(rng()%3)-1; t.gap=1+rng()%7; t.publish_delay=rng()%8;
            t.delay={unsigned(rng()%8),unsigned(rng()%8),unsigned(rng()%8)};
            t.response_delay=rng()%8; t.response_hold=rng()%8;
            queue[owner].push_back(t);
        }
        drain(); check(completed-before==1000,"random completion count");
        std::cout<<"Arbiter random seed "<<seed<<": 1000/1000 PASS\n";
    }
    void finish(const std::string &path) {
        for (const auto &channel:{"AR","AW","W","IFU_R","LSU_R","LSU_B","R_delay","B_delay"})
            for (const auto &bin:{"none","short","long"})
                check(coverage[std::string(channel)+"/"+bin]>0,"missing required stall coverage");
        for (int in=-1;in<=1;++in) for (int out=-1;out<=1;++out)
            check(coverage["ordering/"+std::to_string(in)+"/"+std::to_string(out)]>0,"missing ordering cross");
        for (unsigned s=0;s<16;++s) check(coverage["strobe/"+std::to_string(s)]>0,"missing WSTRB forwarding");
        for (const auto &kind:{"IFU_R","LSU_R","LSU_B"}) for (unsigned r:{0u,2u,3u})
            check(coverage[std::string("response/")+kind+"/"+std::to_string(r)]>0,"missing response cross");
        check(coverage["fairness/winner_0"] && coverage["fairness/winner_1"],"missing both contention winners");
        std::ofstream f(path); check(bool(f),"cannot create coverage CSV");
        f<<"bin,hits\n"; for (const auto &entry:coverage) f<<entry.first<<","<<entry.second<<"\n";
        f.close(); check(bool(f),"coverage write failed");
        std::cout<<"accepted="<<accepted<<" completed="<<completed<<" reset_aborted="<<aborted
                 <<" slave_write_effects="<<effects<<" coverage_bins="<<coverage.size()<<"\n";
        std::cout<<"M5 S1 transaction scoreboard: PASS\n";
    }
};

int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);
    try {
        if(argc>2) injected_fault=argv[2];
        Bench b; b.directed(); b.reset_cases();
        for (unsigned seed=1;seed<=10;++seed) b.random(seed);
        b.finish(argc>1?argv[1]:"arbiter-coverage.csv"); b.dut.final();
    } catch (const std::exception &e) {
        std::cerr<<"FAIL: "<<e.what()<<"\n"; return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
