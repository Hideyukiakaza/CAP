; src/codegen/codegen.asm - Code Generator Driver & Buffer Utilities for CAP v0.1
default rel

%include "src/ast.inc"
%include "src/codegen/target.inc"

struc CodeBuf
    .ptr:      resq 1
    .cap:      resq 1
    .len:      resq 1
endstruc

section .data
err_no_main: db "Error: main function not found", 10, 0
s_main_name: db "main", 0

err_name_undef_var_1: db "NameError: undefined name '", 0
err_name_undef_var_2: db "'", 10, 0

err_name_undef_fn_1: db "NameError: undefined function '", 0
err_name_undef_fn_2: db "'", 10, 0

err_type_not_struct_1: db "TypeError: cannot access field '", 0
err_type_not_struct_2: db "': '", 0
err_type_not_struct_3: db "' is not a struct", 0
err_type_not_struct_param_hint: db " (struct parameters need an annotation, e.g. p: Point)", 0
err_newline_cg: db 10, 0

err_type_no_such_field_1: db "TypeError: struct '", 0
err_type_no_such_field_2: db "' has no field '", 0
err_type_no_such_field_3: db "'", 10, 0

err_freestanding_prim_1: db "'", 0
err_freestanding_prim_2: db "' requires a hosted target; freestanding mode has no OS to call into — use asm: or raw pointer MMIO for hardware I/O", 10, 0

err_naked_return: db "Error: return not allowed in naked function", 10, 0
err_naked_var:    db "Error: variable declaration not allowed in naked function", 10, 0
err_naked_alloc:  db "Error: alloc not allowed in naked function", 10, 0
err_naked_defer:  db "Error: defer not allowed in naked function", 10, 0

s_builtin_print:    db "print", 0
s_builtin_input:    db "input", 0
s_builtin_alloc:    db "alloc", 0
s_builtin_free:     db "free", 0
s_builtin_range:    db "range", 0
s_builtin_fstring:  db "fstring", 0

section .text
global compile_program
global create_code_buf, emit_byte, emit_dword, emit_qword, emit_bytes, patch_dword
global find_symbol_offset, add_symbol, add_symbol_type, find_symbol_entry
global find_struct_decl, find_struct_field, resolve_field_access
global fn_sym_init, add_fn_symbol, find_fn_symbol

extern malloc_bytes, str_ncmp, str_len, print_err, print_err_bytes, sys_exit
extern write_elf64_binary
extern x86_emit_program, arm_emit_program

create_code_buf:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rdi, CodeBuf_size
    call malloc_bytes
    mov rbx, rax

    mov rdi, 1024 * 1024     ; 1 MB buffer
    call malloc_bytes
    mov [rbx + CodeBuf.ptr], rax
    mov qword [rbx + CodeBuf.cap], 1024 * 1024
    mov qword [rbx + CodeBuf.len], 0

    mov rax, rbx
    pop r12
    pop rbx
    pop rbp
    ret

emit_byte:
    push rbx
    mov rbx, [rdi + CodeBuf.ptr]
    add rbx, [rdi + CodeBuf.len]
    mov [rbx], sil
    inc qword [rdi + CodeBuf.len]
    pop rbx
    ret

emit_dword:
    push rbx
    mov rbx, [rdi + CodeBuf.ptr]
    add rbx, [rdi + CodeBuf.len]
    mov [rbx], esi
    add qword [rdi + CodeBuf.len], 4
    pop rbx
    ret

emit_qword:
    push rbx
    mov rbx, [rdi + CodeBuf.ptr]
    add rbx, [rdi + CodeBuf.len]
    mov [rbx], rsi
    add qword [rdi + CodeBuf.len], 8
    pop rbx
    ret

emit_bytes:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi             ; CodeBuf
    mov r12, rsi             ; src
    mov r13, rdx             ; len

