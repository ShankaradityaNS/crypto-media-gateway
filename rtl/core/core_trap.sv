// Trap controller, Combinational: decides whether a trap fires this cycle,
//what cause to record, and where to redirect fetch.
// Priority follows the RISC-V spec: earlier pipeline stages win, since an instruction
// that is illegal never reaches memory
module core_trap import core_pkg::*; (
    input logic         valid,          //the instruction is real
    input logic         illegal_instr,
    input logic         is_ecall,
    input logic         is_ebreak,
    input logic         misaligned_load,
    input logic         misaligned_store,
    input logic         is_mret,
    input logic [XLEN-1:0] pc,          //PC of faulting instruction
    input logic [XLEN-1:0] mem_addr,        //data addr of the access in MEM
    input logic [XLEN-1:0] mtvec,
    input logic [XLEN-1:0] mepc,
    input logic         access_fault_load,
    input logic         access_fault_store,
    input logic         instr_fault,
    input logic         is_interrupt,
    input logic [XLEN-1:0] fetch_target,    //redirect target of taken branch/jump
    input logic [XLEN-1:0] irq_cause,       //which irq, when is_interrupt is true/1
    output logic         trap_taken,     // enter a trap
    output logic [XLEN-1:0] trap_cause,
    output logic [XLEN-1:0] trap_epc,   //value to write into mepc
    output logic [XLEN-1:0] trap_tval,  //value to write into mtval
    output logic            trap_return, //mret: leave a trap
    output logic            redirect,
    output logic [XLEN-1:0] redirect_pc
);

//A taken branch or jump to a target that is not 4-byte aligned. Derived from
//the taregt rather than carried as a flag: an untaken branch contributes
//zero and an aligned taregt has zero low bits, so a non-zero pair is exactly
//the fault case. JALR already clears bit 0, so in practise this catches a 
//target that is 2-byte but not 4-byte aligned -- which is a fault on a core
//without the C extension.
logic misaligned_fetch;
assign misaligned_fetch = (fetch_target[1:0] != 2'b00);

logic any_exception;
assign any_exception = illegal_instr | is_ecall | is_ebreak | misaligned_load 
                        | misaligned_store | access_fault_load | access_fault_store
                        | instr_fault | misaligned_fetch;

//An interrupt is taken before the instruction in MEM executes, so it wins
//over any exception that instruction would have raised -- the instruction
//has not run yet. mepc points at it and it re-executes after mret.
assign trap_taken = valid && (any_exception || is_interrupt);
assign trap_return = valid && is_mret;

always_comb begin
    if (is_interrupt)            trap_cause = irq_cause;
    else if (instr_fault)        trap_cause = CAUSE_INSTR_FAULT;
    else if (misaligned_fetch)   trap_cause = CAUSE_INSTR_ALIGN;
    else if (illegal_instr)      trap_cause = CAUSE_ILLEGAL;
    else if (is_ecall)      trap_cause = CAUSE_ECALL_M;
    else if (is_ebreak)     trap_cause = CAUSE_BREAKPOINT;
    else if (misaligned_load) trap_cause = CAUSE_LOAD_ALIGN;
    else if (misaligned_store) trap_cause = CAUSE_STORE_ALIGN;
    else if (access_fault_load) trap_cause = CAUSE_LOAD_FAULT;
    else if (access_fault_store) trap_cause = CAUSE_STORE_FAULT;
    else                    trap_cause = '0;
end

//mtval is derived from the cause that actually won, not from a second copy
//of the priority chain. That way the two can never disagree, and a future
//change to the priority order cannot leave mtval reporting he address if a 
//fault that lost
always_comb begin
    unique case (trap_cause)
        CAUSE_INSTR_ALIGN: trap_tval = fetch_target;    //the misaligned target
        CAUSE_LOAD_ALIGN,
        CAUSE_STORE_ALIGN,
        CAUSE_LOAD_FAULT,
        CAUSE_STORE_FAULT:  trap_tval = mem_addr;   //faulting data address
        CAUSE_INSTR_FAULT,
        CAUSE_BREAKPOINT:   trap_tval = pc;         //faulting instruction
        default:            trap_tval = '0;         //ecall, illegal, interrupt
    endcase
end

// mepc holds the PC of the faulting instruction, not the next one,
// the handler decides whether to retry it or skip past it
assign trap_epc = pc & ~64'd3;

assign redirect = trap_taken | trap_return;

//mtvex[1:0]: 0->direct 1->vectored approach to handling interrupts
//Vectored dispatch applies to interrupts only; exceptions always
//go to the base address. With no interrupts implemented yet,
//every trap takes the base, but the mode decode is in place.
logic [XLEN-1:0] tvec_base;
logic tvec_vectored;
assign tvec_base = {mtvec[XLEN-1:2], 2'b00};
assign tvec_vectored = (mtvec[1:0] == 2'b01);

//Vectored dispatch scales the exception CODE, so the interrupt bit has to be
//masked off first -- shifting a cause with bit 63 set would land nowhere.
//Exceptions always take the base address regardless of mode.
logic [XLEN-1:0] irq_code;
assign irq_code = trap_cause & ~(64'd1 << (XLEN-1));

logic [XLEN-1:0] trap_target;
assign trap_target = (tvec_vectored && is_interrupt)
                        ? (tvec_base + (irq_code << 2))
                        : tvec_base;

// Direct mode only: mtvec[1:0] is the mode field, not address bits.
assign redirect_pc = trap_taken ? trap_target : mepc;

endmodule
