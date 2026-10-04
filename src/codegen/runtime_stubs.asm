; Copyright 2026 Devadath A A (aka Hideyukiakaza)
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

; src/codegen/runtime_stubs.asm - Runtime Stubs for CAP v0.1 Executables
default rel

%include "src/codegen/target.inc"

section .text
global emit_x86_print_int, emit_x86_print_str, emit_x86_div_zero_trap, emit_x86_overflow_trap, emit_x86_alloc, emit_x86_free, emit_x86_input, emit_x86_type_mismatch_trap, emit_x86_format_int
global emit_arm_print_int, emit_arm_print_str, emit_arm_div_zero_trap, emit_arm_overflow_trap, emit_arm_alloc, emit_arm_free, emit_arm_input, emit_arm_type_mismatch_trap, emit_arm_format_int
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


emit_x86_free:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_free]
    mov rdx, _stub_x86_free_end - _stub_x86_free
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_x86_input:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_input]
    mov rdx, _stub_x86_input_end - _stub_x86_input
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_x86_type_mismatch_trap:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_type_mismatch]
    mov rdx, _stub_x86_type_mismatch_end - _stub_x86_type_mismatch
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_x86_overflow_trap:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_overflow]
    mov rdx, _stub_x86_overflow_end - _stub_x86_overflow
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_x86_format_int:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_format_int]
    mov rdx, _stub_x86_format_int_end - _stub_x86_format_int
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret


emit_x86_alloc:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel _stub_x86_alloc]
    mov rdx, _stub_x86_alloc_end - _stub_x86_alloc
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
    db 0xFD, 0x7B, 0xBD, 0xA9
    db 0xFD, 0x03, 0x00, 0x91
    db 0xE9, 0x03, 0x00, 0xAA
    db 0xEF, 0xBF, 0x00, 0x91
    db 0x4B, 0x01, 0x80, 0x52
    db 0xEB, 0x01, 0x00, 0x39
    db 0x2C, 0x00, 0x80, 0xD2
    db 0x4D, 0x01, 0x80, 0xD2
    db 0x3F, 0x01, 0x00, 0xF1
    db 0xC1, 0x00, 0x00, 0x54
    db 0xEF, 0x05, 0x00, 0xD1
    db 0x0B, 0x06, 0x80, 0x52
    db 0xEB, 0x01, 0x00, 0x39
    db 0x8C, 0x05, 0x00, 0x91
    db 0x13, 0x00, 0x00, 0x14
    db 0x0A, 0x00, 0x80, 0xD2
    db 0x3F, 0x01, 0x00, 0xF1
    db 0x6A, 0x00, 0x00, 0x54
    db 0x2A, 0x00, 0x80, 0xD2
    db 0xE9, 0x03, 0x09, 0xCB
    db 0x2E, 0x09, 0xCD, 0x9A
    db 0xCB, 0xA5, 0x0D, 0x9B
    db 0x6B, 0xC1, 0x00, 0x11
    db 0xEF, 0x05, 0x00, 0xD1
    db 0xEB, 0x01, 0x00, 0x39
    db 0x8C, 0x05, 0x00, 0x91
    db 0xE9, 0x03, 0x0E, 0xAA
    db 0x29, 0xFF, 0xFF, 0xB5
    db 0xAA, 0x00, 0x00, 0xB4
    db 0xEF, 0x05, 0x00, 0xD1
    db 0xAB, 0x05, 0x80, 0x52
    db 0xEB, 0x01, 0x00, 0x39
    db 0x8C, 0x05, 0x00, 0x91
    db 0x20, 0x00, 0x80, 0xD2
    db 0xE1, 0x03, 0x0F, 0xAA
    db 0xE2, 0x03, 0x0C, 0xAA
    db 0x08, 0x08, 0x80, 0xD2
    db 0x01, 0x00, 0x00, 0xD4
    db 0xFD, 0x7B, 0xC3, 0xA8
    db 0xC0, 0x03, 0x5F, 0xD6
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
    db 0xFD, 0x7B, 0xBD, 0xA9
    db 0xFD, 0x03, 0x00, 0x91
    db 0xE9, 0x03, 0x00, 0xAA
    db 0x0C, 0x00, 0x80, 0xD2
    db 0x2B, 0x69, 0x6C, 0x38
    db 0x6B, 0x00, 0x00, 0x34
    db 0x8C, 0x05, 0x00, 0x91
    db 0xFD, 0xFF, 0xFF, 0x17
    db 0x20, 0x00, 0x80, 0xD2
    db 0xE1, 0x03, 0x09, 0xAA
    db 0xE2, 0x03, 0x0C, 0xAA
    db 0x08, 0x08, 0x80, 0xD2
    db 0x01, 0x00, 0x00, 0xD4
    db 0xEF, 0xBF, 0x00, 0x91
    db 0x4B, 0x01, 0x80, 0x52
    db 0xEB, 0x01, 0x00, 0x39
    db 0x20, 0x00, 0x80, 0xD2
    db 0xE1, 0x03, 0x0F, 0xAA
    db 0x22, 0x00, 0x80, 0xD2
    db 0x08, 0x08, 0x80, 0xD2
    db 0x01, 0x00, 0x00, 0xD4
    db 0xFD, 0x7B, 0xC3, 0xA8
    db 0xC0, 0x03, 0x5F, 0xD6
