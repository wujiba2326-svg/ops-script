#!/usr/bin/env bash
################################################################################
# 动态查找日志路径 - 只输出路径
################################################################################

echo "=========================================="
echo "动态日志路径查找"
echo "=========================================="

# ==================== PHP ====================
echo ""
echo "[PHP]"

# 从 php.ini
if command -v php >/dev/null 2>&1; then
    php -i 2>/dev/null | grep "^error_log" | awk '{print $3}' | grep -v "no value"
fi

# 从 php-fpm 配置
find /etc -name "php-fpm.conf" -o -name "www.conf" 2>/dev/null | while read conf; do
    grep -E "^error_log|^slowlog|^access.log" "$conf" 2>/dev/null | awk '{print $3}'
done

# 扫描目录
find /var/log -maxdepth 2 -name "*php*.log" -o -name "*fpm*.log" 2>/dev/null

# ==================== Nginx ====================
echo ""
echo "[Nginx]"

# 从配置
if command -v nginx >/dev/null 2>&1; then
    nginx_conf=$(nginx -V 2>&1 | grep -oE 'conf-path=[^ ]+' | cut -d= -f2 || echo "/etc/nginx/nginx.conf")
    
    if [[ -f "$nginx_conf" ]]; then
        find $(dirname "$nginx_conf") -name "*.conf" 2>/dev/null | xargs grep -hE "access_log|error_log" 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';'
    fi
fi

# 扫描目录
find /var/log/nginx -type f -name "*.log" 2>/dev/null

# ==================== MySQL ====================
echo ""
echo "[MySQL]"

# 从 MySQL 查询
if command -v mysql >/dev/null 2>&1; then
    mysql -e "SELECT @@log_error;" 2>/dev/null | tail -1
    mysql -e "SELECT @@slow_query_log_file;" 2>/dev/null | tail -1
    mysql -e "SELECT @@general_log_file;" 2>/dev/null | tail -1
fi

# 从配置
for cnf in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
    [[ -f "$cnf" ]] && grep -E "^log-error|^log_error|^slow_query_log_file" "$cnf" 2>/dev/null | awk -F= '{print $2}' | tr -d ' "'
done

# 扫描目录
find /var/log -maxdepth 2 -name "*mysql*.log" -o -name "*mariadb*.log" 2>/dev/null
find /var/lib/mysql -maxdepth 1 -name "*.err" 2>/dev/null

# ==================== Redis ====================
echo ""
echo "[Redis]"

# 从 redis-cli
if command -v redis-cli >/dev/null 2>&1; then
    redis-cli CONFIG GET logfile 2>/dev/null | tail -1
fi

# 从配置
for conf in /etc/redis/redis.conf /etc/redis.conf; do
    [[ -f "$conf" ]] && grep "^logfile" "$conf" 2>/dev/null | awk '{print $2}' | tr -d '"'
done

# 扫描目录
find /var/log -maxdepth 2 -name "*redis*.log" 2>/dev/null

# ==================== MongoDB ====================
echo ""
echo "[MongoDB]"

# 从进程
mongo_pid=$(pgrep mongod 2>/dev/null | head -1)
if [[ -n "$mongo_pid" ]]; then
    # 从配置
    mongo_conf=$(ps -p $mongo_pid -o args= 2>/dev/null | grep -oE '\-f [^ ]+|\-\-config [^ ]+' | awk '{print $2}')
    [[ -n "$mongo_conf" && -f "$mongo_conf" ]] && grep -A 10 "systemLog:" "$mongo_conf" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"'
    
    # 从 lsof
    lsof -p $mongo_pid 2>/dev/null | grep "\.log" | awk '{print $9}'
fi

# 从配置
for conf in /etc/mongod.conf /etc/mongodb.conf /usr/local/mongodb/config; do
    [[ -f "$conf" ]] && grep -A 10 "systemLog:" "$conf" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"'
done

# 扫描目录
find /var/log -maxdepth 2 -name "*mongo*.log" 2>/dev/null
find /usr/local/mongodb -maxdepth 2 -name "*.log" 2>/dev/null

# ==================== Elasticsearch ====================
echo ""
echo "[Elasticsearch]"

