#!/usr/bin/env bash
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/bin/server-optimizer.sh"
bash -n "$script"
out=$(mktemp)
trap 'rm -f "$out"' EXIT
bash "$script" --profile proxy >"$out"
grep -q '科学上网服务器' "$out"
grep -q '当前值 → 修改后' "$out"
grep -q '计划模式：未修改系统' "$out"
bash "$script" --profile game >"$out"
grep -q '游戏加速器' "$out"
# 非交互环境必须拒绝 --apply，不能创建备份或写入系统。
if bash "$script" --profile proxy --apply </dev/null >"$out" 2>&1; then exit 1; fi
grep -q '交互终端' "$out"
if bash "$script" --profile invalid >/dev/null 2>&1; then exit 1; fi
printf 'optimizer tests passed\n'
