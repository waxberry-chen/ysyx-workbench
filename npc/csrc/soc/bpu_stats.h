#pragma once
#include <array>
#include <cstdint>
#include <ostream>

// Recovery latency ends at the first post-redirect IFQ->opbuf transfer.
// A second redirect interrupts the sample. These intervals are not additive
// stall losses; report completed/interrupted/pending samples separately.
struct BpuStats {
    int mode=0;
    uint64_t cycle=0, branches=0, covered=0, wrong=0, npc_wrong=0;
    uint64_t requests=0, flushed=0, dropped=0, trained=0;
    uint64_t recoveries=0, latency=0, maximum=0, interrupted=0, start=0;
    bool waiting=false;
    std::array<uint64_t,8> redirects{};
    std::array<uint64_t,4> directions{}; // index=(prediction<<1)|actual
    void event(int m,int flags,int kind,int count) {
        mode=m; ++cycle;
        if(flags&1) {
            ++branches; covered+=bool(flags&2);
            unsigned p=bool(flags&4),a=bool(flags&8);
            ++directions[2*p+a];wrong+=p!=a;
        }
        npc_wrong+=bool(flags&16);requests+=bool(flags&32);
        dropped+=bool(flags&64);trained+=bool(flags&256);flushed+=count;
        if(kind) {
            ++redirects.at(kind);interrupted+=waiting;
            waiting=true;start=cycle;
        } else if(waiting && (flags&128)) {
            uint64_t delay=cycle-start;latency+=delay;
            if(delay>maximum)maximum=delay;
            ++recoveries;waiting=false;
        }
    }
    void json(std::ostream &f) const {
        f<<"{\"mode\":"<<mode<<",\"branches\":"<<branches
         <<",\"covered\":"<<covered<<",\"direction_wrong\":"<<wrong
         <<",\"npc_wrong\":"<<npc_wrong<<",\"trained\":"<<trained
         <<",\"fetch_requests\":"<<requests<<",\"flushed_entries\":"<<flushed
         <<",\"discarded_responses\":"<<dropped<<",\"directions\":[";
        for(unsigned i=0;i<4;++i){if(i)f<<',';f<<directions[i];}
        f<<"],\"redirects\":[";
        for(unsigned i=0;i<8;++i){if(i)f<<',';f<<redirects[i];}
        f<<"],\"recovery_completed\":"<<recoveries<<",\"recovery_cycles\":"<<latency
         <<",\"recovery_max\":"<<maximum<<",\"recovery_interrupted\":"<<interrupted
         <<",\"recovery_pending\":"<<int(waiting)<<'}';
    }
};