# 从进程
es_pid=$(pgrep -f "org.elasticsearch.bootstrap.Elasticsearch" 2>/dev/null | head -1)
if [[ -n "$es_pid" ]]; then
    es_home=$(ps -p $es_pid -o args= 2>/dev/null | grep -oE 'es.path.home=[^ ]+' | cut -d= -f2)
    [[ -n "$es_home" ]] && find "$es_home/logs" -maxdepth 1 -name "*.log" 2>/dev/null
fi

# 扫描目录
find /var/log/elasticsearch -name "*.log" 2>/dev/null
find /usr/local/elasticsearch/logs -name "*.log" 2>/dev/null

# ==================== 去重汇总 ====================
echo ""
echo "=========================================="
echo "[全部日志路径 - 去重]"
echo "=========================================="

{
    # PHP
    command -v php >/dev/null 2>&1 && php -i 2>/dev/null | grep "^error_log" | awk '{print $3}' | grep -v "no value"
    find /etc -name "php-fpm.conf" -o -name "www.conf" 2>/dev/null | xargs grep -hE "^error_log|^slowlog" 2>/dev/null | awk '{print $3}'
    find /var/log -maxdepth 2 -name "*php*.log" -o -name "*fpm*.log" 2>/dev/null
    
    # Nginx
    if command -v nginx >/dev/null 2>&1; then
        nginx_conf=$(nginx -V 2>&1 | grep -oE 'conf-path=[^ ]+' | cut -d= -f2 || echo "/etc/nginx/nginx.conf")
        [[ -f "$nginx_conf" ]] && find $(dirname "$nginx_conf") -name "*.conf" 2>/dev/null | xargs grep -hE "access_log|error_log" 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';'
    fi
    find /var/log/nginx -type f 2>/dev/null
    
    # MySQL
    command -v mysql >/dev/null 2>&1 && mysql -e "SELECT @@log_error; SELECT @@slow_query_log_file;" 2>/dev/null | tail -2
    for cnf in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
        [[ -f "$cnf" ]] && grep -E "^log-error|^log_error|^slow" "$cnf" 2>/dev/null | awk -F= '{print $2}' | tr -d ' "'
    done
    find /var/log -maxdepth 2 -name "*mysql*.log" -o -name "*mariadb*.log" 2>/dev/null
    find /var/lib/mysql -maxdepth 1 -name "*.err" 2>/dev/null
    
    # Redis
    command -v redis-cli >/dev/null 2>&1 && redis-cli CONFIG GET logfile 2>/dev/null | tail -1
    for conf in /etc/redis/redis.conf /etc/redis.conf; do
        [[ -f "$conf" ]] && grep "^logfile" "$conf" 2>/dev/null | awk '{print $2}' | tr -d '"'
    done
    find /var/log -maxdepth 2 -name "*redis*.log" 2>/dev/null
    
    # MongoDB
    mongo_pid=$(pgrep mongod 2>/dev/null | head -1)
    if [[ -n "$mongo_pid" ]]; then
        mongo_conf=$(ps -p $mongo_pid -o args= 2>/dev/null | grep -oE '\-f [^ ]+|\-\-config [^ ]+' | awk '{print $2}')
        [[ -f "$mongo_conf" ]] && grep -A 10 "systemLog:" "$mongo_conf" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"'
        lsof -p $mongo_pid 2>/dev/null | grep "\.log" | awk '{print $9}'
    fi
    find /var/log -maxdepth 2 -name "*mongo*.log" 2>/dev/null
    
    # ES
    es_pid=$(pgrep -f "org.elasticsearch.bootstrap.Elasticsearch" 2>/dev/null | head -1)
    if [[ -n "$es_pid" ]]; then
        es_home=$(ps -p $es_pid -o args= 2>/dev/null | grep -oE 'es.path.home=[^ ]+' | cut -d= -f2)
        [[ -n "$es_home" ]] && find "$es_home/logs" -maxdepth 1 -name "*.log" 2>/dev/null
    fi
    find /var/log/elasticsearch /usr/local/elasticsearch/logs -name "*.log" 2>/dev/null
    
} | grep -v "^$" | grep -v "stdout" | sort -u | while read log; do
    [[ -f "$log" ]] && echo "$log"
done