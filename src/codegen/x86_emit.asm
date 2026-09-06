; src/codegen/x86_emit.asm - x86-64 Machine Code Emitter for CAP v0.1
default rel

%include "src/ast.inc"
%include "src/codegen/target.inc"

section .data
err_unsupported_asm: db "Error: asm block contains unsupported instruction. Supported instructions: mov, add, sub, syscall, ret, push, pop", 10, 0
s_print:             db "print", 0
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
extern emit_x86_print_int, emit_x86_print_str
extern sym_init, add_symbol, find_symbol_offset
extern fn_sym_init, add_fn_symbol, find_fn_symbol
extern print_err, sys_exit, str_ncmp, parse_dec_int

struc X86State
    .code_buf:     resq 1
    .print_int_off:resq 1
    .print_str_off:resq 1
    .fn_main_off:  resq 1
    .stack_offset: resq 1
    .loop_start:   resq 1
    .loop_end:     resq 1
endstruc

section .bss
xstate: resb X86State_size

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
    call fn_sym_init

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
    mov rax, [r13 + 16]      ; current len
    mov [xstate + X86State.print_int_off], rax
    mov rdi, r13
    call emit_x86_print_int

    mov rax, [r13 + 16]
    mov [xstate + X86State.print_str_off], rax
    mov rdi, r13
    call emit_x86_print_str

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

    ; Allocate stack slot
    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [xstate + X86State.stack_offset], 8

    ; Move arg register to stack slot
    ; System V arg regs: rdi (0), rsi (1), rdx (2), rcx (3), r8 (4), r9 (5)
    ; mov [rbp - off], arg_reg
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
    mov rax, rcx
    neg rax
    mov sil, al
    call emit_byte

    inc r10
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
    call x86_emit_stmt
    jmp .next

.s_var_decl:
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
    add qword [xstate + X86State.stack_offset], 8
    mov rax, rcx

.var_has_slot:
    push rax                 ; stack offset
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    pop rcx                  ; stack offset

    ; mov [rbp - off], rax -> 48 89 85 <32-bit negative disp>
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
    jmp .next

