#!/usr/bin/env bash
# CAP v0.1 Codegen Test Runner
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPC="$ROOT/../../capc"
MODE="${1:-check}"

pass=0
fail=0
skip=0

run_one() {
    local src="$1"
    local base
    base="$(basename "$src" .cap)"
    local golden_x86="$ROOT/golden/x86/$base.out"
    local golden_arm="$ROOT/golden/arm/$base.out"
    local stdin_file="$ROOT/$base.stdin"

    # --- x86-64 Target ---
    local bin_x86="/tmp/cap_test_${base}_x86"
    local stdout_x86 stderr_x86 exit_x86 actual_x86 x86_compile_status
    "$CAPC" -o "$bin_x86" "$src" 2>/tmp/cap_test_stderr_x86
    x86_compile_status=$?
    if [ $x86_compile_status -ne 0 ]; then
        actual_x86="COMPILE_ERROR: $(cat /tmp/cap_test_stderr_x86)"
    else
        if [ -f "$stdin_file" ]; then
            stdout_x86="$(timeout 3 "$bin_x86" < "$stdin_file" 2>/tmp/cap_test_stderr_x86)"
        else
            stdout_x86="$(timeout 3 "$bin_x86" 2>/tmp/cap_test_stderr_x86)"
        fi
        exit_x86=$?
        stderr_x86="$(cat /tmp/cap_test_stderr_x86)"
        actual_x86="$(cat <<EOF
EXIT: $exit_x86
STDOUT:
$stdout_x86
STDERR:
$stderr_x86
EOF
)"
    fi
    rm -f "$bin_x86" /tmp/cap_test_stderr_x86

    # --- ARM64 Target ---
    local bin_arm="/tmp/cap_test_${base}_arm"
    local stdout_arm stderr_arm exit_arm actual_arm arm_compile_status
    if [ "$base" = "08_asm_block" ]; then
        local arm_src="/tmp/08_asm_block_arm.cap"
        cat << 'EOF' > "$arm_src"
fn main():
    x = 42
    asm:
        mov x0, 42
    return x
EOF
        "$CAPC" -a -o "$bin_arm" "$arm_src" 2>/tmp/cap_test_stderr_arm
        arm_compile_status=$?
        rm -f "$arm_src"
    else
        "$CAPC" -a -o "$bin_arm" "$src" 2>/tmp/cap_test_stderr_arm
        arm_compile_status=$?
    fi

    if [ $arm_compile_status -ne 0 ]; then
        actual_arm="COMPILE_ERROR: $(cat /tmp/cap_test_stderr_arm)"
    else
        if [ -f "$stdin_file" ]; then
            stdout_arm="$(timeout 3 qemu-aarch64 "$bin_arm" < "$stdin_file" 2>/tmp/cap_test_stderr_arm)"
        else
            stdout_arm="$(timeout 3 qemu-aarch64 "$bin_arm" 2>/tmp/cap_test_stderr_arm)"
        fi
        exit_arm=$?
        stderr_arm="$(cat /tmp/cap_test_stderr_arm)"
        actual_arm="$(cat <<EOF
EXIT: $exit_arm
STDOUT:
$stdout_arm
STDERR:
$stderr_arm
EOF
)"
    fi
    rm -f "$bin_arm" /tmp/cap_test_stderr_arm

    if [ "$MODE" = "--update" ]; then
        mkdir -p "$ROOT/golden/x86"
        echo "$actual_x86" > "$golden_x86"
        if [ -f "$golden_arm" ]; then
            echo "$actual_arm" > "$golden_arm"
        fi
        echo "UPDATED  $base"
        return
    fi

    # Check x86-64
    if [ ! -f "$golden_x86" ]; then
        echo "NO GOLD  $base (x86-64)"
        fail=$((fail+1))
    else
        local expected_x86
        expected_x86="$(cat "$golden_x86")"
        if [ "$actual_x86" = "$expected_x86" ]; then
            echo "PASS     $base (x86-64)"
            pass=$((pass+1))
        else
            echo "FAIL     $base (x86-64)"
            diff <(echo "$expected_x86") <(echo "$actual_x86") | sed 's/^/         /'
            fail=$((fail+1))
        fi
    fi

    # Check ARM64
    if [ ! -f "$golden_arm" ]; then
        echo "SKIP     $base (ARM64)"
        skip=$((skip+1))
    else
        local expected_arm
        expected_arm="$(cat "$golden_arm")"
        if [ "$actual_arm" = "$expected_arm" ]; then
            echo "PASS     $base (ARM64)"
            pass=$((pass+1))
        else
            echo "FAIL     $base (ARM64)"
            diff <(echo "$expected_arm") <(echo "$actual_arm") | sed 's/^/         /'
            fail=$((fail+1))
        fi
    fi
}

for f in "$ROOT"/*.cap; do
    run_one "$f"
done

if [ "$MODE" != "--update" ]; then
    echo ""
    echo "Results: $pass passed, $fail failed, $skip skipped"
    [ "$fail" -eq 0 ]
fi
