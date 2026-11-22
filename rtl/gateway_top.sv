//Top level wiring for the exit gate slice
//Compute side writes into the bank; FSM notices; drain walker pulls it output; packet emits
module gateway_top #(
    parameter int BYTES  = 16384,
    parameter int AWIDTH = 256,
    parameter int BWIDTH = 128,
    parameter int OWIDTH = 64,
    parameter int BDEPTH = (BYTES*8)/BWIDTH,
    parameter int ADEPTH = (BYTES*8)/AWIDTH,
    parameter int BAW    = $clog2(BDEPTH),
    parameter int AAW    = $clog2(ADEPTH)
)(
    input logic     clk,
    input logic     rst_n,

    //compute-side write port, driven by the testbench (virtual camera)
    input  logic              a_en,
    input  logic [AAW-1:0]    a_addr,
    input  logic [AWIDTH-1:0] a_wdata,

    input logic     compute_done,       //"tile written, go
    input logic     consumer_ack,       //downstream took it
    input logic     mode,               //0->pass-through, 1->pack

    output logic [1:0] state,
    output logic [OWIDTH-1:0] drain_data,      //byte currently pulled out Port B
    output logic    drain_valid,
    output logic [BAW-1:0]    drain_count   //how many bytes drained so far
);

logic drain_req;
logic drain_done;
logic [BAW-1:0] b_addr;
logic [BWIDTH-1:0] b_rdata;
logic b_en;

sram_bank #(.BYTES(BYTES),
            .AWIDTH(AWIDTH),
            .BWIDTH(BWIDTH)
) u_bank (
    .clk(clk),
    .a_en(a_en),
    .a_addr(a_addr),
    .a_wdata(a_wdata),
    //Clean SDP(Simple Dual Port) Interface: No seperate write-enable or read port on A
    .b_en(b_en),
    .b_addr(b_addr),
    .b_rdata(b_rdata)
);

exit_fsm u_fsm (
    .clk(clk), .rst_n(rst_n),
    .compute_done(compute_done),
    .drain_done(drain_done),
    .consumer_ack(consumer_ack),
    .state(state),
    .drain_req(drain_req)
);

//Drain walker: issues port B reads while drain_req is high
//Advances only when a read actually goes out, so a stalled cycle
//never skips a word. last_q marks "final read issues, still in flight"
//bits into 64 bit words; this just proves the handshake works
logic [BAW-1:0] addr_q;
logic active_q;
logic last_q;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        addr_q <= '0;
        active_q <= 1'b0;
        last_q <= 1'b0;
    end else if (!drain_req) begin          //reset when FSM leaves DIRTY
        addr_q <= '0;
        active_q <= 1'b0;
        last_q <= 1'b0;
    end else begin
        if(!active_q && !last_q) begin
            active_q <= 1'b1;
            addr_q <= '0;
        end else if (b_en) begin
            if (addr_q == BAW'(BDEPTH-1)) begin
                active_q <= 1'b0;
                last_q <= 1'b1;
            end else begin
                addr_q <= addr_q + 1'b1;
            end
        end
    end
end

//Bit buffer skid-buffer Interface
logic       pk_in_ready;
logic       pk_in_valid;
logic [BWIDTH-1:0]      pk_in_data;
logic       pk_busy;
logic pend_q;                           //b_rdata holds valid unconsumed data

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) pend_q <= 1'b0;
    else if(!drain_req) pend_q <= 1'b0;
    else if(b_en) pend_q <= 1'b1;
    else if(pk_in_ready) pend_q <= 1'b0;
end

exit_packer #(.BWIDTH(BWIDTH), .OWIDTH(OWIDTH)) u_packer (
    .clk(clk), .rst_n(rst_n), .mode(mode),
    .in_valid(pk_in_valid),
    .in_data(pk_in_data),
    .in_ready(pk_in_ready),
    .out_valid(drain_valid),
    .out_data(drain_data),
    .busy(pk_busy)
);

assign b_en = active_q && (!pend_q || pk_in_ready);
assign pk_in_valid = pend_q;
assign pk_in_data = b_rdata;
assign b_addr = addr_q;
assign drain_count = addr_q;
assign drain_done = last_q && !pend_q && !pk_busy;

endmodule
