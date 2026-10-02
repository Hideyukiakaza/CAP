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
  - IDT Exception Printer Address: `de_handler` (`0x100CCF`) trampolines to stub common exception printer at `0x100BC8` (outputs `EXCEPTION: vector=<dec> err=0x<16 hex> rip=0x<16 hex>\n` to serial port `0x3F8`). Thin boot mode (`--boot-thin`) excludes the stub printer.
  - *Non-canonical RIP Exception Report:* When a `ret` instruction pops a non-canonical address (e.g. `0x0000800000000000`) into `RIP`, QEMU's x86_64 CPU model records the target non-canonical `RIP` (`0x0000800000000000`) on the `#GP` (vector 13, error 0) stack frame during instruction fetch/branch validation. Real hardware behavior for this case has not been verified, and QEMU's reported RIP must not be taken as a hardware guarantee.

## Freestanding Blob Paging

- **Boot Stub Initial Paging:**
  - Initial `CR3` = `0x1000`
  - `PML4` at `0x1000`: `PML4[0] = 0x2003` (`0x2000 | P | RW`, pointing to PDPT at `0x2000`).
  - `PDPT` at `0x2000`: `PDPT[0] = 0x3003` (`0x3000 | P | RW`, pointing to PD at `0x3000`).
  - `PD` at `0x3000`: 8 identity-mapped 2MB leaves using `P | RW | PS` (`0x83` flags):
    - `PD[0] = 0x00000000 | 0x83` (linear `0x00000000` to `0x00200000`)
    - `PD[1] = 0x00200000 | 0x83` (linear `0x00200000` to `0x00400000`)
    - `PD[2] = 0x00400000 | 0x83` (linear `0x00400000` to `0x00600000`)
    - ... up to `PD[7]` mapping physical/linear addresses `0x00000000` through `0x01000000` (16MB).

- **User Page Table Mapping (`13_cap_cr3.cap`):**
  - Custom `CR3` = `0x20000`
  - `PML4` at `0x20000`: `PML4[0] = 0x21003` (`0x21000 | P | RW`, pointing to PDPT at `0x21000`).
  - `PDPT` at `0x21000`: `PDPT[0] = 0x22003` (`0x22000 | P | RW`, pointing to PD at `0x22000`).
  - `PD` at `0x22000`: 2MB identity-mapped leaves using `P | RW | PS` (`0x83` flags):
    - `PD[0] = 0x00000083` (linear `0x00000000` to `0x00200000`)
    - `PD[1] = 0x00200083` (linear `0x00200000` to `0x00400000`)

- **Extended Page Table Mapping (`14`/`15`/`16`/`17`):**
  - `PD[2] = 0x00400083` (linear `0x00400000` to `0x00600000`, 4-6MB).
- **Linear Range Present:** Mapped contiguous 0-6MB identity range (`0x00000000` to `0x00600000`), covering low page tables (`0x20000`), boot stub and user code (`0x100000`), IDTR/IDT (`0x100400`/`0x100500`), stack (`0x200000`), and extended RAM (`0x400000`).

## Remaining Blob vs Thin Boot (`--boot-thin`)

- **Fat Boot Stub (`--freestanding`):**
  - Prefix Size: 3270 bytes
  - Multiboot2 Header: Magic `0xE85250D6`, Architecture 0 (i386), Header Length 24 bytes, Checksum `0x17ADAF12`.
  - 32-bit Protected Mode Entry Point: `0x100080`.
  - Stub Setup: Enables CR4.PAE, sets `CR3 = 0x1000` (mapping 16MB), enables EFER.LME and CR0.PG, loads stub GDT at `0x100148`, far jumps to 64-bit CS `0x08`, loads stub IDT at `0x5000` with 32 exception handlers, sets stack `rsp = 0x200000`, calls `main()`, and halts on exit (`cli; hlt`).
  - Serial Exception Printer: Common exception printer stub at `0x100BC8` formatting `EXCEPTION: vector=<dec> err=0x<hex> rip=0x<hex>`.

- **Thin Boot Stub (`--freestanding --boot-thin`):**
  - Prefix Size: 512 bytes (0x200 bytes)
  - Multiboot1 / Multiboot2 Header: Magic `0x1BADB002` / `0xE85250D6`, Architecture 0 (i386), Checksum `0xE4524FFE` / `0x17ADAF06`.
  - 32-bit Handoff Entry Point: `0x100078`.
  - Thin Setup:
    1. Zeroes 12KB page directory area (`0x1000`..`0x3FFF`).
    2. Writes PML4[0]=`0x2003` at `0x1000`, PDPT[0]=`0x3003` at `0x2000`, PD[0]=`0x83`, PD[1]=`0x200083`, PD[2]=`0x400083` at `0x3000` (mapping 0–6MB via 3 2MB `PS` leaves).
    3. Sets CR4.PAE (`0x20`), `CR3 = 0x1000`, EFER.LME (`0x100`), CR0.PG (`0x80000001`).
    4. Loads thin GDT (limit `0x17`, base `0x100110`, with Code 0x08 `0x00AF9A000000FFFF` and Data 0x10 `0x00CF92000000FFFF`), far jumps to 64-bit CS `0x08` (`0x1000EA`).
    5. Sets stack `rsp = 0x90000`, calls `main()`, and falls into `cli; hlt; jmp .hlt_loop`.
  - Excludes all serial printing and IDT stubs. Handlers/IDT must be provided by CAP user code.
  - Usage: `--boot-thin` requires `--freestanding` or `-k` flag; using `--boot-thin` without `--freestanding` triggers a compile error.
  - *Note:* `--no-boot-stub` remains an independent option emitting a bare ELF64 executable with `e_entry = main()`, which is not meant for direct QEMU `-kernel` boot.

## Bitwise Operators

- Bitwise operators (`&`, `|`, `^`, `<<`, `>>`, `~`) operate on 64-bit two's complement integers.
- Both operands of bitwise operations must be integers (floats or strings trigger `RuntimeError: type mismatch in arithmetic operation` in hosted mode).
- Shift counts are masked to 6 bits (`cl & 63` on x86-64, `x1 & 63` on ARM64).
- `>>` performs arithmetic right shift (sign-extending).

## Builtin Functions and Type Classification

- `input()` classifies numeric-shaped input into INT (`tag = 1`), FLOAT (`tag = 2`), or fallback STRING (`tag = 3`).
- *Note:* In CAP v0.1, `input()` recognizes and tags float-shaped input (`FLOAT = 2`), but float arithmetic and floating-point printing are not yet implemented in v0.1.
