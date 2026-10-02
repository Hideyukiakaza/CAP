# CAP v0.1.0 Language Reference

This document describes the syntax and semantics of CAP v0.1.0.

## 1. Functions & Parameters

Functions are declared with `fn` and use Python-style indentation:

```cap
/* ignore-example-check */
fn add(a, b):
    return a + b
```

- Scalar parameters are unannotated.
- Struct parameters require explicit type annotations (e.g. `fn process(p: Point):`).
- Program entry point requires `fn main():`.
- Functions declared with `naked fn main():` omit standard prologues/epilogues (variable declarations, `alloc`, `defer`, and `return` expressions are prohibited in naked functions).

## 2. Variables and Assignment

- Variables are declared implicitly on first assignment: `x = 10`.
- Flow-insensitive variable checking rule: A variable assigned in any code branch is treated as defined across the function body.

## 3. Literals & Range Rules

- **Decimal Literals:** Signed magnitudes `0` to `9223372036854775807`. Magnitude `9223372036854775808` is valid only as direct operand of unary minus (`-9223372036854775808` = `INT64_MIN`). Larger values produce `LexerError: integer literal '<spelling>' out of range (line N)`.
- **Hexadecimal (`0x`/`0X`) & Binary (`0b`/`0B`):** 64-bit raw bit patterns wrapping in two's complement. Digit separators (`_`) are allowed between valid digits. Exceeding 64 bits produces `LexerError: hex literal ... exceeds 64 bits` / `LexerError: binary literal ... exceeds 64 bits`.

## 4. Operators & Precedence

Precedence (tightest to loosest):
1. Unary: `-`, `&` (address-of), `~` (bitwise NOT)
2. Multiplicative: `*`, `/`, `%`
3. Additive: `+`, `-`
4. Shifts: `<<`, `>>` (arithmetic right shift)
5. Bitwise AND: `&`
6. Bitwise XOR: `^`
7. Bitwise OR: `|`
8. Relational: `<`, `>`, `<=`, `>=`
9. Equality: `==`, `!=`

## 5. Control Flow

```cap
fn main():
    x = 10
    if x > 5:
        print("Greater than 5")
    else:
        print("Less or equal")
    return 0
```

Supported control statements: `if`, `elif`, `else`, `while`, `loop`, `break`, `for ... in range(...)`.

## 6. Structs & Memory Management

```cap
/* ignore-example-check */
struct Point:
    x: int
    y: int

fn main():
    p = Point{x: 10, y: 20}
    ptr = alloc(64)
    defer free(ptr)
    return 0
```

- Field access: `p.x`.
- `alloc(size)` allocates heap memory; `defer stmt` schedules deferred statements to execute on scope exit; `free(ptr)` releases memory.

## 7. Builtin Functions & F-Strings

- `print(expr)`: Output integer, string, or f-string expression.
- `input()`: Read numeric/string input.
- F-strings: `f"x = {x}"`. Double braces `{{` and `}}` unescape to literal `{` and `}`.

## 8. Inline Assembly (`asm:`)

Supported x86-64 instructions in `asm:` blocks:
- Registers: `rax`, `rbx`, `rcx`, `rdx`, `rsi`, `rdi`, `rbp`, `rsp`, `r8`..`r15`, `cr3`, segment registers (`ds`, `es`, `ss`).
- Instructions: `mov`, `add`, `sub`, `and`, `or`, `xor`, `cmp`, `jmp`, `je`, `jne`, `jl`, `jle`, `jg`, `jge`, `call`, `ret`, `retfq`, `push`, `pop`, `in`, `out`, `stosq`, `shr`, `sar`, `shl`, `nop`, `cli`, `sti`, `hlt`, `lgdt`, `lidt`.

## 9. Freestanding Mode Restrictions

In `--freestanding` mode:
- Hosted system calls (`print`, `input`, `alloc`, `free`) produce compile-time errors.
- Hardware I/O is performed via `asm:` blocks or MMIO.
