#!/bin/bash
# ================================================================================
# 脚本名称：更新GeoLite2.sh
# 功能描述：更新 Loyalsoldier/geoip 增强版地理位置数据库
# 适用环境：宝塔面板 + CentOS/Rocky/AlmaLinux/Debian/Ubuntu/Windows Git Bash
# 创建日期：2026-05-20
# 更新日期：2026-05-22
#
# 数据源：https://github.com/Loyalsoldier/geoip/releases
# - Country.mmdb (国家/地区数据库，对应原 GeoLite2-City)
# - Country-asn.mmdb (ASN 数据库，对应原 GeoLite2-ASN)
#
# CDN 源支持（自动回退）：
# 1. GitHub Releases (主源)
# 2. JSDelivr CDN (cdn.jsdelivr.net)
# 3. Fastly JSDelivr CDN (fastly.jsdelivr.net)
#
# 设计思路：
# 1. 使用 GitHub API 获取最新 release tag
# 2. 下载 .mmdb 文件和对应的 .sha256sum 校验文件
# 3. 支持多个 CDN 源，自动回退到可用的源
# 4. 验证 SHA256 校验和确保文件完整性
# 5. 使用"原子更新"策略：先下载到临时文件，验证成功后再替换
# 6. 自动备份旧版本（带时间戳）
# 7. 支持重试机制，网络不稳定也能成功
# 8. 跨平台支持：兼容 Windows Git Bash 和 Linux 系统
# ================================================================================

set -eo pipefail

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    export PATH="/c/Program Files/Git/usr/bin:$PATH"
fi

# ================================================================================
# 常量定义区域
# ================================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly GEOIP_DIR="$PROJECT_DIR/数据/GeoIP"
readonly GEOIP_CITY_DB="$GEOIP_DIR/GeoLite2-City.mmdb"
readonly GEOIP_ASN_DB="$GEOIP_DIR/GeoLite2-ASN.mmdb"
readonly GEOIP_VERSION_FILE="$GEOIP_DIR/GeoIP.version"

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    readonly LOG_DIR="$GEOIP_DIR/日志"
else
    readonly LOG_DIR="/var/log"
fi
readonly UPDATE_LOG="${LOG_DIR}/GeoIP更新日志.log"
readonly AUDIT_LOG="${LOG_DIR}/审计日志.log"

readonly GITHUB_API_URL="https://api.github.com/repos/Loyalsoldier/geoip/releases/latest"
readonly GITHUB_RELEASE_BASE="https://github.com/Loyalsoldier/geoip/releases/download"
readonly JSDELIVR_BASE="https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@"
readonly FASTLY_JSDELIVR_BASE="https://fastly.jsdelivr.net/gh/Loyalsoldier/geoip@"
readonly BYTEMIRA_CDN_BASE="https://gcore.jsdelivr.net/gh/Loyalsoldier/geoip@"

readonly TIMEOUT=120
readonly MAX_RETRIES=3
readonly MIN_DISK_SPACE_MB=100
readonly MIN_FILE_SIZE=1000000
readonly CDN_RETRIES=3

# ================================================================================
# ANSI 颜色代码定义
# ================================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ================================================================================
# 全局变量
# ================================================================================
IS_WINDOWS=false
DOWNLOAD_TOOL=""
LATEST_TAG=""

# ================================================================================
# 工具函数库
# ================================================================================

print_separator() {
    echo -e "${BLUE}============================================================${NC}"
}

print_title() {
    print_separator
    echo -e "${GREEN}$1${NC}"
    print_separator
    echo ""
}

log_info() {
    local msg="$1"
    echo -e "${YELLOW}[INFO] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$UPDATE_LOG" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR] $msg${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$UPDATE_LOG" 2>/dev/null || true
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $msg" >> "$UPDATE_LOG" 2>/dev/null || true
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    fi
    return 1
}

