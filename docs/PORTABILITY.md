# CAP Portability Note

This document outlines the system dependencies and OS-specific components of the CAP compiler (`capc`) v0.1.1.

## Linux x86-64 Host Dependencies

1. **Linux Syscalls:**
   - The compiler uses raw x86-64 Linux system calls for file and console I/O (`sys_open` [2], `sys_read` [0], `sys_write` [1], `sys_close` [3], `sys_exit` [60]). Implementation is located in `src/utils.asm`.

2. **ELF Writer:**
   - Output binary generation produces 64-bit System V ELF executables (`ET_EXEC`) in `src/output/elf_writer.asm`.

3. **Toolchain & Linker:**
   - The compiler build relies on NASM (`nasm -f elf64`) and the GNU linker (`ld`) via `Makefile`.

4. **Test Runners:**
   - Test suites utilize Bash scripts (`tests/frontend/run_tests.sh`, `tests/codegen/run_tests.sh`, `tests/freestanding/run_tests.sh`, `tests/docs/run_tests.sh`, `tests/cli/run_tests.sh`) relying on standard POSIX/GNU utilities (`diff`, `sed`, `timeout`, `qemu-system-x86_64`, `qemu-aarch64`).

*Note:* Porting to other host operating systems (e.g. macOS or Windows) requires either running under virtualization / containerization (WSL2 / Docker) or rewriting the OS system interface layer and executable binary generator.
