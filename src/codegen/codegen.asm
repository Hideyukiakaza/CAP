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

section .text
global compile_program
global create_code_buf, emit_byte, emit_dword, emit_qword, emit_bytes, patch_dword
global find_symbol_offset, add_symbol
global fn_sym_init, add_fn_symbol, find_fn_symbol

extern malloc_bytes, str_ncmp, str_len, print_err, sys_exit
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

    mov r12, rdi             ; ast_root
    mov r13, rsi             ; target_arch
    mov r14, rdx             ; output_filename

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

    ; Dispatch to architecture emitter
    cmp r13, TARGET_ARM64
    je .do_arm
    mov rdi, r12
    mov rsi, rbx
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

    mov rbx, [rdi + ASTNode.child1]
.s_loop:
    test rbx, rbx
    jz .s_done

    cmp qword [rbx + ASTNode.type], AST_STRUCT_DECL
    jne .s_next

    ; Compute field offsets for struct
    mov r12, [rbx + ASTNode.child1] ; field list
    xor r13, r13                     ; current offset = 0

.field_loop:
    test r12, r12
    jz .field_done

    mov [r12 + ASTNode.extra], r13  ; store offset in .extra
    add r13, 8                      ; 8 bytes per field in v0.1
    mov r12, [r12 + ASTNode.next]
    jmp .field_loop

.field_done:
    mov [rbx + ASTNode.extra], r13  ; store struct size in .extra

.s_next:
    mov rbx, [rbx + ASTNode.next]
    jmp .s_loop

.s_done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; Symbol Tables
section .bss
global sym_buf, fn_buf
sym_buf: resb 8192
sym_count: resq 1

fn_buf: resb 8192
fn_count: resq 1

section .text
global sym_init
sym_init:
    mov qword [sym_count], 0
    ret

add_symbol:
    push rbx
    mov rbx, [sym_count]
    imul rbx, 24             ; 24 bytes per entry (3 qwords)
    lea rax, [sym_buf + rbx]
    mov [rax], rdi
    mov [rax + 8], rsi
    mov [rax + 16], rdx
    inc qword [sym_count]
    pop rbx
    ret

find_symbol_offset:
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
    imul r14, 24
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
    imul r14, 24
    lea rax, [sym_buf + r14]
    mov rax, [rax + 16]
    jmp .done

.not_found:
    mov rax, -1

.done:
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
