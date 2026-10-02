# CAP User Guide & Tutorial

Welcome to CAP v0.1.0! This guide walks you through installing the compiler, writing hosted applications, and creating bare-metal freestanding programs for QEMU.

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

## 2. Hello World

Create `hello.cap`:
```cap
fn main():
    print("Hello, CAP v0.1.0!")
    return 0
```

Compile and run:
```bash
./capc -o hello hello.cap
./hello
```
Output:
```
Hello, CAP v0.1.0!
```

## 3. Variables and Functions

```cap
fn add(a, b):
    return a + b

fn main():
    x = 10
    y = 20
    sum = add(x, y)
    print(f"Sum: {sum}")
    return 0
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

fn main():
    p = Point{x: 5, y: 12}
    print(f"Point x={p.x}, y={p.y}")
    return 0
```

Output:
```
Point x=5, y=12
```

## 5. Freestanding Kernel Mode

Compile for bare-metal target without hosted dependencies:
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
