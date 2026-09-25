#!/usr/bin/env bash
# Portable Debian/Ubuntu server inventory; no network or package installation.
set -u
export LC_ALL=C

redact=1
format=text
output=''
usage() { printf '%s\n' 'Usage: system-report.sh [--output FILE] [--json] [--no-redact]'; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; output=$2; shift 2 ;;
    --json) format=json; shift ;;
    --no-redact) redact=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

TMP=''; cleanup() { [ -n "$TMP" ] && rm -f "$TMP"; }; trap cleanup EXIT HUP INT TERM
if command -v mktemp >/dev/null 2>&1; then TMP=$(mktemp) || exit 1; else TMP="${TMPDIR:-/tmp}/system-report.$$"; fi
umask 077
warn() { printf '[WARN] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
read_one() { [ -r "$1" ] && sed -n '1p' "$1" 2>/dev/null || printf 'N/A'; }
redact_text() {
  if [ "$redact" -eq 1 ]; then
    sed -E \
      -e 's#([Pp]assword|[Tt]oken|[Ss]ecret|[Aa]pi[_-]?[Kk]ey)=[^[:space:]]+#\1=<REDACTED>#g' \
      -e 's#UUID=[^,[:space:]]+#UUID=<REDACTED>#g' \
      -e 's#([[:space:]=]|^)([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}#\1<MAC_REDACTED>#g' \
      -e 's#([[:space:]=]|^)([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?#\1<IP_REDACTED>#g' \
      -e 's#/home/[^/[:space:]]+#/home/<USER>#g' \
      -e 's#(/etc/)?machine-id[=:][^[:space:]]+#machine-id=<REDACTED>#g'
  else cat
  fi
}
section() { printf '\n== %s ==\n' "$1"; }
command_output() { if have "$1"; then shift; "$@" 2>&1 || warn "$1 failed"; else printf 'N/A (missing %s)\n' "$1"; warn "$1 is not installed"; fi; }
bytes_human() { awk -v b="${1:-0}" 'BEGIN { if (b < 1024) printf "%.0f B",b; else if (b < 1048576) printf "%.2f KiB",b/1024; else if (b < 1073741824) printf "%.2f MiB",b/1048576; else if (b < 1099511627776) printf "%.2f GiB",b/1073741824; else printf "%.2f TiB",b/1099511627776 }'; }

collect_text() {
  printf 'system-report generated: '; date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'N/A\n'
  section 'Host and hardware'
  printf 'Hostname: '; read_one /etc/hostname
  printf 'Architecture: '; have uname && uname -m || printf 'N/A\n'
  printf 'CPU model: '; awk -F: '/^model name/{gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || printf 'N/A\n'
  printf 'CPU logical processors: '; have nproc && nproc || awk '/^processor/{n++} END{print n+0}' /proc/cpuinfo 2>/dev/null
  for f in sys_vendor product_name product_version board_name bios_version; do printf '%s: %s\n' "$f" "$(read_one "/sys/class/dmi/id/$f")"; done
  section 'Memory and storage'
  if [ -r /proc/meminfo ]; then awk '/^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):/ {printf "%s: %.2f MiB\n",$1,$2/1024}' /proc/meminfo; else printf 'Memory: N/A\n'; fi
  if have free; then free -h; else warn 'free is not installed'; fi
  printf 'Mounted filesystems:\n'; if have df; then df -hT 2>&1 || warn 'df failed'; else printf 'N/A\n'; fi
  printf 'Block devices:\n'; if have lsblk; then lsblk -e 7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>&1 || warn 'lsblk failed'; else printf 'N/A (missing lsblk)\n'; fi
  section 'Operating system'
  if [ -r /etc/os-release ]; then cat /etc/os-release; else printf 'os-release: N/A\n'; fi
  printf 'Debian version: '; read_one /etc/debian_version; printf '\n'
  section 'Kernel'
  if have uname; then uname -a; uname -r; else printf 'N/A\n'; fi
  [ -r /proc/version ] && cat /proc/version || true
  printf 'Kernel osrelease: '; read_one /proc/sys/kernel/osrelease; printf '\n'
  section 'Kernel parameters'
  printf 'cmdline: '; read_one /proc/cmdline; printf '\n'
  if have sysctl; then sysctl -a 2>/dev/null | grep -E '^(kernel\.(hostname|ostype|osrelease|version)|vm\.(swappiness|overcommit_memory)|net\.ipv[46]\.)' || warn 'sysctl query failed'; else for f in hostname ostype osrelease version; do printf 'kernel.%s: %s\n' "$f" "$(read_one "/proc/sys/kernel/$f")"; done; fi
  section 'Swap / page file'
  if have swapon; then swapon --show 2>&1 || warn 'swapon failed'; else [ -r /proc/swaps ] && cat /proc/swaps || printf 'N/A\n'; fi
  section '/etc common configuration'
  for f in /etc/hostname /etc/hosts /etc/fstab /etc/issue /etc/resolv.conf; do if [ -r "$f" ]; then printf '\n--- %s ---\n' "$f"; cat "$f" | redact_text; fi; done
  if [ -r /etc/apt/sources.list ]; then printf '\n--- /etc/apt/sources.list ---\n'; cat /etc/apt/sources.list | redact_text; fi
  if [ -d /etc/apt/sources.list.d ]; then for f in /etc/apt/sources.list.d/*.list; do [ -r "$f" ] || continue; printf '\n--- %s ---\n' "$f"; cat "$f" | redact_text; done; fi
  section 'OpenSSL'
  if have openssl; then openssl version -a 2>&1 || warn 'openssl failed'; else printf 'N/A (missing openssl)\n'; fi
  section 'Network addresses and routes'
  if have ip; then ip -4 addr show; ip -6 addr show; ip -4 route show; ip -6 route show; elif have hostname; then hostname -I 2>/dev/null || printf 'N/A\n'; else printf 'N/A (missing ip and hostname)\n'; fi
  section 'DNS'
  if have resolvectl; then resolvectl status 2>&1 | grep -E 'DNS Servers|DNS Domain|Current DNS Server' || true; fi
  if have nmcli; then nmcli device show 2>/dev/null | grep -E 'IP[46]\.DNS|IP4\.DOMAIN|IP6\.DOMAIN' || true; fi
  [ -r /etc/resolv.conf ] && grep -E '^[[:space:]]*(nameserver|search|domain|options)' /etc/resolv.conf | redact_text || printf 'N/A\n'
  [ "$redact" -eq 1 ] || warn 'redaction disabled; do not share this report publicly'
}

collect_json() {
  # Stable, dependency-free JSON summary; detailed text remains the default format.
  printf '{\n  "generated_utc": "'; date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null | sed 's/"/\\"/g'; printf '",\n'
  printf '  "hostname": "'; read_one /etc/hostname | redact_text | sed ':a;N;$!ba;s/[\r\n]/ /g;s/"/\\"/g'; printf '",\n'
  printf '  "architecture": "'; (have uname && uname -m || printf N/A) | sed 's/"/\\"/g'; printf '",\n'
  printf '  "kernel": "'; (have uname && uname -r || printf N/A) | sed 's/"/\\"/g'; printf '",\n'
  printf '  "os_release": '; if [ -r /etc/os-release ]; then printf 'true'; else printf 'false'; fi; printf ',\n'
  printf '  "redacted": %s\n}\n' "$([ "$redact" -eq 1 ] && printf true || printf false)"
}
if [ "$format" = json ]; then collect_json; else collect_text; fi >"$TMP" || { warn 'collection failed'; exit 1; }
if [ -n "$output" ]; then mkdir -p "$(dirname "$output")" 2>/dev/null || true; mv "$TMP" "$output" || { warn "cannot write $output"; exit 1; }; TMP=''; else cat "$TMP"; fi
