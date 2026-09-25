# Linux System Report

离线、只读采集 Debian/Ubuntu 服务器硬件、系统、内核、存储和网络摘要。默认使用中文固定字段，经过解析后只显示简洁摘要，不直接倾印命令或配置文件原文。脚本不会联网、安装软件、修改系统或上传报告，适合网络受限和工具残缺的环境。

## 使用

### 一键运行

直接从 GitHub 加载并运行最新脚本（默认输出已脱敏报告）：

```sh
curl -fsSL https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/system-report.sh | bash
```

没有 `curl` 时可使用 `wget`：

```sh
wget -qO- https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/system-report.sh | bash
```

> 一键命令会执行远程脚本。对生产服务器或安全要求较高的环境，建议先下载、检查内容，再运行。

### 加载到本地后运行

```sh
curl -fsSLo system-report.sh https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/system-report.sh
chmod +x system-report.sh
./system-report.sh
```

也可以使用 `wget` 加载：

```sh
wget -O system-report.sh https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/system-report.sh
chmod +x system-report.sh
./system-report.sh --output report.txt
```

### 本地运行

```sh
chmod +x bin/system-report.sh
./bin/system-report.sh
./bin/system-report.sh --output report.txt
./bin/system-report.sh --json
```

默认脱敏主机名、IP、MAC、UUID、machine-id、用户路径及常见密码/token 键值。`--no-redact` 仅适合本机排障，切勿公开分享原始报告。

报告面向服务器优化人员，包含 CPU/主板/BIOS、内存与提交额度、Dirty/Writeback/Slab、Swap 与 zram/zswap、vm 内核参数、PSI 内存/IO 压力、透明大页、网络队列、文件句柄限制、磁盘使用率、系统/内核、OpenSSL、IPv4/IPv6、路由和 DNS。输出是采集时快照，不直接给出调优结论；应结合业务负载、内核版本和云厂商文档评估。脚本仅读取有限的 `/etc` 文件，不读取 shadow、私钥、历史记录或应用密钥。

## 兼容和降级

Bash、`/proc`、`/sys` 与基础 POSIX 工具是核心要求；`ip`、`lsblk`、`lscpu`、`free`、`openssl`、`swapon`、`sysctl`、`dmidecode`、`resolvectl`、`nmcli` 缺失时会显示 N/A 或采用有限回退。不会执行 `apt install`，因此可在国际网络受限时运行。虚拟机、容器、非 root 用户可能无法提供 DMI 或完整网络信息。

## 开发

```sh
bash -n bin/system-report.sh
./tests/test-system-report.sh
```

公开仓库不应提交真实报告、凭据、代理配置或数据库。MIT License。
