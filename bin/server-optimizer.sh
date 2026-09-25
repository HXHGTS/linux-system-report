#!/usr/bin/env bash
# 根据硬件和用途生成 Linux 服务器优化建议；默认只读，不修改系统。
set -u
export LC_ALL=C
profile=''
usage() { printf '%s\n' '用法：server-optimizer.sh [--profile proxy|game]'; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; profile=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) printf '未知参数：%s\n' "$1" >&2; usage >&2; exit 2;;
  esac
done
if [ -z "$profile" ]; then
  printf '请选择服务器使用场景：\n1. 科学上网服务器\n2. 游戏加速器\n选择 [1-2]：'
  read -r choice || exit 2
  case "$choice" in 1) profile=proxy;; 2) profile=game;; *) printf '无效选择。\n' >&2; exit 2;; esac
fi
case "$profile" in proxy|game) ;; *) printf '场景必须是 proxy 或 game。\n' >&2; exit 2;; esac

have() { command -v "$1" >/dev/null 2>&1; }
readv() { [ -r "$1" ] && sed -n '1p' "$1" 2>/dev/null || printf '不可用'; }
sysv() { readv "/proc/sys/$1"; }
memv() { awk -v k="$1" '$1==k":" {printf "%.2f MiB",$2/1024;ok=1} END{if(!ok)print "不可用"}' /proc/meminfo 2>/dev/null; }
num_mem_kb() { awk -v k="$1" '$1==k":" {print $2; exit}' /proc/meminfo 2>/dev/null; }
section() { printf '\n【%s】\n' "$1"; }
status() { [ "$1" != '不可用' ] && printf '已检测：%s\n' "$1" || printf '无法检测：%s\n' "$2"; }

cpu=$(awk -F: '/^model name/{gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null); [ -n "$cpu" ] || cpu='不可用'
cores=$(awk '/^processor/{n++} END{print n+0}' /proc/cpuinfo 2>/dev/null)
mem_total=$(num_mem_kb MemTotal); mem_available=$(num_mem_kb MemAvailable)
[ -n "$mem_total" ] || mem_total=0; [ -n "$mem_available" ] || mem_available=0
swap_total=$(num_mem_kb SwapTotal); swap_free=$(num_mem_kb SwapFree); [ -n "$swap_total" ] || swap_total=0; [ -n "$swap_free" ] || swap_free=0

printf '服务器优化建议（只读模式）\n场景：%s\n' "$([ "$profile" = proxy ] && printf '科学上网服务器' || printf '游戏加速器')"
printf '注意：本脚本只生成候选建议，不执行 sysctl、tc、iptables/nft、systemctl 或写入 /etc。\n'
section '硬件与运行环境'; printf 'CPU：%s\n逻辑处理器：%s\n内存：%s\n可用内存：%s\nSwap：%s\n内核：%s\n' "$cpu" "$cores" "$(memv MemTotal)" "$(memv MemAvailable)" "$(memv SwapTotal)" "$(uname -r 2>/dev/null || printf 不可用)"
section '当前关键观测'; printf 'vm.swappiness：%s\nvm.overcommit_memory：%s\nvm.vfs_cache_pressure：%s\nCommitted_AS：%s\nCommitLimit：%s\n' "$(sysv vm/swappiness)" "$(sysv vm/overcommit_memory)" "$(sysv vm/vfs_cache_pressure)" "$(memv Committed_AS)" "$(memv CommitLimit)"
if [ -r /proc/pressure/memory ]; then printf '内存 PSI：'; awk 'NR==1{print $4" "$5" "$6}' /proc/pressure/memory; else printf '内存 PSI：不可用\n'; fi
if [ -r /proc/pressure/io ]; then printf 'IO PSI：'; awk 'NR==1{print $4" "$5" "$6}' /proc/pressure/io; else printf 'IO PSI：不可用\n'; fi
if have ip; then printf '网络接口：%s；IPv4：%s；IPv6：%s；默认路由：%s\n' "$(ip -o link 2>/dev/null | awk 'END{print NR}')" "$(ip -o -4 addr 2>/dev/null | wc -l)" "$(ip -o -6 addr 2>/dev/null | wc -l)" "$(ip -4 route 2>/dev/null | awk '$1=="default"{n++}END{print n+0}')"; else printf '网络：无法检测（缺少 ip）\n'; fi

section '检测结果';
if [ "$mem_total" -lt 1048576 ]; then printf '内存较小（低于 1 GiB），不建议盲目提高缓存、队列或并发上限。\n'; elif [ "$mem_total" -lt 4194304 ]; then printf '内存中等（1-4 GiB），建议以实测压力和 Swap 使用率为依据。\n'; else printf '内存充足（至少 4 GiB），仍需结合业务并发和 PSI 判断。\n'; fi
if [ "$swap_total" -eq 0 ]; then printf '未检测到 Swap：内存紧张时可能触发 OOM。\n'; else printf '已配置 Swap，当前使用量约 %s。\n' "$(awk -v t="$swap_total" -v f="$swap_free" 'BEGIN{printf "%.2f MiB",(t-f)/1024}')"; fi

section '建议';
if [ "$profile" = proxy ]; then
  printf '%s\n' '1. 连接转发：先确认是否启用 NAT/转发、实际并发、带宽、MTU 和 conntrack，再评估端口范围、文件句柄和队列上限。'
  printf '%s\n' '2. 虚拟内存：以 MemAvailable、Committed_AS/CommitLimit、Swap 使用量和内存 PSI 判断；不要仅凭内存大小固定 swappiness 或 overcommit 值。'
  printf '%s\n' '3. 吞吐优化：只有在持续带宽压测和 CPU/IO PSI 正常时，才评估拥塞控制、socket 缓冲和 netdev backlog；不要直接套用网上参数。'
  printf '%s\n' '4. 安全与稳定：不要为追求吞吐关闭 syncookies、盲目扩大 conntrack 或修改 MTU；变更前记录当前值并准备回滚。'
else
  printf '%s\n' '1. 低延迟优先：先采样 RTT、抖动、丢包、路径和 UDP 实际流量；不要把 somaxconn、TCP backlog 或大队列当作游戏延迟优化。'
  printf '%s\n' '2. 队列与 MTU：确认网卡、隧道、路径 MTU 和 qdisc 后再评估；以减少排队延迟为目标，不盲目增大队列。'
  printf '%s\n' '3. CPU/内存：检查 CPU、内存和 IO PSI、软中断及 Swap；避免在压力未定位前关闭 THP 或强制切换内存策略。'
  printf '%s\n' '4. 网络质量：使用多时段 ping/mtr/ss/ethtool 采样验证，区分服务器资源问题与线路、路由或上游拥塞问题。'
fi

section '需要人工确认'; printf '%s\n' '- 业务并发峰值、协议类型（TCP/UDP）、带宽、RTT/丢包、是否 NAT/隧道。\n- 云厂商限制、网卡队列、内核版本和当前 qdisc。\n- 任何参数修改都应先备份、分批变更、验证并保留回滚方案。'
printf '\n结论：这是基于当前快照的候选建议，不是自动调优或性能测试结果。\n'
