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
    if [ "$base" = "08_freestanding" ]; then
        continue
    fi
    golden="$EX_DIR/golden/$base.out"
    bin="/tmp/cap_doc_ex_$base"

    "$CAPC" -o "$bin" "$src" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAIL compile $base"
        fail=$((fail+1))
        continue
    fi

    out="$("$bin")"
    rm -f "$bin"

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

echo ""
echo "Docs Examples Results: $pass passed, $fail failed"
if [ $fail -ne 0 ]; then
    return 1 2>/dev/null || exit 1
fi
