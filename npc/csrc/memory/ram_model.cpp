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
    printf("I-RAM model: seed=%u, max_latency=%u, request_ready=%u%%\n",
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
    Log("I-RAM transactions: requests = %" PRIu64 ", responses = %" PRIu64
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

class DataRamModel {
 public:
  void init(uint32_t seed, uint32_t max_latency, uint32_t ready_percent) {
    assert(ready_percent >= 1 && ready_percent <= 100);
    seed_ = seed;
    max_latency_ = max_latency;
    ready_percent_ = ready_percent;
    reset();
    printf("D-RAM model: seed=%u, max_latency=%u, request_ready=%u%%\n",
           seed_, max_latency_, ready_percent_);
  }

  void drive() {
    if (!dut->rstn) {
      dut->d_req_ready = 0;
      dut->d_rsp_valid = 0;
      dut->d_rsp_data = 0;
      return;
    }

    dut->d_req_ready =
        state_ == IDLE && (rng_() % 100u) < ready_percent_;
    dut->d_rsp_valid = state_ == RESP;
    dut->d_rsp_data = response_data_;
  }

  void sample() {
    req_fire_ = dut->d_req_valid && dut->d_req_ready;
    rsp_fire_ = dut->d_rsp_valid && dut->d_rsp_ready;
    req_stalled_ = dut->d_req_valid && !dut->d_req_ready;
    rsp_stalled_ = dut->d_rsp_valid && !dut->d_rsp_ready;

    if (dut->rstn && previous_request_stalled_) {
      assert(dut->d_req_valid);
      assert(dut->d_req_write == stalled_request_write_);
      assert(dut->d_req_addr == stalled_request_addr_);
      assert(dut->d_req_size == stalled_request_size_);
      assert(dut->d_req_wdata == stalled_request_wdata_);
    }

    sampled_request_write_ = dut->d_req_write;
    sampled_request_addr_ = dut->d_req_addr;
    sampled_request_size_ = dut->d_req_size;
    sampled_request_wdata_ = dut->d_req_wdata;

    previous_request_stalled_ = req_stalled_;
    if (req_stalled_) {
      stalled_request_write_ = sampled_request_write_;
      stalled_request_addr_ = sampled_request_addr_;
      stalled_request_size_ = sampled_request_size_;
      stalled_request_wdata_ = sampled_request_wdata_;
    }
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
        assert(!rsp_fire_);
        if (req_fire_) {
          request_write_ = sampled_request_write_;
          request_addr_ = sampled_request_addr_;
          request_size_ = sampled_request_size_;
          request_wdata_ = sampled_request_wdata_;
          assert(request_size_ <= 2);
          latency_left_ = random_latency();
          request_count_++;
          if (request_write_) {
            store_count_++;
          } else {
            load_count_++;
          }
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
          assert(response_count_ <= request_count_);
          state_ = IDLE;
        }
        break;
    }
  }

  void report() const {
    Log("D-RAM transactions: requests = %" PRIu64
        " (loads = %" PRIu64 ", stores = %" PRIu64 ")"
        ", responses = %" PRIu64
        ", request stall cycles = %" PRIu64
        ", response stall cycles = %" PRIu64,
        request_count_, load_count_, store_count_, response_count_,
        request_stall_cycles_, response_stall_cycles_);
  }

 private:
  enum State { IDLE, WAIT, RESP };

  void reset() {
    state_ = IDLE;
    response_data_ = 0;
    latency_left_ = 0;
    request_count_ = 0;
    response_count_ = 0;
    load_count_ = 0;
    store_count_ = 0;
    request_stall_cycles_ = 0;
    response_stall_cycles_ = 0;
    previous_request_stalled_ = false;
    rng_.seed(seed_);
  }

  uint32_t random_latency() {
    const uint64_t range = (uint64_t)max_latency_ + 1;
    return (uint32_t)((uint64_t)rng_() % range);
  }

  void prepare_response() {
    const uint32_t size_bytes = 1u << request_size_;
    if (request_write_) {
      paddr_write(request_addr_, size_bytes, request_wdata_);
      response_data_ = 0;
    } else {
      response_data_ = paddr_read(request_addr_, size_bytes);
    }
  }

  State state_ = IDLE;
  uint32_t seed_ = 0;
  uint32_t max_latency_ = 3;
  uint32_t ready_percent_ = 75;
  bool request_write_ = false;
  paddr_t request_addr_ = 0;
  uint32_t request_size_ = 0;
  word_t request_wdata_ = 0;
  word_t response_data_ = 0;
  uint32_t latency_left_ = 0;
  uint64_t request_count_ = 0;
  uint64_t response_count_ = 0;
  uint64_t load_count_ = 0;
  uint64_t store_count_ = 0;
  uint64_t request_stall_cycles_ = 0;
  uint64_t response_stall_cycles_ = 0;
  std::mt19937 rng_;

  bool req_fire_ = false;
  bool rsp_fire_ = false;
  bool req_stalled_ = false;
  bool rsp_stalled_ = false;
  bool sampled_request_write_ = false;
  paddr_t sampled_request_addr_ = 0;
  uint32_t sampled_request_size_ = 0;
  word_t sampled_request_wdata_ = 0;
  bool previous_request_stalled_ = false;
  bool stalled_request_write_ = false;
  paddr_t stalled_request_addr_ = 0;
  uint32_t stalled_request_size_ = 0;
  word_t stalled_request_wdata_ = 0;
  bool sample_valid_ = false;
};

static InstructionRamModel instruction_ram_model;
static DataRamModel data_ram_model;
#endif

void init_ram_model(uint32_t seed, uint32_t max_latency,
                    uint32_t ready_percent) {
#ifdef CONFIG_RAM
  instruction_ram_model.init(seed, max_latency, ready_percent);
  data_ram_model.init(seed ^ UINT32_C(0x9e3779b9), max_latency,
                      ready_percent);
#else
  (void)seed;
  (void)max_latency;
  (void)ready_percent;
#endif
}

void ram_model_drive() {
#ifdef CONFIG_RAM
  instruction_ram_model.drive();
  data_ram_model.drive();
#endif
}

void ram_model_sample() {
#ifdef CONFIG_RAM
  instruction_ram_model.sample();
  data_ram_model.sample();
#endif
}

void ram_model_tick() {
#ifdef CONFIG_RAM
  instruction_ram_model.tick();
  data_ram_model.tick();
#endif
}

void ram_model_report() {
#ifdef CONFIG_RAM
  instruction_ram_model.report();
  data_ram_model.report();
#endif
}
