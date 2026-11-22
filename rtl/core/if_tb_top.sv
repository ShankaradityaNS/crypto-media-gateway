// Test harness only: fetch stage wired to the instruction
// TCM verilator needs a single top module, and fetch is meaningless
// without a memory to fetch from
module if_tb_top import core_pkg::*; (
    input logic             clk,
    input logic             rst_n,
    input logic             stall,
    input logic             branch_taken,
    input logic [XLEN-1:0]  branch_target,
    output logic [XLEN-1:0] if_pc,
    output logic [ILEN-1:0] if_instr,
    output logic            if_valid
);

logic [XLEN-1:0] imem_addr;
logic [ILEN-1:0] imem_rdata;

core_if u_if (
    .clk(clk), .rst_n(rst_n), .stall(stall),
    .branch_taken(branch_taken), .branch_target(branch_target),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata), .if_pc(if_pc),
    .if_instr(if_instr), .if_valid(if_valid)
);

tcm u_tcm (
    .clk(clk), .en(!stall),
    .addr(imem_addr),
    .rdata(imem_rdata)
);

endmodule
