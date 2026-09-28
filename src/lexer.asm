; src/lexer.asm - Lexer / Tokenizer for CAP v0.1 in NASM x86_64
default rel

%include "src/tokens.inc"

section .data
err_tab: db "SyntaxError: Tabs are not allowed for indentation", 10, 0
err_indent: db "SyntaxError: Indentation must be a multiple of 4 spaces", 10, 0
err_mismatch_indent: db "SyntaxError: Unindent does not match any outer indentation level", 10, 0
err_unexpected_char: db "LexerError: Unexpected character", 10, 0
err_unterm_string: db "LexerError: Unterminated string literal", 10, 0
err_lexer_malformed_num_1: db "LexerError: malformed numeric literal '", 0
err_lexer_malformed_num_2: db "' on line ", 0
err_newline: db 10, 0

kw_if:     db "if", 0
kw_elif:   db "elif", 0
kw_else:   db "else", 0
kw_for:    db "for", 0
kw_in:     db "in", 0
kw_while:  db "while", 0
kw_loop:   db "loop", 0
kw_break:  db "break", 0
kw_fn:     db "fn", 0
kw_return: db "return", 0
kw_struct: db "struct", 0
kw_const:  db "const", 0
kw_raw:    db "raw", 0
kw_defer:  db "defer", 0
kw_alloc:  db "alloc", 0
kw_free:   db "free", 0
kw_asm:    db "asm", 0
kw_import: db "import", 0
kw_range:  db "range", 0

section .bss
global lexer_tokens, lexer_token_count, lexer_token_idx
lexer_tokens:      resq 1
lexer_token_count: resq 1
lexer_token_capacity: resq 1
lexer_token_idx:   resq 1

src_ptr:      resq 1
src_start:    resq 1
line_num:     resq 1
at_line_start: resb 1
in_asm_block: resb 1
asm_indent_level: resq 1

indent_stack: resq 64
indent_sp:    resq 1

section .text
global tokenize_source, lexer_next_token, lexer_peek_token, lexer_rewind, dump_tokens_debug, lookup_keyword
global save_lexer_state, restore_lexer_state
extern malloc_bytes, print_err, print_err_bytes, print_err_num, print_str, print_char, print_num, sys_write, sys_exit, str_ncmp, str_cmp, str_len

save_lexer_state:
    mov rax, [lexer_tokens]
    mov [rdi + LexerState.tokens], rax
    mov rax, [lexer_token_count]
    mov [rdi + LexerState.token_count], rax
    mov rax, [lexer_token_capacity]
    mov [rdi + LexerState.token_capacity], rax
    mov rax, [lexer_token_idx]
    mov [rdi + LexerState.token_idx], rax
    mov rax, [src_ptr]
    mov [rdi + LexerState.src_ptr], rax
    mov rax, [src_start]
    mov [rdi + LexerState.src_start], rax
    mov rax, [line_num]
    mov [rdi + LexerState.line_num], rax
    mov al, [at_line_start]
    mov [rdi + LexerState.at_line_start], al
    mov al, [in_asm_block]
    mov [rdi + LexerState.in_asm_block], al
    mov rax, [asm_indent_level]
    mov [rdi + LexerState.asm_indent], rax
    mov rax, [indent_sp]
    mov [rdi + LexerState.indent_sp], rax

    lea rsi, [indent_stack]
    lea rdx, [rdi + LexerState.indent_stack]
    mov rcx, 64
.copy_ind:
    mov rax, [rsi]
    mov [rdx], rax
    add rsi, 8
    add rdx, 8
    loop .copy_ind
    ret

restore_lexer_state:
    mov rax, [rdi + LexerState.tokens]
    mov [lexer_tokens], rax
    mov rax, [rdi + LexerState.token_count]
    mov [lexer_token_count], rax
    mov rax, [rdi + LexerState.token_capacity]
    mov [lexer_token_capacity], rax
    mov rax, [rdi + LexerState.token_idx]
    mov [lexer_token_idx], rax
    mov rax, [rdi + LexerState.src_ptr]
    mov [src_ptr], rax
    mov rax, [rdi + LexerState.src_start]
    mov [src_start], rax
    mov rax, [rdi + LexerState.line_num]
    mov [line_num], rax
    mov al, [rdi + LexerState.at_line_start]
    mov [at_line_start], al
    mov al, [rdi + LexerState.in_asm_block]
    mov [in_asm_block], al
    mov rax, [rdi + LexerState.asm_indent]
    mov [asm_indent_level], rax
    mov rax, [rdi + LexerState.indent_sp]
    mov [indent_sp], rax

    lea rsi, [rdi + LexerState.indent_stack]
    lea rdx, [indent_stack]
    mov rcx, 64
