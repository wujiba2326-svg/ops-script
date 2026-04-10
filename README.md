# ops-script

运维日志收集工具集。

---

## 脚本说明

| 文件                | 用途                                            |
| ------------------- | ----------------------------------------------- |
| `find_log_paths.sh` | 动态发现各服务当前日志路径（排除压缩/归档文件） |
| `collect_logs.sh`   | Shell 版：按服务类型收集最后 20000 行日志       |
| `collect_logs.go`   | Go 版：同上，无外部依赖，跨平台单二进制         |

---

## collect_logs.go

### 功能

- 自动发现 PHP / Nginx / MySQL / Redis / MongoDB / Elasticsearch 的日志路径
- 截取每个日志文件最后 **20000 行**
- 按服务类型归档到以**执行时间命名**的目录

### 输出目录结构

```text
log_collect_20260409_143022/
├── php/
│   └── php_error.log
├── nginx/
│   ├── access.log
│   └── error.log
├── mysql/
│   ├── mysqld.err
│   └── slow.log
├── redis/
│   └── redis-server.log
├── mongodb/
│   └── mongod.log
├── elasticsearch/
│   └── elasticsearch.log
└── other/
    └── app.log
```

### 编译

需要 Go 1.18+。

```bash
# 编译为当前平台
go build -o collect_logs collect_logs.go

# 交叉编译 Linux amd64（Mac/Linux）
GOOS=linux GOARCH=amd64 go build -o collect_logs collect_logs.go

# 交叉编译 Linux amd64（Windows PowerShell，部署到 x86-64 服务器）
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -o file/x8664/collect_logs_linux collect_logs.go

# 交叉编译 Linux arm64（Windows PowerShell，部署到 ARM64 服务器 / Apple Silicon WSL）
$env:GOOS="linux"; $env:GOARCH="arm64"; go build -o file/arm64/collect_logs_linux collect_logs.go

```

### 使用

```bash
# 直接运行（需要 root 或对应日志读权限）
./collect_logs

# 查看产出目录
ls log_collect_*/
```

### 权限说明

部分日志（如 `/var/log/mysql/`、`/var/lib/mysql/*.err`）默认只有 root 或对应服务用户可读。建议以 root 执行：

```bash
sudo ./collect_logs
```

---

## analyze_logs.go

日志智能分析工具，读取 `collect_logs` 产出的目录，逐服务发送给大模型诊断，最终输出中文汇总报告。支持 **MiniMax** 和 **Claude** 两个 provider。

### 分析能力

- 自动读取 `out/` 下最新的收集目录（或手动指定）
- 按服务分组，每组单独发一次请求，针对性分析
- 超长日志自动裁剪（取首尾各半，保留上下文，单次上限 120 000 字符）
- 所有服务分析完后输出**全局汇总**：最严重问题、各服务健康状态、优先处理建议

### Provider 说明

| Provider  | 环境变量            | 默认模型             |
| --------- | ------------------- | -------------------- |
| `minimax` | `MINIMAX_API_KEY`   | MiniMax-Text-01      |
| `claude`  | `CLAUDE_API_KEY`    | claude-sonnet-4-6    |

### 前置条件

根据使用的 provider 设置对应环境变量：

```bash
# 使用 MiniMax
export MINIMAX_API_KEY=your_key_here

# 使用 Claude
export CLAUDE_API_KEY=your_key_here
```

### 编译 analyze_logs

```bash
go build -o analyze_logs analyze_logs.go


# 交叉编译 Linux amd64（Windows PowerShell，部署到 x86-64 服务器）
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -o file/x8664/analyze_logs analyze_logs.go

# 交叉编译 Linux arm64（Windows PowerShell，部署到 ARM64 服务器 / Apple Silicon WSL）
$env:GOOS="linux"; $env:GOARCH="arm64"; go build -o file/arm64/analyze_logs analyze_logs.go
```

### 运行

```bash
# 使用 MiniMax（默认），自动分析 out/ 下最新目录
./analyze_logs

# 使用 Claude
./analyze_logs --provider claude

# 指定日志目录
./analyze_logs --provider claude out/log_collect_20260410_144109

# 简写
./analyze_logs -p minimax out/log_collect_20260410_144109
```

### 输出示例

```text
分析目录: out/log_collect_20260410_144109

========== 分析服务: php ==========
- 时间范围：2025-07-23 09:28 ~ 09:59
- 主要问题：
  · PHP Fatal error：Composer 要求 PHP >= 8.2.0，当前为 7.4.33
  · upstream timed out：FastCGI 连接超时
- 建议：
  · 将 PHP 版本升级至 8.2+，或降级对应 Composer 依赖
  · 检查 php-fpm 进程状态及 max_children 配置

========== 分析服务: nginx ==========
...

========== 全局汇总 ==========
...
```

---

## find_log_paths.sh / collect_logs.sh

### 使用方式

```bash
chmod +x find_log_paths.sh collect_logs.sh

# 仅查看日志路径，不收集
./find_log_paths.sh

# 收集日志（Shell 版）
./collect_logs.sh
```

### 支持的服务

| 服务            | 发现来源                                                      |
| --------------- | ------------------------------------------------------------- |
| PHP             | `php -i`、`php-fpm.conf`、`www.conf`、`/var/log`              |
| Nginx           | `nginx -V` 推导配置目录、`/var/log/nginx`                     |
| MySQL           | `SELECT @@log_error`、`my.cnf`、`/var/log`、`/var/lib/mysql`  |
| Redis           | `redis-cli CONFIG GET logfile`、`redis.conf`、`/var/log`      |
| MongoDB         | 进程参数、`mongod.conf`、`lsof`、`/var/log`                   |
| Elasticsearch   | 进程参数 `es.path.home`、`/var/log/elasticsearch`             |

### 归档排除规则

以下文件会被自动跳过，只保留当前活跃日志：

- `*.gz` / `*.bz2` / `*.zip` — 压缩文件
- `*.1` / `*.2` — logrotate 数字轮转
- `*-YYYYMMDD*` / `*-YYYY-MM-DD*` — 日期命名轮转
