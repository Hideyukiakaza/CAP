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

; src/codegen/arm_emit.asm - ARM64 Machine Code Emitter for CAP v0.1
default rel

%include "src/ast.inc"
%include "src/codegen/target.inc"

section .data
err_unsupported_arm_asm: db "SyntaxError: asm block contains unsupported ARM instruction. Supported instructions: mov, add, sub, svc, ret", 10, 0
s_main_arm:              db "main", 0
s_print_arm:             db "print", 0
s_len_arm:               db "len", 0
s_input_arm:             db "input", 0
s_fstring_arm:           db "fstring", 0
s_free_arm:              db "free", 0
s_svc:                   db "svc", 0
s_ret_arm:               db "ret", 0
s_mov_arm:               db "mov", 0

section .text
global arm_emit_program
extern emit_byte, emit_dword, emit_qword, emit_bytes, patch_dword
extern emit_arm_print_int, emit_arm_print_str, emit_arm_div_zero_trap, emit_arm_overflow_trap, emit_arm_alloc, emit_arm_free, emit_arm_input, emit_arm_type_mismatch_trap, emit_arm_format_int, emit_arm_oob_trap, emit_arm_print_list, emit_arm_dict_missing_trap, emit_arm_print_dict
extern sym_init, add_symbol, add_symbol_type, find_symbol_offset
extern find_struct_decl, find_struct_field, resolve_field_access
extern fn_sym_init, add_fn_symbol, find_fn_symbol, find_symbol_entry
extern print_err, sys_exit, str_ncmp, parse_dec_int, parse_int_literal

struc ArmState
    .code_buf:          resq 1
    .print_int_off:     resq 1
    .print_str_off:     resq 1
    .print_list_off:    resq 1
    .print_dict_off:    resq 1
    .div_zero_off:      resq 1
    .overflow_off:      resq 1
    .alloc_off:         resq 1
    .free_off:          resq 1
    .input_off:         resq 1
    .type_mismatch_off:  resq 1
    .format_int_off:    resq 1
    .oob_off:           resq 1
    .dict_missing_off:  resq 1
    .fn_main_off:       resq 1
    .stack_offset:      resq 1
    .ast_root:          resq 1
endstruc

section .bss
armstate: resb ArmState_size
arm_defer_nodes: resq 256
arm_defer_count: resq 1
arm_is_main_fn: resq 1
arm_break_head: resq 1

section .text

%macro EMIT_ARM 1
    mov rdi, r13
    mov r8d, %1
    mov esi, r8d
    call emit_dword
%endmacro

arm_emit_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; code_buf

    mov [armstate + ArmState.code_buf], r13
    mov [armstate + ArmState.ast_root], r12
    call fn_sym_init

    ; 1. Emit _start at offset 0
    ; bl main (0x94000000 - placeholder rel26 = 0)
    EMIT_ARM 0x94000000

    ; mov x8, #94 (sys_exit_group = 94) -> 0xD2800BC8
    EMIT_ARM 0xD2800BC8

    ; svc #0 -> 0xD4000001
    EMIT_ARM 0xD4000001

    ; 2. Emit Runtime Stubs
    mov rax, [r13 + 16]      ; len
    mov [armstate + ArmState.print_int_off], rax
    mov rdi, r13
    call emit_arm_print_int

    mov rax, [r13 + 16]
    mov [armstate + ArmState.print_str_off], rax
    mov rdi, r13
    call emit_arm_print_str

    mov rax, [r13 + 16]
    mov [armstate + ArmState.print_list_off], rax
    mov rdi, r13
    call emit_arm_print_list

    mov rax, [r13 + 16]
    mov [armstate + ArmState.print_dict_off], rax
    mov rdi, r13
    call emit_arm_print_dict

    mov rax, [r13 + 16]
    mov [armstate + ArmState.dict_missing_off], rax
    mov rdi, r13
    call emit_arm_dict_missing_trap

    mov rax, [r13 + 16]
    mov [armstate + ArmState.div_zero_off], rax
    mov rdi, r13
    call emit_arm_div_zero_trap

    mov rax, [r13 + 16]
    mov [armstate + ArmState.overflow_off], rax
    mov rdi, r13
    call emit_arm_overflow_trap

    mov rax, [r13 + 16]
    mov [armstate + ArmState.alloc_off], rax
    mov rdi, r13
    call emit_arm_alloc

    mov rax, [r13 + 16]
    mov [armstate + ArmState.free_off], rax
    mov rdi, r13
    call emit_arm_free

    mov rax, [r13 + 16]
    mov [armstate + ArmState.input_off], rax
    mov rdi, r13
    call emit_arm_input

    mov rax, [r13 + 16]
    mov [armstate + ArmState.type_mismatch_off], rax
    mov rdi, r13
    call emit_arm_type_mismatch_trap

    mov rax, [r13 + 16]
    mov [armstate + ArmState.oob_off], rax
    mov rdi, r13
    call emit_arm_oob_trap

    mov rax, [r13 + 16]
    mov [armstate + ArmState.format_int_off], rax
    mov rdi, r13
    call emit_arm_format_int

    ; Dynamically patch inter-stub call in _stub_arm_input calling _stub_arm_alloc.
    mov rax, [armstate + ArmState.alloc_off]
    mov rcx, [armstate + ArmState.input_off]
    add rcx, 0x44            ; input_off + 0x44
    sub rax, rcx             ; disp_bytes
    sar rax, 2               ; disp_words
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d              ; patched BL instruction dword
    mov rdi, r13             ; code_buf
    mov rsi, [armstate + ArmState.input_off]
    add rsi, 0x44            ; patch offset
    mov rdx, rax             ; patch dword value
    call patch_dword

    ; Dynamically patch inter-stub call in _stub_arm_print_list calling _stub_arm_format_int.
    mov rax, [armstate + ArmState.format_int_off]
    mov rcx, [armstate + ArmState.print_list_off]
    add rcx, 0x74            ; print_list_off + 0x74
    sub rax, rcx             ; disp_bytes
    sar rax, 2               ; disp_words
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d              ; patched BL instruction dword
    mov rdi, r13             ; code_buf
    mov rsi, [armstate + ArmState.print_list_off]
    add rsi, 0x74            ; patch offset
    mov rdx, rax             ; patch dword value
    call patch_dword

    ; Dynamically patch inter-stub call in _stub_arm_print_dict calling _stub_arm_format_int.
    mov rax, [armstate + ArmState.format_int_off]
    mov rcx, [armstate + ArmState.print_dict_off]
    add rcx, 0xF8            ; print_dict_off + 0xF8
    sub rax, rcx             ; disp_bytes
    sar rax, 2               ; disp_words
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d              ; patched BL instruction dword
    mov rdi, r13             ; code_buf
    mov rsi, [armstate + ArmState.print_dict_off]
    add rsi, 0xF8            ; patch offset
    mov rdx, rax             ; patch dword value
    call patch_dword

    ; Dynamically patch inter-stub call in _stub_arm_print_dict calling _stub_arm_print_list.
    mov rax, [armstate + ArmState.print_list_off]
    mov rcx, [armstate + ArmState.print_dict_off]
    add rcx, 0x190           ; print_dict_off + 0x190
    sub rax, rcx             ; disp_bytes
    sar rax, 2               ; disp_words
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d              ; patched BL instruction dword
    mov rdi, r13             ; code_buf
    mov rsi, [armstate + ArmState.print_dict_off]
    add rsi, 0x190           ; patch offset
    mov rdx, rax             ; patch dword value
    call patch_dword

    ; Dynamically patch inter-stub call in _stub_arm_print_dict calling _stub_arm_print_dict.
    mov rax, [armstate + ArmState.print_dict_off]
    mov rcx, [armstate + ArmState.print_dict_off]
    add rcx, 0x198           ; print_dict_off + 0x198
    sub rax, rcx             ; disp_bytes
    sar rax, 2               ; disp_words
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d              ; patched BL instruction dword
    mov rdi, r13             ; code_buf
    mov rsi, [armstate + ArmState.print_dict_off]
    add rsi, 0x198           ; patch offset
    mov rdx, rax             ; patch dword value
    call patch_dword

    ; 3. Emit All Functions in AST
    mov rbx, [r12 + ASTNode.child1]
.fn_loop:
    test rbx, rbx
    jz .done_fns

    cmp qword [rbx + ASTNode.type], AST_FN_DECL
    jne .next_top

    mov rdi, rbx
    call arm_emit_fn

