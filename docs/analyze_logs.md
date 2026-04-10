# analyze_logs

日志智能分析工具，读取 `collect_logs` 产出的目录，逐服务调用大模型诊断，生成中文分析报告并保存为 Markdown 文件。

---

## 功能

- 自动读取 `out/` 下最新的收集目录（或手动指定）
- 按服务分组，每组单独发一次请求，针对性分析
- 超长日志自动裁剪（取首尾各半，保留上下文，单次上限 120 000 字符）
- 所有服务分析完后输出**全局汇总**：最严重问题、各服务健康状态、优先处理建议
- 分析结果自动保存为 `out/<收集目录名>_report.md`

---

## Provider

配置统一写在 `config.json`（不入库，从 `config.example.json` 复制），`api_key` 也可用环境变量覆盖。

| Provider  | 协议       | 模型              | 环境变量覆盖 api_key |
| --------- | ---------- | ----------------- | -------------------- |
| `minimax` | anthropic  | MiniMax-M2.7      | `MINIMAX_API_KEY`    |
| `claude`  | openai     | claude-sonnet-4-6 | `CLAUDE_API_KEY`     |

---

## 配置

```bash
cp config.example.json config.json
# 编辑 config.json，填入 api_key
```

`config.json` 结构：

```json
{
  "minimax": {
    "api_key": "your_key",
    "base_url": "https://api.minimax.io/anthropic/v1/messages",
    "model": "MiniMax-M2.7",
    "max_tokens": 4096,
    "protocol": "anthropic"
  },
  "claude": {
    "api_key": "your_key",
    "base_url": "http://your-proxy/v1/chat/completions",
    "model": "claude-sonnet-4-6",
    "max_tokens": 2048,
    "protocol": "openai"
  }
}
```

新增 provider 只需在 `config.json` 加一个 key，代码不用改。

---

## 编译

```bash
# 编译为当前平台
go build -o analyze_logs analyze_logs.go

# 交叉编译 Linux amd64（Windows PowerShell）
$env:GOOS="linux"; $env:GOARCH="amd64"; go build -o file/x8664/analyze_logs analyze_logs.go

# 交叉编译 Linux arm64（Windows PowerShell）
$env:GOOS="linux"; $env:GOARCH="arm64"; go build -o file/arm64/analyze_logs analyze_logs.go
```

---

## 使用

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

---

## 输出

终端实时打印分析进度，完成后报告保存至：

```text
out/log_collect_20260410_144109_report.md
```
