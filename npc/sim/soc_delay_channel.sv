// Simulation-only one-entry channel. Delay acceptance and presentation
// independently; once VALID is presented it and the payload stay stable.
// No clock gating, fabricated responses, or changes to the CPU's CLINT clock.
module npc_soc_delay_channel #(parameter WIDTH=32, parameter CHANNEL=0) (
    input clock, reset,
    input s_valid, output s_ready, input [WIDTH-1:0] s_data,
    output m_valid, input m_ready, output [WIDTH-1:0] m_data
);
    typedef enum logic [1:0] {IDLE, ACCEPT, WAIT, OUTPUT} state_t;
    state_t state;
    reg [WIDTH-1:0] data_q;
    int unsigned seed, maximum, fixed_delay, rng, remaining;
    int unsigned accepted, delivered, input_waits, output_waits;
    function automatic int unsigned next_random(input int unsigned x);
        x=x^(x<<13); x=x^(x>>17); return x^(x<<5);
    endfunction
    initial begin
        seed=1; maximum=7; fixed_delay=0;
        void'($value$plusargs("npc_delay_seed=%d",seed));
        void'($value$plusargs("npc_delay_max=%d",maximum));
        void'($value$plusargs("npc_delay_fixed=%d",fixed_delay));
        assert(seed>0 && maximum<=64 && fixed_delay<=1) else $fatal(1,"Invalid delay configuration");
    end
    assign s_ready=!reset && state==ACCEPT && remaining==0;
    assign m_valid=!reset && state==OUTPUT;
    assign m_data=data_q;
    always @(posedge clock) begin
        if(reset) begin
            state<=IDLE;data_q<=0;remaining<=0;
            rng<=seed^(32'h9e3779b9*(CHANNEL+1));
            accepted<=0;delivered<=0;input_waits<=0;output_waits<=0;
        end else case(state)
            IDLE: if(s_valid) begin
                remaining<=fixed_delay!=0?maximum:rng%(maximum+1);
                rng<=next_random(rng);state<=ACCEPT;
            end
            ACCEPT: if(remaining!=0) begin
                remaining<=remaining-1;input_waits<=input_waits+1;
            end else if(s_valid) begin
                data_q<=s_data;accepted<=accepted+1;
                remaining<=fixed_delay!=0?maximum:rng%(maximum+1);
                rng<=next_random(rng);state<=WAIT;
            end
            WAIT: if(remaining!=0) begin
                remaining<=remaining-1;output_waits<=output_waits+1;
            end else state<=OUTPUT;
            OUTPUT: if(m_ready) begin delivered<=delivered+1;state<=IDLE;end
            default: state<=IDLE;
        endcase
    end
    assert property (@(posedge clock) disable iff(reset)
        s_valid && !s_ready |=> s_valid && $stable(s_data));
    assert property (@(posedge clock) disable iff(reset)
        m_valid && !m_ready |=> m_valid && $stable(m_data));
    assert property (@(posedge clock) disable iff(reset)
        delivered<=accepted && accepted-delivered<=1);
    final $display("NPC_DELAY channel=%0d accepted=%0d delivered=%0d input_waits=%0d output_waits=%0d seed=%0d max=%0d fixed=%0d",
        CHANNEL,accepted,delivered,input_waits,output_waits,seed,maximum,fixed_delay);
endmodule
