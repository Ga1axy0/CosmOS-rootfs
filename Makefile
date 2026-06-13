SHELL := /bin/bash

PROJECT_ROOT := $(CURDIR)
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts
BUILD_DIR := $(PROJECT_ROOT)/build
BUILD_ROOT ?= $(BUILD_DIR)
STAMP_DIR := $(BUILD_DIR)/.stamps
ROOTFS_BASE_DIR := $(PROJECT_ROOT)/rootfs
ROOTFS_DIR ?= $(ROOTFS_BASE_DIR)
TARGET ?= riscv64-linux-musl
COMMON_LDFLAGS ?= -static

export TARGET
export CROSS_PREFIX
export TOOLCHAIN_BIN
export BUSYBOX_ARCH
export ROOTFS_DIR
export BUILD_ROOT
export JOBS
export COMMON_CFLAGS
export COMMON_CXXFLAGS
export COMMON_CPPFLAGS
export COMMON_LDFLAGS
export GLIBC_LIB
export GLIBC_TOOLCHAIN
export MUSL_LIB
export MUSL_ARCH

PRIORITY_SCRIPT := $(SCRIPTS_DIR)/build-busybox.sh
OTHER_SCRIPTS := $(filter-out $(PRIORITY_SCRIPT),$(sort $(wildcard $(SCRIPTS_DIR)/*.sh)))
SCRIPTS := $(if $(wildcard $(PRIORITY_SCRIPT)),$(PRIORITY_SCRIPT)) $(OTHER_SCRIPTS)
SCRIPT_NAMES := $(basename $(notdir $(SCRIPTS)))

.DEFAULT_GOAL := rootfs-init

.PHONY: rootfs-init prepare-rootfs list clean clean-stamps help $(SCRIPT_NAMES)

prepare-rootfs:
	@if [[ "$(ROOTFS_DIR)" != "$(ROOTFS_BASE_DIR)" && ! -d "$(ROOTFS_DIR)" ]]; then \
		if [[ ! -d "$(ROOTFS_BASE_DIR)" ]]; then \
			echo "[ERROR] base rootfs directory not found: $(ROOTFS_BASE_DIR)" >&2; \
			exit 1; \
		fi; \
		echo "[INIT] copy $(ROOTFS_BASE_DIR) -> $(ROOTFS_DIR)"; \
		mkdir -p "$$(dirname "$(ROOTFS_DIR)")"; \
		cp -a "$(ROOTFS_BASE_DIR)" "$(ROOTFS_DIR)"; \
	fi

rootfs-init: prepare-rootfs
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

$(SCRIPT_NAMES): prepare-rootfs
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
	@rm -rf "$(BUILD_DIR)" "$(ROOTFS_DIR)"
	@echo "[OK] removed rootfs build outputs"

help:
	@echo "Targets:"
	@echo "  make rootfs-init   Run all scripts in scripts/ once, tracked by build stamps"
	@echo "  make <script>      Run one script target, e.g. make build-coreutil"
	@echo "  make clean         Remove build directory and generated rootfs"
	@echo "  make list          List available script targets"
	@echo "  make clean-stamps  Remove build stamps so scripts will run again"
