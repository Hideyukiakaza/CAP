; src/parser.asm - Recursive Descent Parser for CAP v0.1 in NASM x86_64
default rel

%include "src/tokens.inc"
%include "src/ast.inc"

section .data
err_syntax: db "SyntaxError: Unexpected token", 10, 0
err_expected_colon: db "SyntaxError: Expected ':'", 10, 0
err_expected_indent: db "SyntaxError: Expected indented block", 10, 0
err_expected_ident: db "SyntaxError: Expected identifier after '.'", 10, 0
s_type_is: db "Token type: ", 0
s_line_is: db "Token line: ", 0
s_val_is: db "Token val: ", 0
s_prog_peek: db "Program peek token type: ", 0
s_fstring: db "fstring", 0

section .text
global parse_program
extern tokenize_source, lexer_next_token, lexer_peek_token, lexer_rewind, lookup_keyword
extern save_lexer_state, restore_lexer_state, malloc_bytes
extern create_ast_node, print_err, print_str, sys_exit, sys_write, print_char, print_num

parse_program:
    push rbx
    push r12
    push r13

    mov rdi, AST_PROGRAM
    call create_ast_node
    mov r12, rax

    xor r13, r13

.stmt_loop:
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_EOF
    je .done_program

    cmp rcx, TOKEN_NEWLINE
    je .skip_top_nl
    cmp rcx, TOKEN_INDENT
    je .skip_top_nl
    cmp rcx, TOKEN_DEDENT
    je .skip_top_nl
    jmp .not_nl

.skip_top_nl:
    call lexer_next_token
    jmp .stmt_loop

.not_nl:
    call parse_statement
    test rax, rax
    jz .stmt_loop

    test r13, r13
    jnz .append_stmt
    mov [r12 + ASTNode.child1], rax
    mov r13, rax
    jmp .stmt_loop

.append_stmt:
    mov [r13 + ASTNode.next], rax
    mov r13, rax
    jmp .stmt_loop

.done_program:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

parse_statement:
    push rbx
    push r12

    call lexer_peek_token
    mov rbx, rax
    mov rcx, [rbx + Token.type]

    cmp rcx, TOKEN_EOF
    je .no_stmt
    cmp rcx, TOKEN_INDENT
    je .no_stmt
    cmp rcx, TOKEN_DEDENT
    je .no_stmt
    cmp rcx, TOKEN_NEWLINE
    je .no_stmt

    cmp rcx, TOKEN_KEYWORD
    je .handle_kw

    call parse_var_assign_or_expr_stmt
    pop r12
    pop rbx
    ret

.no_stmt:
    xor rax, rax
    pop r12
    pop rbx
    ret

.handle_kw:
    mov rsi, [rbx + Token.val]
    mov rdx, [rbx + Token.len]
    call lookup_keyword
    mov rdx, rax

    cmp rdx, KW_IMPORT
    je .p_import
    cmp rdx, KW_CONST
    je .p_const
    cmp rdx, KW_RAW
    je .p_raw_var
    cmp rdx, KW_NAKED
    je .p_naked
    cmp rdx, KW_FN
    je .p_fn
    cmp rdx, KW_STRUCT
    je .p_struct
    cmp rdx, KW_DEFER
    je .p_defer
    cmp rdx, KW_RETURN
    je .p_return
    cmp rdx, KW_BREAK
    je .p_break
    cmp rdx, KW_IF
    je .p_if
    cmp rdx, KW_FOR
    je .p_for
    cmp rdx, KW_WHILE
    je .p_while
    cmp rdx, KW_LOOP
    je .p_loop
    cmp rdx, KW_ASM
    je .p_asm
    cmp rdx, KW_ELIF
    je .p_elif_else_top
    cmp rdx, KW_ELSE
    je .p_elif_else_top

    call parse_expr_stmt
    pop r12
    pop rbx
    ret

.p_elif_else_top:
    xor rax, rax
    pop r12
    pop rbx
    ret

.p_naked:
    call lexer_next_token
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_KEYWORD
    jne .p_naked_not_fn

    mov rsi, [rax + Token.val]
    mov rdx, [rax + Token.len]
    call lookup_keyword
    cmp rax, KW_FN
    jne .p_naked_not_fn

    call parse_fn_decl_stmt
    mov qword [rax + ASTNode.extra], 1
    pop r12
    pop rbx
    ret

.p_naked_not_fn:
    call lexer_rewind
    call parse_var_assign_or_expr_stmt
    pop r12
    pop rbx
    ret

.p_import:
    call parse_import_stmt
    pop r12
    pop rbx
    ret
