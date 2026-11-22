// Control and status registers.
//Read is combinational; write commits on the clk edge
//mcycle and minstret free-run and are only overriden by an explicit write
module core_csr import core_pkg::*; #(
    parameter bit SECURITY_ENABLE = 1
    )(
    input logic         clk,
    input logic         rst_n,
    input logic         instr_retired,      //one instruction commited
    input logic [11:0]  addr,
    input csr_op_e      op,
    input logic [XLEN-1:0] wdata,           //register value or zero-extended imm
    input logic         we,                 //this instruction accesses a CSR
    input logic         trap_taken,
    input logic [XLEN-1:0] trap_cause_i,
    input logic [XLEN-1:0] trap_epc_i,
    input logic [XLEN-1:0] trap_tval_i,
    input logic         trap_return,        //mret: restore MIE from MPIE
    input logic         ext_irq,            //external interrupt request pin

    output logic [XLEN-1:0] rdata,
    output logic        secure_mode,
    output logic [XLEN-1:0] mtvec_o,
    output logic [XLEN-1:0] mepc_o,
    output logic            irq_pending,        //an enabled interrupt is waiting
    output logic [XLEN-1:0] irq_cause,
    output logic [SLOT_SEL_W-1:0] comp_slot_live,
    output logic [SLOT_SEL_W-1:0] crypt_slot_live
);

logic [XLEN-1:0] mstatus_q, mtvec_q, mscratch_q;
logic [XLEN-1:0] mepc_q, mcause_q, mtval_q;
logic [XLEN-1:0] mcycle_q, minstret_q;
logic [XLEN-1:0] attest_exp_q, attest_act_q, attest_start_q;
logic            attest_armed_q, attest_fail_q;
logic            secmode_q;
logic [XLEN-1:0] mie_q;

logic [SLOT_SEL_W-1:0] comp_live_q, comp_pend_q;
logic [SLOT_SEL_W-1:0] crypt_live_q, crypt_pend_q;

logic swap_pending;
assign swap_pending = (comp_pend_q != comp_live_q) || (crypt_pend_q != crypt_live_q);

logic [7:0] comp_live_b, comp_pend_b, crypt_live_b, crypt_pend_b;
assign comp_live_b = 8'(comp_live_q);
assign comp_pend_b = 8'(comp_pend_q);
assign crypt_live_b = 8'(crypt_live_q);
assign crypt_pend_b = 8'(crypt_pend_q);

//mstatus is WARL - Write Any Read Legal. Only the fields this core implements are writable, and
//MPP is read-only 3 (M-mode) because no other privilage mode exists.
//Without this SW probing for S-mode by writing MPP sees its write
//stick and concludes a mode is available that is not.
localparam logic [XLEN-1:0] MSTATUS_WMASK = 64'h0000_0000_0000_0088;        // MPIE | MIE
localparam logic [XLEN-1:0] MSTATUS_FIXED = 64'h0000_0000_0000_1800;        // MPP =3
localparam int MSTATUS_MIE_BIT = 3;
localparam int MSTATUS_MPIE_BIT = 7;

