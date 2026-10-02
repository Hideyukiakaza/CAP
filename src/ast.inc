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

; src/ast.inc - AST Definitions for CAP v0.1

%define AST_PROGRAM      1
%define AST_IMPORT       2
%define AST_CONST        3
%define AST_VAR_DECL     4
%define AST_FN_DECL      5
%define AST_STRUCT_DECL  6
%define AST_FIELD_DECL   7
%define AST_DEFER        8
%define AST_RETURN       9
%define AST_BREAK        10
%define AST_IF           11
%define AST_ELIF         12
%define AST_ELSE         13
%define AST_FOR          14
%define AST_WHILE        15
%define AST_LOOP         16
%define AST_ASM_BLOCK    17
%define AST_EXPR_STMT    18
%define AST_BIN_OP       19
%define AST_UN_OP        20
%define AST_LITERAL      21
%define AST_IDENT        22
%define AST_ALLOC        23
%define AST_STRUCT_LIT   24
%define AST_FIELD_INIT   25
%define AST_CALL         26
%define AST_INDEX        27
%define AST_BLOCK        28
%define AST_PARAM        29
%define AST_FIELD_ACCESS 30
%define AST_FIELD_ASSIGN 31

struc ASTNode
    .type:   resq 1
    .val:    resq 1
    .val_len:resq 1
    .child1: resq 1
    .child2: resq 1
    .child3: resq 1
    .next:   resq 1
    .extra:  resq 1
    .line:   resq 1
endstruc
