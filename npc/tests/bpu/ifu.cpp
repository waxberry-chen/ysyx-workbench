#include "Vysyx_ifu.h"
#include "verilated.h"
#include <array>
#include <deque>
#include <random>
#include <stdexcept>
#include <iostream>
struct Ctx {unsigned pc,inst,error,index,taken,npc,branch;};
static void need(bool yes,const char *s){if(!yes)throw std::runtime_error(s);}
int main(int argc,char **argv){
    Verilated::commandArgs(argc,argv);
    try {
        Vysyx_ifu d;std::mt19937 rng(88);std::deque<Ctx> queue;
        std::array<unsigned,128> pht;pht.fill(1);unsigned ghr=0;
        unsigned next=0x80000000,request=0,age=0,redirects=0,drops=0,accepted=0;
        unsigned same_edge=0,repeated=0,queue_flush=0,push_pop=0,unaligned=0;
        bool previous_redirect=false;
        bool pending=false,stale=false;unsigned instruction=0,error=0;
        d.clk=0;d.rst_n=0;d.redirect_valid=0;d.imem_req_ready=0;d.imem_rsp_valid=0;
        d.if_ctx_ready=0;d.bpu_train_valid=0;d.eval();d.clk=1;d.eval();d.clk=0;d.rst_n=1;
        for(unsigned cycle=0;cycle<30000;++cycle){
            d.imem_req_ready=rng()%4!=0;d.if_ctx_ready=rng()%3==0;
            d.redirect_valid=rng()%23==0;d.redirect_target=0x80000000+4*(rng()%256);
            d.imem_rsp_valid=pending&&age==0;d.imem_rsp_data=instruction;d.imem_rsp_error=error;
            d.bpu_train_valid=rng()%3==0;d.bpu_train_index=rng()%128;d.bpu_train_taken=rng()%2;
            d.eval();
            if(d.redirect_valid){
                same_edge+=bool(d.imem_rsp_valid&&d.imem_rsp_ready);
                repeated+=previous_redirect;queue_flush+=!queue.empty();
                queue.clear();next=d.redirect_target;stale=pending;++redirects;
            }
            previous_redirect=d.redirect_valid;
            bool popped=d.if_ctx_valid&&d.if_ctx_ready;
            if(d.if_ctx_valid){
                need(!queue.empty(),"IFU_SCOREBOARD: unexpected context");auto c=queue.front();
                need(d.if_ctx_pc==c.pc&&d.if_ctx_inst==c.inst&&d.if_ctx_error==c.error,"IFU_SCOREBOARD: payload ordering");
                unsigned index=d.if_ctx_pred_index;
                if(argc>1)index^=1; // test-only corrupt sampled metadata, not the DUT
                need(index==c.index&&d.if_ctx_pred_taken==c.taken&&d.if_ctx_pred_npc==c.npc&&d.if_ctx_pred_branch==c.branch,
                    "IFU_SCOREBOARD: prediction metadata mismatch");
                if(d.if_ctx_ready)queue.pop_front();
            }
            bool rf=d.imem_rsp_valid&&d.imem_rsp_ready;
            bool af=d.imem_req_valid&&d.imem_req_ready;
            if(rf){
                need(pending,"IFU_SCOREBOARD: response without request");
                if(stale)++drops;
                else {
                    // Include halfword-aligned B/J targets: NPC must stay PC+4.
                    bool b=(instruction&127)==0x63&&!error,j=(instruction&127)==0x6f&&!error;
                    bool aligned=instruction!=0x00000163 && instruction!=0x0020006f;
                    unsigned index=((request>>2)^ghr)&127,taken=aligned&&(j||(b&&pht[index]>=2));
                    next=taken?request+(j?unsigned(-8):16):request+4;
                    unaligned+=!aligned&&!error;push_pop+=popped;
                    queue.push_back({request,instruction,error,index,taken,next,unsigned(b)});
                }
                pending=stale=false;
            }
            if(af){need(!pending&&!d.redirect_valid,"IFU_SCOREBOARD: outstanding/redirect");
                need(d.imem_req_addr==next,"IFU_SCOREBOARD: next request PC");
                request=next;pending=true;age=rng()%8;++accepted;
                instruction=std::array<unsigned,5>{0x00000863,0xff9ff06f,0x00000013,0x00000163,0x0020006f}[rng()%5];error=rng()%17==0;
            }
            if(d.bpu_train_valid){auto&v=pht[d.bpu_train_index];if(d.bpu_train_taken&&v<3)++v;if(!d.bpu_train_taken&&v>0)--v;ghr=(ghr*2+d.bpu_train_taken)&127;}
            d.clk=1;d.eval();d.clk=0;d.eval();if(age)--age;
        }
        need(redirects>100&&drops>100&&accepted>1000,"IFU coverage insufficient");
        need(same_edge&&repeated&&queue_flush&&push_pop&&unaligned,"IFU corner coverage insufficient");
        std::cout<<"IFU_SCOREBOARD PASS cycles=30000 requests="<<accepted<<" redirects="<<redirects<<" drops="<<drops
                 <<" redirect_response="<<same_edge<<" repeated_redirect="<<repeated
                 <<" queue_flush="<<queue_flush<<" push_pop="<<push_pop<<" unaligned_target="<<unaligned<<'\n';
    }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}
}