//Only the ext interrupt is implemented. The other two bitsread as
//zero and ignore writes, so sw cannot enable an interrupt that has
//no source behind it
localparam logic [XLEN-1:0] MIE_WMASK = (64'd1 << IRQ_M_EXT);

logic [XLEN-1:0] mip;
always_comb begin
    mip = '0;
    mip[IRQ_M_EXT] = ext_irq;
end

logic [XLEN-1:0] irq_active;
assign irq_active = mip & mie_q;

//M-mode interrupt priority per the spec: ext then SW then
//timer
always_comb begin
    if (irq_active[IRQ_M_EXT]) irq_cause = CAUSE_M_EXT_INT;
    else if (irq_active[IRQ_M_SOFT]) irq_cause = CAUSE_M_SOFT_INT;
    else if (irq_active[IRQ_M_TIMER]) irq_cause = CAUSE_M_TIMER_INT;
    else                            irq_cause = '0;
end

//Taken only when pending, locally enabled in mie, and globally enabled.
assign irq_pending = mstatus_q[MSTATUS_MIE_BIT] && |irq_active;

//read
always_comb begin
    unique case (addr)
    CSR_MSTATUS:        rdata = mstatus_q;
    CSR_MTVEC:          rdata = mtvec_q;
    CSR_MSCRATCH:       rdata = mscratch_q;
    CSR_MEPC:           rdata = mepc_q;
    CSR_MCAUSE:         rdata = mcause_q;
    CSR_MTVAL:          rdata = mtval_q;
    CSR_MCYCLE:         rdata = mcycle_q;
    CSR_MINSTRET:       rdata = minstret_q;
    CSR_ATTEST_CTRL:    rdata = {63'b0, attest_armed_q};
    CSR_ATTEST_EXP:     rdata = attest_exp_q;
    CSR_ATTEST_ACT:     rdata = attest_act_q;
    CSR_ATTEST_STAT:    rdata = {62'b0, attest_fail_q, attest_armed_q};
    CSR_SECMODE:        rdata = {63'b0, secmode_q};
    CSR_SLOT_COMP:   rdata = {{(XLEN-8){1'b0}}, comp_pend_b};
    CSR_SLOT_CRYPT:  rdata = {{(XLEN-8){1'b0}}, crypt_pend_b};
    CSR_SLOT_COMMIT: rdata = {63'b0, swap_pending};
    CSR_SLOT_LIVE:   rdata = {{(XLEN-16){1'b0}}, crypt_live_b, comp_live_b};
    CSR_MIE:            rdata = mie_q;
    CSR_MIP:            rdata = mip;
    default:            rdata = '0;
    endcase
end

//The value to commit, per the three CSR operation
logic [XLEN-1:0] next;
always_comb begin
    unique case (op)
        CSR_RW:     next = wdata;
        CSR_RS:     next = rdata | wdata;
        CSR_RC:     next = rdata & ~wdata;
        default:    next = rdata;
    endcase
end

//write
always_ff @( posedge clk or negedge rst_n ) begin
    if(!rst_n) begin
        mstatus_q <= MSTATUS_FIXED;
        mtvec_q <= '0;
        mscratch_q <= '0;
        mepc_q <= '0;
        mcause_q <= '0;
        mtval_q <= '0;
        mcycle_q <= '0;
        minstret_q <= '0;
        attest_exp_q <= '0;
        attest_act_q <= '0;
        attest_start_q <= '0;
        attest_armed_q <= '0;
        attest_fail_q <= '0;
        secmode_q <= 1'b0;
        mie_q <= '0;
        comp_live_q  <= SLOT_SEL_W'(DEFAULT_COMP_SLOT);
        comp_pend_q  <= SLOT_SEL_W'(DEFAULT_COMP_SLOT);
        crypt_live_q <= SLOT_SEL_W'(DEFAULT_CRYPT_SLOT);
        crypt_pend_q <= SLOT_SEL_W'(DEFAULT_CRYPT_SLOT);
    end else begin
        //counters free-run
        mcycle_q <= mcycle_q + 64'd1;
        if (instr_retired) minstret_q <= minstret_q + 64'd1;
        if(trap_taken) begin
            //hardware trap wins: record where and why
            mepc_q <= trap_epc_i;
            mcause_q <= trap_cause_i;
            mtval_q <= trap_tval_i;
            //MPIE captures the enable state being left behind; MIE clears so
            //the handler runs masked unil it chooses otherwise
            mstatus_q[MSTATUS_MPIE_BIT] <= mstatus_q[MSTATUS_MIE_BIT];
            mstatus_q[MSTATUS_MIE_BIT] <= 1'b0;
        end
        else if (trap_return) begin
            mstatus_q[MSTATUS_MIE_BIT]  <= mstatus_q[MSTATUS_MPIE_BIT];
            mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
        end
        else if (we) begin
            unique case (addr)
                CSR_MSTATUS: mstatus_q <= (next & MSTATUS_WMASK) | MSTATUS_FIXED;
                CSR_MTVEC: mtvec_q <= (next[1:0] < 2'd2) ? next : {next[XLEN-1:2], 2'b00} ;
                CSR_MSCRATCH: mscratch_q <= next;
                CSR_MEPC: mepc_q <= next;
                CSR_MCAUSE: mcause_q <= next;
                CSR_MTVAL: mtval_q <= next;
                CSR_MCYCLE: mcycle_q <= next;
                CSR_MINSTRET: minstret_q <= next;
                CSR_ATTEST_EXP: attest_exp_q <= next;
                CSR_ATTEST_CTRL: begin
                    if(next[0]) begin
                        //arm: record the cycle we started at
                        attest_start_q <= mcycle_q;
                        attest_armed_q <= 1'b1;
                        attest_fail_q <= 1'b0;
                    end else if (attest_armed_q) begin
                        //check: measure elapsed and compare
                        attest_act_q <= mcycle_q - attest_start_q;
                        attest_armed_q <= 1'b0;
                        attest_fail_q <= ((mcycle_q - attest_start_q) != attest_exp_q);
                    end
                end
                CSR_SECMODE: secmode_q <= next[0];
                CSR_MIE: mie_q <= next & MIE_WMASK;
                CSR_SLOT_COMP:
                    if (next < 64'(NUM_SLOTS)) comp_pend_q  <= next[SLOT_SEL_W-1:0];
                CSR_SLOT_CRYPT:
                    if (next < 64'(NUM_SLOTS)) crypt_pend_q <= next[SLOT_SEL_W-1:0];
                CSR_SLOT_COMMIT:
                    if (next[0]) begin
                        comp_live_q  <= comp_pend_q;
                        crypt_live_q <= crypt_pend_q;
                    end
                default: ;
        endcase
        end
    end
end

assign secure_mode = SECURITY_ENABLE && secmode_q;
assign mtvec_o = mtvec_q;
assign mepc_o =  mepc_q;
assign comp_slot_live  = comp_live_q;
assign crypt_slot_live = crypt_live_q;
    
endmodule
