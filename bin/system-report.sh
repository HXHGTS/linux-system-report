#!/usr/bin/env bash
# Debian/Ubuntu 服务器优化评估摘要：只读、离线、不安装软件。
set -u
export LC_ALL=C
redact=1; format=text; output=''
usage() { printf '%s\n' '用法：system-report.sh [--output 文件] [--json] [--no-redact]'; }
while [ "$#" -gt 0 ]; do case "$1" in
  --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output=$2; shift 2;;
  --json) format=json; shift;; --no-redact) redact=0; shift;;
  -h|--help) usage; exit 0;; *) printf '未知参数：%s\n' "$1" >&2; exit 2;;
esac; done
umask 077; TMP=$(mktemp 2>/dev/null || printf '%s/system-report.%s' "${TMPDIR:-/tmp}" "$$") || exit 1
cleanup() { [ -n "${TMP:-}" ] && rm -f "$TMP"; }; trap cleanup EXIT HUP INT TERM
have() { command -v "$1" >/dev/null 2>&1; }
why() { printf '不可用（%s）' "$1"; }
read1() { [ -r "$1" ] && sed -n '1p' "$1" 2>/dev/null || printf '不可用'; }
section() { printf '\n【%s】\n' "$1"; }
mem() { awk -v k="$1" '$1==k":" {printf "%.2f MiB",$2/1024;ok=1} END{if(!ok)print "不可用"}' /proc/meminfo 2>/dev/null; }
sysval() { [ -r "/proc/sys/$1" ] && read1 "/proc/sys/$1" || printf '不可用'; }
mask() { if [ "$redact" -eq 1 ]; then sed -E -e 's#([Pp]assword|[Tt]oken|[Ss]ecret|[Aa]pi[_-]?[Kk]ey)=[^[:space:]]+#\1=<已隐藏>#g' -e 's#UUID=[^,[:space:]]+#UUID=<已隐藏>#g' -e 's#/home/[^/[:space:]]+#/home/<用户>#g' -e 's#([[:space:]=]|^)([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}#\1<MAC已隐藏>#g' -e 's#([[:space:]=]|^)([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?#\1<IP已隐藏>#g'; else cat; fi; }
count_file() { [ -r "$1" ] && awk 'NF{n++} END{print n+0}' "$1" 2>/dev/null || printf '不可用'; }
psi() { f="/proc/pressure/$1"; if [ -r "$f" ]; then awk '{printf "%s: avg10=%s avg60=%s avg300=%s\n",$1,$4,$5,$6}' "$f"; else printf '%s：不可用（内核未提供）\n' "$1"; fi; }
collect_text() {
 printf '服务器优化评估摘要\n生成时间：'; date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || printf '不可用\n'
 section '主机与硬件'; printf '主机名：%s\n架构：%s\n' "$(read1 /etc/hostname | mask)" "$(have uname && uname -m || why '缺少 uname')"
 cpu=$(awk -F: '/^model name/{gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null); [ -n "$cpu" ] || cpu=$(why '无法读取 cpuinfo'); printf 'CPU 型号：%s\n' "$cpu"; printf '逻辑处理器：%s\n' "$(awk '/^processor/{n++} END{print n+0}' /proc/cpuinfo 2>/dev/null)"
 for p in '厂商:sys_vendor' '产品:product_name' '主板:board_name' 'BIOS:bios_version'; do l=${p%%:*}; f=${p#*:}; printf '%s：%s\n' "$l" "$(read1 "/sys/class/dmi/id/$f")"; done
 section '内存与虚拟内存'; printf '总内存：%s\n可用内存：%s\n已提交：%s\n提交上限：%s\n脏页：%s\n回写中：%s\nSlab：%s\n匿名页：%s\nSwap 缓存：%s\n' "$(mem MemTotal)" "$(mem MemAvailable)" "$(mem Committed_AS)" "$(mem CommitLimit)" "$(mem Dirty)" "$(mem Writeback)" "$(mem Slab)" "$(mem AnonPages)" "$(mem SwapCached)"
 section '内核参数'; for p in vm/swappiness vm/overcommit_memory vm/overcommit_ratio vm/vfs_cache_pressure vm/min_free_kbytes vm/dirty_background_ratio vm/dirty_ratio vm/dirty_expire_centisecs vm/dirty_writeback_centisecs vm/max_map_count vm/oom_dump_tasks kernel/panic_on_oom kernel/pid_max kernel/threads-max; do printf '%s：%s\n' "$p" "$(sysval "$p")"; done
 section '交换空间与内存压力'; printf 'Swap 总量：%s\nSwap 可用：%s\nSwap 设备数：%s\n' "$(mem SwapTotal)" "$(mem SwapFree)" "$(count_file /proc/swaps)"; if [ -r /sys/module/zswap/parameters/enabled ]; then printf 'zswap：%s\n' "$(read1 /sys/module/zswap/parameters/enabled)"; else printf 'zswap：不可用\n'; fi; if [ -d /sys/block/zram0 ]; then printf 'zram：已检测到\n'; else printf 'zram：未检测到\n'; fi; psi memory
 section '透明大页'; for p in enabled defrag shmem_enabled; do printf '%s：%s\n' "$p" "$(read1 "/sys/kernel/mm/transparent_hugepage/$p")"; done; printf '匿名大页：%s\n' "$(mem AnonHugePages)"
 section '网络与队列'; if have ip; then printf '接口数：%s\nIPv4 地址数：%s\nIPv6 地址数：%s\n默认路由数：%s\n' "$(ip -o link 2>/dev/null | awk 'END{print NR}')" "$(ip -o -4 addr 2>/dev/null | wc -l)" "$(ip -o -6 addr 2>/dev/null | wc -l)" "$(ip -4 route 2>/dev/null | awk '$1=="default"{n++}END{print n+0}')"; else printf '网络：%s\n' "$(why '缺少 ip')"; fi; for p in net/core/somaxconn net/core/netdev_max_backlog net/ipv4/tcp_max_syn_backlog net/ipv4/tcp_syncookies net/ipv4/ip_local_port_range net/ipv4/tcp_tw_reuse; do printf '%s：%s\n' "$p" "$(sysval "$p")"; done
 section '文件句柄与资源限制'; printf '系统最大文件数：%s\n文件使用计数：%s\ninode 使用计数：%s\n进程上限：%s\n线程上限：%s\n当前打开文件限制：%s\n' "$(sysval fs/file-max)" "$(awk '{print $1"/"$2"/"$3}' /proc/sys/fs/file-nr 2>/dev/null || printf 不可用)" "$(awk '{print $1"/"$2}' /proc/sys/fs/inode-nr 2>/dev/null || printf 不可用)" "$(sysval kernel/pid_max)" "$(sysval kernel/threads-max)" "$(ulimit -n 2>/dev/null || printf 不可用)"
 section '磁盘与文件系统'; if have df; then df -P -h 2>/dev/null | awk 'NR>1{printf "挂载点%d：总量=%s 已用=%s 可用=%s 使用率=%s\n",NR-1,$2,$3,$4,$5}'; else printf '文件系统：%s\n' "$(why '缺少 df')"; fi; printf 'IO 压力：\n'; psi io
 section '配置摘要'; for f in /etc/hostname /etc/hosts /etc/fstab /etc/resolv.conf /etc/security/limits.conf; do [ -e "$f" ] && printf '%s：已存在（原文不展示）\n' "$f" || printf '%s：不存在\n' "$f"; done
 section '操作系统与内核'; if [ -r /etc/os-release ]; then . /etc/os-release 2>/dev/null; printf '系统：%s\n版本：%s\n' "${PRETTY_NAME:-不可用}" "${VERSION_ID:-不可用}"; else printf '系统：不可用\n'; fi; printf '内核版本：%s\n构建信息：%s\n' "$(have uname && uname -r || why '缺少 uname')" "$(have uname && uname -v | sed 's/[[:space:]]\+/ /g' | cut -c1-100 || why '缺少 uname')"
 section 'OpenSSL 与 DNS'; if have openssl; then printf 'OpenSSL：%s\n' "$(openssl version 2>/dev/null | awk '{print $1" "$2}')"; else printf 'OpenSSL：不可用\n'; fi; if [ -r /etc/resolv.conf ]; then printf 'DNS 服务器数：%s\n搜索域数：%s\n' "$(grep -Ec '^[[:space:]]*nameserver[[:space:]]' /etc/resolv.conf 2>/dev/null || printf 0)" "$(grep -E '^[[:space:]]*(search|domain)[[:space:]]' /etc/resolv.conf 2>/dev/null | awk '{n+=NF-1}END{print n+0}')"; else printf 'DNS：不可用\n'; fi
 printf '\n说明：以上为采集时快照，不等于性能测试或调优结论；请结合业务、内核版本和云厂商文档评估。\n'; [ "$redact" -eq 1 ] || printf '提示：已关闭脱敏，请勿公开分享。\n'
}
collect_json() { r=false; [ "$redact" -eq 1 ] && r=true; h=$(read1 /etc/hostname | mask | tr -d '\r\n' | sed 's/"/\\"/g;s/\\/\\\\/g'); printf '{"generated_utc":"'; date -u '+%Y-%m-%dT%H:%M:%SZ'; printf '","redacted":%s,"hostname":"%s","architecture":"%s","kernel":"%s","swap_total":"%s","swap_free":"%s"}\n' "$r" "$h" "$(have uname && uname -m || printf 不可用)" "$(have uname && uname -r || printf 不可用)" "$(mem SwapTotal)" "$(mem SwapFree)"; }
if [ "$format" = json ]; then collect_json; else collect_text; fi > "$TMP" || exit 1
if [ -n "$output" ]; then mv "$TMP" "$output" || exit 1; TMP=''; else cat "$TMP"; fi
