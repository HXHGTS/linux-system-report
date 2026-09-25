#!/usr/bin/env bash
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/bin/system-report.sh"
bash -n "$script"
out=$(mktemp)
trap 'rm -f "$out"' EXIT
bash "$script" --output "$out"
grep -q '【操作系统与内核】' "$out"
grep -q '【内存与虚拟内存】' "$out"
grep -q '【内核参数】' "$out"
grep -q '【交换空间与内存压力】' "$out"
grep -q '【文件句柄与资源限制】' "$out"
if grep -Eq 'MemTotal:|Filesystem|NAME[[:space:]]+SIZE|Linux version|^  [a-z].*=' "$out"; then
  echo '原始系统输出意外出现在报告中' >&2
  exit 1
fi
bash "$script" --json | grep -q '"redacted": true'
if bash "$script" --bad-option >/dev/null 2>&1; then echo 'bad option unexpectedly accepted' >&2; exit 1; fi
echo 'tests passed'
