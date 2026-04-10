#!/usr/bin/env bash
################################################################################
# 动态查找日志路径 - 排除压缩和归档文件
################################################################################

echo "=========================================="
echo "动态日志路径查找 (排除压缩归档)"
echo "=========================================="

# ==================== PHP ====================
echo ""
echo "[PHP]"

if command -v php >/dev/null 2>&1; then
    php -i 2>/dev/null | grep "^error_log" | awk '{print $3}' | grep -v "no value"
fi

find /etc -name "php-fpm.conf" -o -name "www.conf" 2>/dev/null | while read conf; do
    grep -E "^error_log|^slowlog|^access.log" "$conf" 2>/dev/null | awk '{print $3}'
done

find /var/log -maxdepth 2 \( -name "*php*.log" -o -name "*fpm*.log" \) \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    ! -name "*.zip" \
    ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
    ! -name "*.1" \
    ! -name "*.2" \
    2>/dev/null

# Remi 仓库多版本 PHP
for _ver in php73 php74 php80 php81 php82 php83; do
    find "/var/opt/remi/${_ver}/log" -maxdepth 2 -name "*.log" \
        ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
        ! -name "*.1" ! -name "*.2" 2>/dev/null
done

# ==================== Nginx ====================
echo ""
echo "[Nginx]"

if command -v nginx >/dev/null 2>&1; then
    nginx_conf=$(nginx -V 2>&1 | grep -oE 'conf-path=[^ ]+' | cut -d= -f2 || echo "/etc/nginx/nginx.conf")
    [[ -f "$nginx_conf" ]] && find $(dirname "$nginx_conf") -name "*.conf" 2>/dev/null | xargs grep -hE "access_log|error_log" 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';'
fi

find /var/log/nginx -type f -name "*.log" \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    ! -name "*.zip" \
    ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
    ! -name "*.1" \
    ! -name "*.2" \
    2>/dev/null

# ==================== MySQL ====================
echo ""
echo "[MySQL]"

if command -v mysql >/dev/null 2>&1; then
    mysql -e "SELECT @@log_error;" 2>/dev/null | tail -1
    mysql -e "SELECT @@slow_query_log_file;" 2>/dev/null | tail -1
fi

for cnf in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
    [[ -f "$cnf" ]] && grep -E "^log-error|^log_error|^slow_query_log_file" "$cnf" 2>/dev/null | awk -F= '{print $2}' | tr -d ' "'
done

find /var/log -maxdepth 2 \( -name "*mysql*.log" -o -name "*mariadb*.log" \) \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
    2>/dev/null
    
find /var/lib/mysql -maxdepth 1 -name "*.err" 2>/dev/null

# ==================== Redis ====================
echo ""
echo "[Redis]"

if command -v redis-cli >/dev/null 2>&1; then
    redis-cli CONFIG GET logfile 2>/dev/null | tail -1
fi

for conf in /etc/redis/redis.conf /etc/redis.conf; do
    [[ -f "$conf" ]] && grep "^logfile" "$conf" 2>/dev/null | awk '{print $2}' | tr -d '"'
done

find /var/log -maxdepth 2 -name "*redis*.log" \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
    2>/dev/null

# ==================== MongoDB ====================
echo ""
echo "[MongoDB]"

mongo_pid=$(pgrep mongod 2>/dev/null | head -1)
if [[ -n "$mongo_pid" ]]; then
    mongo_conf=$(ps -p $mongo_pid -o args= 2>/dev/null | grep -oE '\-f [^ ]+|\-\-config [^ ]+' | awk '{print $2}')
    [[ -n "$mongo_conf" && -f "$mongo_conf" ]] && grep -A 10 "systemLog:" "$mongo_conf" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"'
    
    lsof -p $mongo_pid 2>/dev/null | grep "\.log" | awk '{print $9}' | grep -v "\.gz"
fi

for conf in /etc/mongod.conf /etc/mongodb.conf /usr/local/mongodb/config; do
    [[ -f "$conf" ]] && grep -A 10 "systemLog:" "$conf" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"'
done

find /var/log -maxdepth 2 -name "*mongo*.log" \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
    2>/dev/null
    
find /usr/local/mongodb -maxdepth 2 -name "*.log" \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    2>/dev/null

# ==================== Elasticsearch ====================
echo ""
echo "[Elasticsearch]"

es_pid=$(pgrep -f "org.elasticsearch.bootstrap.Elasticsearch" 2>/dev/null | head -1)
if [[ -n "$es_pid" ]]; then
    es_home=$(ps -p $es_pid -o args= 2>/dev/null | grep -oE 'es.path.home=[^ ]+' | cut -d= -f2)
    [[ -n "$es_home" ]] && find "$es_home/logs" -maxdepth 1 -name "*.log" \
        ! -name "*.gz" \
        ! -name "*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" \
        2>/dev/null
