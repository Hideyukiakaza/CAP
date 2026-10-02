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
