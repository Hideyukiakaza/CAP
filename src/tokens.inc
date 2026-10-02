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

; src/tokens.inc - Token Definitions for CAP v0.1 Frontend

%define TOKEN_EOF        0
%define TOKEN_NEWLINE    1
%define TOKEN_INDENT     2
%define TOKEN_DEDENT     3
%define TOKEN_IDENT      4
%define TOKEN_INT        5
%define TOKEN_FLOAT      6
%define TOKEN_STRING     7
%define TOKEN_KEYWORD    8
%define TOKEN_OP         9
%define TOKEN_COLON      10
%define TOKEN_COMMA      11
%define TOKEN_DOT        12
%define TOKEN_LPAREN     13
%define TOKEN_RPAREN     14
%define TOKEN_LBRACE     15
%define TOKEN_RBRACE     16
%define TOKEN_LBRACKET   17
%define TOKEN_RBRACKET   18
%define TOKEN_ASM_LINE   19

; Keyword Subtypes
%define KW_IF        1
%define KW_ELIF      2
%define KW_ELSE      3
%define KW_FOR       4
%define KW_IN        5
%define KW_WHILE     6
%define KW_LOOP      7
%define KW_BREAK     8
%define KW_FN        9
%define KW_RETURN    10
%define KW_STRUCT    11
%define KW_CONST     12
%define KW_RAW       13
%define KW_DEFER     14
%define KW_ALLOC     15
%define KW_FREE      16
%define KW_ASM       17
%define KW_IMPORT    18
%define KW_RANGE     19
%define KW_NAKED     20

struc Token
    .type: resq 1
    .val:  resq 1
    .len:  resq 1
    .line: resq 1
endstruc

struc LexerState
    .tokens:         resq 1
    .token_count:    resq 1
    .token_capacity: resq 1
    .token_idx:      resq 1
    .src_ptr:        resq 1
    .src_start:      resq 1
    .line_num:       resq 1
    .at_line_start:  resb 1
    .in_asm_block:   resb 1
    .pad:            resb 6
    .asm_indent:     resq 1
    .indent_sp:      resq 1
    .indent_stack:   resq 64
endstruc
