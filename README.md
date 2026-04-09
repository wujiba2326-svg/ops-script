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

# 交叉编译 Linux amd64（在 Windows/Mac 上构建）
GOOS=linux GOARCH=amd64 go build -o collect_logs collect_logs.go
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