.bytes_arm_ps_end:


emit_arm_format_int:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_fmt]
    mov rdx, .bytes_arm_fmt_end - .bytes_arm_fmt
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_fmt:
    db 0xFD, 0x7B, 0xBD, 0xA9
    db 0xFD, 0x03, 0x00, 0x91
    db 0xF3, 0x0B, 0x00, 0xF9
    db 0xF4, 0x0F, 0x00, 0xF9
    db 0xE9, 0x03, 0x00, 0xAA
    db 0xEA, 0x03, 0x01, 0xAA
    db 0x3F, 0x01, 0x00, 0xF1
    db 0xC1, 0x00, 0x00, 0x54
    db 0x0B, 0x06, 0x80, 0x52
    db 0x4B, 0x01, 0x00, 0x39
    db 0x5F, 0x05, 0x00, 0x39
    db 0x20, 0x00, 0x80, 0xD2
    db 0x1F, 0x00, 0x00, 0x14
    db 0x10, 0x00, 0x80, 0xD2
    db 0x3F, 0x01, 0x00, 0xF1
    db 0x6A, 0x00, 0x00, 0x54
    db 0x30, 0x00, 0x80, 0xD2
    db 0xE9, 0x03, 0x09, 0xCB
    db 0xEF, 0xBF, 0x00, 0x91
    db 0x0C, 0x00, 0x80, 0xD2
    db 0x4D, 0x01, 0x80, 0xD2
    db 0x2E, 0x09, 0xCD, 0x9A
    db 0xCB, 0xA5, 0x0D, 0x9B
    db 0x6B, 0xC1, 0x00, 0x11
    db 0xEF, 0x05, 0x00, 0xD1
    db 0xEB, 0x01, 0x00, 0x39
    db 0x8C, 0x05, 0x00, 0x91
    db 0xE9, 0x03, 0x0E, 0xAA
    db 0x29, 0xFF, 0xFF, 0xB5
    db 0xB0, 0x00, 0x00, 0xB4
    db 0xEF, 0x05, 0x00, 0xD1
    db 0xAB, 0x05, 0x80, 0x52
    db 0xEB, 0x01, 0x00, 0x39
    db 0x8C, 0x05, 0x00, 0x91
    db 0xE0, 0x03, 0x0C, 0xAA
    db 0x0D, 0x00, 0x80, 0xD2
    db 0xBF, 0x01, 0x0C, 0xEB
    db 0xAA, 0x00, 0x00, 0x54
    db 0xEB, 0x69, 0x6D, 0x38
    db 0x4B, 0x69, 0x2D, 0x38
    db 0xAD, 0x05, 0x00, 0x91
    db 0xFB, 0xFF, 0xFF, 0x17
    db 0x5F, 0x69, 0x2C, 0x38
    db 0xF3, 0x0B, 0x40, 0xF9
    db 0xF4, 0x0F, 0x40, 0xF9
    db 0xFD, 0x7B, 0xC3, 0xA8
    db 0xC0, 0x03, 0x5F, 0xD6
