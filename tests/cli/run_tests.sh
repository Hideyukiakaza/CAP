#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPC="$ROOT/../../capc"

out="$("$CAPC" --version)"
exp="$(cat "$ROOT/golden/version.out")"

if [ "$out" = "$exp" ]; then
    echo "PASS     cli_version"
else
    echo "FAIL     cli_version"
    diff <(echo "$exp") <(echo "$out")
    return 1 2>/dev/null || exit 1
fi

# Imports are parsed by the frontend, but module resolution is not implemented.
# The compiler must reject them instead of silently generating a program that ignores them.
tmp_src="$(mktemp /tmp/cap_cli_import_XXXXXX.cap)"
tmp_bin="${tmp_src%.cap}.out"
tmp_err="${tmp_src%.cap}.err"
printf 'import math\n' > "$tmp_src"
if "$CAPC" -o "$tmp_bin" "$tmp_src" 2>"$tmp_err"; then
    echo "FAIL     cli_import_unsupported (compiler accepted import)"
    rm -f "$tmp_src" "$tmp_bin" "$tmp_err"
    exit 1
elif grep -q "SyntaxError: import is not implemented yet" "$tmp_err"; then
    echo "PASS     cli_import_unsupported"
else
    echo "FAIL     cli_import_unsupported (unexpected diagnostic)"
    cat "$tmp_err"
    rm -f "$tmp_src" "$tmp_bin" "$tmp_err"
    exit 1
fi
rm -f "$tmp_src" "$tmp_bin" "$tmp_err"
