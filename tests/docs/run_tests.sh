#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPC="$ROOT/../../capc"
EX_DIR="$ROOT/../../docs/examples"

pass=0
fail=0

for src in "$EX_DIR"/*.cap; do
    [ -f "$src" ] || continue
    base="$(basename "$src" .cap)"
    golden="$EX_DIR/golden/$base.out"
    bin="/tmp/cap_doc_ex_$base"

    if [ "$base" = "08_freestanding" ]; then
        "$CAPC" --freestanding -o "$bin" "$src" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "FAIL compile $base"
            fail=$((fail+1))
            continue
        fi
        out="$(timeout 5 qemu-system-x86_64 -kernel "$bin" -serial stdio -display none -no-reboot 2>/tmp/cap_doc_stderr)"
        rm -f "$bin" /tmp/cap_doc_stderr
    else
        "$CAPC" -o "$bin" "$src" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "FAIL compile $base"
            fail=$((fail+1))
            continue
        fi
        out="$("$bin")"
        rm -f "$bin"
    fi

    if [ ! -f "$golden" ]; then
        echo "NO GOLD  $base"
        fail=$((fail+1))
        continue
    fi

    exp="$(cat "$golden")"
    if [ "$out" = "$exp" ]; then
        echo "PASS     $base"
        pass=$((pass+1))
    else
        echo "FAIL exec    $base"
        diff <(echo "$exp") <(echo "$out")
        fail=$((fail+1))
    fi
done

python3 -c '
import re, glob, os, sys

ex_files = set()
for p in glob.glob("' "$EX_DIR" '/*.cap"):
    with open(p) as f:
        ex_files.add(f.read().strip())

failed = False
docs = ["README.md", "docs/LANGUAGE.md", "docs/GUIDE.md"]
for doc in docs:
    doc_path = os.path.join("'"$ROOT/../.."'", doc)
    if not os.path.exists(doc_path):
        continue
    with open(doc_path) as f:
        content = f.read()
    blocks = re.findall(r"```cap\n(.*?)```", content, re.DOTALL)
    for i, b in enumerate(blocks):
        b_clean = b.strip()
        if "/* ignore-example-check */" in b_clean or b_clean.startswith(";"):
            continue
        if b_clean not in ex_files:
            print(f"FAIL doc check {doc} block {i+1}:\n{b_clean}")
            failed = True

if failed:
    sys.exit(1)
else:
    print("PASS     docs_code_block_match")
'
if [ $? -ne 0 ]; then
    fail=$((fail+1))
else
    pass=$((pass+1))
fi

echo ""
echo "Docs Examples Results: $pass passed, $fail failed"
if [ $fail -ne 0 ]; then
    return 1 2>/dev/null || exit 1
fi
