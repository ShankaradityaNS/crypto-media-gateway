//Token FSM for the async exit gate
//EMPTY - nothing to send
//DIRTY - compute side has written data, not yet drained
//READY - data drained and packed, available downstream

module exit_fsm (
    input logic     clk,
    input logic     rst_n,
    input logic     compute_done,       //compute side raises when frame/tile written
    input logic     drain_done,         //shifter raises when it has pulled everything
    input logic     consumer_ack,       //downstream took data

    output logic [1:0] state,
    output logic    drain_req           //tells shifter to star pulling
);
 typedef enum logic [1:0] {
    S_EMPTY = 2'b00,
    S_DIRTY = 2'b01,
    S_READY = 2'b10
 } state_e;

 state_e cur, nxt;

 //Sequential: state register
 always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cur <= S_EMPTY;
    else cur <= nxt;
end

//Combinational: next state logic
always_comb begin
    nxt = cur;
    case (cur)
        S_EMPTY: if (compute_done) nxt = S_DIRTY;
        S_DIRTY: if (drain_done) nxt = S_READY;
        S_READY: if (consumer_ack) nxt = S_EMPTY;
        default: nxt = S_EMPTY;
    endcase
end

assign drain_req = (cur == S_DIRTY);
assign state = cur;

endmodule
