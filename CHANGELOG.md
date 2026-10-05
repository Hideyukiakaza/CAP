# CHANGELOG

## [0.1.1] - 2026-10-03

### Added
- Hosted top-level statement desugaring (implicit `main` wrapper) for executable top-level scripts.
- Implicit return 0 for non-naked hosted functions.
- Shorthand count syntax for `for` loops (`for i in count:` / `for i in expr:` as shorthand for `range(expr)`).
- `break` statement support inside `for`, `while`, and `loop` constructs with semantic validation disallowing `break` outside loops.
- F-string expression span scanning inside `{...}` supporting nested string literals, parentheses, braces, and stray `:` error detection.
- C-Style ternary conditional operator `cond ? a : b` with right-associativity, lazy branch evaluation, string and integer truthiness checks, and result tag preservation.
- Differential test runner `tests/diff/run_diff.py` verifying x86-64 and ARM64 output equivalence.
- Bumped compiler version string to `capc 0.1.1`.

### Fixed
- Fixed arithmetic type check to apply to the left operand as well as the right operand on x86-64 and ARM64.
- Fixed `break` jump target resolution in nested loops and multiple `break` statements.
- Fixed x86-64 `.s_for` stack frame isolation to prevent register corruption during statement code generation.
- Fixed error message for freestanding mode missing `main` to `SyntaxError: freestanding targets require 'fn main()' or 'naked fn main()' (line 1)`.
- Standardized lexer unexpected character error message format to `LexerError: unexpected character '<char>' (line <L>)`.

### Notes
- Freestanding mode (`--freestanding`, `--boot-thin`, `--no-boot-stub`) continues to require an explicit `fn main` or `naked fn main`.

## [0.1.0] - 2026-09-29

Initial alpha release of CAP for Linux x86-64.

### Added
- Native x86-64 direct machine code emitter (`capc`) written in NASM assembly.
- Target architectures: Hosted Linux x86-64 (default), Hosted Linux ARM64 (`-a`), Freestanding bare-metal (`--freestanding` / `-k`), Thin boot freestanding (`--boot-thin`), and No-boot-stub ELF64 (`--no-boot-stub`).
- Lexer and parser supporting Python-style indentation, functions, variables, structs, control flow (`if`/`elif`/`else`, `while`, `loop`, `for` with `range`), `asm:` blocks, `alloc`/`defer`/`free`, f-strings, bitwise operators, and unary address-of function operator (`&fn`).
- Single-pass direct ELF64 executable generation without intermediate compiler infrastructure.
- Comprehensive test suites covering frontend parsing (36 tests), direct code generation & execution (76 tests), freestanding bare-metal booting under QEMU (19 tests), and CLI / documentation examples.

- Fixed: the arithmetic type check now applies to the left operand on x86-64 and ARM64