.rest_ind:
    mov rax, [rsi]
    mov [rdx], rax
    add rsi, 8
    add rdx, 8
    loop .rest_ind
    ret

tokenize_source:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov [src_ptr], rdi
    mov [src_start], rdi
    mov qword [line_num], 1
    mov byte [at_line_start], 1
    mov byte [in_asm_block], 0

    mov qword [indent_stack], 0
    mov qword [indent_sp], 0

    mov rdi, 1024 * Token_size
    call malloc_bytes
    mov [lexer_tokens], rax
    mov qword [lexer_token_count], 0
    mov qword [lexer_token_capacity], 1024
    mov qword [lexer_token_idx], 0

.lex_loop:
    mov rsi, [src_ptr]
    mov al, [rsi]
    test al, al
    jz .lex_eof

    cmp byte [at_line_start], 1
    jne .not_asm_mode
    call handle_line_indentation

    cmp byte [in_asm_block], 1
    jne .not_asm_mode
    call try_lex_asm_line
    cmp rax, 1
    je .lex_loop

.not_asm_mode:
    mov rsi, [src_ptr]
    mov al, [rsi]
    test al, al
    jz .lex_eof

    cmp al, ' '
    je .skip_space

    cmp al, '/'
    jne .not_comment
    cmp byte [rsi + 1], '*'
    jne .not_comment
    cmp byte [rsi + 2], '/'
    jne .not_comment
    call handle_comment
    jmp .lex_loop

.not_comment:
    cmp al, 10
    je .handle_newline
    cmp al, 13
    je .skip_carriage_return

    cmp al, '0'
    jl .not_digit
    cmp al, '9'
    jle .lex_number
.not_digit:

    mov rsi, [src_ptr]
    mov al, [rsi]
    cmp al, 'f'
    jne .not_fstr
    cmp byte [rsi + 1], '"'
    je .lex_fstr_token

.not_fstr:
    call is_alpha
    test rax, rax
    jnz .lex_ident_or_kw

    mov rsi, [src_ptr]
    mov al, [rsi]

    cmp al, 'f'
    jne .chk_quote
    cmp byte [rsi + 1], '"'
    je .lex_fstr_token

.chk_quote:
    cmp al, '"'
    je .lex_string

    call lex_operator_or_punct
    test rax, rax
    jnz .lex_loop

    mov rsi, err_unexpected_char
    call print_err
    mov rsi, [src_ptr]
    mov dil, [rsi]
    call print_char
    mov dil, 10
    call print_char
    mov rdi, 1
    call sys_exit

.skip_space:
    inc qword [src_ptr]
    jmp .lex_loop

.skip_carriage_return:
    inc qword [src_ptr]
    jmp .lex_loop

.handle_newline:
    inc qword [src_ptr]
    mov byte [at_line_start], 1
    mov rdi, TOKEN_NEWLINE
    xor rsi, rsi
    xor rdx, rdx
    call emit_token
    inc qword [line_num]
    jmp .lex_loop

.lex_number:
    call lex_number_token
    jmp .lex_loop

.lex_ident_or_kw:
    call lex_ident_token
    jmp .lex_loop

.lex_fstr_token:
    call lex_fstring
    jmp .lex_loop

.lex_string:
    call lex_string_token
    jmp .lex_loop

.lex_eof:
    mov rcx, [indent_sp]
.unwind_loop:
    test rcx, rcx
    jz .emit_eof
    mov rdi, TOKEN_DEDENT
    xor rsi, rsi
    xor rdx, rdx
    call emit_token
    dec rcx
    jmp .unwind_loop

.emit_eof:
    mov qword [indent_sp], 0
    mov rdi, TOKEN_EOF
    xor rsi, rsi
    xor rdx, rdx
    call emit_token

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

handle_line_indentation:
    push rbx
    push r12
    mov rsi, [src_ptr]
    xor rbx, rbx

