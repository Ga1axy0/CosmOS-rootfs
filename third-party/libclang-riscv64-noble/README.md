# RISC-V libclang runtime

These `.deb` archives are the RISC-V packages for LLVM 18 and its runtime
dependency closure from the official Ubuntu 24.04 (Noble) ports repository:

<https://ports.ubuntu.com/ubuntu-ports/>

`SHA256SUMS` is derived from the Noble and Noble Updates `Packages` indexes.
The rootfs build verifies every archive before extracting it; no network
access or guest-side package manager is required.

Install it into the RISC-V rootfs with:

```sh
make build-libclang-riscv64-rv
```

It is also enabled by default when `WITH_RUST=1`. Set `WITH_LIBCLANG=0` to
exclude it from `rootfs-init`.