.p_const:
    call parse_const_stmt
    pop r12
    pop rbx
    ret
.p_raw_var:
    call parse_raw_var_stmt
    pop r12
    pop rbx
    ret
.p_fn:
    call parse_fn_decl_stmt
    pop r12
    pop rbx
    ret
.p_struct:
    call parse_struct_decl_stmt
    pop r12
    pop rbx
    ret
.p_defer:
    call parse_defer_stmt
    pop r12
    pop rbx
    ret
.p_return:
    call parse_return_stmt
    pop r12
    pop rbx
    ret
.p_break:
    call parse_break_stmt
    pop r12
    pop rbx
    ret
.p_if:
    call parse_if_stmt
    pop r12
    pop rbx
    ret
.p_for:
    call parse_for_stmt
    pop r12
    pop rbx
    ret
.p_while:
    call parse_while_stmt
    pop r12
    pop rbx
    ret
.p_loop:
    call parse_loop_stmt
    pop r12
    pop rbx
    ret
.p_asm:
    call parse_asm_block_stmt
    pop r12
    pop rbx
    ret

parse_import_stmt:
    push rbx
    call lexer_next_token
    call lexer_next_token
    mov rbx, rax
    mov rdi, AST_IMPORT
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    push rax
    call consume_optional_newline
    pop rax
    pop rbx
    ret

parse_const_stmt:
    push rbx
    push r12
    call lexer_next_token
    call lexer_next_token
    mov rbx, rax
    call lexer_next_token
    call parse_expr
    mov r12, rax
    mov rdi, AST_CONST
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    push rax
    call consume_optional_newline
    pop rax
    pop r12
    pop rbx
    ret

parse_raw_var_stmt:
    push rbx
    push r12
    call lexer_next_token
    call lexer_next_token
    mov rbx, rax
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_COLON
    jne .no_type
    call lexer_next_token
    call lexer_next_token
.no_type:
    call lexer_next_token
    call parse_expr
    mov r12, rax
    mov rdi, AST_VAR_DECL
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    mov qword [rax + ASTNode.extra], 1
    push rax
    call consume_optional_newline
    pop rax
    pop r12
    pop rbx
    ret

parse_var_assign_or_expr_stmt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    call lexer_peek_token
    mov rbx, rax
    cmp qword [rbx + Token.type], TOKEN_IDENT
    jne .is_expr_stmt_fallback

    call lexer_next_token          ; consume IDENT
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_COLON
    je .handle_colon_decl

    call lexer_rewind              ; rewind to IDENT

.is_expr_stmt_fallback:
    call parse_expr
    mov rbx, rax                   ; rbx = lhs_expr

    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .make_expr_stmt

    mov rdx, [rax + Token.val]
    mov rcx, [rax + Token.len]
    cmp rcx, 1
    jne .make_expr_stmt
    cmp byte [rdx], '='
    jne .make_expr_stmt

    call lexer_next_token          ; consume '='
    call parse_expr
    mov r12, rax                   ; r12 = rhs_expr

    cmp qword [rbx + ASTNode.type], AST_FIELD_ACCESS
    je .make_field_assign

    mov rdi, AST_VAR_DECL
    call create_ast_node
    mov r13, rax
    mov rdx, [rbx + ASTNode.val]
    mov rcx, [rbx + ASTNode.val_len]
    mov [r13 + ASTNode.val], rdx
    mov [r13 + ASTNode.val_len], rcx
    mov [r13 + ASTNode.child1], r12 ; child1 = RHS
    jmp .done_assign_node

.make_field_assign:
    mov rdi, AST_FIELD_ASSIGN
    call create_ast_node
    mov r13, rax
    mov rdx, [rbx + ASTNode.val]
    mov rcx, [rbx + ASTNode.val_len]
    mov [r13 + ASTNode.val], rdx
    mov [r13 + ASTNode.val_len], rcx
    mov [r13 + ASTNode.child1], r12 ; child1 = RHS
    mov [r13 + ASTNode.child2], rbx ; child2 = LHS (FieldAccess)

.done_assign_node:
    push r13
    call consume_optional_newline
    pop rax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.make_expr_stmt:
    mov rdi, AST_EXPR_STMT
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    push rax
    call consume_optional_newline
    pop rax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.handle_colon_decl:
    call lexer_next_token          ; consume ':'
    call lexer_next_token          ; consume TYPE
    call lexer_next_token          ; consume '='
    call parse_expr
    mov r12, rax
    mov rdi, AST_VAR_DECL
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    push rax
    call consume_optional_newline
    pop rax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