.copy_loop:
    test r13, r13
    jz .done
    mov sil, [r12]
    mov rdi, rbx
    call emit_byte
    inc r12
    dec r13
    jmp .copy_loop

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

patch_dword:
    push rbx
    mov rbx, [rdi + CodeBuf.ptr]
    add rbx, rsi             ; offset
    mov [rbx], edx           ; new value
    pop rbx
    ret

compile_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; target_arch
    mov r14, rdx             ; output_filename
    mov [cg_target_arch], r13

    ; Check if main function exists in AST
    mov rbx, [r12 + ASTNode.child1]
.find_main_loop:
    test rbx, rbx
    jz .no_main_err

    cmp qword [rbx + ASTNode.type], AST_FN_DECL
    jne .next_stmt

    mov rdi, [rbx + ASTNode.val]
    mov rsi, s_main_name
    mov rdx, [rbx + ASTNode.val_len]
    call str_ncmp
    test rax, rax
    jz .found_main

.next_stmt:
    mov rbx, [rbx + ASTNode.next]
    jmp .find_main_loop

.found_main:
    ; Create CodeBuf
    call create_code_buf
    mov rbx, rax             ; rbx = CodeBuf

    ; Process Struct Declarations (compute size and field offsets)
    mov rdi, r12
    call process_struct_decls

    ; Perform Semantic Checks
    mov rdi, r12
    call semantic_check_program

    ; Dispatch to architecture emitter
    cmp r13, TARGET_ARM64
    je .do_arm
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    call x86_emit_program
    jmp .do_write

.do_arm:
    mov rdi, r12
    mov rsi, rbx
    call arm_emit_program

.do_write:
    ; write_elf64_binary(output_filename, target_arch, code_buf.ptr, code_buf.len)
    mov rdi, r14
    mov rsi, r13
    mov rdx, [rbx + CodeBuf.ptr]
    mov rcx, [rbx + CodeBuf.len]
    call write_elf64_binary

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.no_main_err:
    mov rsi, err_no_main
    call print_err
    mov rdi, 1
    call sys_exit


; Pre-pass for Struct Declarations
process_struct_decls:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r14, rdi                     ; ast_root
    mov rbx, [rdi + ASTNode.child1]
.s_loop:
    test rbx, rbx
    jz .s_done

    cmp qword [rbx + ASTNode.type], AST_STRUCT_DECL
    jne .s_next

    mov r12, [rbx + ASTNode.child1] ; field list
    xor r13, r13                     ; current offset = 0

.field_loop:
    test r12, r12
    jz .field_done

    mov [r12 + ASTNode.extra], r13  ; store offset in .extra

    mov rsi, [r12 + ASTNode.child1] ; field type name ptr
    mov rdx, [r12 + ASTNode.child2] ; field type name len
    test rsi, rsi
    jz .field_default_size

    mov rdi, r14                     ; ast_root
    call find_struct_decl
    test rax, rax
    jz .field_default_size

    mov r15, [rax + ASTNode.extra]  ; inner struct total size
    test r15, r15
    jz .field_default_size
    add r13, r15
    jmp .field_next

.field_default_size:
    add r13, 8                      ; 8 bytes per field

.field_next:
    mov r12, [r12 + ASTNode.next]
    jmp .field_loop

.field_done:
    mov [rbx + ASTNode.extra], r13  ; store struct size in .extra

.s_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .s_loop

.s_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; Semantic Check & Symbol Tables
section .bss
global sym_buf, fn_buf, cg_target_arch
sym_buf: resb 8192
sym_count: resq 1

fn_buf: resb 8192
fn_count: resq 1

local_sym_buf: resb 8192
local_sym_count: resq 1
cg_target_arch: resq 1
in_naked_fn: resq 1

section .text
global semantic_check_program

semantic_check_program:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r14, rdi             ; ast_root

    mov rbx, [r14 + ASTNode.child1]