log_audit() {
    local action="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local current_user=$(whoami)
    local sudo_user=${SUDO_USER:-$current_user}
    local sudo_uid=${SUDO_UID:-$UID}
    local tty=$(tty 2>/dev/null || echo 'unknown')
    local pwd_dir=$(pwd)
    local hostname=$(hostname)
    
    local audit_entry="$timestamp | HOST=$hostname | FROM=$sudo_user($sudo_uid) -> TO=$current_user($UID) | TTY=$tty | PWD=$pwd_dir | SCRIPT=$SCRIPT_NAME | ACTION=$action"
    
    echo "$audit_entry" >> "$AUDIT_LOG" 2>/dev/null || true
}

log_audit_start() {
    log_audit "SCRIPT_START | ARGS=$*"
}

log_audit_end() {
    local exit_code=$1
    log_audit "SCRIPT_END | EXIT_CODE=$exit_code"
}

detect_os() {
    log_info "检测操作系统..."
    
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        IS_WINDOWS=true
        log_info "检测到 Windows 系统 (Git Bash)"
    else
        IS_WINDOWS=false
        log_info "检测到 Linux/Unix 系统"
    fi
    
    if check_command curl; then
        DOWNLOAD_TOOL="curl"
        log_success "使用 curl 进行下载"
    elif check_command wget; then
        DOWNLOAD_TOOL="wget"
        log_success "使用 wget 进行下载"
    else
        log_error "未找到 curl 或 wget 工具"
        return 1
    fi
}