.next_top:
    mov rbx, [rbx + ASTNode.next]
    jmp .fn_loop

.done_fns:
    ; Patch bl main in _start (at word 0)
    mov rax, [armstate + ArmState.fn_main_off]
    sar rax, 2               ; convert to word offset
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    mov rdi, r13
    xor rsi, rsi
    mov edx, eax
    call patch_dword

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


arm_patch_break_list:
    push rbp
    mov rbp, rsp
    push rbx
    push r10

    mov rax, [rdi + 16]        ; len
    mov rbx, [arm_break_head]
.patch_loop:
    test rbx, rbx
    jz .done
    mov rcx, [rdi + 0]         ; ptr
    mov r10d, [rcx + rbx]
    mov rdx, rax
    sub rdx, rbx
    sar rdx, 2
    and edx, 0x03FFFFFF
    or edx, 0x14000000
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


arm_emit_fn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov qword [arm_defer_count], 0
    mov qword [arm_is_main_fn], 0
    mov qword [arm_break_head], 0

    mov r12, rdi             ; fn AST node
    mov r13, [armstate + ArmState.code_buf]

    ; Register function in fn_table
    mov rax, [r13 + 16]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rax
    call add_fn_symbol

    ; Check main
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_main_arm
    mov rdx, [r12 + ASTNode.val_len]
    cmp rdx, 4
    jne .not_main
    call str_ncmp
    test rax, rax
    jnz .not_main
    mov qword [arm_is_main_fn], 1
    mov rax, [r13 + 16]
    mov [armstate + ArmState.fn_main_off], rax
