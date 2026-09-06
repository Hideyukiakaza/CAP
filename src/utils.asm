; src/utils.asm - Helper utilities for CAP frontend in NASM x86_64
default rel

section .text
global sys_exit, sys_write, sys_read, sys_open, sys_close, sys_mmap
global malloc_init, malloc_bytes, str_len, str_cmp, str_ncmp, print_str, print_err, print_char, print_num

%define SYS_READ 0
%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_MMAP 9
%define SYS_BRK 12
%define SYS_EXIT 60

%define STDIN 0
%define STDOUT 1
%define STDERR 2

sys_exit:
    mov rax, SYS_EXIT
    syscall

sys_write:
    mov rax, SYS_WRITE
    syscall
    ret

sys_read:
    mov rax, SYS_READ
    syscall
    ret

sys_open:
    mov rax, SYS_OPEN
    syscall
    ret

sys_close:
    mov rax, SYS_CLOSE
    syscall
    ret

print_str:
    push rdi
    push rdx
    push rsi
    mov rdi, rsi
    call str_len
    mov rdx, rax
    pop rsi
    mov rdi, STDOUT
    call sys_write
    pop rdx
    pop rdi
    ret

print_err:
    push rdi
    push rdx
    push rsi
    mov rdi, rsi
    call str_len
    mov rdx, rax
    pop rsi
    mov rdi, STDERR
    call sys_write
    pop rdx
    pop rdi
    ret

print_char:
    push rax
    push rsi
    push rdx
    push rdi
    sub rsp, 16
    mov [rsp], dil
    mov rdi, STDOUT
    mov rsi, rsp
    mov rdx, 1
    call sys_write
    add rsp, 16
    pop rdi
    pop rdx
    pop rsi
    pop rax
    ret

print_num:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    sub rsp, 32

    mov rax, rdi
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rbx, 10

    test rax, rax
    jnz .pn_loop
    dec rsi
    mov byte [rsi], '0'
    jmp .pn_print

.pn_loop:
    test rax, rax
    jz .pn_print
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    jmp .pn_loop

.pn_print:
    call print_str

    add rsp, 32
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

str_len:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

str_cmp:
    xor rax, rax
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .loop
.equal:
    xor rax, rax
    ret
.diff:
    movzx rax, al
    movzx rcx, cl
    sub rax, rcx
    ret

str_ncmp:
    xor rax, rax
    test rdx, rdx
    jz .equal
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rdi
    inc rsi
    dec rdx
    jnz .loop
.equal:
    xor rax, rax
    ret
.diff:
    movzx rax, al
    movzx rcx, cl
    sub rax, rcx
    ret

section .bss
global heap_ptr, heap_end
heap_ptr: resq 1
heap_end: resq 1

section .text
malloc_init:
    push rbx
    mov rax, SYS_BRK
    xor rdi, rdi
    syscall
    mov [heap_ptr], rax
    mov [heap_end], rax
    pop rbx
    ret

malloc_bytes:
    push rbx
    push rcx
    push rdx
    add rdi, 7
    and rdi, ~7
    
    mov rax, [heap_ptr]
    mov rbx, rax
    add rbx, rdi
    
    cmp rbx, [heap_end]
    jle .allocate
    
    push rdi
    push rax
    mov rdi, [heap_end]
    add rdi, 65536
    cmp rdi, rbx
    jge .do_brk
    mov rdi, rbx
    add rdi, 65536
.do_brk:
    mov rax, SYS_BRK
    syscall
    mov [heap_end], rax
    pop rax
    pop rdi

.allocate:
    mov [heap_ptr], rbx
    pop rdx
    pop rcx
    pop rbx
    ret
