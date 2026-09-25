#!/usr/bin/env bash
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script="$root/bin/server-optimizer.sh"
bash -n "$script"
out=$(mktemp)
trap 'rm -f "$out"' EXIT
bash "$script" --profile proxy >"$out"
grep -q '科学上网服务器' "$out"
grep -q '只读模式' "$out"
grep -q '候选建议' "$out"
! grep -Eq 'sysctl -w|systemctl|iptables -A|tc qdisc add' "$out"
bash "$script" --profile game >"$out"
grep -q '游戏加速器' "$out"
if bash "$script" --profile invalid >/dev/null 2>&1; then exit 1; fi
printf 'optimizer tests passed\n'
