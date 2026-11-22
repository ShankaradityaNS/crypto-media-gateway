module mem_tb_top import core_pkg::*; (
    input logic             clk,
    input logic [XLEN-1:0]  addr,
    input logic [XLEN-1:0]  store_data,
    input logic [2:0]       funct3,
    input logic             mem_read,
    input logic             mem_write,
    output logic [XLEN-1:0] load_result,
    output logic            misaligned_load,
    output logic            misaligned_store
);
    logic               dmem_en;
    logic [XLEN-1:0]    dmem_addr, dmem_wdata, dmem_rdata;
    logic [7:0]         dmem_wstrb;

    core_mem u_mem (
        .addr(addr), .store_data(store_data), .funct3(funct3),
        .mem_read(mem_read), .mem_write(mem_write),
        .dmem_en(dmem_en), .dmem_addr(dmem_addr),
        .dmem_wstrb(dmem_wstrb), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .load_result(load_result),
        .misaligned_load(misaligned_load), .misaligned_store(misaligned_store)
    );

    dmem u_dmem (
        .clk(clk), .en(dmem_en), .addr(dmem_addr),
        .wstrb(dmem_wstrb), .wdata(dmem_wdata),
        .rdata(dmem_rdata)
    );

endmodule
