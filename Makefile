# Starship Project
# Copyright (C) 2021 by phantom
# Email: phantom@zju.edu.cn
# This file is under MIT License, see https://www.phvntom.tech/LICENSE.txt

TARGET_FPGA ?= a7
TARGET_CORE := axizjv
SUPPORTED_BOARDS := vc707 a7

TOP			:= $(CURDIR)
SRC			:= $(TOP)/repo
BUILD		:= $(TOP)/build/$(TARGET_FPGA)
CONFIG		:= $(TOP)/conf
SBT_BUILD 	:= $(TOP)/target $(TOP)/project/target $(TOP)/project/project
ZJV_SRC     := $(SRC)/ZJV2
ZJV_RSRC    := $(SRC)/ZJV2/src/main/resources/platform/rocket/build.sbt

ifndef RISCV
$(error $$RISCV is undefined, please set $$RISCV to your riscv-toolchain)
endif

ifeq ($(filter $(TARGET_FPGA),$(SUPPORTED_BOARDS)),)
$(error $(TARGET_FPGA) is not supported yet. Choose one from $(SUPPORTED_BOARDS))
endif

all: bitstream

#######################################
#                                      
#         Board Args Mapper
#                                      
#######################################

freq_a7     := 50
freq_vc707  := 100

szmem_a7    := 128
szmem_vc707 := 1024

board_a7    := nexys_a7
board_vc707 := vc707

core_rocket := TLRocket
core_axizjv := AXIZJV

#######################################
#                                      
#         Verilog Generator
#                                      
#######################################

TARGET_FPGA_UP  := $(shell echo $(TARGET_FPGA) | tr '[:lower:]' '[:upper:]')
ROCKET_SRC		:= $(SRC)/rocket-chip
ROCKET_BUILD	:= $(BUILD)/rocket-chip
ROCKET_JVM_MEM	?= 2G
ROCKET_JAVA		:= java -Xmx$(ROCKET_JVM_MEM) -Xss8M -jar $(ROCKET_SRC)/sbt-launch.jar
ROCKET_TOP_PROJ	?= starship.fpga
ROCKET_TOP		?= TestHarness$(TARGET_FPGA_UP)
ROCKET_CON_PROJ	?= starship.fpga
ROCKET_CONFIG	?= $(core_$(TARGET_CORE))Config
ROCKET_FREQ     ?= $(freq_$(TARGET_FPGA))
ROCKET_SZMEM    ?= $(szmem_$(TARGET_FPGA))
ROCKET_OUTPUT	:= $(ROCKET_TOP_PROJ).$(ROCKET_TOP).$(ROCKET_CONFIG)
ROCKET_VERILOG	:= $(ROCKET_BUILD)/$(ROCKET_OUTPUT).v
ROCKET_FIRRTL	:= $(ROCKET_BUILD)/$(ROCKET_OUTPUT).fir
PROJECT_CONFIG  := $(ROCKET_CON_PROJ).$(ROCKET_CONFIG),
PROJECT_CONFIG  := $(PROJECT_CONFIG)$(ROCKET_CON_PROJ).With$(ROCKET_FREQ)MHz,
PROJECT_CONFIG  := $(PROJECT_CONFIG)$(ROCKET_CON_PROJ).With$(ROCKET_SZMEM)MB,
PROJECT_CONFIG  := $(PROJECT_CONFIG)$(ROCKET_CON_PROJ).With$(TARGET_FPGA_UP)

define swap_sbt_fwd
	mv $(ZJV_SRC)/build.sbt $(ZJV_SRC)/build.sbt.original
	cp $(ZJV_RSRC) $(ZJV_SRC)/build.sbt
endef

define swap_sbt_back
	rm $(ZJV_SRC)/build.sbt
	mv $(ZJV_SRC)/build.sbt.original $(ZJV_SRC)/build.sbt
endef

$(ROCKET_FIRRTL): 
	mkdir -p $(ROCKET_BUILD)
	$(call swap_sbt_fwd)
	if $(ROCKET_JAVA) "runMain freechips.rocketchip.system.Generator	\
					-td $(ROCKET_BUILD) -T $(ROCKET_TOP_PROJ).$(ROCKET_TOP)	\
					-C  $(PROJECT_CONFIG) \
					-n $(ROCKET_OUTPUT)"; then \
		echo FIRRTLized; \
	fi
	$(call swap_sbt_back)