.count_space:
    mov al, [rsi + rbx]
    cmp al, 9
    je .err_tab_found
    cmp al, ' '
    jne .done_count
    inc rbx
    jmp .count_space

.err_tab_found:
    mov rsi, err_tab
    call print_err
    mov rdi, 1
    call sys_exit

.done_count:
    mov al, [rsi + rbx]
    cmp al, 10
    je .blank_line
    cmp al, 13
    je .blank_line
    cmp al, 0
    je .blank_line
    cmp al, '/'
    jne .check_indent_change
    cmp byte [rsi + rbx + 1], '*'
    jne .check_indent_change
    cmp byte [rsi + rbx + 2], '/'
    je .blank_line

.check_indent_change:
    add [src_ptr], rbx
    mov byte [at_line_start], 0

    mov r12, [indent_sp]
    mov rax, [indent_stack + r12 * 8]

    cmp rbx, rax
    je .indent_equal
    jg .indent_increase

.indent_decrease:
    cmp r12, 0
    jz .err_mismatch
    dec r12
    mov rax, [indent_stack + r12 * 8]
    mov rdi, TOKEN_DEDENT
    xor rsi, rsi
    xor rdx, rdx
    call emit_token
    mov [indent_sp], r12
    cmp rbx, rax
    je .indent_equal
    jl .indent_decrease

.err_mismatch:
    mov rsi, err_mismatch_indent
    call print_err
    mov rdi, 1
    call sys_exit

.indent_increase:
    mov rcx, rbx
    sub rcx, rax
    mov rdx, rcx
    and rdx, 3
    jnz .err_not_4

.push_indents:
    add rax, 4
    inc qword [indent_sp]
    mov r12, [indent_sp]
    mov [indent_stack + r12 * 8], rax
    mov rdi, TOKEN_INDENT
    xor rsi, rsi
    xor rdx, rdx
    call emit_token
    cmp rax, rbx
    jl .push_indents

.indent_equal:
    pop r12
    pop rbx
    ret

.err_not_4:
    mov rsi, err_indent
    call print_err
    mov rdi, 1
    call sys_exit

.blank_line:
    add [src_ptr], rbx
    pop r12
    pop rbx
    ret

handle_comment:
    add qword [src_ptr], 3
.comment_loop:
    mov rsi, [src_ptr]
    mov al, [rsi]
    test al, al
    jz .done_comment
    cmp al, 10
    je .done_comment
    cmp al, '/'
    jne .next_c
    cmp byte [rsi + 1], '*'
    jne .next_c
    cmp byte [rsi + 2], '/'
    jne .next_c
    add qword [src_ptr], 3
    ret
.next_c:
    inc qword [src_ptr]
    jmp .comment_loop
.done_comment:
    ret

try_lex_asm_line:
    push rbx
    push r12
    mov rsi, [src_ptr]
    mov al, [rsi]
    cmp al, 10
    je .not_asm
    cmp al, 13
    je .not_asm

    mov r12, [indent_sp]
    mov r12, [indent_stack + r12 * 8]
    mov rbx, [asm_indent_level]
    cmp r12, rbx
    jl .exit_asm_mode

    xor rcx, rcx
.find_eol:
    mov al, [rsi + rcx]
    test al, al
    jz .got_asm_line
    cmp al, 10
    je .got_asm_line
    inc rcx
    jmp .find_eol

.got_asm_line:
    mov rdi, TOKEN_ASM_LINE
    mov rsi, [src_ptr]
    mov rdx, rcx
    call emit_token

    add [src_ptr], rcx
    pop r12
    pop rbx
    mov rax, 1
    ret

.exit_asm_mode:
    mov byte [in_asm_block], 0
.not_asm:
    pop r12
    pop rbx
    xor rax, rax
    ret

is_dec_digit:
    cmp al, '0'
    jl .not_dec
    cmp al, '9'
    jg .not_dec
    mov rax, 1
    ret
.not_dec:
    xor rax, rax
    ret

is_hex_digit:
    cmp al, '0'
    jl .chk_hex_alpha
    cmp al, '9'
    jle .is_hex
.chk_hex_alpha:
    cmp al, 'a'
    jl .chk_hex_upper
    cmp al, 'f'
    jle .is_hex