parse_fn_decl_stmt:
    push rbx
    push r12
    push r13
    push r14
    call lexer_next_token
    call lexer_next_token
    mov rbx, rax
    call lexer_next_token

    xor r12, r12
    xor r13, r13
.param_loop:
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_RPAREN
    je .done_params
    cmp rcx, TOKEN_COMMA
    jne .parse_one_param
    call lexer_next_token
    jmp .param_loop

.parse_one_param:
    call lexer_next_token
    mov rdx, rax
    mov rdi, AST_PARAM
    call create_ast_node
    mov r14, rax
    mov r8, [rdx + Token.val]
    mov r9, [rdx + Token.len]
    mov [r14 + ASTNode.val], r8
    mov [r14 + ASTNode.val_len], r9

    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_COLON
    jne .no_param_type
    call lexer_next_token
    call lexer_next_token
    mov r8, [rax + Token.val]
    mov r9, [rax + Token.len]
    mov [r14 + ASTNode.child1], r8
    mov [r14 + ASTNode.child2], r9
.no_param_type:
    test r13, r13
    jnz .app_param
    mov r12, r14
    mov r13, r14
    jmp .param_loop
.app_param:
    mov [r13 + ASTNode.next], r14
    mov r13, r14
    jmp .param_loop

.done_params:
    call lexer_next_token
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov r13, rax

    mov rdi, AST_FN_DECL
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    mov [rax + ASTNode.child2], r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_struct_decl_stmt:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call lexer_next_token
    call lexer_next_token
    mov rbx, rax
    call lexer_next_token
    call consume_optional_newline

    call lexer_next_token
    xor r12, r12
    xor r13, r13

.field_loop:
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_DEDENT
    je .done_struct
    cmp rcx, TOKEN_NEWLINE
    jne .parse_field
    call lexer_next_token
    jmp .field_loop

.parse_field:
    call lexer_next_token
    mov r14, [rax + Token.val]
    mov r15, [rax + Token.len]
    call lexer_next_token
    call lexer_next_token
    mov r8, [rax + Token.val]
    mov r9, [rax + Token.len]

    mov rdi, AST_FIELD_DECL
    call create_ast_node
    mov [rax + ASTNode.val], r14
    mov [rax + ASTNode.val_len], r15
    mov [rax + ASTNode.child1], r8
    mov [rax + ASTNode.child2], r9

    test r13, r13
    jnz .app_field
    mov r12, rax
    mov r13, rax
    jmp .field_loop
.app_field:
    mov [r13 + ASTNode.next], rax
    mov r13, rax
    jmp .field_loop

.done_struct:
    call lexer_next_token
    mov rdi, AST_STRUCT_DECL
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    push rax
    call consume_optional_newline
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_defer_stmt:
    call lexer_next_token          ; consume 'defer'
    call parse_statement
    mov rbx, rax
    mov rdi, AST_DEFER
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    push rax
    call consume_optional_newline
    pop rax
    ret

parse_return_stmt:
    call lexer_next_token
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_NEWLINE
    je .ret_no_val
    cmp rcx, TOKEN_DEDENT
    je .ret_no_val
    cmp rcx, TOKEN_EOF
    je .ret_no_val

    call parse_expr
    mov rbx, rax
    jmp .create_ret
.ret_no_val:
    xor rbx, rbx
.create_ret:
    mov rdi, AST_RETURN
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    push rax
    call consume_optional_newline
    pop rax
    ret

parse_break_stmt:
    call lexer_next_token
    mov rdi, AST_BREAK
    call create_ast_node
    push rax
    call consume_optional_newline
    pop rax
    ret

parse_if_stmt:
    push rbx
    push r12
    push r13
    call lexer_next_token
    call parse_expr
    mov rbx, rax
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov r12, rax

    call parse_elif_or_else_branches
    mov r13, rax

    mov rdi, AST_IF
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov [rax + ASTNode.child3], r13
    pop r13
    pop r12
    pop rbx
    ret

parse_elif_or_else_branches:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_KEYWORD
    jne .no_branch
    mov rsi, [rax + Token.val]
    mov rdx, [rax + Token.len]
    call lookup_keyword
    mov rdx, rax
    cmp rdx, KW_ELIF
    je .p_elif
    cmp rdx, KW_ELSE
    je .p_else

.no_branch:
    xor rax, rax
    ret

.p_elif:
    push rbx
    push r12
    push r13
    call lexer_next_token
    call parse_expr
    mov rbx, rax
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov r12, rax
    call parse_elif_or_else_branches
    mov r13, rax

    mov rdi, AST_ELIF
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov [rax + ASTNode.child3], r13
    pop r13
    pop r12
    pop rbx
    ret

