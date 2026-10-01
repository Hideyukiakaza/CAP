; src/utils.asm - Helper utilities for CAP frontend in NASM x86_64
default rel

extern line_num

section .data
s_err_int_1:  db "LexerError: integer literal '", 0
s_err_int_2:  db "' out of range", 0

s_err_hex_1:  db "LexerError: hex literal '", 0
s_err_hex_2:  db "' exceeds 64 bits", 0

s_err_bin_1:  db "LexerError: binary literal '", 0
s_err_bin_2:  db "' exceeds 64 bits", 0

s_err_line_1: db " (line ", 0
s_err_line_2: db ")", 10, 0
s_err_nl:     db 10, 0

section .text
global sys_exit, sys_write, sys_read, sys_open, sys_close, sys_mmap
global malloc_init, malloc_bytes, str_len, str_cmp, str_ncmp, print_str, print_err, print_err_bytes, print_err_num, print_char, print_num, parse_dec_int, parse_int_literal

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

print_err_bytes:
    push rdi
    push rsi
    push rdx
    mov rdi, STDERR
    call sys_write
    pop rdx
    pop rsi
    pop rdi
    ret

print_err_num:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    sub rsp, 32

    mov rax, rdi
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rbx, 10

    test rax, rax
    jnz .pen_loop
    dec rsi
    mov byte [rsi], '0'
    jmp .pen_print

.pen_loop:
    test rax, rax
    jz .pen_print
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    jmp .pen_loop

.pen_print:
    call print_err

    add rsp, 32
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
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


parse_dec_int:
    xor rsi, rsi
    jmp parse_int_literal

parse_int_literal:
    ; rdi = str_ptr, rcx = len, rsi = allow_min_mag (1 if under unary minus, 0 otherwise), r8 = explicit_line (0 if none)
    ; Returns uint64/int64 in rax. If out of range, prints error and exits with 1.
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r8                  ; explicit_line [rbp - 48]
    push rdi                 ; orig_str_ptr [rbp - 56]
    push rcx                 ; orig_len [rbp - 64]

    mov r12, rdi             ; str_ptr
    mov r13, rcx             ; len
    mov r14, rsi             ; allow_min_mag

    test r13, r13
    jz .range_err

    mov al, [r12]
    cmp al, '0'
    jne .parse_dec

    cmp r13, 2
    jl .parse_dec

    mov bl, [r12 + 1]
    cmp bl, 'x'
    je .parse_hex
    cmp bl, 'X'
    je .parse_hex
    cmp bl, 'b'
    je .parse_bin
    cmp bl, 'B'
    je .parse_bin
    jmp .parse_dec

.parse_hex:
    add r12, 2
    sub r13, 2
    xor rax, rax
    xor r15, r15

.hex_loop:
    test r13, r13
    jz .hex_done
    mov bl, [r12]
    inc r12
    dec r13

    cmp bl, '_'
    je .hex_loop

    call hex_char_to_val
    cmp rbx, 0
    jl .range_err

    inc r15
    cmp r15, 16
    jg .range_err

    shl rax, 4
    or rax, rbx
    jmp .hex_loop

.hex_done:
    test r15, r15
    jz .range_err
    jmp .success

.parse_bin:
    add r12, 2
    sub r13, 2
    xor rax, rax
    xor r15, r15

.bin_loop:
    test r13, r13
    jz .bin_done
    mov bl, [r12]
    inc r12
    dec r13

    cmp bl, '_'
    je .bin_loop

    cmp bl, '0'
    je .bin_zero
    cmp bl, '1'
    je .bin_one
    jmp .range_err

.bin_zero:
    xor rbx, rbx
    jmp .bin_accum
.bin_one:
    mov rbx, 1
.bin_accum:
    inc r15
    cmp r15, 64
    jg .range_err

    shl rax, 1
    or rax, rbx
    jmp .bin_loop

.bin_done:
    test r15, r15
    jz .range_err
    jmp .success

.parse_dec:
    xor rax, rax
    xor r15, r15

.dec_loop:
    test r13, r13
    jz .dec_done
    mov cl, [r12]
    inc r12
    dec r13

    cmp cl, '_'
    je .dec_loop

    cmp cl, '0'
    jl .range_err
    cmp cl, '9'
    jg .range_err

    sub cl, '0'
    movzx rcx, cl

    mov rbx, 10
    mul rbx
    test rdx, rdx
    jnz .range_err

    add rax, rcx
    jc .range_err

    inc r15
    jmp .dec_loop

.dec_done:
    test r15, r15
    jz .range_err

    mov rbx, 0x8000000000000000
    cmp rax, rbx
    ja .range_err
    je .check_min_mag
    jmp .success

.check_min_mag:
    cmp r14, 1
    je .success

.range_err:
    mov r12, [rbp - 56]      ; restore orig_str_ptr
    mov r13, [rbp - 64]      ; restore orig_len
    cmp r13, 2
    jl .range_dec
    mov al, [r12]
    cmp al, '0'
    jne .range_dec
    mov bl, [r12 + 1]
    cmp bl, 'x'
    je .range_hex
    cmp bl, 'X'
    je .range_hex
    cmp bl, 'b'
    je .range_bin
    cmp bl, 'B'
    je .range_bin

.range_dec:
    mov rsi, s_err_int_1
    call print_err
    mov rsi, r12
    mov rdx, r13
    call print_err_bytes
    mov rsi, s_err_int_2
    call print_err
    jmp .range_print_line

.range_hex:
    mov rsi, s_err_hex_1
    call print_err
    mov rsi, r12
    mov rdx, r13
    call print_err_bytes
    mov rsi, s_err_hex_2
    call print_err
    jmp .range_print_line

.range_bin:
    mov rsi, s_err_bin_1
    call print_err
    mov rsi, r12
    mov rdx, r13
    call print_err_bytes
    mov rsi, s_err_bin_2
    call print_err

.range_print_line:
    mov rdi, [rbp - 48]      ; explicit_line
    test rdi, rdi
    jnz .got_err_line
    mov rdi, [line_num]
.got_err_line:
    test rdi, rdi
    jz .range_no_line
    mov rsi, s_err_line_1
    call print_err
    call print_err_num
    mov rsi, s_err_line_2
    call print_err
    mov rdi, 1
    call sys_exit

.range_no_line:
    mov rsi, s_err_nl
    call print_err
    mov rdi, 1
    call sys_exit

.success:
    add rsp, 24              ; clean up push r8, rdi, rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

hex_char_to_val:
    cmp bl, '0'
    jl .not_h
    cmp bl, '9'
    jle .h_digit
    cmp bl, 'a'
    jl .chk_h_upper
    cmp bl, 'f'
    jle .h_lower
.chk_h_upper:
    cmp bl, 'A'
    jl .not_h
    cmp bl, 'F'
    jle .h_upper
.not_h:
    mov rbx, -1
    ret
.h_digit:
    sub bl, '0'
    movzx rbx, bl
    ret
.h_lower:
    sub bl, 'a'
    add bl, 10
    movzx rbx, bl
    ret
.h_upper:
    sub bl, 'A'
    add bl, 10
    movzx rbx, bl
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