.chk_hex_upper:
    cmp al, 'A'
    jl .not_hex
    cmp al, 'F'
    jle .is_hex
.not_hex:
    xor rax, rax
    ret
.is_hex:
    mov rax, 1
    ret

is_bin_digit:
    cmp al, '0'
    je .is_bin
    cmp al, '1'
    je .is_bin
    xor rax, rax
    ret
.is_bin:
    mov rax, 1
    ret

is_ident_char_or_dot:
    cmp al, '.'
    je .is_id
    cmp al, '_'
    je .is_id
    call is_alnum
    ret
.is_id:
    mov rax, 1
    ret

lex_number_token:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rsi, [src_ptr]
    mov al, [rsi]

    cmp al, '0'
    jne .parse_decimal

    mov bl, [rsi + 1]
    cmp bl, 'x'
    je .parse_hex
    cmp bl, 'X'
    je .parse_hex
    cmp bl, 'b'
    je .parse_binary
    cmp bl, 'B'
    je .parse_binary
    jmp .parse_decimal

.parse_hex:
    mov rcx, 2
    mov al, [rsi + rcx]
    call is_hex_digit
    test rax, rax
    jz .err_malformed

.hex_loop:
    mov al, [rsi + rcx]
    call is_hex_digit
    test rax, rax
    jnz .next_hex_char

    mov al, [rsi + rcx]
    cmp al, '_'
    jne .hex_done
    mov al, [rsi + rcx - 1]
    call is_hex_digit
    test rax, rax
    jz .err_malformed
    mov al, [rsi + rcx + 1]
    call is_hex_digit
    test rax, rax
    jz .err_malformed

.next_hex_char:
    inc rcx
    jmp .hex_loop

.hex_done:
    mov al, [rsi + rcx]
    call is_ident_char_or_dot
    test rax, rax
    jnz .err_malformed

    mov rdi, TOKEN_INT
    jmp .emit_num

.parse_binary:
    mov rcx, 2
    mov al, [rsi + rcx]
    call is_bin_digit
    test rax, rax
    jz .err_malformed

.bin_loop:
    mov al, [rsi + rcx]
    call is_bin_digit
    test rax, rax
    jnz .next_bin_char

    mov al, [rsi + rcx]
    cmp al, '_'
    jne .bin_done
    mov al, [rsi + rcx - 1]
    call is_bin_digit
    test rax, rax
    jz .err_malformed
    mov al, [rsi + rcx + 1]
    call is_bin_digit
    test rax, rax
    jz .err_malformed

.next_bin_char:
    inc rcx
    jmp .bin_loop

.bin_done:
    mov al, [rsi + rcx]
    call is_ident_char_or_dot
    test rax, rax
    jnz .err_malformed

    mov rdi, TOKEN_INT
    jmp .emit_num

.parse_decimal:
    xor rcx, rcx
    xor r12, r12

.dec_loop:
    mov al, [rsi + rcx]
    call is_dec_digit
    test rax, rax
    jnz .next_dec_char

    mov al, [rsi + rcx]
    cmp al, '_'
    jne .check_dec_dot
    test rcx, rcx
    jz .err_malformed
    mov al, [rsi + rcx - 1]
    call is_dec_digit
    test rax, rax
    jz .err_malformed
    mov al, [rsi + rcx + 1]
    call is_dec_digit
    test rax, rax
    jz .err_malformed
    jmp .next_dec_char

.check_dec_dot:
    cmp al, '.'
    jne .dec_done
    test r12, r12
    jnz .err_malformed
    mov bl, [rsi + rcx + 1]
    cmp bl, '0'
    jl .dec_done
    cmp bl, '9'
    jg .dec_done

    mov r12, 1
    test rcx, rcx
    jz .err_malformed
    mov al, [rsi + rcx - 1]
    cmp al, '_'
    je .err_malformed

.next_dec_char:
    inc rcx
    jmp .dec_loop

.dec_done:
    mov al, [rsi + rcx]
    call is_alpha
    test rax, rax
    jnz .err_malformed
    cmp al, '_'
    je .err_malformed

    test r12, r12
    jnz .is_float
    mov rdi, TOKEN_INT
    jmp .emit_num
.is_float:
    mov rdi, TOKEN_FLOAT

