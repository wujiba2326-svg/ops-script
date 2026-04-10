#!/usr/bin/env bash
################################################################################
# 收集各服务最后 20000 行日志，按时间目录 + 服务类型归档
# 目录结构: ./log_collect_YYYYMMDD_HHMMSS/<service>/<filename>.log
################################################################################

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BASE_DIR="$(cd "$(dirname "$0")" && pwd)/out/log_collect_${TIMESTAMP}"

LINES=20000
COLLECTED_COUNT=0

# --------------------------------------------------------------------------
# 工具函数
# --------------------------------------------------------------------------

# 判断日志路径所属服务类型
classify_log() {
    local path="$1"
    local lower
    lower=$(echo "$path" | tr '[:upper:]' '[:lower:]')

    case "$lower" in
        *php*|*fpm*)         echo "php" ;;
        *nginx*)             echo "nginx" ;;
        *mysql*|*mariadb*)   echo "mysql" ;;
        *redis*)             echo "redis" ;;
        *mongo*)             echo "mongodb" ;;
        *elastic*|*es*)      echo "elasticsearch" ;;
        *)                   echo "other" ;;
    esac
}

# 收集单个日志文件最后 N 行
collect_one() {
    local log_path="$1"
    local service="$2"

    [[ -f "$log_path" ]] || return

    local dest_dir="${BASE_DIR}/${service}"
    mkdir -p "$dest_dir"

    # 保留原始文件名，加 .tail 后缀区分
    local filename
    filename=$(basename "$log_path")
    local dest_file="${dest_dir}/${filename}"

    tail -n "${LINES}" "$log_path" > "$dest_file" 2>/dev/null

    local saved_lines
    saved_lines=$(wc -l < "$dest_file" 2>/dev/null || echo 0)
    COLLECTED_COUNT=$((COLLECTED_COUNT + 1))
    echo "  [OK] ${service}  ${log_path}  (${saved_lines} lines)  -> ${dest_file}"
}

# --------------------------------------------------------------------------
# 收集各服务日志路径（复用 find_log_paths.sh 的查找逻辑）
# --------------------------------------------------------------------------

