//Data TCM, 64 bit wide, single cycle synchronous read,byte enabled write
//Byte enabled matter: storing one byte must not disturb the other seven
module dmem #(
    parameter int WORDS = 2048,     //16KB
    parameter int AW    = $clog2(WORDS)
)(
    input logic         clk,
    input logic         en,
    input logic [63:0]  addr,
    input logic [7:0]   wstrb,      //onr byte per byte lane
    input logic [63:0]  wdata,
    output logic [63:0] rdata
);

logic [63:0] mem [0:WORDS-1];

//addr[AWW+2:3] drops th low three bits: this is a 64-bit word index
logic [AW-1:0] widx;
assign widx = addr[AW+2:3];

always_ff @( posedge clk) begin
    if (en) begin
        for (int i=0;i<8;i++)
            if(wstrb[i])
                mem[widx][i*8 +: 8] <= wdata[i*8 +: 8];
        rdata <= mem[widx];
    end
end
    
endmodule
