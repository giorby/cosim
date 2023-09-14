# Output directory:
OUT_DIR := /tmp/test

# Source files common to all targets:
SRC_FILES := platform.c fastuart.c
LD_SCRIPT := fpga.ld

# Optimization flags
OPT := -O3 -g3 -flto
CPU := -mcpu=cortex-a9 -mfloat-abi=hard -mfpu=fpv4-sp-d16
#CPU += -mthumb -mabi=aapcs

# Compiler flags
CFLAGS += $(OPT) $(CPU)
CFLAGS += -Wall
CFLAGS += -ffunction-sections -fdata-sections -fno-strict-aliasing
CFLAGS += -fno-builtin -fshort-enums

# Linker flags
LDFLAGS += -DBUILD_TIMESTAMP=$(shell date -Iseconds) build_date.c
LDFLAGS += $(OPT) $(CPU)
LDFLAGS += $(LD_SCRIPT)
LDFLAGS += -Wl,--gc-sections
LDFLAGS += --specs=nano.specs
LDFLAGS += -lc -lnosys -lm


.PHONY: default

# Default target:
default: $(OUT_DIR)/loop.elf $(OUT_DIR)/user.elf

$(OUT_DIR)/loop.elf: test-bfm.c $(SRC_FILES)
	arm-none-eabi-gcc $(CFLAGS) $< $(SRC_FILES) $(LDFLAGS) -o $@

$(OUT_DIR)/user.elf: test-pty.c $(SRC_FILES)
	arm-none-eabi-gcc $(CFLAGS) $< $(SRC_FILES) $(LDFLAGS) -o $@

