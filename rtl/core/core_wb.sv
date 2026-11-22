//Writeback stage. Chooses the value to commit and gates the write.
module core_wb import core_pkg::*; (
    input logic [XLEN-1:0]      alu_result,
    input logic                 wb_from_mem,
    input logic                 reg_write,
    input logic [RAW-1:0]       rd_addr,
    input logic                 valid,      //instruction is real, not finished
    input logic [XLEN-1:0]      csr_rdata,
    input logic                 csr_valid,
    input logic [XLEN-1:0]      mem_rdata,
    input logic [2:0]           funct3,
    input logic [2:0]           byte_off,

    output logic                rf_we,
    output logic [RAW-1:0]      rf_waddr,
    output logic [XLEN-1:0]     rf_wdata
);

    assign rf_waddr = rd_addr;
    assign rf_wdata = csr_valid ? csr_rdata : wb_from_mem ? load_result : alu_result;

    //x0 is hardwired to 0, so a write to it must never happen.
    //The register file also guards this, but blocking it here keepes
    //the write-enable honest for anything else watching it.
    assign rf_we = reg_write && valid && (rd_addr != '0);

    // The memory read lands at the MEM/WB boundary, so the aligner
    // belongs here, driven by this instruction's own funct3 and offset.
    logic [XLEN-1:0] shifted;
    assign shifted = mem_rdata >> (8*byte_off);

    logic [XLEN-1:0] load_result;
    always_comb begin
        load_result = '0;
        unique case (funct3)
            3'b000: load_result = {{56{shifted[7]}},  shifted[7:0]};
            3'b001: load_result = {{48{shifted[15]}}, shifted[15:0]};
            3'b010: load_result = {{32{shifted[31]}}, shifted[31:0]};
            3'b011: load_result = mem_rdata;
            3'b100: load_result = {56'b0, shifted[7:0]};
            3'b101: load_result = {48'b0, shifted[15:0]};
            3'b110: load_result = {32'b0, shifted[31:0]};
            default: ;
        endcase
    end
    
endmodule
