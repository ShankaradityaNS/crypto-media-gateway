//Five Stage RV64I pipeline
//IF->ID->EX->MEM->WB, with forwarding and load-use stall
module core_top import core_pkg::*; #(
    parameter logic [XLEN-1:0] RESET_PC = ITCM_BASE
)(
    input logic clk,
    input logic rst_n,
    input logic ext_irq,
    output logic halt_req,

    //ITCM fill port for the boot and hot-swap DMA.
    input logic itcm_we,
    input logic [ITCM_AW-1:0] itcm_waddr,  //4096 words
    input logic [31:0] itcm_wdata,
    output logic itcm_wreject
);

    `ifndef SYNTHESIS
        //Elaboration-time memory map check. Simulation only: this is pure
        //parameter arithmetic, so a violation is a design error caught at
        //elaboration rather than anything the hardware needs to test.
        initial begin
            if (IMEM_END > DTCM_BASE)
                $error("instruction windows overlap DTCM");
            if ((DTCM_BASE + DTCM_SIZE) > SIG_BASE)
                $error("DTCM overlaps signature region");
            if ((SIG_BASE + SIG_SIZE) > HALT_ADDR)
                $error("Signature region overlaps HALT address");
        end
    `endif

    //pipeline registers
    if_id_t if_id_q;
    id_ex_t id_ex_q;
    ex_mem_t ex_mem_q;
    mem_wb_t mem_wb_q;

    //control
    logic stall;        //from the hazard unit
    logic branch_taken; //from EX
    logic [SLOT_SEL_W-1:0] comp_slot_sel, crypt_slot_sel;
    logic [XLEN-1:0] branch_target;

    //IF
    logic [XLEN-1:0] imem_addr;
    logic [ILEN-1:0] imem_rdata;
    logic [XLEN-1:0] if_pc;
    logic [ILEN-1:0] if_instr;
    logic            if_valid;
    logic            instr_fault;
    logic            if_instr_fault;

    core_if #(.RESET_PC(RESET_PC)) u_if (
        .clk(clk), .rst_n(rst_n), .stall(stall),
        .branch_taken(branch_taken), .branch_target(branch_target),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .if_pc(if_pc), .if_instr(if_instr), .if_valid(if_valid),
        .instr_fault(if_instr_fault)
    );

    tcm #(
        .RESIDENT_WORDS (RESIDENT_WORDS), .SLOT_WORDS(SLOT_WORDS),
        .NUM_SLOTS(NUM_SLOTS)
    ) u_itcm (
        .clk(clk), .en(!stall), .addr(imem_addr), .rdata(imem_rdata),
        .comp_slot(comp_slot_sel), .crypt_slot(crypt_slot_sel),
        .we(itcm_we), .waddr(itcm_waddr), .wdata(itcm_wdata),
        .wreject(itcm_wreject)
    );

    // IF/ID register
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)              if_id_q <= '0;
        else if (branch_taken)  if_id_q <= '0;      //flush
        else if (!stall) begin
            if_id_q.valid <= if_valid;
            if_id_q.pc <= if_pc;
            if_id_q.instr <= if_instr;
            if_id_q.instr_fault <= if_instr_fault;
        end
    end

    // ID
    logic [RAW-1:0] id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [XLEN-1:0] id_imm, rf_rs1_data, rf_rs2_data;
    alu_op_e    id_alu_op;
    logic       id_alu_src_imm, id_alu_src_pc, id_is_word_op;
    logic       id_is_branch, id_is_jump, id_is_jalr;
    logic       id_mem_read, id_mem_write, id_reg_write, id_wb_from_mem;
    logic [2:0] id_funct3;
    logic [11:0] id_csr_addr;
    csr_op_e     id_csr_op;
    logic        id_csr_imm_sel;
    logic       id_illegal_instr, id_is_ecall, id_is_ebreak, id_is_mret;
    logic       mem_misaligned_load, mem_misaligned_store;
    logic       mem_fault_load, mem_fault_store;

    core_id u_id (
        .if_instr(if_id_q.instr),
        .rs1_addr(id_rs1_addr), .rs2_addr(id_rs2_addr), .rd_addr(id_rd_addr),
        .imm(id_imm), .alu_op(id_alu_op), .alu_src_imm(id_alu_src_imm),
        .alu_src_pc(id_alu_src_pc), .is_word_op(id_is_word_op),
        .is_branch(id_is_branch), .is_jump(id_is_jump),
        .is_jalr(id_is_jalr), .mem_read(id_mem_read), .mem_write(id_mem_write),
        .reg_write(id_reg_write), .wb_from_mem(id_wb_from_mem), .funct3_o(id_funct3),
        .csr_addr(id_csr_addr), .csr_op(id_csr_op), .csr_imm_sel(id_csr_imm_sel),
        .illegal_instr(id_illegal_instr), .is_ecall(id_is_ecall), 
        .is_ebreak(id_is_ebreak), .is_mret(id_is_mret)
    );

    logic            rf_we;
    logic [RAW-1:0]  rf_waddr;
    logic [XLEN-1:0] rf_wdata;

    regfile u_rf(
        .clk(clk), .rst_n(rst_n), .rs1_addr(id_rs1_addr),
        .rs1_data(rf_rs1_data), .rs2_addr(id_rs2_addr),
        .rs2_data(rf_rs2_data), .rd_we(rf_we), .rd_addr(rf_waddr),
        .rd_data(rf_wdata)
    );

    // ID/EX register. A stall injects a bubble here: the instruction
    // in ID is held, and EX receives an invalid entry
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n || branch_taken || stall) begin
            id_ex_q <= '0;
        end else begin
            id_ex_q.valid <= if_id_q.valid;
            id_ex_q.pc <= if_id_q.pc;
            id_ex_q.rs1_addr <= id_rs1_addr;
            id_ex_q.rs2_addr <= id_rs2_addr;
            id_ex_q.rd_addr <= id_rd_addr;
            id_ex_q.rs1_data <= rf_rs1_data;
            id_ex_q.rs2_data <= rf_rs2_data;
            id_ex_q.imm <= id_imm;
            id_ex_q.funct3 <= id_funct3;
            id_ex_q.alu_op <= id_alu_op;
            id_ex_q.alu_src_imm <= id_alu_src_imm;
            id_ex_q.alu_src_pc <= id_alu_src_pc;
            id_ex_q.is_word_op <= id_is_word_op;
            id_ex_q.is_branch <= id_is_branch;
            id_ex_q.is_jump <= id_is_jump;
            id_ex_q.is_jalr <= id_is_jalr;
            id_ex_q.mem_read <= id_mem_read;
            id_ex_q.mem_write <= id_mem_write;
            id_ex_q.reg_write <= id_reg_write;
            id_ex_q.wb_from_mem <= id_wb_from_mem;
            id_ex_q.csr_addr <= id_csr_addr;
            id_ex_q.csr_op <= id_csr_op;
            id_ex_q.csr_imm_sel <= id_csr_imm_sel;
            id_ex_q.illegal_instr <= id_illegal_instr;
            id_ex_q.is_ecall <= id_is_ecall;
            id_ex_q.is_ebreak <= id_is_ebreak;
            id_ex_q.is_mret <= id_is_mret;
            id_ex_q.instr_fault <= if_id_q.instr_fault;
        end
    end

    // EX
    fwd_sel_e fwd_a, fwd_b;

    core_hazard u_hazard (
        .ex_rs1_addr(id_ex_q.rs1_addr), .ex_rs2_addr(id_ex_q.rs2_addr),
        .mem_reg_write(ex_mem_q.reg_write && ex_mem_q.valid),
        .mem_rd_addr(ex_mem_q.rd_addr),
        .wb_reg_write(mem_wb_q.reg_write && mem_wb_q.valid),
        .wb_rd_addr(mem_wb_q.rd_addr),
        .ex_mem_read(id_ex_q.mem_read && id_ex_q.valid), .ex_rd_addr(id_ex_q.rd_addr),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr),
        .fwd_a(fwd_a), .fwd_b(fwd_b), .stall(stall)
    );

    // Forwarding muxes. WB's value is the one about to be written.
    // which is rf_wdata, not the register file's current contents.
    logic [XLEN-1:0] ex_rs1_fwd, ex_rs2_fwd;
    always_comb begin
        unique case (fwd_a)
            FWD_MEM: ex_rs1_fwd = ex_mem_q.csr_valid ? ex_mem_q.csr_rdata
                                                     : ex_mem_q.alu_result;
            FWD_WB:  ex_rs1_fwd = rf_wdata;
            default: ex_rs1_fwd = id_ex_q.rs1_data;
        endcase
    end
    always_comb begin
        unique case (fwd_b)
            FWD_MEM: ex_rs2_fwd = ex_mem_q.csr_valid ? ex_mem_q.csr_rdata
                                                     : ex_mem_q.alu_result;
            FWD_WB:  ex_rs2_fwd = rf_wdata;
            default: ex_rs2_fwd = id_ex_q.rs2_data;
        endcase
    end

    logic [XLEN-1:0] ex_alu_result, ex_branch_target;
    logic ex_branch_taken;
    logic [XLEN-1:0] csr_rdata;
    logic [XLEN-1:0] csr_wdata;
    logic            csr_access;
    logic            csr_we;
    logic            secure_mode;

    core_ex u_ex (
        .pc(id_ex_q.pc), .rs1_data(ex_rs1_fwd), .rs2_data(ex_rs2_fwd),
        .imm(id_ex_q.imm), .alu_op(id_ex_q.alu_op),
        .alu_src_imm(id_ex_q.alu_src_imm), .alu_src_pc(id_ex_q.alu_src_pc),
        .is_word_op(id_ex_q.is_word_op), .is_branch(id_ex_q.is_branch),
        .is_jump(id_ex_q.is_jump), .is_jalr(id_ex_q.is_jalr),
        .funct3(id_ex_q.funct3), .alu_result(ex_alu_result),
        .branch_taken(ex_branch_taken), .branch_target(ex_branch_target)
    );

    // A trap or mret redirects fetch, and takes priority over a branch:
    // the trapping instruction is older than anything in EX.
    //A misaligned target must never be fetched. The branch itself traps when
    //it reaches MEM, so fetch just continues in sequence until the trap
    //redirect arrives a cycle later.
    assign branch_taken = trap_redirect || (ex_branch_taken && id_ex_q.valid && 
                            (ex_branch_target[1:0] == 2'b00));
    assign branch_target = trap_redirect ? trap_redirect_pc : ex_branch_target;
    //A CSR instruction sources its opearnds from rs1 or from 1  5-bit
    //immediate sitting in the rs1 field, zero extended
    assign csr_wdata = id_ex_q.csr_imm_sel ? {59'b0, id_ex_q.rs1_addr} : ex_rs1_fwd;
    // "this instruction accesses a CSR" - drives writeback and forwarding
    assign csr_access = (id_ex_q.csr_op != CSR_NONE) && id_ex_q.valid
                            && !id_ex_q.instr_fault
                            && !id_ex_q.illegal_instr;

    // "this instruction writes the CSR". Per the spec, csrrs/csrrc with a
    // zero source must not write, so a plain read cannot fire a write-side
    // effect. The rs1 field also carries uimm for the csrrsi/csrrci forms,
    // so one test covers both.
    assign csr_we = csr_access
                        && !((id_ex_q.csr_op == CSR_RS ||
                              id_ex_q.csr_op == CSR_RC)
                             && id_ex_q.rs1_addr == 5'd0);
                                 
    core_csr u_csr (
        .clk(clk), .rst_n(rst_n), .instr_retired(mem_wb_q.valid),
        .addr(id_ex_q.csr_addr), .op(id_ex_q.csr_op), .wdata(csr_wdata),
        .we(csr_we), .rdata(csr_rdata), .secure_mode(secure_mode),
        .trap_taken(trap_taken), .trap_cause_i(trap_cause), 
        .trap_epc_i(trap_epc), .mtvec_o(csr_mtvec), .mepc_o(csr_mepc),
        .trap_tval_i(trap_tval), .trap_return(trap_return), .ext_irq(ext_irq),
        .irq_pending(irq_pending), .irq_cause(irq_cause),
        .comp_slot_live(comp_slot_sel), .crypt_slot_live(crypt_slot_sel)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) ex_mem_q <= '0;
        else if (trap_redirect) ex_mem_q <= '0;
        else begin
            ex_mem_q.valid <= id_ex_q.valid;
            ex_mem_q.rd_addr <= id_ex_q.rd_addr;
            ex_mem_q.alu_result <= ex_alu_result;
            ex_mem_q.store_data <= ex_rs2_fwd;
            ex_mem_q.funct3 <= id_ex_q.funct3;
            ex_mem_q.mem_read <= id_ex_q.mem_read && id_ex_q.valid
                                    && !id_ex_q.instr_fault
                                    && !id_ex_q.illegal_instr;
            ex_mem_q.mem_write <= id_ex_q.mem_write && id_ex_q.valid
                                    && !id_ex_q.instr_fault
                                    && !id_ex_q.illegal_instr;
            //Qualified here rather than at each consumer: a bubble must never
            //claim to write a register. Three separate consumers previously
            //had to remember this, and all three forgot.
            ex_mem_q.reg_write <= id_ex_q.reg_write && id_ex_q.valid;   
            ex_mem_q.wb_from_mem <= id_ex_q.wb_from_mem;
            ex_mem_q.csr_rdata <= csr_rdata;
            ex_mem_q.csr_valid <= csr_access;
            ex_mem_q.pc         <= id_ex_q.pc;
            ex_mem_q.illegal_instr <= id_ex_q.illegal_instr;
            ex_mem_q.is_ecall      <= id_ex_q.is_ecall;
            ex_mem_q.is_ebreak     <= id_ex_q.is_ebreak;
            ex_mem_q.is_mret       <= id_ex_q.is_mret;
            ex_mem_q.instr_fault   <= id_ex_q.instr_fault;
            ex_mem_q.fetch_target  <= (ex_branch_taken && id_ex_q.valid)
                                        ? ex_branch_target : '0;
        end
    end

    // MEM
    logic            dmem_en;
    logic [XLEN-1:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [7:0]      dmem_wstrb;
    logic            trap_taken, trap_return, trap_redirect;
    logic [XLEN-1:0] trap_cause, trap_epc, trap_redirect_pc;
    logic [XLEN-1:0] csr_mtvec, csr_mepc;
    logic            sigmem_en;
    logic [XLEN-1:0] sigmem_rdata;
    logic            mem_in_sig, mem_in_sig_q;
    logic [XLEN-1:0] mem_rdata_mux;
    logic [XLEN-1:0] trap_tval;

    logic           irq_pending;
    logic [XLEN-1:0] irq_cause;

    // Memory read data arrives a cycle after the address, so the
    // region select must be registered to travel with it.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mem_in_sig_q <= 1'b0;
        else        mem_in_sig_q <= mem_in_sig;
    end

    assign mem_rdata_mux = mem_in_sig_q ? sigmem_rdata : dmem_rdata;

    core_mem u_mem (
        .addr(ex_mem_q.alu_result), .store_data(ex_mem_q.store_data),
        .funct3(ex_mem_q.funct3), .mem_read(ex_mem_q.mem_read && ex_mem_q.valid),
        .mem_write(ex_mem_q.mem_write && ex_mem_q.valid), .dmem_en(dmem_en),
        .dmem_addr(dmem_addr),
        .dmem_wstrb(dmem_wstrb), .dmem_wdata(dmem_wdata),
        .misaligned_load(mem_misaligned_load), .misaligned_store(mem_misaligned_store),
        .access_fault_load(mem_fault_load), .access_fault_store(mem_fault_store),
        .halt_req(halt_req), .sigmem_en(sigmem_en), .in_sig(mem_in_sig)
    );

    core_trap u_trap(
        .valid(ex_mem_q.valid), .illegal_instr(ex_mem_q.illegal_instr),
        .is_ecall(ex_mem_q.is_ecall), .is_ebreak(ex_mem_q.is_ebreak),
        .misaligned_load(mem_misaligned_load), .misaligned_store(mem_misaligned_store),
        .is_mret(ex_mem_q.is_mret), .pc(ex_mem_q.pc), .mtvec(csr_mtvec),
        .mepc(csr_mepc), .trap_taken(trap_taken), .trap_cause(trap_cause),
        .trap_epc(trap_epc), .trap_return(trap_return), .redirect(trap_redirect),
        .redirect_pc(trap_redirect_pc), .access_fault_load(mem_fault_load),
        .access_fault_store(mem_fault_store), .instr_fault(ex_mem_q.instr_fault),
        .mem_addr(ex_mem_q.alu_result), .trap_tval(trap_tval),
        .fetch_target(ex_mem_q.fetch_target), .is_interrupt(irq_pending),
        .irq_cause(irq_cause)
    );

    //A trap must not let the instruction in MEM commit: it re-executes after
    //mret. Register writes are already suppressed, and memory is the other
    //commit point -- an interrupted store would otherwise write twice.
    dmem u_dtcm (
        .clk(clk), .en(dmem_en && !trap_taken), .addr(dmem_addr),
        .wstrb(dmem_wstrb), .wdata(dmem_wdata), .rdata(dmem_rdata)
    );

    //Signature memory for the compliance tests. Same module as the data TCM.
    //A seperate instance so the regions stay independent
    dmem #(.WORDS(1024)) u_sigmem (
        .clk(clk), .en(sigmem_en && !trap_taken), .addr(dmem_addr), .wstrb(dmem_wstrb),
        .wdata(dmem_wdata), .rdata(sigmem_rdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) mem_wb_q <= '0;
        else begin
            mem_wb_q.valid <= ex_mem_q.valid;
            mem_wb_q.rd_addr <= ex_mem_q.rd_addr;
            mem_wb_q.alu_result <= ex_mem_q.alu_result;
            mem_wb_q.reg_write <= ex_mem_q.reg_write && !trap_taken && ex_mem_q.valid;
            mem_wb_q.wb_from_mem <= ex_mem_q.wb_from_mem;
            mem_wb_q.csr_rdata <= ex_mem_q.csr_rdata;
            mem_wb_q.csr_valid <= ex_mem_q.csr_valid;
            mem_wb_q.funct3    <= ex_mem_q.funct3;
            mem_wb_q.byte_off  <= ex_mem_q.alu_result[2:0];
        end
    end

    // WB
    core_wb u_wb (
        .alu_result(mem_wb_q.alu_result),
        .mem_rdata(mem_rdata_mux),
        .funct3(mem_wb_q.funct3),
        .byte_off(mem_wb_q.byte_off),
        .wb_from_mem(mem_wb_q.wb_from_mem),
        .reg_write(mem_wb_q.reg_write),
        .rd_addr(mem_wb_q.rd_addr),
        .valid(mem_wb_q.valid),
        .rf_we(rf_we), .rf_waddr(rf_waddr), .rf_wdata(rf_wdata),
        .csr_rdata(mem_wb_q.csr_rdata), .csr_valid(mem_wb_q.csr_valid)
    );

    
    
endmodule