.sem_fn_loop:
    test rbx, rbx
    jz .sem_done

    cmp qword [rbx + ASTNode.type], AST_FN_DECL
    jne .sem_fn_next

    mov rdi, r14
    mov rsi, rbx
    call semantic_check_fn

.sem_fn_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .sem_fn_loop

.sem_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

semantic_check_fn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; fn_decl node

    mov rax, [r13 + ASTNode.extra]
    mov [in_naked_fn], rax

    mov qword [local_sym_count], 0

    mov rbx, [r13 + ASTNode.child1]
.param_loop:
    test rbx, rbx
    jz .params_done

    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    mov rdx, 1               ; is_param = 1
    mov rcx, [rbx + ASTNode.child1] ; type_ptr
    mov r8,  [rbx + ASTNode.child2] ; type_len
    call add_local_symbol

    mov rbx, [rbx + ASTNode.next]
    jmp .param_loop

.params_done:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_stmts

    mov qword [in_naked_fn], 0

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

add_local_symbol:
    push rbx
    mov rbx, [local_sym_count]
    imul rbx, 40
    lea rax, [local_sym_buf + rbx]
    mov [rax], rdi
    mov [rax + 8], rsi
    mov [rax + 16], rdx
    mov [rax + 24], rcx
    mov [rax + 32], r8
    inc qword [local_sym_count]
    pop rbx
    ret

find_local_symbol:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi             ; search ptr
    mov r13, rsi             ; search len
    mov rbx, [local_sym_count]

.search_l_loop:
    test rbx, rbx
    jz .not_found_l
    dec rbx

    mov r14, rbx
    imul r14, 40
    lea rax, [local_sym_buf + r14]

    mov rdx, [rax + 8]
    cmp rdx, r13
    jne .search_l_loop

    mov rdi, r12
    mov rsi, [rax]
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jnz .search_l_loop

    mov r14, rbx
    imul r14, 40
    lea rax, [local_sym_buf + r14]
    jmp .done_l

.not_found_l:
    xor rax, rax

.done_l:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

semantic_check_stmts:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12, rdi
    mov rbx, rsi

.stmt_loop:
    test rbx, rbx
    jz .stmts_done

    mov rdi, r12
    mov rsi, rbx
    call semantic_check_stmt

    mov rbx, [rbx + ASTNode.next]
    jmp .stmt_loop

.stmts_done:
    pop r12
    pop rbx
    pop rbp
    ret

semantic_check_stmt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    test r13, r13
    jz .stmt_done

    mov rax, [r13 + ASTNode.type]

    cmp rax, AST_BLOCK
    je .s_block
    cmp rax, AST_VAR_DECL
    je .s_assign
    cmp rax, AST_FIELD_ASSIGN
    je .s_field_assign
    cmp rax, AST_IF
    je .s_if
    cmp rax, AST_ELIF
    je .s_if
    cmp rax, AST_ELSE
    je .s_else
    cmp rax, AST_FOR
    je .s_for
    cmp rax, AST_WHILE
    je .s_while
    cmp rax, AST_LOOP
    je .s_loop
    cmp rax, AST_DEFER
    je .s_defer
    cmp rax, AST_RETURN
    je .s_return
    cmp rax, AST_EXPR_STMT
    je .s_expr

    jmp .stmt_done

.s_block:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_stmts
    jmp .stmt_done

.s_assign:
    cmp qword [in_naked_fn], 1
    jne .do_assign_chk
    mov rsi, err_naked_var
    call print_err
    mov rdi, 1
    call sys_exit

.do_assign_chk:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr

    mov rdi, [r13 + ASTNode.val]
    mov rsi, [r13 + ASTNode.val_len]
    call find_local_symbol
    test rax, rax
    jnz .stmt_done

    mov rdi, [r13 + ASTNode.val]
    mov rsi, [r13 + ASTNode.val_len]
    mov rdx, 0
    xor rcx, rcx
    xor r8, r8

    mov rbx, [r13 + ASTNode.child1]
    test rbx, rbx
    jz .do_add_var
    cmp qword [rbx + ASTNode.type], AST_STRUCT_LIT
    jne .do_add_var

    mov rcx, [rbx + ASTNode.val]
    mov r8,  [rbx + ASTNode.val_len]