.p_else:
    push rbx
    call lexer_next_token
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov rbx, rax

    mov rdi, AST_ELSE
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    pop rbx
    ret

parse_for_stmt:
    push rbx
    push r12
    push r13
    call lexer_next_token
    call lexer_next_token
    mov rbx, rax
    call lexer_next_token
    call parse_expr
    mov r12, rax
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov r13, rax

    mov rdi, AST_FOR
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    mov [rax + ASTNode.child2], r13
    pop r13
    pop r12
    pop rbx
    ret

parse_while_stmt:
    push rbx
    push r12
    call lexer_next_token
    call parse_expr
    mov rbx, rax
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov r12, rax

    mov rdi, AST_WHILE
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    pop r12
    pop rbx
    ret

parse_loop_stmt:
    push rbx
    call lexer_next_token
    call lexer_next_token
    call consume_optional_newline
    call parse_block
    mov rbx, rax

    mov rdi, AST_LOOP
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    pop rbx
    ret

parse_asm_block_stmt:
    push rbx
    push r12
    push r13
    call lexer_next_token
    call lexer_next_token
    call consume_optional_newline

    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_INDENT
    jne .no_asm_indent
    call lexer_next_token
.no_asm_indent:

    xor r12, r12
    xor r13, r13
.asm_loop:
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_NEWLINE
    jne .check_asm_line
    call lexer_next_token
    jmp .asm_loop

.check_asm_line:
    cmp rcx, TOKEN_ASM_LINE
    jne .done_asm

    call lexer_next_token
    mov rbx, rax
    mov rdi, AST_EXPR_STMT
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx

    test r13, r13
    jnz .app_asm
    mov r12, rax
    mov r13, rax
    jmp .asm_loop
.app_asm:
    mov [r13 + ASTNode.next], rax
    mov r13, rax
    jmp .asm_loop

.done_asm:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_DEDENT
    jne .skip_asm_dedent
    call lexer_next_token
.skip_asm_dedent:
    mov rdi, AST_ASM_BLOCK
    call create_ast_node
    mov [rax + ASTNode.child1], r12
    pop r13
    pop r12
    pop rbx
    ret

parse_expr_stmt:
    push rbx
    call parse_expr
    mov rbx, rax
    mov rdi, AST_EXPR_STMT
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    push rax
    call consume_optional_newline
    pop rax
    pop rbx
    ret

parse_block:
    push rbx
    push r12
    push r13
    call lexer_next_token
    xor r12, r12
    xor r13, r13

.block_loop:
    call lexer_peek_token
    mov rcx, [rax + Token.type]
    cmp rcx, TOKEN_DEDENT
    je .done_block
    cmp rcx, TOKEN_EOF
    je .done_block
    cmp rcx, TOKEN_NEWLINE
    jne .parse_block_stmt
    call lexer_next_token
    jmp .block_loop

.parse_block_stmt:
    call parse_statement
    test rax, rax
    jz .done_block

    test r13, r13
    jnz .app_block_stmt
    mov r12, rax
    mov r13, rax
    jmp .block_loop
.app_block_stmt:
    mov [r13 + ASTNode.next], rax
    mov r13, rax
    jmp .block_loop

.done_block:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_DEDENT
    jne .skip_dedent_consume
    call lexer_next_token
.skip_dedent_consume:
    mov rdi, AST_BLOCK
    call create_ast_node
    mov [rax + ASTNode.child1], r12
    pop r13
    pop r12
    pop rbx
    ret

parse_expr:
    call parse_equality_expr
    ret

parse_equality_expr:
    push rbx
    push r12
    call parse_relational_expr
    mov rbx, rax

.eq_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .eq_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    mov ch, [rdx + 1]
    cmp cl, '='
    jne .chk_ne
    cmp ch, '='
    je .is_eq_op
.chk_ne:
    cmp cl, '!'
    jne .eq_done
    cmp ch, '='
    jne .eq_done

.is_eq_op:
    call lexer_next_token
    push rax
    call parse_relational_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .eq_loop

.eq_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_relational_expr:
    push rbx
    push r12
    call parse_bitwise_or_expr
    mov rbx, rax

.rel_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .rel_done
    mov rdx, [rax + Token.val]
    mov rcx, [rax + Token.len]
    cmp rcx, 1
    je .rel_1char
    cmp rcx, 2
    je .rel_2char
    jmp .rel_done

.rel_1char:
    mov cl, [rdx]
    cmp cl, '<'
    je .is_rel_op
    cmp cl, '>'
    je .is_rel_op
    jmp .rel_done

