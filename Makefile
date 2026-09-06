ASM = nasm
ASMFLAGS = -f elf64 -g -F dwarf
LD = ld
LDFLAGS = 

OBJS = src/main.o src/utils.o src/lexer.o src/ast.o src/parser.o
TARGET = capc

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJS)

src/main.o: src/main.asm
	$(ASM) $(ASMFLAGS) src/main.asm -o src/main.o

src/utils.o: src/utils.asm
	$(ASM) $(ASMFLAGS) src/utils.asm -o src/utils.o

src/lexer.o: src/lexer.asm
	$(ASM) $(ASMFLAGS) src/lexer.asm -o src/lexer.o

src/ast.o: src/ast.asm
	$(ASM) $(ASMFLAGS) src/ast.asm -o src/ast.o

src/parser.o: src/parser.asm
	$(ASM) $(ASMFLAGS) src/parser.asm -o src/parser.o

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
