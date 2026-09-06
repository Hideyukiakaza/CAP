ASM = nasm
ASMFLAGS = -f elf64 -g -F dwarf
LD = ld
LDFLAGS = 

OBJS = src/main.o src/utils.o src/lexer.o src/ast.o src/parser.o \
       src/output/elf_writer.o src/codegen/runtime_stubs.o \
       src/codegen/codegen.o src/codegen/x86_emit.o src/codegen/arm_emit.o
TARGET = capc

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJS)

src/main.o: src/main.asm src/codegen/target.inc
	$(ASM) $(ASMFLAGS) src/main.asm -o src/main.o

src/utils.o: src/utils.asm
	$(ASM) $(ASMFLAGS) src/utils.asm -o src/utils.o

src/lexer.o: src/lexer.asm
	$(ASM) $(ASMFLAGS) src/lexer.asm -o src/lexer.o

src/ast.o: src/ast.asm
	$(ASM) $(ASMFLAGS) src/ast.asm -o src/ast.o

src/parser.o: src/parser.asm
	$(ASM) $(ASMFLAGS) src/parser.asm -o src/parser.o

src/output/elf_writer.o: src/output/elf_writer.asm src/codegen/target.inc
	$(ASM) $(ASMFLAGS) src/output/elf_writer.asm -o src/output/elf_writer.o

src/codegen/runtime_stubs.o: src/codegen/runtime_stubs.asm src/codegen/target.inc
	$(ASM) $(ASMFLAGS) src/codegen/runtime_stubs.asm -o src/codegen/runtime_stubs.o

src/codegen/codegen.o: src/codegen/codegen.asm src/codegen/target.inc
	$(ASM) $(ASMFLAGS) src/codegen/codegen.asm -o src/codegen/codegen.o

src/codegen/x86_emit.o: src/codegen/x86_emit.asm src/codegen/target.inc
	$(ASM) $(ASMFLAGS) src/codegen/x86_emit.asm -o src/codegen/x86_emit.o

src/codegen/arm_emit.o: src/codegen/arm_emit.asm src/codegen/target.inc
	$(ASM) $(ASMFLAGS) src/codegen/arm_emit.asm -o src/codegen/arm_emit.o

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
