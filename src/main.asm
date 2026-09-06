; src/main.asm - CAP v0.1 Frontend CLI Entry Point in NASM x86_64
default rel

section .data
s_dump_ast: db "--dump-ast", 0
s_dump_tokens: db "--dump-tokens", 0
err_usage: db "Usage: capc [--dump-ast] <filename.cap>", 10, 0
msg1: db "Msg 1: File read", 10, 0
msg2: db "Msg 2: Tokenized", 10, 0
msg3: db "Msg 3: Parsed AST", 10, 0
msg4: db "Msg 4: Dumped AST", 10, 0
err_open:  db "Error: Could not open source file", 10, 0
err_read:  db "Error: Could not read source file", 10, 0

section .bss
filename:      resq 1
dump_ast_mode: resb 1
dump_tok_mode: resb 1
file_buffer:   resq 1
file_size:     resq 1

section .text
global _start
extern malloc_init, malloc_bytes, str_cmp, print_err, print_str, sys_open, sys_read, sys_close, sys_exit
extern tokenize_source, parse_program, dump_ast, dump_tokens_debug

_start:
    pop r12
    cmp r12, 2
    jl .show_usage

    pop rbx
    dec r12

    mov byte [dump_ast_mode], 0
    mov byte [dump_tok_mode], 0
    mov qword [filename], 0

.parse_args_loop:
    test r12, r12
    jz .done_args
    pop rbx

    mov rdi, rbx
    mov rsi, s_dump_ast
    call str_cmp
    test rax, rax
    jnz .chk_tok

    mov byte [dump_ast_mode], 1
    dec r12
    jmp .parse_args_loop

.chk_tok:
    mov rdi, rbx
    mov rsi, s_dump_tokens
    call str_cmp
    test rax, rax
    jnz .not_flag

    mov byte [dump_tok_mode], 1
    dec r12
    jmp .parse_args_loop

.not_flag:
    mov [filename], rbx
    dec r12
    jmp .parse_args_loop

.done_args:
    mov rdi, [filename]
    test rdi, rdi
    jz .show_usage

    call malloc_init

    mov rdi, [filename]
    mov rsi, 0
    xor rdx, rdx
    call sys_open
    cmp rax, 0
    jl .file_open_err
    mov rbx, rax

    mov rdi, 1024 * 1024
    call malloc_bytes
    mov [file_buffer], rax

    mov rdi, rbx
    mov rsi, [file_buffer]
    mov rdx, 1024 * 1024 - 1
    call sys_read
    cmp rax, 0
    jl .file_read_err
    mov [file_size], rax

    mov rdi, [file_buffer]
    mov byte [rdi + rax], 0

    mov rdi, rbx
    call sys_close

    mov rdi, [file_buffer]
    call tokenize_source

    cmp byte [dump_tok_mode], 1
    jne .do_parse
    call dump_tokens_debug
    mov rdi, 0
    call sys_exit

.do_parse:
    call parse_program
    mov rbx, rax

    cmp byte [dump_ast_mode], 1
    jne .exit_success

    mov rdi, rbx
    call dump_ast

.exit_success:
    mov rdi, 0
    call sys_exit

.show_usage:
    mov rsi, err_usage
    call print_err
    mov rdi, 1
    call sys_exit

.file_open_err:
    mov rsi, err_open
    call print_err
    mov rdi, 1
    call sys_exit

.file_read_err:
    mov rsi, err_read
    call print_err
    mov rdi, 1
    call sys_exit
