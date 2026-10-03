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

; src/codegen/x86_emit.asm - x86-64 Machine Code Emitter for CAP v0.1
default rel

%include "src/ast.inc"
%include "src/codegen/target.inc"

section .data
err_unsupported_asm: db "SyntaxError: asm block contains unsupported instruction. Supported instructions: mov, add, sub, syscall, ret, push, pop", 10, 0
s_print:             db "print", 0
s_input:             db "input", 0
s_fstring:           db "fstring", 0
s_main:              db "main", 0
s_syscall:           db "syscall", 0
s_ret:               db "ret", 0
s_mov:               db "mov", 0
s_add:               db "add", 0
s_sub:               db "sub", 0
s_push:              db "push", 0
s_pop:               db "pop", 0

section .text
global x86_emit_program
extern emit_byte, emit_dword, emit_qword, emit_bytes, patch_dword
extern emit_x86_print_int, emit_x86_print_str, emit_x86_div_zero_trap, emit_x86_overflow_trap, emit_x86_alloc, emit_x86_input, emit_x86_type_mismatch_trap, emit_x86_format_int
extern sym_init, add_symbol, add_symbol_type, find_symbol_entry, find_symbol_offset
extern find_struct_decl, find_struct_field, resolve_field_access
extern fn_sym_init, add_fn_symbol, find_fn_symbol
extern print_err, print_err_bytes, sys_exit, str_ncmp, parse_dec_int, parse_int_literal
extern boot_thin_header

struc X86State
    .code_buf:     resq 1
    .print_int_off:resq 1
    .print_str_off:resq 1
    .div_zero_off: resq 1
    .overflow_off: resq 1
    .alloc_off:    resq 1
    .input_off:    resq 1
    .type_mismatch_off: resq 1
    .format_int_off: resq 1
    .fn_main_off:  resq 1
    .stack_offset: resq 1
    .loop_start:   resq 1
    .loop_end:     resq 1
    .ast_root:     resq 1
    .target_mode:  resq 1
endstruc

section .bss
xstate: resb X86State_size
defer_nodes: resq 256
defer_count: resq 1
scope_defer_base: resq 64
scope_depth: resq 1
x86_break_head: resq 1

section .text

x86_emit_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; code_buf
    mov r14, rdx             ; target_mode

    mov [xstate + X86State.code_buf], r13
    mov [xstate + X86State.ast_root], r12
    mov [xstate + X86State.target_mode], r14
    call fn_sym_init

    cmp r14, TARGET_FREESTANDING
    je .emit_freestanding_start
    cmp r14, TARGET_BOOT_THIN
    je .emit_freestanding_start
    cmp r14, TARGET_NO_BOOT_STUB
    je .emit_functions

    ; --- HOSTED _start ---
    ; call main (E8 <rel32>) - place-holder rel32 = 0
    mov rdi, r13
    mov sil, 0xE8
    call emit_byte
    mov rdi, r13
    xor rsi, rsi
    call emit_dword          ; offset 1 is rel32 for main

    ; mov rdi, rax (48 89 C7)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte

    ; mov rax, 60 (48 C7 C0 3C 00 00 00)
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov esi, 60
    call emit_dword

    ; syscall (0F 05)
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x05
    call emit_byte

    ; 2. Emit Runtime Stubs
    mov rax, [r13 + 16]      ; current len
    mov [xstate + X86State.print_int_off], rax
    mov rdi, r13
    call emit_x86_print_int

    mov rax, [r13 + 16]
    mov [xstate + X86State.print_str_off], rax
    mov rdi, r13
    call emit_x86_print_str

    mov rax, [r13 + 16]
    mov [xstate + X86State.div_zero_off], rax
    mov rdi, r13
    call emit_x86_div_zero_trap

    mov rax, [r13 + 16]
    mov [xstate + X86State.overflow_off], rax
    mov rdi, r13
    call emit_x86_overflow_trap

    mov rax, [r13 + 16]
    mov [xstate + X86State.type_mismatch_off], rax
    mov rdi, r13
    call emit_x86_type_mismatch_trap

    mov rax, [r13 + 16]
    mov [xstate + X86State.input_off], rax
    mov rdi, r13
    call emit_x86_input

    mov rax, [r13 + 16]
    mov [xstate + X86State.alloc_off], rax
    mov rdi, r13
    call emit_x86_alloc

    mov rax, [r13 + 16]
    mov [xstate + X86State.format_int_off], rax
    mov rdi, r13
    call emit_x86_format_int

    ; Dynamically patch inter-stub call in _stub_x86_input calling _stub_x86_alloc.
    mov rax, [xstate + X86State.alloc_off]
    mov rcx, [xstate + X86State.input_off]
    add rcx, 0x39            ; input_off + 0x34 + 5
    sub rax, rcx             ; rel32
    mov rdi, r13             ; code_buf
    mov rsi, [xstate + X86State.input_off]
    add rsi, 0x35            ; patch offset
    mov rdx, rax             ; rel32
    call patch_dword
    jmp .emit_functions

.emit_freestanding_start:
    ; --- FREESTANDING _start ---
    ; call main (E8 <rel32>)
    mov rdi, r13
    mov sil, 0xE8
    call emit_byte
    mov rdi, r13
    xor rsi, rsi
    call emit_dword          ; offset 1 is rel32 for main

    ; cli (FA)
    mov rdi, r13
    mov sil, 0xFA
    call emit_byte

    ; hlt (F4)
    mov rdi, r13
    mov sil, 0xF4
    call emit_byte

    ; jmp $-3 (EB FD)
    mov rdi, r13
    mov sil, 0xEB
    call emit_byte
    mov sil, 0xFD
    call emit_byte

.emit_functions:
    ; 3. Emit All Functions in AST
    mov rbx, [r12 + ASTNode.child1]
.fn_loop:
    test rbx, rbx
    jz .done_fns

    cmp qword [rbx + ASTNode.type], AST_FN_DECL
    jne .next_top

    mov rdi, rbx
    call x86_emit_fn

.next_top:
    mov rbx, [rbx + ASTNode.next]
    jmp .fn_loop

.done_fns:
    cmp r14, TARGET_NO_BOOT_STUB
    je .no_patch_main
    cmp r14, TARGET_BOOT_THIN
    je .patch_boot_thin_main

    ; Patch call main in _start (at file offset 1)
    mov rax, [xstate + X86State.fn_main_off]
    sub rax, 5               ; rel32 = target - (1 + 4)
    mov rdi, r13
    mov rsi, 1
    mov rdx, rax
    call patch_dword
    jmp .no_patch_main

.patch_boot_thin_main:
    mov rax, [xstate + X86State.fn_main_off]
    add rax, 251             ; rel32 = (512 + fn_main_off) - (256 + 5) = 251 + fn_main_off
    lea rdi, [boot_thin_header]
    mov dword [rdi + 257], eax

.no_patch_main:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


x86_patch_break_list:
    push rbp
    mov rbp, rsp
    push rbx
    push r10

    mov rax, [rdi + 16]        ; len
    mov rbx, [x86_break_head]
.patch_loop:
    test rbx, rbx
    jz .done
    mov rcx, [rdi + 0]         ; ptr
    mov r10d, [rcx + rbx]
    mov rdx, rax
    sub rdx, rbx
    sub rdx, 4
    push rax
    push r10
    mov rsi, rbx
    call patch_dword
    pop r10
    pop rax
    mov rbx, r10
    jmp .patch_loop
.done:
    pop r10
    pop rbx
    pop rbp
    ret


x86_emit_fn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov qword [defer_count], 0
    mov qword [scope_depth], 0
    mov qword [scope_defer_base], 0
    mov qword [x86_break_head], 0

    mov r12, rdi             ; fn AST node
    mov r13, [xstate + X86State.code_buf]

    ; Register function in fn_table
    mov rax, [r13 + 16]      ; current code offset
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rax
    call add_fn_symbol

    ; Check if this is main
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_main
    mov rdx, [r12 + ASTNode.val_len]
    call str_ncmp
    test rax, rax
    jnz .not_main
    mov rax, [r13 + 16]      ; len
    mov [xstate + X86State.fn_main_off], rax
.not_main:

    cmp qword [r12 + ASTNode.extra], 1
    je .naked_fn_body

    ; Prologue:
    ; push rbp (55)
    mov rdi, r13
    mov sil, 0x55
    call emit_byte
    ; mov rbp, rsp (48 89 E5)
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xE5
    call emit_byte
    ; sub rsp, 512 (48 81 EC 00 02 00 00)
    mov sil, 0x48
    call emit_byte
    mov sil, 0x81
    call emit_byte
    mov sil, 0xEC
    call emit_byte
    mov esi, 512
    call emit_dword

    call sym_init
    mov qword [xstate + X86State.stack_offset], 8

    ; Process Parameters (child1)
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10             ; param counter
.param_loop:
    test rbx, rbx
    jz .body

    mov r15, [xstate + X86State.stack_offset]
    mov r8, [rbx + ASTNode.child1]     ; type ptr (if struct)
    mov r9, [rbx + ASTNode.child2]     ; type len (if struct)

    test r8, r8
    jz .p_scalar

    push rbx
    push r10
    mov rdi, [xstate + X86State.ast_root]
    mov rsi, r8
    mov rdx, r9
    call find_struct_decl
    pop r10
    pop rbx
    test rax, rax
    jz .p_scalar

    mov r11, [rax + ASTNode.extra]     ; struct size
    push rbx
    push r10
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    mov rdx, r15
    mov rcx, [rbx + ASTNode.child1]
    mov r8, [rbx + ASTNode.child2]
    call add_symbol_type
    pop r10
    pop rbx

    add qword [xstate + X86State.stack_offset], r11
    xor r14, r14
.p_copy_loop:
    cmp r14, r11
    jge .param_next

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte

    cmp r10, 0
    je .sp0
    cmp r10, 1
    je .sp1
    cmp r10, 2
    je .sp2
    cmp r10, 3
    je .sp3
    cmp r10, 4
    je .sp4
    jmp .sp5

.sp0: mov sil, 0x7D
    jmp .emit_sp_disp
.sp1: mov sil, 0x75
    jmp .emit_sp_disp
.sp2: mov sil, 0x55
    jmp .emit_sp_disp
.sp3: mov sil, 0x4D
    jmp .emit_sp_disp
.sp4: mov sil, 0x45
    jmp .emit_sp_disp
.sp5: mov sil, 0x4D
.emit_sp_disp:
    call emit_byte
    mov rax, r15
    add rax, r14
    neg rax
    mov sil, al
    call emit_byte

    inc r10
    add r14, 8
    jmp .p_copy_loop

.p_scalar:
    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [xstate + X86State.stack_offset], 16

    mov r15, rcx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte

    cmp r10, 0
    je .p0
    cmp r10, 1
    je .p1
    cmp r10, 2
    je .p2
    cmp r10, 3
    je .p3
    cmp r10, 4
    je .p4
    jmp .p5

.p0: mov sil, 0x7D
    jmp .emit_p_disp
.p1: mov sil, 0x75
    jmp .emit_p_disp
.p2: mov sil, 0x55
    jmp .emit_p_disp
.p3: mov sil, 0x4D
    jmp .emit_p_disp
.p4: mov sil, 0x45
    jmp .emit_p_disp
.p5: mov sil, 0x4D
.emit_p_disp:
    call emit_byte
    mov rax, r15
    neg rax
    mov sil, al
    call emit_byte

    ; Store tag 1 for parameter: mov qword [rbp - (r15 + 8)], 1
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, r15
    add rax, 8
    neg rax
    mov esi, eax
    call emit_dword
    mov esi, 1
    call emit_dword

    inc r10

.param_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .param_loop