.rel_2char:
    mov cl, [rdx]
    mov ch, [rdx + 1]
    cmp ch, '='
    jne .rel_done
    cmp cl, '<'
    je .is_rel_op
    cmp cl, '>'
    je .is_rel_op
    jmp .rel_done

.is_rel_op:
    call lexer_next_token
    push rax
    call parse_bitwise_or_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .rel_loop

.rel_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_bitwise_or_expr:
    push rbx
    push r12
    call parse_bitwise_xor_expr
    mov rbx, rax

.bor_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .bor_done
    mov rcx, [rax + Token.len]
    cmp rcx, 1
    jne .bor_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    cmp cl, '|'
    jne .bor_done

.is_bor_op:
    call lexer_next_token
    push rax
    call parse_bitwise_xor_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .bor_loop

.bor_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_bitwise_xor_expr:
    push rbx
    push r12
    call parse_bitwise_and_expr
    mov rbx, rax

.bxor_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .bxor_done
    mov rcx, [rax + Token.len]
    cmp rcx, 1
    jne .bxor_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    cmp cl, '^'
    jne .bxor_done

.is_bxor_op:
    call lexer_next_token
    push rax
    call parse_bitwise_and_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .bxor_loop

.bxor_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_bitwise_and_expr:
    push rbx
    push r12
    call parse_shift_expr
    mov rbx, rax

.band_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .band_done
    mov rcx, [rax + Token.len]
    cmp rcx, 1
    jne .band_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    cmp cl, '&'
    jne .band_done

.is_band_op:
    call lexer_next_token
    push rax
    call parse_shift_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .band_loop

.band_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_shift_expr:
    push rbx
    push r12
    call parse_additive_expr
    mov rbx, rax

.sh_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .sh_done
    mov rcx, [rax + Token.len]
    cmp rcx, 2
    jne .sh_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    mov ch, [rdx + 1]
    cmp cl, '<'
    je .chk_shl
    cmp cl, '>'
    je .chk_shr
    jmp .sh_done

.chk_shl:
    cmp ch, '<'
    je .is_sh_op
    jmp .sh_done

.chk_shr:
    cmp ch, '>'
    je .is_sh_op
    jmp .sh_done

.is_sh_op:
    call lexer_next_token
    push rax
    call parse_additive_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .sh_loop

.sh_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_additive_expr:
    push rbx
    push r12
    call parse_multiplicative_expr
    mov rbx, rax

.add_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .add_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    cmp cl, '+'
    je .is_add_op
    cmp cl, '-'
    je .is_add_op
    jmp .add_done

.is_add_op:
    call lexer_next_token
    push rax
    call parse_multiplicative_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .add_loop

.add_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_multiplicative_expr:
    push rbx
    push r12
    call parse_unary_expr
    mov rbx, rax

.mul_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .mul_done
    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    cmp cl, '*'
    je .is_mul_op
    cmp cl, '/'
    je .is_mul_op
    cmp cl, '%'
    je .is_mul_op
    jmp .mul_done

