//Exit gate output stage. Two modes:
//MODE_PASS - dense data split each BWIDTH read into OWIDTH words
//MODE_PACK - symbol+length entries concatenate then emit
module exit_packer #(
    parameter int BWIDTH = 128,
    parameter int OWIDTH = 64
)(
    input logic     clk,
    input logic     rst_n,
    input logic     mode,           //0->pass, 1->pack
    input logic     in_valid,
    input logic [BWIDTH-1:0]    in_data,
    output logic    in_ready,
    output logic    out_valid,
    output logic [OWIDTH-1:0]   out_data,
    output logic    busy
);

logic [BWIDTH-1:0] buf_q;
logic       busy_q;
logic       half_q;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        buf_q <= '0;
        busy_q <= 1'b0;
        half_q <= 1'b0;
    end else begin
        if(in_valid && in_ready) begin
            buf_q <= in_data;
            busy_q <= 1'b1;
            half_q <= 1'b0;
        end else if(busy_q) begin
            if(half_q) busy_q <= 1'b0;
            else half_q <= 1'b1;
        end
    end
end

assign in_ready = !busy_q || half_q;
assign out_valid = busy_q;
assign out_data = half_q ? buf_q[BWIDTH-1:OWIDTH] : buf_q[OWIDTH-1:0];
assign busy = busy_q;

endmodule
