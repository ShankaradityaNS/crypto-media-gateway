VERILATOR = verilator
RTL = ../rtl/core
VFLAGS = --cc --exe --build --trace -Wall -Wno-EOFNEWLINE -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Mdir obj_dir

regfile:
	$(VERILATOR) $(VFLAGS) --top-module regfile \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/regfile.sv tb_regfile.cpp
	./obj_dir/Vregfile

fetch:
	$(VERILATOR) $(VFLAGS) --top-module if_tb_top \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/tcm.sv $(RTL)/core_if.sv $(RTL)/if_tb_top.sv \
		tb_if.cpp
	./obj_dir/Vif_tb_top +imem=imem.hex

imm:
	$(VERILATOR) $(VFLAGS) --top-module core_imm \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_imm.sv tb_imm.cpp
	./obj_dir/Vcore_imm

decode:
	$(VERILATOR) $(VFLAGS) --top-module core_id \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_imm.sv $(RTL)/core_id.sv tb_decode.cpp
	./obj_dir/Vcore_id

execute:
	$(VERILATOR) $(VFLAGS) --top-module core_ex \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_ex.sv tb_ex.cpp
	./obj_dir/Vcore_ex

writeback:
	$(VERILATOR) $(VFLAGS) --top-module core_wb \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_wb.sv tb_wb.cpp
	./obj_dir/Vcore_wb

hazard:
	$(VERILATOR) $(VFLAGS) --top-module core_hazard \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_hazard.sv tb_hazard.cpp
	./obj_dir/Vcore_hazard

core:
	$(VERILATOR) $(VFLAGS) --trace-structs --top-module core_top \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/tcm.sv $(RTL)/dmem.sv \
		$(RTL)/core_if.sv $(RTL)/core_imm.sv $(RTL)/core_id.sv \
		$(RTL)/core_ex.sv $(RTL)/core_mem.sv $(RTL)/core_wb.sv \
		$(RTL)/core_hazard.sv $(RTL)/regfile.sv $(RTL)/core_top.sv \
		$(RTL)/core_csr.sv $(RTL)/core_trap.sv \
		tb_core.cpp
	./obj_dir/Vcore_top +imem=prog.hex

csr:
	$(VERILATOR) $(VFLAGS) --top-module core_csr \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_csr.sv tb_csr.cpp
	./obj_dir/Vcore_csr

trap:
	$(VERILATOR) $(VFLAGS) --top-module core_trap \
	    $(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_trap.sv tb_trap.cpp
	./obj_dir/Vcore_trap

tcm:
	$(VERILATOR) $(VFLAGS) --top-module tcm \
		$(RTL)/tcm.sv tb_tcm.cpp
	./obj_dir/Vtcm

lint:
	$(VERILATOR) --lint-only -Wall -Wno-EOFNEWLINE -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
	    --top-module core_top \
	    $(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/tcm.sv $(RTL)/dmem.sv \
	    $(RTL)/core_if.sv $(RTL)/core_imm.sv $(RTL)/core_id.sv \
	    $(RTL)/core_ex.sv $(RTL)/core_mem.sv $(RTL)/core_wb.sv \
	    $(RTL)/core_hazard.sv $(RTL)/core_csr.sv $(RTL)/core_trap.sv \
	    $(RTL)/regfile.sv $(RTL)/core_top.sv 

memory:
	verilator --cc --exe --build --trace -Wall -Wno-EOFNEWLINE \
	    -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Mdir obj_dir --top-module core_mem \
	    ../rtl/core/cmg_config.sv ../rtl/core/core_pkg.sv ../rtl/core/core_mem.sv \
	    tb_mem.cpp
	./obj_dir/Vcore_mem

riscv:
	verilator --cc --exe --build --trace -Wall -Wno-EOFNEWLINE -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Mdir obj_dir_riscv --top-module core_top \
		../rtl/core/cmg_config.sv ../rtl/core/core_pkg.sv ../rtl/core/tcm.sv ../rtl/core/dmem.sv \
		../rtl/core/core_if.sv ../rtl/core/core_imm.sv ../rtl/core/core_id.sv \
		../rtl/core/core_ex.sv ../rtl/core/core_mem.sv ../rtl/core/core_wb.sv \
		../rtl/core/core_hazard.sv ../rtl/core/regfile.sv ../rtl/core/core_top.sv \
		../rtl/core/core_csr.sv ../rtl/core/core_trap.sv \
		tb_riscv.cpp

ctest:
	verilator --cc --exe --build --trace -Wall -Wno-EOFNEWLINE -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Mdir obj_dir_ctest --top-module core_top \
		../rtl/core/cmg_config.sv ../rtl/core/core_pkg.sv ../rtl/core/tcm.sv ../rtl/core/dmem.sv \
		../rtl/core/core_if.sv ../rtl/core/core_imm.sv ../rtl/core/core_id.sv \
		../rtl/core/core_ex.sv ../rtl/core/core_mem.sv ../rtl/core/core_wb.sv \
		../rtl/core/core_hazard.sv ../rtl/core/regfile.sv ../rtl/core/core_top.sv \
		../rtl/core/core_csr.sv ../rtl/core/core_trap.sv \
		tb_ctest.cpp

slotcsr:
	$(VERILATOR) $(VFLAGS) --top-module core_csr \
		$(RTL)/cmg_config.sv $(RTL)/core_pkg.sv $(RTL)/core_csr.sv tb_slotcsr.cpp
	./obj_dir/Vcore_csr

clean:
	rm -rf obj_dir wave.vcd