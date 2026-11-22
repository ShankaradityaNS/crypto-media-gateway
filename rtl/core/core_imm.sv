// Immediate extraction and sign extension, split out so it can be verified on its own.
//Folded into core_id.sv once it passes.
module core_imm import core_pkg::*; (
    input logic [ILEN-1:0] instr,
    output logic [XLEN-1:0] imm
);

    logic [6:0] opcode;
    assign opcode = instr[6:0];

    imm_sel_e sel;

    always_comb begin
        unique case (opcode)
            OP_IMM, OP_IMM_W, OP_LOAD, OP_JALR: sel = IMM_I;
            OP_STORE:                           sel = IMM_S;
            OP_BRANCH:                          sel = IMM_B;
            OP_LUI, OP_AUIPC:                   sel = IMM_U;
            OP_JAL:                             sel = IMM_J;
            default:                            sel = IMM_NONE;
        endcase
    end

    always_comb begin
        unique case (sel)
            IMM_I: imm = {{52{instr[31]}}, instr[31:20]};
            IMM_S: imm = {{52{instr[31]}}, instr[31:25], instr[11:7]};
            IMM_B: imm = {{51{instr[31]}}, instr[31], instr[7],
                            instr[30:25], instr[11:8], 1'b0};
            IMM_U: imm = {{32{instr[31]}}, instr[31:12], 12'b0};
            IMM_J: imm = {{43{instr[31]}}, instr[31], instr[19:12],
                            instr[20], instr[30:21], 1'b0};
            default: imm = '0;
        endcase
    end

endmodule
