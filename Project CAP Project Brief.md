# Project CAP — Project Brief

---

## 1. Vision & Mission

**Vision:** A language where the fastest possible machine code and the most readable possible source code are the same thing.

**Mission:** CAP is a systems programming language built around a custom assembler — source code is translated directly into machine code, with no intermediate compiler stage — targeting performance that meets or exceeds hand-optimized Assembly and C, in both low-level and high-level code, while reading more simply than Python.

**On the "beat world-class Assembly experts" goal:** I'll build toward this honestly rather than softening it — it's your call and a legitimate north star. Two things make it achievable rather than just aspirational: (1) a human expert can out-optimize *one* hot loop, but can't out-optimize *every* piece of a large program with equal care — CAP's optimizer can apply expert-level techniques (register allocation, instruction scheduling, SIMD) uniformly and exhaustively everywhere, which is where consistent wins come from; (2) profile-guided optimization lets CAP use *real execution data* that a human hand-tuning in the abstract doesn't have. The benchmark suite (Phase 5) should be designed specifically to prove this — not cherry-picked, published with full methodology, re-run publicly.

---

## 2. Core Design Principles

| Principle | Description |
|---|---|
| **Direct-to-machine-code** | No IR, no separate compiler pass — CAP source is parsed and translated straight into machine code by the custom assembler. |
| **Zero ceremony** | No boilerplate, minimal keywords, whitespace-significant like Python. |
| **Zero-cost abstractions** | Every construct compiles to what a human would write by hand — verified via disassembly diffing in CI. |
| **No hidden control flow** | Nothing invisible to the reader — no implicit exceptions, no implicit allocation. |
| **Direct hardware transparency** | Any construct can drop to raw register/memory access without leaving the language (`asm:` blocks, raw pointers). |
| **Deterministic memory** | No garbage collector. Ownership tracking + manual control. |
| **One way to do it** | Reduces both cognitive load and assembler complexity. |

### Key Differentiators

**vs Assembly:** readable structured syntax, automatic (overridable) register allocation, compile-time safety checks at zero runtime cost, portable across ISAs from one source.

**vs C:** no manual memory bugs by default (ownership-tracked `alloc`/`free`), no undefined behavior class of footguns, uniform optimization applied everywhere instead of relying on the programmer's diligence.

**vs Python:** no interpreter, no GIL, static typing with full inference, no implicit heap allocation, no GC pauses, no JIT warmup — deterministic performance every run.

---

## 3. Syntax (v0.1)

### Comments
```cap
/*/ single line comment
/*/ First line
End line /*/
```

### Variables
```cap
x = 10          /*/ inferred int
y = 10.5         /*/ inferred float
name = "cap"      /*/ inferred string
const PI = 3.14159   /*/ assemble-time constant
```

### Conditionals
```cap
if x > 10:
    print("big")
elif x == 10:
    print("equal")
else:
    print("small")
```

### Loops
```cap
for i in 10:        /*/ range(10)-style: 0..9
    print(i)

for i in range(2, 10, 2):   /*/ start, stop, step
    print(i)

while x > 0:
    x -= 1

loop:                /*/ infinite loop
    if done:
        break
```

### Functions
```cap
fn add(a, b):         /*/ auto datatype detection
    return a + b

fn greet(name):
    print("hello " + name)
```

### Memory Management
```cap
x = alloc(int, 100)     /*/ heap-allocate 100 ints, ownership tracked
defer free(x)            /*/ deterministic cleanup, scope-bound

y = &x                    /*/ borrow (read-only reference)
z = &mut x                 /*/ mutable reference

raw p: *int = &x[0]        /*/ explicit raw pointer, escape hatch to hardware
```

### Structs & Low-Level Access
```cap
struct Vec3:
    x: f32
    y: f32
    z: f32

v = Vec3{x: 1.0, y: 2.0, z: 3.0}

asm:
    mov rax, 1
    syscall
```
### Import statements
```cap
import <module_name> /*/ Python-style.
```

