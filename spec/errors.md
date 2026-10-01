# CAP Error Types and Exit Codes

CAP compiler errors and runtime traps are strictly categorized into two exit code groups:

## Exit Code 1: Compile-Time Errors

Compile-time errors occur during tokenization, parsing, or semantic analysis/codegen before machine code execution. All compile-time errors print a diagnostic message to `stderr` and terminate compilation immediately with exit code `1`.

| Error Class | Error Message Format | Cause |
| :--- | :--- | :--- |
| `LexerError` | `LexerError: malformed numeric literal '<spelling>' (line <L>)` | Invalid characters or bad `_` placement in numeric tokens (e.g. `10abc`, `0xG`, `0b102`, `1_`, `1__0`). |
| `LexerError` | `LexerError: integer literal '<spelling>' out of range (line <L>)` | Decimal integer literal exceeds maximum permitted bounds (`> 9223372036854775807`, or `9223372036854775808` un-negated). |
| `LexerError` | `LexerError: hex literal '<spelling>' exceeds 64 bits (line <L>)` | Hexadecimal literal exceeds 64 bits (more than 16 hex digits). |
| `LexerError` | `LexerError: binary literal '<spelling>' exceeds 64 bits (line <L>)` | Binary literal exceeds 64 bits (more than 64 binary digits). |
| `SyntaxError` | `SyntaxError: <description> (line <L>)` | Indentation, grammar, or naked function rule violations. |
| `NameError` | `NameError: undefined name '<var_name>' (line <L>)` | Variable referenced before assignment or definition in function scope (textual order). |
| `NameError` | `NameError: undefined function '<fn_name>' (line <L>)` | Function called without being declared or builtin. |
| `NameError` | `NameError: main function not found` | Source file lacks a top-level `main` function declaration. |
| `TypeError` | `TypeError: cannot access field '<field>': '<var>' is not a struct (line <L>)` | Field access on a non-struct type or scalar literal (e.g. `10.x`). Includes hint for unannotated struct parameters (`struct parameters need an annotation, e.g. p: Point`). |
| `TypeError` | `TypeError: struct '<struct>' has no field '<field>' (line <L>)` | Accessing a field that does not exist on the target struct. |

## CLI Errors

Command-line and driver usage errors produce `Error: <description>` output on `stderr` and exit with code `1`. These are environment/invocation errors rather than language compile diagnostics:

- `Error: Could not open source file` — The specified input file path could not be opened.
- `Error: Could not read source file` — The source file could not be read into memory.
- `Error: -o flag requires an output filename argument` — `-o` option provided without a trailing output path.
- `Error: --boot-thin requires --freestanding or -k` — `--boot-thin` flag specified without enabling freestanding target mode.
- `Error: Could not open output file for writing` — The target output ELF binary could not be opened or created for writing.

## Exit Code 101: Runtime Traps

Runtime traps occur during program execution. The runtime stub writes an error string to `stderr` and exits immediately with code `101`.

| Runtime Trap | Error Message |
| :--- | :--- |
| Division by zero | `RuntimeError: division by zero` |
| Signed 64-bit integer overflow | `RuntimeError: integer overflow` |
| Arithmetic type mismatch | `RuntimeError: type mismatch` |

## Integer Literal Range Rules & Asymmetry

- **Hexadecimal (`0x`/`0X`) and Binary (`0b`/`0B`):**
  - Treated as 64-bit raw bit patterns wrapping in two's complement.
  - Up to 16 hex digits or 64 binary digits are allowed (`0xFFFFFFFFFFFFFFFF` = `-1`, `0x8000000000000000` = `INT64_MIN`).
  - Literals exceeding 64 bits produce a compile-time `LexerError: hex literal '<spelling>' exceeds 64 bits (line <L>)` or `LexerError: binary literal '<spelling>' exceeds 64 bits (line <L>)`.

- **Decimal Literals:**
  - Represent signed magnitudes from `0` to `9223372036854775807` (`2^63 - 1`).
  - The exact magnitude `9223372036854775808` is permitted **only as the direct operand of unary minus** (`-9223372036854775808` -> `INT64_MIN`).
  - An un-negated decimal literal > `9223372036854775807` produces a compile-time `LexerError: integer literal '<spelling>' out of range (line <L>)`.
