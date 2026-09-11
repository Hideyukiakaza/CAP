; src/codegen/runtime_stubs.asm - Runtime Stubs for CAP v0.1 Executables
default rel

%include "src/codegen/target.inc"

section .text
global emit_x86_print_int, emit_x86_print_str, emit_x86_div_zero_trap
global emit_arm_print_int, emit_arm_print_str, emit_arm_div_zero_trap
extern emit_bytes

emit_x86_print_int:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rdi         ; CodeBuf ptr

    lea rsi, [rel _stub_x86_print_int]
    mov rdx, _stub_x86_print_int_end - _stub_x86_print_int
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbx
    pop rbp
    ret


emit_x86_print_str:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_print_str]
    mov rdx, _stub_x86_print_str_end - _stub_x86_print_str
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_x86_div_zero_trap:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_div_zero]
    mov rdx, _stub_x86_div_zero_end - _stub_x86_div_zero
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_arm_print_int:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_pi]
    mov rdx, .bytes_arm_pi_end - .bytes_arm_pi
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_pi:
    db 0xFD, 0x7B, 0xBD, 0xA9    ; stp x29, x30, [sp, #-48]!
    db 0xFD, 0x03, 0x00, 0x91    ; mov x29, sp
    db 0xE9, 0x03, 0x00, 0xAA    ; mov x9, x0
    db 0xEF, 0xBF, 0x00, 0x91    ; add x15, sp, #47
    db 0x4B, 0x01, 0x80, 0x52    ; mov w11, #10
    db 0xEB, 0x01, 0x00, 0x39    ; strb w11, [x15]
    db 0x2C, 0x00, 0x80, 0xD2    ; mov x12, #1
    db 0x4D, 0x01, 0x80, 0xD2    ; mov x13, #10
    db 0x3F, 0x01, 0x00, 0xF1    ; cmp x9, #0
    db 0xC1, 0x00, 0x00, 0x54    ; b.ne +24 (.p_check_neg)
    db 0xEF, 0x05, 0x00, 0xD1    ; sub x15, x15, #1
    db 0x0B, 0x06, 0x80, 0x52    ; mov w11, #48
    db 0xEB, 0x01, 0x00, 0x39    ; strb w11, [x15]
    db 0x8C, 0x05, 0x00, 0x91    ; add x12, x12, #1
    db 0x13, 0x00, 0x00, 0x14    ; b +76 (.p_write)
    db 0x0A, 0x00, 0x80, 0xD2    ; mov x10, #0
    db 0x3F, 0x01, 0x00, 0xF1    ; cmp x9, #0
    db 0x6A, 0x00, 0x00, 0x54    ; b.ge +12 (.p_loop)
    db 0x2A, 0x00, 0x80, 0xD2    ; mov x10, #1
    db 0xE9, 0x03, 0x09, 0xCB    ; neg x9, x9
    db 0x2E, 0x09, 0xCD, 0x9A    ; udiv x14, x9, x13
    db 0xCB, 0xA5, 0x0D, 0x9B    ; msub x11, x14, x13, x9
    db 0x6B, 0xC1, 0x00, 0x11    ; add w11, w11, #48
    db 0xEF, 0x05, 0x00, 0xD1    ; sub x15, x15, #1
    db 0xEB, 0x01, 0x00, 0x39    ; strb w11, [x15]
    db 0x8C, 0x05, 0x00, 0x91    ; add x12, x12, #1
    db 0xE9, 0x03, 0x0E, 0xAA    ; mov x9, x14
    db 0x29, 0xFF, 0xFF, 0xB5    ; cbnz x9, -28 (.p_loop)
    db 0xAA, 0x00, 0x00, 0xB4    ; cbz x10, +20 (.p_write)
    db 0xEF, 0x05, 0x00, 0xD1    ; sub x15, x15, #1
    db 0xAB, 0x05, 0x80, 0x52    ; mov w11, #45
    db 0xEB, 0x01, 0x00, 0x39    ; strb w11, [x15]
    db 0x8C, 0x05, 0x00, 0x91    ; add x12, x12, #1
    db 0x20, 0x00, 0x80, 0xD2    ; mov x0, #1
    db 0xE1, 0x03, 0x0F, 0xAA    ; mov x1, x15
    db 0xE2, 0x03, 0x0C, 0xAA    ; mov x2, x12
    db 0x08, 0x08, 0x80, 0xD2    ; mov x8, #64
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0xFD, 0x7B, 0xC3, 0xA8    ; ldp x29, x30, [sp], #48
    db 0xC0, 0x03, 0x5F, 0xD6    ; ret
.bytes_arm_pi_end:


emit_arm_print_str:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_ps]
    mov rdx, .bytes_arm_ps_end - .bytes_arm_ps
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_ps:
    db 0xE2, 0x03, 0x01, 0xAA    ; mov x2, x1
    db 0xE1, 0x03, 0x00, 0xAA    ; mov x1, x0
    db 0x20, 0x00, 0x80, 0xD2    ; mov x0, #1
    db 0x08, 0x08, 0x80, 0xD2    ; mov x8, #64
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0xC0, 0x03, 0x5F, 0xD6    ; ret
.bytes_arm_ps_end:


emit_arm_div_zero_trap:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_dz]
    mov rdx, .bytes_arm_dz_end - .bytes_arm_dz
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_dz:
    db 0x40, 0x00, 0x80, 0xD2    ; mov x0, #2
    db 0xE1, 0x00, 0x00, 0x10    ; adr x1, +28
    db 0x02, 0x04, 0x80, 0xD2    ; mov x2, #32
    db 0x08, 0x08, 0x80, 0xD2    ; mov x8, #64
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0x20, 0x00, 0x80, 0xD2    ; mov x0, #1
    db 0xA8, 0x0B, 0x80, 0xD2    ; mov x8, #93
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db "RuntimeError: division by zero", 10, 0
.bytes_arm_dz_end:


; Machine code template routines
_stub_x86_print_int:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov rax, rdi
    lea rsi, [rbp - 1]
    mov byte [rsi], 10
    mov rcx, 1
    mov rbx, 10

    test rax, rax
    jnz .p_check_neg
    dec rsi
    mov byte [rsi], '0'
    inc rcx
    jmp .p_write

.p_check_neg:
    xor r8, r8               ; is_neg = 0
    test rax, rax
    jns .p_loop
    mov r8, 1                ; is_neg = 1
    neg rax                  ; abs(n)

.p_loop:
    test rax, rax
    jz .p_check_sign
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    jmp .p_loop

.p_check_sign:
    test r8, r8
    jz .p_write
    dec rsi
    mov byte [rsi], '-'
    inc rcx

.p_write:
    mov rdx, rcx
    mov rdi, 1
    mov rax, 1
    syscall
    mov rsp, rbp
    pop rbp
    ret
_stub_x86_print_int_end:


_stub_x86_print_str:
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    mov rax, 1
    syscall
    ret
_stub_x86_print_str_end:


_stub_x86_div_zero:
    mov rdi, 2          ; STDERR
    lea rsi, [rel .msg]
    mov rdx, 31         ; len
    mov rax, 1          ; sys_write
    syscall
    mov rdi, 1          ; exit code 1
    mov rax, 60         ; sys_exit
    syscall
.msg: db "RuntimeError: division by zero", 10
_stub_x86_div_zero_end:
