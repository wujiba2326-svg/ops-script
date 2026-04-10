# collect_logs

日志收集工具，自动发现各服务日志路径，截取最后 20000 行，按服务类型归档。

提供 Shell 和 Go 两个版本，功能相同，Go 版无外部依赖，可单二进制部署。

---

## 功能

- 自动发现 PHP / Nginx / MySQL / Redis / MongoDB / Elasticsearch 的日志路径
- 截取每个日志文件最后 **20000 行**
- 按服务类型归档到以**执行时间命名**的目录，输出到 `out/`

---

## 输出目录结构

```text
out/log_collect_20260409_143022/
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

---

## 编译（Go 版）

需要 Go 1.18+。

```bash
# 编译为当前平台
go build -o collect_logs collect_logs.go

# 交叉编译 Linux amd64（Mac/Linux）
GOOS=linux GOARCH=amd64 go build -o collect_logs collect_logs.go

# 交叉编译 Linux amd64（Windows PowerShell）
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -o file/x8664/collect_logs_linux collect_logs.go

# 交叉编译 Linux arm64（Windows PowerShell）
$env:GOOS="linux"; $env:GOARCH="arm64"; go build -o file/arm64/collect_logs_linux collect_logs.go
```

---

## 使用

```bash
# Go 版（需要 root 或对应日志读权限）
sudo ./collect_logs

# Shell 版
chmod +x collect_logs.sh
sudo ./collect_logs.sh

# 仅查看日志路径，不收集
chmod +x find_log_paths.sh
./find_log_paths.sh
```

---

## 支持的服务及日志发现来源

| 服务          | 发现来源                                                     |
| ------------- | ------------------------------------------------------------ |
| PHP           | `php -i`、`php-fpm.conf`、`www.conf`、`/var/log`、`/home/logs/fpm`、`/usr/local/php/var/log` |
| Nginx         | `nginx -V` 推导配置目录、`/var/log/nginx`                    |
| MySQL         | `SELECT @@log_error`、`my.cnf`、`/var/log`、`/var/log/mysql`、`/var/lib/mysql` |
| Redis         | `redis-cli CONFIG GET logfile`、`redis.conf`、`/var/log`、`/var/log/redis` |
| MongoDB       | 进程参数、`mongod.conf`、`lsof`、`/var/log`                  |
| Elasticsearch | 进程参数 `es.path.home`、`/var/log/elasticsearch`            |

---

## 归档排除规则

以下文件自动跳过，只收集当前活跃日志：

- `*.gz` / `*.bz2` / `*.zip` — 压缩文件
- `*.1` / `*.2` — logrotate 数字轮转
- `*-YYYYMMDD*` / `*-YYYY-MM-DD*` — 日期命名轮转