.do_add_var:
    call add_local_symbol
    jmp .stmt_done

.s_field_assign:
    cmp qword [in_naked_fn], 1
    jne .do_fassign_chk
    mov rsi, err_naked_var
    call print_err
    mov rdi, 1
    call sys_exit

.do_fassign_chk:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr

    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_expr
    jmp .stmt_done

.s_if:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr

    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_stmt

    mov rdi, r12
    mov rsi, [r13 + ASTNode.child3]
    call semantic_check_stmt
    jmp .stmt_done

.s_else:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_stmt
    jmp .stmt_done

.s_for:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr

    mov rdi, [r13 + ASTNode.val]
    mov rsi, [r13 + ASTNode.val_len]
    call find_local_symbol
    test rax, rax
    jnz .for_body

    mov rdi, [r13 + ASTNode.val]
    mov rsi, [r13 + ASTNode.val_len]
    mov rdx, 0
    xor rcx, rcx
    xor r8, r8
    call add_local_symbol

.for_body:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_stmt
    jmp .stmt_done

.s_while:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr

    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_stmt
    jmp .stmt_done

.s_loop:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_stmt
    jmp .stmt_done

.s_defer:
    cmp qword [in_naked_fn], 1
    jne .do_defer_chk
    mov rsi, err_naked_defer
    call print_err
    mov rdi, 1
    call sys_exit

.do_defer_chk:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_stmt
    jmp .stmt_done

.s_return:
    cmp qword [in_naked_fn], 1
    jne .do_ret_chk
    cmp qword [r13 + ASTNode.child1], 0
    je .do_ret_chk
    mov rsi, err_naked_return
    call print_err
    mov rdi, 1
    call sys_exit

.do_ret_chk:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr
    jmp .stmt_done

.s_expr:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr
    jmp .stmt_done

.stmt_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

semantic_check_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    test r13, r13
    jz .expr_done

    mov rax, [r13 + ASTNode.type]

    cmp rax, AST_IDENT
    je .e_ident
    cmp rax, AST_CALL
    je .e_call
    cmp rax, AST_FIELD_ACCESS
    je .e_field_access
    cmp rax, AST_STRUCT_LIT
    je .e_struct_lit
    cmp rax, AST_BIN_OP
    je .e_bin_op
    cmp rax, AST_UN_OP
    je .e_un_op
    cmp rax, AST_ALLOC
    je .e_alloc
    cmp rax, AST_INDEX
    je .e_index

    jmp .expr_done

.e_ident:
    mov rdi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call is_builtin_name
    test rax, rax
    jnz .expr_done

    mov rdi, r12
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call find_struct_decl
    test rax, rax
    jnz .expr_done

    mov rdi, [r13 + ASTNode.val]
    mov rsi, [r13 + ASTNode.val_len]
    call find_local_symbol
    test rax, rax
    jnz .expr_done

    mov rsi, err_name_undef_var_1
    call print_err
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_name_undef_var_2
    call print_err
    mov rdi, 1
    call sys_exit

.e_call:
    cmp qword [cg_target_arch], TARGET_FREESTANDING
    jne .chk_builtin

    mov rdi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call is_freestanding_restricted
    test rax, rax
    jz .chk_builtin

    mov rsi, err_freestanding_prim_1
    call print_err
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_freestanding_prim_2
    call print_err
    mov rdi, 1
    call sys_exit

.chk_builtin:
    mov rdi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call is_builtin_name
    test rax, rax
    jnz .check_args

    mov rdi, r12
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call find_fn_decl_in_ast
    test rax, rax
    jnz .check_args

    mov rsi, err_name_undef_fn_1
    call print_err
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_name_undef_fn_2
    call print_err
    mov rdi, 1
    call sys_exit

