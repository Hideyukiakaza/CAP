# CAP v0.1.1 Language Reference

This document describes the syntax and semantics of CAP v0.1.1.

## 1. Program Entry & Functions

Small hosted scripts need no `main` wrapper; CAP is not a Python subset. There are no lists, dicts, files, or integers past 64 bits.

### Hosted Mode Rules
- A file with no `fn main` runs its top-level statements.
- A `fn` or `struct` declaration at top level is not executed directly. Functions may be called before the line where they are declared.
- Falling off the end of a top-level script or function exits with code 0.
- A top-level `return n` sets the program exit code to `n`.
- A non-naked function that does not end in an explicit `return` returns 0.
- `defer` statements run once, in reverse order, before returning or falling off.
- `fn main():` still works. Mixing `fn main():` with a top-level statement that is not a `fn` or `struct` declaration produces `SyntaxError: top-level statements cannot be mixed with 'fn main()' (line N)`.
- A hosted file containing only declarations and no top-level statements produces `NameError: main function not found`.

### Freestanding Mode Rules
- Freestanding targets (`--freestanding`, `--boot-thin`, `--no-boot-stub`) require an explicit `fn main` or `naked fn main`. Implicit `main` does not apply.
- A `naked fn` emits raw body instructions without compiler frame prologues/epilogues and does not gain a synthesized `return`.

### Parameters & Scope
- Scalar parameters are unannotated.
- Struct parameters require explicit type annotations (e.g., `fn process(p: Point):`).
- A top-level variable is not visible inside a function. Referencing a top-level variable inside a function produces `NameError: undefined name 'x' (line N)` followed by the hint `top-level variables are not visible inside functions; pass 'x' as a parameter`.
- Referencing an undefined variable that exists nowhere produces a single-line `NameError: undefined name 'x' (line N)` without a hint.

```cap
fn add(a, b):
    return a + b

x = 10
y = 20
sum = add(x, y)
print(f"Sum: {sum}")
```

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
10. Ternary Conditional: `cond ? true_expr : false_expr` (right-associative)

## 5. Control Flow & Loops

- `for i in 10:` is shorthand for `for i in range(10):`. `i` takes values 0, 1, 2, 3, 4, 5, 6, 7, 8, 9. The stop value is exclusive. `for i in n:` and `for i in (n + 1):` use the same shorthand.
- `for i in range(...)` remains fully supported, including `range(stop)`, `range(start, stop)`, and `range(start, stop, step)`.
- `while (n > 0):` is equivalent to `while n > 0:`.
- `loop:` runs continuously until a `break` or `return` is executed. A `loop` without an exit strategy hangs indefinitely.
- `break` exits the enclosing `loop`, `while`, or `for` loop, and execution continues at the next statement after the loop.
- Using `break` outside an enclosing loop produces a compile-time `SyntaxError: 'break' outside loop (line N)`.
- `/*/` begins a comment that runs to the end of the line.

```cap
for i in 3:
    print(f"Count {i}")

for i in range(2, 6, 2):
    print(f"Step {i}")

n = 3
while (n > 0):
    print(f"While {n}")
    n = n - 1
```

```cap
loop:
    print("once")
    break

for i in 2:
    loop:
        print(f"Inner {i}")
        break
    print("Outer")
```

```cap
/*/ Full-line comment
x = 5 /*/ Trailing comment
msg = "# Not a comment"
print(f"Value: {x}") /*/ Comment in indented block
print(msg)
```

## 6. Structs & Memory Management

```cap
struct Point:
    x: int
    y: int

p = Point{x: 5, y: 12}
print(f"Point x={p.x}, y={p.y}")
```

- Field access: `p.x`.
- `alloc(size)` allocates heap memory; `defer stmt` schedules deferred statements to run when the function returns, in reverse order.
- `free(ptr)` currently crashes (segfault) and is not covered by any test. Do not use it yet (see Known Limitations in the README).

```cap
ptr = alloc(16)
print("Allocated memory successfully")
```

```cap
fn test():
    defer print(2)
    print(1)

test()
```

## 7. Builtin Functions, Input, and F-Strings

- `print(expr)`: Output integer, string, or f-string expression.
- `input()`: Reads a line from stdin. A prompt string is permitted: `input("Enter your name: ")`.
- **Runtime Type Conversion for `input()`:** Integer-shaped text is assigned INT (tag 1), float-shaped text is assigned FLOAT (tag 2), and any other text is assigned STRING (tag 3). For an integer line, `a + 5` works directly without requiring an explicit `int()` conversion call. Float arithmetic is not implemented, and a float tag does not make `n * 2` work.
- F-strings: `f"x = {x}"`. Double braces `{{` and `}}` unescape to literal `{` and `}`.
- **F-string Expression Spans:** Expressions within `{ ... }` support sub-expressions including string literals, parentheses, and ternary operators: `f"status: {(a == 0) ? "zero" : "non-zero"}"`.
- **C-Style Ternary Operator (`cond ? a : b`):** CAP supports right-associative conditional expressions `cond ? a : b`. Python-style `a if c else b` produces `SyntaxError: CAP uses 'cond ? a : b' for conditional expressions (line N)`.

## 8. Inline Assembly (`asm:`)

Supported x86-64 instructions in `asm:` blocks:
- Registers: `rax`, `rbx`, `rcx`, `rdx`, `rsi`, `rdi`, `rbp`, `rsp`, `r8`..`r15`, `cr3`, segment registers (`ds`, `es`, `ss`).
- Instructions: `mov`, `add`, `sub`, `and`, `or`, `xor`, `cmp`, `jmp`, `je`, `jne`, `jl`, `jle`, `jg`, `jge`, `call`, `ret`, `retfq`, `push`, `pop`, `in`, `out`, `stosq`, `shr`, `sar`, `shl`, `nop`, `cli`, `sti`, `hlt`, `lgdt`, `lidt`.

```cap
asm:
    mov rax, 0x383420310A
print("ASM block executed")
```

## 9. Freestanding Mode Restrictions

In `--freestanding` mode:
- Hosted system calls (`print`, `input`, `alloc`, `free`) produce compile-time errors.
- Hardware I/O is performed via `asm:` blocks or MMIO.

```cap
fn main():
    asm:
        mov dx, 0x3F8
        mov al, 0x48
        out dx, al
    return 0
```
