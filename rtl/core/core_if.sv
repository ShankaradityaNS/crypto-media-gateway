//Instruction fetch. PC register plus a TCM read port
//TCM read is synchronous, so the instruction arrives the cycle after
//its address is presented. pc_fetched_q tracks which PC the currently
//visible instruction belongs to.
//Single-cycle TCM, so the instruction arrives the cycle after the addr
module core_if import core_pkg::*; #(
    parameter logic [XLEN-1:0] RESET_PC = 64'h0000_0000_8000_0000
    )(
    input logic             clk,
    input logic             rst_n,
    input logic             stall,      //hold PC
    input logic             branch_taken,
    input logic [XLEN-1:0]  branch_target,
    output logic [XLEN-1:0] imem_addr,
    input logic [ILEN-1:0]  imem_rdata,
    output logic [XLEN-1:0] if_pc,      //PC of the instruction in if_instr
    output logic [ILEN-1:0] if_instr,
    output logic            if_valid,
    output logic            instr_fault
);

    logic [XLEN-1:0] pc_q;
    logic [XLEN-1:0] pc_fetched_q;      //PC that imem_rdata corresponds to
    logic            valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pc_q            <= RESET_PC;
            pc_fetched_q    <= '0;
            valid_q         <= 1'b0;
        end else if (branch_taken) begin
            pc_q            <= branch_target;
            valid_q         <= 1'b0;
        end else if (!stall) begin
            pc_q            <= pc_q + 64'd4;
            pc_fetched_q    <= pc_q;
            valid_q         <= 1'b1;
        end
    end

    assign imem_addr = pc_q;
    assign if_pc     = pc_fetched_q;
    assign if_instr  = imem_rdata;
    assign if_valid  = valid_q;

    //Fetch must land inside the instruction TCM. Anything else is
    //an instruction access fault - the aliased word must not execute
    logic in_itcm;
    assign in_itcm = (pc_fetched_q >= ITCM_BASE) && 
                        (pc_fetched_q < IMEM_END);

    assign instr_fault = valid_q && !in_itcm;

endmodule
