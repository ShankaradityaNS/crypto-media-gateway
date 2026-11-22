VERILATOR	 = verilator
RTL_DIR		 = ../rtl
TOP 		 = gateway_top

VFLAGS = --cc --exe --build --trace -Wall
VFLAGS += -Wno-fatal
VFLAGS += --top-module $(TOP)
VFLAGS += -Mdir obj_dir

SRCS = $(RTL_DIR)/sram_bank.sv $(RTL_DIR)/exit_fsm.sv \
		$(RTL_DIR)/exit_packer.sv $(RTL_DIR)/$(TOP).sv

all: obj_dir/V$(TOP)

obj_dir/V$(TOP): $(SRCS) tb_gateway.cpp
	$(VERILATOR) $(VFLAGS) $(SRCS) tb_gateway.cpp

run: obj_dir/V$(TOP)
	./obj_dir/V$(TOP)

wave: run
	gtkwave wave.vcd &

clean:
	rm -rf obj_dir wave.vcd