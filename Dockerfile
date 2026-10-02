FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    nasm \
    binutils \
    make \
    qemu-system-x86 \
    qemu-user \
    bash \
    diffutils \
    grep \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /cap

COPY . .

RUN make clean && make

CMD ["./capc", "--version"]