.s_return:
    mov rdi, [r12 + ASTNode.child1]
    test rdi, rdi
    jz .ret_epilogue
    call x86_emit_expr

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
    xor rsi, rsi
    call emit_dword

    ; Patch jz rel32
    mov rax, [r13 + 16]
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
    xor rsi, rsi
    call emit_dword

    ; Emit body (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt

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
    push rbp
    mov rbp, rsp
    sub rsp, 32

    ; Bind loop var i
    mov rcx, [xstate + X86State.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 8], rcx       ; [rbp - 8] = i_off

    ; Allocate stop limit slot
    mov rcx, [xstate + X86State.stack_offset]
    add qword [xstate + X86State.stack_offset], 8
    mov [rbp - 16], rcx      ; [rbp - 16] = stop_off

    ; Evaluate stop expression
    mov rdi, [r12 + ASTNode.child1]
    mov rdi, [rdi + ASTNode.child1]
    call x86_emit_expr       ; rax = stop limit
    mov rcx, [rbp - 16]

    ; Store stop limit in [rbp - stop_off]
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

    ; Initialize loop var = 0
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
    call emit_dword          ; 0

    mov rbx, [r13 + 16]      ; loop_start

.for_head:
    ; Load loop var into rax: mov rax, [rbp - i_off]
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
    call emit_dword

    ; Load stop limit into rcx: mov rcx, [rbp - stop_off]
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
    call emit_dword

    ; cmp rax, rcx (48 39 C8)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x39
    call emit_byte
    mov sil, 0xC8
    call emit_byte

    ; jge for_end (0F 8D rel32)
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x8D
    call emit_byte
    mov rax, [r13 + 16]
    mov [rbp - 24], rax      ; jge fixup off
    xor rsi, rsi
    call emit_dword

    ; Emit body
    push rbx
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_stmt
    pop rbx

    ; Increment loop var: add qword [rbp - i_off], 1
    mov rcx, [rbp - 8]
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x83
    call emit_byte
    mov sil, 0x85
    call emit_byte
    mov rax, rcx
    neg rax
    mov esi, eax
    call emit_dword
    mov sil, 1
    call emit_byte

    ; jmp for_head
    mov sil, 0xE9
    call emit_byte
    mov rax, rbx
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword

    ; Patch jge rel32
    mov rax, [r13 + 16]
    mov rcx, [rbp - 24]
    sub rax, rcx
    sub rax, 4
    mov rdi, r13
    mov rsi, rcx
    mov rdx, rax
    call patch_dword

    mov rsp, rbp
    pop rbp
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
    cmp rax, AST_STRUCT_LIT
    je .e_struct_lit
    cmp rax, AST_INDEX
    je .e_index
    jmp .done

.e_literal:
    mov rdi, [r12 + ASTNode.val]
    mov rcx, [r12 + ASTNode.val_len]
    call parse_dec_int

    ; mov rax, imm64 (48 B8 <8 bytes>)
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0xB8
    call emit_byte
    mov rsi, rax
    call emit_qword
    jmp .done

.e_ident:
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_symbol_offset
    cmp rax, -1
    je .done

    ; mov rax, [rbp - off] (48 8B 85 <32-bit disp>)
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
    jmp .done

.e_bin_op:
    ; Left child (child1)
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    ; push rax (50)
    mov rdi, r13
    mov sil, 0x50
    call emit_byte

    ; Right child (child2)
    mov rdi, [r12 + ASTNode.child2]
    call x86_emit_expr

    ; pop rcx (59) -> rcx = left, rax = right
    mov rdi, r13
    mov sil, 0x59
    call emit_byte

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
    ; mov rbx, rax; mov rax, rcx; cqo; idiv rbx
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
    mov sil, 0x48
    call emit_byte
    mov sil, 0x99
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xF3
    call emit_byte
    jmp .done

.op_mod:
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
    mov sil, 0x48
    call emit_byte
    mov sil, 0x99
    call emit_byte
    mov sil, 0x48
    call emit_byte
    mov sil, 0xF7
    call emit_byte
    mov sil, 0xF3
    call emit_byte
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
    jnz .user_call

    ; Call print(arg1)
    mov rdi, [r12 + ASTNode.child1]
    call x86_emit_expr
    mov rdi, r13
    mov sil, 0x48
    call emit_byte
    mov sil, 0x89
    call emit_byte
    mov sil, 0xC7
    call emit_byte

    mov sil, 0xE8
    call emit_byte
    mov rax, [xstate + X86State.print_int_off]
    mov rcx, [r13 + 16]
    add rcx, 4
    sub rax, rcx
    mov esi, eax
    call emit_dword
    jmp .done

.user_call:
    ; Evaluate multi-arg calls: push evaluated args to stack, then pop into rdi, rsi, rdx, rcx, r8, r9
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10             ; arg count
.arg_eval_loop:
    test rbx, rbx
    jz .pop_args

    push r10
    push rbx
    mov rdi, rbx
    call x86_emit_expr        ; rax = arg val
    pop rbx
    pop r10

    ; push rax (50)
    mov rdi, r13
    mov sil, 0x50
    call emit_byte

    inc r10
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
    mov r13, rsi             ; len
    mov r14, rdx             ; CodeBuf

.trim_loop:
    test r13, r13
    jz .done_line
    mov al, [r12]
    cmp al, ' '
    jne .check_mnem
    inc r12
    dec r13
    jmp .trim_loop

.check_mnem:
    ; Check "syscall"
    mov rdi, r12
    mov rsi, s_syscall
    mov rdx, 7
    call str_ncmp
    test rax, rax
    jnz .chk_ret

    mov rdi, r14
    mov sil, 0x0F
    call emit_byte
    mov sil, 0x05
    call emit_byte
    jmp .done_line

.chk_ret:
    mov rdi, r12
    mov rsi, s_ret
    mov rdx, 3
    call str_ncmp
    test rax, rax
    jnz .chk_mov

    mov rdi, r14
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
    sub r13, 3

.trim_mov:
    cmp byte [r12], ' '
    jne .parsed_mov
    inc r12
    dec r13
    jmp .trim_mov

.parsed_mov:
    cmp byte [r12], 'r'
    jne .asm_err

    mov al, [r12 + 1]
    cmp al, 'a'
    je .mov_dest_rax
    cmp al, 'd'
    je .mov_dest_rdi

    jmp .asm_err

.mov_dest_rax:
    mov rdi, r14
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC0
    call emit_byte

    add r12, 4
    sub r13, 4
.trim_imm1:
    cmp byte [r12], ' '
    jne .parse_imm1
    inc r12
    dec r13
    jmp .trim_imm1
.parse_imm1:
    mov rdi, r12
    mov rcx, r13
    call parse_dec_int
    mov rdi, r14
    mov esi, eax
    call emit_dword
    jmp .done_line

.mov_dest_rdi:
    cmp byte [r12 + 5], 'r'
    je .mov_rdi_rax

    mov rdi, r14
    mov sil, 0x48
    call emit_byte
    mov sil, 0xC7
    call emit_byte
    mov sil, 0xC7
    call emit_byte

    add r12, 4
    sub r13, 4
.trim_imm2:
    cmp byte [r12], ' '
    jne .parse_imm2
    inc r12
    dec r13
    jmp .trim_imm2
.parse_imm2:
    mov rdi, r12
    mov rcx, r13
    call parse_dec_int
    mov rdi, r14
    mov esi, eax
    call emit_dword
    jmp .done_line

.mov_rdi_rax:
    mov rdi, r14
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

    mov rdi, r14
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

    mov rdi, r14
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

    mov rdi, r14
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

    mov rdi, r14
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
