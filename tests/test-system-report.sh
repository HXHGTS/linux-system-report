#!/usr/bin/env bash
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/bin/system-report.sh"
bash -n "$script"
out=$(mktemp)
trap 'rm -f "$out"' EXIT
bash "$script" --output "$out"
grep -q '== Operating system ==' "$out"
grep -q '== Memory and storage ==' "$out"
bash "$script" --json | grep -q '"redacted": true'
if bash "$script" --bad-option >/dev/null 2>&1; then echo 'bad option unexpectedly accepted' >&2; exit 1; fi
echo 'tests passed'
