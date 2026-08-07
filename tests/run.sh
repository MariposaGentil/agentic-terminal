#!/usr/bin/env bash
# Discover and run every tests/test_*.sh, then print an aggregate summary.
# Exits non-zero if any assertion or test file fails. Invoked by `make test`.
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass=0
fail=0
files=0
failed_files=0

for t in "$DIR"/test_*.sh; do
    [ -e "$t" ] || continue
    files=$((files + 1))
    name="${t##*/}"
    echo "== $name =="
    out="$(bash "$t" 2>&1)"
    rc=$?
    printf '%s\n' "$out"
    p="$(printf '%s\n' "$out" | grep -c '^  ok ' || true)"
    f="$(printf '%s\n' "$out" | grep -c '^  FAIL ' || true)"
    pass=$((pass + p))
    fail=$((fail + f))
    [ "$rc" -ne 0 ] && failed_files=$((failed_files + 1))
    echo
done

echo "==================================================="
echo "Assertions: $pass passed, $fail failed"
echo "Files:      $files run, $failed_files failed"
if [ "$fail" -gt 0 ] || [ "$failed_files" -gt 0 ]; then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: ALL TESTS PASSED"
