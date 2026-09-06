; src/codegen/arm_emit.asm - ARM64 Machine Code Emitter for CAP v0.1
default rel

%include "src/ast.inc"
%include "src/codegen/target.inc"

section .data
err_unsupported_arm_asm: db "Error: asm block contains unsupported ARM instruction. Supported instructions: mov, add, sub, svc, ret", 10, 0
s_main_arm:              db "main", 0
s_print_arm:             db "print", 0
s_svc:                   db "svc", 0
s_ret_arm:               db "ret", 0
s_mov_arm:               db "mov", 0

section .text
global arm_emit_program
extern emit_byte, emit_dword, emit_qword, emit_bytes, patch_dword
extern emit_arm_print_int, emit_arm_print_str
extern sym_init, add_symbol, find_symbol_offset
extern fn_sym_init, add_fn_symbol, find_fn_symbol
extern print_err, sys_exit, str_ncmp, parse_dec_int

struc ArmState
    .code_buf:     resq 1
    .print_int_off:resq 1
    .print_str_off:resq 1
    .fn_main_off:  resq 1
    .stack_offset: resq 1
endstruc

section .bss
armstate: resb ArmState_size

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

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; code_buf

    mov [armstate + ArmState.code_buf], r13
    call fn_sym_init

    ; 1. Emit _start at offset 0
    ; bl main (0x94000000 - placeholder rel26 = 0)
    EMIT_ARM 0x94000000

    ; mov x8, #93 (sys_exit = 93) -> 0xD2800BA8
    EMIT_ARM 0xD2800BA8

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

    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