.check_args:
    mov rbx, [r13 + ASTNode.child1]
.arg_loop:
    test rbx, rbx
    jz .expr_done
    mov rdi, r12
    mov rsi, rbx
    call semantic_check_expr
    mov rbx, [rbx + ASTNode.next]
    jmp .arg_loop

.e_field_access:
    mov rbx, [r13 + ASTNode.child1]
    test rbx, rbx
    jz .expr_done

    mov rdi, r12
    mov rsi, rbx
    call semantic_check_expr

    cmp qword [rbx + ASTNode.type], AST_LITERAL
    je .err_base_is_literal

    cmp qword [rbx + ASTNode.type], AST_IDENT
    je .chk_ident_base

    jmp .expr_done

.chk_ident_base:
    mov rdi, [rbx + ASTNode.val]
    mov rsi, [rbx + ASTNode.val_len]
    call find_local_symbol
    test rax, rax
    jz .expr_done

    mov r14, rax
    cmp qword [r14 + 24], 0
    jne .check_field_in_struct

    mov rsi, err_type_not_struct_1
    call print_err
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_type_not_struct_2
    call print_err
    mov rsi, [rbx + ASTNode.val]
    mov rdx, [rbx + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_type_not_struct_3
    call print_err

    cmp qword [r14 + 16], 1
    jne .print_type_nl
    mov rsi, err_type_not_struct_param_hint
    call print_err

.print_type_nl:
    mov rsi, err_newline_cg
    call print_err
    mov rdi, 1
    call sys_exit

.check_field_in_struct:
    mov rdi, r12
    mov rsi, [r14 + 24]
    mov rdx, [r14 + 32]
    call find_struct_decl
    test rax, rax
    jz .expr_done

    mov rdi, rax
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call find_struct_field
    test rax, rax
    jnz .expr_done

    mov rsi, err_type_no_such_field_1
    call print_err
    mov rsi, [r14 + 24]
    mov rdx, [r14 + 32]
    call print_err_bytes
    mov rsi, err_type_no_such_field_2
    call print_err
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_type_no_such_field_3
    call print_err
    mov rdi, 1
    call sys_exit

.err_base_is_literal:
    mov rsi, err_type_not_struct_1
    call print_err
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_type_not_struct_2
    call print_err
    mov rsi, [rbx + ASTNode.val]
    mov rdx, [rbx + ASTNode.val_len]
    call print_err_bytes
    mov rsi, err_type_not_struct_3
    call print_err
    mov rsi, err_newline_cg
    call print_err
    mov rdi, 1
    call sys_exit

.e_struct_lit:
    mov rbx, [r13 + ASTNode.child1]
.s_init_loop:
    test rbx, rbx
    jz .expr_done
    mov rdi, r12
    mov rsi, [rbx + ASTNode.child1]
    call semantic_check_expr
    mov rbx, [rbx + ASTNode.next]
    jmp .s_init_loop

.e_bin_op:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_expr
    jmp .expr_done

.e_un_op:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr
    jmp .expr_done

.e_alloc:
    cmp qword [in_naked_fn], 1
    jne .do_alloc_chk
    mov rsi, err_naked_alloc
    call print_err
    mov rdi, 1
    call sys_exit

.do_alloc_chk:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr
    jmp .expr_done

.e_index:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call semantic_check_expr
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child2]
    call semantic_check_expr
    jmp .expr_done

.expr_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

is_freestanding_restricted:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rdx

    mov rsi, s_builtin_print
    call check_match
    test rax, rax
    jnz .r_yes

    mov rsi, s_builtin_input
    call check_match
    test rax, rax
    jnz .r_yes

    mov rsi, s_builtin_alloc
    call check_match
    test rax, rax
    jnz .r_yes

    xor rax, rax
    pop r12
    pop rbx
    ret

.r_yes:
    mov rax, 1
    pop r12
    pop rbx
    ret