.emit_num:
    mov rsi, [src_ptr]
    mov rdx, rcx
    call emit_token
    add [src_ptr], rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err_malformed:
    mov rsi, [src_ptr]
.scan_bad_run:
    mov al, [rsi + rcx]
    call check_ident_or_dot
    test rax, rax
    jz .print_bad_err
    inc rcx
    jmp .scan_bad_run

.print_bad_err:
    push rcx
    mov rsi, err_lexer_malformed_num_1
    call print_err
    pop rdx
    mov rsi, [src_ptr]
    call print_err_bytes
    mov rsi, err_lexer_malformed_num_2
    call print_err
    mov rdi, [line_num]
    call print_err_num
    mov rsi, err_newline
    call print_err

    mov rdi, 1
    call sys_exit

check_ident_or_dot:
    cmp al, '.'
    je .id_yes
    cmp al, '_'
    je .id_yes
    cmp al, '0'
    jl .id_no
    cmp al, '9'
    jle .id_yes
    cmp al, 'a'
    jl .id_u
    cmp al, 'z'
    jle .id_yes
.id_u:
    cmp al, 'A'
    jl .id_no
    cmp al, 'Z'
    jle .id_yes
.id_no:
    xor rax, rax
    ret
.id_yes:
    mov rax, 1
    ret

lex_fstring:
    mov rsi, [src_ptr]
    xor rcx, rcx
    add rcx, 2               ; skip f"
.fstr_loop:
    mov al, [rsi + rcx]
    test al, al
    jz .err_fstr
    cmp al, 10
    je .err_fstr
    cmp al, '"'
    je .fstr_done
    inc rcx
    jmp .fstr_loop

.fstr_done:
    inc rcx                  ; include closing quote
    mov rdi, TOKEN_STRING
    mov rsi, [src_ptr]
    mov rdx, rcx
    call emit_token
    add [src_ptr], rcx
    ret

.err_fstr:
    mov rsi, err_unterm_string
    call print_err
    mov rdi, 1
    call sys_exit

lex_string_token:
    inc qword [src_ptr]
    mov rsi, [src_ptr]
    xor rcx, rcx
.str_loop:
    mov al, [rsi + rcx]
    test al, al
    jz .err_string
    cmp al, 10
    je .err_string
    cmp al, '"'
    je .str_done
    inc rcx
    jmp .str_loop

.str_done:
    mov rdi, TOKEN_STRING
    mov rsi, [src_ptr]
    mov rdx, rcx
    call emit_token
    add rcx, 1
    add [src_ptr], rcx
    ret

.err_string:
    mov rsi, err_unterm_string
    call print_err
    mov rdi, 1
    call sys_exit

lex_ident_token:
    push rbx
    push r12
    push r13
    mov rsi, [src_ptr]
    xor rcx, rcx

.ident_loop:
    mov al, [rsi + rcx]
    call is_alnum
    test rax, rax
    jz .ident_done
    inc rcx
    jmp .ident_loop

.ident_done:
    mov r13, rcx
    mov rsi, [src_ptr]
    mov rdx, r13
    call lookup_keyword
    test rax, rax
    jz .not_kw

    push rax
    cmp rax, KW_ASM
    jne .not_asm_kw
    mov byte [in_asm_block], 1
    mov r12, [indent_sp]
    mov r12, [indent_stack + r12 * 8]
    add r12, 4
    mov [asm_indent_level], r12

.not_asm_kw:
    pop rax
    mov rdi, TOKEN_KEYWORD
    mov rsi, [src_ptr]
    mov rdx, r13
    call emit_token
    add [src_ptr], r13
    pop r13
    pop r12
    pop rbx
    ret

.not_kw:
    mov rdi, TOKEN_IDENT
    mov rsi, [src_ptr]
    mov rdx, r13
    call emit_token
    add [src_ptr], r13
    pop r13
    pop r12
    pop rbx
    ret

lex_operator_or_punct:
    mov rsi, [src_ptr]
    mov al, [rsi]

    cmp al, '&'
    jne .check_2char
    cmp byte [rsi + 1], 'm'
    jne .check_2char
    cmp byte [rsi + 2], 'u'
    jne .check_2char
    cmp byte [rsi + 3], 't'
    jne .check_2char
    mov rdi, TOKEN_OP
    mov rsi, [src_ptr]
    mov rdx, 4
    call emit_token
    add qword [src_ptr], 4
    mov rax, 1
    ret

