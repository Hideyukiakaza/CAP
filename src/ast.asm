; Copyright 2026 Hideyukiakaza
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

; src/ast.asm - AST Node allocation and formatting/printing for CAP v0.1
default rel

%include "src/tokens.inc"
%include "src/ast.inc"

section .data
s_Program:     db "Program", 10, 0
s_Import:      db "Import ", 0
s_Const:       db "ConstDecl ", 0
s_VarDecl:     db "VarDecl ", 0
s_RawVarDecl:  db "RawVarDecl ", 0
s_FnDecl:      db "FnDecl ", 0
s_Param:       db "Param ", 0
s_StructDecl:  db "StructDecl ", 0
s_FieldDecl:   db "FieldDecl ", 0
s_Defer:       db "Defer", 10, 0
s_Return:      db "Return", 10, 0
s_Break:       db "Break", 10, 0
s_If:          db "If", 10, 0
s_Elif:        db "Elif", 10, 0
s_Else:        db "Else", 10, 0
s_For:         db "For ", 0
s_While:       db "While", 10, 0
s_Loop:        db "Loop", 10, 0
s_AsmBlock:    db "AsmBlock", 10, 0
s_ExprStmt:    db "ExprStmt", 10, 0
s_BinOp:       db "BinOp ", 0
s_UnOp:        db "UnOp ", 0
s_Literal:     db "Literal ", 0
s_Ident:       db "Ident ", 0
s_Alloc:       db "Alloc ", 0
s_StructLit:   db "StructLit ", 0
s_FieldInit:   db "FieldInit ", 0
s_Call:        db "Call ", 0
s_Index:       db "Index", 10, 0
s_Block:       db "Block", 10, 0
s_FieldAccess: db "FieldAccess ", 0
s_FieldAssign: db "FieldAssign ", 0

s_spaces:      db "  ", 0
s_newline:     db 10, 0

section .text
global create_ast_node, dump_ast
extern malloc_bytes, print_str, sys_write, line_num, lexer_peek_token

create_ast_node:
    push rbx
    push r12
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov r12, rdi

    mov rdi, ASTNode_size
    call malloc_bytes
    mov rbx, rax

    mov [rbx + ASTNode.type], r12
    mov qword [rbx + ASTNode.val], 0
    mov qword [rbx + ASTNode.val_len], 0
    mov qword [rbx + ASTNode.child1], 0
    mov qword [rbx + ASTNode.child2], 0
    mov qword [rbx + ASTNode.child3], 0
    mov qword [rbx + ASTNode.next], 0
    mov qword [rbx + ASTNode.extra], 0
    mov qword [rbx + ASTNode.line], 0

    call lexer_peek_token
    test rax, rax
    jz .no_tok
    mov rcx, [rax + Token.line]
    mov [rbx + ASTNode.line], rcx

.no_tok:
    mov rax, rbx
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop r12
    pop rbx
    ret

dump_ast:
    xor rsi, rsi
    call print_ast_node
    ret

print_ast_node:
    test rdi, rdi
    jz .done

    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi

.list_loop:
    test rbx, rbx
    jz .pop_done

    mov r13, r12
.indent_loop:
    test r13, r13
    jz .print_node_content
    mov rsi, s_spaces
    call print_str
    dec r13
    jmp .indent_loop

