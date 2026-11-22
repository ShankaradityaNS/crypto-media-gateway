//Memory stage. Aligns sub-word loads and stores to the 64-bit data TCM.
//Combinational address and write-data formatting: the read data comes
//back the following cycle so load results are handled by the caller
module core_mem import core_pkg::*;(
    input logic [XLEN-1:0] addr,        //from the ALU
    input logic [XLEN-1:0] store_data,  //rs2
    input logic [2:0]      funct3,
    input logic            mem_read,
    input logic            mem_write,

    //to the data TCM
    output logic            dmem_en,
    output logic [XLEN-1:0] dmem_addr,
    output logic [XLEN-1:0] dmem_wdata,
    output logic [7:0]      dmem_wstrb,

    //from the data TCM, one cycle later
    output logic            misaligned_load,
    output logic            misaligned_store,

    output logic            access_fault_load,
    output logic            access_fault_store,
    output logic            halt_req,
    output logic            sigmem_en,
    output logic            in_sig
);

    logic [2:0] byte_off;
    logic mem_fault;
    assign byte_off = addr[2:0];

    //Full 64-bit region decode. Every access must match exactly one
    //region; anything else faults rather than landing somewhere
    logic in_dtcm, in_halt;
    assign in_dtcm = (addr >= DTCM_BASE) && (addr < (DTCM_BASE + DTCM_SIZE));
    assign in_halt = (addr == HALT_ADDR);

    assign in_sig = (addr >= SIG_BASE) && (addr < (SIG_BASE + SIG_SIZE));

    logic mapped;
    assign mapped = in_dtcm | in_halt | in_sig;

    assign access_fault_load = mem_read && !mapped;
    assign access_fault_store = mem_write && !mapped;

    assign halt_req = mem_write && in_halt;

    //A store or load that raises an exception must not reach memory. The trap
    //is detected in this same cycle , but the write would commit on this clock
    //edge, so the enable has to be suppressed combinationally
    assign mem_fault = misaligned_load | misaligned_store | access_fault_load
                        | access_fault_store;

    assign dmem_en = (mem_read | mem_write) && in_dtcm && !mem_fault;
    assign dmem_addr = addr;

    assign sigmem_en = (mem_read | mem_write) && in_sig && !mem_fault;

    //store: place the data in the right byte lanes
    always_comb begin
        dmem_wdata = '0;
        dmem_wstrb = '0;
        if (mem_write) begin
            unique case (funct3)
                3'b000: begin                           //SB
                    dmem_wdata = {56'b0, store_data[7:0]} << (8*byte_off);
                    dmem_wstrb = 8'b0000_0001 << byte_off;
                end
                3'b001: begin                           //SH
                    dmem_wdata = {48'b0, store_data[15:0]} << (8*byte_off);
                    dmem_wstrb = 8'b0000_0011 << byte_off;
                end
                3'b010: begin                           // SW
                    dmem_wdata = {32'b0, store_data[31:0]} << (8*byte_off);
                    dmem_wstrb = 8'b0000_1111 << byte_off;
                end
                3'b011: begin                           // SD
                    dmem_wdata = store_data;
                    dmem_wstrb = 8'b1111_1111;
                end
                default: ;
            endcase
        end
    end

    //Aligment: halfword needs addr[0]=0 word needs addr[1:0]=0,
    // doubleword needs addr[2:0]=0. Byte access is always aligned
    logic align_fault;
    always_comb begin
        unique case (funct3[1:0])
            2'b00: align_fault = 1'b0;      //byte
            2'b01: align_fault = addr[0];   //halfword
            2'b10: align_fault = |addr[1:0]; //word
            2'b11: align_fault = |addr[2:0];    //doubleword
            default: align_fault = 1'b0;
    endcase
    end

    assign misaligned_load = mem_read && align_fault;
    assign misaligned_store = mem_write && align_fault;

    endmodule