.bytes_arm_fmt_end:


emit_arm_alloc:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_alloc]
    mov rdx, .bytes_arm_alloc_end - .bytes_arm_alloc
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_alloc:
    db 0xFD, 0x7B, 0xBE, 0xA9    ; stp x29, x30, [sp, #-32]!
    db 0xFD, 0x03, 0x00, 0x91    ; mov x29, sp
    db 0xE0, 0x0B, 0x00, 0xF9    ; str x0, [sp, #16]
    db 0x01, 0x20, 0x00, 0x91    ; add x1, x0, #8
    db 0x00, 0x00, 0x80, 0xD2    ; mov x0, #0
    db 0x62, 0x00, 0x80, 0xD2    ; mov x2, #3 (PROT_READ|PROT_WRITE)
    db 0x43, 0x04, 0x80, 0xD2    ; mov x3, #34 (MAP_PRIVATE|MAP_ANONYMOUS)
    db 0x04, 0x00, 0x80, 0x92    ; mov x4, #-1
    db 0x05, 0x00, 0x80, 0xD2    ; mov x5, #0
    db 0xC8, 0x1B, 0x80, 0xD2    ; mov x8, #222 (sys_mmap)
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0xE1, 0x0B, 0x40, 0xF9    ; ldr x1, [sp, #16]
    db 0x01, 0x00, 0x00, 0xF9    ; str x1, [x0]
    db 0x00, 0x20, 0x00, 0x91    ; add x0, x0, #8
    db 0xFD, 0x7B, 0xC2, 0xA8    ; ldp x29, x30, [sp], #32
    db 0xC0, 0x03, 0x5F, 0xD6    ; ret
.bytes_arm_alloc_end:


emit_arm_free:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_free]
    mov rdx, .bytes_arm_free_end - .bytes_arm_free
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_free:
    db 0xFD, 0x7B, 0xBF, 0xA9    ; stp x29, x30, [sp, #-16]!
    db 0xFD, 0x03, 0x00, 0x91    ; mov x29, sp
    db 0xC0, 0x00, 0x00, 0xB4    ; cbz x0, +6
    db 0x01, 0x80, 0x5F, 0xF8    ; ldur x1, [x0, #-8]
    db 0x21, 0x20, 0x00, 0x91    ; add x1, x1, #8
    db 0x00, 0x20, 0x00, 0xD1    ; sub x0, x0, #8
    db 0xE8, 0x1A, 0x80, 0xD2    ; mov x8, #215 (sys_munmap)
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0xFD, 0x7B, 0xC1, 0xA8    ; ldp x29, x30, [sp], #16
    db 0xC0, 0x03, 0x5F, 0xD6    ; ret
.bytes_arm_free_end:


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
    db 0xA0, 0x0C, 0x80, 0xD2    ; mov x0, #101
    db 0xC8, 0x0B, 0x80, 0xD2    ; mov x8, #94 (sys_exit_group)
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db "RuntimeError: division by zero", 10, 0
.bytes_arm_dz_end:


emit_arm_overflow_trap:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_ovf]
    mov rdx, .bytes_arm_ovf_end - .bytes_arm_ovf
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_ovf:
    db 0x40, 0x00, 0x80, 0xD2    ; mov x0, #2
    db 0xE1, 0x00, 0x00, 0x10    ; adr x1, +28
    db 0xE2, 0x03, 0x80, 0xD2    ; mov x2, #31
    db 0x08, 0x08, 0x80, 0xD2    ; mov x8, #64
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0xA0, 0x0C, 0x80, 0xD2    ; mov x0, #101
    db 0xC8, 0x0B, 0x80, 0xD2    ; mov x8, #94 (sys_exit_group)
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db "RuntimeError: integer overflow", 10, 0
.bytes_arm_ovf_end:


emit_arm_type_mismatch_trap:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_tm]
    mov rdx, .bytes_arm_tm_end - .bytes_arm_tm
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

.bytes_arm_tm:
    db 0x40, 0x00, 0x80, 0xD2    ; mov x0, #2
    db 0xE1, 0x00, 0x00, 0x10    ; adr x1, +28
    db 0x82, 0x06, 0x80, 0xD2    ; mov x2, #52
    db 0x08, 0x08, 0x80, 0xD2    ; mov x8, #64
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db 0xA0, 0x0C, 0x80, 0xD2    ; mov x0, #101
    db 0xC8, 0x0B, 0x80, 0xD2    ; mov x8, #94 (sys_exit_group)
    db 0x01, 0x00, 0x00, 0xD4    ; svc #0
    db "RuntimeError: type mismatch in arithmetic operation", 10, 0, 0, 0, 0
.bytes_arm_tm_end:


emit_arm_input:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, rdi

    lea rsi, [rel .bytes_arm_inp]
    mov rdx, .bytes_arm_inp_end - .bytes_arm_inp
    mov rdi, r12
    call emit_bytes

    pop r12
    pop rbp
    ret

; NOTE: Inter-stub dependency — emit_arm_input calls emit_arm_alloc.
; The BL instruction at offset +0x44 inside .bytes_arm_inp is dynamically back-patched
; in arm_emit.asm using patch_dword.
.bytes_arm_inp:
    db 0xFD, 0x7B, 0xBD, 0xA9
    db 0xFD, 0x03, 0x00, 0x91
    db 0xF3, 0x0B, 0x00, 0xF9
    db 0xF4, 0x0F, 0x00, 0xF9
    db 0xF5, 0x13, 0x00, 0xF9
    db 0xF3, 0x03, 0x00, 0xAA
    db 0xF4, 0x03, 0x01, 0xAA
    db 0x7F, 0x02, 0x00, 0xF1
    db 0x00, 0x01, 0x00, 0x54
    db 0x9F, 0x02, 0x00, 0xF1
    db 0xC0, 0x00, 0x00, 0x54
    db 0x20, 0x00, 0x80, 0xD2
    db 0xE1, 0x03, 0x13, 0xAA
    db 0xE2, 0x03, 0x14, 0xAA
    db 0x08, 0x08, 0x80, 0xD2
    db 0x01, 0x00, 0x00, 0xD4
    db 0x00, 0x20, 0x80, 0xD2
    db 0x00, 0x00, 0x00, 0x94    ; +0x44: BL alloc placeholder
    db 0xF5, 0x03, 0x00, 0xAA
    db 0x13, 0x00, 0x80, 0xD2
    db 0x7F, 0xFA, 0x03, 0xF1
    db 0x2A, 0x02, 0x00, 0x54
    db 0x00, 0x00, 0x80, 0xD2
    db 0xA1, 0x02, 0x13, 0x8B
    db 0x22, 0x00, 0x80, 0xD2
    db 0xE8, 0x07, 0x80, 0xD2
    db 0x01, 0x00, 0x00, 0xD4
    db 0x1F, 0x04, 0x00, 0xF1
    db 0x41, 0x01, 0x00, 0x54
    db 0xAB, 0x6A, 0x73, 0x38
    db 0x7F, 0x29, 0x00, 0x71
    db 0xA0, 0x00, 0x00, 0x54
    db 0x7F, 0x35, 0x00, 0x71
    db 0x60, 0x00, 0x00, 0x54
    db 0x73, 0x06, 0x00, 0x91
    db 0xF1, 0xFF, 0xFF, 0x17
    db 0xBF, 0x6A, 0x33, 0x38
    db 0x02, 0x00, 0x00, 0x14
    db 0xBF, 0x6A, 0x33, 0x38
    db 0xF3, 0x08, 0x00, 0xB4
    db 0x0D, 0x00, 0x80, 0xD2
    db 0xAB, 0x02, 0x40, 0x39
    db 0x7F, 0xB5, 0x00, 0x71
    db 0x81, 0x00, 0x00, 0x54
    db 0x2D, 0x00, 0x80, 0xD2
    db 0x7F, 0x06, 0x00, 0xF1
    db 0x00, 0x08, 0x00, 0x54
    db 0x0C, 0x00, 0x80, 0xD2
    db 0x0E, 0x00, 0x80, 0xD2
    db 0xEF, 0x03, 0x0D, 0xAA
    db 0xFF, 0x01, 0x13, 0xEB
    db 0xAA, 0x01, 0x00, 0x54
    db 0xAB, 0x6A, 0x6F, 0x38
    db 0x7F, 0xB9, 0x00, 0x71
    db 0x61, 0x00, 0x00, 0x54
    db 0x8C, 0x05, 0x00, 0x91
    db 0x06, 0x00, 0x00, 0x14
    db 0x7F, 0xC1, 0x00, 0x71
    db 0x8B, 0x06, 0x00, 0x54
    db 0x7F, 0xE5, 0x00, 0x71
    db 0x4C, 0x06, 0x00, 0x54
    db 0xCE, 0x05, 0x00, 0x91
    db 0xEF, 0x05, 0x00, 0x91
    db 0xF3, 0xFF, 0xFF, 0x17
    db 0xCE, 0x05, 0x00, 0xB4
    db 0x9F, 0x01, 0x00, 0xF1
    db 0x80, 0x00, 0x00, 0x54
    db 0x9F, 0x05, 0x00, 0xF1
    db 0xA0, 0x02, 0x00, 0x54
    db 0x29, 0x00, 0x00, 0x14
    db 0x00, 0x00, 0x80, 0xD2
    db 0xAF, 0x02, 0x0D, 0x8B
    db 0x4A, 0x01, 0x80, 0xD2
    db 0xEB, 0x01, 0x40, 0x39
    db 0x2B, 0x01, 0x00, 0x34
    db 0x7F, 0xC1, 0x00, 0x71
    db 0xEB, 0x00, 0x00, 0x54
    db 0x7F, 0xE5, 0x00, 0x71
    db 0xAC, 0x00, 0x00, 0x54
    db 0x6B, 0xC1, 0x00, 0x51
    db 0x00, 0x2C, 0x0A, 0x9B
    db 0xEF, 0x05, 0x00, 0x91
    db 0xF7, 0xFF, 0xFF, 0x17
    db 0xAB, 0x02, 0x40, 0x39
    db 0x7F, 0xB5, 0x00, 0x71
    db 0x41, 0x00, 0x00, 0x54
    db 0xE0, 0x03, 0x00, 0xCB
    db 0x21, 0x00, 0x80, 0xD2
    db 0x18, 0x00, 0x00, 0x14
    db 0x00, 0x00, 0x80, 0xD2
    db 0xAF, 0x02, 0x0D, 0x8B
    db 0x4A, 0x01, 0x80, 0xD2
    db 0xEB, 0x01, 0x40, 0x39
    db 0x6B, 0x01, 0x00, 0x34
    db 0x7F, 0xB9, 0x00, 0x71
    db 0x20, 0x01, 0x00, 0x54
    db 0x7F, 0xC1, 0x00, 0x71
    db 0xEB, 0x00, 0x00, 0x54
    db 0x7F, 0xE5, 0x00, 0x71
    db 0xAC, 0x00, 0x00, 0x54
    db 0x6B, 0xC1, 0x00, 0x51
    db 0x00, 0x2C, 0x0A, 0x9B
    db 0xEF, 0x05, 0x00, 0x91
    db 0xF5, 0xFF, 0xFF, 0x17
    db 0xAB, 0x02, 0x40, 0x39
    db 0x7F, 0xB5, 0x00, 0x71
    db 0x41, 0x00, 0x00, 0x54
    db 0xE0, 0x03, 0x00, 0xCB
    db 0x41, 0x00, 0x80, 0xD2
    db 0x03, 0x00, 0x00, 0x14
    db 0xE0, 0x03, 0x15, 0xAA
    db 0x61, 0x00, 0x80, 0xD2
    db 0xF3, 0x0B, 0x40, 0xF9
    db 0xF4, 0x0F, 0x40, 0xF9
    db 0xF5, 0x13, 0x40, 0xF9
    db 0xFD, 0x7B, 0xC3, 0xA8
    db 0xC0, 0x03, 0x5F, 0xD6
.bytes_arm_inp_end:


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
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12, rdi             ; str_ptr
    xor rcx, rcx             ; len = 0
.ps_len_loop:
    cmp byte [r12 + rcx], 0
    je .ps_len_done
    inc rcx
    jmp .ps_len_loop
.ps_len_done:
    mov rdx, rcx             ; len
    mov rsi, r12
    mov rdi, 1               ; STDOUT
    mov rax, 1               ; sys_write
    syscall

    sub rsp, 16
    mov byte [rsp], 10
    mov rdi, 1
    mov rsi, rsp
    mov rdx, 1
    mov rax, 1
    syscall
    add rsp, 16

    pop r12
    pop rbx
    pop rbp
    ret
_stub_x86_print_str_end:


_stub_x86_div_zero:
    mov rdi, 2          ; STDERR
    lea rsi, [rel .msg]
    mov rdx, 31         ; len
    mov rax, 1          ; sys_write
    syscall
    mov rdi, 101        ; exit code 101
    mov rax, 60         ; sys_exit
    syscall
.msg: db "RuntimeError: division by zero", 10
_stub_x86_div_zero_end:


_stub_x86_overflow:
    mov rdi, 2          ; STDERR
    lea rsi, [rel .msg]
    mov rdx, 31         ; len ("RuntimeError: integer overflow\n")
    mov rax, 1          ; sys_write
    syscall
    mov rdi, 101        ; exit code 101
    mov rax, 60         ; sys_exit
    syscall
.msg: db "RuntimeError: integer overflow", 10
_stub_x86_overflow_end:


_stub_x86_type_mismatch:
    mov rdi, 2          ; STDERR
    lea rsi, [rel .msg]
    mov rdx, 52         ; len ("RuntimeError: type mismatch in arithmetic operation\n")
    mov rax, 1          ; sys_write
    syscall
    mov rdi, 101        ; exit code 101
    mov rax, 60         ; sys_exit
    syscall
.msg: db "RuntimeError: type mismatch in arithmetic operation", 10
_stub_x86_type_mismatch_end:


; NOTE: Inter-stub dependency — _stub_x86_input calls _stub_x86_alloc.
; The call instruction below (at +0x34 from _stub_x86_input) is back-patched
; dynamically in x86_emit.asm using patch_dword so that stub emission order
; changes do not alter or break the target displacement.
_stub_x86_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; prompt_ptr
    mov r13, rsi             ; prompt_len

    test r12, r12
    jz .input_read
    test r13, r13
    jz .input_read

    mov rdi, 1               ; STDOUT
    mov rsi, r12
    mov rdx, r13
    mov rax, 1               ; sys_write
    syscall

.input_read:
    mov rdi, 256
    call _stub_x86_alloc
    mov r14, rax             ; r14 = buf_ptr

    xor r15, r15             ; bytes_read = 0
.read_byte_loop:
    cmp r15, 254
    jge .read_done

    mov rdi, 0               ; STDIN
    lea rsi, [r14 + r15]
    mov rdx, 1
    mov rax, 0               ; sys_read
    syscall
    test rax, rax
    jle .read_done

    mov cl, [r14 + r15]
    cmp cl, 10               ; '\n'
    je .chop_nl
    cmp cl, 13               ; '\r'
    je .read_byte_loop
    inc r15
    jmp .read_byte_loop

.chop_nl:
    mov byte [r14 + r15], 0
    jmp .read_done_term

.read_done:
    mov byte [r14 + r15], 0  ; null terminate

.read_done_term:
    test r15, r15
    jz .input_is_str

    xor rcx, rcx             ; start_idx = 0
    mov rsi, r14
    mov al, [rsi]
    cmp al, '-'
    jne .check_digits
    mov rcx, 1               ; start_idx = 1
    cmp r15, 1
    je .input_is_str         ; "-" alone is str

.check_digits:
    xor r8, r8               ; dot_count = 0
    xor r9, r9               ; digit_count = 0
    mov rbx, rcx             ; start_idx

.scan_loop:
    cmp rbx, r15
    jge .scan_done
    mov al, [rsi + rbx]
    cmp al, '.'
    jne .chk_digit
    inc r8
    jmp .next_char

.chk_digit:
    cmp al, '0'
    jl .input_is_str
    cmp al, '9'
    jg .input_is_str
    inc r9

.next_char:
    inc rbx
    jmp .scan_loop

.scan_done:
    test r9, r9
    jz .input_is_str         ; no digits

    cmp r8, 0
    je .input_is_int
    cmp r8, 1
    je .input_is_float
    jmp .input_is_str

.input_is_int:
    xor rax, rax
    mov rdi, r14
    add rdi, rcx
.parse_int_loop:
    mov bl, [rdi]
    test bl, bl
    jz .parse_int_done
    cmp bl, '0'
    jl .parse_int_done
    cmp bl, '9'
    jg .parse_int_done
    sub bl, '0'
    imul rax, 10
    movzx rbx, bl
    add rax, rbx
    inc rdi
    jmp .parse_int_loop

.parse_int_done:
    cmp byte [r14], '-'
    jne .int_pos
    neg rax
.int_pos:
    mov rdx, 1               ; tag = 1 (INT)
    jmp .input_done

.input_is_float:
    xor rax, rax
    mov rdi, r14
    add rdi, rcx
.parse_float_loop:
    mov bl, [rdi]
    test bl, bl
    jz .parse_float_done
    cmp bl, '.'
    je .parse_float_done
    cmp bl, '0'
    jl .parse_float_done
    cmp bl, '9'
    jg .parse_float_done
    sub bl, '0'
    imul rax, 10
    movzx rbx, bl
    add rax, rbx
    inc rdi
    jmp .parse_float_loop

.parse_float_done:
    cmp byte [r14], '-'
    jne .float_pos
    neg rax
.float_pos:
    mov rdx, 2               ; tag = 2 (FLOAT)
    jmp .input_done

.input_empty:
.input_is_str:
    mov rax, r14             ; val = string ptr
    mov rdx, 3               ; tag = 3 (STRING)

.input_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
_stub_x86_input_end:


_stub_x86_alloc:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi             ; rbx = n (requested size)
    lea rsi, [rbx + 8]       ; rsi = n + 8 (mmap len)

    xor rdi, rdi             ; addr = 0
    mov rdx, 3               ; prot = PROT_READ|PROT_WRITE
    mov r10, 0x22            ; flags = MAP_PRIVATE|MAP_ANONYMOUS
    mov r8, -1               ; fd = -1
    xor r9, r9               ; offset = 0
    mov rax, 9               ; sys_mmap = 9
    syscall

    mov [rax], rbx           ; store size n in header
    add rax, 8               ; return ptr + 8

    pop r12
    pop rbx
    pop rbp
    ret
_stub_x86_alloc_end:


_stub_x86_free:
    push rbp
    mov rbp, rsp

    test rdi, rdi
    jz .free_done

    mov rsi, [rdi - 8]       ; rsi = n
    add rsi, 8               ; rsi = n + 8 (munmap len)
    sub rdi, 8               ; rdi = ptr - 8 (munmap addr)
    mov rax, 11              ; sys_munmap = 11
    syscall

.free_done:
    pop rbp
    ret
_stub_x86_free_end:


_stub_x86_format_int:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rax, rdi             ; int val
    mov r12, rsi             ; buf_ptr
    sub rsp, 32
    lea rsi, [rsp + 31]
    mov byte [rsi], 0
    mov rcx, 0
    mov rbx, 10

    test rax, rax
    jnz .fmt_check_neg
    mov byte [r12], '0'
    mov byte [r12 + 1], 0
    mov rax, 1
    jmp .fmt_done

.fmt_check_neg:
    xor r13, r13             ; is_neg = 0
    test rax, rax
    jns .fmt_loop
    mov r13, 1
    neg rax

.fmt_loop:
    test rax, rax
    jz .fmt_sign
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    jmp .fmt_loop

.fmt_sign:
    test r13, r13
    jz .fmt_copy
    dec rsi
    mov byte [rsi], '-'
    inc rcx

.fmt_copy:
    mov rax, rcx             ; formatted len
    mov rbx, r12             ; dst
.copy_loop:
    test rcx, rcx
    jz .fmt_done
    mov dl, [rsi]
    mov [rbx], dl
    inc rsi
    inc rbx
    dec rcx
    jmp .copy_loop

.fmt_done:
    mov byte [r12 + rax], 0
    mov rsi, r12
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
_stub_x86_format_int_end:
