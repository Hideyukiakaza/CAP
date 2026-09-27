; src/codegen/x86_emit.asm - x86-64 Machine Code Emitter for CAP v0.1
default rel

%include "src/ast.inc"
%include "src/codegen/target.inc"

section .data
err_unsupported_asm: db "Error: asm block contains unsupported instruction. Supported instructions: mov, add, sub, syscall, ret, push, pop, out, in", 10, 0
err_freestanding_print: db "'print' requires a hosted target; freestanding mode has no OS to call into — use asm: or raw pointer MMIO for hardware I/O", 10, 0
err_freestanding_input: db "'input' requires a hosted target; freestanding mode has no OS to call into — use asm: or raw pointer MMIO for hardware I/O", 10, 0
err_freestanding_alloc: db "'alloc' requires a hosted target; freestanding mode has no OS to call into — use asm: or raw pointer MMIO for hardware I/O", 10, 0
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
s_out:               db "out", 0
s_in:                db "in", 0
s_dx:                db "dx", 0
s_al:                db "al", 0
s_eax:               db "eax", 0

section .text
global x86_emit_program
extern emit_byte, emit_dword, emit_qword, emit_bytes, patch_dword
extern emit_x86_print_int, emit_x86_print_str, emit_x86_div_zero_trap, emit_x86_overflow_trap, emit_x86_alloc, emit_x86_input, emit_x86_type_mismatch_trap, emit_x86_format_int
extern sym_init, add_symbol, add_symbol_type, find_symbol_entry, find_symbol_offset
extern find_struct_decl, find_struct_field, resolve_field_access
extern fn_sym_init, add_fn_symbol, find_fn_symbol
extern print_err, sys_exit, str_ncmp, parse_dec_int, target_arch

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
    .is_curr_fn_main: resb 1
endstruc

section .bss
xstate: resb X86State_size
defer_nodes: resq 256
defer_count: resq 1
scope_defer_base: resq 64
scope_depth: resq 1

section .text

x86_emit_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; code_buf

    mov [xstate + X86State.code_buf], r13
    mov [xstate + X86State.ast_root], r12
    call fn_sym_init

    ; Check if freestanding mode
    cmp qword [target_arch], TARGET_FREESTANDING
    je .emit_freestanding_start

    ; 1. Emit _start sequence at offset 0
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
    ; NOTE: Emission order matches runtime_stubs.asm layout.
    ; Inter-stub call from _stub_x86_input to _stub_x86_alloc is dynamically
    ; back-patched below to prevent stub emission order dependencies.
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
    ; Offset +0x34 in _stub_x86_input is 'call rel32' (E8 <rel32>).
    ; rel32 = alloc_off - (input_off + 0x34 + 5)
    mov rax, [xstate + X86State.alloc_off]
    mov rcx, [xstate + X86State.input_off]
    add rcx, 0x39            ; input_off + 0x34 + 5
    sub rax, rcx             ; rel32
    mov rdi, r13             ; code_buf
    mov rsi, [xstate + X86State.input_off]
    add rsi, 0x35            ; patch offset
    mov rdx, rax             ; rel32
    call patch_dword

    jmp .emit_fns

.emit_freestanding_start:
    ; Freestanding mode _start:
    ; call main (E8 <rel32>) - placeholder rel32 at offset 1
    mov rdi, r13
    mov sil, 0xE8
    call emit_byte
    mov rdi, r13
    xor rsi, rsi
    call emit_dword          ; offset 1 is rel32 for main

    ; QEMU ACPI shutdown: mov dx, 0x604; mov ax, 0x2000; out dx, ax
    mov rdi, r13
    mov sil, 0x66
    call emit_byte
    mov sil, 0xBA
    call emit_byte
    mov sil, 0x04
    call emit_byte
    mov sil, 0x06
    call emit_byte

    mov sil, 0x66
    call emit_byte
    mov sil, 0xB8
    call emit_byte
    mov sil, 0x00
    call emit_byte
    mov sil, 0x20
    call emit_byte

    mov sil, 0x66
    call emit_byte
    mov sil, 0xEF
    call emit_byte

    ; Halt loop: cli; hlt; jmp -3 (FA F4 EB FD)
    mov sil, 0xFA            ; cli
    call emit_byte
    mov sil, 0xF4            ; hlt
    call emit_byte
    mov sil, 0xEB            ; jmp
    call emit_byte
    mov sil, 0xFD            ; -3 bytes
    call emit_byte

.emit_fns:
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
    ; Patch call main in _start (at file offset 1)
    mov rax, [xstate + X86State.fn_main_off]
    sub rax, 5               ; rel32 = target - (1 + 4)
    mov rdi, r13
    mov rsi, 1
    mov rdx, rax
    call patch_dword

    pop r13
    pop r12
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
    mov byte [xstate + X86State.is_curr_fn_main], 1
    jmp .is_main_done
.not_main:
    mov byte [xstate + X86State.is_curr_fn_main], 0
.is_main_done:

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
    add qword [xstate + X86State.stack_offset], 8

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

    inc r10

.param_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .param_loop

.body:
    ; Emit Function Body (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt

    cmp qword [target_arch], TARGET_FREESTANDING
    jne .body_std_epilogue
    cmp byte [xstate + X86State.is_curr_fn_main], 1
    jne .body_std_epilogue

    ; Freestanding main fall-through epilogue: cli; hlt; jmp -3 (FA F4 EB FD)
    mov rdi, r13
    mov sil, 0xFA            ; cli
    call emit_byte
    mov sil, 0xF4            ; hlt
    call emit_byte
    mov sil, 0xEB            ; jmp
    call emit_byte
    mov sil, 0xFD            ; -3 bytes
    call emit_byte
    jmp .fn_done

.body_std_epilogue:
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

.fn_done:
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
    sub rsp, 40              ; stack space for loop state: [rbp-32]=i_off, [rbp-40]=stop_off, [rbp-48]=step_off, [rbp-56]=pos_fixup, [rbp-64]=neg_fixup

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
    cmp qword [target_arch], TARGET_FREESTANDING
    jne .ret_std_epilogue
    cmp byte [xstate + X86State.is_curr_fn_main], 1
    jne .ret_std_epilogue

    ; Freestanding main return epilogue: cli; hlt; jmp -3 (FA F4 EB FD)
    mov rdi, r13
    mov sil, 0xFA            ; cli
    call emit_byte
    mov sil, 0xF4            ; hlt
    call emit_byte
    mov sil, 0xEB            ; jmp
    call emit_byte
    mov sil, 0xFD            ; -3 bytes
    call emit_byte
    jmp .next

.ret_std_epilogue:
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
    jmp .next

.s_for:
    ; Bind loop var i on function stack frame
    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 32], rcx      ; for_i_off

    ; Allocate stop limit slot
    mov rcx, [xstate + X86State.stack_offset]
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 40], rcx      ; for_stop_off

    ; Allocate step slot
    mov rcx, [xstate + X86State.stack_offset]
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 48], rcx      ; for_step_off

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
    mov rcx, [rbp - 40]
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
    mov rcx, [rbp - 32]
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
    mov rcx, [rbp - 48]
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
    mov rcx, [rbp - 32]
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
    mov rcx, [rbp - 40]
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
    mov rcx, [rbp - 48]
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
    mov rcx, [rbp - 48]
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
    mov rcx, [rbp - 48]
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
    mov rcx, [rbp - 32]
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

    mov rcx, [rbp - 40]
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
    mov [rbp - 56], rax      ; for_pos_fixup
    xor rsi, rsi
    call emit_dword

    ; jmp .for_body (E9 +23)
    mov sil, 0xE9
    call emit_byte
    mov esi, 23
    call emit_dword

    ; --- Negative Step Case: check i <= stop ---
    mov rcx, [rbp - 32]
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

    mov rcx, [rbp - 40]
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
    mov [rbp - 64], rax      ; for_neg_fixup
    xor rsi, rsi
    call emit_dword

.for_body:
    ; Emit body
    push rbx
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt
    pop rbx

    ; Increment loop var: i += step
    mov rcx, [rbp - 48]
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

    mov rcx, [rbp - 32]
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
    mov rcx, [rbp - 56]
    sub rax, rcx
    sub rax, 4
    mov rdi, r13
    mov rsi, rcx
    mov rdx, rax
    call patch_dword

    ; Patch jle (neg)
    mov rax, [r13 + 16]
    mov rcx, [rbp - 64]
    sub rax, rcx
    sub rax, 4
    mov rdi, r13
    mov rsi, rcx
    mov rdx, rax
    call patch_dword

    jmp .next

.s_loop:
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
    jmp .next

.s_break:
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
    add rsp, 40
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
    cmp qword [target_arch], TARGET_FREESTANDING
    je err_free_alloc
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

    ; Check if left tag (r8) == 3 or right tag (rdx) == 3
    mov sil, 0x49
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xF8
    call emit_byte
    mov sil, 0x03
    call emit_byte            ; cmp r8, 3
    mov sil, 0x74
    call emit_byte
    mov sil, 0x06
    call emit_byte            ; je +6 (trap)

    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0xFA
    call emit_byte
    mov sil, 0x03
    call emit_byte            ; cmp rdx, 3
    mov sil, 0x75
    call emit_byte
    mov sil, 0x05
    call emit_byte            ; jne +5 (skip)

    ; Trigger type_mismatch_trap
    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.type_mismatch_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; Check operator
    mov rbx, [r12 + ASTNode.val]
    mov cl, [rbx]

    cmp cl, '+'
    je .op_add
    cmp cl, '-'
    je .op_sub
    cmp cl, '*'
    je .op_mul
    cmp cl, '/'
    je .op_div
    cmp cl, '%'
    je .op_mod
    cmp cl, '='
    je .op_eq
    cmp cl, '!'
    je .op_ne
    cmp cl, '<'
    je .op_lt
    cmp cl, '>'
    je .op_gt
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

.op_mod:
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
    cmp cl, '&'
    jne .done
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
    cmp qword [target_arch], TARGET_FREESTANDING
    je err_free_input
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
    cmp qword [target_arch], TARGET_FREESTANDING
    je err_free_print
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


x86_encode_asm_line:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

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
    ; Check "out"
    mov rdi, r12
    mov rsi, s_out
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jz .do_out

    ; Check "in"
    mov rdi, r12
    mov rsi, s_in
    mov rdx, 2
    call str_ncmp
    test rax, rax
    jz .do_in

    ; Check "syscall"
    mov rdi, r12
    mov rsi, s_syscall
    mov rdx, 7
    call str_ncmp
    test rax, rax
    jnz .chk_ret

    mov rdi, r13
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x05
    call emit_byte
    jmp .done_line

.do_out:
    add r12, 3
    sub r14, 3
.trim_out:
    cmp byte [r12], ' '
    jne .check_out_src
    inc r12
    dec r14
    jmp .trim_out
.check_out_src:
    ; skip "dx", trim spaces/comma
    add r12, 2
    sub r14, 2
.trim_out_comma:
    mov al, [r12]
    cmp al, ' '
    je .inc_out_c
    cmp al, ','
    je .inc_out_c
    jmp .check_out_reg
.inc_out_c:
    inc r12
    dec r14
    jmp .trim_out_comma
.check_out_reg:
    cmp byte [r12], 'a'
    jne .asm_err
    cmp byte [r12 + 1], 'l'
    je .out_al
    cmp byte [r12 + 1], 'x'
    je .out_eax
    cmp byte [r12 + 1], 'e'
    je .chk_out_eax
    jmp .asm_err
.chk_out_eax:
    cmp byte [r12 + 2], 'x'
    je .out_eax
    jmp .asm_err
.out_al:
    mov rdi, r13
    mov sil, 0xEE
    call emit_byte
    jmp .done_line
.out_eax:
    mov rdi, r13
    mov sil, 0xEF
    call emit_byte
    jmp .done_line

.do_in:
    add r12, 2
    sub r14, 2
.trim_in:
    cmp byte [r12], ' '
    jne .check_in_dest
    inc r12
    dec r14
    jmp .trim_in
.check_in_dest:
    cmp byte [r12], 'a'
    jne .asm_err
    cmp byte [r12 + 1], 'l'
    je .in_al
    cmp byte [r12 + 1], 'e'
    je .in_eax
    jmp .asm_err
.in_al:
    mov rdi, r13
    mov sil, 0xEC
    call emit_byte
    jmp .done_line
.in_eax:
    mov rdi, r13
    mov sil, 0xED
    call emit_byte
    jmp .done_line

.chk_ret:
    mov rdi, r12
    mov rsi, s_ret
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_mov

    mov rdi, r13
    mov sil, 0xC3
    call emit_byte
    jmp .done_line

.chk_mov:
    mov rdi, r12
    mov rsi, s_mov
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_add

    add r12, 3
    sub r14, 3

.trim_mov:
    cmp byte [r12], ' '
    jne .parsed_mov
    inc r12
    dec r14
    jmp .trim_mov

