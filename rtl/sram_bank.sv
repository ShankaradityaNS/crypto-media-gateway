//16KB dual port SRAM bank model - SDP bank with asymmeytric port widths
//Port A: compute side, write only AWIDTH bits
//Port B: exit gate side, read only BWIDTH bits
//Storage is held at BWIDTH; a wide write fills RATIO consecutive entires
module sram_bank #(
    parameter int BYTES = 16384,    //16KB
    parameter int AWIDTH = 256,
    parameter int BWIDTH = 128,
    parameter int BDEPTH = (BYTES*8)/BWIDTH,
    parameter int ADEPTH = (BYTES*8)/AWIDTH,
    parameter int RATIO = AWIDTH/BWIDTH,
    parameter int BAW    = $clog2(BDEPTH),
    parameter int AAW    = $clog2(ADEPTH),
    parameter int RAW    = $clog2(RATIO)
)(
    input logic     clk,

    //Port A compute side(write)
    input logic                 a_en,
    input logic [AAW-1:0]       a_addr,
    input logic [AWIDTH-1:0]    a_wdata,  

    //Port B shifter side(read)
    input logic                 b_en,
    input logic [BAW-1:0]       b_addr,
    output logic [BWIDTH-1:0]    b_rdata
);

//The storage array itself in real Si this becomes an SRAM macro,
//in FPGA Vivado infers BRAM from exactly this pattern
logic [BWIDTH-1:0] mem [0:BDEPTH-1];

//Port A: synchronous write only
always_ff @(posedge clk) begin
    if (a_en) begin
        for(int i=0;i<RATIO;i++)
            mem[{a_addr, i[RAW-1:0]}] <= a_wdata[i*BWIDTH +: BWIDTH];
    end
end

//Port B: synchronous read only
always_ff @(posedge clk) begin
    if (b_en) b_rdata <= mem[b_addr];
end

endmodule
