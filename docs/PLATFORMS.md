# CAP Platform Support

CAP v0.1.1 targets Linux x86-64 host environments.

## Platform Support Matrix

| Host OS | Host Arch | Target Binaries | Support Status |
|---|---|---|---|
| Linux (Ubuntu 24.04+) | x86-64 | ELF x86-64, ELF ARM64, Freestanding Multiboot | Native (Tested & Supported) |
| Windows 10/11 | x86-64 | ELF x86-64, ELF ARM64, Freestanding Multiboot | via WSL2 / Docker (Untested) |
| macOS | Intel / Apple Silicon | ELF x86-64, ELF ARM64, Freestanding Multiboot | via Docker (`--platform linux/amd64`) (Untested) |

## Running under Windows (WSL2) (Untested)

Install Ubuntu on WSL2 and execute standard Linux build commands:

```bash
wsl --install -d Ubuntu
sudo apt update && sudo apt install -y nasm binutils make qemu-system-x86 qemu-user
make clean && make
```

## Running under Docker (macOS / Windows / Linux)

Build and run using the project Dockerfile:

```bash
docker build -t capc .
docker run --rm capc capc --version
```

To compile a CAP source file inside Docker:

```bash
docker run --rm -v $(pwd):/work -w /work capc capc -o hello docs/examples/01_hello.cap
```

On Apple Silicon Macs (Untested), pass `--platform linux/amd64`:

```bash
docker build --platform linux/amd64 -t capc .
docker run --platform linux/amd64 --rm capc capc --version
```
