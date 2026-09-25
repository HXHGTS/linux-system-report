#!/usr/bin/env bash
# 场景化 Linux 参数优化：显示变更计划，确认后备份并应用，失败自动回滚。
set -u
export LC_ALL=C
PROFILE=''; APPLY=0; ROLLBACK=''; DROPIN=/etc/sysctl.d/99-server-optimizer.conf
usage() { printf '%s\n' '用法：server-optimizer.sh [--profile proxy|game] [--apply] [--rollback 备份目录]'; }
while [ "$#" -gt 0 ]; do case "$1" in
  --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2;;
  --apply) APPLY=1; shift;; --rollback) [ "$#" -ge 2 ] || exit 2; ROLLBACK=$2; shift 2;;
  -h|--help) usage; exit 0;; *) printf '未知参数：%s\n' "$1" >&2; exit 2;;
esac; done
if [ -n "$ROLLBACK" ]; then
  [ "$(id -u)" -eq 0 ] || { printf '回滚需要 root。\n' >&2; exit 1; }
  [ -t 0 ] && [ -t 1 ] || { printf '回滚必须在交互终端执行。\n' >&2; exit 1; }
  [ -r "$ROLLBACK/manifest" ] || { printf '备份清单不存在。\n' >&2; exit 1; }
  printf '将根据备份恢复参数和配置：%s\n请输入 ROLLBACK 继续：' "$ROLLBACK"; read -r answer || exit 1; [ "$answer" = ROLLBACK ] || { printf '已取消。\n'; exit 0; }
  [ -r "$ROLLBACK/sysctl-values" ] || exit 1
  while IFS='=' read -r key old; do [ -n "$key" ] || continue; sysctl -w "$key=$old" >/dev/null || { printf '恢复失败：%s\n' "$key" >&2; exit 1; }; done < "$ROLLBACK/sysctl-values"
  if grep -q '^DROPIN_ABSENT=1$' "$ROLLBACK/manifest"; then rm -f "$DROPIN"; else cp "$ROLLBACK/dropin" "$DROPIN"; fi
  printf '回滚完成，请重新执行采集脚本验证。\n'; exit 0
fi
if [ -z "$PROFILE" ]; then printf '请选择服务器用途：\n1. 科学上网服务器\n2. 游戏加速器\n选择 [1-2]：'; read -r c || exit 2; case "$c" in 1) PROFILE=proxy;; 2) PROFILE=game;; *) printf '无效选择。\n' >&2; exit 2;; esac; fi
case "$PROFILE" in proxy|game) ;; *) printf '场景必须是 proxy 或 game。\n' >&2; exit 2;; esac
have() { command -v "$1" >/dev/null 2>&1; }
getv() { [ -r "/proc/sys/$1" ] && cat "/proc/sys/$1" 2>/dev/null || printf '不可用'; }
add_candidate() { key=$1; target=$2; reason=$3; current=$(getv "${key//./\/}"); if [ "$current" = '不可用' ]; then printf '%s|%s|%s|跳过：内核不支持\n' "$key" "$current" "$reason" >> "$PLAN"; return; fi; printf '%s|%s|%s|%s\n' "$key" "$current" "$target" "$reason" >> "$PLAN"; }
TMP=$(mktemp -d 2>/dev/null) || exit 1
cleanup() { rm -rf "$TMP"; }; trap cleanup EXIT HUP INT TERM
PLAN="$TMP/plan"; : > "$PLAN"
# 仅处理固定 allowlist；候选值保守，需用户确认后才应用。
if [ "$PROFILE" = proxy ]; then
  add_candidate net.core.somaxconn 4096 '高并发监听场景候选；需结合实际连接数验证'
  add_candidate net.core.netdev_max_backlog 4096 '吞吐/突发流量候选；需观察丢包和 CPU 压力'
  add_candidate net.ipv4.tcp_max_syn_backlog 4096 'TCP 建连突发候选；不代表应长期增大'
else
  add_candidate net.core.somaxconn 1024 '仅保守提高监听队列；低延迟服务需压测确认'
  add_candidate net.ipv4.tcp_syncookies 1 '保持安全默认值，不关闭 SYN 防护'