arm_emit_fn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

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
    call str_ncmp
    test rax, rax
    jnz .not_main
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
    mov qword [armstate + ArmState.stack_offset], 16

    ; Process Parameters
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10
.param_loop:
    test rbx, rbx
    jz .body

    mov rcx, [armstate + ArmState.stack_offset]
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [armstate + ArmState.stack_offset], 16

    ; stur x[r10], [x29, #-rcx]
    ; 0xF80003A0 | (( -rcx & 0x1FF) << 12) | r10
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    or eax, r10d
    EMIT_ARM eax

    inc r10
    mov rbx, [rbx + ASTNode.next]
    jmp .param_loop

.body:
    ; Emit Function Body
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_stmt

    ; Epilogue:
    ; mov x0, #0
    EMIT_ARM 0xD2800000
    ; add sp, sp, #256 -> 0x910403FF
    EMIT_ARM 0x910403FF
    ; ldp x29, x30, [sp], #48 -> 0xA8C37BFD
    EMIT_ARM 0xA8C37BFD
    ; ret -> 0xD65F03C0
    EMIT_ARM 0xD65F03C0

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
    cmp rax, AST_ASM_BLOCK
    je .s_asm_block
    cmp rax, AST_EXPR_STMT
    je .s_expr_stmt
    jmp .next

.s_block:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_stmt
    jmp .next

.s_var_decl:
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
    push rax
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr
    pop rcx                  ; stack offset

    ; stur x0, [x29, #-off]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d
    EMIT_ARM eax
    jmp .next

.s_return:
    mov rdi, [r12 + ASTNode.child1]
    test rdi, rdi
    jz .ret_epilogue
    call arm_emit_expr

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
    jmp .next

.s_for:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    ; Bind loop var i
    mov rcx, [armstate + ArmState.stack_offset]
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    mov rdx, rcx
    call add_symbol
    add qword [armstate + ArmState.stack_offset], 16
    mov [rbp - 8], rcx       ; [rbp - 8] = i_off

    ; Allocate stop limit slot
    mov rcx, [armstate + ArmState.stack_offset]
    add qword [armstate + ArmState.stack_offset], 16
    mov [rbp - 16], rcx      ; [rbp - 16] = stop_off

    ; Evaluate range stop expression
    mov rdi, [r12 + ASTNode.child1]
    mov rdi, [rdi + ASTNode.child1]
    call arm_emit_expr       ; x0 = stop limit

    ; Store stop limit in [x29, #-stop_off]
    mov rcx, [rbp - 16]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003A0
    or eax, r8d              ; stur x0, [x29, #-stop_off]
    EMIT_ARM eax

    ; Initialize loop var = 0 -> stur xzr, [x29, #-i_off]
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF80003BF
    or eax, r8d              ; stur xzr, [x29, #-i_off]
    EMIT_ARM eax

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
    mov [rbp - 24], rax      ; fixup_off
    EMIT_ARM 0x5400000A

    ; Emit body
    push rbx
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_stmt
    pop rbx

    ; Increment loop var: ldur x0; add x0, x0, #1; stur x0
    mov rcx, [rbp - 8]
    mov rax, rcx
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax

    ; add x0, x0, #1 -> 0x91000400
    EMIT_ARM 0x91000400

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
    mov rcx, [rbp - 24]
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
    jmp .next

.s_loop:
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
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


arm_emit_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

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
    jmp .done

.e_literal:
    mov rdi, [r12 + ASTNode.val]
    mov rcx, [r12 + ASTNode.val_len]
    call parse_dec_int

    ; movz x0, #imm16 (0xD2800000 | (imm << 5))
    and eax, 0xFFFF
    shl eax, 5
    mov r8d, 0xD2800000
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.e_ident:
    mov rdi, [r12 + ASTNode.val]
    mov rsi, [r12 + ASTNode.val_len]
    call find_symbol_offset
    cmp rax, -1
    je .done

    ; ldur x0, [x29, #-off]
    neg rax
    and eax, 0x1FF
    shl eax, 12
    mov r8d, 0xF84003A0
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.e_bin_op:
    ; Left child
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr
    ; str x0, [sp, #-16]! -> 0xF81F0FE0
    EMIT_ARM 0xF81F0FE0

    ; Right child
    mov rdi, [r12 + ASTNode.child2]
    call arm_emit_expr

    ; ldr x1, [sp], #16 -> 0xF84107E1
    EMIT_ARM 0xF84107E1

    ; Op
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
    cmp cl, '='
    je .op_eq
    cmp cl, '<'
    je .op_lt
    cmp cl, '>'
    je .op_gt
    jmp .done

.op_add:
    ; add x0, x1, x0 -> 0x8B000020
    EMIT_ARM 0x8B000020
    jmp .done

.op_sub:
    ; sub x0, x1, x0 -> 0xCB000020
    EMIT_ARM 0xCB000020
    jmp .done

.op_mul:
    ; mul x0, x1, x0 -> 0x9B007C20
    EMIT_ARM 0x9B007C20
    jmp .done

.op_div:
    ; sdiv x0, x1, x0 -> 0x9AC00C20
    EMIT_ARM 0x9AC00C20
    jmp .done

.op_eq:
    ; cmp x1, x0 (0xEB00003F); cset x0, EQ (0x9A9F17E0)
    EMIT_ARM 0xEB00003F
    EMIT_ARM 0x9A9F17E0
    jmp .done

.op_lt:
    ; cmp x1, x0 (0xEB00003F); cset x0, LT (0x9A9FA7E0)
    EMIT_ARM 0xEB00003F
    EMIT_ARM 0x9A9FA7E0
    jmp .done

.op_gt:
    ; cmp x1, x0 (0xEB00003F); cset x0, GT (0x9A9FD7E0)
    EMIT_ARM 0xEB00003F
    EMIT_ARM 0x9A9FD7E0
    jmp .done

.e_un_op:
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr
    ; neg x0, x0 -> 0xCB0003E0
    EMIT_ARM 0xCB0003E0
    jmp .done

.e_call:
    ; Check print
    mov rdi, [r12 + ASTNode.val]
    mov rsi, s_print_arm
    mov rdx, [r12 + ASTNode.val_len]
    call str_ncmp
    test rax, rax
    jnz .user_call

    ; Call print(arg1)
    mov rdi, [r12 + ASTNode.child1]
    call arm_emit_expr        ; x0 = arg
    ; bl print_int
    mov rax, [armstate + ArmState.print_int_off]
    sub rax, [r13 + 16]
    sar rax, 2
    and eax, 0x03FFFFFF
    mov r8d, 0x94000000
    or eax, r8d
    EMIT_ARM eax
    jmp .done

.user_call:
    ; Evaluate multi-arg calls into x0, x1, x2...
    mov rbx, [r12 + ASTNode.child1]
    xor r10, r10             ; arg count
.arm_arg_loop:
    test rbx, rbx
    jz .pop_arm_args

    push r10
    push rbx
    mov rdi, rbx
    call arm_emit_expr        ; x0 = arg val
    pop rbx
    pop r10

    ; str x0, [sp, #-16]! -> 0xF81F0FE0
    EMIT_ARM 0xF81F0FE0

    inc r10
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
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


arm_emit_asm_lines:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

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