.parsed_mov:
    cmp byte [r12], 'd'
    jne .chk_mov_al
    cmp byte [r12 + 1], 'x'
    je .mov_dest_dx
.chk_mov_al:
    cmp byte [r12], 'a'
    jne .chk_mov_r
    cmp byte [r12 + 1], 'l'
    je .mov_dest_al
.chk_mov_r:
    cmp byte [r12], 'r'
    jne .asm_err

    mov al, [r12 + 1]
    cmp al, 'a'
    je .mov_dest_rax
    cmp al, 'd'
    je .mov_dest_rdi

    jmp .asm_err

.mov_dest_dx:
    mov rdi, r13
    mov sil, 0x66
    call emit_byte
    mov sil, 0xBA
    call emit_byte

    add r12, 2
    sub r14, 2
.trim_dx_comma:
    mov al, [r12]
    cmp al, ' '
    je .inc_dx_c
    cmp al, ','
    je .inc_dx_c
    jmp .parse_dx_imm
.inc_dx_c:
    inc r12
    dec r14
    jmp .trim_dx_comma
.parse_dx_imm:
    mov rdi, r12
    mov rcx, r14
    call parse_dec_int
    push rax
    mov rdi, r13
    mov sil, al
    call emit_byte
    pop rax
    shr rax, 8
    mov rdi, r13
    mov sil, al
    call emit_byte
    jmp .done_line

.mov_dest_al:
    mov rdi, r13
    mov sil, 0xB0
    call emit_byte

    add r12, 2
    sub r14, 2
.trim_al_comma:
    mov al, [r12]
    cmp al, ' '
    je .inc_al_c
    cmp al, ','
    je .inc_al_c
    jmp .parse_al_imm
.inc_al_c:
    inc r12
    dec r14
    jmp .trim_al_comma
.parse_al_imm:
    mov rdi, r12
    mov rcx, r14
    call parse_dec_int
    mov rdi, r13
    mov sil, al
    call emit_byte
    jmp .done_line

.mov_dest_rax:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC0
    call emit_byte

    add r12, 4
    sub r14, 4
.trim_imm1:
    cmp byte [r12], ' '
    jne .parse_imm1
    inc r12
    dec r14
    jmp .trim_imm1
.parse_imm1:
    mov rdi, r12
    mov rcx, r14
    call parse_dec_int
    mov rdi, r13
    mov esi, eax
    call emit_dword
    jmp .done_line

.mov_dest_rdi:
    cmp byte [r12 + 5], 'r'
    je .mov_rdi_rax

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC7
    call emit_byte

    add r12, 4
    sub r14, 4
.trim_imm2:
    cmp byte [r12], ' '
    jne .parse_imm2
    inc r12
    dec r14
    jmp .trim_imm2
.parse_imm2:
    mov rdi, r12
    mov rcx, r14
    call parse_dec_int
    mov rdi, r13
    mov esi, eax
    call emit_dword
    jmp .done_line

.mov_rdi_rax:
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    jmp .done_line

.chk_add:
    mov rdi, r12
    mov rsi, s_add
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_sub

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x01
    call emit_byte
    mov sil, 0xD8
    call emit_byte
    jmp .done_line

.chk_sub:
    mov rdi, r12
    mov rsi, s_sub
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_push

    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x29
    call emit_byte
    mov sil, 0xD8
    call emit_byte
    jmp .done_line

.chk_push:
    mov rdi, r12
    mov rsi, s_push
    mov rdx, 4
    call str_ncmp
    test rax, rax
    jnz .chk_pop

    mov rdi, r13
    mov sil, 0x53
    call emit_byte
    jmp .done_line

.chk_pop:
    mov rdi, r12
    mov rsi, s_pop
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .asm_err

    mov rdi, r13
    mov sil, 0x5B
    call emit_byte
    jmp .done_line

.done_line:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.asm_err:
    mov rsi, err_unsupported_asm
    call print_err
    mov rdi, 1
    call sys_exit

err_free_print:
    mov rsi, err_freestanding_print
    call print_err
    mov rdi, 1
    call sys_exit

err_free_input:
    mov rsi, err_freestanding_input
    call print_err
    mov rdi, 1
    call sys_exit

err_free_alloc:
    mov rsi, err_freestanding_alloc
    call print_err
    mov rdi, 1
    call sys_exit