is_builtin_name:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rdx

    mov rsi, s_builtin_print
    call check_match
    test rax, rax
    jnz .b_yes

    mov rsi, s_builtin_input
    call check_match
    test rax, rax
    jnz .b_yes

    mov rsi, s_builtin_alloc
    call check_match
    test rax, rax
    jnz .b_yes

    mov rsi, s_builtin_free
    call check_match
    test rax, rax
    jnz .b_yes

    mov rsi, s_builtin_range
    call check_match
    test rax, rax
    jnz .b_yes

    mov rsi, s_builtin_fstring
    call check_match
    test rax, rax
    jnz .b_yes

    xor rax, rax
    pop r12
    pop rbx
    ret

.b_yes:
    mov rax, 1
    pop r12
    pop rbx
    ret

check_match:
    mov rdi, rsi
    call str_len
    cmp rax, r12
    jne .no_m
    mov rdi, rbx
    mov rdx, r12
    call str_ncmp
    test rax, rax
    jz .m_yes
.no_m:
    xor rax, rax
    ret
.m_yes:
    mov rax, 1
    ret

find_fn_decl_in_ast:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rsi
    mov r13, rdx
    mov rbx, [rdi + ASTNode.child1]

.f_ast_loop:
    test rbx, rbx
    jz .f_ast_not_found

    cmp qword [rbx + ASTNode.type], AST_FN_DECL
    jne .f_ast_next

    mov rdx, [rbx + ASTNode.val_len]
    cmp rdx, r13
    jne .f_ast_next

    mov rdi, r12
    mov rsi, [rbx + ASTNode.val]
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jz .f_ast_found

.f_ast_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .f_ast_loop

.f_ast_found:
    mov rax, rbx
    jmp .f_ast_done

.f_ast_not_found:
    xor rax, rax

.f_ast_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

section .text
global sym_init
sym_init:
    mov qword [sym_count], 0
    ret

add_symbol:
    push rbx
    mov rbx, [sym_count]
    imul rbx, 40             ; 40 bytes per entry (5 qwords)
    lea rax, [sym_buf + rbx]
    mov [rax], rdi
    mov [rax + 8], rsi
    mov [rax + 16], rdx
    mov qword [rax + 24], 0
    mov qword [rax + 32], 0
    inc qword [sym_count]
    pop rbx
    ret

add_symbol_type:
    push rbx
    mov rbx, [sym_count]
    imul rbx, 40             ; 40 bytes per entry
    lea rax, [sym_buf + rbx]
    mov [rax], rdi
    mov [rax + 8], rsi
    mov [rax + 16], rdx
    mov [rax + 24], rcx
    mov [rax + 32], r8
    inc qword [sym_count]
    pop rbx
    ret

find_symbol_entry:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi             ; search ptr
    mov r13, rsi             ; search len
    mov rbx, [sym_count]

.search_loop:
    test rbx, rbx
    jz .not_found
    dec rbx

    mov r14, rbx
    imul r14, 40
    lea rax, [sym_buf + r14]

    mov rdx, [rax + 8]       ; entry len
    cmp rdx, r13
    jne .search_loop

    mov rdi, r12
    mov rsi, [rax]           ; entry ptr
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jnz .search_loop

    mov r14, rbx
    imul r14, 40
    lea rax, [sym_buf + r14]
    jmp .done

.not_found:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

find_symbol_offset:
    call find_symbol_entry
    test rax, rax
    jz .not_found
    mov rax, [rax + 16]
    ret
.not_found:
    mov rax, -1
    ret

find_struct_decl:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rsi             ; type_ptr
    mov r13, rdx             ; type_len
    mov rbx, [rdi + ASTNode.child1] ; ast_root statements

.s_loop:
    test rbx, rbx
    jz .s_not_found

    cmp qword [rbx + ASTNode.type], AST_STRUCT_DECL
    jne .s_next

    mov rdx, [rbx + ASTNode.val_len]
    cmp rdx, r13
    jne .s_next

    mov rdi, r12
    mov rsi, [rbx + ASTNode.val]
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jz .s_found

