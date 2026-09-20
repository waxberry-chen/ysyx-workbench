#include "ram_model.h"

#include <assert.h>
#include <inttypes.h>
#include <random>

#include "Vysyx_core.h"
#include "common.h"

extern Vysyx_core *dut;

#ifdef CONFIG_RAM
class InstructionRamModel {
 public:
  void init(uint32_t seed, uint32_t max_latency, uint32_t ready_percent) {
    assert(ready_percent >= 1 && ready_percent <= 100);
    seed_ = seed;
    max_latency_ = max_latency;
    ready_percent_ = ready_percent;
    reset();
    printf("RAM model: seed=%u, max_latency=%u, request_ready=%u%%\n",
           seed_, max_latency_, ready_percent_);
  }

  // Drive slave outputs while clk is low, before the active edge.
  void drive() {
    if (!dut->rstn) {
      dut->if_req_ready = 0;
      dut->if_rsp_valid = 0;
      dut->if_rsp_data = 0;
      return;
    }

    dut->if_req_ready =
        state_ == IDLE && (rng_() % 100u) < ready_percent_;
    dut->if_rsp_valid = state_ == RESP;
    dut->if_rsp_data = response_data_;
  }

  // Capture the settled handshake inputs before the active edge.  tick()
  // consumes this snapshot after the RTL sequential state has updated.
  void sample() {
    req_fire_ = dut->if_req_valid && dut->if_req_ready;
    rsp_fire_ = dut->if_rsp_valid && dut->if_rsp_ready;
    req_stalled_ = dut->if_req_valid && !dut->if_req_ready;
    rsp_stalled_ = dut->if_rsp_valid && !dut->if_rsp_ready;
    sampled_request_addr_ = dut->if_req_addr;
    sample_valid_ = true;
  }

  void tick() {
    assert(sample_valid_);
    sample_valid_ = false;

    if (!dut->rstn) {
      reset();
      return;
    }

    request_stall_cycles_ += req_stalled_;
    response_stall_cycles_ += rsp_stalled_;

    switch (state_) {
      case IDLE:
        if (req_fire_) {
          request_addr_ = sampled_request_addr_;
          latency_left_ = random_latency();
          request_count_++;
          if (latency_left_ == 0) {
            prepare_response();
            state_ = RESP;
          } else {
            state_ = WAIT;
          }
        }
        break;

      case WAIT:
        assert(!req_fire_ && !rsp_fire_);
        latency_left_--;
        if (latency_left_ == 0) {
          prepare_response();
          state_ = RESP;
        }
        break;

      case RESP:
        assert(!req_fire_);
        if (rsp_fire_) {
          response_count_++;
          state_ = IDLE;
        }
        break;
    }
  }

  void report() const {
    Log("RAM transactions: requests = %" PRIu64 ", responses = %" PRIu64
        ", request stall cycles = %" PRIu64
        ", response stall cycles = %" PRIu64,
        request_count_, response_count_, request_stall_cycles_,
        response_stall_cycles_);
  }

 private:
  enum State { IDLE, WAIT, RESP };

  void reset() {
    state_ = IDLE;
    request_addr_ = 0;
    response_data_ = 0;
    latency_left_ = 0;
    request_count_ = 0;
    response_count_ = 0;
    request_stall_cycles_ = 0;
    response_stall_cycles_ = 0;
    rng_.seed(seed_);
  }

  uint32_t random_latency() {
    const uint64_t range = (uint64_t)max_latency_ + 1;
    return (uint32_t)((uint64_t)rng_() % range);
  }

  void prepare_response() {
    // Access the backend exactly once per accepted request.  RESP may then be
    // held for an arbitrary number of cycles without repeating the read.
    pmem_read(true, request_addr_, 4, &response_data_);
  }

  State state_ = IDLE;
  uint32_t seed_ = 42;
  uint32_t max_latency_ = 3;
  uint32_t ready_percent_ = 75;
  paddr_t request_addr_ = 0;
  word_t response_data_ = 0;
  uint32_t latency_left_ = 0;
  uint64_t request_count_ = 0;
  uint64_t response_count_ = 0;
  uint64_t request_stall_cycles_ = 0;
  uint64_t response_stall_cycles_ = 0;
  std::mt19937 rng_;

  bool req_fire_ = false;
  bool rsp_fire_ = false;
  bool req_stalled_ = false;
  bool rsp_stalled_ = false;
  paddr_t sampled_request_addr_ = 0;
  bool sample_valid_ = false;
};

static InstructionRamModel ram_model;
#endif

void init_ram_model(uint32_t seed, uint32_t max_latency,
                    uint32_t ready_percent) {
#ifdef CONFIG_RAM
  ram_model.init(seed, max_latency, ready_percent);
#else
  (void)seed;
  (void)max_latency;
  (void)ready_percent;
#endif
}

void ram_model_drive() {
#ifdef CONFIG_RAM
  ram_model.drive();
#endif
}

void ram_model_sample() {
#ifdef CONFIG_RAM
  ram_model.sample();
#endif
}

void ram_model_tick() {
#ifdef CONFIG_RAM
  ram_model.tick();
#endif
}

void ram_model_report() {
#ifdef CONFIG_RAM
  ram_model.report();
#endif
}
