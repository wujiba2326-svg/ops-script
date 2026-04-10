package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

const maxChunkBytes = 120000 // 单次发送的最大字符数，留余量给 prompt

// ===== Provider 配置 =====

type ProviderConfig struct {
	APIKey    string `json:"api_key"`
	BaseURL   string `json:"base_url"`
	Model     string `json:"model"`
	MaxTokens int    `json:"max_tokens"`
	Protocol  string `json:"protocol"` // "openai" 或 "anthropic"
}

type Provider struct {
	Name string
	ProviderConfig
}

// 从 config.json 加载，环境变量 <PROVIDER>_API_KEY 可覆盖 api_key
func loadProvider(name string) (Provider, error) {
	data, err := os.ReadFile("config.json")
	if err != nil {
		return Provider{}, fmt.Errorf("读取 config.json 失败: %w", err)
	}

	var configs map[string]ProviderConfig
	if err := json.Unmarshal(data, &configs); err != nil {
		return Provider{}, fmt.Errorf("解析 config.json 失败: %w", err)
	}

	cfg, ok := configs[name]
	if !ok {
		var available []string
		for k := range configs {
			available = append(available, k)
		}
		return Provider{}, fmt.Errorf("config.json 中不存在 provider %q，可选: %s", name, strings.Join(available, ", "))
	}

	// 环境变量优先
	envKey := strings.ToUpper(name) + "_API_KEY"
	if v := os.Getenv(envKey); v != "" {
		cfg.APIKey = v
	}

	if cfg.APIKey == "" {
		return Provider{}, fmt.Errorf("api_key 未配置，请在 config.json 填写或设置环境变量 %s", envKey)
	}

	return Provider{Name: name, ProviderConfig: cfg}, nil
}

// ===== OpenAI 兼容格式 =====

type OAIMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type OAIRequest struct {
	Model     string       `json:"model"`
	Messages  []OAIMessage `json:"messages"`
	MaxTokens int          `json:"max_tokens,omitempty"`
}

type OAIResponse struct {
	Choices []struct {
		Message OAIMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
	BaseResp *struct {
		StatusCode int    `json:"status_code"`
		StatusMsg  string `json:"status_msg"`
	} `json:"base_resp,omitempty"`
}

// ===== Anthropic 格式 =====

type AnthropicRequest struct {
	Model     string             `json:"model"`
	MaxTokens int                `json:"max_tokens"`
	System    string             `json:"system"`
	Messages  []AnthropicMessage `json:"messages"`
}

type AnthropicMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type AnthropicResponse struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// ===== 发送请求 =====

const systemPrompt = "你是一个运维专家，负责分析服务器日志，找出异常、错误、性能问题，并给出简明的中文诊断报告。"

func doPost(url, apiKey string, reqBody any) ([]byte, error) {
	body, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}
	httpReq, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func callProvider(p Provider, prompt string) (string, error) {
	maxTok := p.MaxTokens
	if maxTok <= 0 {
		maxTok = 2048
	}

	if p.Protocol == "anthropic" {
		req := AnthropicRequest{
			Model:     p.Model,
			MaxTokens: maxTok,
			System:    systemPrompt,
			Messages:  []AnthropicMessage{{Role: "user", Content: prompt}},
		}
		data, err := doPost(p.BaseURL, p.APIKey, req)
		if err != nil {
			return "", err
		}
		var resp AnthropicResponse
		if err := json.Unmarshal(data, &resp); err != nil {
			return "", fmt.Errorf("解析响应失败: %s", string(data))
		}
		if resp.Error != nil {
			return "", fmt.Errorf("API 错误: %s", resp.Error.Message)
		}
		for _, block := range resp.Content {
			if block.Type == "text" {
				return block.Text, nil
			}
		}
		return "", fmt.Errorf("空响应: %s", string(data))
	}

	// openai 兼容
	req := OAIRequest{
		Model:     p.Model,
		MaxTokens: maxTok,
		Messages: []OAIMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: prompt},
		},
	}
	data, err := doPost(p.BaseURL, p.APIKey, req)
	if err != nil {
		return "", err
	}
	var resp OAIResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return "", fmt.Errorf("解析响应失败: %s", string(data))
	}
	if resp.Error != nil {
		return "", fmt.Errorf("API 错误: %s", resp.Error.Message)
	}
	if resp.BaseResp != nil && resp.BaseResp.StatusCode != 0 {
		return "", fmt.Errorf("API 错误(%d): %s", resp.BaseResp.StatusCode, resp.BaseResp.StatusMsg)
	}
	if len(resp.Choices) == 0 {
		return "", fmt.Errorf("空响应: %s", string(data))
	}
	return resp.Choices[0].Message.Content, nil
}

// ===== 读取日志文件 =====

func readFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(data)
}

// 超长内容只取首尾，保留上下文
func trimContent(content string, maxBytes int) string {
	if len(content) <= maxBytes {
		return content
	}
	half := maxBytes / 2
	return content[:half] + "\n\n... [中间内容已省略] ...\n\n" + content[len(content)-half:]
}

// ===== 主流程 =====

func main() {
	// 解析参数：[--provider minimax|claude] [logDir]
	providerName := "minimax"
	logDir := ""

	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--provider", "-p":
			if i+1 < len(args) {
				providerName = args[i+1]
				i++
			}
		default:
			if logDir == "" {
				logDir = args[i]
			}
		}
	}

	p, err := loadProvider(providerName)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// 自动找最新目录
	if logDir == "" {
		entries, err := os.ReadDir("out")
		if err != nil || len(entries) == 0 {
			fmt.Fprintln(os.Stderr, "未找到 out/ 目录，请指定日志目录作为参数")
			os.Exit(1)
		}
		logDir = filepath.Join("out", entries[len(entries)-1].Name())
	}

	// 报告输出路径：与日志目录同级，文件名加 _report.md
	reportPath := logDir + "_report.md"

	fmt.Printf("Provider  : %s (%s)\n", p.Name, p.Model)
	fmt.Printf("分析目录  : %s\n", logDir)
	fmt.Printf("报告文件  : %s\n\n", reportPath)

	var report strings.Builder
	report.WriteString(fmt.Sprintf("# 日志分析报告\n\n"))
	report.WriteString(fmt.Sprintf("- **分析目录**: %s\n", logDir))
	report.WriteString(fmt.Sprintf("- **Provider**: %s (%s)\n", p.Name, p.Model))
	report.WriteString(fmt.Sprintf("- **生成时间**: %s\n\n", filepath.Base(logDir)))

	// 收集所有日志文件，按服务分组
	type logFile struct {
		service string
		path    string
		name    string
	}
	var files []logFile

	_ = filepath.WalkDir(logDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(logDir, path)
		parts := strings.SplitN(rel, string(filepath.Separator), 2)
		service := "other"
		if len(parts) == 2 {
			service = parts[0]
		}
		files = append(files, logFile{service: service, path: path, name: d.Name()})
		return nil
	})

	// 按服务分组
	groups := map[string][]logFile{}
	for _, f := range files {
		groups[f.service] = append(groups[f.service], f)
	}

	// 逐服务分析
	var summaries []string

	for service, logs := range groups {
		fmt.Printf("========== 分析服务: %s ==========\n", service)

		var combined strings.Builder
		for _, lf := range logs {
			content := readFile(lf.path)
			if strings.TrimSpace(content) == "" {
				continue
			}
			combined.WriteString(fmt.Sprintf("\n\n### 文件: %s\n", lf.name))
			combined.WriteString(trimContent(content, maxChunkBytes/len(logs)+1000))
		}

		logContent := combined.String()
		if strings.TrimSpace(logContent) == "" {
			fmt.Printf("  (无内容，跳过)\n\n")
			continue
		}
		logContent = trimContent(logContent, maxChunkBytes)

		prompt := fmt.Sprintf(`请分析以下【%s】服务的日志，重点找出：
1. 错误和异常（error/fatal/critical/exception）
2. 性能问题（超时、慢请求）
3. 时间范围（最早和最晚的日志时间）
4. 总体健康状况评估

请用中文给出简明诊断报告，格式：
- 时间范围：
- 主要问题：（列点）
- 建议：（列点）

日志内容：
%s`, service, logContent)

		result, err := callProvider(p, prompt)
		if err != nil {
			fmt.Printf("  [错误] %v\n\n", err)
			continue
		}

		fmt.Println(result)
		fmt.Println()
		summaries = append(summaries, fmt.Sprintf("## %s\n\n%s", service, result))
		report.WriteString(fmt.Sprintf("## %s\n\n%s\n\n", service, result))
	}

	// 全局汇总
	if len(summaries) > 0 {
		fmt.Println("========== 全局汇总 ==========")
		allResults := strings.Join(summaries, "\n\n")
		allResults = trimContent(allResults, maxChunkBytes)

		prompt := fmt.Sprintf(`以下是各服务的日志诊断报告，请给出一份整体汇总：
1. 最严重的问题
2. 各服务健康状态一览表
3. 优先处理建议

%s`, allResults)

		summary, err := callProvider(p, prompt)
		if err != nil {
			fmt.Printf("[错误] 汇总失败: %v\n", err)
		} else {
			fmt.Println(summary)
			report.WriteString(fmt.Sprintf("## 全局汇总\n\n%s\n", summary))
		}
	}

	// 写入 MD 文件
	if err := os.WriteFile(reportPath, []byte(report.String()), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "写入报告失败: %v\n", err)
	} else {
		fmt.Printf("\n报告已保存: %s\n", reportPath)
	}
}
