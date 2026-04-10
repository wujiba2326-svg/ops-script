# ops-script

运维日志收集与分析工具集。

---

## 文档

- [collect_logs](docs/collect_logs.md) — 日志收集（Shell / Go），自动发现各服务日志，截取最后 20000 行归档
- [analyze_logs](docs/analyze_logs.md) — 日志分析（Go + 大模型），逐服务诊断，生成 Markdown 报告

---

## 文件说明

| 文件                   | 用途                                        |
| ---------------------- | ------------------------------------------- |
| `find_log_paths.sh`    | 动态发现各服务当前日志路径（不收集）        |
| `collect_logs.sh`      | Shell 版日志收集                            |
| `collect_logs.go`      | Go 版日志收集，无外部依赖，跨平台单二进制   |
| `analyze_logs.go`      | Go 版日志分析，调用大模型输出诊断报告       |
| `config.example.json`  | analyze_logs provider 配置模板              |
