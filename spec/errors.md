# CAP Error Types and Exit Codes

CAP compiler errors and runtime traps are strictly categorized into two exit code groups:

## Exit Code 1: Compile-Time Errors

Compile-time errors occur during tokenization, parsing, or semantic analysis/codegen before machine code execution. All compile-time errors print a diagnostic message to `stderr` and terminate compilation immediately with exit code `1`.

| Error Class | Error Message Format | Cause |
| :--- | :--- | :--- |
| `LexerError` | `LexerError: malformed numeric literal '<token>' on line <L>` | Invalid characters or bad `_` placement in numeric tokens (e.g. `10abc`, `0xG`, `0b102`, `1_`, `1__0`). |
| `SyntaxError` | `SyntaxError: <description>` | Indentation or grammar syntax violations (e.g. tab indentation, unclosed braces/quotes, missing colon). |
| `NameError` | `NameError: undefined name '<var_name>'` | Variable referenced before assignment or definition in function scope (textual order). |
| `NameError` | `NameError: undefined function '<fn_name>'` | Function called without being declared or builtin. |
| `TypeError` | `TypeError: cannot access field '<field>': '<var>' is not a struct` | Field access on a non-struct type or scalar literal (e.g. `10.x`). Includes hint for unannotated struct parameters (`struct parameters need an annotation, e.g. p: Point`). |
| `TypeError` | `TypeError: struct '<struct>' has no field '<field>'` | Accessing a field that does not exist on the target struct. |
| `Error` | `Error: integer literal out of range` | Integer literal exceeds permitted bounds. |

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
  - Literals exceeding 64 bits produce a compile-time `Error: integer literal out of range`.

- **Decimal Literals:**
  - Represent signed magnitudes from `0` to `9223372036854775807` (`2^63 - 1`).
  - The exact magnitude `9223372036854775808` is permitted **only as the direct operand of unary minus** (`-9223372036854775808` -> `INT64_MIN`).
  - An un-negated decimal literal > `9223372036854775807` produces a compile-time `Error: integer literal out of range`.
