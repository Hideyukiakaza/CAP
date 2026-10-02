# CAP Programming Language (v0.1.0)

CAP is a compiled systems programming language featuring Python-like syntax, dynamic runtime type tagging, and direct machine code emission into ELF executables without intermediate compiler passes or LLVM.

## Table of Contents
- [1. Vision and Goals](#1-vision-and-goals)
- [2. Quick Example](#2-quick-example)
- [3. Installation](#3-installation)
- [4. Using the Compiler](#4-using-the-compiler)
- [5. Language Reference Summary](#5-language-reference-summary)
- [6. Freestanding and Kernel Mode](#6-freestanding-and-kernel-mode)
- [7. Error Reference](#7-error-reference)
- [8. Platform Support](#8-platform-support)
- [9. Known Limitations and Roadmap](#9-known-limitations-and-roadmap)
- [10. Project Layout and Building](#10-project-layout-and-building)

---

## 1. Vision and Goals

**Project Vision:** Combine readable, white-space sensitive syntax with direct bare-metal hardware control, fast native compilation, and embedded assembly support.

**Project Goals (Not Claims):**
- *Goal:* Achieve high compiler throughput by emitting direct machine code without heavy middle-end IR optimization passes.
- *Goal:* Provide seamless inline assembly (`asm:`) with zero compiler frame overhead for OS kernels and drivers.
- *Goal:* Keep the core toolchain self-contained in pure NASM x86-64 assembly without external C runtime dependencies.

**Current Status:** Release `v0.1.0` (Alpha) targeting Linux x86-64 hosts.

---

## 2. Quick Example

Source file (`docs/examples/01_hello.cap`):
```cap
fn main():
    print("Hello, CAP v0.1.0!")
    return 0
```

Compile and run:
```bash
./capc -o hello docs/examples/01_hello.cap
./hello
```

Actual output:
```
Hello, CAP v0.1.0!
```

---

## 3. Installation

Detailed guide in [docs/GUIDE.md](docs/GUIDE.md).

### Prerequisites (Ubuntu 24.04 LTS)
```bash
sudo apt update && sudo apt install -y nasm binutils make qemu-system-x86 qemu-user
```

### Build from Source
```bash
git clone https://github.com/Hideyukiakaza/cap.git
cd cap
make clean && make
./capc --version
```

---

## 4. Using the Compiler

Command-line syntax:
```
capc [-a] [--freestanding|-k] [--boot-thin] [--no-boot-stub] [-o <outfile>] [--dump-ast] [--dump-tokens] [-v|--version] <filename.cap>
```

### Command-Line Flags
- `-o <outfile>`: Specify output binary filename (defaults to input basename without `.cap`).
- `-a`: Select ARM64 hosted target architecture (`qemu-aarch64` runner).
- `--freestanding` or `-k`: Select freestanding bare-metal target (Multiboot2 x86-64 image loaded at `0x100000`).
- `--boot-thin`: Select thin Multiboot1/2 handoff header (512 bytes) without built-in serial or IDT exception stubs (requires `--freestanding` or `-k`).
- `--no-boot-stub`: Emit bare ELF64 executable with `e_entry` pointing directly at `main()`.
- `--dump-ast`: Print AST node hierarchy and exit.
- `--dump-tokens`: Print lexer token stream debug output and exit.
- `-v` or `--version`: Print `capc 0.1.0` and exit 0.

### Reserved Exit Codes
- `0`: Successful compilation or CLI flag execution.
- `1`: Compile-time error (LexerError, SyntaxError, NameError, TypeError) or CLI usage error.
- `101`: Runtime trap (division by zero, integer overflow, type mismatch).

---

## 5. Language Reference Summary

Full specification available in [docs/LANGUAGE.md](docs/LANGUAGE.md).

### Functions and Parameters
```cap
fn add(a, b):
    return a + b

fn main():
    x = 10
    y = 20
    sum = add(x, y)
    print(f"Sum: {sum}")
    return 0
```

### Structs
Struct parameter declarations require explicit type annotations:
```cap
struct Point:
    x: int
    y: int

fn main():
    p = Point{x: 5, y: 12}
    print(f"Point x={p.x}, y={p.y}")
    return 0
```

### Control Flow
```cap
fn main():
    x = 10
    if x > 5:
        print("Greater than 5")
    else:
        print("Less or equal")
    return 0
```

### Bitwise Operators
```cap
fn main():
    a = 0b1100
    b = 0b1010
    and_val = a & b
    or_val = a | b
    xor_val = a ^ b
    shl_val = a << 2
    print(f"AND: {and_val}, OR: {or_val}, XOR: {xor_val}, SHL: {shl_val}")
    return 0
```

### Inline Assembly (`asm:`)
```cap
fn main():
    asm:
        mov rax, 0x383420310A
    print("ASM block executed")
    return 0
```

### Memory Management (`alloc`/`defer`/`free`)
```cap
fn main():
    ptr = alloc(16)
    print("Allocated memory successfully")
    return 0
```

---

## 6. Freestanding and Kernel Mode

Freestanding mode generates raw bare-metal images bootable under QEMU system emulation:

```cap
fn main():
    asm:
        mov dx, 0x3F8
        mov al, 0x48
        out dx, al
    return 0
```

Compile and boot in QEMU:
```bash
./capc --freestanding -o kernel.bin docs/examples/08_freestanding.cap
qemu-system-x86_64 -kernel kernel.bin -serial stdio -display none -no-reboot
```

### Exception Printer Format
When an unhandled exception occurs in standard freestanding mode, the kernel printer emits serial log lines over port `0x3F8`:
```
EXCEPTION: vector=0 err=0x0000000000000000 rip=0x0000000000100D64
```

---

## 7. Error Reference

Complete diagnostic rules in [spec/errors.md](spec/errors.md).

| Error Class | Format | Cause |
|---|---|---|
| `LexerError` | `LexerError: malformed numeric literal '<spelling>' (line <L>)` | Bad digit or `_` placement |
| `LexerError` | `LexerError: integer literal '<spelling>' out of range (line <L>)` | Decimal literal > `9223372036854775807` |
| `LexerError` | `LexerError: hex literal '<spelling>' exceeds 64 bits (line <L>)` | Hex token > 16 digits |
| `SyntaxError` | `SyntaxError: <description> (line <L>)` | Grammar/indentation rule violation |
| `NameError` | `NameError: undefined name '<var>' (line <L>)` | Reference before definition |
| `TypeError` | `TypeError: struct '<name>' has no field '<field>' (line <L>)` | Invalid field access |

---

## 8. Platform Support

Detailed instructions in [docs/PLATFORMS.md](docs/PLATFORMS.md).

| Host Platform | Support Status | Method |
|---|---|---|
| Linux x86-64 (Ubuntu 24.04+) | Supported | Native |
| Windows 10/11 x86-64 | Supported | WSL2 / Docker |
| macOS (Intel / Apple Silicon) | Supported | Docker (`--platform linux/amd64`) |

---

## 9. Known Limitations and Roadmap

### Known Limitations
1. **Flow-Insensitive Variable Check:** Variable definition analysis is flow-insensitive; assigning a variable inside a conditional branch marks it as defined across the whole function body.
2. **QEMU RIP Report on Non-Canonical `ret`:** QEMU's x86_64 CPU model records the target non-canonical address on the `#GP` stack frame upon `ret` to non-canonical space; real hardware behavior is unverified and not guaranteed.
3. **Freestanding Mode Restricted Builtins:** `print`, `input`, and `alloc` produce compile-time errors in freestanding mode.

### Roadmap (Unpromised Project Directions)
- Native macOS and Windows executable backends.
- Direct AArch64 host compiler binary.
- Floating-point arithmetic and full standard library.

---

## 10. Project Layout and Building

### Directory Structure
- `src/`: NASM compiler source files.
- `spec/`: Core language specifications and error documentation.
- `docs/`: User guides, platform matrix, portability notes, and verified examples.
- `tests/`: Frontend, codegen, freestanding, doc, and CLI test runners.

### Running Test Suites
```bash
./tests/frontend/run_tests.sh
./tests/codegen/run_tests.sh
./tests/freestanding/run_tests.sh
./tests/docs/run_tests.sh
./tests/cli/run_tests.sh
```

### License
Licensed under the [Apache License, Version 2.0](LICENSE).
Copyright 2026 Hideyukiakaza.
