; src/main.asm - CAP v0.1 CLI Entry Point with Codegen Support
default rel

%include "src/codegen/target.inc"

section .data
s_dump_ast:          db "--dump-ast", 0
s_dump_tokens:       db "--dump-tokens", 0
s_flag_a:            db "-a", 0
s_flag_o:            db "-o", 0
s_flag_freestanding: db "--freestanding", 0
s_flag_k:            db "-k", 0
s_flag_no_boot_stub: db "--no-boot-stub", 0
s_flag_boot_thin:    db "--boot-thin", 0
err_usage:           db "Usage: capc [-a] [--freestanding|-k] [--boot-thin] [-o <outfile>] [--dump-ast] <filename.cap>", 10, 0
err_boot_thin:       db "Error: --boot-thin requires --freestanding or -k", 10, 0
err_open:      db "Error: Could not open source file", 10, 0
err_read:      db "Error: Could not read source file", 10, 0
err_missing_o: db "Error: -o flag requires an output filename argument", 10, 0

section .bss
global target_arch, output_filename
filename:        resq 1
output_filename: resq 1
target_arch:     resq 1
dump_ast_mode:   resb 1
dump_tok_mode:   resb 1
boot_thin_mode:  resb 1
file_buffer:     resq 1
file_size:       resq 1

section .text
global _start
extern malloc_init, malloc_bytes, str_cmp, print_err, print_str, sys_open, sys_read, sys_close, sys_exit
extern tokenize_source, parse_program, dump_ast, dump_tokens_debug
extern compile_program

_start:
    pop r12             ; argc
    cmp r12, 2
    jl .show_usage

    pop rbx             ; argv[0]
    dec r12

    mov byte [dump_ast_mode], 0
    mov byte [dump_tok_mode], 0
    mov byte [boot_thin_mode], 0
    mov qword [filename], 0
    mov qword [output_filename], 0
    mov qword [target_arch], TARGET_X86_64

.parse_args_loop:
    test r12, r12
    jz .done_args
    pop rbx             ; current arg
    dec r12

    ; check -a
    mov rdi, rbx
    mov rsi, s_flag_a
    call str_cmp
    test rax, rax
    jnz .chk_k
    mov qword [target_arch], TARGET_ARM64
    jmp .parse_args_loop

.chk_k:
    mov rdi, rbx
    mov rsi, s_flag_k
    call str_cmp
    test rax, rax
    jnz .chk_freestanding
    mov qword [target_arch], TARGET_FREESTANDING
    jmp .parse_args_loop

.chk_freestanding:
    mov rdi, rbx
    mov rsi, s_flag_freestanding
    call str_cmp
    test rax, rax
    jnz .chk_no_boot_stub
    cmp qword [target_arch], TARGET_NO_BOOT_STUB
    je .parse_args_loop
    mov qword [target_arch], TARGET_FREESTANDING
    jmp .parse_args_loop

.chk_no_boot_stub:
    mov rdi, rbx
    mov rsi, s_flag_no_boot_stub
    call str_cmp
    test rax, rax
    jnz .chk_boot_thin
    mov qword [target_arch], TARGET_NO_BOOT_STUB
    jmp .parse_args_loop

.chk_boot_thin:
    mov rdi, rbx
    mov rsi, s_flag_boot_thin
    call str_cmp
    test rax, rax
    jnz .chk_o
    mov byte [boot_thin_mode], 1
    jmp .parse_args_loop

.chk_o:
    mov rdi, rbx
    mov rsi, s_flag_o
    call str_cmp
    test rax, rax
    jnz .chk_dump_ast
    test r12, r12
    jz .missing_o_err
    pop rbx
    dec r12
    mov [output_filename], rbx
    jmp .parse_args_loop

.chk_dump_ast:
    mov rdi, rbx
    mov rsi, s_dump_ast
    call str_cmp
    test rax, rax
    jnz .chk_tok
    mov byte [dump_ast_mode], 1
    jmp .parse_args_loop

.chk_tok:
    mov rdi, rbx
    mov rsi, s_dump_tokens
    call str_cmp
    test rax, rax
    jnz .not_flag
    mov byte [dump_tok_mode], 1
    jmp .parse_args_loop

.not_flag:
    mov [filename], rbx
    jmp .parse_args_loop

.done_args:
    cmp byte [boot_thin_mode], 1
    jne .chk_filename
    cmp qword [target_arch], TARGET_FREESTANDING
    jne .boot_thin_without_freestanding_err
    mov qword [target_arch], TARGET_BOOT_THIN

.chk_filename:
    mov rdi, [filename]
    test rdi, rdi
    jz .show_usage

    call malloc_init

    ; Derive output filename if not set via -o
    cmp qword [output_filename], 0
    jne .has_output_name

    ; Allocate memory for output_filename
    mov rdi, 1024
    call malloc_bytes
    mov [output_filename], rax

    ; Copy filename to output_filename
    mov rsi, [filename]
    mov rdi, [output_filename]
.copy_loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .copy_done
    inc rsi
    inc rdi
    jmp .copy_loop
.copy_done:
    ; Strip trailing .cap if present
    mov rdi, [output_filename]
    extern str_len
    call str_len
    cmp rax, 4
    jl .has_output_name

    ; Check if last 4 chars are ".cap"
    mov rbx, [output_filename]
    add rbx, rax
    sub rbx, 4
    cmp byte [rbx], '.'
    jne .has_output_name
    cmp byte [rbx+1], 'c'
    jne .has_output_name
    cmp byte [rbx+2], 'a'
    jne .has_output_name
    cmp byte [rbx+3], 'p'
    jne .has_output_name
    mov byte [rbx], 0    ; null terminate to strip .cap

.has_output_name:
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
    mov rbx, rax       ; rbx = AST root

    cmp byte [dump_ast_mode], 1
    jne .do_compile

    mov rdi, rbx
    call dump_ast
    mov rdi, 0
    call sys_exit

.do_compile:
    mov rdi, rbx                 ; AST root
    mov rsi, [target_arch]       ; TARGET_X86_64 or TARGET_ARM64
    mov rdx, [output_filename]   ; output path
    call compile_program

    mov rdi, 0
    call sys_exit

.show_usage:
    mov rsi, err_usage
    call print_err
    mov rdi, 1
    call sys_exit

.boot_thin_without_freestanding_err:
    mov rsi, err_boot_thin
    call print_err
    mov rdi, 1
    call sys_exit

.missing_o_err:
    mov rsi, err_missing_o
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
