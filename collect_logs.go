package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const tailLines = 20000

// classifyLog 根据路径关键词判断服务类型
func classifyLog(path string) string {
	lower := strings.ToLower(path)
	switch {
	case strings.Contains(lower, "php") || strings.Contains(lower, "fpm"):
		return "php"
	case strings.Contains(lower, "nginx"):
		return "nginx"
	case strings.Contains(lower, "mysql") || strings.Contains(lower, "mariadb"):
		return "mysql"
	case strings.Contains(lower, "redis"):
		return "redis"
	case strings.Contains(lower, "mongo"):
		return "mongodb"
	case strings.Contains(lower, "elastic") || strings.Contains(lower, "/es/"):
		return "elasticsearch"
	default:
		return "other"
	}
}

// tailFile 读取文件最后 n 行，写入 dst
func tailFile(src, dst string, n int) (int, error) {
	f, err := os.Open(src)
	if err != nil {
		return 0, err
	}
	defer f.Close()

	// 先把所有行读进环形缓冲
	ring := make([]string, n)
	idx := 0
	total := 0
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	for scanner.Scan() {
		ring[idx%n] = scanner.Text()
		idx++
		total++
	}
	if err := scanner.Err(); err != nil {
		return 0, err
	}

	out, err := os.Create(dst)
	if err != nil {
		return 0, err
	}
	defer out.Close()

	w := bufio.NewWriter(out)
	count := total
	if count > n {
		count = n
	}
	start := idx - count
	for i := 0; i < count; i++ {
		fmt.Fprintln(w, ring[(start+i)%n])
	}
	return count, w.Flush()
}

// runCmd 执行命令，返回 stdout 各行（忽略 stderr）
func runCmd(name string, args ...string) []string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return nil
	}
	var lines []string
	for _, l := range strings.Split(string(out), "\n") {
		l = strings.TrimSpace(l)
		if l != "" {
			lines = append(lines, l)
		}
	}
	return lines
}

// commandExists 检查命令是否存在
func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

// findFiles 在 dir 内按 pattern 查找，排除归档文件
func findFiles(dir string, maxDepth int, patterns []string) []string {
	excludeSuffixes := []string{".gz", ".bz2", ".zip", ".1", ".2"}
	var result []string

	_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(dir, path)
		depth := len(strings.Split(rel, string(os.PathSeparator)))
		if d.IsDir() {
			if depth > maxDepth {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		// 排除归档
		for _, suf := range excludeSuffixes {
			if strings.HasSuffix(name, suf) {
				return nil
			}
		}
		// 排除日期轮转文件 (name-YYYYMMDD* 或 name-YYYY-MM-DD*)
		for _, seg := range strings.Split(name, "-") {
			if len(seg) == 8 && isDigits(seg) {
				return nil
			}
			if len(seg) == 4 && isDigits(seg) {
				return nil
			}
		}
		// 匹配 pattern
		for _, pat := range patterns {
			if matched, _ := filepath.Match(pat, name); matched {
				result = append(result, path)
				return nil
			}
		}
		return nil
	})
	return result
}

func isDigits(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// grepFile 从文件中提取匹配行的第 n 个字段（awk-like）
func grepFile(path, pattern string, fieldSep string, fieldIdx int) []string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	var result []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, pattern) || matchSimple(line, pattern) {
			var fields []string
			if fieldSep == "" {
				fields = strings.Fields(line)
			} else {
				fields = strings.Split(line, fieldSep)
			}
			if fieldIdx < len(fields) {
				v := strings.TrimSpace(fields[fieldIdx])
				v = strings.Trim(v, `"'`)
				if v != "" {
					result = append(result, v)
				}
			}
		}
	}
	return result
}

// matchSimple 简单前缀匹配（替代 grep -E 基础用法）
func matchSimple(line, pattern string) bool {
	return strings.HasPrefix(line, pattern)
}

// ============================================================
// 各服务日志路径发现
// ============================================================

func discoverPHP() []string {
	var paths []string

	// php -i
	if commandExists("php") {
		for _, line := range runCmd("php", "-i") {
			if strings.HasPrefix(line, "error_log") {
				parts := strings.Fields(line)
				if len(parts) >= 3 && parts[2] != "no" {
					paths = append(paths, parts[2])
				}
			}
		}
	}

	// php-fpm.conf / www.conf
	for _, confDir := range []string{"/etc"} {
		_ = filepath.WalkDir(confDir, func(p string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			n := d.Name()
			if n == "php-fpm.conf" || n == "www.conf" {
				for _, key := range []string{"error_log", "slowlog", "access.log"} {
					paths = append(paths, grepFile(p, key, " ", 2)...)
				}
			}
			return nil
		})
	}

	// 扫描目录
	paths = append(paths, findFiles("/var/log", 2, []string{"*php*.log", "*fpm*.log"})...)
	paths = append(paths, findFiles("/home/logs/fpm", 2, []string{"*.log"})...)
	paths = append(paths, findFiles("/usr/local/php/var/log", 2, []string{"*.log"})...)
	return paths
}

