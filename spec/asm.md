# CAP Assembly Block Direct Machine Code Encoder Specification

## Architecture Overview
The inline assembly block (`asm:`) in CAP allows direct x86-64 machine code generation via a table-driven opcode encoder.

## Encoder Schema
Each instruction in `asm_table` is represented as an `AsmTableEntry` (64 bytes):
- `mne_ptr` (8 bytes): Pointer to mnemonic string (e.g. `"mov"`)
- `mne_len` (8 bytes): Length of mnemonic string
- `op1_mask` (8 bytes): Bitmask of accepted operand 1 shapes
- `op2_mask` (8 bytes): Bitmask of accepted operand 2 shapes
- `pfx1` (1 byte): Mandatory prefix 1 (e.g., `0x0F` or `0x66`), `0` if none
- `pfx2` (1 byte): Mandatory prefix 2, `0` if none
- `opcode` (1 byte): Base opcode byte
- `modrm_reg` (1 byte): `0..7` for opcode extension (e.g., `/2` for `lgdt`, `/3` for `lidt`), `10` (`REG_FROM_OP1`) if ModRM `reg` field comes from Op1, `11` (`REG_FROM_OP2`) if ModRM `reg` field comes from Op2, `255` (`NO_MODRM` / `0xFF`) if no ModRM byte is emitted
- `flags` (1 byte): Feature flags:
  - `F_REX_W` (`0x01`): REX.W prefix required (64-bit operand size)
  - `F_IMM8` (`0x02`): 8-bit immediate payload
  - `F_IMM16` (`0x04`): 16-bit immediate payload
  - `F_IMM32` (`0x08`): 32-bit immediate payload
  - `F_IMM64` (`0x10`): 64-bit immediate payload
  - `F_OPCODE_REG_ADD` (`0x20`): Add lower 3 bits of target register to opcode byte (e.g. `mov reg, imm64`, `push reg`, `pop reg`)
  - `F_SREG_DEST` (`0x40`): Segment register destination check (reject `mov cs, ...`)

## Addressing Shapes & ModRM/SIB Encoding
Supported memory addressing shapes inside `[...]`:
1. `[base]` (e.g., `[rbx]`): ModRM with `mod = 00`
2. `[base + disp]` (e.g., `[rbp + 8]`, `[rsp - 16]`): ModRM with `mod = 01` (8-bit disp) or `mod = 10` (32-bit disp)
3. `[base + idx * scale + disp]` (e.g., `[rbx + rcx * 4 + 16]`): SIB byte encoding with scale `1`, `2`, `4`, or `8`
4. `[imm32]` (e.g., `[0x100000]`): Absolute address encoded as SIB `0x25` with `mod = 00` and `rm = 4` (32-bit displacement)

## General Purpose & Segment Registers
- **GPR64**: `rax, rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8..r15`
- **GPR32**: `eax, ecx, edx, ebx, esp, ebp, esi, edi, r8d..r15d`
- **GPR16**: `ax, cx, dx, bx, sp, bp, si, di, r8w..r15w`
- **GPR8**: `al, cl, dl, bl, spl, bpl, sil, dil, r8b..r15b`
- **SREG**: `es, cs, ss, ds, fs, gs`
- **CR**: `cr0, cr2, cr3, cr4`

## Diagnostic Errors
- Unknown mnemonic: `Error: unknown asm instruction '<mne>'`
- Invalid operands: `Error: invalid operands for '<mne>'`