collect_all_logs() {
    local -a paths=()

    # ===== PHP =====
    if command -v php >/dev/null 2>&1; then
        while IFS= read -r p; do
            [[ -n "$p" && "$p" != "no value" ]] && paths+=("$p")
        done < <(php -i 2>/dev/null | grep "^error_log" | awk '{print $3}' | grep -v "no value")
    fi

    find /etc -name "php-fpm.conf" -o -name "www.conf" 2>/dev/null | while read -r conf; do
        grep -E "^error_log|^slowlog|^access.log" "$conf" 2>/dev/null | awk '{print $3}'
    done | while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done

    # Remi 多版本 php-fpm.d 配置目录
    for _ver in php73 php74 php80 php81 php82 php83; do
        find "/etc/opt/remi/${_ver}/php-fpm.d" -name "*.conf" 2>/dev/null | while read -r conf; do
            grep -E "^error_log|^slowlog|^access.log" "$conf" 2>/dev/null | awk '{print $3}'
        done | while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done
    done

    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
        find /var/log /home/logs/fpm /usr/local/php/var/log -maxdepth 2 \( -name "*php*.log" -o -name "*fpm*.log" -o -name "*.log" \) \
            ! -name "*.gz" ! -name "*.bz2" ! -name "*.zip" \
            ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
            ! -name "*.1" ! -name "*.2" 2>/dev/null
    )

    # Remi 仓库多版本 PHP
    for _ver in php73 php74 php80 php81 php82 php83; do
        while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            find "/var/opt/remi/${_ver}/log" -maxdepth 2 -type f \
                ! -name "*.gz" ! -name "*.bz2" ! -name "*.zip" \
                ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
                ! -name "*.1" ! -name "*.2" 2>/dev/null
        )
    done

    # ===== Nginx =====
    if command -v nginx >/dev/null 2>&1; then
        nginx_conf=$(nginx -V 2>&1 | grep -oE 'conf-path=[^ ]+' | cut -d= -f2 || echo "/etc/nginx/nginx.conf")
        if [[ -f "$nginx_conf" ]]; then
            while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
                find "$(dirname "$nginx_conf")" -name "*.conf" 2>/dev/null \
                | xargs grep -hE "access_log|error_log" 2>/dev/null \
                | grep -v "#" | awk '{print $2}' | tr -d ';'
            )
        fi
    fi

    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
        find /var/log/nginx -type f -name "*.log" \
            ! -name "*.gz" ! -name "*.bz2" ! -name "*.zip" \
            ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" \
            ! -name "*.1" ! -name "*.2" 2>/dev/null
    )

    # ===== MySQL =====
    if command -v mysql >/dev/null 2>&1; then
        while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            mysql -e "SELECT @@log_error;" 2>/dev/null | tail -1
            mysql -e "SELECT @@slow_query_log_file;" 2>/dev/null | tail -1
        )
    fi

    for cnf in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
        [[ -f "$cnf" ]] && while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            grep -E "^log-error|^log_error|^slow_query_log_file" "$cnf" 2>/dev/null \
            | awk -F= '{print $2}' | tr -d ' "'
        )
    done

    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
        find /var/log /var/log/mysql -maxdepth 2 \( -name "*mysql*.log" -o -name "*mariadb*.log" -o -name "*.log" \) \
            ! -name "*.gz" ! -name "*.bz2" \
            ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" 2>/dev/null
        find /var/lib/mysql -maxdepth 1 -name "*.err" 2>/dev/null
    )

    # ===== Redis =====
    if command -v redis-cli >/dev/null 2>&1; then
        while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            redis-cli CONFIG GET logfile 2>/dev/null | tail -1
        )
    fi

    for conf in /etc/redis/redis.conf /etc/redis.conf; do
        [[ -f "$conf" ]] && while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            grep "^logfile" "$conf" 2>/dev/null | awk '{print $2}' | tr -d '"'
        )
    done

    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
        find /var/log /var/log/redis -maxdepth 2 -name "*.log" \
            ! -name "*.gz" ! -name "*.bz2" \
            ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" 2>/dev/null
    )

    # ===== MongoDB =====
    mongo_pid=$(pgrep mongod 2>/dev/null | head -1)
    if [[ -n "$mongo_pid" ]]; then
        mongo_conf=$(ps -p "$mongo_pid" -o args= 2>/dev/null \
            | grep -oE '\-f [^ ]+|\-\-config [^ ]+' | awk '{print $2}')
        if [[ -n "$mongo_conf" && -f "$mongo_conf" ]]; then
            while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
                grep -A 10 "systemLog:" "$mongo_conf" 2>/dev/null \
                | grep "path:" | awk '{print $2}' | tr -d '"'
            )
        fi
        while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            lsof -p "$mongo_pid" 2>/dev/null | grep "\.log" | awk '{print $9}' | grep -v "\.gz"
        )
    fi

    for conf in /etc/mongod.conf /etc/mongodb.conf /usr/local/mongodb/config; do
        [[ -f "$conf" ]] && while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
            grep -A 10 "systemLog:" "$conf" 2>/dev/null \
            | grep "path:" | awk '{print $2}' | tr -d '"'
        )
    done

    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
        find /var/log -maxdepth 2 -name "*mongo*.log" \
            ! -name "*.gz" ! -name "*.bz2" \
            ! -name "*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*" 2>/dev/null
        find /usr/local/mongodb -maxdepth 2 -name "*.log" \
            ! -name "*.gz" ! -name "*.bz2" 2>/dev/null
    )

    # ===== Elasticsearch =====
    es_pid=$(pgrep -f "org.elasticsearch.bootstrap.Elasticsearch" 2>/dev/null | head -1)
    if [[ -n "$es_pid" ]]; then
        es_home=$(ps -p "$es_pid" -o args= 2>/dev/null \
            | grep -oE 'es.path.home=[^ ]+' | cut -d= -f2)
        if [[ -n "$es_home" ]]; then
            while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
                find "$es_home/logs" -maxdepth 1 -name "*.log" \
                    ! -name "*.gz" \
                    ! -name "*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" 2>/dev/null
            )
        fi
    fi

    while IFS= read -r p; do [[ -n "$p" ]] && paths+=("$p"); done < <(
        find /var/log/elasticsearch /usr/local/elasticsearch/logs -name "*.log" \
            ! -name "*.gz" ! -name "*.bz2" \
            ! -name "*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*" 2>/dev/null
    )

    # ---------- 去重并收集 ----------
    declare -A seen
    for log_path in "${paths[@]}"; do
        [[ -z "$log_path" ]]       && continue
        [[ "${seen[$log_path]}" ]] && continue
        [[ ! -f "$log_path" ]]     && continue
        seen["$log_path"]=1

        local service
        service=$(classify_log "$log_path")
        collect_one "$log_path" "$service"
    done
}

# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------

echo "=========================================="
echo "日志收集开始"
echo "时间戳 : ${TIMESTAMP}"
echo "输出目录: ${BASE_DIR}"
echo "截取行数: ${LINES}"
echo "=========================================="
echo ""

mkdir -p "${BASE_DIR}"

collect_all_logs

echo ""
echo "=========================================="
echo "收集完成，目录结构："
echo "=========================================="
if [[ "${COLLECTED_COUNT}" -eq 0 ]]; then
    echo "未收集到任何日志文件，已创建空目录: ${BASE_DIR}"
elif [[ -d "${BASE_DIR}" ]]; then
    (
        cd "${BASE_DIR}" && find . -type f | sort | sed 's|^\./||'
    )
else
    echo "输出目录不存在: ${BASE_DIR}"
fi