func discoverNginx() []string {
	var paths []string

	if commandExists("nginx") {
		lines := runCmd("nginx", "-V")
		var confPath string
		for _, l := range lines {
			if idx := strings.Index(l, "conf-path="); idx >= 0 {
				confPath = strings.SplitN(l[idx+len("conf-path="):], " ", 2)[0]
				break
			}
		}
		if confPath == "" {
			confPath = "/etc/nginx/nginx.conf"
		}
		if _, err := os.Stat(confPath); err == nil {
			confDir := filepath.Dir(confPath)
			_ = filepath.WalkDir(confDir, func(p string, d os.DirEntry, err error) error {
				if err != nil || d.IsDir() {
					return nil
				}
				if strings.HasSuffix(d.Name(), ".conf") {
					paths = append(paths, extractNginxLogPaths(p)...)
				}
				return nil
			})
		}
	}

	paths = append(paths, findFiles("/var/log/nginx", 1, []string{"*.log"})...)
	return paths
}

func extractNginxLogPaths(confFile string) []string {
	f, err := os.Open(confFile)
	if err != nil {
		return nil
	}
	defer f.Close()

	var result []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "access_log") || strings.HasPrefix(line, "error_log") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				p := strings.TrimSuffix(parts[1], ";")
				if strings.HasPrefix(p, "/") {
					result = append(result, p)
				}
			}
		}
	}
	return result
}

func discoverMySQL() []string {
	var paths []string

	if commandExists("mysql") {
		for _, q := range []string{"SELECT @@log_error;", "SELECT @@slow_query_log_file;"} {
			lines := runCmd("mysql", "-e", q)
			if len(lines) > 0 {
				paths = append(paths, lines[len(lines)-1])
			}
		}
	}

	for _, cnf := range []string{"/etc/my.cnf", "/etc/mysql/my.cnf", "/etc/mysql/mysql.conf.d/mysqld.cnf"} {
		if _, err := os.Stat(cnf); err == nil {
			for _, key := range []string{"log-error", "log_error", "slow_query_log_file"} {
				paths = append(paths, grepFile(cnf, key, "=", 1)...)
			}
		}
	}

	paths = append(paths, findFiles("/var/log", 2, []string{"*mysql*.log", "*mariadb*.log"})...)
	paths = append(paths, findFiles("/var/log/mysql", 2, []string{"*.log"})...)
	paths = append(paths, findFiles("/var/lib/mysql", 1, []string{"*.err"})...)
	return paths
}

func discoverRedis() []string {
	var paths []string

	if commandExists("redis-cli") {
		lines := runCmd("redis-cli", "CONFIG", "GET", "logfile")
		if len(lines) > 0 {
			paths = append(paths, lines[len(lines)-1])
		}
	}

	for _, conf := range []string{"/etc/redis/redis.conf", "/etc/redis.conf"} {
		if _, err := os.Stat(conf); err == nil {
			paths = append(paths, grepFile(conf, "logfile", " ", 1)...)
		}
	}

	paths = append(paths, findFiles("/var/log", 2, []string{"*redis*.log"})...)
	paths = append(paths, findFiles("/var/log/redis", 2, []string{"*.log"})...)
	return paths
}

func discoverMongoDB() []string {
	var paths []string

	pids := runCmd("pgrep", "mongod")
	if len(pids) > 0 {
		pid := pids[0]
		args := runCmd("ps", "-p", pid, "-o", "args=")
		if len(args) > 0 {
			parts := strings.Fields(args[0])
			for i, p := range parts {
				if (p == "-f" || p == "--config") && i+1 < len(parts) {
					confFile := parts[i+1]
					if _, err := os.Stat(confFile); err == nil {
						paths = append(paths, parseMongoConf(confFile)...)
					}
				}
			}
		}
		// lsof
		lsofLines := runCmd("lsof", "-p", pid)
		for _, l := range lsofLines {
			if strings.HasSuffix(l, ".log") {
				f := strings.Fields(l)
				if len(f) > 0 {
					paths = append(paths, f[len(f)-1])
				}
			}
		}
	}

	for _, conf := range []string{"/etc/mongod.conf", "/etc/mongodb.conf", "/usr/local/mongodb/config"} {
		if _, err := os.Stat(conf); err == nil {
			paths = append(paths, parseMongoConf(conf)...)
		}
	}

	paths = append(paths, findFiles("/var/log", 2, []string{"*mongo*.log"})...)
	paths = append(paths, findFiles("/usr/local/mongodb", 2, []string{"*.log"})...)
	return paths
}