.is_mul_op:
    call lexer_next_token
    push rax
    call parse_unary_expr
    mov r12, rax
    pop r8
    mov rdi, AST_BIN_OP
    call create_ast_node
    mov rdx, [r8 + Token.val]
    mov rcx, [r8 + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .mul_loop

.mul_done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

parse_unary_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_OP
    jne .not_unary

    mov rdx, [rax + Token.val]
    mov cl, [rdx]
    cmp cl, '-'
    je .is_un_op
    cmp cl, '&'
    je .is_un_op
    cmp cl, '~'
    je .is_un_op
    jmp .not_unary

.is_un_op:
    call lexer_next_token
    mov rbx, rax
    call parse_unary_expr
    mov r12, rax
    mov rdi, AST_UN_OP
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    pop r12
    pop rbx
    pop rbp
    ret

.not_unary:
    call parse_primary_expr
    pop r12
    pop rbx
    pop rbp
    ret

parse_primary_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    call lexer_peek_token
    mov rbx, rax
    mov rcx, [rbx + Token.type]

    cmp rcx, TOKEN_INT
    je .p_lit
    cmp rcx, TOKEN_FLOAT
    je .p_lit
    cmp rcx, TOKEN_STRING
    je .p_lit
    cmp rcx, TOKEN_KEYWORD
    je .p_kw
    cmp rcx, TOKEN_IDENT
    je .p_ident_or_call_or_struct
    cmp rcx, TOKEN_LPAREN
    je .p_paren

    push rbx
    mov rsi, err_syntax
    call print_err
    pop rbx
    mov rsi, s_type_is
    call print_str
    mov rdi, [rbx + Token.type]
    call print_num
    mov rdi, 10
    call print_char
    mov rsi, s_line_is
    call print_str
    mov rdi, [rbx + Token.line]
    call print_num
    mov rdi, 10
    call print_char
    mov rsi, s_val_is
    call print_str
    mov rsi, [rbx + Token.val]
    mov rdx, [rbx + Token.len]
    test rsi, rsi
    jz .err_out2
    test rdx, rdx
    jz .err_out2
    mov rdi, 1
    call sys_write
.err_out2:
    mov rdi, 10
    call print_char
    mov rdi, 1
    call sys_exit

.p_lit:
    call lexer_next_token
    mov rbx, rax
    mov rdi, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    test rdi, rdi
    jz .make_standard_lit
    cmp rcx, 3
    jl .make_standard_lit
    cmp byte [rdi], 'f'
    jne .make_standard_lit
    cmp byte [rdi + 1], '"'
    je .parse_fstr

.make_standard_lit:
    mov rdi, AST_LITERAL
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov rbx, rax
    jmp .postfix_loop

.parse_fstr:
    mov rdi, rbx
    call parse_fstring
    mov rbx, rax
    jmp .postfix_loop

.p_kw:
    mov rsi, [rbx + Token.val]
    mov rdx, [rbx + Token.len]
    call lookup_keyword
    mov rdx, rax
    cmp rdx, KW_ALLOC
    je .p_alloc
    cmp rdx, KW_RANGE
    je .p_range
    jmp .p_ident_or_call_or_struct

.p_alloc:
    call lexer_next_token          ; consume 'alloc'
    call lexer_next_token          ; consume '('
    call parse_expr
    mov r12, rax                   ; size expr
    call lexer_next_token          ; consume ')'

    mov rdi, AST_ALLOC
    call create_ast_node
    mov [rax + ASTNode.child1], r12
    mov rbx, rax
    jmp .postfix_loop

.p_range:
    call lexer_next_token
    call lexer_next_token
    call parse_expr
    mov rbx, rax
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_COMMA
    jne .one_arg_range
    call lexer_next_token
    call parse_expr
    mov r12, rax
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_COMMA
    jne .two_arg_range
    call lexer_next_token
    call parse_expr
    mov r13, rax
    call lexer_next_token
    jmp .build_range_call

.one_arg_range:
    call lexer_next_token
    xor r12, r12
    xor r13, r13
    jmp .build_range_call

.two_arg_range:
    call lexer_next_token
    xor r13, r13

.build_range_call:
    mov rdi, AST_CALL
    call create_ast_node
    mov qword [rax + ASTNode.val], range_str
    mov qword [rax + ASTNode.val_len], 5
    mov [rax + ASTNode.child1], rbx
    test r12, r12
    jz .range_done
    mov [rbx + ASTNode.next], r12
    test r13, r13
    jz .range_done
    mov [r12 + ASTNode.next], r13
.range_done:
    mov rbx, rax
    jmp .postfix_loop

.p_ident_or_call_or_struct:
    call lexer_next_token
    mov rbx, rax
    call lexer_peek_token
    mov rcx, [rax + Token.type]

    cmp rcx, TOKEN_LPAREN
    je .p_call
    cmp rcx, TOKEN_LBRACE
    je .p_struct_lit
    cmp rcx, TOKEN_LBRACKET
    je .p_index

    mov rdi, AST_IDENT
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov rbx, rax
    jmp .postfix_loop

.p_call:
    call lexer_next_token
    xor r12, r12
    xor r13, r13
.call_arg_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_RPAREN
    je .done_call_args
    cmp qword [rax + Token.type], TOKEN_COMMA
    jne .parse_arg
    call lexer_next_token
    jmp .call_arg_loop

.parse_arg:
    call parse_expr
    test r13, r13
    jnz .app_arg
    mov r12, rax
    mov r13, rax
    jmp .call_arg_loop
.app_arg:
    mov [r13 + ASTNode.next], rax
    mov r13, rax
    jmp .call_arg_loop

.done_call_args:
    call lexer_next_token
    mov rdi, AST_CALL
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    mov rbx, rax
    jmp .postfix_loop

.p_struct_lit:
    push r14
    push r15
    call lexer_next_token
    xor r12, r12
    xor r13, r13

.field_init_loop:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_RBRACE
    je .done_struct_fields
    cmp qword [rax + Token.type], TOKEN_COMMA
    jne .parse_field_init
    call lexer_next_token
    jmp .field_init_loop

.parse_field_init:
    call lexer_next_token
    mov r14, [rax + Token.val]
    mov r15, [rax + Token.len]
    call lexer_next_token
    call parse_expr
    push rax

    mov rdi, AST_FIELD_INIT
    call create_ast_node
    mov [rax + ASTNode.val], r14
    mov [rax + ASTNode.val_len], r15
    pop r9
    mov [rax + ASTNode.child1], r9

    test r13, r13
    jnz .app_finit
    mov r12, rax
    mov r13, rax
    jmp .field_init_loop
.app_finit:
    mov [r13 + ASTNode.next], rax
    mov r13, rax
    jmp .field_init_loop

.done_struct_fields:
    call lexer_next_token
    mov rdi, AST_STRUCT_LIT
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov [rax + ASTNode.child1], r12
    pop r15
    pop r14
    mov rbx, rax
    jmp .postfix_loop

.p_index:
    call lexer_next_token
    call parse_expr
    mov r12, rax
    call lexer_next_token

    mov rdi, AST_IDENT
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    mov rbx, rax

    mov rdi, AST_INDEX
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .postfix_loop

.p_paren:
    call lexer_next_token
    call parse_expr
    mov rbx, rax
    call lexer_next_token
    jmp .postfix_loop

.postfix_loop:
    call lexer_peek_token
    mov rcx, [rax + Token.type]

    cmp rcx, TOKEN_DOT
    je .postfix_dot
    cmp rcx, TOKEN_LBRACKET
    je .postfix_index

    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.postfix_dot:
    call lexer_next_token          ; consume '.'
    call lexer_peek_token          ; peek token after '.'
    cmp qword [rax + Token.type], TOKEN_IDENT
    jne .err_expected_ident

    call lexer_next_token          ; consume field ident token
    mov r12, [rax + Token.val]     ; IMMEDIATELY extract val
    mov r13, [rax + Token.len]     ; IMMEDIATELY extract len

    mov rdi, AST_FIELD_ACCESS
    call create_ast_node
    mov [rax + ASTNode.val], r12
    mov [rax + ASTNode.val_len], r13
    mov [rax + ASTNode.child1], rbx
    mov rbx, rax
    jmp .postfix_loop

.err_expected_ident:
    mov rsi, err_expected_ident
    call print_err
    mov rdi, 1
    call sys_exit

.postfix_index:
    call lexer_next_token          ; consume '['
    call parse_expr
    mov r12, rax
    call lexer_next_token          ; consume ']'

    mov rdi, AST_INDEX
    call create_ast_node
    mov [rax + ASTNode.child1], rbx
    mov [rax + ASTNode.child2], r12
    mov rbx, rax
    jmp .postfix_loop

parse_ident_as_expr:
    call lexer_next_token
    mov rbx, rax
    mov rdi, AST_IDENT
    call create_ast_node
    mov rdx, [rbx + Token.val]
    mov rcx, [rbx + Token.len]
    mov [rax + ASTNode.val], rdx
    mov [rax + ASTNode.val_len], rcx
    ret

consume_optional_newline:
    call lexer_peek_token
    cmp qword [rax + Token.type], TOKEN_NEWLINE
    jne .no_nl
    call lexer_next_token
.no_nl:
    ret

section .data
range_str: db "range", 0

section .text
create_unescaped_literal_node:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi             ; seg_start_ptr
    mov r13, rsi             ; seg_len

    mov rdi, r13
    inc rdi
    call malloc_bytes
    mov r14, rax             ; r14 = unescaped_buf

    xor r15, r15             ; src_i = 0
    xor rbx, rbx             ; dst_i = 0

.unescape_loop:
    cmp r15, r13
    jge .unescape_done

    mov al, [r12 + r15]
    cmp al, '{'
    jne .chk_close
    mov r8, r15
    inc r8
    cmp r8, r13
    jge .copy_char
    cmp byte [r12 + r8], '{'
    jne .copy_char
    mov byte [r14 + rbx], '{'
    inc rbx
    add r15, 2
    jmp .unescape_loop

.chk_close:
    cmp al, '}'
    jne .copy_char
    mov r8, r15
    inc r8
    cmp r8, r13
    jge .copy_char
    cmp byte [r12 + r8], '}'
    jne .copy_char
    mov byte [r14 + rbx], '}'
    inc rbx
    add r15, 2
    jmp .unescape_loop

.copy_char:
    mov [r14 + rbx], al
    inc rbx
    inc r15
    jmp .unescape_loop

.unescape_done:
    mov byte [r14 + rbx], 0

    mov rdi, AST_LITERAL
    call create_ast_node
    mov [rax + ASTNode.val], r14
    mov [rax + ASTNode.val_len], rbx

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


global parse_fstring
parse_fstring:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi             ; Token
    mov r12, [rbx + Token.val]
    mov r13, [rbx + Token.len]

    ; Skip f" (add 2) and trailing " (sub 3)
    add r12, 2
    sub r13, 3

    xor r14, r14             ; segment head
    xor r15, r15             ; segment tail
    xor rcx, rcx             ; curr idx
    mov r8, r12              ; seg start ptr

.fstr_scan:
    cmp rcx, r13
    jge .fstr_done_seg

    mov al, [r12 + rcx]
    cmp al, '{'
    je .fstr_open_brace
    cmp al, '}'
    je .fstr_close_brace
    inc rcx
    jmp .fstr_scan

.fstr_open_brace:
    mov r9, rcx
    inc r9
    cmp r9, r13
    jge .do_open_brace
    cmp byte [r12 + r9], '{'
    jne .do_open_brace

    ; Escaped {{
    add rcx, 2
    jmp .fstr_scan

.do_open_brace:
    mov r9, r12
    add r9, rcx
    sub r9, r8
    jz .parse_expr_span

    push rcx
    push r8
    mov rdi, r8
    mov rsi, r9
    call create_unescaped_literal_node
    pop r8
    pop rcx

    test r15, r15
    jnz .app_lit_seg
    mov r14, rax
    mov r15, rax
    jmp .parse_expr_span
.app_lit_seg:
    mov [r15 + ASTNode.next], rax
    mov r15, rax

.parse_expr_span:
    inc rcx                  ; skip '{'
    mov r8, r12
    add r8, rcx              ; expr_start_ptr
    xor r9, r9               ; expr_len = 0
    mov r10, 1               ; brace_depth = 1

.scan_close:
    cmp rcx, r13
    jge .finish_expr_span
    mov al, [r12 + rcx]
    cmp al, '{'
    jne .chk_rbrace
    inc r10
    jmp .inc_expr
.chk_rbrace:
    cmp al, '}'
    jne .inc_expr
    dec r10
    jz .finish_expr_span

.inc_expr:
    inc rcx
    inc r9
    jmp .scan_close

.finish_expr_span:
    cmp rcx, r13
    jge .done_expr_parse
    inc rcx                  ; skip '}'

.done_expr_parse:
    push rcx
    push r8
    push r9
    mov rdi, r8
    mov rsi, r9
    call parse_span_expr
    pop r9
    pop r8
    pop rcx

    test r15, r15
    jnz .app_expr_seg
    mov r14, rax
    mov r15, rax
    jmp .reset_seg_start
.app_expr_seg:
    mov [r15 + ASTNode.next], rax
    mov r15, rax

.reset_seg_start:
    mov r8, r12
    add r8, rcx
    jmp .fstr_scan

.fstr_close_brace:
    mov r9, rcx
    inc r9
    cmp r9, r13
    jge .next_c_brace
    cmp byte [r12 + r9], '}'
    jne .next_c_brace
    inc rcx
.next_c_brace:
    inc rcx
    jmp .fstr_scan

.fstr_done_seg:
    mov r9, r12
    add r9, r13
    sub r9, r8
    jz .build_fstr_node

    push r8
    push r9
    mov rdi, r8
    mov rsi, r9
    call create_unescaped_literal_node
    pop r9
    pop r8

    test r15, r15
    jnz .app_tail_seg
    mov r14, rax
    mov r15, rax
    jmp .build_fstr_node
.app_tail_seg:
    mov [r15 + ASTNode.next], rax
    mov r15, rax

.build_fstr_node:
    mov rdi, AST_CALL
    call create_ast_node
    mov qword [rax + ASTNode.val], s_fstring
    mov qword [rax + ASTNode.val_len], 7
    mov [rax + ASTNode.child1], r14

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


parse_span_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 600

    mov r12, rdi             ; span_ptr
    mov r13, rsi             ; span_len

    mov rdi, r13
    inc rdi
    call malloc_bytes
    mov rbx, rax

    xor rcx, rcx
.copy_span:
    cmp rcx, r13
    jge .span_copied
    mov al, [r12 + rcx]
    mov [rbx + rcx], al
    inc rcx
    jmp .copy_span
.span_copied:
    mov byte [rbx + r13], 0

    mov rdi, rsp
    call save_lexer_state

    mov rdi, rbx
    call tokenize_source

    call parse_expr
    mov r12, rax

    mov rdi, rsp
    call restore_lexer_state

    mov rax, r12
    add rsp, 600
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