.not_main:

    ; Prologue:
    ; stp x29, x30, [sp, #-48]! -> 0xA9BD7BFD
    EMIT_ARM 0xA9BD7BFD
    ; mov x29, sp -> 0x910003FD
    EMIT_ARM 0x910003FD
    ; sub sp, sp, #256 -> 0xD10403FF
    EMIT_ARM 0xD10403FF

    call sym_init
    mov qword [armstate + ArmState.stack_offset], 64

    ; Process Parameters
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10             ; param counter
.param_loop:
    test rbx, rbx
    jz .body

    mov r15, [armstate + ArmState.stack_offset]
    mov r8, [rbx + ASTNode.child1]     ; type ptr (if struct)
    mov r9, [rbx + ASTNode.child2]     ; type len (if struct)

    test r8, r8
    jz .p_scalar

    push rbx
    push r10
    mov rdi, [armstate + ArmState.ast_root]
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

    add qword [armstate + ArmState.stack_offset], r11
    xor r14, r14
.p_copy_loop:
    cmp r14, r11
    jge .param_next

    ; stur x[r10], [x29, #-(r15 + r14)]
    mov rax, r15
    add rax, r14
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    or eax, r10d
    EMIT_ARM eax

    inc r10
    add r14, 8
    jmp .p_copy_loop

.p_scalar:
    mov rcx, [armstate + ArmState.stack_offset]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [armstate + ArmState.stack_offset], 16

    ; stur x[r10], [x29, #-rcx]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    or eax, r10d
    EMIT_ARM eax

    ; stur x11, [x29, #-(rcx + 8)] (INT tag = 1)
    ; mov x11, #1 -> 0xD280002B
    EMIT_ARM 0xD280002B
    mov rax, rcx
    add rax, 8
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003AB
    or eax, r8d
    EMIT_ARM eax

    inc r10

.param_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .param_loop

.body:
    ; Emit Function Body
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_stmt

    cmp qword [arm_is_main_fn], 1
    jne .epilogue_no_defer

    mov rbx, [arm_defer_count]
.fn_falloff_unwind_loop:
    test rbx, rbx
    jz .epilogue_no_defer
    dec rbx
    mov rdi, [arm_defer_nodes + rbx * 8]
    push rbx
    call arm_emit_stmt
    pop rbx
    jmp .fn_falloff_unwind_loop

.epilogue_no_defer:
    ; Epilogue:
    ; mov x0, #0
    EMIT_ARM 0xD2800000
    ; add sp, sp, #256 -> 0x910403FF
    EMIT_ARM 0x910403FF
    ; ldp x29, x30, [sp], #48 -> 0xA8C37BFD
    EMIT_ARM 0xA8C37BFD
    ; ret -> 0xD65F03C0
    EMIT_ARM 0xD65F03C0

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


arm_emit_stmt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov qword [rbp - 80], 0
    mov qword [rbp - 88], 0

    mov r12, rdi
    mov r13, [armstate + ArmState.code_buf]

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
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_stmt
    jmp .next

.s_defer:
    cmp qword [arm_is_main_fn], 1
    jne .next
    mov rcx, [arm_defer_count]
    mov rax, [r12 + ASTNode.child1]
    mov [arm_defer_nodes + rcx * 8], rax
    inc qword [arm_defer_count]
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

    mov rcx, [armstate + ArmState.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [armstate + ArmState.stack_offset], 16
    mov rax, rcx

.var_has_slot:
    push rax                 ; stack offset
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr       ; x0 = val, x1 = tag
    pop rcx                  ; stack offset

    ; stur x0, [x29, #-off]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    EMIT_ARM eax

    ; stur x1, [x29, #-(off + 8)]
    mov rax, rcx
    add rax, 8
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A1
    or eax, r8d
    EMIT_ARM eax
    jmp .next

.s_var_field_assign:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = RHS val, x1 = RHS tag
    ; str x0, [sp, #-16]! -> 0xF81F0FE0
    EMIT_ARM 0xF81F0FE0

    mov rdi, [armstate + ArmState.ast_root]
    mov rsi, [r12 + ASTNode.child2]
    call resolve_field_access
    mov r8, rax              ; target offset

    ; ldr x0, [sp], #16 -> 0xF84107E0
    EMIT_ARM 0xF84107E0

    ; stur x0, [x29, #-r8]
    mov rax, r8
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    EMIT_ARM eax
    jmp .next

.s_var_struct_lit:
    mov r14, [rbx + ASTNode.val]
    mov r15, [rbx + ASTNode.val_len]

    mov rdi, [armstate + ArmState.ast_root]
    mov rsi, r14
    mov rdx, r15
    call find_struct_decl
    test rax, rax
    jz .next
    mov r11, rax                     ; r11 = struct_decl node

    mov rcx, [armstate + ArmState.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    mov rcx, r14
    mov r8, r15
    push r11
    push rdx
    call add_symbol_type
    pop rcx                          ; rcx = base stack offset
    pop r11

    mov rax, [r11 + ASTNode.extra]
    add qword [armstate + ArmState.stack_offset], rax

    mov r10, [rbx + ASTNode.child1]  ; r10 = FieldInit list
    xor r15, r15                     ; current_field_offset = 0
    call .emit_arm_struct_lit_fields
    jmp .next

.emit_arm_struct_lit_fields:
.slit_loop_arm:
    test r10, r10
    jz .slit_done_arm

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
    jz .slit_next_arm

    mov r8, [rax + ASTNode.extra]     ; field offset inside struct
    add r8, r15                      ; total combined field offset
    mov r14, [r10 + ASTNode.child1]  ; field expr node

    cmp qword [r14 + ASTNode.type], AST_STRUCT_LIT
    je .slit_nested_struct_arm

    push r11
    push r10
    push rcx
    push r15
    push r8
    mov rdi, r14
    call arm_emit_expr               ; x0 = val, x1 = tag
    pop r8
    pop r15
    pop rcx
    pop r10
    pop r11

    ; stur x0, [x29, #-(base_off + field_off)]
    mov rax, rcx
    add rax, r8
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    EMIT_ARM eax
    jmp .slit_next_arm

.slit_nested_struct_arm:
    mov rdi, [armstate + ArmState.ast_root]
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
    jz .slit_next_arm

    push r11
    push r10
    push rcx
    push r15
    mov r11, rax                     ; nested struct_decl
    mov r10, [r14 + ASTNode.child1]  ; nested FieldInit list
    mov r15, r8                      ; updated current_field_offset
    call .emit_arm_struct_lit_fields
    pop r15
    pop rcx
    pop r10
    pop r11

.slit_next_arm:
    mov r10, [r10 + ASTNode.next]
    jmp .slit_loop_arm

.slit_done_arm:
    ret

.s_return:
    mov rdi, [r12 + ASTNode.child1]
    test rdi, rdi
    jz .ret_no_expr
    call arm_emit_expr
    jmp .ret_unwind

.ret_no_expr:
    ; mov x0, #0
    EMIT_ARM 0xD2800000

.ret_unwind:
    cmp qword [arm_is_main_fn], 1
    jne .ret_epilogue

    ; str x0, [sp, #-16]! -> push x0
    EMIT_ARM 0xF81F0FE0

    mov rbx, [arm_defer_count]
.ret_unwind_loop:
    test rbx, rbx
    jz .ret_unwind_done
    dec rbx
    mov rdi, [arm_defer_nodes + rbx * 8]
    push rbx
    call arm_emit_stmt
    pop rbx
    jmp .ret_unwind_loop

.ret_unwind_done:
    ; ldr x0, [sp], #16 -> pop x0
    EMIT_ARM 0xF84107E0

.ret_epilogue:
    ; add sp, sp, #256 -> 0x910403FF
    EMIT_ARM 0x910403FF
    ; ldp x29, x30, [sp], #48 -> 0xA8C37BFD
    EMIT_ARM 0xA8C37BFD
    ; ret -> 0xD65F03C0
    EMIT_ARM 0xD65F03C0
    jmp .next

.s_if:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr

    ; cbz x0, else_target (0xB4000000 - placeholder)
    mov rbx, [r13 + 16]      ; offset
    push rbx
    EMIT_ARM 0xB4000000

    ; then block
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_stmt

    ; b end_target (0x14000000 - placeholder)
    mov r10, [r13 + 16]
    push r10
    EMIT_ARM 0x14000000

    ; Patch cbz
    mov rax, [r13 + 16]
    pop r10
    pop rbx
    push r10
    sub rax, rbx
    sar rax, 2               ; word offset
    and eax, 0x7FFFF
    shl eax, 5
    mov r8d, 0xB4000000
    or eax, r8d
    mov rdi, r13
    mov rsi, rbx
    mov edx, eax
    call patch_dword

    ; else block
    mov rdi, [r12 + ASTNode.child3]
    test rdi, rdi
    jz .patch_if_end
    call arm_emit_stmt

.patch_if_end:
    ; Patch b end
    mov rax, [r13 + 16]
    pop r10
    sub rax, r10
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    mov rdi, r13
    mov rsi, r10
    mov edx, eax
    call patch_dword
    jmp .next

.s_while:
    push qword [arm_break_head]
    mov qword [arm_break_head], 0

    mov rbx, [r13 + 16]      ; loop_start
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr

    ; cbz x0, loop_end
    mov r10, [r13 + 16]
    push rbx
    push r10
    EMIT_ARM 0xB4000000

    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_stmt

    pop r10
    pop rbx

    ; b loop_start
    mov rax, rbx
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    EMIT_ARM eax

    ; Patch cbz
    mov rax, [r13 + 16]
    sub rax, r10
    sar rax, 2
    and eax, 0x7FFFF
    shl eax, 5
    mov r8d, 0xB4000000
    or eax, r8d
    mov rdi, r13
    mov rsi, r10
    mov edx, eax
    call patch_dword

    ; Patch breaks
    mov rdi, r13
    call arm_patch_break_list
    pop qword [arm_break_head]
    jmp .next

.s_for:
    push qword [arm_break_head]
    mov qword [arm_break_head], 0

    push rbp
    mov rbp, rsp
    sub rsp, 48              ; [rbp-8]=i_off, [rbp-16]=stop_off, [rbp-24]=step_off, [rbp-32]=pos_fixup

    ; Bind loop var i
    mov rcx, [armstate + ArmState.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [armstate + ArmState.stack_offset], 16
    mov [rbp - 8], rcx       ; [rbp - 8] = i_off

    ; Store tag 1 for loop variable i: stur x11, [x29, #-(i_off + 8)]
    EMIT_ARM 0xD280002B      ; mov x11, #1
    mov rax, rcx
    add rax, 8
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003AB
    EMIT_ARM eax

    ; Allocate stop limit slot
    mov rcx, [armstate + ArmState.stack_offset]
    add qword [armstate + ArmState.stack_offset], 16
    mov [rbp - 16], rcx      ; [rbp - 16] = stop_off

    ; Allocate step slot
    mov rcx, [armstate + ArmState.stack_offset]
    add qword [armstate + ArmState.stack_offset], 16
    mov [rbp - 24], rcx      ; [rbp - 24] = step_off

    ; Parse range args
    mov rbx, [r12 + ASTNode.child1]
    mov rbx, [rbx + ASTNode.child1] ; arg1
    test rbx, rbx
    jz .for_done_init_arm

    mov r10, [rbx + ASTNode.next]   ; arg2
    test r10, r10
    jnz .range_2_or_3_args_arm

    ; 1 arg: range(stop)
    mov rdi, rbx
    call arm_emit_expr
    mov rcx, [rbp - 16]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-stop_off]

    ; start = 0
    EMIT_ARM 0xD2800000      ; mov x0, #0
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-i_off]

    ; step = 1
    EMIT_ARM 0xD2800020      ; mov x0, #1
    mov rcx, [rbp - 24]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-step_off]
    jmp .for_done_init_arm

.range_2_or_3_args_arm:
    ; 2 or 3 args: range(start, stop[, step])
    mov rdi, rbx
    call arm_emit_expr       ; arg1 = start
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-i_off]

    mov rdi, r10
    call arm_emit_expr       ; arg2 = stop
    mov rcx, [rbp - 16]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-stop_off]

    mov r11, [r10 + ASTNode.next] ; arg3
    test r11, r11
    jz .range_default_step_arm

    mov rdi, r11
    call arm_emit_expr       ; arg3 = step
    mov rcx, [rbp - 24]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-step_off]
    jmp .for_done_init_arm

.range_default_step_arm:
    EMIT_ARM 0xD2800020      ; mov x0, #1
    mov rcx, [rbp - 24]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0
    EMIT_ARM eax             ; stur x0, [x29, #-step_off]

.for_done_init_arm:
    mov rbx, [r13 + 16]      ; loop_start

.for_head:
    ; Load loop var into x0: ldur x0, [x29, #-i_off]
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax

    ; Load stop limit into x1: ldur x1, [x29, #-stop_off]
    mov rcx, [rbp - 16]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A1
    or eax, r8d
    EMIT_ARM eax

    ; cmp x0, x1 -> 0xEB01001F
    EMIT_ARM 0xEB01001F

    ; b.ge for_end (0x5400000A)
    mov rax, [r13 + 16]
    mov [rbp - 32], rax      ; fixup_off
    EMIT_ARM 0x5400000A

    ; Emit body
    push rbx
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_stmt
    pop rbx

    ; Increment loop var: i += step
    ; ldur x0, [x29, #-i_off]
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax

    ; ldur x1, [x29, #-step_off]
    mov rcx, [rbp - 24]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A1
    or eax, r8d
    EMIT_ARM eax

    ; add x0, x0, x1 -> 0x8B010000
    EMIT_ARM 0x8B010000

    ; stur x0, [x29, #-i_off]
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    EMIT_ARM eax

    ; b for_head
    mov rax, rbx
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    EMIT_ARM eax

    ; Patch b.ge
    mov rax, [r13 + 16]
    mov rcx, [rbp - 32]
    sub rax, rcx
    sar rax, 2               ; word offset
    and eax, 0x7FFFF
    shl eax, 5
    mov r8d, 0x5400000A
    or eax, r8d
    mov rdi, r13
    mov rsi, rcx
    mov edx, eax
    call patch_dword

    mov rsp, rbp
    pop rbp

    ; Patch breaks
    mov rdi, r13
    call arm_patch_break_list
    pop qword [arm_break_head]
    jmp .next

.s_loop:
    push qword [arm_break_head]
    mov qword [arm_break_head], 0

    mov rbx, [r13 + 16]
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_stmt

    ; b loop_start
    mov rax, rbx
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    EMIT_ARM eax

    ; Patch breaks
    mov rdi, r13
    call arm_patch_break_list
    pop qword [arm_break_head]
    jmp .next

.s_break:
    mov rax, [r13 + 16]      ; fixup_off
    mov rsi, [arm_break_head]    ; old head
    mov rdi, r13
    call emit_dword          ; placeholder stores old head
    mov [arm_break_head], rax    ; new head
    jmp .next

.s_asm_block:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_asm_lines
    jmp .next

.s_expr_stmt:
    mov rdi, [r12 + ASTNode.child1]
    test rdi, rdi
    jz .next
    call arm_emit_expr
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


arm_emit_expr:
    push rbp
    mov rbp, rsp
    sub rsp, 128
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov qword [rbp - 80], 0
    mov qword [rbp - 88], 0

    mov r12, rdi
    mov r13, [armstate + ArmState.code_buf]

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
    cmp rax, AST_FIELD_ACCESS
    je .e_field_access
    cmp rax, AST_TERNARY
    je .e_ternary
    cmp rax, AST_LIST_LIT
    je .e_list_lit
    cmp rax, AST_INDEX
    je .e_index
    cmp rax, AST_DICT_LIT
    je .e_dict_lit
    jmp .done

.e_dict_lit:
    mov rbx, [r12 + ASTNode.child1]
    xor r14, r14
.d_count_loop_arm:
    test rbx, rbx
    jz .d_count_done_arm
    inc r14
    mov rbx, [rbx + ASTNode.next]
    jmp .d_count_loop_arm

.d_count_done_arm:
    mov rax, r14
    shl rax, 5
    add rax, 16

    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800000
    or eax, r8d
    EMIT_ARM eax             ; mov x0, alloc_size

    mov rax, [armstate + ArmState.alloc_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax             ; bl alloc_off -> x0 = dict_ptr

    mov eax, r14d
    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800001
    or eax, r8d
    EMIT_ARM eax             ; mov x1, n
    EMIT_ARM 0xF9000001      ; str x1, [x0]
    EMIT_ARM 0xF9000401      ; str x1, [x0, #8]

    mov rbx, [r12 + ASTNode.child1]
    xor r15, r15
.d_elem_emit_loop_arm:
    test rbx, rbx
    jz .d_elem_emit_done_arm

    push r15                 ; save elem index r15

    EMIT_ARM 0xA9BF07E0      ; stp x0, x1, [sp, #-16]! (spill dict_ptr x0 and tag x1)

    push rbx
    mov rdi, [rbx + ASTNode.child2] ; key_expr
    call arm_emit_expr              ; x0 = key_ptr, x1 = key_tag
    pop rbx

    EMIT_ARM 0xF1000C3F      ; cmp x1, #3 (STRING tag)
    mov r8, [r13 + 16]
    mov [rbp - 8], r8
    EMIT_ARM 0x54000000      ; b.eq +8

    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [r13 + 16]
    mov r8, [rbp - 8]
    sub rax, r8
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    mov r8d, 0x54000000
    or eax, r8d
    mov rdi, r13
    mov rsi, [rbp - 8]
    mov rdx, rax
    call patch_dword

    EMIT_ARM 0xA9BF07E0      ; stp x0, x1, [sp, #-16]! (spill key_ptr x0 and tag x1)

    push rbx
    mov rdi, [rbx + ASTNode.child1] ; val_expr
    call arm_emit_expr              ; x0 = val, x1 = val_tag
    pop rbx

    EMIT_ARM 0xA8C10FE2      ; ldp x2, x3, [sp], #16 (pop key_ptr into x2, tag into x3)
    EMIT_ARM 0xA8C117E4      ; ldp x4, x5, [sp], #16 (pop dict_ptr into x4, tag into x5)

    pop r15                  ; restore elem index r15
    mov rax, r15
    shl rax, 5
    add rax, 16              ; rax = offset

    mov r8, rax
    shr r8, 3
    shl r8, 10
    mov r9d, 0xF9000082
    or r8d, r9d
    EMIT_ARM r8d             ; str x2, [x4, #offset]

    EMIT_ARM 0xD2800068      ; mov x8, #3
    add rax, 8
    mov r8, rax
    shr r8, 3
    shl r8, 10
    mov r9d, 0xF9000088
    or r8d, r9d
    EMIT_ARM r8d             ; str x8, [x4, #offset+8]

    add rax, 8
    mov r8, rax
    shr r8, 3
    shl r8, 10
    mov r9d, 0xF9000080
    or r8d, r9d
    EMIT_ARM r8d             ; str x0, [x4, #offset+16]

    add rax, 8
    mov r8, rax
    shr r8, 3
    shl r8, 10
    mov r9d, 0xF9000081
    or r8d, r9d
    EMIT_ARM r8d             ; str x1, [x4, #offset+24]

    EMIT_ARM 0xAA0403E0      ; mov x0, x4 (dict_ptr)

    inc r15
    mov rbx, [rbx + ASTNode.next]
    jmp .d_elem_emit_loop_arm

.d_elem_emit_done_arm:
    EMIT_ARM 0xD28000A1      ; mov x1, #5 (DICT tag)
    jmp .done

.e_list_lit:
    mov rbx, [r12 + ASTNode.child1]
    xor r14, r14
.l_count_loop_arm:
    test rbx, rbx
    jz .l_count_done_arm
    inc r14
    mov rbx, [rbx + ASTNode.next]
    jmp .l_count_loop_arm

.l_count_done_arm:
    mov rax, r14
    shl rax, 4
    add rax, 16

    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [armstate + ArmState.alloc_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov eax, r14d
    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800001
    or eax, r8d
    EMIT_ARM eax
    EMIT_ARM 0xF9000001
    EMIT_ARM 0xF9000401

    mov rbx, [r12 + ASTNode.child1]
    xor r15, r15
.l_elem_emit_loop_arm:
    test rbx, rbx
    jz .l_elem_emit_done_arm

    EMIT_ARM 0xF81F0FE0

    push rbx
    push r15
    mov rdi, rbx
    call arm_emit_expr
    pop r15
    pop rbx

    EMIT_ARM 0xF84107E2

    mov rax, r15
    shl rax, 4
    add rax, 16

    mov r8, rax
    shr r8, 3
    shl r8, 10
    mov r9d, 0xF9000040
    or r8d, r9d
    EMIT_ARM r8d

    add rax, 8
    shr rax, 3
    shl rax, 10
    mov r9d, 0xF9000041
    or eax, r9d
    EMIT_ARM eax

    EMIT_ARM 0xAA0203E0

    inc r15
    mov rbx, [rbx + ASTNode.next]
    jmp .l_elem_emit_loop_arm

.l_elem_emit_done_arm:
    EMIT_ARM 0xD2800081
    jmp .done

.e_index:
    mov qword [rbp - 80], 0
    mov qword [rbp - 88], 0

    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = base_ptr, x1 = base_tag

    EMIT_ARM 0xF100143F       ; cmp x1, #5
    mov rax, [r13 + 16]
    mov [rbp - 8], rax        ; dict_idx_jz_fixup
    EMIT_ARM 0x54000000       ; b.eq .dict_idx_path

    EMIT_ARM 0xF100103F       ; cmp x1, #4
    mov rax, [r13 + 16]
    mov [rbp - 16], rax       ; list_idx_jz_fixup
    EMIT_ARM 0x54000000       ; b.eq .list_idx_path

    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

.list_idx_path_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 16]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 16]
    mov edx, eax
    call patch_dword          ; patch b.eq .list_idx_path

.idx_base_ok:
    EMIT_ARM 0xF81F0FE0       ; str x0, [sp, #-16]!

    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_expr

    EMIT_ARM 0xF100043F       ; cmp x1, #1
    mov rbx, [r13 + 16]
    push rbx
    EMIT_ARM 0x54000000       ; b.eq

    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [r13 + 16]
    pop rbx
    sub rax, rbx
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    mov r8d, 0x54000000
    or eax, r8d
    mov rdi, r13
    mov rsi, rbx
    mov rdx, rax
    call patch_dword

.idx_tag_ok:
    EMIT_ARM 0xF84107E2       ; ldr x2, [sp], #16

    EMIT_ARM 0xF100001F       ; cmp x0, #0
    mov rbx, [r13 + 16]
    push rbx
    EMIT_ARM 0x5400000B       ; b.lt

    EMIT_ARM 0xF9400043       ; ldr x3, [x2]
    EMIT_ARM 0xEB03001F       ; cmp x0, x3
    mov r10, [r13 + 16]
    push r10
    EMIT_ARM 0x5400000A       ; b.ge

    mov r14, [r13 + 16]
    push r14
    EMIT_ARM 0x14000000       ; b

    mov rax, [r13 + 16]
    pop r14
    pop r10
    pop rbx
    push r14

    mov rcx, rax
    sub rcx, rbx
    sar rcx, 2
    and ecx, 0x0007FFFF
    shl ecx, 5
    mov r8d, 0x5400000B
    or ecx, r8d
    mov rdi, r13
    mov rsi, rbx
    mov rdx, rcx
    call patch_dword

    mov rcx, rax
    sub rcx, r10
    sar rcx, 2
    and ecx, 0x0007FFFF
    shl ecx, 5
    mov r8d, 0x5400000A
    or ecx, r8d
    mov rdi, r13
    mov rsi, r10
    mov rdx, rcx
    call patch_dword

.idx_oob:
    mov rax, [armstate + ArmState.oob_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [r13 + 16]
    pop r14
    sub rax, r14
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    mov rdi, r13
    mov rsi, r14
    mov rdx, rax
    call patch_dword

.idx_in_range:
    EMIT_ARM 0x91004042
    EMIT_ARM 0x8B001042
    EMIT_ARM 0xF9400441
    EMIT_ARM 0xF9400040

    ; Emit b .done at RUNTIME
    mov rax, [r13 + 16]
    mov [rbp - 80], rax       ; list_idx_done_fixup
    EMIT_ARM 0x14000000

.dict_idx_path_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 8]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 8]
    mov edx, eax
    call patch_dword

    EMIT_ARM 0xA9BF07E0       ; stp x0, x1, [sp, #-16]! (spill dict_ptr x0 and dict_tag x1)

    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_expr        ; lookup key_expr -> x0 = key_ptr, x1 = key_tag

    EMIT_ARM 0xA8C10FE2       ; ldp x2, x3, [sp], #16 (restore dict_ptr x2 and dict_tag x3)

    EMIT_ARM 0xF1000C3F       ; cmp x1, #3 (STRING tag)
    mov rax, [r13 + 16]
    mov [rbp - 64], rax       ; tag_chk_fixup
    EMIT_ARM 0x54000000       ; b.eq

    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [r13 + 16]
    sub rax, [rbp - 64]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    mov r8d, 0x54000000
    or eax, r8d
    mov rdi, r13
    mov rsi, [rbp - 64]
    mov rdx, rax
    call patch_dword

    EMIT_ARM 0xF9400043       ; ldr x3, [x2] (n entries)
    EMIT_ARM 0xD2800004       ; mov x4, #0 (i = 0)

.dict_search_loop_arm:
    EMIT_ARM 0xEB03009F       ; cmp x4, x3
    mov rax, [r13 + 16]
    mov [rbp - 72], rax       ; not_found_fixup
    EMIT_ARM 0x5400000A       ; b.ge .dict_not_found

    EMIT_ARM 0x91004045       ; add x5, x2, #16
    EMIT_ARM 0x8B0414A5       ; add x5, x5, x4, lsl #5
    EMIT_ARM 0xF94000A6       ; ldr x6, [x5] (entry key_ptr)

    EMIT_ARM 0xD2800007       ; mov x7, #0 (char index)

.dict_cmp_loop_arm:
    EMIT_ARM 0x38676808       ; ldrb w8, [x0, x7]
    EMIT_ARM 0x386768C9       ; ldrb w9, [x6, x7]
    EMIT_ARM 0x6B09011F       ; cmp w8, w9
    EMIT_ARM 0x54000081       ; b.ne .dict_next_entry (+4 words)
    EMIT_ARM 0x340000A8       ; cbz w8, .dict_found (+5 words)
    EMIT_ARM 0x910004E7       ; add x7, x7, #1
    EMIT_ARM 0x17FFFFFA       ; b .dict_cmp_loop_arm (-6 words)

.dict_next_entry_arm:
    EMIT_ARM 0x91000484       ; add x4, x4, #1
    EMIT_ARM 0x17FFFFF2       ; b .dict_search_loop_arm (-14 words)

.dict_found_arm:
    EMIT_ARM 0xF94008A0       ; ldr x0, [x5, #16] (val)
    EMIT_ARM 0xF9400CA1       ; ldr x1, [x5, #24] (val_tag)

    mov rax, [r13 + 16]
    mov [rbp - 88], rax       ; dict_idx_done_fixup
    EMIT_ARM 0x14000000       ; b .done at RUNTIME

.dict_not_found_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 72]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    mov r8d, 0x5400000A
    or eax, r8d
    mov rdi, r13
    mov rsi, [rbp - 72]
    mov rdx, rax
    call patch_dword

    mov rax, [armstate + ArmState.dict_missing_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

.e_index_done:
    mov rsi, [rbp - 80]
    test rsi, rsi
    jz .chk_dict_idx_done
    mov rax, [r13 + 16]
    sub rax, rsi
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rdx, rax
    call patch_dword

.chk_dict_idx_done:
    mov rsi, [rbp - 88]
    test rsi, rsi
    jz .done
    mov rax, [r13 + 16]
    sub rax, rsi
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rdx, rax
    call patch_dword
    jmp .done

.e_ternary:
    push r12                 ; save outer AST_TERNARY node

    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr       ; x0 = val, x1 = tag

    ; Truthiness check: cmp x1, #3 (STRING tag) -> 0xF1000C3F
    EMIT_ARM 0xF1000C3F
    ; b.eq .t_str_chk_arm (+2 words -> 0x54000040)
    EMIT_ARM 0x54000040

    ; Non-string truthiness: cmp x0, #0 -> 0xF100001F
    EMIT_ARM 0xF100001F
    ; b .t_branch_test_arm (+2 words -> 0x14000002)
    EMIT_ARM 0x14000002

.t_str_chk_arm:
    ; String truthiness: ldrb w0, [x0] -> 0x39400000
    EMIT_ARM 0x39400000
    ; cmp x0, #0 -> 0xF100001F
    EMIT_ARM 0xF100001F

.t_branch_test_arm:
    ; b.eq false_branch_arm (0x54000000 - placeholder)
    mov rbx, [r13 + 16]      ; offset
    push rbx
    EMIT_ARM 0x54000000

    ; True branch: evaluate child2
    mov r12, [rsp + 8]       ; restore r12 from stack
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_expr

    ; b end_ternary_arm (0x14000000 - placeholder)
    mov r10, [r13 + 16]
    push r10
    EMIT_ARM 0x14000000

    ; Patch b.eq (false_branch_arm start)
    mov rax, [r13 + 16]
    pop r10                  ; re-push b offset
    pop rbx                  ; b.eq offset
    push r10
    sub rax, rbx
    sar rax, 2               ; word offset
    and eax, 0x7FFFF
    shl eax, 5
    mov r8d, 0x54000000
    or eax, r8d
    mov rdi, r13
    mov rsi, rbx
    mov edx, eax
    call patch_dword

    ; False branch: evaluate child3
    mov r12, [rsp + 8]       ; restore r12 from stack
    mov rdi, [r12 + ASTNode.child3]
    call arm_emit_expr

    ; Patch b (end_ternary_arm)
    mov rax, [r13 + 16]
    pop r10                  ; b offset
    sub rax, r10
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    mov rdi, r13
    mov rsi, r10
    mov edx, eax
    call patch_dword

    pop r12                  ; restore r12
    jmp .done

.e_alloc:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = size
    ; bl alloc
    mov rax, [armstate + ArmState.alloc_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.e_field_access:
    mov rdi, [armstate + ArmState.ast_root]
    mov rsi, r12
    call resolve_field_access
    cmp rax, -1
    je .done

    ; ldur x0, [x29, #-off]
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax

    ; mov x1, #1 (INT tag = 1) -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.e_literal:
    mov rdi, [r12 + ASTNode.val]
    mov rcx, [r12 + ASTNode.val_len]
    test rdi, rdi
    jz .e_lit_zero_arm
    mov al, [rdi]
    cmp al, '0'
    jl .e_lit_str_arm
    cmp al, '9'
    jg .e_lit_str_arm

    xor r8, r8
.chk_float_dot_arm:
    cmp r8, rcx
    jge .is_int_lit_arm
    cmp byte [rdi + r8], '.'
    je .e_lit_float_arm
    inc r8
    jmp .chk_float_dot_arm

.e_lit_float_arm:
    ; mov x0, #0 -> 0xD2800000
    EMIT_ARM 0xD2800000
    ; mov x1, #2 (FLOAT tag = 2) -> 0xD2800041
    EMIT_ARM 0xD2800041
    jmp .done

.is_int_lit_arm:
    xor rsi, rsi
    mov r8, [r12 + ASTNode.line]
    call parse_int_literal
    mov rbx, rax

    mov eax, ebx
    and eax, 0xFFFF
    shl eax, 5
    or eax, 0xD2800000
    EMIT_ARM eax

    mov rax, rbx
    shr rax, 16
    and eax, 0xFFFF
    jz .chk_chunk2
    shl eax, 5
    or eax, 0xF2A00000
    EMIT_ARM eax

.chk_chunk2:
    mov rax, rbx
    shr rax, 32
    and eax, 0xFFFF
    jz .chk_chunk3
    shl eax, 5
    or eax, 0xF2C00000
    EMIT_ARM eax

.chk_chunk3:
    mov rax, rbx
    shr rax, 48
    and eax, 0xFFFF
    jz .chunk_done
    shl eax, 5
    or eax, 0xF2E00000
    EMIT_ARM eax

.chunk_done:

    ; mov x1, #1 (INT tag = 1) -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.e_lit_str_arm:
    mov rbx, [r12 + ASTNode.val_len]
    mov rax, rbx
    add rax, 4
    and rax, -4              ; align string len to multiple of 4 bytes
    sar rax, 2               ; string words
    inc rax                  ; +1 for the branch instruction itself
    and eax, 0x03FFFFFF
    mov r8d, 0x14000000
    or eax, r8d
    EMIT_ARM eax

    mov r14, [r13 + 16]      ; str_addr_off

    mov rdi, r13
    mov rsi, [r12 + ASTNode.val]
    mov rdx, rbx
    call emit_bytes
    mov sil, 0
    call emit_byte           ; null byte

.align_loop:
    mov rax, [r13 + 16]
    test rax, 3
    jz .aligned
    mov rdi, r13
    mov sil, 0
    call emit_byte
    jmp .align_loop

.aligned:
    ; adr x0, str_addr
    mov rax, r14
    sub rax, [r13 + 16]      ; negative relative offset
    mov r8, rax
    and r8d, 3               ; immlo = rax & 3
    shl r8d, 29
    sar rax, 2               ; immhi = rax >> 2 (signed)
    and eax, 0x7FFFF         ; mask 19 bits
    shl eax, 5
    or eax, r8d
    mov r8d, 0x10000000
    or eax, r8d
    EMIT_ARM eax             ; adr x0, str_addr

    ; mov x1, #3 (STRING tag = 3) -> 0xD2800061
    EMIT_ARM 0xD2800061
    jmp .done

.e_lit_zero_arm:
    ; mov x0, #0 -> 0xD2800000
    EMIT_ARM 0xD2800000
    ; mov x1, #0 -> 0xD2800001
    EMIT_ARM 0xD2800001
    jmp .done

.e_ident:
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_symbol_offset
    cmp rax, -1
    je .done

    mov rbx, rax

    ; ldur x0, [x29, #-off]
    mov rax, rbx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax

    ; ldur x1, [x29, #-(off + 8)]
    mov rax, rbx
    add rax, 8
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A1
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.e_bin_op:
    ; Left child
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = val, x1 = tag
    ; str x0, [sp, #-16]! -> 0xF81F0FE0
    EMIT_ARM 0xF81F0FE0
    ; str x1, [sp, #-16]! -> 0xF81F0FE1
    EMIT_ARM 0xF81F0FE1

    ; Right child
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_expr        ; x0 = right val, x1 = right tag

    ; ldr x3, [sp], #16 -> 0xF84107E3 (left tag)
    EMIT_ARM 0xF84107E3
    ; ldr x2, [sp], #16 -> 0xF84107E2 (left val)
    EMIT_ARM 0xF84107E2

    ; Check if left tag (x3) != 1 or right tag (x1) != 1
    ; cmp x3, #1 -> 0xF100047F
    EMIT_ARM 0xF100047F
    ; b.ne +16 -> 0x54000081 (to trap bl)
    EMIT_ARM 0x54000081

    ; cmp x1, #1 -> 0xF100043F
    EMIT_ARM 0xF100043F
    ; b.ne +8 -> 0x54000041 (trap)
    EMIT_ARM 0x54000041
    ; b +8 -> 0x14000002 (skip trap)
    EMIT_ARM 0x14000002

    ; Trigger type_mismatch_trap
    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    ; Op
    mov r11, [r12 + ASTNode.val]
    mov r8b, [r11]
    mov r9b, [r11 + 1]

    cmp r8b, '&'
    je .op_band_arm
    cmp r8b, '|'
    je .op_bor_arm
    cmp r8b, '^'
    je .op_bxor_arm
    cmp r8b, '<'
    je .chk_shl_arm
    cmp r8b, '>'
    je .chk_shr_arm

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
    jmp .done

.chk_shl_arm:
    cmp r9b, '<'
    je .op_shl_arm
    jmp .op_lt

.chk_shr_arm:
    cmp r9b, '>'
    je .op_shr_arm
    jmp .op_gt

.op_band_arm:
    ; and x0, x2, x0 -> 0x8A000040
    EMIT_ARM 0x8A000040
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_bor_arm:
    ; orr x0, x2, x0 -> 0xAA000040
    EMIT_ARM 0xAA000040
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_bxor_arm:
    ; eor x0, x2, x0 -> 0xCA000040
    EMIT_ARM 0xCA000040
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_shl_arm:
    ; lsl x0, x2, x0 -> 0x9AC02040
    EMIT_ARM 0x9AC02040
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_shr_arm:
    ; asrv x0, x2, x0 -> 0x9AC02840
    EMIT_ARM 0x9AC02840
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_add:
    ; add x0, x2, x0 -> 0x8B000040
    EMIT_ARM 0x8B000040
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_sub:
    ; sub x0, x2, x0 -> 0xCB000040
    EMIT_ARM 0xCB000040
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_mul:
    ; mul x0, x2, x0 -> 0x9B007C40
    EMIT_ARM 0x9B007C40
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_div:
    ; cbnz x0, +8 (0xB5000040)
    EMIT_ARM 0xB5000040

    ; bl div_zero_trap
    mov rax, [armstate + ArmState.div_zero_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    ; sdiv x0, x2, x0 -> 0x9AC00C40
    EMIT_ARM 0x9AC00C40
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_mod:
    ; cbnz x0, +8 (0xB5000040)
    EMIT_ARM 0xB5000040

    ; bl div_zero_trap
    mov rax, [armstate + ArmState.div_zero_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    ; sdiv x3, x2, x0 -> 0x9AC00C43
    EMIT_ARM 0x9AC00C43
    ; msub x0, x3, x0, x2 -> 0x9B008860
    EMIT_ARM 0x9B008860
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_eq:
    ; cmp x2, x0 (0xEB00005F); cset x0, EQ (0x9A9F17E0)
    EMIT_ARM 0xEB00005F
    EMIT_ARM 0x9A9F17E0
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_lt:
    ; cmp x2, x0 (0xEB00005F); cset x0, LT (0x9A9FA7E0)
    EMIT_ARM 0xEB00005F
    EMIT_ARM 0x9A9FA7E0
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_gt:
    ; cmp x2, x0 (0xEB00005F); cset x0, GT (0x9A9FD7E0)
    EMIT_ARM 0xEB00005F
    EMIT_ARM 0x9A9FD7E0
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.e_un_op:
    mov rbx, [r12 + ASTNode.val]
    mov cl, [rbx]
    cmp cl, '~'
    je .op_bnot_arm
    cmp cl, '&'
    je .do_addr_arm
    cmp cl, '-'
    jne .normal_un_op_arm

    mov rdi, [r12 + ASTNode.child1]
    cmp qword [rdi + ASTNode.type], AST_LITERAL
    jne .normal_un_op_arm

    mov rbx, [rdi + ASTNode.val]
    test rbx, rbx
    jz .normal_un_op_arm
    mov al, [rbx]
    cmp al, '0'
    jl .normal_un_op_arm
    cmp al, '9'
    jg .normal_un_op_arm

    mov rdi, rbx
    mov rcx, [r12 + ASTNode.child1]
    mov rcx, [rcx + ASTNode.val_len]
    mov rsi, 1
    mov r8, [r12 + ASTNode.line]
    call parse_int_literal

    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800000
    or eax, r8d
    EMIT_ARM eax
    mov eax, 0xD2800021
    EMIT_ARM eax
    EMIT_ARM 0xCB0003E0
    jmp .done

.do_addr_arm:
    mov rbx, [r12 + ASTNode.child1]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_fn_symbol
    cmp rax, -1
    je .addr_var_arm

    ; Function symbol found! rax = fn_off
    add rax, 0x400078         ; hosted base VA
    mov rbx, rax

    ; mov x0, imm (lower 16) -> movz x0, imm16
    mov eax, ebx
    and eax, 0xFFFF
    shl eax, 5
    or eax, 0xD2800000
    EMIT_ARM eax

    ; mov x0, imm (upper 16) -> movk x0, imm16, lsl #16
    mov rax, rbx
    shr rax, 16
    and eax, 0xFFFF
    shl eax, 5
    or eax, 0xF2A00000
    EMIT_ARM eax

    ; mov x1, #1 (INT tag = 1) -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.addr_var_arm:
    mov rbx, [r12 + ASTNode.child1]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_symbol_offset
    neg rax
    and eax, 0xFFF
    shl eax, 10
    mov r8d, 0xD10003A0
    or eax, r8d
    EMIT_ARM eax

    ; mov x1, #1 (INT tag = 1) -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.op_bnot_arm:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr
    ; cmp x1, #1 -> 0xF100043F
    EMIT_ARM 0xF100043F
    ; b.eq +8 -> 0x54000040 (skip trap)
    EMIT_ARM 0x54000040

    ; Trigger type_mismatch_trap
    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    ; mvn x0, x0 -> 0xAA2003E0
    EMIT_ARM 0xAA2003E0
    ; mov x1, #1 -> 0xD2800021
    EMIT_ARM 0xD2800021
    jmp .done

.normal_un_op_arm:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr
    EMIT_ARM 0xCB0003E0
    jmp .done

.e_call:
    ; Check len
    cmp qword [r12 + ASTNode.val_len], 3
    jne .chk_print
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_len_arm
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jz .call_len_arm

.chk_print:
    cmp qword [r12 + ASTNode.val_len], 5
    jne .chk_input
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_print_arm
    mov rdx, 5
    call str_ncmp
    test rax, rax
    jz .call_print

.chk_input:
    cmp qword [r12 + ASTNode.val_len], 5
    jne .chk_free
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_input_arm
    mov rdx, 5
    call str_ncmp
    test rax, rax
    jz .call_input

.chk_free:
    cmp qword [r12 + ASTNode.val_len], 4
    jne .chk_fstring
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_free_arm
    mov rdx, 4
    call str_ncmp
    test rax, rax
    jz .call_free

.chk_fstring:
    cmp qword [r12 + ASTNode.val_len], 7
    jne .user_call
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_fstring_arm
    mov rdx, 7
    call str_ncmp
    test rax, rax
    jz .call_fstring
    jmp .user_call

.call_len_arm:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr

    EMIT_ARM 0xF100143F       ; cmp x1, #5 (DICT)
    mov rax, [r13 + 16]
    mov [rbp - 72], rax       ; dict_len_jz_fixup
    EMIT_ARM 0x54000000       ; b.eq .len_is_list_arm

    EMIT_ARM 0xF100103F       ; cmp x1, #4 (LIST)
    mov rax, [r13 + 16]
    mov [rbp - 96], rax       ; list_len_jz_fixup
    EMIT_ARM 0x54000000

    EMIT_ARM 0xF1000C3F       ; cmp x1, #3 (STRING)
    mov rax, [r13 + 16]
    mov [rbp - 104], rax      ; str_len_jz_fixup
    EMIT_ARM 0x54000000

    mov rax, [armstate + ArmState.type_mismatch_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

.len_is_list_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 72]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 72]
    mov edx, eax
    call patch_dword          ; patch dict_len_jz

    mov rax, [r13 + 16]
    sub rax, [rbp - 96]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 96]
    mov rdx, rax
    call patch_dword          ; patch list_len_jz
    EMIT_ARM 0xF9400000
    EMIT_ARM 0xD2800021

    mov rax, [r13 + 16]
    mov [rbp - 112], rax      ; list_len_done_fixup
    EMIT_ARM 0x14000000

    mov rax, [r13 + 16]
    sub rax, [rbp - 104]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 104]
    mov rdx, rax
    call patch_dword          ; patch str_len_jz

.len_is_str_arm:
    EMIT_ARM 0xAA0003E1
    EMIT_ARM 0xD2800000
.len_str_loop_arm:
    EMIT_ARM 0x38600822
    EMIT_ARM 0x34000062
    EMIT_ARM 0x91000400
    EMIT_ARM 0x17FFFFFF
.len_str_done_arm:
    EMIT_ARM 0xD2800021

    mov rsi, [rbp - 112]
    mov rax, [r13 + 16]
    sub rax, rsi
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rdx, rax
    call patch_dword
    jmp .done

.call_fstring:
    ; mov x0, #256 -> 0xD2802000
    EMIT_ARM 0xD2802000

    ; bl alloc_off
    mov rax, [armstate + ArmState.alloc_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax             ; call alloc -> x0 = buf_ptr

    ; str x0, [sp, #-16]! -> 0xF81F0FE0 (push buf_start)
    EMIT_ARM 0xF81F0FE0
    ; str x0, [sp, #-16]! -> 0xF81F0FE0 (push curr_buf_ptr)
    EMIT_ARM 0xF81F0FE0

    mov rbx, [r12 + ASTNode.child1]
.fstr_loop_arm:
    test rbx, rbx
    jz .fstr_done_arm

    push rbx
    mov rdi, rbx
    call arm_emit_expr        ; x0 = val, x1 = tag
    pop rbx

    ; cmp x1, #3 -> 0xF1000C3F
    EMIT_ARM 0xF1000C3F

    ; b.eq .fstr_copy_str (+6 words -> 0x540000C0)
    EMIT_ARM 0x540000C0

.fstr_fmt_int_arm:
    ; ldr x1, [sp], #16 -> 0xF84107E1 (pop curr_buf_ptr into x1)
    EMIT_ARM 0xF84107E1

    ; bl format_int_off (x0 = val, x1 = buf_ptr)
    mov rax, [armstate + ArmState.format_int_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax             ; call format_int_off -> x0 = formatted_len

    ; add x1, x1, x0 -> 0x8B000021
    EMIT_ARM 0x8B000021

    ; str x1, [sp, #-16]! -> 0xF81F0FE1 (push updated curr_buf_ptr)
    EMIT_ARM 0xF81F0FE1

    ; b .fstr_next (+7 words -> 0x14000007)
    EMIT_ARM 0x14000007

.fstr_copy_str_arm:
    ; ldr x2, [sp], #16 -> 0xF84107E2 (pop curr_buf_ptr into x2)
    EMIT_ARM 0xF84107E2

.c_loop_arm:
    ; ldrb w3, [x0], #1 -> 0x38401403
    EMIT_ARM 0x38401403
    ; cbz w3, .c_done_arm (+3 words -> 0x34000063)
    EMIT_ARM 0x34000063
    ; strb w3, [x2], #1 -> 0x38001443
    EMIT_ARM 0x38001443
    ; b .c_loop_arm (-3 words -> 0x17FFFFFD)
    EMIT_ARM 0x17FFFFFD

.c_done_arm:
    ; str x2, [sp, #-16]! -> 0xF81F0FE2 (push updated curr_buf_ptr)
    EMIT_ARM 0xF81F0FE2

.fstr_next_arm:
    mov rbx, [rbx + ASTNode.next]
    jmp .fstr_loop_arm

.fstr_done_arm:
    ; ldr x2, [sp], #16 -> 0xF84107E2 (pop curr_buf_ptr)
    EMIT_ARM 0xF84107E2
    ; strb wzr, [x2] -> 0x3900005F
    EMIT_ARM 0x3900005F

    ; ldr x0, [sp], #16 -> 0xF84107E0 (pop buf_start into x0)
    EMIT_ARM 0xF84107E0
    ; mov x1, #3 -> 0xD2800061 (STRING tag)
    EMIT_ARM 0xD2800061
    jmp .done

.call_free:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = ptr, x1 = tag

    ; bl free_off
    mov rax, [armstate + ArmState.free_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.call_input:
    mov rbx, [r12 + ASTNode.child1]
    test rbx, rbx
    jz .input_no_prompt_arm

    push rbx
    mov rdi, rbx
    call arm_emit_expr        ; x0 = prompt_ptr
    pop rbx

    ; mov x1, #prompt_len
    mov eax, [rbx + ASTNode.val_len]
    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800001
    or eax, r8d
    EMIT_ARM eax
    jmp .do_input_call_arm

.input_no_prompt_arm:
    ; mov x0, #0 -> 0xD2800000
    EMIT_ARM 0xD2800000
    ; mov x1, #0 -> 0xD2800001
    EMIT_ARM 0xD2800001

.do_input_call_arm:
    ; bl input_off
    mov rax, [armstate + ArmState.input_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.call_print:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = val, x1 = tag

    EMIT_ARM 0xF100143F       ; cmp x1, #5 (DICT)
    mov rax, [r13 + 16]
    mov [rbp - 8], rax        ; dict_jz_fixup
    EMIT_ARM 0x54000000

    EMIT_ARM 0xF100103F       ; cmp x1, #4 (LIST)
    mov rax, [r13 + 16]
    mov [rbp - 16], rax       ; list_jz_fixup
    EMIT_ARM 0x54000000

    EMIT_ARM 0xF1000C3F       ; cmp x1, #3 (STRING)
    mov rax, [r13 + 16]
    mov [rbp - 24], rax       ; str_jz_fixup
    EMIT_ARM 0x54000000

    mov rax, [armstate + ArmState.print_int_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [r13 + 16]
    mov [rbp - 32], rax       ; int_jmp_fixup
    EMIT_ARM 0x14000000

.print_as_str_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 24]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 24]
    mov edx, eax
    call patch_dword

    mov rax, [armstate + ArmState.print_str_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    mov rax, [r13 + 16]
    mov [rbp - 40], rax       ; str_jmp_fixup
    EMIT_ARM 0x14000000

.print_as_list_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 16]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 16]
    mov edx, eax
    call patch_dword

    mov rax, [armstate + ArmState.print_list_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    EMIT_ARM 0xD10043FF
    EMIT_ARM 0x52800141
    EMIT_ARM 0x390003E1
    EMIT_ARM 0xD2800020
    EMIT_ARM 0x910003E1
    EMIT_ARM 0xD2800022
    EMIT_ARM 0xD2800808
    EMIT_ARM 0xD4000001
    EMIT_ARM 0x910043FF

    mov rax, [r13 + 16]
    mov [rbp - 48], rax       ; list_jmp_fixup
    EMIT_ARM 0x14000000

.print_as_dict_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 8]
    sar rax, 2
    and eax, 0x0007FFFF
    shl eax, 5
    or eax, 0x54000000
    mov rdi, r13
    mov rsi, [rbp - 8]
    mov edx, eax
    call patch_dword

    mov rax, [armstate + ArmState.print_dict_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax

    EMIT_ARM 0xD10043FF
    EMIT_ARM 0x52800141
    EMIT_ARM 0x390003E1
    EMIT_ARM 0xD2800020
    EMIT_ARM 0x910003E1
    EMIT_ARM 0xD2800022
    EMIT_ARM 0xD2800808
    EMIT_ARM 0xD4000001
    EMIT_ARM 0x910043FF

    mov rax, [r13 + 16]
    mov [rbp - 56], rax       ; dict_jmp_fixup
    EMIT_ARM 0x14000000

.print_done_patch_arm:
    mov rax, [r13 + 16]
    sub rax, [rbp - 56]
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rsi, [rbp - 56]
    mov edx, eax
    call patch_dword

    mov rax, [r13 + 16]
    sub rax, [rbp - 48]
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rsi, [rbp - 48]
    mov edx, eax
    call patch_dword

    mov rax, [r13 + 16]
    sub rax, [rbp - 40]
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rsi, [rbp - 40]
    mov edx, eax
    call patch_dword

    mov rax, [r13 + 16]
    sub rax, [rbp - 32]
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov rdi, r13
    mov rsi, [rbp - 32]
    mov edx, eax
    call patch_dword

    jmp .done

.user_call:
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10             ; arg count
.arm_arg_loop:
    test rbx, rbx
    jz .pop_arm_args

    cmp qword [rbx + ASTNode.type], AST_IDENT
    jne .arm_arg_eval_expr

    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_symbol_entry
    test rax, rax
    jz .arm_arg_eval_expr

    mov r14, [rax + 24]       ; type_ptr
    mov r15, [rax + 32]       ; type_len
    mov rcx, [rax + 16]       ; base stack offset
    test r14, r14
    jz .arm_arg_eval_expr

    mov rdi, [armstate + ArmState.ast_root]
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
    jz .arm_arg_eval_expr

    mov r11, [rax + ASTNode.extra]  ; struct size
    xor r14, r14                    ; word offset
.arm_arg_struct_loop:
    cmp r14, r11
    jge .arm_arg_next

    ; ldur x0, [x29, #-(rcx + r14)]
    mov rax, rcx
    add rax, r14
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax

    ; str x0, [sp, #-16]! -> 0xF81F0FE0
    EMIT_ARM 0xF81F0FE0

    inc r10
    add r14, 8
    jmp .arm_arg_struct_loop

.arm_arg_eval_expr:
    push r10
    push rbx
    mov rdi, rbx
    call arm_emit_expr        ; x0 = arg val
    pop rbx
    pop r10

    ; str x0, [sp, #-16]! -> 0xF81F0FE0
    EMIT_ARM 0xF81F0FE0

    inc r10

.arm_arg_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .arm_arg_loop

.pop_arm_args:
    test r10, r10
    jz .do_arm_user_call

    dec r10
.pop_arm_loop:
    cmp r10, 0
    je .pop_x0
    cmp r10, 1
    je .pop_x1
    cmp r10, 2
    je .pop_x2
    jmp .pop_arm_next

.pop_x0:
    ; ldr x0, [sp], #16 -> 0xF84107E0
    EMIT_ARM 0xF84107E0
    jmp .pop_arm_next

.pop_x1:
    ; ldr x1, [sp], #16 -> 0xF84107E1
    EMIT_ARM 0xF84107E1
    jmp .pop_arm_next

.pop_x2:
    ; ldr x2, [sp], #16 -> 0xF84107E2
    EMIT_ARM 0xF84107E2

.pop_arm_next:
    test r10, r10
    jz .do_arm_user_call
    dec r10
    jmp .pop_arm_loop

.do_arm_user_call:
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_fn_symbol
    cmp rax, -1
    jne .has_arm_fn_target
    mov rax, [armstate + ArmState.fn_main_off]

.has_arm_fn_target:
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret


arm_emit_asm_lines:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; stmt list
    mov r13, [armstate + ArmState.code_buf]

.line_loop:
    test r12, r12
    jz .done

    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, r13
    call arm_encode_asm_line

    mov r12, [r12 + ASTNode.next]
    jmp .line_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


arm_encode_asm_line:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; str
    mov r14, rsi             ; len
    mov r13, rdx             ; CodeBuf

.trim_loop:
    test r14, r14
    jz .done_line
    mov al, [r12]
    cmp al, ' '
    jne .check_mnem
    inc r12
    dec r14
    jmp .trim_loop

.check_mnem:
    ; svc #0 -> 0xD4000001
    mov rdi, r12
    mov rsi, s_svc
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_ret

    EMIT_ARM 0xD4000001
    jmp .done_line

.chk_ret:
    mov rdi, r12
    mov rsi, s_ret_arm
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_mov

    EMIT_ARM 0xD65F03C0
    jmp .done_line

.chk_mov:
    mov rdi, r12
    mov rsi, s_mov_arm
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .arm_err

    ; mov x0, #1 -> 0xD2800020
    ; mov x8, #93 -> 0xD2800BA8
    add r12, 3
    sub r14, 3

.trim_mov:
    cmp byte [r12], ' '
    jne .parsed_mov
    inc r12
    dec r14
    jmp .trim_mov

.parsed_mov:
    mov al, [r12 + 1]
    cmp al, '0'
    je .mov_x0
    cmp al, '8'
    je .mov_x8
    jmp .arm_err

.mov_x0:
    ; mov x0, imm (0xD2800000 | (imm << 5))
    add r12, 4
    sub r14, 4
    mov rdi, r12
    mov rcx, r14
    call parse_dec_int
    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800000
    or eax, r8d
    EMIT_ARM eax
    jmp .done_line

.mov_x8:
    ; mov x8, imm (0xD2800008 | (imm << 5))
    add r12, 4
    sub r14, 4
    mov rdi, r12
    mov rcx, r14
    call parse_dec_int
    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800008
    or eax, r8d
    EMIT_ARM eax
    jmp .done_line

.done_line:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.arm_err:
    mov rsi, err_unsupported_arm_asm
    call print_err
    mov rdi, 1
    call sys_exit