.print_node_content:
    mov rax, [rbx + ASTNode.type]

    cmp rax, AST_PROGRAM
    je .p_program
    cmp rax, AST_IMPORT
    je .p_import
    cmp rax, AST_CONST
    je .p_const
    cmp rax, AST_VAR_DECL
    je .p_var_decl
    cmp rax, AST_FN_DECL
    je .p_fn_decl
    cmp rax, AST_PARAM
    je .p_param
    cmp rax, AST_STRUCT_DECL
    je .p_struct_decl
    cmp rax, AST_FIELD_DECL
    je .p_field_decl
    cmp rax, AST_DEFER
    je .p_defer
    cmp rax, AST_RETURN
    je .p_return
    cmp rax, AST_BREAK
    je .p_break
    cmp rax, AST_IF
    je .p_if
    cmp rax, AST_ELIF
    je .p_elif
    cmp rax, AST_ELSE
    je .p_else
    cmp rax, AST_FOR
    je .p_for
    cmp rax, AST_WHILE
    je .p_while
    cmp rax, AST_LOOP
    je .p_loop
    cmp rax, AST_ASM_BLOCK
    je .p_asm_block
    cmp rax, AST_EXPR_STMT
    je .p_expr_stmt
    cmp rax, AST_BIN_OP
    je .p_bin_op
    cmp rax, AST_UN_OP
    je .p_un_op
    cmp rax, AST_LITERAL
    je .p_literal
    cmp rax, AST_IDENT
    je .p_ident
    cmp rax, AST_ALLOC
    je .p_alloc
    cmp rax, AST_STRUCT_LIT
    je .p_struct_lit
    cmp rax, AST_FIELD_INIT
    je .p_field_init
    cmp rax, AST_CALL
    je .p_call
    cmp rax, AST_INDEX
    je .p_index
    cmp rax, AST_BLOCK
    je .p_block
    cmp rax, AST_FIELD_ACCESS
    je .p_field_access
    cmp rax, AST_FIELD_ASSIGN
    je .p_field_assign

    jmp .next_in_list

.p_program:
    mov rsi, s_Program
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .pop_done

.p_import:
    mov rsi, s_Import
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    jmp .next_in_list

.p_const:
    mov rsi, s_Const
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    push rbx
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    pop rbx
    mov rdi, [rbx + ASTNode.child2]
    test rdi, rdi
    jz .next_in_list
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_field_assign:
    mov rsi, s_FieldAssign
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    push rbx
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    pop rbx
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_var_decl:
    mov rax, [rbx + ASTNode.extra]
    test rax, rax
    jz .p_var_std
    mov rsi, s_RawVarDecl
    jmp .p_var_print
.p_var_std:
    mov rsi, s_VarDecl
.p_var_print:
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_fn_decl:
    mov rsi, s_FnDecl
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_param:
    mov rsi, s_Param
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    jmp .next_in_list

.p_struct_decl:
    mov rsi, s_StructDecl
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_field_decl:
    mov rsi, s_FieldDecl
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    jmp .next_in_list

.p_defer:
    mov rsi, s_Defer
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_return:
    mov rsi, s_Return
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_break:
    mov rsi, s_Break
    call print_str
    jmp .next_in_list

.p_if:
    mov rsi, s_If
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child3]
    mov rsi, r12
    call print_ast_node
    jmp .next_in_list

.p_elif:
    mov rsi, s_Elif
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child3]
    mov rsi, r12
    call print_ast_node
    jmp .next_in_list

.p_else:
    mov rsi, s_Else
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_for:
    mov rsi, s_For
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_while:
    mov rsi, s_While
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_loop:
    mov rsi, s_Loop
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_asm_block:
    mov rsi, s_AsmBlock
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_expr_stmt:
    mov rsi, s_ExprStmt
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_bin_op:
    mov rsi, s_BinOp
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_un_op:
    mov rsi, s_UnOp
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_literal:
    mov rsi, s_Literal
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    jmp .next_in_list

.p_ident:
    mov rsi, s_Ident
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    jmp .next_in_list

.p_alloc:
    mov rsi, s_Alloc
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_struct_lit:
    mov rsi, s_StructLit
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_field_init:
    mov rsi, s_FieldInit
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_call:
    mov rsi, s_Call
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_index:
    mov rsi, s_Index
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    mov rdi, [rbx + ASTNode.child2]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.p_block:
    mov rsi, s_Block
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .pop_done

.p_field_access:
    mov rsi, s_FieldAccess
    call print_str
    call print_val_str
    mov rsi, s_newline
    call print_str
    mov rdi, [rbx + ASTNode.child1]
    mov rsi, r12
    inc rsi
    call print_ast_node
    jmp .next_in_list

.next_in_list:
    mov rbx, [rbx + ASTNode.next]
    jmp .list_loop

.pop_done:
    pop r14
    pop r13
    pop r12
    pop rbx
.done:
    ret

print_val_str:
    push rdi
    push rsi
    push rdx
    mov rsi, [rbx + ASTNode.val]
    mov rdx, [rbx + ASTNode.val_len]
    test rsi, rsi
    jz .str_done
    test rdx, rdx
    jz .str_done
    mov rdi, 1
    call sys_write
.str_done:
    pop rdx
    pop rsi
    pop rdi
    ret