.check_2char:
    mov bl, [rsi + 1]
    cmp al, '='
    je .c_eq
    cmp al, '!'
    je .c_ne
    cmp al, '<'
    je .c_le
    cmp al, '>'
    je .c_ge
    jmp .check_1char

.c_eq:
    cmp bl, '='
    jne .check_1char
    jmp .emit_2char_op
.c_ne:
    cmp bl, '='
    jne .check_1char
    jmp .emit_2char_op
.c_le:
    cmp bl, '='
    jne .check_1char
    jmp .emit_2char_op
.c_ge:
    cmp bl, '='
    jne .check_1char
    jmp .emit_2char_op

.emit_2char_op:
    mov rdi, TOKEN_OP
    mov rsi, [src_ptr]
    mov rdx, 2
    call emit_token
    add qword [src_ptr], 2
    mov rax, 1
    ret

.check_1char:
    cmp al, ':'
    je .t_colon
    cmp al, ','
    je .t_comma
    cmp al, '.'
    je .t_dot
    cmp al, '('
    je .t_lparen
    cmp al, ')'
    je .t_rparen
    cmp al, '{'
    je .t_lbrace
    cmp al, '}'
    je .t_rbrace
    cmp al, '['
    je .t_lbracket
    cmp al, ']'
    je .t_rbracket
    cmp al, '+'
    je .t_op
    cmp al, '-'
    je .t_op
    cmp al, '*'
    je .t_op
    cmp al, '/'
    je .t_op
    cmp al, '%'
    je .t_op
    cmp al, '='
    je .t_op
    cmp al, '<'
    je .t_op
    cmp al, '>'
    je .t_op
    cmp al, '&'
    je .t_op

    xor rax, rax
    ret

.t_colon:
    mov rdi, TOKEN_COLON
    jmp .emit_1char
.t_comma:
    mov rdi, TOKEN_COMMA
    jmp .emit_1char
.t_dot:
    mov rdi, TOKEN_DOT
    jmp .emit_1char
.t_lparen:
    mov rdi, TOKEN_LPAREN
    jmp .emit_1char
.t_rparen:
    mov rdi, TOKEN_RPAREN
    jmp .emit_1char
.t_lbrace:
    mov rdi, TOKEN_LBRACE
    jmp .emit_1char
.t_rbrace:
    mov rdi, TOKEN_RBRACE
    jmp .emit_1char
.t_lbracket:
    mov rdi, TOKEN_LBRACKET
    jmp .emit_1char
.t_rbracket:
    mov rdi, TOKEN_RBRACKET
    jmp .emit_1char
.t_op:
    mov rdi, TOKEN_OP
    jmp .emit_1char

.emit_1char:
    mov rsi, [src_ptr]
    mov rdx, 1
    call emit_token
    inc qword [src_ptr]
    mov rax, 1
    ret

is_alpha:
    cmp al, 'a'
    jl .check_upper
    cmp al, 'z'
    jle .yes
.check_upper:
    cmp al, 'A'
    jl .check_under
    cmp al, 'Z'
    jle .yes
.check_under:
    cmp al, '_'
    je .yes
    xor rax, rax
    ret
.yes:
    mov rax, 1
    ret

is_alnum:
    cmp al, '0'
    jl .not_d
    cmp al, '9'
    jle .is_yes
.not_d:
    cmp al, 'a'
    jl .c_u
    cmp al, 'z'
    jle .is_yes
.c_u:
    cmp al, 'A'
    jl .c_un
    cmp al, 'Z'
    jle .is_yes
.c_un:
    cmp al, '_'
    je .is_yes
    xor rax, rax
    ret
.is_yes:
    mov rax, 1
    ret

lookup_keyword:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx

    %macro CHECK_KW 2
        mov rdi, %1
        call str_len
        cmp rax, r13
        jne %%next
        mov rdi, r12
        mov rsi, %1
        mov rdx, r13
        call str_ncmp
        test rax, rax
        jnz %%next
        mov rax, %2
        pop r13
        pop r12
        pop rbx
        ret
    %%next:
    %endmacro

    CHECK_KW kw_if, KW_IF
    CHECK_KW kw_elif, KW_ELIF
    CHECK_KW kw_else, KW_ELSE
    CHECK_KW kw_for, KW_FOR
    CHECK_KW kw_in, KW_IN
    CHECK_KW kw_while, KW_WHILE
    CHECK_KW kw_loop, KW_LOOP
    CHECK_KW kw_break, KW_BREAK
    CHECK_KW kw_fn, KW_FN
    CHECK_KW kw_return, KW_RETURN
    CHECK_KW kw_struct, KW_STRUCT
    CHECK_KW kw_const, KW_CONST
    CHECK_KW kw_raw, KW_RAW
    CHECK_KW kw_defer, KW_DEFER
    CHECK_KW kw_alloc, KW_ALLOC
    CHECK_KW kw_free, KW_FREE
    CHECK_KW kw_asm, KW_ASM
    CHECK_KW kw_import, KW_IMPORT
    CHECK_KW kw_range, KW_RANGE

    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

emit_token:
    push rbx
    push r12

    mov rbx, [lexer_token_count]
    mov r12, [lexer_token_capacity]
    cmp rbx, r12
    jl .do_emit

    shl r12, 1
    mov [lexer_token_capacity], r12
    push rdi
    push rsi
    push rdx
    imul rdi, r12, Token_size
    call malloc_bytes
    mov rdi, rax
    mov rsi, [lexer_tokens]
    imul rdx, [lexer_token_count], Token_size
    push rdi
    xor rcx, rcx
.copy_loop:
    cmp rcx, rdx
    jge .copy_done
    mov r8b, [rsi + rcx]
    mov [rdi + rcx], r8b
    inc rcx
    jmp .copy_loop
.copy_done:
    pop rdi
    mov [lexer_tokens], rdi
    pop rdx
    pop rsi
    pop rdi

.do_emit:
    mov r8, [lexer_tokens]
    imul r9, rbx, Token_size
    add r8, r9

    mov [r8 + Token.type], rdi
    mov [r8 + Token.val], rsi
    mov [r8 + Token.len], rdx
    mov r10, [line_num]
    mov [r8 + Token.line], r10

    inc qword [lexer_token_count]

    pop r12
    pop rbx
    ret

lexer_next_token:
    mov rax, [lexer_token_idx]
    cmp rax, [lexer_token_count]
    jge .out_of_bounds
    mov r8, [lexer_tokens]
    imul r9, rax, Token_size
    add r8, r9
    inc qword [lexer_token_idx]
    mov rax, r8
    ret
.out_of_bounds:
    mov r8, [lexer_tokens]
    mov rax, [lexer_token_count]
    dec rax
    imul r9, rax, Token_size
    add r8, r9
    mov rax, r8
    ret

lexer_peek_token:
    mov rax, [lexer_token_idx]
    cmp rax, [lexer_token_count]
    jge .out_of_bounds_peek
    mov r8, [lexer_tokens]
    imul r9, rax, Token_size
    add r8, r9
    mov rax, r8
    ret
.out_of_bounds_peek:
    mov r8, [lexer_tokens]
    mov rax, [lexer_token_count]
    dec rax
    imul r9, rax, Token_size
    add r8, r9
    mov rax, r8
    ret

lexer_rewind:
    mov rax, [lexer_token_idx]
    test rax, rax
    jz .at_start
    dec qword [lexer_token_idx]
.at_start:
    ret

section .data
s_tok_fmt: db "Tok type: ", 0
s_tok_val: db " val: ", 0
s_dbg_nl: db 10, 0

section .text
dump_tokens_debug:
    push rbx
    push r12
    xor rbx, rbx
.dt_loop:
    cmp rbx, [lexer_token_count]
    jge .dt_done
    mov r8, [lexer_tokens]
    imul r9, rbx, Token_size
    add r8, r9

    mov rsi, s_tok_fmt
    call print_str

    mov r12, [r8 + Token.type]
    mov rdi, r12
    call print_num

    mov rsi, s_tok_val
    call print_str

    mov rsi, [r8 + Token.val]
    mov rdx, [r8 + Token.len]
    test rsi, rsi
    jz .no_v
    test rdx, rdx
    jz .no_v
    mov rdi, 1
    call sys_write
.no_v:
    mov rsi, s_dbg_nl
    call print_str

    inc rbx
    jmp .dt_loop
.dt_done:
    pop r12
    pop rbx
    ret