.body:
    ; Emit Function Body (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt

    ; Epilogue:
    ; xor rax, rax (for default return 0 if falls through)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xC0
    call emit_byte

    ; mov rsp, rbp (48 89 EC)
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xEC
    call emit_byte
    ; pop rbp (5D)
    mov sil, 0x5D
    call emit_byte
    ; ret (C3)
    mov sil, 0xC3
    call emit_byte

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.naked_fn_body:
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


x86_emit_stmt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; stmt node
    mov r13, [xstate + X86State.code_buf]

.stmt_loop:
    test r12, r12
    jz .done

    mov rax, [r12 + ASTNode.type]

    cmp rax, AST_BLOCK
    je .s_block
    cmp rax, AST_VAR_DECL
    je .s_var_decl
    cmp rax, AST_FIELD_ASSIGN
    je .s_var_field_assign
    cmp rax, AST_DEFER
    je .s_defer
    cmp rax, AST_RETURN
    je .s_return
    cmp rax, AST_IF
    je .s_if
    cmp rax, AST_ELIF
    je .s_if
    cmp rax, AST_WHILE
    je .s_while
    cmp rax, AST_FOR
    je .s_for
    cmp rax, AST_LOOP
    je .s_loop
    cmp rax, AST_BREAK
    je .s_break
    cmp rax, AST_ASM_BLOCK
    je .s_asm_block
    cmp rax, AST_EXPR_STMT
    je .s_expr_stmt
    jmp .next

.s_block:
    inc qword [scope_depth]
    mov rcx, [scope_depth]
    mov rax, [defer_count]
    mov [scope_defer_base + rcx * 8], rax

    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_stmt

    mov rcx, [scope_depth]
    mov rbx, [scope_defer_base + rcx * 8]
.block_unwind_loop:
    cmp qword [defer_count], rbx
    jle .block_unwind_done
    dec qword [defer_count]
    mov rcx, [defer_count]
    mov rdi, [defer_nodes + rcx * 8]
    push rbx
    call x86_emit_stmt
    pop rbx
    jmp .block_unwind_loop

.block_unwind_done:
    dec qword [scope_depth]
    jmp .next

.s_defer:
    mov rcx, [defer_count]
    mov rax, [r12 + ASTNode.child1]
    mov [defer_nodes + rcx * 8], rax
    inc qword [defer_count]
    jmp .next

.s_var_decl:
    mov rbx, [r12 + ASTNode.child1]
    test rbx, rbx
    jz .next

    cmp qword [r12 + ASTNode.child2], 0
    jne .s_var_field_assign

    cmp qword [rbx + ASTNode.type], AST_STRUCT_LIT
    je .s_var_struct_lit

    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_symbol_offset
    cmp rax, -1
    jne .var_has_slot

    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [xstate + X86State.stack_offset], 16
    mov rax, rcx

.var_has_slot:
    push rax                 ; stack offset
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr       ; rax = val, rdx = tag
    pop rcx                  ; stack offset

    ; mov [rbp - off], rax
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword

    ; mov [rbp - off - 8], rdx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x95
    call emit_byte
    mov rax, rcx
    add rax, 8
    neg rax
    mov esi, eax
    call emit_dword
    jmp .next

.s_var_field_assign:
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    mov rdi, r13
    mov sil, 0x50
    call emit_byte           ; push rax (RHS)

    mov rdi, [xstate + X86State.ast_root]
    mov rsi, [r12 + ASTNode.child2]
    call resolve_field_access
    mov r8, rax              ; target offset

    mov rdi, r13
    mov sil, 0x59
    call emit_byte           ; pop rcx (RHS)

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov rax, r8
    neg rax
    mov esi, eax
    call emit_dword
    jmp .next

.s_var_struct_lit:
    mov r14, [rbx + ASTNode.val]
    mov r15, [rbx + ASTNode.val_len]

    mov rdi, [xstate + X86State.ast_root]
    mov rsi, r14
    mov rdx, r15
    call find_struct_decl
    test rax, rax
    jz .next
    mov r11, rax

    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    mov rcx, r14
    mov r8, r15
    push r11
    push rdx
    call add_symbol_type
    pop rcx
    pop r11

    mov rax, [r11 + ASTNode.extra]
    add qword [xstate + X86State.stack_offset], rax

    mov r10, [rbx + ASTNode.child1]
    xor r15, r15              ; current_field_offset = 0
    call .emit_x86_struct_lit_fields
    jmp .next

.emit_x86_struct_lit_fields:
.slit_loop:
    test r10, r10
    jz .slit_done

    mov rdi, r11
    mov rsi, [r10 + ASTNode.val]
    mov rdx, [r10 + ASTNode.val_len]
    push r11
    push r10
    push rcx
    push r15
    call find_struct_field
    pop r15
    pop rcx
    pop r10
    pop r11
    test rax, rax
    jz .slit_next

    mov r8, [rax + ASTNode.extra]     ; field offset inside struct
    add r8, r15                      ; total combined field offset
    mov r14, [r10 + ASTNode.child1]  ; field expr node

    cmp qword [r14 + ASTNode.type], AST_STRUCT_LIT
    je .slit_nested_struct

    push r11
    push r10
    push rcx
    push r15
    push r8
    mov rdi, r14
    call x86_emit_expr
    pop r8
    pop r15
    pop rcx
    pop r10
    pop r11

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    add rax, r8
    neg rax
    mov esi, eax
    call emit_dword
    jmp .slit_next

.slit_nested_struct:
    mov rdi, [xstate + X86State.ast_root]
    mov rsi, [rax + ASTNode.child1]  ; nested struct type name ptr
    mov rdx, [rax + ASTNode.child2]  ; nested struct type name len
    push r11
    push r10
    push rcx
    push r15
    push r8
    call find_struct_decl
    pop r8
    pop r15
    pop rcx
    pop r10
    pop r11
    test rax, rax
    jz .slit_next

    push r11
    push r10
    push rcx
    push r15
    mov r11, rax                     ; nested struct_decl
    mov r10, [r14 + ASTNode.child1]  ; nested FieldInit list
    mov r15, r8                      ; updated current_field_offset
    call .emit_x86_struct_lit_fields
    pop r15
    pop rcx
    pop r10
    pop r11

.slit_next:
    mov r10, [r10 + ASTNode.next]
    jmp .slit_loop

.slit_done:
    ret

.s_return:
    mov rdi, [r12 + ASTNode.child1]
    test rdi, rdi
    jz .ret_no_expr
    call x86_emit_expr
    jmp .ret_unwind

.ret_no_expr:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xC0
    call emit_byte

.ret_unwind:
    mov rdi, r13
    mov sil, 0x50
    call emit_byte           ; push rax (save return val)

    mov rbx, [defer_count]
.ret_unwind_loop:
    test rbx, rbx
    jz .ret_unwind_done
    dec rbx
    mov rdi, [defer_nodes + rbx * 8]
    push rbx
    call x86_emit_stmt
    pop rbx
    jmp .ret_unwind_loop

.ret_unwind_done:
    mov rdi, r13
    mov sil, 0x58
    call emit_byte           ; pop rax (restore return val)

.ret_epilogue:
    ; mov rsp, rbp (48 89 EC)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xEC
    call emit_byte
    ; pop rbp (5D)
    mov sil, 0x5D
    call emit_byte
    ; ret (C3)
    mov sil, 0xC3
    call emit_byte
    jmp .next

.s_if:
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    ; test rax, rax (48 85 C0)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    ; jz branch_else (0F 84 rel32)
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x84
    call emit_byte
    mov rbx, [r13 + 16]      ; offset of rel32
    push rbx
    xor rsi, rsi
    call emit_dword

    ; Emit then block (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt

    ; jmp branch_end (E9 rel32)
    mov rdi, r13
    mov sil, 0xE9
    call emit_byte
    mov r10, [r13 + 16]      ; offset of jmp rel32
    push r10
    xor rsi, rsi
    call emit_dword

    ; Patch jz rel32
    mov rax, [r13 + 16]
    pop r10
    pop rbx
    push r10
    sub rax, rbx
    sub rax, 4
    mov rdi, r13
    mov rsi, rbx
    mov rdx, rax
    call patch_dword

    ; Emit else/elif (child3)
    mov rdi, [r12 + ASTNode.child3]
    test rdi, rdi
    jz .patch_if_end
    call x86_emit_stmt

.patch_if_end:
    ; Patch jmp rel32
    mov rax, [r13 + 16]
    pop r10
    sub rax, r10
    sub rax, 4
    mov rdi, r13
    mov rsi, r10
    mov rdx, rax
    call patch_dword
    jmp .next

.s_while:
    push qword [x86_break_head]
    mov qword [x86_break_head], 0

    mov rbx, [r13 + 16]      ; loop_start
    mov [xstate + X86State.loop_start], rbx

    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    ; test rax, rax
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    ; jz loop_end (0F 84 rel32)
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x84
    call emit_byte
    mov r10, [r13 + 16]      ; jz rel32 offset
    push rbx
    push r10
    xor rsi, rsi
    call emit_dword

    ; Emit body (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt

    pop r10
    pop rbx

    ; jmp loop_start (E9 rel32)
    mov rdi, r13
    mov sil, 0xE9
    call emit_byte
    mov rax, rbx
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; Patch jz rel32
    mov rax, [r13 + 16]
    sub rax, r10
    sub rax, 4
    mov rdi, r13
    mov rsi, r10
    mov rdx, rax
    call patch_dword

    ; Patch breaks
    mov rdi, r13
    call x86_patch_break_list
    pop qword [x86_break_head]
    jmp .next

.s_for:
    push qword [x86_break_head]
    mov qword [x86_break_head], 0

    push rbp
    mov rbp, rsp
    sub rsp, 64              ; [rbp-8]=i_off, [rbp-16]=stop_off, [rbp-24]=step_off, [rbp-32]=pos_fixup, [rbp-40]=neg_fixup

    ; Bind loop var i on function stack frame
    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [xstate + X86State.stack_offset], 16
    mov [rbp - 8], rcx       ; for_i_off

    ; Store tag 1 for loop variable i: mov qword [rbp - (i_off + 8)], 1
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    add rax, 8
    neg rax
    mov esi, eax
    call emit_dword
    mov esi, 1
    call emit_dword

    ; Allocate stop limit slot
    mov rcx, [xstate + X86State.stack_offset]
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 16], rcx      ; for_stop_off

    ; Allocate step slot
    mov rcx, [xstate + X86State.stack_offset]
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 24], rcx      ; for_step_off

    ; Parse range args (child1 = AST_CALL range)
    mov rbx, [r12 + ASTNode.child1]
    mov rbx, [rbx + ASTNode.child1] ; arg1
    test rbx, rbx
    jz .for_done_init

    ; Check arg count
    mov r10, [rbx + ASTNode.next]   ; arg2
    test r10, r10
    jnz .range_2_or_3_args

    ; 1 arg: range(stop) -> start=0, stop=arg1, step=1
    mov rdi, rbx
    call x86_emit_expr
    mov rcx, [rbp - 16]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; store stop

    ; start = 0
    mov rcx, [rbp - 8]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword
    xor esi, esi
    call emit_dword          ; store start 0

    ; step = 1
    mov rcx, [rbp - 24]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword
    mov esi, 1
    call emit_dword          ; store step 1
    jmp .for_done_init

.range_2_or_3_args:
    ; Evaluate start (arg1)
    mov rdi, rbx
    call x86_emit_expr
    mov rcx, [rbp - 8]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; store start

    ; Evaluate stop (arg2)
    mov rdi, r10
    call x86_emit_expr
    mov rcx, [rbp - 16]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; store stop

    ; Check arg3
    mov r11, [r10 + ASTNode.next]
    test r11, r11
    jz .range_default_step

    ; Evaluate step (arg3)
    mov rdi, r11
    call x86_emit_expr
    mov rcx, [rbp - 24]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; store step
    jmp .for_done_init

.range_default_step:
    mov rcx, [rbp - 24]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword
    mov esi, 1
    call emit_dword          ; store step 1

.for_done_init:
    mov rbx, [r13 + 16]      ; loop_start

.for_head:
    ; Runtime check: cmp step, 0
    mov rcx, [rbp - 24]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xBD
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword
    mov sil, 0
    call emit_byte            ; cmp qword [rbp - step_off], 0

    ; jl .for_neg_step (0F 7C rel8)
    mov sil, 0x7C
    call emit_byte
    mov sil, 0x1C
    call emit_byte            ; jl +28

    ; --- Positive Step Case: check i >= stop ---
    mov rcx, [rbp - 8]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; mov rax, [rbp - i_off]

    mov rcx, [rbp - 16]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; mov rcx, [rbp - stop_off]

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC8
    call emit_byte          ; cmp rax, rcx

    ; jge for_end (0F 8D rel32)
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov rax, [r13 + 16]
    mov [rbp - 32], rax      ; for_pos_fixup
    xor rsi, rsi
    call emit_dword

    ; jmp .for_body (E9 +23)
    mov sil, 0xE9
    call emit_byte
    mov esi, 23
    call emit_dword

    ; --- Negative Step Case: check i <= stop ---
    mov rcx, [rbp - 8]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; mov rax, [rbp - i_off]

    mov rcx, [rbp - 16]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; mov rcx, [rbp - stop_off]

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC8
    call emit_byte          ; cmp rax, rcx

    ; jle for_end (0F 8E rel32)
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x8E
    call emit_byte
    mov rax, [r13 + 16]
    mov [rbp - 40], rax      ; for_neg_fixup
    xor rsi, rsi
    call emit_dword

.for_body:
    ; Emit body
    push rbx
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt
    pop rbx

    ; Increment loop var: i += step
    mov rcx, [rbp - 24]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; mov rax, [rbp - step_off]

    mov rcx, [rbp - 8]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x01
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword          ; add [rbp - i_off], rax

    ; jmp for_head
    mov sil, 0xE9
    call emit_byte
    mov rax, rbx
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; Patch jge (pos)
    mov rax, [r13 + 16]
    mov rcx, [rbp - 32]
    sub rax, rcx
    sub rax, 4
    mov rdi, r13
    mov rsi, rcx
    mov rdx, rax
    call patch_dword

    ; Patch jle (neg)
    mov rax, [r13 + 16]
    mov rcx, [rbp - 40]
    sub rax, rcx
    sub rax, 4
    mov rdi, r13
    mov rsi, rcx
    mov rdx, rax
    call patch_dword

    mov rsp, rbp
    pop rbp

    ; Patch breaks
    mov rdi, r13
    call x86_patch_break_list
    pop qword [x86_break_head]

    jmp .next

.s_loop:
    push qword [x86_break_head]
    mov qword [x86_break_head], 0

    mov rbx, [r13 + 16]
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_stmt

    mov rdi, r13
    mov sil, 0xE9
    call emit_byte
    mov rax, rbx
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; Patch breaks
    mov rdi, r13
    call x86_patch_break_list
    pop qword [x86_break_head]
    jmp .next

.s_break:
    mov rdi, r13
    mov sil, 0xE9
    call emit_byte           ; jmp rel32

    mov rax, [r13 + 16]      ; fixup_off
    mov rsi, [x86_break_head]    ; old head
    mov rdi, r13
    call emit_dword          ; placeholder rel32 stores old head
    mov [x86_break_head], rax    ; new head
    jmp .next

.s_asm_block:
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_asm_lines
    jmp .next

.s_expr_stmt:
    mov rdi, [r12 + ASTNode.child1]
    test rdi, rdi
    jz .next
    call x86_emit_expr
    jmp .next

.next:
    mov r12, [r12 + ASTNode.next]
    jmp .stmt_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


x86_emit_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; expr node
    mov r13, [xstate + X86State.code_buf]

    mov rax, [r12 + ASTNode.type]

    cmp rax, AST_LITERAL
    je .e_literal
    cmp rax, AST_IDENT
    je .e_ident
    cmp rax, AST_BIN_OP
    je .e_bin_op
    cmp rax, AST_UN_OP
    je .e_un_op
    cmp rax, AST_CALL
    je .e_call
    cmp rax, AST_ALLOC
    je .e_alloc
    cmp rax, AST_STRUCT_LIT
    je .e_struct_lit
    cmp rax, AST_INDEX
    je .e_index
    cmp rax, AST_FIELD_ACCESS
    je .e_field_access
    jmp .done

.e_alloc:
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte            ; mov rdi, rax

    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.alloc_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

.print_end:
    jmp .done

.e_field_access:
    mov rdi, [xstate + X86State.ast_root]
    mov rsi, r12
    call resolve_field_access
    cmp rax, -1
    je .done

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x85
    call emit_byte
    neg rax
    mov esi, eax
    call emit_dword

    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword          ; rdx = 1 (INT tag)
    jmp .done

.e_literal:
    mov rdi, [r12 + ASTNode.val]
    mov rcx, [r12 + ASTNode.val_len]
    test rdi, rdi
    jz .e_lit_zero
    mov al, [rdi]
    cmp al, '0'
    jl .e_lit_str
    cmp al, '9'
    jg .e_lit_str

    xor r8, r8
.chk_float_dot:
    cmp r8, rcx
    jge .is_int_lit
    cmp byte [rdi + r8], '.'
    je .e_lit_float
    inc r8
    jmp .chk_float_dot

.e_lit_float:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xC0
    call emit_byte            ; xor rax, rax

    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 2
    call emit_dword          ; mov rdx, 2 (tag = 2 FLOAT)
    jmp .done

.is_int_lit:
    mov r8, [r12 + ASTNode.line]
    call parse_dec_int
    ; mov rax, imm64
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xB8
    call emit_byte
    mov rsi, rax
    call emit_qword

    ; mov rdx, 1 (tag = 1 INT)
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.e_lit_str:
    mov rbx, [r12 + ASTNode.val_len]
    mov rdi, r13
    mov sil, 0xEB
    call emit_byte
    mov rax, rbx
    inc rax
    mov sil, al
    call emit_byte

    mov r14, [r13 + 16]      ; str_addr_off

    mov rdi, r13
    mov rsi, [r12 + ASTNode.val]
    mov rdx, rbx
    call emit_bytes
    mov sil, 0
    call emit_byte           ; null byte

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov sil, 0x05
    call emit_byte
    mov rax, r14
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 3
    call emit_dword          ; tag = 3 STRING
    jmp .done

.e_lit_zero:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xD2
    call emit_byte
    jmp .done

.e_ident:
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_symbol_offset
    cmp rax, -1
    je .done

    mov rbx, rax             ; rbx = stack_offset

    ; mov rax, [rbp - off] (48 8B 85 <32-bit disp>)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rbx
    neg rax
    mov esi, eax
    call emit_dword

    ; mov rdx, [rbp - off - 8] (48 8B 95 <32-bit disp>)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x95
    call emit_byte
    mov rax, rbx
    add rax, 8
    neg rax
    mov esi, eax
    call emit_dword
    jmp .done

.e_bin_op:
    ; Left child (child1)
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr        ; rax = val, rdx = tag
    ; push rax (val), push rdx (tag)
    mov rdi, r13
    mov sil, 0x50
    call emit_byte           ; push rax
    mov sil, 0x52
    call emit_byte           ; push rdx

    ; Right child (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_expr       ; rax = right val, rdx = right tag

    ; pop r8 (left tag), pop rcx (left val)
    mov rdi, r13
    mov sil, 0x41
    call emit_byte
    mov sil, 0x58
    call emit_byte           ; pop r8 (left tag)
    mov sil, 0x59
    call emit_byte           ; pop rcx (left val)

    cmp qword [xstate + X86State.target_mode], TARGET_FREESTANDING
    je .skip_type_check
    cmp qword [xstate + X86State.target_mode], TARGET_BOOT_THIN
    je .skip_type_check

    ; Check if left tag (r8) != 1 or right tag (rdx) != 1
    mov sil, 0x49
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xF8
    call emit_byte
    mov sil, 0x01
    call emit_byte            ; cmp r8, 1
    mov sil, 0x75
    call emit_byte
    mov sil, 0x06
    call emit_byte            ; jne +6 (to trap call)

    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFA
    call emit_byte
    mov sil, 0x01
    call emit_byte            ; cmp rdx, 1
    mov sil, 0x74
    call emit_byte
    mov sil, 0x05
    call emit_byte            ; je +5 (skip)

    ; Trigger type_mismatch_trap
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.type_mismatch_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

.skip_type_check:
    ; Register contract for binary ops:
    ; LHS value is in rcx, RHS value is in rax.
    ; Result must be in rax, tag in rdx (1 = INT).
    mov r11, [r12 + ASTNode.val]
    mov r8b, [r11]
    mov r9b, [r11 + 1]

    cmp r8b, '&'
    je .op_band
    cmp r8b, '|'
    je .op_bor
    cmp r8b, '^'
    je .op_bxor
    cmp r8b, '<'
    je .chk_shl
    cmp r8b, '>'
    je .chk_shr

    cmp r8b, '+'
    je .op_add
    cmp r8b, '-'
    je .op_sub
    cmp r8b, '*'
    je .op_mul
    cmp r8b, '/'
    je .op_div
    cmp r8b, '%'
    je .op_mod
    cmp r8b, '='
    je .op_eq
    cmp r8b, '!'
    je .op_ne
    jmp .done

.chk_shl:
    cmp r9b, '<'
    je .op_shl
    jmp .op_lt

.chk_shr:
    cmp r9b, '>'
    je .op_shr
    jmp .op_gt

.op_band:
    ; and rax, rcx (48 21 C8)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x21
    call emit_byte
    mov sil, 0xC8
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.op_bor:
    ; or rax, rcx (48 09 C8)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x09
    call emit_byte
    mov sil, 0xC8
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.op_bxor:
    ; xor rax, rcx (48 31 C8)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xC8
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.op_shl:
    ; LHS is in rcx, RHS (shift count) is in rax.
    ; mov rbx, rcx (48 89 CB)
    ; mov rcx, rax (48 89 C1)
    ; mov rax, rbx (48 89 D8)
    ; sal rax, cl  (48 D3 E0)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xCB
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC1
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xD8
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0xD3
    call emit_byte
    mov sil, 0xE0
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.op_shr:
    ; LHS is in rcx, RHS (shift count) is in rax.
    ; mov rbx, rcx (48 89 CB)
    ; mov rcx, rax (48 89 C1)
    ; mov rax, rbx (48 89 D8)
    ; sar rax, cl  (48 D3 F8)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xCB
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC1
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xD8
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0xD3
    call emit_byte
    mov sil, 0xF8
    call emit_byte

    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.op_add:
    ; add rax, rcx (48 01 C8)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x01
    call emit_byte
    mov sil, 0xC8
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword          ; rdx = 1
    jmp .done

.op_sub:
    ; sub rcx, rax; mov rax, rcx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x29
    call emit_byte
    mov sil, 0xC1
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC8
    call emit_byte
    jmp .done

.op_mul:
    ; imul rax, rcx (48 0F AF C1)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0xAF
    call emit_byte
    mov sil, 0xC1
    call emit_byte
    jmp .done

.op_div:
    cmp qword [xstate + X86State.target_mode], TARGET_FREESTANDING
    je .raw_idiv
    cmp qword [xstate + X86State.target_mode], TARGET_BOOT_THIN
    je .raw_idiv

    ; Check division by zero: test rax, rax (48 85 C0)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x75
    call emit_byte
    mov sil, 0x05
    call emit_byte
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.div_zero_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; mov rbx, rax; mov rax, rcx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC3
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC8
    call emit_byte

    ; INT64_MIN / -1 Pre-check: cmp rbx, -1
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFB
    call emit_byte
    mov sil, 0xFF
    call emit_byte            ; cmp rbx, -1
    mov sil, 0x75
    call emit_byte
    mov sil, 0x14
    call emit_byte            ; jne +20 (.do_idiv)

    mov sil, 0x48
    call emit_byte
    mov sil, 0xBA
    call emit_byte
    mov rsi, 0x8000000000000000
    call emit_qword
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xD0
    call emit_byte            ; cmp rax, rdx
    mov sil, 0x75
    call emit_byte
    mov sil, 0x05
    call emit_byte            ; jne +5 (.do_idiv)

    ; Trigger overflow_trap!
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.overflow_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

.do_idiv:
    ; cqo; idiv rbx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x99
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xFB
    call emit_byte
    jmp .done

.raw_idiv:
    ; mov rbx, rax; mov rax, rcx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC3
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC8
    call emit_byte

    ; cqo; idiv rbx
    mov sil, 0x48
    call emit_byte
    mov sil, 0x99
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xFB
    call emit_byte
    jmp .done

.op_mod:
    cmp qword [xstate + X86State.target_mode], TARGET_FREESTANDING
    je .raw_imod
    cmp qword [xstate + X86State.target_mode], TARGET_BOOT_THIN
    je .raw_imod

    ; Check division by zero: test rax, rax (48 85 C0)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x75
    call emit_byte
    mov sil, 0x05
    call emit_byte
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.div_zero_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC3
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC8
    call emit_byte

    ; INT64_MIN / -1 Pre-check for mod (result is 0)
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFB
    call emit_byte
    mov sil, 0xFF
    call emit_byte            ; cmp rbx, -1
    mov sil, 0x75
    call emit_byte
    mov sil, 0x14
    call emit_byte            ; jne +20 (.do_imod)

    mov sil, 0x48
    call emit_byte
    mov sil, 0xBA
    call emit_byte
    mov rsi, 0x8000000000000000
    call emit_qword
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xD0
    call emit_byte            ; cmp rax, rdx
    mov sil, 0x75
    call emit_byte
    mov sil, 0x05
    call emit_byte            ; jne +5

    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xC0
    call emit_byte            ; xor rax, rax
    mov sil, 0xEB
    call emit_byte
    mov sil, 0x05
    call emit_byte            ; jmp +5 (.done)

.do_imod:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x99
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xFB
    call emit_byte            ; idiv rbx
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xD0
    call emit_byte            ; mov rax, rdx
    jmp .done

.raw_imod:
    ; mov rbx, rax; mov rax, rcx
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC3
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC8
    call emit_byte

    ; cqo; idiv rbx; mov rax, rdx
    mov sil, 0x48
    call emit_byte
    mov sil, 0x99
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xFB
    call emit_byte            ; idiv rbx
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xD0
    call emit_byte            ; mov rax, rdx
    jmp .done

.op_eq:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC1
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x94
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0xB6
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    jmp .done

.op_ne:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC1
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x95
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0xB6
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    jmp .done

.op_lt:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC1
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x9C
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0xB6
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    jmp .done

.op_gt:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC1
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x9F
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0x0F
    call emit_byte
    mov sil, 0xB6
    call emit_byte
    mov sil, 0xC0
    call emit_byte
    jmp .done

.e_un_op:
    mov rbx, [r12 + ASTNode.val]
    mov cl, [rbx]
    cmp cl, '-'
    jne .normal_un_op_x86

    mov rdi, [r12 + ASTNode.child1]
    cmp qword [rdi + ASTNode.type], AST_LITERAL
    jne .normal_un_op_x86

    mov rbx, [rdi + ASTNode.val]
    test rbx, rbx
    jz .normal_un_op_x86
    mov al, [rbx]
    cmp al, '0'
    jl .normal_un_op_x86
    cmp al, '9'
    jg .normal_un_op_x86

    mov rdi, rbx
    mov rcx, [r12 + ASTNode.child1]
    mov rcx, [rcx + ASTNode.val_len]
    mov rsi, 1
    mov r8, [r12 + ASTNode.line]
    call parse_int_literal

    ; mov rax, imm64
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xB8
    call emit_byte
    mov rsi, rax
    call emit_qword

    ; neg rax
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xD8
    call emit_byte

    ; mov rdx, 1 (tag = 1 INT)
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.normal_un_op_x86:
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    mov rbx, [r12 + ASTNode.val]
    mov cl, [rbx]
    cmp cl, '-'
    jne .chk_addr
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xD8
    call emit_byte
    jmp .done

.chk_addr:
    cmp cl, '~'
    je .op_bnot
    cmp cl, '&'
    jne .done
    jmp .do_addr

.op_bnot:
    ; Check if tag rdx != 1
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFA
    call emit_byte
    mov sil, 0x01
    call emit_byte            ; cmp rdx, 1
    mov sil, 0x74
    call emit_byte
    mov sil, 0x05
    call emit_byte            ; je +5 (skip)

    ; Trigger type_mismatch_trap
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.type_mismatch_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; not rax (48 F7 D0)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xD0
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.do_addr:
    mov rbx, [r12 + ASTNode.child1]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_fn_symbol
    cmp rax, -1
    je .addr_var

    ; Function symbol found! rax = code offset fn_off
    cmp qword [xstate + X86State.target_mode], TARGET_FREESTANDING
    je .addr_fn_fs
    cmp qword [xstate + X86State.target_mode], TARGET_BOOT_THIN
    je .addr_fn_boot_thin
    add rax, 0x400078         ; hosted base VA
    jmp .addr_fn_emit
.addr_fn_boot_thin:
    add rax, 0x100200         ; freestanding thin base VA (0x100000 + 512)
    jmp .addr_fn_emit
.addr_fn_fs:
    add rax, 0x100CC6         ; freestanding fat base VA (0x100000 + 3270)
.addr_fn_emit:
    ; Emit mov rax, imm64 (48 B8 <8-byte imm64>)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xB8
    call emit_byte
    mov rsi, rax              ; imm64 VA
    call emit_qword

    ; Set tag rdx = 1 (INT)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 1
    call emit_dword
    jmp .done

.addr_var:
    mov rbx, [r12 + ASTNode.child1]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_symbol_offset
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov sil, 0x85
    call emit_byte
    neg rax
    mov esi, eax
    call emit_dword
    jmp .done

.e_call:
    ; Check print
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_print
    mov rdx, [r12 + ASTNode.val_len]
    call str_ncmp
    test rax, rax
    jz .call_print

    ; Check input
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_input
    mov rdx, [r12 + ASTNode.val_len]
    call str_ncmp
    test rax, rax
    jz .call_input

    ; Check fstring
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_fstring
    mov rdx, [r12 + ASTNode.val_len]
    call str_ncmp
    test rax, rax
    jz .call_fstring
    jmp .user_call

.call_fstring:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov esi, 256
    call emit_dword          ; mov rdi, 256

    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.alloc_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword          ; call alloc_off -> rax = buf_ptr

    mov rdi, r13
    mov sil, 0x50
    call emit_byte           ; push rax (buf_start)
    mov sil, 0x50
    call emit_byte           ; push rax (curr_buf_ptr)

    mov rbx, [r12 + ASTNode.child1]
.fstr_loop:
    test rbx, rbx
    jz .fstr_done

    push rbx
    mov rdi, rbx
    call x86_emit_expr        ; at runtime rax = val, rdx = tag
    pop rbx

    ; Emit runtime check: cmp rdx, 3 (48 83 FA 03)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFA
    call emit_byte
    mov sil, 0x03
    call emit_byte

    ; je .fstr_copy_str (74 0F)
    mov sil, 0x74
    call emit_byte
    mov sil, 0x0F
    call emit_byte

.fstr_fmt_int:
    mov rdi, r13
    mov sil, 0x5E
    call emit_byte           ; pop rsi (curr_buf_ptr)
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte            ; mov rdi, rax (int val)

    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.format_int_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword          ; call format_int_off -> rax = len

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x01
    call emit_byte
    mov sil, 0xC6
    call emit_byte            ; add rsi, rax
    mov sil, 0x56
    call emit_byte            ; push rsi (updated curr_buf_ptr)

    ; jmp .fstr_next (EB 15)
    mov sil, 0xEB
    call emit_byte
    mov sil, 0x15
    call emit_byte

.fstr_copy_str:
    mov rdi, r13
    mov sil, 0x5F
    call emit_byte           ; pop rdi (curr_buf_ptr)
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC6
    call emit_byte            ; mov rsi, rax (str_ptr)

.c_loop:
    mov rdi, r13
    mov sil, 0x8A
    call emit_byte
    mov sil, 0x0E
    call emit_byte            ; mov cl, [rsi]
    mov sil, 0x84
    call emit_byte
    mov sil, 0xC9
    call emit_byte            ; test cl, cl
    mov sil, 0x74
    call emit_byte
    mov sil, 0x0A
    call emit_byte            ; jz +10 (.c_done)
    mov sil, 0x88
    call emit_byte
    mov sil, 0x0F
    call emit_byte            ; mov [rdi], cl
    mov sil, 0x48
    call emit_byte
    mov sil, 0xFF
    call emit_byte
    mov sil, 0xC6
    call emit_byte            ; inc rsi
    mov sil, 0x48
    call emit_byte
    mov sil, 0xFF
    call emit_byte
    mov sil, 0xC7
    call emit_byte            ; inc rdi
    mov sil, 0xEB
    call emit_byte
    mov sil, 0xF0
    call emit_byte            ; jmp -16

.c_done:
    mov rdi, r13
    mov sil, 0x57
    call emit_byte            ; push rdi (updated curr_buf_ptr)

.fstr_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .fstr_loop

.fstr_done:
    mov rdi, r13
    mov sil, 0x5F
    call emit_byte           ; pop rdi (curr_buf_ptr)
    mov sil, 0xC6
    call emit_byte
    mov sil, 0x07
    call emit_byte
    mov sil, 0x00
    call emit_byte            ; mov byte [rdi], 0

    mov sil, 0x58
    call emit_byte           ; pop rax (buf_start)
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC2
    call emit_byte
    mov esi, 3
    call emit_dword          ; rdx = 3 (STRING tag)
    jmp .done

.call_input:
    mov rbx, [r12 + ASTNode.child1]
    test rbx, rbx
    jz .input_no_prompt

    push rbx
    mov rdi, rbx
    call x86_emit_expr        ; at runtime, rax = prompt_ptr
    pop rbx

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte            ; mov rdi, rax

    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC6
    call emit_byte
    mov esi, [rbx + ASTNode.val_len]
    call emit_dword          ; mov rsi, prompt_len
    jmp .do_input_call

.input_no_prompt:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xFF
    call emit_byte            ; xor rdi, rdi
    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xF6
    call emit_byte            ; xor rsi, rsi

.do_input_call:
    mov rdi, r13
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.input_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword
    jmp .done

.call_print:
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr        ; rax = val, rdx = tag at runtime

    ; Runtime check: cmp rdx, 3 (48 83 FA 03)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFA
    call emit_byte
    mov sil, 0x03
    call emit_byte

    ; je .print_as_str (74 0A)
    mov sil, 0x74
    call emit_byte
    mov sil, 0x0A
    call emit_byte

    ; --- Print as int ---
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte            ; mov rdi, rax

    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.print_int_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    mov rdi, r13
    mov sil, 0xEB
    call emit_byte
    mov sil, 0x0B
    call emit_byte            ; jmp .done (2 bytes)

.print_as_str:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte            ; mov rdi, rax

    mov sil, 0x48
    call emit_byte
    mov sil, 0x31
    call emit_byte
    mov sil, 0xF6
    call emit_byte            ; xor rsi, rsi

    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.print_str_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword
    jmp .done

.user_call:
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10             ; arg count
.arg_eval_loop:
    test rbx, rbx
    jz .pop_args

    cmp qword [rbx + ASTNode.type], AST_IDENT
    jne .arg_eval_expr

    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_symbol_entry
    test rax, rax
    jz .arg_eval_expr

    mov r14, [rax + 24]       ; type_ptr
    mov r15, [rax + 32]       ; type_len
    mov rcx, [rax + 16]       ; base stack offset
    test r14, r14
    jz .arg_eval_expr

    mov rdi, [xstate + X86State.ast_root]
    mov rsi, r14
    mov rdx, r15
    push r10
    push rbx
    push rcx
    call find_struct_decl
    pop rcx
    pop rbx
    pop r10
    test rax, rax
    jz .arg_eval_expr

    mov r11, [rax + ASTNode.extra]  ; struct size
    xor r14, r14                    ; word offset
.arg_struct_loop:
    cmp r14, r11
    jge .arg_next

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x8B
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    add rax, r14
    neg rax
    mov esi, eax
    call emit_dword

    mov rdi, r13
    mov sil, 0x50
    call emit_byte

    inc r10
    add r14, 8
    jmp .arg_struct_loop

.arg_eval_expr:
    push r10
    push rbx
    mov rdi, rbx
    call x86_emit_expr
    pop rbx
    pop r10

    mov rdi, r13
    mov sil, 0x50
    call emit_byte

    inc r10

.arg_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .arg_eval_loop

.pop_args:
    test r10, r10
    jz .do_user_call

    dec r10
.pop_loop:
    cmp r10, 0
    je .pop_rdi
    cmp r10, 1
    je .pop_rsi
    cmp r10, 2
    je .pop_rdx
    jmp .pop_next

.pop_rdi:
    mov rdi, r13
    mov sil, 0x5F
    call emit_byte
    jmp .pop_next

.pop_rsi:
    mov rdi, r13
    mov sil, 0x5E
    call emit_byte
    jmp .pop_next

.pop_rdx:
    mov rdi, r13
    mov sil, 0x5A
    call emit_byte

.pop_next:
    test r10, r10
    jz .do_user_call
    dec r10
    jmp .pop_loop

.do_user_call:
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_fn_symbol
    cmp rax, -1
    jne .has_fn_target
    mov rax, [xstate + X86State.fn_main_off]

.has_fn_target:
    mov rdi, r13
    mov sil, 0xE8
    call emit_byte
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword
    jmp .done

.e_struct_lit:
    jmp .done

.e_index:
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


x86_emit_asm_lines:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi             ; stmt list
    mov r13, [xstate + X86State.code_buf]

.line_loop:
    test r12, r12
    jz .done

    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, r13
    call x86_encode_asm_line

    mov r12, [r12 + ASTNode.next]
    jmp .line_loop

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


%define OP_NONE    0
%define OP_REG     1
%define OP_MEM     2
%define OP_IMM     3

%define REG_GPR64  1
%define REG_GPR32  2
%define REG_GPR16  3
%define REG_GPR8   4
%define REG_SREG   5
%define REG_CR     6

%define M_NONE     0x0001
%define M_REG64    0x0002
%define M_REG32    0x0004
%define M_REG16    0x0008
%define M_REG8     0x0010
%define M_SREG     0x0020
%define M_CR       0x0040
%define M_MEM      0x0080
%define M_IMM      0x0100
%define M_DX       0x0200
%define M_AX       0x0400
%define M_EAX      0x0800
%define M_AL       0x1000

%define M_RM64     (M_REG64 | M_MEM)
%define M_RM32     (M_REG32 | M_MEM)
%define M_RM16     (M_REG16 | M_MEM)
%define M_RM8      (M_REG8  | M_MEM)

%define REG_FROM_OP1 10
%define REG_FROM_OP2 11
%define NO_MODRM     0xFF

%define F_REX_W          0x01
%define F_IMM8           0x02
%define F_IMM16          0x04
%define F_IMM32          0x08
%define F_IMM64          0x10
%define F_OPCODE_REG_ADD 0x20
%define F_SREG_DEST      0x40

struc AsmOp
    .type:     resq 1
    .reg_kind: resq 1
    .reg_code: resq 1
    .mem_base: resq 1
    .mem_idx:  resq 1
    .mem_scale:resq 1
    .mem_disp: resq 1
    .imm_val:  resq 1
endstruc

struc AsmTableEntry
    .mne_ptr:   resq 1
    .mne_len:   resq 1
    .op1_mask:  resq 1
    .op2_mask:  resq 1
    .pfx1:      resq 1
    .pfx2:      resq 1
    .opcode:    resq 1
    .modrm_reg: resq 1
    .flags:     resq 1
endstruc

section .data
err_asm_unknown_mne_1: db "SyntaxError: unknown asm instruction '", 0
err_asm_unknown_mne_2: db "'", 10, 0
err_asm_invalid_ops_1: db "SyntaxError: invalid operands for '", 0
err_asm_invalid_ops_2: db "'", 10, 0

s_reg_rax: db "rax", 0
s_reg_rcx: db "rcx", 0
s_reg_rdx: db "rdx", 0
s_reg_rbx: db "rbx", 0
s_reg_rsp: db "rsp", 0
s_reg_rbp: db "rbp", 0
s_reg_rsi: db "rsi", 0
s_reg_rdi: db "rdi", 0
s_reg_r8:  db "r8", 0
s_reg_r9:  db "r9", 0
s_reg_r10: db "r10", 0
s_reg_r11: db "r11", 0
s_reg_r12: db "r12", 0
s_reg_r13: db "r13", 0
s_reg_r14: db "r14", 0
s_reg_r15: db "r15", 0

s_reg_eax: db "eax", 0
s_reg_ecx: db "ecx", 0
s_reg_edx: db "edx", 0
s_reg_ebx: db "ebx", 0
s_reg_esp: db "esp", 0
s_reg_ebp: db "ebp", 0
s_reg_esi: db "esi", 0
s_reg_edi: db "edi", 0
s_reg_r8d: db "r8d", 0
s_reg_r9d: db "r9d", 0
s_reg_r10d:db "r10d", 0
s_reg_r11d:db "r11d", 0
s_reg_r12d:db "r12d", 0
s_reg_r13d:db "r13d", 0
s_reg_r14d:db "r14d", 0
s_reg_r15d:db "r15d", 0

s_reg_ax:  db "ax", 0
s_reg_cx:  db "cx", 0
s_reg_dx:  db "dx", 0
s_reg_bx:  db "bx", 0
s_reg_sp:  db "sp", 0
s_reg_bp:  db "bp", 0
s_reg_si:  db "si", 0
s_reg_di:  db "di", 0
s_reg_r8w: db "r8w", 0
s_reg_r9w: db "r9w", 0
s_reg_r10w:db "r10w", 0
s_reg_r11w:db "r11w", 0
s_reg_r12w:db "r12w", 0
s_reg_r13w:db "r13w", 0
s_reg_r14w:db "r14w", 0
s_reg_r15w:db "r15w", 0

s_reg_al:   db "al", 0
s_reg_cl:   db "cl", 0
s_reg_dl:   db "dl", 0
s_reg_bl:   db "bl", 0
s_reg_spl:  db "spl", 0
s_reg_bpl:  db "bpl", 0
s_reg_sil:  db "sil", 0
s_reg_dil:  db "dil", 0
s_reg_r8b:  db "r8b", 0
s_reg_r9b:  db "r9b", 0
s_reg_r10b: db "r10b", 0
s_reg_r11b: db "r11b", 0
s_reg_r12b: db "r12b", 0
s_reg_r13b: db "r13b", 0
s_reg_r14b: db "r14b", 0
s_reg_r15b: db "r15b", 0

s_reg_es:  db "es", 0
s_reg_cs:  db "cs", 0
s_reg_ss:  db "ss", 0
s_reg_ds:  db "ds", 0
s_reg_fs:  db "fs", 0
s_reg_gs:  db "gs", 0

s_reg_cr0: db "cr0", 0
s_reg_cr2: db "cr2", 0
s_reg_cr3: db "cr3", 0
s_reg_cr4: db "cr4", 0

s_mne_mov:    db "mov", 0
s_mne_add:    db "add", 0
s_mne_sub:    db "sub", 0
s_mne_xor:    db "xor", 0
s_mne_and:    db "and", 0
s_mne_or:     db "or", 0
s_mne_div:    db "div", 0
s_mne_idiv:   db "idiv", 0
s_mne_push:   db "push", 0
s_mne_pop:    db "pop", 0
s_mne_in:     db "in", 0
s_mne_out:    db "out", 0
s_mne_lgdt:   db "lgdt", 0
s_mne_lidt:   db "lidt", 0
s_mne_invlpg: db "invlpg", 0
s_mne_rdmsr:  db "rdmsr", 0
s_mne_wrmsr:  db "wrmsr", 0
s_mne_cpuid:  db "cpuid", 0
s_mne_iretq:  db "iretq", 0
s_mne_int:    db "int", 0
s_mne_cli:    db "cli", 0
s_mne_sti:    db "sti", 0
s_mne_hlt:    db "hlt", 0
s_mne_nop:    db "nop", 0
s_mne_ret:    db "ret", 0
s_mne_syscall:db "syscall", 0
s_mne_jmp:    db "jmp", 0
s_mne_stosq:  db "stosq", 0
s_mne_retfq:  db "retfq", 0
s_mne_shr:    db "shr", 0

align 8
reg_table:
    dq s_reg_rax, 3, REG_GPR64, 0
    dq s_reg_rcx, 3, REG_GPR64, 1
    dq s_reg_rdx, 3, REG_GPR64, 2
    dq s_reg_rbx, 3, REG_GPR64, 3
    dq s_reg_rsp, 3, REG_GPR64, 4
    dq s_reg_rbp, 3, REG_GPR64, 5
    dq s_reg_rsi, 3, REG_GPR64, 6
    dq s_reg_rdi, 3, REG_GPR64, 7
    dq s_reg_r8,  2, REG_GPR64, 8
    dq s_reg_r9,  2, REG_GPR64, 9
    dq s_reg_r10, 3, REG_GPR64, 10
    dq s_reg_r11, 3, REG_GPR64, 11
    dq s_reg_r12, 3, REG_GPR64, 12
    dq s_reg_r13, 3, REG_GPR64, 13
    dq s_reg_r14, 3, REG_GPR64, 14
    dq s_reg_r15, 3, REG_GPR64, 15

    dq s_reg_eax, 3, REG_GPR32, 0
    dq s_reg_ecx, 3, REG_GPR32, 1
    dq s_reg_edx, 3, REG_GPR32, 2
    dq s_reg_ebx, 3, REG_GPR32, 3
    dq s_reg_esp, 3, REG_GPR32, 4
    dq s_reg_ebp, 3, REG_GPR32, 5
    dq s_reg_esi, 3, REG_GPR32, 6
    dq s_reg_edi, 3, REG_GPR32, 7
    dq s_reg_r8d, 3, REG_GPR32, 8
    dq s_reg_r9d, 3, REG_GPR32, 9
    dq s_reg_r10d,4, REG_GPR32, 10
    dq s_reg_r11d,4, REG_GPR32, 11
    dq s_reg_r12d,4, REG_GPR32, 12
    dq s_reg_r13d,4, REG_GPR32, 13
    dq s_reg_r14d,4, REG_GPR32, 14
    dq s_reg_r15d,4, REG_GPR32, 15

    dq s_reg_ax,  2, REG_GPR16, 0
    dq s_reg_cx,  2, REG_GPR16, 1
    dq s_reg_dx,  2, REG_GPR16, 2
    dq s_reg_bx,  2, REG_GPR16, 3
    dq s_reg_sp,  2, REG_GPR16, 4
    dq s_reg_bp,  2, REG_GPR16, 5
    dq s_reg_si,  2, REG_GPR16, 6
    dq s_reg_di,  2, REG_GPR16, 7
    dq s_reg_r8w, 3, REG_GPR16, 8
    dq s_reg_r9w, 3, REG_GPR16, 9
    dq s_reg_r10w,4, REG_GPR16, 10
    dq s_reg_r11w,4, REG_GPR16, 11
    dq s_reg_r12w,4, REG_GPR16, 12
    dq s_reg_r13w,4, REG_GPR16, 13
    dq s_reg_r14w,4, REG_GPR16, 14
    dq s_reg_r15w,4, REG_GPR16, 15

    dq s_reg_al,   2, REG_GPR8, 0
    dq s_reg_cl,   2, REG_GPR8, 1
    dq s_reg_dl,   2, REG_GPR8, 2
    dq s_reg_bl,   2, REG_GPR8, 3
    dq s_reg_spl,  3, REG_GPR8, 4
    dq s_reg_bpl,  3, REG_GPR8, 5
    dq s_reg_sil,  3, REG_GPR8, 6
    dq s_reg_dil,  3, REG_GPR8, 7
    dq s_reg_r8b,  3, REG_GPR8, 8
    dq s_reg_r9b,  3, REG_GPR8, 9
    dq s_reg_r10b, 4, REG_GPR8, 10
    dq s_reg_r11b, 4, REG_GPR8, 11
    dq s_reg_r12b, 4, REG_GPR8, 12
    dq s_reg_r13b, 4, REG_GPR8, 13
    dq s_reg_r14b, 4, REG_GPR8, 14
    dq s_reg_r15b, 4, REG_GPR8, 15

    dq s_reg_es,  2, REG_SREG, 0
    dq s_reg_cs,  2, REG_SREG, 1
    dq s_reg_ss,  2, REG_SREG, 2
    dq s_reg_ds,  2, REG_SREG, 3
    dq s_reg_fs,  2, REG_SREG, 4
    dq s_reg_gs,  2, REG_SREG, 5

    dq s_reg_cr0, 3, REG_CR, 0
    dq s_reg_cr2, 3, REG_CR, 2
    dq s_reg_cr3, 3, REG_CR, 3
    dq s_reg_cr4, 3, REG_CR, 4
    dq 0, 0, 0, 0

align 8
asm_table:
    ; mov
    dq s_mne_mov, 3, M_REG64, M_IMM,    0x00, 0x00, 0xB8, NO_MODRM,     F_REX_W | F_IMM64 | F_OPCODE_REG_ADD
    dq s_mne_mov, 3, M_REG32, M_IMM,    0x00, 0x00, 0xB8, NO_MODRM,     F_IMM32 | F_OPCODE_REG_ADD
    dq s_mne_mov, 3, M_REG16, M_IMM,    0x66, 0x00, 0xB8, NO_MODRM,     F_IMM16 | F_OPCODE_REG_ADD
    dq s_mne_mov, 3, M_REG8,  M_IMM,    0x00, 0x00, 0xB0, NO_MODRM,     F_IMM8  | F_OPCODE_REG_ADD
    dq s_mne_mov, 3, M_RM64,  M_REG64,  0x00, 0x00, 0x89, REG_FROM_OP2,  F_REX_W
    dq s_mne_mov, 3, M_REG64, M_RM64,   0x00, 0x00, 0x8B, REG_FROM_OP1,  F_REX_W
    dq s_mne_mov, 3, M_RM32,  M_REG32,  0x00, 0x00, 0x89, REG_FROM_OP2,  0
    dq s_mne_mov, 3, M_REG32, M_RM32,   0x00, 0x00, 0x8B, REG_FROM_OP1,  0
    dq s_mne_mov, 3, M_RM16,  M_REG16,  0x66, 0x00, 0x89, REG_FROM_OP2,  0
    dq s_mne_mov, 3, M_REG16, M_RM16,   0x66, 0x00, 0x8B, REG_FROM_OP1,  0
    dq s_mne_mov, 3, M_RM8,   M_REG8,   0x00, 0x00, 0x88, REG_FROM_OP2,  0
    dq s_mne_mov, 3, M_REG8,  M_RM8,    0x00, 0x00, 0x8A, REG_FROM_OP1,  0
    dq s_mne_mov, 3, M_SREG,  M_RM16,   0x00, 0x00, 0x8E, REG_FROM_OP1,  F_SREG_DEST
    dq s_mne_mov, 3, M_RM16,  M_SREG,   0x00, 0x00, 0x8C, REG_FROM_OP2,  0
    dq s_mne_mov, 3, M_CR,    M_REG64,  0x0F, 0x00, 0x22, REG_FROM_OP1,  0
    dq s_mne_mov, 3, M_REG64, M_CR,     0x0F, 0x00, 0x20, REG_FROM_OP2,  0

    ; add
    dq s_mne_add, 3, M_RM64,  M_REG64,  0x00, 0x00, 0x01, REG_FROM_OP2,  F_REX_W
    dq s_mne_add, 3, M_REG64, M_RM64,   0x00, 0x00, 0x03, REG_FROM_OP1,  F_REX_W
    dq s_mne_add, 3, M_RM32,  M_REG32,  0x00, 0x00, 0x01, REG_FROM_OP2,  0
    dq s_mne_add, 3, M_REG32, M_RM32,   0x00, 0x00, 0x03, REG_FROM_OP1,  0
    dq s_mne_add, 3, M_RM64,  M_IMM,    0x00, 0x00, 0x81, 0,             F_REX_W | F_IMM32
    dq s_mne_add, 3, M_RM32,  M_IMM,    0x00, 0x00, 0x81, 0,             F_IMM32

    ; sub
    dq s_mne_sub, 3, M_RM64,  M_REG64,  0x00, 0x00, 0x29, REG_FROM_OP2,  F_REX_W
    dq s_mne_sub, 3, M_REG64, M_RM64,   0x00, 0x00, 0x2B, REG_FROM_OP1,  F_REX_W
    dq s_mne_sub, 3, M_RM32,  M_REG32,  0x00, 0x00, 0x29, REG_FROM_OP2,  0
    dq s_mne_sub, 3, M_REG32, M_RM32,   0x00, 0x00, 0x2B, REG_FROM_OP1,  0
    dq s_mne_sub, 3, M_RM64,  M_IMM,    0x00, 0x00, 0x81, 5,             F_REX_W | F_IMM32
    dq s_mne_sub, 3, M_RM32,  M_IMM,    0x00, 0x00, 0x81, 5,             F_IMM32

    ; xor
    dq s_mne_xor, 3, M_RM64,  M_REG64,  0x00, 0x00, 0x31, REG_FROM_OP2,  F_REX_W
    dq s_mne_xor, 3, M_REG64, M_RM64,   0x00, 0x00, 0x33, REG_FROM_OP1,  F_REX_W
    dq s_mne_xor, 3, M_RM32,  M_REG32,  0x00, 0x00, 0x31, REG_FROM_OP2,  0
    dq s_mne_xor, 3, M_REG32, M_RM32,   0x00, 0x00, 0x33, REG_FROM_OP1,  0
    dq s_mne_xor, 3, M_RM64,  M_IMM,    0x00, 0x00, 0x81, 6,             F_REX_W | F_IMM32
    dq s_mne_xor, 3, M_RM32,  M_IMM,    0x00, 0x00, 0x81, 6,             F_IMM32

    ; and
    dq s_mne_and, 3, M_RM64,  M_REG64,  0x00, 0x00, 0x21, REG_FROM_OP2,  F_REX_W
    dq s_mne_and, 3, M_REG64, M_RM64,   0x00, 0x00, 0x23, REG_FROM_OP1,  F_REX_W
    dq s_mne_and, 3, M_RM32,  M_REG32,  0x00, 0x00, 0x21, REG_FROM_OP2,  0
    dq s_mne_and, 3, M_REG32, M_RM32,   0x00, 0x00, 0x23, REG_FROM_OP1,  0
    dq s_mne_and, 3, M_RM64,  M_IMM,    0x00, 0x00, 0x81, 4,             F_REX_W | F_IMM32
    dq s_mne_and, 3, M_RM32,  M_IMM,    0x00, 0x00, 0x81, 4,             F_IMM32

    ; or
    dq s_mne_or, 2,  M_RM64,  M_REG64,  0x00, 0x00, 0x09, REG_FROM_OP2,  F_REX_W
    dq s_mne_or, 2,  M_REG64, M_RM64,   0x00, 0x00, 0x0B, REG_FROM_OP1,  F_REX_W
    dq s_mne_or, 2,  M_RM32,  M_REG32,  0x00, 0x00, 0x09, REG_FROM_OP2,  0
    dq s_mne_or, 2,  M_REG32, M_RM32,   0x00, 0x00, 0x0B, REG_FROM_OP1,  0
    dq s_mne_or, 2,  M_RM64,  M_IMM,    0x00, 0x00, 0x81, 1,             F_REX_W | F_IMM32
    dq s_mne_or, 2,  M_RM32,  M_IMM,    0x00, 0x00, 0x81, 1,             F_IMM32

    ; div / idiv
    dq s_mne_div, 3,  M_RM32, M_NONE,   0x00, 0x00, 0xF7, 6,             0
    dq s_mne_div, 3,  M_RM64, M_NONE,   0x00, 0x00, 0xF7, 6,             F_REX_W
    dq s_mne_idiv, 4, M_RM32, M_NONE,   0x00, 0x00, 0xF7, 7,             0
    dq s_mne_idiv, 4, M_RM64, M_NONE,   0x00, 0x00, 0xF7, 7,             F_REX_W

    ; push / pop
    dq s_mne_push, 4, M_REG64, M_NONE,  0x00, 0x00, 0x50, NO_MODRM,     F_OPCODE_REG_ADD
    dq s_mne_push, 4, M_IMM,   M_NONE,  0x00, 0x00, 0x6A, NO_MODRM,     F_IMM8
    dq s_mne_pop, 3,  M_REG64, M_NONE,  0x00, 0x00, 0x58, NO_MODRM,     F_OPCODE_REG_ADD

    ; in / out
    dq s_mne_out, 3,  M_DX, M_AL,       0x00, 0x00, 0xEE, NO_MODRM,     0
    dq s_mne_out, 3,  M_DX, M_EAX,      0x00, 0x00, 0xEF, NO_MODRM,     0
    dq s_mne_out, 3,  M_DX, M_AX,       0x66, 0x00, 0xEF, NO_MODRM,     0
    dq s_mne_in, 2,   M_AL, M_DX,       0x00, 0x00, 0xEC, NO_MODRM,     0
    dq s_mne_in, 2,   M_EAX, M_DX,      0x00, 0x00, 0xED, NO_MODRM,     0
    dq s_mne_in, 2,   M_AX, M_DX,       0x66, 0x00, 0xED, NO_MODRM,     0

    ; System instructions
    dq s_mne_lgdt, 4, M_MEM, M_NONE,    0x0F, 0x00, 0x01, 2,             0
    dq s_mne_lidt, 4, M_MEM, M_NONE,    0x0F, 0x00, 0x01, 3,             0
    dq s_mne_invlpg, 6, M_MEM, M_NONE,  0x0F, 0x00, 0x01, 7,             0
    dq s_mne_rdmsr, 5, M_NONE, M_NONE,  0x0F, 0x32, 0x00, NO_MODRM,     0
    dq s_mne_wrmsr, 5, M_NONE, M_NONE,  0x0F, 0x30, 0x00, NO_MODRM,     0
    dq s_mne_cpuid, 5, M_NONE, M_NONE,  0x0F, 0xA2, 0x00, NO_MODRM,     0
    dq s_mne_iretq, 5, M_NONE, M_NONE,  0x48, 0x00, 0xCF, NO_MODRM,     0
    dq s_mne_int, 3,  M_IMM, M_NONE,    0x00, 0x00, 0xCD, NO_MODRM,     F_IMM8
    dq s_mne_cli, 3,  M_NONE, M_NONE,  0x00, 0x00, 0xFA, NO_MODRM,     0
    dq s_mne_sti, 3,  M_NONE, M_NONE,  0x00, 0x00, 0xFB, NO_MODRM,     0
    dq s_mne_hlt, 3,  M_NONE, M_NONE,  0x00, 0x00, 0xF4, NO_MODRM,     0
    dq s_mne_nop, 3,  M_NONE, M_NONE,  0x00, 0x00, 0x90, NO_MODRM,     0
    dq s_mne_ret, 3,  M_NONE, M_NONE,  0x00, 0x00, 0xC3, NO_MODRM,     0
    dq s_mne_syscall, 7, M_NONE, M_NONE, 0x0F, 0x05, 0x00, NO_MODRM,    0
    dq s_mne_jmp, 3,  M_REG64, M_NONE, 0x00, 0x00, 0xFF, 4,            F_REX_W
    dq s_mne_stosq, 5, M_NONE, M_NONE, 0xF3, 0x00, 0xAB, NO_MODRM,     F_REX_W
    dq s_mne_retfq, 5, M_NONE, M_NONE, 0x00, 0x00, 0xCB, NO_MODRM,     F_REX_W
    dq s_mne_shr, 3,   M_REG64, M_IMM,  0x00, 0x00, 0xC1, 5,            F_REX_W | F_IMM8
    dq s_mne_shr, 3,   M_REG32, M_IMM,  0x00, 0x00, 0xC1, 5,            F_IMM8
    dq 0, 0, 0, 0, 0, 0

section .text

x86_encode_asm_line:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbp, rsp
    sub rsp, 256

    mov r12, rdi             ; str
    mov r14, rsi             ; len
    mov [rbp - 8], rdx       ; CodeBuf

.trim_line:
    test r14, r14
    jz .done_line_td
    mov al, [r12]
    cmp al, ' '
    je .inc_trim_l
    cmp al, 9
    je .inc_trim_l
    jmp .parsed_trim_l
.inc_trim_l:
    inc r12
    dec r14
    jmp .trim_line

.parsed_trim_l:
    test r14, r14
    jz .done_line_td

    mov [rbp - 16], r12
    xor rcx, rcx
.find_mne_end:
    cmp rcx, r14
    jge .got_mne_len
    mov al, [r12 + rcx]
    cmp al, ' '
    je .got_mne_len
    cmp al, 9
    je .got_mne_len
    cmp al, 10
    je .got_mne_len
    cmp al, 13
    je .got_mne_len
    inc rcx
    jmp .find_mne_end

.got_mne_len:
    mov [rbp - 24], rcx

    add r12, rcx
    sub r14, rcx

    lea rdi, [rbp - 160]
    xor rax, rax
    mov rcx, 16
    rep stosq

    mov qword [rbp - 32], 0

.trim_before_op1:
    test r14, r14
    jz .do_table_match
    mov al, [r12]
    cmp al, ' '
    je .inc_trim_op1
    cmp al, 9
    je .inc_trim_op1
    jmp .parse_op1
.inc_trim_op1:
    inc r12
    dec r14
    jmp .trim_before_op1

.parse_op1:
    test r14, r14
    jz .do_table_match

    mov rdi, r12
    mov rcx, r14
    call find_comma_or_end
    mov r15, rax

    mov rdi, r12
    mov rsi, r15
    lea rdx, [rbp - 96]
    call parse_asm_operand

    mov qword [rbp - 32], 1

    add r12, r15
    sub r14, r15

    test r14, r14
    jz .do_table_match
    cmp byte [r12], ','
    jne .do_table_match

    inc r12
    dec r14

.trim_before_op2:
    test r14, r14
    jz .do_table_match
    mov al, [r12]
    cmp al, ' '
    je .inc_trim_op2
    cmp al, 9
    je .inc_trim_op2
    jmp .parse_op2
.inc_trim_op2:
    inc r12
    dec r14
    jmp .trim_before_op2

.parse_op2:
    test r14, r14
    jz .do_table_match

    mov rdi, r12
    mov rcx, r14
    call find_comma_or_end
    mov r15, rax

    mov rdi, r12
    mov rsi, r15
    lea rdx, [rbp - 160]
    call parse_asm_operand

    mov qword [rbp - 32], 2

.do_table_match:
    lea r15, [asm_table]

.tbl_loop:
    mov rax, [r15 + AsmTableEntry.mne_ptr]
    test rax, rax
    jz .mne_search_check

    mov rcx, [r15 + AsmTableEntry.mne_len]
    cmp rcx, [rbp - 24]
    jne .tbl_next

    mov rdi, [rbp - 16]
    mov rsi, rax
    mov rdx, rcx
    call str_ncmp
    test rax, rax
    jnz .tbl_next

    lea rdi, [rbp - 96]
    mov rsi, [r15 + AsmTableEntry.op1_mask]
    call operand_matches_mask
    test rax, rax
    jz .tbl_next

    lea rdi, [rbp - 160]
    mov rsi, [r15 + AsmTableEntry.op2_mask]
    call operand_matches_mask
    test rax, rax
    jz .tbl_next

    mov rax, [r15 + AsmTableEntry.flags]
    test rax, F_SREG_DEST
    jz .match_found
    cmp qword [rbp - 96 + AsmOp.reg_code], 1
    je .tbl_next

.match_found:
    mov rdi, [rbp - 8]
    mov rsi, r15
    lea rdx, [rbp - 96]
    lea rcx, [rbp - 160]
    call encode_asm_entry
    jmp .done_line_td

.tbl_next:
    add r15, AsmTableEntry_size
    jmp .tbl_loop

.mne_search_check:
    lea r15, [asm_table]
.chk_mne_exist:
    mov rax, [r15 + AsmTableEntry.mne_ptr]
    test rax, rax
    jz .err_unknown_mne

    mov rcx, [r15 + AsmTableEntry.mne_len]
    cmp rcx, [rbp - 24]
    jne .chk_mne_next

    mov rdi, [rbp - 16]
    mov rsi, rax
    mov rdx, rcx
    call str_ncmp
    test rax, rax
    jz .err_invalid_ops

.chk_mne_next:
    add r15, AsmTableEntry_size
    jmp .chk_mne_exist

.err_unknown_mne:
    mov rsi, err_asm_unknown_mne_1
    call print_err
    mov rsi, [rbp - 16]
    mov rdx, [rbp - 24]
    call print_err_bytes
    mov rsi, err_asm_unknown_mne_2
    call print_err
    mov rdi, 1
    call sys_exit

.err_invalid_ops:
    mov rsi, err_asm_invalid_ops_1
    call print_err
    mov rsi, [rbp - 16]
    mov rdx, [rbp - 24]
    call print_err_bytes
    mov rsi, err_asm_invalid_ops_2
    call print_err
    mov rdi, 1
    call sys_exit

.done_line_td:
    mov rsp, rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


find_comma_or_end:
    push rbx
    xor rax, rax
    xor rbx, rbx
.fce_loop:
    cmp rax, rcx
    jge .fce_done
    mov dl, [rdi + rax]
    cmp dl, '['
    je .fce_open
    cmp dl, ']'
    je .fce_close
    cmp dl, ','
    je .fce_chk_comma
.fce_next:
    inc rax
    jmp .fce_loop
.fce_open:
    mov rbx, 1
    jmp .fce_next
.fce_close:
    xor rbx, rbx
    jmp .fce_next
.fce_chk_comma:
    test rbx, rbx
    jnz .fce_next
.fce_done:
    pop rbx
    ret


parse_asm_operand:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

.po_trim:
    test r13, r13
    jz .po_none
    mov al, [r12]
    cmp al, ' '
    je .po_inc_trim
    cmp al, 9
    je .po_inc_trim
    jmp .po_trim_trail
.po_inc_trim:
    inc r12
    dec r13
    jmp .po_trim

.po_trim_trail:
    test r13, r13
    jz .po_none
    mov al, [r12 + r13 - 1]
    cmp al, ' '
    je .po_dec_trail
    cmp al, 9
    je .po_dec_trail
    cmp al, 10
    je .po_dec_trail
    cmp al, 13
    je .po_dec_trail
    jmp .po_start
.po_dec_trail:
    dec r13
    jmp .po_trim_trail

.po_none:
    mov qword [r14 + AsmOp.type], OP_NONE
    jmp .po_done

.po_start:
    cmp byte [r12], '['
    je .po_mem

    mov rdi, r12
    mov rsi, r13
    call lookup_register
    cmp rax, -1
    je .po_imm

    mov qword [r14 + AsmOp.type], OP_REG
    mov [r14 + AsmOp.reg_kind], rax
    mov [r14 + AsmOp.reg_code], rdx
    jmp .po_done

.po_imm:
    mov qword [r14 + AsmOp.type], OP_IMM
    mov rdi, r12
    mov rcx, r13
    xor rsi, rsi
    call parse_int_literal
    mov [r14 + AsmOp.imm_val], rax
    jmp .po_done

.po_mem:
    mov qword [r14 + AsmOp.type], OP_MEM
    mov qword [r14 + AsmOp.mem_base], -1
    mov qword [r14 + AsmOp.mem_idx], -1
    mov qword [r14 + AsmOp.mem_scale], 0
    mov qword [r14 + AsmOp.mem_disp], 0

    inc r12
    dec r13
    cmp byte [r12 + r13 - 1], ']'
    jne .po_mem_err
    dec r13

    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call parse_mem_expr
    jmp .po_done

.po_mem_err:
    mov qword [r14 + AsmOp.type], OP_NONE

.po_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


lookup_register:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    lea rbx, [reg_table]
.reg_loop:
    mov rax, [rbx]
    test rax, rax
    jz .reg_not_found

    mov rdx, [rbx + 8]
    cmp rdx, r13
    jne .reg_next

    mov rdi, r12
    mov rsi, rax
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jz .reg_found

.reg_next:
    add rbx, 32
    jmp .reg_loop

.reg_found:
    mov rax, [rbx + 16]
    mov rdx, [rbx + 24]
    jmp .reg_done

.reg_not_found:
    mov rax, -1
    mov rdx, -1

.reg_done:
    pop r13
    pop r12
    pop rbx
    ret


parse_mem_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; str
    mov r13, rsi             ; len
    mov r14, rdx             ; op_struct

.pme_loop:
    test r13, r13
    jz .pme_done

.pme_trim_space:
    test r13, r13
    jz .pme_done
    mov al, [r12]
    cmp al, ' '
    je .pme_inc_space
    cmp al, 9
    je .pme_inc_space
    jmp .pme_sign_check
.pme_inc_space:
    inc r12
    dec r13
    jmp .pme_trim_space

.pme_sign_check:
    xor r15, r15
    mov rbx, 1
    cmp byte [r12], '-'
    jne .pme_chk_plus
    mov rbx, -1
    inc r12
    dec r13
    jmp .pme_scan_term
.pme_chk_plus:
    cmp byte [r12], '+'
    jne .pme_scan_term
    inc r12
    dec r13

.pme_scan_term:
    cmp r15, r13
    jge .pme_got_term
    mov al, [r12 + r15]
    cmp al, '+'
    je .pme_got_term
    cmp al, '-'
    je .pme_got_term
    inc r15
    jmp .pme_scan_term

.pme_got_term:
    test r15, r15
    jz .pme_next_term

    mov rdi, r12
    mov rsi, r15

.trim_t_lead:
    test rsi, rsi
    jz .pme_next_term
    mov al, [rdi]
    cmp al, ' '
    je .inc_t_lead
    cmp al, 9
    je .inc_t_lead
    jmp .trim_t_trail
.inc_t_lead:
    inc rdi
    dec rsi
    jmp .trim_t_lead

.trim_t_trail:
    test rsi, rsi
    jz .pme_next_term
    mov al, [rdi + rsi - 1]
    cmp al, ' '
    je .dec_t_trail
    cmp al, 9
    je .dec_t_trail
    jmp .t_trimmed
.dec_t_trail:
    dec rsi
    jmp .trim_t_trail

.t_trimmed:
    push rdi
    push rsi
    call check_term_has_star
    pop rsi
    pop rdi
    test rax, rax
    jnz .pme_star_term

    push rdi
    push rsi
    call lookup_register
    pop rsi
    pop rdi
    cmp rax, -1
    je .pme_disp_term

    cmp qword [r14 + AsmOp.mem_base], -1
    jne .pme_as_idx
    mov [r14 + AsmOp.mem_base], rdx
    jmp .pme_next_term

.pme_as_idx:
    mov [r14 + AsmOp.mem_idx], rdx
    mov qword [r14 + AsmOp.mem_scale], 1
    jmp .pme_next_term

.pme_star_term:
    mov r8, rax
    push rdi
    push rsi
    push r8
    mov rsi, r8
    call lookup_register
    pop r8
    pop rsi
    pop rdi
    cmp rax, -1
    je .pme_next_term
    mov [r14 + AsmOp.mem_idx], rdx

    lea rbx, [rdi + r8 + 1]
    mov rcx, rsi
    sub rcx, r8
    dec rcx

.trim_s_lead:
    test rcx, rcx
    jz .pme_next_term
    mov al, [rbx]
    cmp al, ' '
    je .inc_s_lead
    cmp al, 9
    je .inc_s_lead
    jmp .s_trimmed
.inc_s_lead:
    inc rbx
    dec rcx
    jmp .trim_s_lead

.s_trimmed:
    mov rdi, rbx
    xor rsi, rsi
    call parse_int_literal
    cmp rax, 1
    je .valid_scale
    cmp rax, 2
    je .valid_scale
    cmp rax, 4
    je .valid_scale
    cmp rax, 8
    je .valid_scale
    jmp .invalid_ops_exit
.valid_scale:
    mov [r14 + AsmOp.mem_scale], rax
    jmp .pme_next_term

.pme_disp_term:
    mov rcx, rsi
    xor rsi, rsi
    call parse_int_literal
    cmp rbx, -1
    jne .add_disp
    neg rax
.add_disp:
    add [r14 + AsmOp.mem_disp], rax

.pme_next_term:
    add r12, r15
    sub r13, r15
    jmp .pme_loop

.pme_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.invalid_ops_exit:
    mov rsi, err_asm_invalid_ops_1
    call print_err
    mov rdi, 1
    call sys_exit


check_term_has_star:
    xor rax, rax
.cts_loop:
    cmp rax, rsi
    jge .cts_none
    cmp byte [rdi + rax], '*'
    je .cts_found
    inc rax
    jmp .cts_loop
.cts_found:
    ret
.cts_none:
    xor rax, rax
    ret


operand_matches_mask:
    push rbx
    mov rax, [rdi + AsmOp.type]

    cmp rsi, M_NONE
    jne .m_check_type
    cmp rax, OP_NONE
    je .m_yes
    jmp .m_no

.m_check_type:
    cmp rax, OP_NONE
    je .m_no

    cmp rax, OP_IMM
    jne .m_chk_reg
    test rsi, M_IMM
    jnz .m_yes
    jmp .m_no

.m_chk_reg:
    cmp rax, OP_REG
    jne .m_chk_mem

    mov rbx, [rdi + AsmOp.reg_kind]
    cmp rbx, REG_GPR64
    jne .m_c32
    test rsi, M_REG64
    jnz .m_yes
    jmp .m_no

.m_c32:
    cmp rbx, REG_GPR32
    jne .m_c16
    test rsi, M_REG32
    jnz .m_yes
    test rsi, M_EAX
    jz .m_no
    cmp qword [rdi + AsmOp.reg_code], 0
    je .m_yes
    jmp .m_no

.m_c16:
    cmp rbx, REG_GPR16
    jne .m_c8
    test rsi, M_REG16
    jnz .m_yes
    test rsi, M_AX
    jz .m_chk_dx
    cmp qword [rdi + AsmOp.reg_code], 0
    je .m_yes
.m_chk_dx:
    test rsi, M_DX
    jz .m_no
    cmp qword [rdi + AsmOp.reg_code], 2
    je .m_yes
    jmp .m_no

.m_c8:
    cmp rbx, REG_GPR8
    jne .m_csreg
    test rsi, M_REG8
    jnz .m_yes
    test rsi, M_AL
    jz .m_no
    cmp qword [rdi + AsmOp.reg_code], 0
    je .m_yes
    jmp .m_no

.m_csreg:
    cmp rbx, REG_SREG
    jne .m_ccr
    test rsi, M_SREG
    jnz .m_yes
    jmp .m_no

.m_ccr:
    cmp rbx, REG_CR
    jne .m_no
    test rsi, M_CR
    jnz .m_yes
    jmp .m_no

.m_chk_mem:
    cmp rax, OP_MEM
    jne .m_no
    test rsi, M_MEM
    jnz .m_yes
    jmp .m_no

.m_yes:
    mov rax, 1
    pop rbx
    ret
.m_no:
    xor rax, rax
    pop rbx
    ret


encode_asm_entry:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; CodeBuf
    mov r13, rsi             ; TableEntry
    mov r14, rdx             ; Op1
    mov r15, rcx             ; Op2

    xor rbx, rbx
    mov rax, [r13 + AsmTableEntry.flags]
    test rax, F_REX_W
    jz .chk_rex_regs
    or rbx, 8

.chk_rex_regs:
    mov rax, [r13 + AsmTableEntry.modrm_reg]
    cmp rax, REG_FROM_OP1
    je .reg_r_op1
    cmp rax, REG_FROM_OP2
    je .reg_r_op2
    jmp .chk_rm_rex

.reg_r_op1:
    mov rax, [r14 + AsmOp.reg_code]
    cmp rax, 8
    jl .chk_rm_rex
    or rbx, 4
    jmp .chk_rm_rex

.reg_r_op2:
    mov rax, [r15 + AsmOp.reg_code]
    cmp rax, 8
    jl .chk_rm_rex
    or rbx, 4

.chk_rm_rex:
    lea rdx, [r14]
    mov rax, [r13 + AsmTableEntry.modrm_reg]
    cmp rax, REG_FROM_OP1
    jne .rm_r_op1
    lea rdx, [r15]
.rm_r_op1:
    cmp qword [rdx + AsmOp.type], OP_REG
    jne .rm_m_rex

    mov rax, [rdx + AsmOp.reg_code]
    cmp rax, 8
    jl .emit_pfx
    or rbx, 1
    jmp .emit_pfx

.rm_m_rex:
    cmp qword [rdx + AsmOp.type], OP_MEM
    jne .emit_pfx

    mov rax, [rdx + AsmOp.mem_base]
    cmp rax, 8
    jl .chk_m_idx_rex
    or rbx, 1

.chk_m_idx_rex:
    mov rax, [rdx + AsmOp.mem_idx]
    cmp rax, 8
    jl .emit_pfx
    or rbx, 2

.emit_pfx:
.do_pfx1_e:
    mov rax, [r13 + AsmTableEntry.pfx1]
    test rax, rax
    jz .do_pfx2_e
    mov rdi, r12
    mov sil, al
    call emit_byte

.do_pfx2_e:
    mov rax, [r13 + AsmTableEntry.pfx2]
    test rax, rax
    jz .do_rex_e
    mov rdi, r12
    mov sil, al
    call emit_byte

.do_rex_e:
    test rbx, rbx
    jz .do_opcode_e
    mov rdi, r12
    mov sil, bl
    or sil, 0x40
    call emit_byte

.do_opcode_e:
    mov rax, [r13 + AsmTableEntry.opcode]
    mov sil, al
    mov rcx, [r13 + AsmTableEntry.flags]
    test rcx, F_OPCODE_REG_ADD
    jz .emit_op_b
    mov rax, [r14 + AsmOp.reg_code]
    and rax, 7
    add sil, al

.emit_op_b:
    mov rdi, r12
    call emit_byte

    mov rax, [r13 + AsmTableEntry.modrm_reg]
    cmp rax, NO_MODRM
    je .do_immediates_e

.do_modrm_e:
    mov rax, [r13 + AsmTableEntry.modrm_reg]
    cmp rax, REG_FROM_OP1
    je .reg_v1
    cmp rax, REG_FROM_OP2
    je .reg_v2
    mov r8, rax
    jmp .got_reg_val

.reg_v1:
    mov r8, [r14 + AsmOp.reg_code]
    and r8, 7
    jmp .got_reg_val

.reg_v2:
    mov r8, [r15 + AsmOp.reg_code]
    and r8, 7

.got_reg_val:
    lea rsi, [r14]
    mov rax, [r13 + AsmTableEntry.modrm_reg]
    cmp rax, REG_FROM_OP1
    jne .got_rm_op
    lea rsi, [r15]

.got_rm_op:
    mov rdi, r12
    mov rdx, r8
    call encode_modrm_sib_bytes

.do_immediates_e:
    mov rax, [r13 + AsmTableEntry.flags]
    test rax, F_IMM8
    jnz .imm_8
    test rax, F_IMM16
    jnz .imm_16
    test rax, F_IMM32
    jnz .imm_32
    test rax, F_IMM64
    jnz .imm_64
    jmp .enc_entry_done

.imm_8:
    mov rdi, r12
    mov sil, [r15 + AsmOp.imm_val]
    cmp qword [r15 + AsmOp.type], OP_IMM
    je .e_im8
    mov sil, [r14 + AsmOp.imm_val]
.e_im8:
    call emit_byte
    jmp .enc_entry_done

.imm_16:
    mov rdi, r12
    mov rax, [r15 + AsmOp.imm_val]
    cmp qword [r15 + AsmOp.type], OP_IMM
    je .e_im16
    mov rax, [r14 + AsmOp.imm_val]
.e_im16:
    push rax
    mov sil, al
    call emit_byte
    pop rax
    shr rax, 8
    mov sil, al
    call emit_byte
    jmp .enc_entry_done

.imm_32:
    mov rdi, r12
    mov eax, [r15 + AsmOp.imm_val]
    cmp qword [r15 + AsmOp.type], OP_IMM
    je .e_im32
    mov eax, [r14 + AsmOp.imm_val]
.e_im32:
    mov esi, eax
    call emit_dword
    jmp .enc_entry_done

.imm_64:
    mov rdi, r12
    mov rax, [r15 + AsmOp.imm_val]
    cmp qword [r15 + AsmOp.type], OP_IMM
    je .e_im64
    mov rax, [r14 + AsmOp.imm_val]
.e_im64:
    mov rsi, rax
    call emit_qword
    jmp .enc_entry_done

.enc_entry_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


encode_modrm_sib_bytes:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; CodeBuf
    mov r13, rsi             ; rm_op
    mov r14, rdx             ; reg_val (0..7)

    cmp qword [r13 + AsmOp.type], OP_REG
    je .enc_reg_direct

    mov rax, [r13 + AsmOp.mem_base]
    cmp rax, -1
    jne .enc_mem_base

    ; [imm32] (Absolute Address)
    mov rax, [r13 + AsmOp.mem_disp]
    mov rbx, 0xFFFFFFFF
    cmp rax, rbx
    ja .imm32_range_err

    mov sil, r14b
    and sil, 7
    shl sil, 3
    or sil, 4
    mov rdi, r12
    call emit_byte

    mov rdi, r12
    mov sil, 0x25
    call emit_byte

    mov rdi, r12
    mov esi, [r13 + AsmOp.mem_disp]
    call emit_dword
    jmp .enc_m_done

.imm32_range_err:
    mov rsi, err_asm_invalid_ops_1
    call print_err
    mov rsi, [rbp - 16]
    mov rdx, [rbp - 24]
    call print_err_bytes
    mov rsi, err_asm_invalid_ops_2
    call print_err
    mov rdi, 1
    call sys_exit

.enc_mem_base:
    mov rbx, [r13 + AsmOp.mem_base]
    and rbx, 7

    mov r15, [r13 + AsmOp.mem_idx]
    cmp r15, -1
    jne .need_sib
    cmp rbx, 4
    je .need_sib
    xor r8, r8
    jmp .chk_mod

.need_sib:
    mov r8, 1

.chk_mod:
    mov r10, [r13 + AsmOp.mem_disp]
    test r10, r10
    jnz .chk_disp8

    cmp rbx, 5
    je .mod_01
    xor r9, r9
    jmp .emit_modrm

.chk_disp8:
    cmp r10, -128
    jl .mod_10
    cmp r10, 127
    jg .mod_10

.mod_01:
    mov r9, 1
    jmp .emit_modrm

.mod_10:
    mov r9, 2

.emit_modrm:
    mov sil, r9b
    shl sil, 6
    mov al, r14b
    and al, 7
    shl al, 3
    or sil, al

    test r8, r8
    jnz .rm_is_4
    mov al, bl
    and al, 7
    or sil, al
    jmp .write_modrm

.rm_is_4:
    or sil, 4

.write_modrm:
    mov rdi, r12
    call emit_byte

    test r8, r8
    jz .emit_disp

    mov rax, [r13 + AsmOp.mem_scale]
    cmp rax, 8
    je .sc_3
    cmp rax, 4
    je .sc_2
    cmp rax, 2
    je .sc_1
    xor sil, sil
    jmp .got_sc

.sc_3:
    mov sil, 3 << 6
    jmp .got_sc
.sc_2:
    mov sil, 2 << 6
    jmp .got_sc
.sc_1:
    mov sil, 1 << 6

.got_sc:
    mov rax, r15
    cmp rax, -1
    jne .got_idx_code
    mov rax, 4

.got_idx_code:
    and rax, 7
    shl rax, 3
    or sil, al
    mov al, bl
    and al, 7
    or sil, al

    mov rdi, r12
    call emit_byte

.emit_disp:
    cmp r9, 1
    je .emit_d8
    cmp r9, 2
    je .emit_d32
    cmp rbx, 5
    je .emit_d32
    jmp .enc_m_done

.emit_d8:
    mov rdi, r12
    mov sil, r10b
    call emit_byte
    jmp .enc_m_done

.emit_d32:
    mov rdi, r12
    mov esi, r10d
    call emit_dword
    jmp .enc_m_done

.enc_reg_direct:
    mov sil, 3 << 6
    mov al, r14b
    and al, 7
    shl al, 3
    or sil, al
    mov rax, [r13 + AsmOp.reg_code]
    and rax, 7
    or sil, al

    mov rdi, r12
    call emit_byte

.enc_m_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
