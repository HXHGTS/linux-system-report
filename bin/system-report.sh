#!/usr/bin/env bash
# Debian/Ubuntu 服务器摘要采集器：只读、离线、不安装软件。
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
value() { [ -r "$1" ] && sed -n '1p' "$1" 2>/dev/null || printf '不可用'; }
why() { printf '不可用（%s）' "$1"; }
section() { printf '\n【%s】\n' "$1"; }
mem_value() { awk -v k="$1" '$1==k":" {printf "%.2f MiB",$2/1024; ok=1} END{if(!ok)print "不可用"}' /proc/meminfo 2>/dev/null; }
mask() { if [ "$redact" -eq 1 ]; then sed -E -e 's#([Pp]assword|[Tt]oken|[Ss]ecret|[Aa]pi[_-]?[Kk]ey)=[^[:space:]]+#\1=<已隐藏>#g' -e 's#UUID=[^,[:space:]]+#UUID=<已隐藏>#g' -e 's#/home/[^/[:space:]]+#/home/<用户>#g' -e 's#([[:space:]=]|^)([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}#\1<MAC已隐藏>#g' -e 's#([[:space:]=]|^)([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?#\1<IP已隐藏>#g'; else cat; fi; }
collect_text() {
  printf '服务器信息摘要\n生成时间：'; date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || printf '不可用\n'
  section '主机与硬件'; printf '主机名：%s\n' "$(value /etc/hostname | mask)"; printf '架构：%s\n' "$(have uname && uname -m || why '缺少 uname')"
  cpu=$(awk -F: '/^model name/{gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null); [ -n "$cpu" ] || cpu=$(why '无法读取 cpuinfo'); printf 'CPU 型号：%s\n' "$cpu"; n=$(awk '/^processor/{n++} END{print n+0}' /proc/cpuinfo 2>/dev/null); printf '逻辑处理器：%s\n' "${n:-不可用}"
  for pair in '厂商:sys_vendor' '产品:product_name' '主板:board_name' 'BIOS:bios_version'; do label=${pair%%:*}; file=${pair#*:}; printf '%s：%s\n' "$label" "$(value "/sys/class/dmi/id/$file")"; done
  section '内存与存储'; printf '总内存：%s\n可用内存：%s\n' "$(mem_value MemTotal)" "$(mem_value MemAvailable)"
  if have df; then printf '挂载点数量：%s\n' "$(df -P 2>/dev/null | awk 'NR>1{n++} END{print n+0}')"; else printf '挂载点：%s\n' "$(why '缺少 df')"; fi
  if have lsblk; then printf '磁盘设备数量：%s\n' "$(lsblk -dn 2>/dev/null | awk '$6=="disk"{n++} END{print n+0}')"; else printf '磁盘：%s\n' "$(why '缺少 lsblk')"; fi
  section '操作系统'; if [ -r /etc/os-release ]; then . /etc/os-release 2>/dev/null; printf '系统：%s\n版本：%s\n' "${PRETTY_NAME:-${NAME:-不可用}}" "${VERSION_ID:-不可用}"; else printf '系统：%s\n' "$(why '缺少 os-release')"; fi; printf 'Debian 版本：%s\n' "$(value /etc/debian_version)"
  section '内核'; printf '版本：%s\n' "$(have uname && uname -r || why '缺少 uname')"; printf '构建信息：%s\n' "$(have uname && uname -v | sed 's/[[:space:]]\+/ /g' | cut -c1-100 || why '缺少 uname')"
  section '内核参数'; printf '启动参数数量：%s（内容不展示）\n' "$(value /proc/cmdline | awk '{print NF}')"; for p in swappiness overcommit_memory; do printf '%s：%s\n' "$p" "$(value "/proc/sys/vm/$p")"; done
  section '交换空间'; printf '总量：%s\n可用：%s\n' "$(mem_value SwapTotal)" "$(mem_value SwapFree)"
  section '配置摘要'; for f in /etc/hostname /etc/hosts /etc/fstab /etc/issue /etc/resolv.conf; do [ -e "$f" ] && printf '%s：已存在（原文不展示）\n' "$f" || printf '%s：不存在\n' "$f"; done; [ -r /etc/apt/sources.list ] && printf 'APT 主源：已配置（原文不展示）\n' || printf 'APT 主源：不可用\n'
  section 'OpenSSL'; if have openssl; then printf '版本：%s\n' "$(openssl version 2>/dev/null | awk '{print $1" "$2}')"; else printf '%s\n' "$(why '缺少 openssl')"; fi
  section '网络'; if have ip; then printf '接口数：%s\nIPv4 地址数：%s\nIPv6 地址数：%s\n默认路由数：%s\n' "$(ip -o link 2>/dev/null | awk 'END{print NR}')" "$(ip -o -4 addr 2>/dev/null | wc -l)" "$(ip -o -6 addr 2>/dev/null | wc -l)" "$(ip -4 route 2>/dev/null | awk '$1=="default"{n++} END{print n+0}')"; else printf '网络：%s\n' "$(why '缺少 ip')"; fi
  section 'DNS'; if [ -r /etc/resolv.conf ]; then printf 'DNS 服务器数量：%s\n搜索域数量：%s\n' "$(grep -Ec '^[[:space:]]*nameserver[[:space:]]' /etc/resolv.conf 2>/dev/null || printf 0)" "$(grep -E '^[[:space:]]*(search|domain)[[:space:]]' /etc/resolv.conf 2>/dev/null | awk '{n+=NF-1} END{print n+0}')"; else printf 'DNS：%s\n' "$(why '缺少 resolv.conf')"; fi
  [ "$redact" -eq 1 ] || printf '\n提示：已关闭脱敏，请勿公开分享此报告。\n'
}
collect_json() { printf '{"generated_utc":"'; date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; printf '","redacted":%s,"hostname":"'; value /etc/hostname | mask | tr -d '\r\n' | sed 's/"/\\"/g'; printf '","architecture":"'; (have uname && uname -m || printf 不可用); printf '","kernel":"'; (have uname && uname -r || printf 不可用); printf '"}\n'; }
if [ "$format" = json ]; then collect_json; else collect_text; fi > "$TMP" || exit 1
if [ -n "$output" ]; then mv "$TMP" "$output" || exit 1; TMP=''; else cat "$TMP"; fi
