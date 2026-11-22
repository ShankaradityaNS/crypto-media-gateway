package core_pkg;
    import cmg_config::*;
    export cmg_config::*;
    parameter int XLEN = 64;
    parameter int ILEN = 32;
    parameter int REGS = 32;
    parameter int RAW = $clog2(REGS);

    //RV64I major opcodes (bits[6:0])
    localparam logic [6:0] OP_LUI       = 7'b0110111;
    localparam logic [6:0] OP_AUIPC     = 7'b0010111;
    localparam logic [6:0] OP_JAL       = 7'b1101111;
    localparam logic [6:0] OP_JALR      = 7'b1100111;
    localparam logic [6:0] OP_BRANCH    = 7'b1100011;
    localparam logic [6:0] OP_LOAD      = 7'b0000011;
    localparam logic [6:0] OP_STORE     = 7'b0100011;
    localparam logic [6:0] OP_IMM       = 7'b0010011;
    localparam logic [6:0] OP_REG       = 7'b0110011;
    localparam logic [6:0] OP_IMM_W     = 7'b0011011;       // ADDIW, SLLIW,...
    localparam logic [6:0] OP_REG_W     = 7'b0111011;       //ADDW, SUBW,....
    localparam logic [6:0] OP_MISC_MEM  = 7'b0001111;

    // Physical Memory Map
    //Full 64-bit decode. An access matching no region faults
    //Instruction memory map, derived from cmg_config.
    //
    //Resident code sits at ITCM_BASE and is never swapped. The two windows
    //each alias to one slot from a shared pool, selected by a CSR. Every
    //algorithm is built to run at its window's base address, so one binary
    //per algorithm works whichever slot holds it.
    //
    //Slot 0 is conventionally the fallback algorithm. No hardware enforces
    //that yet -- the write-protection policy is still open.
    localparam logic [XLEN-1:0] ITCM_BASE = 64'hFFFF_FFFF_8000_0000;
        localparam logic [XLEN-1:0] RESIDENT_SIZE = XLEN'(RESIDENT_BYTES);
        
    localparam logic [XLEN-1:0] COMP_BASE = ITCM_BASE + XLEN'(RESIDENT_BYTES);
    localparam logic [XLEN-1:0] COMP_SIZE = XLEN'(SLOT_BYTES);

    localparam logic [XLEN-1:0] CRYPT_BASE = COMP_BASE + XLEN'(SLOT_BYTES);
    localparam logic [XLEN-1:0] CRYPT_SIZE = XLEN'(SLOT_BYTES);

    //End of the instruction addr space, for the overlap check. The
    //windows are what occupy addresses; the slot pool is physical only
    localparam logic [XLEN-1:0] IMEM_END = CRYPT_BASE + CRYPT_SIZE;

    //Physical ITCM: resident plus the whole pool
    localparam int ITCM_WORDS = (RESIDENT_BYTES + SLOT_BYTES * NUM_SLOTS) / 4;
    localparam int ITCM_AW = $clog2(ITCM_WORDS);
    localparam int RESIDENT_WORDS = RESIDENT_BYTES / 4;
    localparam int SLOT_WORDS = SLOT_BYTES / 4;
    localparam int SLOT_SEL_W = (NUM_SLOTS > 1) ? $clog2(NUM_SLOTS) : 1;

    localparam logic [XLEN-1:0] DTCM_BASE = 64'hFFFF_FFFF_8001_0000;
    localparam logic [XLEN-1:0] DTCM_SIZE = XLEN'(DTCM_BYTES);

    localparam logic [XLEN-1:0] HALT_ADDR = 64'hFFFF_FFFF_9000_0000;

    localparam logic [XLEN-1:0] CAUSE_INSTR_FAULT = 64'd1;

    //Access fault causes, from the priviledged spec
    localparam logic [XLEN-1:0] CAUSE_LOAD_FAULT = 64'd5;
    localparam logic [XLEN-1:0] CAUSE_STORE_FAULT = 64'd7;

    //Compliance test signature region. tests write their results here
    //the testbench dumps it and compares against the reference file shipped with test
    localparam logic [XLEN-1:0] SIG_BASE = 64'hFFFF_FFFF_8002_0000;
    localparam logic [XLEN-1:0] SIG_SIZE = XLEN'(SIG_BYTES);

    typedef enum logic [3:0] {
        ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
        ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND,
        ALU_PASS_B
    } alu_op_e;

    typedef enum logic [2:0] {
        IMM_I, IMM_S, IMM_B, IMM_U, IMM_J, IMM_NONE
    }imm_sel_e;

    typedef enum logic [1:0] { 
        CSR_NONE, CSR_RW, CSR_RS, CSR_RC
    } csr_op_e;

    // IF/ID pipeline register
    typedef struct packed {
        logic            valid;
        logic [XLEN-1:0] pc;
        logic [ILEN-1:0] instr;
        logic            instr_fault;
    } if_id_t;

    // ID/EX pipeline register
    typedef struct packed {
        logic               valid;
        logic [XLEN-1:0]    pc;
        logic [RAW-1:0]     rs1_addr;
        logic [RAW-1:0]     rs2_addr;
        logic [RAW-1:0]     rd_addr;
        logic [XLEN-1:0]    rs1_data;
        logic [XLEN-1:0]    rs2_data;
        logic [XLEN-1:0]    imm;
        logic [2:0]         funct3;
        alu_op_e            alu_op;
        logic               alu_src_imm;
        logic               alu_src_pc;
        logic               is_word_op;
        logic               is_branch;
        logic               is_jump;
        logic               is_jalr;
        logic               mem_read;
        logic               mem_write;
        logic               reg_write;
        logic               wb_from_mem;
        logic [11:0]        csr_addr;
        csr_op_e            csr_op;
        logic               csr_imm_sel;
        logic               illegal_instr;
        logic               is_ecall;
        logic               is_ebreak;
        logic               is_mret;
        logic               instr_fault;
    } id_ex_t;

    // EX/MEM pipleline register
    typedef struct packed {
        logic               valid;
        logic [RAW-1:0]     rd_addr;
        logic [XLEN-1:0]    alu_result;
        logic [XLEN-1:0]    store_data;
        logic [2:0]         funct3;
        logic               mem_read;
        logic               mem_write;
        logic               reg_write;
        logic               wb_from_mem;
        logic [XLEN-1:0]    csr_rdata;
        logic               csr_valid;
        logic [XLEN-1:0]    pc;
        logic               illegal_instr;
        logic               is_ecall;
        logic               is_ebreak;
        logic               is_mret;
        logic               instr_fault;
        logic [XLEN-1:0]    fetch_target;   //redirect target of a taken branch/jump
    } ex_mem_t;

    // MEM/WB pipeline register
    typedef struct packed {
        logic               valid;
        logic [RAW-1:0]     rd_addr;
        logic [XLEN-1:0]    alu_result;
        logic               reg_write;
        logic               wb_from_mem;
        logic [XLEN-1:0]    csr_rdata;
        logic               csr_valid;
        logic [2:0]         funct3;
        logic [2:0]         byte_off;
    } mem_wb_t;

    typedef enum  logic [1:0] { 
        FWD_NONE, FWD_MEM, FWD_WB
    } fwd_sel_e;

    //System opcode covers CSR instructions, ECALL, EBREAK, FENCE.I
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

    //CSR addresses we implement
    localparam logic [11:0] CSR_MSTATUS     = 12'h300;
    localparam logic [11:0] CSR_MTVEC       = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH    = 12'h340;
    localparam logic [11:0] CSR_MEPC        = 12'h341;
    localparam logic [11:0] CSR_MCAUSE      = 12'h342;
    localparam logic [11:0] CSR_MTVAL       = 12'h343;
    localparam logic [11:0] CSR_MCYCLE      = 12'hB00;
    localparam logic [11:0] CSR_MINSTRET    = 12'hB02;
    localparam logic [11:0] CSR_ATTEST_CTRL = 12'h7C0;      //write 1 to arm, 0 to check
    localparam logic [11:0] CSR_ATTEST_EXP  = 12'h7C1;      //expected cycle count
    localparam logic [11:0] CSR_ATTEST_ACT  = 12'h7C2;      //actual, read-only
    localparam logic [11:0] CSR_ATTEST_STAT = 12'h7C3;      //bit 0: armed, bit 1: mismatch
    localparam logic [11:0] CSR_SECMODE     = 12'h7C4;      //bit 0: secure mode active

    localparam logic [11:0] CSR_SLOT_COMP   = 12'h7C5;
    localparam logic [11:0] CSR_SLOT_CRYPT  = 12'h7C6;
    localparam logic [11:0] CSR_SLOT_COMMIT = 12'h7C7;
    localparam logic [11:0] CSR_SLOT_LIVE   = 12'h7C8;  //RO: {crypt_live, comp_live}

    //SYSTEM instructions with funct3 = 000, distinguished by instr[31:20]
    localparam logic [11:0] SYS_ECALL = 12'h000;
    localparam logic [11:0] SYS_EBREAK = 12'h001;
    localparam logic [11:0] SYS_MRET = 12'h302;

    //Trap causes (mcause value)
    localparam logic [XLEN-1:0] CAUSE_ILLEGAL       = 64'd2;
    localparam logic [XLEN-1:0] CAUSE_BREAKPOINT    = 64'd3;
    localparam logic [XLEN-1:0] CAUSE_ECALL_M       = 64'd11;
    localparam logic [XLEN-1:0] CAUSE_LOAD_ALIGN    = 64'd4;
    localparam logic [XLEN-1:0] CAUSE_STORE_ALIGN   = 64'd6;

    localparam logic [XLEN-1:0] CAUSE_INSTR_ALIGN   = 64'd0;

    //Machine interrupts CSRs
    localparam logic [11:0] CSR_MIE = 12'h304;
    localparam logic [11:0] CSR_MIP = 12'h344;

    //Interrupts causes. The MSB marks a cause as an interrupt rather than an
    //exception -- that bit is how SW and vectored dispatch tell them
    //apart
    localparam logic [XLEN-1:0] CAUSE_M_SOFT_INT = {1'b1, 63'd3};
    localparam logic [XLEN-1:0] CAUSE_M_TIMER_INT = {1'b1, 63'd7};
    localparam logic [XLEN-1:0] CAUSE_M_EXT_INT = {1'b1, 63'd11};

    //mie/mip bit positions. Only the ext interrupts is implemented;
    //the other two are defined so the encoding is right when they arrive.
    localparam int IRQ_M_SOFT = 3;
    localparam int IRQ_M_TIMER = 7;
    localparam int IRQ_M_EXT = 11;

endpackage
