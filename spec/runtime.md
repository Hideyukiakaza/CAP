# CAP v0.1 Runtime Specification

## Reserved Exit Codes

CAP reserves specific exit codes for system and language-level runtime traps. User programs should avoid returning these exit codes from `main()` to distinguish application logic returns from runtime traps.

| Exit Code | Category | Description |
|-----------|----------|-------------|
| `101` | Language Runtime Trap | Triggered by unrecoverable runtime errors during execution (e.g. division by zero, integer overflow, type mismatch). |

## Runtime Traps and Diagnostic Messages

When a runtime trap fires, CAP executables write a diagnostic error message to `stderr` (fd 2) and terminate immediately with exit code `101`.

| Trap Condition | Error Diagnostic Message | Exit Code |
|----------------|--------------------------|-----------|
| Division by Zero | `RuntimeError: division by zero\n` | `101` |
| Signed Integer Overflow (`INT64_MIN / -1`) | `RuntimeError: integer overflow\n` | `101` |
| Type Mismatch in Arithmetic | `RuntimeError: type mismatch in arithmetic operation\n` | `101` |

## Division Behavior by Mode

| Mode | `/ 0` and `% 0` | `INT64_MIN / -1` |
|------|-----------------|------------------|
| Hosted | `RuntimeError: division by zero` + exit 101 | `RuntimeError: integer overflow` + exit 101 |
| Freestanding | Raw `cqo; idiv rbx` — hardware `#DE` (vector 0 on IDT) | Raw `cqo; idiv rbx` — hardware `#DE` |

## Freestanding GDT & IDT Stub Layout

- **GDT Selectors & Limit:**
  - Limit: `0x0017` (23 = 3 x 8-byte descriptors).
  - Selector `0x08`: 64-bit Code Segment (`0x00AF9A000000FFFF`).
  - Selector `0x10`: 64-bit Data Segment (`0x00CF92000000FFFF`).
  - GDTR pseudo-descriptor image: 10 bytes (`limit: u16`, `base: u64`).

- **IDT Gates & Printer Stub:**
  - Base: `0x100500`, Limit: `0x01FF` (32 x 16-byte gate descriptors).
  - 64-bit Interrupt Gate attribute bits: `0x8E00` (P=1, DPL=0, Type=0xE 64-bit Interrupt Gate).
  - Gate Packing:
    - `lo = (handler & 0xFFFF) | (selector << 16) | (0x8E00 << 32) | (((handler >> 16) & 0xFFFF) << 48)`
    - `hi = (handler >> 32) & 0xFFFFFFFF`
  - IDT Exception Printer Address: `0x100C37` (outputs `EXCEPTION: vector=<dec> err=0x<16 hex> rip=0x<16 hex>\n` to serial port `0x3F8`).

## Bitwise Operators

- Bitwise operators (`&`, `|`, `^`, `<<`, `>>`, `~`) operate on 64-bit two's complement integers.
- Both operands of bitwise operations must be integers (floats or strings trigger `RuntimeError: type mismatch in arithmetic operation` in hosted mode).
- Shift counts are masked to 6 bits (`cl & 63` on x86-64, `x1 & 63` on ARM64).
- `>>` performs arithmetic right shift (sign-extending).

## Builtin Functions and Type Classification

- `input()` classifies numeric-shaped input into INT (`tag = 1`), FLOAT (`tag = 2`), or fallback STRING (`tag = 3`).
- *Note:* In CAP v0.1, `input()` recognizes and tags float-shaped input (`FLOAT = 2`), but float arithmetic and floating-point printing are not yet implemented in v0.1.
