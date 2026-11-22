// Hazard detection and forwarding control
// Purely combinational. Decides where each ALU operand comes from,
// and when the pipeline must stall
module core_hazard import core_pkg::*; (
    // the instruction currently in EX needs these two registers
    input logic [RAW-1:0]       ex_rs1_addr,
    input logic [RAW-1:0]       ex_rs2_addr,

    //what MEM is about to produce
    input logic                 mem_reg_write,
    input logic [RAW-1:0]       mem_rd_addr,

    //what WB is about to produce
    input logic                 wb_reg_write,
    input logic [RAW-1:0]       wb_rd_addr,

    // a load currently in EX: its data won't exist until MEM completes
    input logic                 ex_mem_read,
    input logic [RAW-1:0]       ex_rd_addr,

    // the instruction in ID, which may need that load's result
    input logic [RAW-1:0]       id_rs1_addr,
    input logic [RAW-1:0]       id_rs2_addr,

    output fwd_sel_e            fwd_a,
    output fwd_sel_e            fwd_b,
    output logic                stall
);
    
    // Forward from the nearest source. MEM is checked first because a 
    // more recent instruction's result must win over an older one.
    always_comb begin
        if (mem_reg_write && mem_rd_addr != '0 && mem_rd_addr == ex_rs1_addr)
            fwd_a = FWD_MEM;
        else if(wb_reg_write && wb_rd_addr != '0 && wb_rd_addr == ex_rs1_addr)
            fwd_a = FWD_WB;
        else
            fwd_a = FWD_NONE;
    end

    always_comb begin
        if (mem_reg_write && mem_rd_addr != '0 && mem_rd_addr == ex_rs2_addr)
            fwd_b = FWD_MEM;
        else if(wb_reg_write && wb_rd_addr != '0 && wb_rd_addr == ex_rs2_addr)
            fwd_b = FWD_WB;
        else
            fwd_b = FWD_NONE;
    end

    //Load-use hazard: nothung can be forwarded because the value does not exists yet.
    //The only remedy is a one-cycle bubble.
    assign stall = ex_mem_read && ex_rd_addr != '0 &&
                    ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr));

endmodule
