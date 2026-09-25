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

### 一键运行优化脚本

以下命令会加载仓库中的最新优化脚本，并保留终端交互，因此可以选择场景、查看修改前后参数并输入 `APPLY` 确认：

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/server-optimizer.sh)
```

直接指定“科学上网服务器”场景：

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/server-optimizer.sh) --profile proxy
```

直接指定“游戏加速器”场景：

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/server-optimizer.sh) --profile game
```

需要实际应用修改时，仍必须显式加入 `--apply`，并输入 `APPLY`：

```sh
sudo bash <(curl -fsSL https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/server-optimizer.sh) --profile proxy --apply
```

没有 `curl` 时使用 `wget`：

```sh
bash <(wget -qO- https://raw.githubusercontent.com/HXHGTS/linux-system-report/main/bin/server-optimizer.sh) --profile game
```

> 一键命令会执行远程脚本。生产服务器建议先下载并检查脚本；优化应用前会先显示修改计划，备份成功且用户输入 `APPLY` 后才会修改。

### 生成优化建议

根据硬件和当前系统状态，选择服务器用途：

```sh
chmod +x bin/server-optimizer.sh
./bin/server-optimizer.sh
```

运行时选择：

```text
1. 科学上网服务器
2. 游戏加速器
```

也可以直接指定场景：

```sh
./bin/server-optimizer.sh --profile proxy
./bin/server-optimizer.sh --profile game
```

脚本会先检测并展示多个优化类别，而不只检查内核：网络链路与队列、资源限制、Swap/zram、磁盘与文件系统、服务与监听、日志、DNS、时间同步、软件包和安全配置。每类会展示当前状态、优化目标、风险和是否可自动应用。

其中，网络路由/MTU、防火墙、服务启停、DNS/NTP、磁盘分区与挂载、Swap 创建删除、日志清理、软件包升级、SSH 和安全策略默认仅给出建议，不会自动执行；只有固定 allowlist 的低风险 sysctl 参数进入“当前值 → 修改后值”应用计划。

脚本会先显示每个可应用参数的“当前值 → 修改后值”、修改原因和影响范围，然后询问是否应用。

默认是计划模式，不修改系统。确认要修改时必须在交互终端以 root 执行：

```sh
sudo ./bin/server-optimizer.sh --profile proxy --apply
# 或
sudo ./bin/server-optimizer.sh --profile game --apply
```

应用前会要求输入精确确认词 `APPLY`，并在 `/var/backups/server-optimizer/时间戳-PID/` 创建权限为 0700 的备份，备份专用 sysctl 配置和原始参数值。备份成功后才写入 `/etc/sysctl.d/99-server-optimizer.conf`，逐项应用并验证；失败时会尝试自动回滚。

回滚示例：

```sh
sudo ./bin/server-optimizer.sh --rollback /var/backups/server-optimizer/备份目录
```

回滚同样需要 root、交互终端和输入 `ROLLBACK` 确认。脚本不会修改防火墙、路由、MTU、拥塞控制或服务配置。建议结合业务并发、带宽、延迟、丢包、云厂商限制和压测结果，再由管理员决定是否调整参数。

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
