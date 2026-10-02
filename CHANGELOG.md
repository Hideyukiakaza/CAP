# CHANGELOG

## [0.1.0] - 2026-09-29

Initial alpha release of CAP for Linux x86-64.

### Added
- Native x86-64 direct machine code emitter (`capc`) written in NASM assembly.
- Target architectures: Hosted Linux x86-64 (default), Hosted Linux ARM64 (`-a`), Freestanding bare-metal (`--freestanding` / `-k`), Thin boot freestanding (`--boot-thin`), and No-boot-stub ELF64 (`--no-boot-stub`).
- Lexer and parser supporting Python-style indentation, functions, variables, structs, control flow (`if`/`elif`/`else`, `while`, `loop`, `for` with `range`), `asm:` blocks, `alloc`/`defer`/`free`, f-strings, bitwise operators, and unary address-of function operator (`&fn`).
- Single-pass direct ELF64 executable generation without intermediate compiler infrastructure.
- Comprehensive test suites covering frontend parsing (36 tests), direct code generation & execution (76 tests), freestanding bare-metal booting under QEMU (19 tests), and CLI / documentation examples.