$(ROCKET_VERILOG): $(ROCKET_FIRRTL)
	mkdir -p $(ROCKET_BUILD)
	$(call swap_sbt_fwd)
	if $(ROCKET_JAVA) "runMain firrtl.stage.FirrtlMain	\
					-td $(ROCKET_BUILD) --infer-rw $(ROCKET_TOP) \
					--repl-seq-mem -c:$(ROCKET_TOP):-o:$(ROCKET_BUILD)/$(ROCKET_OUTPUT).sram.conf \
					-faf $(ROCKET_BUILD)/$(ROCKET_OUTPUT).anno.json \
					-fct firrtl.passes.InlineInstances \
					-i $< -o $@ -X verilog"; then \
		echo VERILOGged; \
	fi
	$(call swap_sbt_back)

verilog: $(ROCKET_VERILOG)

#######################################
#
#         Bitstream Generator
#
#######################################

FIRMWARE_SRC	:= $(TOP)/firmware
FIRMWARE_BUILD	:= $(BUILD)/firmware
FSBL_SRC		:= $(FIRMWARE_SRC)/fsbl
FSBL_BUILD		:= $(FIRMWARE_BUILD)/fsbl
STARSHIP_ROM_HEX := $(FSBL_BUILD)/sdboot.hex

BOARD_NAME          := $(board_$(TARGET_FPGA))
SCRIPT_SRC			:= $(SRC)/fpga-shells
VIVADO_SRC			:= $(SCRIPT_SRC)/xilinx
VIVADO_BUILD		:= $(BUILD)/vivado
VIVADO_BITSTREAM 	:= $(VIVADO_BUILD)/$(ROCKET_OUTPUT).bit
VERILOG_SRAM		:= $(ROCKET_BUILD)/$(ROCKET_OUTPUT).behav_srams.v
VERILOG_ROM			:= $(ROCKET_BUILD)/$(ROCKET_OUTPUT).rom.v
VERILOG_INCLUDE 	:= $(VIVADO_BUILD)/$(ROCKET_OUTPUT).vsrc.f
VERILOG_SRC			:= $(VERILOG_SRAM) \
					   $(VERILOG_ROM) \
					   $(STARSHIP_ROM_HEX) \
					   $(ROCKET_BUILD)/$(ROCKET_OUTPUT).v \
					   $(ROCKET_BUILD)/plusarg_reader.v \
					   $(ROCKET_BUILD)/dual_port_bram.v \
					   $(ROCKET_BUILD)/single_port_bram.v \
					   $(VIVADO_SRC)/vc707/vsrc/sdio.v \
					   $(VIVADO_SRC)/vc707/vsrc/vc707reset.v \
					   $(SCRIPT_SRC)/testbench/SimTestHarness.v
$(VERILOG_INCLUDE):
	mkdir -p $(VIVADO_BUILD)
	echo $(VERILOG_SRC) > $@

$(VERILOG_SRAM):
	$(ROCKET_SRC)/scripts/vlsi_mem_gen $(ROCKET_BUILD)/$(ROCKET_OUTPUT).sram.conf >> $@

$(STARSHIP_ROM_HEX):
	$(MAKE) -C $(FSBL_SRC) TARGET_FPGA=$(TARGET_FPGA) PBUS_CLK=$(ROCKET_FREQ)000000 ROOT_DIR=$(TOP) ROCKET_OUTPUT=$(ROCKET_OUTPUT) hex

$(VERILOG_ROM): $(STARSHIP_ROM_HEX)
	$(ROCKET_SRC)/scripts/vlsi_rom_gen $(ROCKET_BUILD)/$(ROCKET_OUTPUT).rom.conf $< > $@

$(VIVADO_BITSTREAM): $(ROCKET_VERILOG) $(VERILOG_INCLUDE) $(VERILOG_SRAM) $(VERILOG_ROM)
	mkdir -p $(VIVADO_BUILD)
	cd $(VIVADO_BUILD); vivado -mode batch -nojournal \
		-source $(VIVADO_SRC)/common/tcl/vivado.tcl \
		-tclargs -F "$(VERILOG_INCLUDE)" \
		-top-module "$(ROCKET_TOP)" \
		-ip-vivado-tcls "$(shell find '$(ROCKET_BUILD)' -name '*.vivado.tcl')" \
		-board "$(BOARD_NAME)"

bitstream: $(VIVADO_BITSTREAM)

#######################################
#
#               Utils
#
#######################################

clean:
	rm -rf $(TOP)/build $(SBT_BUILD)