---

## 4. Performance Strategy

1. **Custom assembler, direct emission** — the assembler parses CAP syntax and emits machine code directly; no IR layer, no separate "compiler" stage. Optimization logic lives *inside* the assembler's translation passes rather than a preceding phase.
2. **Zero-cost abstraction verification** — every high-level construct's emitted instructions get diffed against reference hand-written Assembly/C in CI to prove no overhead was introduced.
3. **Optimization passes applied during translation:**
   - Constant folding & propagation (assemble-time constants make this cheap)
   - Dead code elimination
   - Graph-coloring register allocation
   - Instruction scheduling for pipeline/cache efficiency
   - Loop unrolling & auto-vectorization (SIMD) where provably safe
4. **No runtime by default** — no GC, no reflection tax, no dynamic dispatch unless explicitly opted into.
5. **Profile-guided optimization (PGO)** — feed real execution traces back into the assembler; this is the key lever for beating expert hand-written Assembly, which typically isn't tuned against live profiling data.
6. **Escape hatches everywhere** — `asm:` blocks, raw pointers, manual register hints so the assembler is never the only opinion in the room.

---

## 5. Development Roadmap

| Phase | Milestone | Target Outcome |
|---|---|---|
| **Phase 0 — Spec** | Formal grammar (EBNF), frozen keyword list, `/*/` comment spec | v0.1 language spec locked |
| **Phase 1 — Frontend** | Lexer, parser, AST, type inference for `=` assignments | Parses all syntax above |
| **Phase 2 — Assembler Core** | Direct AST → both x86-64 machine code and ARM emission by using explicit flags like -a flag selects ARM, no flag defaults to x86-64. | `fn add` runs as real native code, no IR step |
| **Phase 3 — Control Flow & Memory** | `if/elif/else`, `for`/`range()`, `while`, `loop`, `alloc`/`defer free`, structs | Programs with real control flow and heap use run natively |
| **Phase 4 — Optimizer** | Register allocation, DCE, constant folding, instruction scheduling | Output competitive with hand-written Assembly on first benchmarks |
| **Phase 5 — Benchmarking** | Public, reproducible benchmark suite vs hand-written Assembly and C (including expert-level reference implementations) | Transparent published results — this is where the "beats Assembly" claim gets proven or refined |
| **Phase 6 — PGO & Vectorization** | Profiling feedback loop, SIMD auto-vectorization | Measurable gains over Phase 4 baseline |
| **Phase 7 — Tooling & Public Launch** | Formatter, package manager, docs, contributor guide | Public v0.1 GitHub release |

---

## 6. Anticipated Challenges & Mitigations

| Challenge | Mitigation |
|---|---|
| **"Beats world-class Assembly experts" is the hardest possible bar** | Build the benchmark suite (Phase 5) *before* making public claims. Include profiling-based cases where CAP has an inherent data advantage over static hand-tuning, and be transparent about cases where it doesn't (yet). |
| **No IR means the assembler must do everything at once** | Keep Phase 2 scoped to a dual target (x86-64 and ARM64) so the "parse → optimize → emit" pipeline is provably correct before adding complexity like RISC-V or more aggressive passes. |
| **Type inference + zero-cost promises can conflict** | Define inference rules precisely in Phase 0 so `x = 10` vs `y = 10.5` behavior is unambiguous and never requires a runtime tag/check. |
| **Memory safety without a GC, without a separate borrow-checker pass** | Since ownership tracking has to live inside the assembler's translation logic (no IR to check it in), design this as its own well-defined internal pass in Phase 3 rather than bolting it on later. |
| **Solo development bandwidth on an assembler-scale project** | Roadmap is phased into self-contained, verifiable units you can spec precisely and hand to Jules for implementation, one phase at a time. |
| **Attracting contributors to an unproven language** | Publish real, reproducible Phase 5 benchmark data before the big announcement — proof beats promises for a claim this ambitious. |

---