fi
printf '服务器优化变更计划\n场景：%s\n' "$([ "$PROFILE" = proxy ] && printf '科学上网服务器' || printf '游戏加速器')"
printf '\n【当前值 → 修改后】\n'
changes=0; : > "$TMP/changes"
while IFS='|' read -r key current target reason; do
  if [ "$target" = '跳过：内核不支持' ]; then printf '%-38s 当前=%s  状态=%s\n' "$key" "$current" "$target"; continue; fi
  if [ "$current" = "$target" ]; then printf '%-38s %s → %s  保持（%s）\n' "$key" "$current" "$target" "$reason"; else printf '%-38s %s → %s  待确认（%s）\n' "$key" "$current" "$target" "$reason"; printf '%s=%s\n' "$key" "$target" >> "$TMP/changes"; changes=$((changes+1)); fi
done < "$PLAN"
printf '\n【应用说明】\n将修改 %s 项运行时参数，并写入专用配置：%s\n' "$changes" "$DROPIN"
printf '应用前会创建备份；失败会尝试恢复旧值。不会修改防火墙、路由、MTU 或服务配置。\n'
[ "$changes" -gt 0 ] || { printf '没有需要修改的参数。\n'; exit 0; }
[ "$APPLY" -eq 1 ] || { printf '\n当前为计划模式：未修改系统。需要应用时重新执行并加入 --apply。\n'; exit 0; }
[ "$(id -u)" -eq 0 ] || { printf '应用需要 root，未修改系统。\n' >&2; exit 1; }
[ -t 0 ] && [ -t 1 ] || { printf '应用必须在交互终端执行，未修改系统。\n' >&2; exit 1; }
printf '\n请确认以上修改，输入 APPLY 才会继续：'; read -r answer || exit 1; [ "$answer" = APPLY ] || { printf '已取消，未修改系统。\n'; exit 0; }
if have flock; then exec 9>/run/lock/server-optimizer.lock; flock -n 9 || { printf '已有另一个优化任务运行。\n' >&2; exit 1; }; fi
BACKUP_ROOT=/var/backups/server-optimizer; mkdir -p "$BACKUP_ROOT"; BACKUP="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$$"; (umask 077; mkdir "$BACKUP") || exit 1
printf 'profile=%s\ncreated_utc=%s\n' "$PROFILE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BACKUP/manifest"
if [ -e "$DROPIN" ]; then [ ! -L "$DROPIN" ] || { printf '拒绝覆盖符号链接：%s\n' "$DROPIN" >&2; exit 1; }; cp -p "$DROPIN" "$BACKUP/dropin" || exit 1; else printf 'DROPIN_ABSENT=1\n' >> "$BACKUP/manifest"; fi
cp "$TMP/changes" "$BACKUP/proposed-values"; : > "$BACKUP/sysctl-values"
while IFS='=' read -r key target; do old=$(getv "${key//./\/}"); printf '%s=%s\n' "$key" "$old" >> "$BACKUP/sysctl-values"; done < "$TMP/changes"
chmod 600 "$BACKUP"/*; printf '备份已完成：%s\n' "$BACKUP"
rollback_apply() { while IFS='=' read -r k v; do [ "$v" != '不可用' ] && sysctl -w "$k=$v" >/dev/null 2>&1 || true; done < "$BACKUP/sysctl-values"; if grep -q '^DROPIN_ABSENT=1$' "$BACKUP/manifest"; then rm -f "$DROPIN"; else cp "$BACKUP/dropin" "$DROPIN"; fi; }
if ! mkdir -p "$(dirname "$DROPIN")" || ! : > "$TMP/dropin"; then rollback_apply; exit 1; fi
printf '# server-optimizer profile=%s; review backup before rollback\n' "$PROFILE" > "$TMP/dropin"
while IFS='=' read -r key target; do printf '%s = %s\n' "$key" "$target" >> "$TMP/dropin"; done < "$TMP/changes"
chmod 644 "$TMP/dropin"; if ! mv "$TMP/dropin" "$DROPIN"; then rollback_apply; exit 1; fi
while IFS='=' read -r key target; do if ! sysctl -w "$key=$target" >/dev/null 2>&1 || [ "$(getv "${key//./\/}")" != "$target" ]; then printf '应用失败：%s，开始回滚。\n' "$key" >&2; rollback_apply; exit 1; fi; done < "$TMP/changes"
printf '应用完成：%s 项已验证。备份目录：%s\n' "$changes" "$BACKUP"
printf '如需回滚：sudo %s --rollback %s\n' "$0" "$BACKUP"
