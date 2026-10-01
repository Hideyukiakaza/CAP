#!/usr/bin/env bash
# CAP v0.1 Freestanding / Bare-Metal Test Runner
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPC="$ROOT/../../capc"
MODE="${1:-check}"

pass=0
fail=0

run_one() {
    local src="$1"
    local base
    base="$(basename "$src" .cap)"
    local golden_file="$ROOT/golden/$base.out"
    local bin_fs="/tmp/cap_test_${base}_fs"
    local stdout_fs stderr_fs exit_fs actual_fs compile_status

    local extra_flags=""
    if [ "$base" = "17_boot_thin" ] || [ "$base" = "18_thin_exception" ]; then
        extra_flags="--boot-thin"
    fi

    "$CAPC" --freestanding $extra_flags -o "$bin_fs" "$src" 2>/tmp/cap_test_stderr
    compile_status=$?

    if [ $compile_status -ne 0 ]; then
        stderr_fs="$(cat /tmp/cap_test_stderr | sed -E 's/pid [0-9]+/pid PID/g; /terminating on signal .* \(timeout\)/d')"
        actual_fs="$(cat <<EOF
EXIT: $compile_status
STDOUT:
STDERR:
$stderr_fs
EOF
)"
    else
        stdout_fs="$(timeout 10 qemu-system-x86_64 -kernel "$bin_fs" -serial stdio -display none -no-reboot 2>/tmp/cap_test_stderr)"
        exit_fs=$?
        stderr_fs="$(cat /tmp/cap_test_stderr | sed -E 's/pid [0-9]+/pid PID/g; /terminating on signal .* \(timeout\)/d')"
        actual_fs="$(cat <<EOF
EXIT: $exit_fs
STDOUT:
$stdout_fs
STDERR:
$stderr_fs
EOF
)"
    fi
    rm -f "$bin_fs" /tmp/cap_test_stderr

    if [ "$MODE" = "--update" ]; then
        mkdir -p "$ROOT/golden"
        echo "$actual_fs" > "$golden_file"
        echo "UPDATED  $base"
        return
    fi

    if [ ! -f "$golden_file" ]; then
        echo "NO GOLD  $base"
        fail=$((fail+1))
    else
        local expected
        expected="$(cat "$golden_file")"
        if [ "$actual_fs" = "$expected" ]; then
            echo "PASS     $base"
            pass=$((pass+1))
        else
            echo "FAIL     $base"
            diff <(echo "$expected") <(echo "$actual_fs") | sed 's/^/         /'
            fail=$((fail+1))
        fi
    fi
}

for src in "$ROOT"/*.cap; do
    [ -f "$src" ] || continue
    run_one "$src"
done

echo ""
echo "Results: $pass passed, $fail failed"
if [ $fail -ne 0 ]; then
    exit 1
fi
