; src/output/elf_writer.asm - ELF64 Executable Writer for CAP v0.1
default rel

%include "src/codegen/target.inc"

%define O_WRONLY 1
%define O_CREAT  64
%define O_TRUNC  512

section .data
err_write_elf: db "Error: Could not open output file for writing", 10, 0

section .text
global write_elf64_binary
extern sys_open, sys_write, sys_close, print_err, sys_exit

; write_elf64_binary(rdi = filename, rsi = target_arch, rdx = code_buf, rcx = code_len)
write_elf64_binary:
    push rbp
    mov rbp, rsp
    sub rsp, 128            ; Allocate space for ELF header (64) + Program header (56) = 120 bytes

    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi            ; filename
    mov r13, rsi            ; target_arch
    mov r14, rdx            ; code_buf
    mov r15, rcx            ; code_len

    ; Open output file with O_WRONLY | O_CREAT | O_TRUNC (0x241), mode 0755 (493)
    mov rdi, r12
    mov rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov rdx, 493            ; 0755 permissions (rwxr-xr-x)
    call sys_open
    cmp rax, 0
    jl .open_error
    mov rbx, rax            ; rbx = file descriptor

    ; Construct ELF Header at [rbp - 128]
    lea rdi, [rbp - 128]

    ; Clear 120 bytes
    push rdi
    mov rcx, 120
    xor al, al
    rep stosb
    pop rdi

    ; e_ident
    mov byte [rdi + 0], 0x7F
    mov byte [rdi + 1], 'E'
    mov byte [rdi + 2], 'L'
    mov byte [rdi + 3], 'F'
    mov byte [rdi + 4], 2       ; ELFCLASS64
    mov byte [rdi + 5], 1       ; ELFDATA2LSB (little endian)
    mov byte [rdi + 6], 1       ; EV_CURRENT

    ; e_type
    mov word [rdi + 16], 2      ; ET_EXEC

    ; e_machine
    cmp r13, TARGET_ARM64
    je .arm_machine
    mov word [rdi + 18], EM_X86_64
    jmp .mach_done
.arm_machine:
    mov word [rdi + 18], EM_AARCH64
.mach_done:

    ; e_version
    mov dword [rdi + 20], 1

    ; e_entry = 0x400078
    mov qword [rdi + 24], 0x400078

    ; e_phoff = 64
    mov qword [rdi + 32], 64

    ; e_shoff = 0
    mov qword [rdi + 40], 0

    ; e_flags = 0
    mov dword [rdi + 48], 0

    ; e_ehsize = 64
    mov word [rdi + 52], 64

    ; e_phentsize = 56
    mov word [rdi + 54], 56

    ; e_phnum = 1
    mov word [rdi + 56], 1

    ; Construct Program Header at [rbp - 128 + 64] = [rbp - 64]
    lea rsi, [rdi + 64]

    ; p_type = PT_LOAD (1)
    mov dword [rsi + 0], 1

    ; p_flags = PF_R | PF_W | PF_X (7)
    mov dword [rsi + 4], 7

    ; p_offset = 0
    mov qword [rsi + 8], 0

    ; p_vaddr = 0x400000
    mov qword [rsi + 16], 0x400000

    ; p_paddr = 0x400000
    mov qword [rsi + 24], 0x400000

    ; p_filesz = 120 + code_len
    mov rax, r15
    add rax, 120
    mov qword [rsi + 32], rax

    ; p_memsz = 120 + code_len
    mov qword [rsi + 40], rax

    ; p_align = 0x1000
    mov qword [rsi + 48], 0x1000

    ; Write Headers (120 bytes) to output file
    mov rdi, rbx
    lea rsi, [rbp - 128]
    mov rdx, 120
    call sys_write

    ; Write Code section (r15 bytes) to output file
    test r15, r15
    jz .close_file

    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    call sys_write

.close_file:
    mov rdi, rbx
    call sys_close

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.open_error:
    mov rsi, err_write_elf
    call print_err
    mov rdi, 1
    call sys_exit