func parseMongoConf(conf string) []string {
	f, err := os.Open(conf)
	if err != nil {
		return nil
	}
	defer f.Close()

	var result []string
	inSystemLog := false
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, "systemLog:") {
			inSystemLog = true
			continue
		}
		if inSystemLog {
			if strings.Contains(line, "path:") {
				parts := strings.SplitN(line, "path:", 2)
				if len(parts) == 2 {
					p := strings.TrimSpace(strings.Trim(parts[1], `"`))
					if p != "" {
						result = append(result, p)
					}
				}
				inSystemLog = false
			} else if !strings.HasPrefix(strings.TrimSpace(line), " ") && strings.TrimSpace(line) != "" {
				inSystemLog = false
			}
		}
	}
	return result
}

func discoverElasticsearch() []string {
	var paths []string

	pids := runCmd("pgrep", "-f", "org.elasticsearch.bootstrap.Elasticsearch")
	if len(pids) > 0 {
		args := runCmd("ps", "-p", pids[0], "-o", "args=")
		if len(args) > 0 {
			for _, seg := range strings.Fields(args[0]) {
				if strings.HasPrefix(seg, "es.path.home=") {
					esHome := strings.TrimPrefix(seg, "es.path.home=")
					paths = append(paths, findFiles(filepath.Join(esHome, "logs"), 1, []string{"*.log"})...)
				}
			}
		}
	}

	for _, dir := range []string{"/var/log/elasticsearch", "/usr/local/elasticsearch/logs"} {
		paths = append(paths, findFiles(dir, 1, []string{"*.log"})...)
	}
	return paths
}

// ============================================================
// 收集入口
// ============================================================

func collectAll(baseDir string) {
	allPaths := []string{}
	allPaths = append(allPaths, discoverPHP()...)
	allPaths = append(allPaths, discoverNginx()...)
	allPaths = append(allPaths, discoverMySQL()...)
	allPaths = append(allPaths, discoverRedis()...)
	allPaths = append(allPaths, discoverMongoDB()...)
	allPaths = append(allPaths, discoverElasticsearch()...)

	// 去重
	seen := make(map[string]struct{})
	var unique []string
	for _, p := range allPaths {
		p = strings.TrimSpace(p)
		if p == "" || p == "stdout" {
			continue
		}
		if _, ok := seen[p]; ok {
			continue
		}
		if fi, err := os.Stat(p); err != nil || fi.IsDir() {
			continue
		}
		seen[p] = struct{}{}
		unique = append(unique, p)
	}
	sort.Strings(unique)

	for _, logPath := range unique {
		service := classifyLog(logPath)
		destDir := filepath.Join(baseDir, service)
		if err := os.MkdirAll(destDir, 0755); err != nil {
			fmt.Fprintf(os.Stderr, "  [ERR] mkdir %s: %v\n", destDir, err)
			continue
		}
		destFile := filepath.Join(destDir, filepath.Base(logPath))
		n, err := tailFile(logPath, destFile, tailLines)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  [ERR] %s: %v\n", logPath, err)
			continue
		}
		fmt.Printf("  [OK] %-16s %s (%d lines) -> %s\n", service, logPath, n, destFile)
	}
}

func printTree(baseDir string) {
	_ = filepath.WalkDir(baseDir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(baseDir, path)
		fi, _ := d.Info()
		fmt.Printf("  %s  (%d bytes)\n", rel, fi.Size())
		return nil
	})
}


func main() {
	timestamp := time.Now().Format("20060102_150405")
	cwd, _ := os.Getwd()
	baseDir := filepath.Join(cwd, "out", "log_collect_"+timestamp)

	fmt.Println("==========================================")
	fmt.Println("日志收集开始")
	fmt.Printf("时间戳 : %s\n", timestamp)
	fmt.Printf("输出目录: %s\n", baseDir)
	fmt.Printf("截取行数: %d\n", tailLines)
	fmt.Println("==========================================")
	fmt.Println()

	if err := os.MkdirAll(baseDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "无法创建输出目录: %v\n", err)
		os.Exit(1)
	}

	collectAll(baseDir)

	fmt.Println()
	fmt.Println("==========================================")
	fmt.Println("收集完成，目录结构：")
	fmt.Println("==========================================")
	printTree(baseDir)
}