.s_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .s_loop

.s_found:
    mov rax, rbx
    jmp .s_done

.s_not_found:
    xor rax, rax

.s_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

find_struct_field:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rsi             ; field_ptr
    mov r13, rdx             ; field_len
    mov rbx, [rdi + ASTNode.child1] ; field_decl list

.f_loop:
    test rbx, rbx
    jz .f_not_found

    cmp qword [rbx + ASTNode.type], AST_FIELD_DECL
    jne .f_next

    mov rdx, [rbx + ASTNode.val_len]
    cmp rdx, r13
    jne .f_next

    mov rdi, r12
    mov rsi, [rbx + ASTNode.val]
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jz .f_found

.f_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .f_loop

.f_found:
    mov rax, rbx
    jmp .f_done

.f_not_found:
    xor rax, rax

.f_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

resolve_field_access:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; expr node (AST_FIELD_ACCESS or AST_IDENT)

    mov rax, [r13 + ASTNode.type]
    cmp rax, AST_IDENT
    je .res_ident
    cmp rax, AST_FIELD_ACCESS
    je .res_field_access

    mov rax, -1
    xor rdx, rdx
    xor rcx, rcx
    jmp .res_done

.res_ident:
    mov rdi, [r13 + ASTNode.val]
    mov rsi, [r13 + ASTNode.val_len]
    call find_symbol_entry
    test rax, rax
    jz .res_err

    mov rcx, [rax + 32]       ; type_len
    mov rdx, [rax + 24]       ; type_ptr
    mov rax, [rax + 16]       ; stack_offset
    jmp .res_done

.res_field_access:
    mov rdi, r12
    mov rsi, [r13 + ASTNode.child1]
    call resolve_field_access
    cmp rax, -1
    je .res_err

    mov r14, rax              ; accumulated offset
    mov r15, rdx              ; base type ptr
    mov r8, rcx               ; base type len

    test r15, r15
    jz .res_err

    mov rdi, r12
    mov rsi, r15
    mov rdx, r8
    call find_struct_decl
    test rax, rax
    jz .res_err

    mov rdi, rax
    mov rsi, [r13 + ASTNode.val]
    mov rdx, [r13 + ASTNode.val_len]
    call find_struct_field
    test rax, rax
    jz .res_err

    mov r8, [rax + ASTNode.extra]   ; field offset
    add r14, r8                     ; total combined offset
    mov rdx, [rax + ASTNode.child1] ; field type ptr
    mov rcx, [rax + ASTNode.child2] ; field type len
    mov rax, r14
    jmp .res_done

.res_err:
    mov rax, -1
    xor rdx, rdx
    xor rcx, rcx

.res_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


fn_sym_init:
    mov qword [fn_count], 0
    ret

add_fn_symbol:
    push rbx
    mov rbx, [fn_count]
    imul rbx, 24
    lea rax, [fn_buf + rbx]
    mov [rax], rdi
    mov [rax + 8], rsi
    mov [rax + 16], rdx
    inc qword [fn_count]
    pop rbx
    ret

find_fn_symbol:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov rbx, [fn_count]

.fn_search_loop:
    test rbx, rbx
    jz .fn_not_found
    dec rbx

    mov r14, rbx
    imul r14, 24
    lea rax, [fn_buf + r14]

    mov rdx, [rax + 8]
    cmp rdx, r13
    jne .fn_search_loop

    mov rdi, r12
    mov rsi, [rax]
    mov rdx, r13
    call str_ncmp
    test rax, rax
    jnz .fn_search_loop

    mov r14, rbx
    imul r14, 24
    lea rax, [fn_buf + r14]
    mov rax, [rax + 16]
    jmp .fn_done

.fn_not_found:
    mov rax, -1

.fn_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