check_disk_space() {
    local required_mb=$1
    
    local available_mb
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        available_mb=$(df -m "$GEOIP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    else
        available_mb=$(df -m "$GEOIP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    fi
    
    if [ -z "$available_mb" ]; then
        if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
            available_mb=$(df -m . | awk 'NR==2 {print $4}')
        else
            available_mb=$(df -m /tmp | awk 'NR==2 {print $4}')
        fi
    fi
    
    if [ -z "$available_mb" ]; then
        log_warning "无法检测磁盘空间，跳过检查"
        return 0
    fi
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "磁盘空间不足，需要 ${required_mb}MB，可用 ${available_mb}MB"
        return 1
    fi
    
    log_success "磁盘空间充足: ${available_mb}MB"
    return 0
}

get_file_size() {
    local file=$1
    if [ -f "$file" ]; then
        if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
            wc -c < "$file" | awk '{print $1}'
        else
            stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || wc -c < "$file" | awk '{print $1}'
        fi
    else
        echo "0"
    fi
}

download_file() {
    local url=$1
    local output=$2
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "下载尝试 ${attempt}/${MAX_RETRIES}: $(basename "$url")"
        
        if [ "$DOWNLOAD_TOOL" = "curl" ]; then
            if curl -L --connect-timeout 30 --max-time 600 --retry 2 -o "$output" "$url"; then
                if [ -f "$output" ] && [ -s "$output" ]; then
                    return 0
                else
                    log_warning "下载的文件为空或不存在"
                fi
            else
                log_warning "curl 下载失败，错误代码: $?"
            fi
        elif [ "$DOWNLOAD_TOOL" = "wget" ]; then
            if wget --timeout=30 --tries=2 --waitretry=5 -O "$output" "$url"; then
                if [ -f "$output" ] && [ -s "$output" ]; then
                    return 0
                else
                    log_warning "下载的文件为空或不存在"
                fi
            else
                log_warning "wget 下载失败，错误代码: $?"
            fi
        fi
        
        log_warning "下载失败，等待重试..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    return 1
}

download_with_cdn_fallback() {
    local filename=$1
    local output=$2
    local tag=$3
    local cdn_attempt=1
    
    local github_url="${GITHUB_RELEASE_BASE}/${tag}/${filename}"
    local jsdelivr_url="${JSDELIVR_BASE}${tag}/${filename}"
    local fastly_url="${FASTLY_JSDELIVR_BASE}${tag}/${filename}"
    local bytemira_url="${BYTEMIRA_CDN_BASE}${tag}/${filename}"
    
    local urls=("$bytemira_url" "$jsdelivr_url" "$fastly_url" "$github_url")
    local cdn_names=("ByteMirage CDN" "JSDelivr" "Fastly JSDelivr" "GitHub")
    
    for url in "${urls[@]}"; do
        log_info "尝试从 ${cdn_names[$cdn_attempt-1]} 下载..."
        log_info "下载地址: $url"
        
        if download_file "$url" "$output"; then
            log_success "从 ${cdn_names[$cdn_attempt-1]} 下载成功"
            return 0
        fi
        
        log_warning "${cdn_names[$cdn_attempt-1]} 下载失败，尝试下一个 CDN..."
        cdn_attempt=$((cdn_attempt + 1))
        sleep 5
    done
    
    log_error "所有 CDN 源均下载失败"
    return 1
}

get_latest_tag() {
    log_info "获取最新 release 版本..."
    
    local api_response
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        if [ "$DOWNLOAD_TOOL" = "curl" ]; then
            api_response=$(curl -s --connect-timeout 30 "$GITHUB_API_URL" 2>/dev/null)
        elif [ "$DOWNLOAD_TOOL" = "wget" ]; then
            api_response=$(wget -q -O - --timeout=30 "$GITHUB_API_URL" 2>/dev/null)
        fi
        
        if [ -n "$api_response" ]; then
            LATEST_TAG=$(echo "$api_response" | grep -m 1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
            
            if [ -n "$LATEST_TAG" ]; then
                log_success "最新版本: $LATEST_TAG"
                return 0
            fi
        fi
        
        log_warning "获取版本失败，等待重试..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    log_error "无法获取最新版本信息"
    return 1
}

verify_sha256() {
    local mmdb_file=$1
    local sha256_file=$2
    
    log_info "验证 SHA256 校验和..."
    
    if [ ! -f "$mmdb_file" ] || [ ! -f "$sha256_file" ]; then
        log_error "文件不存在，无法验证"
        return 1
    fi
    
    local expected_checksum
    expected_checksum=$(awk '{print $1}' "$sha256_file")
    
    if [ -z "$expected_checksum" ]; then
        log_error "无法读取校验和文件"
        return 1
    fi
    
    local actual_checksum
    if check_command sha256sum; then
        actual_checksum=$(sha256sum "$mmdb_file" | awk '{print $1}')
    elif check_command shasum; then
        actual_checksum=$(shasum -a 256 "$mmdb_file" | awk '{print $1}')
    else
        log_warning "未找到 sha256sum 或 shasum 工具，跳过校验"
        return 0
    fi
    
    if [ "$actual_checksum" = "$expected_checksum" ]; then
        log_success "SHA256 校验通过"
        return 0
    else
        log_error "SHA256 校验失败"
        log_error "期望: $expected_checksum"
        log_error "实际: $actual_checksum"
        return 1
    fi
}

read_version_file() {
    if [ -f "$GEOIP_VERSION_FILE" ]; then
        source "$GEOIP_VERSION_FILE"
    fi
}

write_version_file() {
    local version_tag=$1
    local city_size=$2
    local asn_size=$3
    local city_update_time=$4
    local asn_update_time=$5
    
    cat > "$GEOIP_VERSION_FILE" << EOF
# GeoIP 数据库版本信息
# 此文件由更新脚本自动生成，请勿手动修改
# 数据源: https://github.com/Loyalsoldier/geoip/releases

# 版本信息
VERSION="$version_tag"

# Country.mmdb (国家/地区数据库)
CITY_FILE="Country.mmdb"
CITY_SIZE="$city_size"
CITY_UPDATE_TIME="$city_update_time"

# Country-asn.mmdb (ASN 数据库)
ASN_FILE="Country-asn.mmdb"
ASN_SIZE="$asn_size"
ASN_UPDATE_TIME="$asn_update_time"
EOF
    
    chmod 644 "$GEOIP_VERSION_FILE"
}

show_version_info() {
    read_version_file
    
    echo ""
    echo -e "${BLUE}GeoIP 数据库版本信息:${NC}"
    echo "========================================"
    
    if [ -n "$VERSION" ]; then
        echo -e "${GREEN}版本号:${NC} $VERSION"
        echo ""
        
        if [ -n "$CITY_SIZE" ] && [ "$CITY_SIZE" != "0" ]; then
            echo -e "${CYAN}Country.mmdb (国家/地区):${NC}"
            echo "  大小: $CITY_SIZE bytes"
            echo "  更新时间: ${CITY_UPDATE_TIME:-未知}"
        fi
        
        if [ -n "$ASN_SIZE" ] && [ "$ASN_SIZE" != "0" ]; then
            echo -e "${CYAN}Country-asn.mmdb (ASN):${NC}"
            echo "  大小: $ASN_SIZE bytes"
            echo "  更新时间: ${ASN_UPDATE_TIME:-未知}"
        fi
    else
        echo -e "${YELLOW}未找到版本信息${NC}"
    fi
    
    echo "========================================"
    echo ""
}

atomic_update() {
    local new_file=$1
    local old_file=$2
    local backup_file="${old_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$old_file" ]; then
        log_info "备份当前数据库到: $backup_file"
        if ! cp "$old_file" "$backup_file"; then
            log_error "备份失败"
            rm -f "$new_file"
            return 1
        fi
    fi
    
    log_info "验证下载的文件..."
    if [ ! -s "$new_file" ]; then
        log_error "下载的文件为空或大小为 0"
        rm -f "$new_file"
        return 1
    fi
    
    local file_size=$(get_file_size "$new_file")
    local min_size=100000
    
    if [[ "$old_file" == *"City.mmdb" ]]; then
        min_size=1000000
    elif [[ "$old_file" == *"ASN.mmdb" ]]; then
        min_size=100000
    fi
    
    if [ "$file_size" -lt "$min_size" ]; then
        log_error "文件大小异常: ${file_size} bytes，期望至少 ${min_size} bytes"
        rm -f "$new_file"
        return 1
    fi
    
    log_info "移动新文件到目标位置..."
    if ! mv "$new_file" "$old_file"; then
        log_error "移动文件失败"
        rm -f "$new_file"
        return 1
    fi
    
    log_success "原子更新完成"
    return 0
}

update_database() {
    local db_type=$1
    local db_file=$2
    local source_name=$3
    local temp_file="${db_file}.tmp.$$"
    local sha256_temp="${temp_file}.sha256sum"
    
    print_title "更新 ${db_type} 数据库"
    
    if [ -f "$db_file" ]; then
        local current_size=$(get_file_size "$db_file")
        log_info "当前数据库大小: ${current_size} bytes"
    fi
    
    if ! download_with_cdn_fallback "$source_name" "$temp_file" "$LATEST_TAG"; then
        log_error "下载数据库文件失败"
        rm -f "$temp_file" "$sha256_temp"
        return 1
    fi
    
    if ! download_with_cdn_fallback "${source_name}.sha256sum" "$sha256_temp" "$LATEST_TAG"; then
        log_warning "下载校验文件失败，跳过校验"
    else
        if ! verify_sha256 "$temp_file" "$sha256_temp"; then
            log_error "校验失败，删除下载的文件"
            rm -f "$temp_file" "$sha256_temp"
            return 1
        fi
        rm -f "$sha256_temp"
    fi
    
    local file_size=$(get_file_size "$temp_file")
    log_success "下载完成，文件大小: $((file_size / 1024 / 1024)) MB"
    
    if ! atomic_update "$temp_file" "$db_file"; then
        log_error "更新失败"
        rm -f "$temp_file"
        return 1
    fi
    
    echo ""
    print_title "更新完成！"
    
    log_success "${db_type} 数据库已成功更新！"
    echo ""
    
    if [ -f "$db_file" ]; then
        local new_size=$(get_file_size "$db_file")
        echo -e "  ${BLUE}版本:${NC} ${LATEST_TAG}"
        echo -e "  ${BLUE}文件大小:${NC} ${new_size} bytes"
        echo -e "  ${BLUE}文件位置:${NC} $db_file"
    fi
    
    echo ""
    return 0
}

cleanup_old_backups() {
    log_info "清理旧的备份文件..."
    
    local backup_count=0
    for backup_file in "$GEOIP_DIR"/*.backup.*; do
        if [ -f "$backup_file" ]; then
            local file_date=$(echo "$backup_file" | grep -oE '[0-9]{8}_[0-9]{6}')
            if [ -n "$file_date" ]; then
                local backup_age=0
                if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
                    local file_timestamp=$(date -d "${file_date:0:4}-${file_date:4:2}-${file_date:6:2} ${file_date:9:2}:${file_date:11:2}:${file_date:13:2}" +%s 2>/dev/null || echo "0")
                    if [ "$file_timestamp" != "0" ]; then
                        backup_age=$(( ($(date +%s) - file_timestamp) / 86400 ))
                    fi
                else
                    backup_age=$(( ($(date +%s) - $(date -d "${file_date:0:4}-${file_date:4:2}-${file_date:6:2} ${file_date:9:2}:${file_date:11:2}:${file_date:13:2}" +%s 2>/dev/null || echo "0")) / 86400 ))
                fi
                
                if [ "$backup_age" -gt 7 ]; then
                    rm -f "$backup_file"
                    backup_count=$((backup_count + 1))
                fi
            fi
        fi
    done
    
    if [ "$backup_count" -gt 0 ]; then
        log_success "已清理 $backup_count 个超过 7 天的备份文件"
    else
        log_info "没有需要清理的备份文件"
    fi
}

show_usage() {
    echo "用法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -c, --city         更新 Country.mmdb (国家/地区数据库)"
    echo "  -a, --asn          更新 Country-asn.mmdb (ASN 数据库)"
    echo "  -f, --force        强制更新"
    echo "  -v, --version      显示数据库版本信息"
    echo "  -C, --clean        清理旧的备份文件"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "数据源: https://github.com/Loyalsoldier/geoip/releases"
    echo ""
    echo "CDN 源支持（自动回退，按优先级排序）："
    echo "  1. ByteMirage CDN (gcore.jsdelivr.net) - 推荐用于中国环境"
    echo "  2. JSDelivr CDN (cdn.jsdelivr.net)"
    echo "  3. Fastly JSDelivr CDN (fastly.jsdelivr.net)"
    echo "  4. GitHub Releases (github.com)"
    echo ""
    echo "示例:"
    echo "  $SCRIPT_NAME              # 更新所有数据库"
    echo "  $SCRIPT_NAME -c           # 只更新 Country 数据库"
    echo "  $SCRIPT_NAME -f           # 强制更新所有数据库"
    echo "  $SCRIPT_NAME -v           # 显示版本信息"
}

# ================================================================================
# 主程序开始
# ================================================================================

print_title "GeoIP 数据库更新脚本 v3.0"
echo -e "${CYAN}数据源: Loyalsoldier/geoip (增强版)${NC}"
echo ""

if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

echo "========================================" >> "$UPDATE_LOG" 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始更新 GeoIP 数据库" >> "$UPDATE_LOG" 2>/dev/null || true
echo "========================================" >> "$UPDATE_LOG" 2>/dev/null || true

log_audit_start "$@"

log_info "脚本目录: $SCRIPT_DIR"
log_info "GeoIP 目录: $GEOIP_DIR"
echo ""

if [ ! -d "$GEOIP_DIR" ]; then
    mkdir -p "$GEOIP_DIR"
fi

log_info "清理残留的临时文件..."
temp_cleanup=0
for temp_file in "$GEOIP_DIR"/*.tmp.*; do
    if [ -f "$temp_file" ]; then
        rm -f "$temp_file"
        temp_cleanup=$((temp_cleanup + 1))
    fi
done
if [ "$temp_cleanup" -gt 0 ]; then
    log_success "已清理 $temp_cleanup 个临时文件"
fi
echo ""

UPDATE_CITY=true
UPDATE_ASN=true
FORCE_UPDATE=false
CLEAN_BACKUPS=false
SHOW_VERSION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--city)
            UPDATE_CITY=true
            UPDATE_ASN=false
            shift
            ;;
        -a|--asn)
            UPDATE_CITY=false
            UPDATE_ASN=true
            shift
            ;;
        -f|--force)
            FORCE_UPDATE=true
            shift
            ;;
        -v|--version)
            SHOW_VERSION=true
            shift
            ;;
        -C|--clean)
            CLEAN_BACKUPS=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

detect_os
echo ""

log_info "检查磁盘空间..."
check_disk_space "$MIN_DISK_SPACE_MB"
echo ""

show_version_info

if [ "$CLEAN_BACKUPS" = true ]; then
    cleanup_old_backups
    exit 0
fi

if [ "$SHOW_VERSION" = true ]; then
    exit 0
fi

if ! get_latest_tag; then
    log_error "无法继续更新"
    exit 1
fi
echo ""

read_version_file

if [ "$FORCE_UPDATE" != true ] && [ -n "$VERSION" ] && [ "$VERSION" = "$LATEST_TAG" ]; then
    log_info "当前版本 $VERSION 已是最新版本，无需更新"
    show_version_info
    log_audit "GEOIP_UPDATE_SKIPPED | REASON=ALREADY_LATEST | VERSION=$VERSION"
    log_audit_end 0
    exit 0
fi

CITY_SIZE="${CITY_SIZE:-}"
ASN_SIZE="${ASN_SIZE:-}"
CITY_UPDATE_TIME="${CITY_UPDATE_TIME:-}"
ASN_UPDATE_TIME="${ASN_UPDATE_TIME:-}"
UPDATE_SUCCESS=true

if [ "$UPDATE_CITY" = true ]; then
    if [ "$FORCE_UPDATE" = true ]; then
        rm -f "$GEOIP_CITY_DB"
    fi
    
    if update_database "Country (国家/地区)" "$GEOIP_CITY_DB" "Country.mmdb"; then
        CITY_SIZE=$(get_file_size "$GEOIP_CITY_DB")
        CITY_UPDATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    else
        UPDATE_SUCCESS=false
    fi
fi

if [ "$UPDATE_ASN" = true ]; then
    if [ "$FORCE_UPDATE" = true ]; then
        rm -f "$GEOIP_ASN_DB"
    fi
    
    if update_database "Country-ASN" "$GEOIP_ASN_DB" "Country-asn.mmdb"; then
        ASN_SIZE=$(get_file_size "$GEOIP_ASN_DB")
        ASN_UPDATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    else
        UPDATE_SUCCESS=false
    fi
fi

if [ "$UPDATE_SUCCESS" = true ]; then
    write_version_file "$LATEST_TAG" "${CITY_SIZE:-0}" "${ASN_SIZE:-0}" "${CITY_UPDATE_TIME:-未知}" "${ASN_UPDATE_TIME:-未知}"
    log_success "版本信息已更新到: $GEOIP_VERSION_FILE"
    
    log_info "更新成功，删除所有旧备份文件..."
    local purge_count=0
    for backup_file in "$GEOIP_DIR"/*.backup.*; do
        if [ -f "$backup_file" ]; then
            rm -f "$backup_file"
            purge_count=$((purge_count + 1))
        fi
    done
    if [ "$purge_count" -gt 0 ]; then
        log_success "已删除 $purge_count 个旧备份文件"
    else
        log_info "没有需要删除的备份文件"
    fi
else
    cleanup_old_backups
fi
show_version_info

log_audit "GEOIP_UPDATE_COMPLETE | VERSION=$LATEST_TAG | CITY=$UPDATE_CITY | ASN=$UPDATE_ASN | FORCE=$FORCE_UPDATE"
log_audit_end 0

echo ""
echo -e "${CYAN}下一步：${NC}"
echo "1. 运行 $PROJECT_DIR/脚本/分析所有站点.sh 生成新的访问报告"
echo "2. 或在宝塔面板设置定时任务自动更新"
echo ""
