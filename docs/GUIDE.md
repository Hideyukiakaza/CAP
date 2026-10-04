# CAP User Guide & Tutorial

Welcome to CAP v0.1.1! This guide walks you through installing the compiler, writing hosted applications, and creating bare-metal freestanding programs for QEMU.

## 1. Installation

### Prerequisites
On Ubuntu 24.04 LTS:
```bash
sudo apt update
sudo apt install -y nasm binutils make qemu-system-x86 qemu-user
```

### Building from Source
```bash
git clone https://github.com/Hideyukiakaza/cap.git
cd cap
make clean && make
./capc --version
```
Output:
```
capc 0.1.1
```

## 2. Hello World

Small hosted scripts need no `main` wrapper!

Create `hello.cap`:
```cap
print("Hello, CAP v0.1.1!")
```

Compile and run:
```bash
./capc -o hello hello.cap
./hello
```
Output:
```
Hello, CAP v0.1.1!
```

## 3. Variables and Functions

```cap
fn add(a, b):
    return a + b

x = 10
y = 20
sum = add(x, y)
print(f"Sum: {sum}")
```

Compile and run:
```bash
./capc -o vars_fn docs/examples/02_vars_and_fn.cap
./vars_fn
```
Output:
```
Sum: 30
```

## 4. Structs

Struct parameters require explicit type annotations (`p: Point`):
```cap
struct Point:
    x: int
    y: int

p = Point{x: 5, y: 12}
print(f"Point x={p.x}, y={p.y}")
```

Output:
```
Point x=5, y=12
```

## 5. Control Flow

```cap
x = 10
if x > 5:
    print("Greater than 5")
else:
    print("Less or equal")

for i in 3:
    print(f"Count {i}")

for i in range(2, 6, 2):
    print(f"Step {i}")

n = 3
while (n > 0):
    print(f"While {n}")
    n = n - 1

loop:
    print("once")
    break
```

## 6. Freestanding Kernel Mode

Compile for bare-metal target without hosted dependencies (requires explicit `main`):
```cap
fn main():
    asm:
        mov dx, 0x3F8
        mov al, 0x48
        out dx, al
    return 0
```

Compile with `--freestanding` and run under QEMU system emulation:
```bash
./capc --freestanding -o kernel.bin docs/examples/08_freestanding.cap
qemu-system-x86_64 -kernel kernel.bin -serial stdio -display none -no-reboot
```
Output:
```
H
```
