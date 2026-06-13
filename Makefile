SHELL := /bin/bash

PROJECT_ROOT := $(CURDIR)
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts
COMMON_SCRIPT := $(SCRIPTS_DIR)/common-musl-env.sh
BUILD_DIR := $(PROJECT_ROOT)/build
BUILD_ROOT ?= $(BUILD_DIR)
STAMP_DIR := $(BUILD_DIR)/.stamps
ROOTFS_BASE_DIR := $(PROJECT_ROOT)/rootfs
ROOTFS_DIR ?= $(ROOTFS_BASE_DIR)
ROOTFS_RV_DIR ?= $(PROJECT_ROOT)/rootfs-rv
ROOTFS_LA_DIR ?= $(PROJECT_ROOT)/rootfs-la
ROOTFS_RV_BUILD_DIR ?= $(BUILD_DIR)/rv
ROOTFS_LA_BUILD_DIR ?= $(BUILD_DIR)/la
ROOTFS_RV_STAMP_DIR ?= $(BUILD_DIR)/.stamps-rv
ROOTFS_LA_STAMP_DIR ?= $(BUILD_DIR)/.stamps-la
TARGET ?= riscv64-linux-musl
RV_ROOTFS_TARGET ?= riscv64-linux-musl
RV_TOOLCHAIN_BIN ?= /opt/riscv64-linux-musl-cross/bin
RV_GLIBC_LIB ?= /usr/riscv64-linux-gnu/lib
RV_MUSL_LIB ?= /opt/riscv64-linux-musl-cross/riscv64-linux-musl/lib
RV_MUSL_ARCH ?= riscv64
LA_ROOTFS_TARGET ?= loongarch64-linux-musl
LA_TOOLCHAIN_BIN ?= /opt/loongarch64-linux-musl-cross/bin
LA_GLIBC_TOOLCHAIN ?= /opt/gcc-13.2.0-loongarch64-linux-gnu
LA_MUSL_LIB ?= /opt/loongarch64-linux-musl-cross/loongarch64-linux-musl/lib
LA_MUSL_ARCH ?= loongarch64
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
ACCOUNT_SCRIPT := $(SCRIPTS_DIR)/build-shadow.sh
HELPER_SCRIPTS := $(COMMON_SCRIPT)
OTHER_SCRIPTS := $(filter-out $(PRIORITY_SCRIPT) $(ACCOUNT_SCRIPT) $(HELPER_SCRIPTS),$(sort $(wildcard $(SCRIPTS_DIR)/*.sh)))
SCRIPTS := $(if $(wildcard $(PRIORITY_SCRIPT)),$(PRIORITY_SCRIPT)) $(OTHER_SCRIPTS) $(if $(wildcard $(ACCOUNT_SCRIPT)),$(ACCOUNT_SCRIPT))
SCRIPT_NAMES := $(basename $(notdir $(SCRIPTS)))
SCRIPT_RV_TARGETS := $(addsuffix -rv,$(SCRIPT_NAMES))
SCRIPT_LA_TARGETS := $(addsuffix -la,$(SCRIPT_NAMES))

.DEFAULT_GOAL := rootfs-init

.PHONY: rootfs-init prepare-rootfs list clean clean-stamps help _run-script $(SCRIPT_NAMES) $(SCRIPT_RV_TARGETS) $(SCRIPT_LA_TARGETS)

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
		if [[ -f "$$stamp" && "$$stamp" -nt "$$script" && "$$stamp" -nt "$(COMMON_SCRIPT)" ]]; then \
			echo "[SKIP] $$name ($(STAMP_DIR))"; \
			continue; \
		fi; \
		echo "[RUN] $$script"; \
		bash "$$script" || exit $$?; \
		touch "$$stamp"; \
		echo "[DONE] $$stamp"; \
	done
	@echo "[OK] rootfs init complete"

$(SCRIPT_NAMES): %: %-rv %-la

$(SCRIPT_RV_TARGETS): %-rv:
	$(MAKE) _run-script \
		SCRIPT_NAME="$*" \
		ROOTFS_DIR="$(ROOTFS_RV_DIR)" \
		BUILD_ROOT="$(ROOTFS_RV_BUILD_DIR)" \
		STAMP_DIR="$(ROOTFS_RV_STAMP_DIR)" \
		TARGET="$(RV_ROOTFS_TARGET)" \
		TOOLCHAIN_BIN="$(RV_TOOLCHAIN_BIN)" \
		BUSYBOX_ARCH=riscv \
		GLIBC_LIB="$(RV_GLIBC_LIB)" \
		MUSL_LIB="$(RV_MUSL_LIB)" \
		MUSL_ARCH="$(RV_MUSL_ARCH)"

$(SCRIPT_LA_TARGETS): %-la:
	$(MAKE) _run-script \
		SCRIPT_NAME="$*" \
		ROOTFS_DIR="$(ROOTFS_LA_DIR)" \
		BUILD_ROOT="$(ROOTFS_LA_BUILD_DIR)" \
		STAMP_DIR="$(ROOTFS_LA_STAMP_DIR)" \
		TARGET="$(LA_ROOTFS_TARGET)" \
		TOOLCHAIN_BIN="$(LA_TOOLCHAIN_BIN)" \
		BUSYBOX_ARCH=loongarch64 \
		GLIBC_TOOLCHAIN="$(LA_GLIBC_TOOLCHAIN)" \
		MUSL_LIB="$(LA_MUSL_LIB)" \
		MUSL_ARCH="$(LA_MUSL_ARCH)"

_run-script: prepare-rootfs
	@mkdir -p "$(STAMP_DIR)"
	@test -n "$(SCRIPT_NAME)" || { echo "[ERROR] SCRIPT_NAME is required" >&2; exit 2; }
	@script="$(SCRIPTS_DIR)/$(SCRIPT_NAME).sh"; \
	stamp="$(STAMP_DIR)/$(SCRIPT_NAME).stamp"; \
	test -f "$$script" || { echo "[ERROR] script not found: $$script" >&2; exit 2; }; \
	if [[ -f "$$stamp" && "$$stamp" -nt "$$script" && "$$stamp" -nt "$(COMMON_SCRIPT)" ]]; then \
		echo "[SKIP] $(SCRIPT_NAME) ($(STAMP_DIR))"; \
	else \
		echo "[RUN] $$script"; \
		bash "$$script" || exit $$?; \
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
	@echo "  make <script>      Build one package into rootfs-rv and rootfs-la"
	@echo "  make <script>-rv   Build one package into rootfs-rv only"
	@echo "  make <script>-la   Build one package into rootfs-la only"
	@echo "  make clean         Remove build directory and generated rootfs"
	@echo "  make list          List available script targets"
	@echo "  make clean-stamps  Remove build stamps so scripts will run again"
