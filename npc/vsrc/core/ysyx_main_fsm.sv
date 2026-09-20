`default_nettype none

module ysyx_main_fsm (
    input clk, 
    input rst_n,
    
    output reg          imem_req_valid,
    input               imem_req_ready,

    input               imem_rsp_valid,
    output reg          imem_rsp_ready,

    input               lsu_access,
    output reg          lsu_req_valid,
    input               lsu_req_ready,
    input               lsu_rsp_valid,
    output reg          lsu_rsp_ready,

    output reg          commit_valid
);

localparam  IF_REQ   = 2'd0,
            IF_WAIT  = 2'd1,
            EXEC     = 2'd2,
            LSU_WAIT = 2'd3;

wire    [1:0] state;
reg     [1:0] next_state;


// current state register
ysyx_gnrl_dffr #(.DW(2)) ysyx_state_register (
    .dnxt   (next_state), 
    .qout   (state), 
    .clk    (clk), 
    .rst_n  (rst_n)
);

// next state & output logic
always @(*) begin
    next_state   = state;
    imem_req_valid = 0;
    imem_rsp_ready = 0;
    lsu_req_valid = 0;
    lsu_rsp_ready = 0;
    commit_valid = 0;
    if (!rst_n) begin
        next_state = IF_REQ;
    end else begin
        case (state)
            IF_REQ: begin
                imem_req_valid = 1;
                if (imem_req_ready) begin
                    next_state = IF_WAIT;
                end
            end
            IF_WAIT: begin
                imem_rsp_ready = 1;
                if (imem_rsp_valid) begin
                    next_state = EXEC;
                end
            end
            EXEC: begin
                if (lsu_access) begin
                    lsu_req_valid = 1;
                    if (lsu_req_ready) begin
                        next_state = LSU_WAIT;
                    end
                end else begin
                    commit_valid = 1;
                    next_state = IF_REQ;
                end
            end
            LSU_WAIT: begin
                lsu_rsp_ready = 1;
                if (lsu_rsp_valid) begin
                    commit_valid = 1;
                    next_state = IF_REQ;
                end
            end
            default: next_state = IF_REQ;
        endcase
    end
end

property p_memory_commit_requires_lsu_response;
    @(posedge clk) disable iff (!rst_n)
        commit_valid && lsu_access |-> lsu_rsp_valid;
endproperty
assert property (p_memory_commit_requires_lsu_response);

endmodule

`default_nettype wire
