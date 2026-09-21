#!/usr/bin/env bash
# CAP v0.1 frontend test runner.
# Usage:
#   ./run_tests.sh            -> run all tests, diff against golden output, report pass/fail
#   ./run_tests.sh --update   -> regenerate golden output from current capc binary (use after an intentional behavior change)

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPC="$ROOT/../../capc"
MODE="${1:-check}"

pass=0
fail=0

run_one() {
    local src="$1"
    local flag="$2"
    local golden_dir="$3"
    local base
    base="$(basename "$src" .cap)"
    local golden="$golden_dir/$base.out"

    local stdout stderr exit_code
    stdout="$("$CAPC" "$flag" "$src" 2>/tmp/cap_test_stderr)"
    exit_code=$?
    stderr="$(cat /tmp/cap_test_stderr)"

    local actual
    actual="$(cat <<EOF
EXIT: $exit_code
STDOUT:
$stdout
STDERR:
$stderr
EOF
)"

    if [ "$MODE" = "--update" ]; then
        echo "$actual" > "$golden"
        echo "UPDATED  $base"
        return
    fi

    if [ ! -f "$golden" ]; then
        echo "NO GOLD  $base (run with --update to create it)"
        fail=$((fail+1))
        return
    fi

    local expected
    expected="$(cat "$golden")"

    if [ "$actual" = "$expected" ]; then
        echo "PASS     $base"
        pass=$((pass+1))
    else
        echo "FAIL     $base"
        diff <(echo "$expected") <(echo "$actual") | sed 's/^/         /'
        fail=$((fail+1))
    fi
}

for f in "$ROOT"/parser/*.cap; do
    run_one "$f" "--dump-ast" "$ROOT/golden/parser"
done

for f in "$ROOT"/lexer/*.cap; do
    run_one "$f" "--dump-tokens" "$ROOT/golden/lexer"
done

if [ "$MODE" != "--update" ]; then
    echo ""
    echo "Results: $pass passed, $fail failed"
    [ "$fail" -eq 0 ]
fi