fi

find /var/log/elasticsearch /usr/local/elasticsearch/logs -name "*.log" \
    ! -name "*.gz" \
    ! -name "*.bz2" \
    ! -name "*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" \
    2>/dev/null

# ==================== 去重汇总 ====================
echo ""
echo "=========================================="
echo "[全部日志路径 - 去重 - 仅当前日志]"
echo "=========================================="

{
    # PHP
    command -v php >/dev/null 2>&1 && php -i 2>/dev/null | grep "^error_log" | awk '{print $3}' | grep -v "no value"
    find /etc -name "php-fpm.conf" -o -name "www.conf" 2>/dev/null | xargs grep -hE "^error_log|^slowlog" 2>/dev/null | awk '{print $3}'
    find /var/log -maxdepth 2 \( -name "*php*.log" -o -name "*fpm*.log" \) ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" ! -name "*.1" ! -name "*.2" 2>/dev/null
    for _ver in php73 php74 php80 php81 php82 php83; do
        find "/var/opt/remi/${_ver}/log" -maxdepth 2 -name "*.log" ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" ! -name "*.1" ! -name "*.2" 2>/dev/null
    done

    # Nginx
    if command -v nginx >/dev/null 2>&1; then
        nginx_conf=$(nginx -V 2>&1 | grep -oE 'conf-path=[^ ]+' | cut -d= -f2 || echo "/etc/nginx/nginx.conf")
        [[ -f "$nginx_conf" ]] && find $(dirname "$nginx_conf") -name "*.conf" 2>/dev/null | xargs grep -hE "access_log|error_log" 2>/dev/null | grep -v "#" | awk '{print $2}' | tr -d ';'
    fi
    find /var/log/nginx -type f -name "*.log" ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" ! -name "*.1" 2>/dev/null
    
    # MySQL
    command -v mysql >/dev/null 2>&1 && mysql -e "SELECT @@log_error; SELECT @@slow_query_log_file;" 2>/dev/null | tail -2
    for cnf in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
        [[ -f "$cnf" ]] && grep -E "^log-error|^log_error|^slow" "$cnf" 2>/dev/null | awk -F= '{print $2}' | tr -d ' "'
    done
    find /var/log -maxdepth 2 \( -name "*mysql*.log" -o -name "*mariadb*.log" \) ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" 2>/dev/null
    find /var/lib/mysql -maxdepth 1 -name "*.err" 2>/dev/null
    
    # Redis
    command -v redis-cli >/dev/null 2>&1 && redis-cli CONFIG GET logfile 2>/dev/null | tail -1
    for conf in /etc/redis/redis.conf /etc/redis.conf; do
        [[ -f "$conf" ]] && grep "^logfile" "$conf" 2>/dev/null | awk '{print $2}' | tr -d '"'
    done
    find /var/log -maxdepth 2 -name "*redis*.log" ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" 2>/dev/null
    
    # MongoDB
    mongo_pid=$(pgrep mongod 2>/dev/null | head -1)
    if [[ -n "$mongo_pid" ]]; then
        mongo_conf=$(ps -p $mongo_pid -o args= 2>/dev/null | grep -oE '\-f [^ ]+|\-\-config [^ ]+' | awk '{print $2}')
        [[ -f "$mongo_conf" ]] && grep -A 10 "systemLog:" "$mongo_conf" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"'
        lsof -p $mongo_pid 2>/dev/null | grep "\.log" | awk '{print $9}' | grep -v "\.gz"
    fi
    find /var/log -maxdepth 2 -name "*mongo*.log" ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" 2>/dev/null
    
    # ES
    es_pid=$(pgrep -f "org.elasticsearch.bootstrap.Elasticsearch" 2>/dev/null | head -1)
    if [[ -n "$es_pid" ]]; then
        es_home=$(ps -p $es_pid -o args= 2>/dev/null | grep -oE 'es.path.home=[^ ]+' | cut -d= -f2)
        [[ -n "$es_home" ]] && find "$es_home/logs" -maxdepth 1 -name "*.log" ! -name "*.gz" ! -name "*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" 2>/dev/null
    fi
    find /var/log/elasticsearch /usr/local/elasticsearch/logs -name "*.log" ! -name "*.gz" ! -name "*.bz2" ! -name "*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" 2>/dev/null
    
} | grep -v "^$" | grep -v "stdout" | sort -u | while read log; do
    [[ -f "$log" ]] && echo "$log"
done