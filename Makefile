SHELL := /bin/bash

PROJECT_ROOT := $(CURDIR)
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts
BUILD_DIR := $(PROJECT_ROOT)/build
STAMP_DIR := $(BUILD_DIR)/.stamps
TARGET ?= riscv64-linux-musl
COMMON_LDFLAGS ?= -static

export TARGET
export CROSS_PREFIX
export TOOLCHAIN_BIN
export JOBS
export COMMON_CFLAGS
export COMMON_CXXFLAGS
export COMMON_CPPFLAGS
export COMMON_LDFLAGS

PRIORITY_SCRIPT := $(SCRIPTS_DIR)/build-busybox.sh
OTHER_SCRIPTS := $(filter-out $(PRIORITY_SCRIPT),$(sort $(wildcard $(SCRIPTS_DIR)/*.sh)))
SCRIPTS := $(if $(wildcard $(PRIORITY_SCRIPT)),$(PRIORITY_SCRIPT)) $(OTHER_SCRIPTS)
SCRIPT_NAMES := $(basename $(notdir $(SCRIPTS)))

.DEFAULT_GOAL := rootfs-init

.PHONY: rootfs-init list clean clean-stamps help $(SCRIPT_NAMES)

rootfs-init:
	@mkdir -p "$(STAMP_DIR)"
	@for script in $(SCRIPTS); do \
		name="$$(basename "$$script" .sh)"; \
		stamp="$(STAMP_DIR)/$$name.stamp"; \
		if [[ -f "$$stamp" && "$$stamp" -nt "$$script" ]]; then \
			echo "[SKIP] $$name ($(STAMP_DIR))"; \
			continue; \
		fi; \
		echo "[RUN] $$script"; \
		bash "$$script"; \
		touch "$$stamp"; \
		echo "[DONE] $$stamp"; \
	done
	@echo "[OK] rootfs init complete"

$(SCRIPT_NAMES):
	@mkdir -p "$(STAMP_DIR)"
	@script="$(SCRIPTS_DIR)/$@.sh"; \
	stamp="$(STAMP_DIR)/$@.stamp"; \
	if [[ -f "$$stamp" && "$$stamp" -nt "$$script" ]]; then \
		echo "[SKIP] $@ ($(STAMP_DIR))"; \
	else \
		echo "[RUN] $$script"; \
		bash "$$script"; \
		touch "$$stamp"; \
		echo "[DONE] $$stamp"; \
	fi

list:
	@printf '%s\n' $(SCRIPT_NAMES)

clean-stamps:
	@rm -rf "$(STAMP_DIR)"
	@echo "[OK] removed $(STAMP_DIR)"

clean:
	@rm -rf "$(BUILD_DIR)" "$(PROJECT_ROOT)/rootfs"
	@echo "[OK] removed rootfs build outputs"

help:
	@echo "Targets:"
	@echo "  make rootfs-init   Run all scripts in scripts/ once, tracked by build stamps"
	@echo "  make <script>      Run one script target, e.g. make build-coreutil"
	@echo "  make clean         Remove build directory and generated rootfs"
	@echo "  make list          List available script targets"
	@echo "  make clean-stamps  Remove build stamps so scripts will run again"
