//32 x 64 bit register file. Two async read ports, one sync write port.
//x0 has no storage and always reads as 0
module regfile import core_pkg::*; (
    input logic             clk,
    input logic             rst_n,
    input logic [RAW-1:0]   rs1_addr, 
    output logic [XLEN-1:0]  rs1_data,
    input logic [RAW-1:0]   rs2_addr,
    output logic [XLEN-1:0]  rs2_data,
    input logic             rd_we,
    input logic [RAW-1:0]   rd_addr,
    input logic [XLEN-1:0]  rd_data
);

    logic [XLEN-1:0] mem [1:REGS-1];    //x0 is not stored

    always_ff @( posedge clk ) begin
        if(rd_we && rd_addr != '0)
            mem[rd_addr] <= rd_data;
    end

    //Asynchronous reads, with write-through so a same-cycle write is seen
    always_comb begin
        if(rs1_addr == '0)                      rs1_data = '0;
        else if(rd_we && rd_addr == rs1_addr)   rs1_data = rd_data;
        else                                    rs1_data = mem[rs1_addr];
    end

    always_comb begin
        if(rs2_addr == '0)                      rs2_data = '0;
        else if(rd_we && rd_addr == rs2_addr)   rs2_data = rd_data;
        else                                    rs2_data = mem[rs2_addr];
    end
    
endmodule
