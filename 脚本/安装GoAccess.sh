#!/bin/bash
# ================================================================================
# 脚本名称：安装GoAccess.sh
# 功能描述：自动从源代码编译安装最新版 GoAccess，并修复 Git 仓库权限
# 适用环境：宝塔面板 + CentOS/Rocky/AlmaLinux/Debian/Ubuntu/Arch/OpenSUSE
# 创建日期：2026-05-20
#
# 设计思路：
# 1. 支持多种Linux发行版和包管理器
# 2. 自动检测系统架构（32位/64位）
# 3. 智能检测并安装编译依赖
# 4. 处理SELinux环境（CentOS/RHEL）
# 5. 使用 set -eo pipefail 确保脚本严格执行
# 6. 使用 trap 清理函数，确保中断时能清理临时文件
# 7. 使用函数封装通用操作，提高代码复用性
# 8. 使用颜色输出提高用户体验
# 9. 自动修复 Git 仓库权限（解决 www 和 root 用户混合操作问题）
# ================================================================================

# 开启严格错误处理模式：
# -e: 任何命令返回非零退出码时立即终止脚本
# -o pipefail: 管道中任何命令失败时，整个管道命令返回失败
set -eo pipefail

# ================================================================================
# 常量定义区域（使用 readonly 确保常量不可修改）
# 设计说明：所有配置项集中在此，便于后续版本更新和维护
# ================================================================================
readonly SCRIPT_NAME="$(basename "$0")"              # 脚本文件名
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # 脚本所在目录（绝对路径）
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"      # 项目根目录（脚本目录的上级）
readonly GOACCESS_VERSION="1.10.2"                   # GoAccess 版本号（可在此处修改）
readonly GOACCESS_TAR="goaccess-${GOACCESS_VERSION}.tar.gz"  # 源码压缩包文件名
readonly GOACCESS_URL="https://tar.goaccess.io/${GOACCESS_TAR}"  # 官方下载地址
readonly WORK_DIR="/tmp/goaccess-build"              # 临时工作目录
readonly GEOIP_DIR="${PROJECT_DIR}/数据/GeoIP"
readonly GEOIP_CITY_DB="${GEOIP_DIR}/GeoLite2-City.mmdb"
readonly GEOIP_ASN_DB="${GEOIP_DIR}/GeoLite2-ASN.mmdb"

INSTALL_PREFIX="/usr/local"                          # 安装前缀（默认）
IS_READONLY_FS=false                                 # 是否只读文件系统

LOG_DIR="/www/wwwlog/GoAccess-Manage"
mkdir -p "$LOG_DIR" 2>/dev/null || true
readonly LOG_DIR_FINAL="$LOG_DIR"
readonly INSTALL_LOG="${LOG_DIR_FINAL}/安装日志.log"        # 安装日志文件
readonly AUDIT_LOG="${LOG_DIR_FINAL}/审计日志.log"          # 审计日志文件

# ================================================================================
# ANSI 颜色代码定义（用于美化输出）
# 设计说明：使用 readonly 防止颜色代码被意外修改
# ================================================================================
readonly RED='\033[0;31m'       # 红色（错误信息）
readonly GREEN='\033[0;32m'     # 绿色（成功信息）
readonly YELLOW='\033[1;33m'    # 黄色（警告/信息）
readonly BLUE='\033[0;34m'      # 蓝色（标题/分隔线）
readonly CYAN='\033[0;36m'      # 青色（提示信息）
readonly NC='\033[0m'           # 恢复默认颜色

# ================================================================================
# 全局变量区域（谨慎使用，优先使用函数参数和局部变量）
# ================================================================================
OS=""                    # 操作系统名称
PKG_MANAGER=""           # 包管理器
OS_FAMILY=""             # 系统家族（Debian/RHEL/Arch/SUSE）
CPU_CORES=""             # CPU核心数
IS_64BIT=""              # 是否64位系统
HAS_SELINUX=""           # 是否启用SELinux
config_args=""           # 编译配置参数

# ================================================================================
# 清理函数（trap 自动调用）
# 设计思路：
# 1. 记录当前退出码（$?）
# 2. 清理临时目录
# 3. 根据参数清理临时文件
# 4. 退出脚本
# ================================================================================
cleanup() {
    # 获取最后执行命令的退出码，保持原退出状态
    local exit_code=$?
    
    # 清理工作目录（忽略可能的错误，因为目录可能不存在）
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
    
    # 如果传入了参数，清理指定的临时文件
    if [ $# -gt 0 ] && [ -f "$1" ]; then
        rm -f "$1" 2>/dev/null || true
    fi
    
    # 以原退出码退出
    exit $exit_code
}

# trap 设置：在以下情况时自动调用 cleanup 函数
# - EXIT: 脚本正常退出时
# - INT: 用户按下 Ctrl+C 时
# - TERM: 系统发送终止信号时
trap cleanup EXIT INT TERM

# ================================================================================
# Git 权限修复函数
# ================================================================================

# --------------------------------------------------------------------------------
# fix_git_permissions: 修复 Git 仓库权限
# 解决 www 和 root 用户混合操作导致的权限问题
# --------------------------------------------------------------------------------
fix_git_permissions() {
    local GIT_DIR="${PROJECT_DIR}/.git"
    local WWW_USER="www"
    local WWW_GROUP="www"
    
    # 检查是否在 Git 仓库中
    if [ ! -d "$GIT_DIR" ]; then
        log_info "未检测到 Git 仓库，跳过权限修复"
        return 0
    fi
    
    log_info "检测到 Git 仓库，开始修复权限..."
    
    # 1. 修改整个仓库的所有者为 www:www
    log_info "步骤 1/4: 修改仓库所有者为 $WWW_USER:$WWW_GROUP"
    chown -R $WWW_USER:$WWW_GROUP "$PROJECT_DIR" 2>/dev/null || log_warning "无法修改所有者（可能需要 root 权限或不在支持的环境中）"
    log_success "✓ 完成"
    
    # 2. 设置目录权限为 755
    log_info "步骤 2/4: 设置目录权限为 755"
    find "$PROJECT_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || log_warning "部分目录权限修改失败"
    log_success "✓ 完成"
    
    # 3. 设置文件权限为 644
    log_info "步骤 3/4: 设置文件权限为 644"
    find "$PROJECT_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || log_warning "部分文件权限修改失败"
    log_success "✓ 完成"
    
    # 4. 为 .git 目录设置特殊权限，确保组可以写入
    log_info "步骤 4/4: 设置 .git 目录组写入权限"
    chmod -R g+w "$GIT_DIR" 2>/dev/null || log_warning ".git 目录权限修改失败"
    log_success "✓ 完成"
    
    # 5. 设置 Git 配置，使新创建的文件继承组权限
    log_info "配置 Git 仓库以继承组权限..."
    cd "$PROJECT_DIR"
    git config core.sharedRepository group 2>/dev/null || true
    cd - >/dev/null
    log_success "✓ 完成"
    
    log_success "Git 仓库权限修复完成！"
    echo ""
    echo -e "${CYAN}提示:${NC} 现在 $WWW_USER 用户可以正常执行 git pull 等操作了"
    echo -e "${CYAN}提示:${NC} 如果 root 用户需要操作仓库，建议使用 sudo -u $WWW_USER git ..."
    echo ""
}

# ================================================================================
# 工具函数库（通用操作封装）
# ================================================================================

# --------------------------------------------------------------------------------
# get_installed_version: 获取已安装的 GoAccess 版本
# 返回：版本字符串（如 "1.10.2"），如果未安装则返回空
# --------------------------------------------------------------------------------
get_installed_version() {
    if check_command goaccess; then
        local version_output=$(goaccess --version 2>&1)
        # 从输出中提取版本号（匹配 "1.10.2" 格式）
        local installed_version=$(echo "$version_output" | grep -oE '([0-9]+\.){2}[0-9]+' | head -1)
        echo "$installed_version"
    fi
}

# --------------------------------------------------------------------------------
# version_compare: 比较两个版本号
# 参数：$1 - 当前版本, $2 - 目标版本
# 返回：
#   0 - 版本相同
#   1 - 当前版本 > 目标版本
#  -1 - 当前版本 < 目标版本
# --------------------------------------------------------------------------------
version_compare() {
    local current=$1
    local target=$2
    
    # 如果任一版本为空，直接返回-1（视为需要安装）
    if [ -z "$current" ] || [ -z "$target" ]; then
        return -1
    fi
    
    # 将版本号拆分为数组
    IFS='.' read -r -a current_parts <<< "$current"
    IFS='.' read -r -a target_parts <<< "$target"
    
    # 比较每个部分
    for i in "${!current_parts[@]}"; do
        local current_num=${current_parts[$i]:-0}
        local target_num=${target_parts[$i]:-0}
        
        if [ "$current_num" -gt "$target_num" ]; then
            return 1
        elif [ "$current_num" -lt "$target_num" ]; then
            return -1
        fi
    done
    
    # 如果当前版本比目标版本短，但前面部分都相同，则视为当前版本更旧
    if [ "${#current_parts[@]}" -lt "${#target_parts[@]}" ]; then
        return -1
    fi
    
    # 版本相同
    return 0
}

# --------------------------------------------------------------------------------
# check_update_needed: 检查是否需要更新
# 返回：
#   0 - 需要安装/更新
#   1 - 已安装最新版本
#   2 - 已安装更高版本
# --------------------------------------------------------------------------------
check_update_needed() {
    local installed_version=$(get_installed_version)
    
    if [ -z "$installed_version" ]; then
        log_info "未检测到已安装的 GoAccess"
        return 0
    fi
    
    log_info "已安装版本: $installed_version"
    log_info "目标版本: $GOACCESS_VERSION"
    
    version_compare "$installed_version" "$GOACCESS_VERSION"
    local compare_result=$?
    
    if [ "$compare_result" -eq 0 ]; then
        log_success "已安装最新版本 ($GOACCESS_VERSION)"
        return 1
    elif [ "$compare_result" -eq 1 ]; then
        log_warning "已安装更高版本 ($installed_version)，高于目标版本 ($GOACCESS_VERSION)"
        return 2
    else
        log_info "需要更新: 当前版本 $installed_version -> 目标版本 $GOACCESS_VERSION"
        return 0
    fi
}

# --------------------------------------------------------------------------------
# print_separator: 打印蓝色分隔线
# 用途：美化输出，区分不同的操作阶段
# --------------------------------------------------------------------------------
print_separator() {
    echo -e "${BLUE}============================================================${NC}"
}

# --------------------------------------------------------------------------------
# print_title: 打印带边框的标题
# 参数：$1 - 标题内容
# 用途：突出显示重要阶段
# --------------------------------------------------------------------------------
print_title() {
    print_separator
    echo -e "${GREEN}$1${NC}"
    print_separator
    echo ""
}

# --------------------------------------------------------------------------------
# log_info: 打印信息级别的日志（黄色）
# 参数：$1 - 信息内容
# --------------------------------------------------------------------------------
log_info() {
    local msg="$1"
    echo -e "${YELLOW}[INFO] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]    $msg" >> "$INSTALL_LOG" 2>/dev/null || true
}

# --------------------------------------------------------------------------------
# log_success: 打印成功级别的日志（绿色）
# 参数：$1 - 成功信息
# --------------------------------------------------------------------------------
log_success() {
    local msg="$1"
    echo -e "${GREEN}[OK] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]      $msg" >> "$INSTALL_LOG" 2>/dev/null || true
}

# --------------------------------------------------------------------------------
# log_error: 打印错误级别的日志（红色，输出到 stderr）
# 参数：$1 - 错误信息
# --------------------------------------------------------------------------------
log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR] $msg${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]   $msg" >> "$INSTALL_LOG" 2>/dev/null || true
}

# --------------------------------------------------------------------------------
# log_warning: 打印警告级别的日志（黄色）
# 参数：$1 - 警告信息
# --------------------------------------------------------------------------------
log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $msg" >> "$INSTALL_LOG" 2>/dev/null || true
}

# --------------------------------------------------------------------------------
# log_separator: 打印日志分隔符
# 参数：$1 - 分隔符类型（可选：start/end/section）
# --------------------------------------------------------------------------------
log_separator() {
    local type="${1:-section}"
    local separator=""
    
    case "$type" in
        start)
            separator="═══════════════════════════════════════════════════════════════"
            echo -e "${BLUE}${separator}${NC}"
            echo "$separator" >> "$INSTALL_LOG" 2>/dev/null || true
            ;;
        end)
            separator="═══════════════════════════════════════════════════════════════"
            echo -e "${BLUE}${separator}${NC}"
            echo "$separator" >> "$INSTALL_LOG" 2>/dev/null || true
            ;;
        *)
            separator="─────────────────────────────────────────────────────────────────"
            echo -e "${BLUE}${separator}${NC}"
            echo "$separator" >> "$INSTALL_LOG" 2>/dev/null || true
            ;;
    esac
}

# --------------------------------------------------------------------------------
# check_command: 检查命令是否存在
# 参数：$1 - 命令名称
# 返回：0 - 存在，1 - 不存在
# 用途：前置检查，避免后续执行失败
# --------------------------------------------------------------------------------
check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    fi
    return 1
}

# --------------------------------------------------------------------------------
# is_package_installed: 通用包检查函数
# 参数：$1 - 包名
# 返回：0 - 已安装，1 - 未安装
# --------------------------------------------------------------------------------
is_package_installed() {
    local pkg_name="$1"
    
    case "$OS_FAMILY" in
        RHEL|SUSE)
            rpm -q "$pkg_name" &>/dev/null
            return $?
            ;;
        Debian)
            dpkg -s "$pkg_name" &>/dev/null
            return $?
            ;;
        Arch)
            pacman -Q "$pkg_name" &>/dev/null
            return $?
            ;;
        *)
            # 未知系统，默认返回未安装
            return 1
            ;;
    esac
}

# --------------------------------------------------------------------------------
# check_and_install_package: 检查并安装单个包
# 参数：$1 - 包名
# 返回：0 - 成功（已安装或安装成功），1 - 失败
# --------------------------------------------------------------------------------
check_and_install_package() {
    local pkg_name="$1"
    
    if is_package_installed "$pkg_name"; then
        log_info "  ✓ $pkg_name 已安装"
        return 0
    fi
    
    log_info "  ✗ $pkg_name 未安装，正在安装..."
    
    case "$OS_FAMILY" in
        Debian)
            $PKG_MANAGER install -y "$pkg_name"
            ;;
        RHEL)
            $PKG_MANAGER install -y "$pkg_name"
            ;;
        Arch)
            $PKG_MANAGER -S --noconfirm "$pkg_name"
            ;;
        SUSE)
            $PKG_MANAGER install -y "$pkg_name"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_success "  ✓ $pkg_name 安装成功"
        return 0
    else
        log_warning "  ✗ $pkg_name 安装失败"
        return 1
    fi
}

# --------------------------------------------------------------------------------
# log_audit: 记录审计日志
# 参数：$1 - 操作描述
# 用途：记录脚本执行的审计信息，包括用户、时间、操作等
# --------------------------------------------------------------------------------
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

# --------------------------------------------------------------------------------
# log_audit_start: 记录脚本开始执行的审计信息
# --------------------------------------------------------------------------------
log_audit_start() {
    log_audit "SCRIPT_START | ARGS=$*"
}

# --------------------------------------------------------------------------------
# log_audit_end: 记录脚本结束执行的审计信息
# 参数：$1 - 退出码
# --------------------------------------------------------------------------------
log_audit_end() {
    local exit_code=$1
    log_audit "SCRIPT_END | EXIT_CODE=$exit_code"
}

# --------------------------------------------------------------------------------
# check_disk_space: 检查磁盘空间
# 参数：$1 - 所需空间（MB）
# 返回：0 - 空间足够，1 - 空间不足
# 用途：防止因为磁盘空间不足导致安装失败
# --------------------------------------------------------------------------------
check_disk_space() {
    local required_mb=$1
    # df -m: 以 MB 为单位显示磁盘使用情况
    # awk 提取第 4 列（可用空间）
    local available_mb=$(df -m /tmp | awk 'NR==2 {print $4}')
    
    if [ -z "$available_mb" ]; then
        available_mb=$(df -m / | awk 'NR==2 {print $4}')
    fi
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "磁盘空间不足，需要 ${required_mb}MB，可用 ${available_mb}MB"
        return 1
    fi
    return 0
}

# --------------------------------------------------------------------------------
# detect_os: 检测操作系统类型和包管理器
# 返回：设置 OS, PKG_MANAGER, OS_FAMILY 变量
# 设计思路：
# 1. 使用 /etc/os-release（标准方式）
# 2. 回退到旧的检测方式
# 3. 支持多种发行版
# --------------------------------------------------------------------------------
detect_os() {
    log_info "检测操作系统..."
    
    # 方法1: 使用 /etc/os-release（推荐，大多数现代系统都有）
    if [ -f /etc/os-release ]; then
        # 加载 os-release 文件
        . /etc/os-release
        
        case "$ID" in
            centos|rocky|almalinux|rhel|fedora|opencloudos)
                OS_FAMILY="RHEL"
                if [ "$ID" = "fedora" ]; then
                    OS="Fedora"
                elif [ "$ID" = "opencloudos" ]; then
                    OS="OpenCloudOS"
                else
                    OS="${PRETTY_NAME:-CentOS/Rocky/AlmaLinux}"
                fi
                # 优先使用 dnf，否则使用 yum
                if check_command dnf; then
                    PKG_MANAGER="dnf"
                elif check_command yum; then
                    PKG_MANAGER="yum"
                fi
                ;;
            debian|ubuntu|linuxmint|pop|elementary)
                OS_FAMILY="Debian"
                OS="${PRETTY_NAME:-Debian/Ubuntu}"
                if check_command apt-get; then
                    PKG_MANAGER="apt-get"
                elif check_command apt; then
                    PKG_MANAGER="apt"
                fi
                ;;
            arch|manjaro|endeavouros|garuda)
                OS_FAMILY="Arch"
                OS="${PRETTY_NAME:-Arch Linux}"
                if check_command pacman; then
                    PKG_MANAGER="pacman"
                fi
                ;;
            opensuse*|sles)
                OS_FAMILY="SUSE"
                OS="${PRETTY_NAME:-openSUSE}"
                if check_command zypper; then
                    PKG_MANAGER="zypper"
                fi
                ;;
            *)
                log_warning "未识别的发行版 ID: $ID，尝试其他检测方式"
                ;;
        esac
    fi
    
    # 方法2: 如果方法1没成功，使用旧的检测方式
    if [ -z "$OS_FAMILY" ]; then
        if [ -f /etc/redhat-release ]; then
            OS_FAMILY="RHEL"
            OS=$(cat /etc/redhat-release | head -1)
            if check_command dnf; then
                PKG_MANAGER="dnf"
            elif check_command yum; then
                PKG_MANAGER="yum"
            fi
        elif [ -f /etc/debian_version ]; then
            OS_FAMILY="Debian"
            OS="Debian $(cat /etc/debian_version)"
            PKG_MANAGER="apt-get"
        elif [ -f /etc/arch-release ]; then
            OS_FAMILY="Arch"
            OS="Arch Linux"
            PKG_MANAGER="pacman"
        elif [ -f /etc/SuSE-release ]; then
            OS_FAMILY="SUSE"
            OS=$(cat /etc/SuSE-release | head -1)
            PKG_MANAGER="zypper"
        fi
    fi
    
    # 验证检测结果
    if [ -z "$OS_FAMILY" ] || [ -z "$PKG_MANAGER" ]; then
        log_error "无法检测操作系统或包管理器"
        echo ""
        echo -e "${CYAN}支持的操作系统：${NC}"
        echo "  - CentOS/Rocky/AlmaLinux/RHEL/Fedora (yum/dnf)"
        echo "  - Debian/Ubuntu/Linux Mint (apt/apt-get)"
        echo "  - Arch Linux/Manjaro (pacman)"
        echo "  - openSUSE/SLES (zypper)"
        echo ""
        exit 1
    fi
    
    log_success "检测到: $OS"
    log_info "系统家族: $OS_FAMILY"
    log_info "包管理器: $PKG_MANAGER"
}

# --------------------------------------------------------------------------------
# detect_arch: 检测系统架构
# 返回：设置 CPU_CORES, IS_64BIT 变量
# --------------------------------------------------------------------------------
detect_arch() {
    log_info "检测系统架构..."
    
    # 检测是否64位系统
    if [ "$(getconf LONG_BIT 2>/dev/null)" = "64" ] || [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "aarch64" ]; then
        IS_64BIT=true
        log_success "64位系统: $(uname -m)"
    else
        IS_64BIT=false
        log_warning "32位系统: $(uname -m)"
    fi
    
    # 检测CPU核心数
    if check_command nproc; then
        CPU_CORES=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    else
        CPU_CORES=4
        log_warning "无法检测CPU核心数，默认使用4核心"
    fi
    log_success "CPU核心数: $CPU_CORES"
}

# --------------------------------------------------------------------------------
# check_selinux: 检测SELinux状态
# 返回：设置 HAS_SELINUX 变量
# --------------------------------------------------------------------------------
check_selinux() {
    if [ "$OS_FAMILY" = "RHEL" ]; then
        if check_command getenforce; then
            local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
            if [ "$selinux_status" = "Enforcing" ]; then
                HAS_SELINUX=true
                log_warning "SELinux 状态: $selinux_status（可能需要调整）"
            elif [ "$selinux_status" = "Permissive" ]; then
                HAS_SELINUX=true
                log_info "SELinux 状态: $selinux_status"
            else
                HAS_SELINUX=false
                log_success "SELinux 未启用"
            fi
        fi
    fi
}

# --------------------------------------------------------------------------------
# download_with_retry: 带重试和进度条的下载函数
# 参数：$1 - 下载地址，$2 - 保存路径
# 返回：0 - 下载成功，1 - 下载失败
# 设计思路：
# 1. 优先使用 wget
# 2. 如果 wget 不可用，尝试 curl
# 3. 最多重试 3 次
# 4. 显示下载进度条
# --------------------------------------------------------------------------------
download_with_retry() {
    local url=$1
    local output=$2
    local max_attempts=3
    local attempt=1
    local timeout=30

    while [ $attempt -le $max_attempts ]; do
        log_info "下载尝试 ${attempt}/${max_attempts}..."
        
        if check_command wget; then
            echo -e "${CYAN}使用 wget 下载，显示进度条...${NC}"
            if wget --timeout="$timeout" --tries=1 --progress=bar:force -O "$output" "$url" 2>&1 | grep --line-buffered '%' | sed -u 's/.* \([0-9]*\)%.*/下载进度: \1%/'; then
                echo ""
                return 0
            fi
        elif check_command curl; then
            echo -e "${CYAN}使用 curl 下载，显示进度条...${NC}"
            if curl -L --connect-timeout "$timeout" --max-time 300 --progress-bar -o "$output" "$url" 2>&1 | tr '\r' '\n' | grep --line-buffered '%' | sed -u 's/.*\([0-9]*\).*$/下载进度: \1%/'; then
                echo ""
                return 0
            fi
        else
            log_error "既没有 wget 也没有 curl，无法下载"
            return 1
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            log_warning "下载失败，${timeout}秒后重试..."
            sleep "$timeout"
        fi
    done
    
    return 1
}

# --------------------------------------------------------------------------------
# check_and_install_missing_deps: 检查并安装缺失的依赖（通用函数）
# 参数：$1 - 依赖数组
# --------------------------------------------------------------------------------
check_and_install_missing_deps() {
    local -n deps_ref=$1
    local install_cmd=$2
    
    log_info "开始检查依赖..."
    local missing_deps=()
    for dep in "${deps_ref[@]}"; do
        if ! is_package_installed "$dep"; then
            missing_deps+=("$dep")
        else
            log_info "  ✓ $dep 已安装"
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_success "所有依赖已满足，无需安装"
    else
        log_info "需要安装 ${#missing_deps[@]} 个依赖: ${missing_deps[*]}"
        log_info "正在安装缺失的依赖..."
        eval "$install_cmd" || {
            log_warning "批量安装失败，尝试逐个安装..."
            for dep in "${missing_deps[@]}"; do
                check_and_install_package "$dep"
            done
        }
    fi
}

# --------------------------------------------------------------------------------
# install_deps: 检测并安装编译依赖
# 设计思路：先检测每个依赖是否已安装，只安装缺失的部分
# --------------------------------------------------------------------------------
install_deps() {
    log_info "检测并安装编译依赖..."
    
    case "$OS_FAMILY" in
        Debian)
            # Debian/Ubuntu 系统
            log_info "更新软件源..."
            $PKG_MANAGER update -y
            
            local deps=("gcc" "make" "wget" "tar")
            
            # ncursesw（宽字符支持）
            if check_command apt-file; then
                deps+=("libncursesw5-dev")
            else
                deps+=("libncurses-dev")
            fi
            
            # GeoIP2 支持、gettext 支持、编译工具
            deps+=("libmaxminddb-dev" "gettext" "autopoint" "gettext-base" "automake" "autoconf" "pkg-config")
            
            check_and_install_missing_deps deps "$PKG_MANAGER install -y \"\${missing_deps[@]}\""
            ;;
        
        RHEL)
            # CentOS/Rocky/AlmaLinux/RHEL/Fedora 系统
            local deps=("gcc" "make" "wget" "tar")
            
            # 先尝试安装 epel-release（如果需要）
            if [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
                if ! rpm -q epel-release &>/dev/null && [ "$ID" != "fedora" ]; then
                    log_info "检测到 EPEL 仓库未安装，正在安装..."
                    $PKG_MANAGER install -y epel-release || log_warning "EPEL 仓库安装失败，可能需要手动安装"
                else
                    log_info "  ✓ epel-release 已安装"
                fi
            fi
            
            deps+=("ncurses-devel")
            
            # GeoIP2 支持
            if [ "$ID" = "fedora" ]; then
                deps+=("libmaxminddb-devel")
            else
                if $PKG_MANAGER list libmaxminddb-devel &>/dev/null; then
                    deps+=("libmaxminddb-devel")
                elif $PKG_MANAGER list maxminddb-devel &>/dev/null; then
                    deps+=("maxminddb-devel")
                fi
            fi
            
            # gettext 支持、编译工具
            deps+=("gettext" "gettext-devel" "gettext-libs" "automake" "autoconf" "pkgconfig")
            
            check_and_install_missing_deps deps "$PKG_MANAGER install -y \"\${missing_deps[@]}\""
            ;;
        
        Arch)
            # Arch Linux 系统
            log_info "同步软件包数据库..."
            $PKG_MANAGER -Sy --noconfirm
            
            local deps=("gcc" "make" "wget" "tar" "ncurses" "libmaxminddb" "gettext" "pkg-config" "automake" "autoconf")
            
            check_and_install_missing_deps deps "$PKG_MANAGER -S --noconfirm \"\${missing_deps[@]}\""
            ;;
        
        SUSE)
            # openSUSE/SLES 系统
            local deps=("gcc" "make" "wget" "tar" "ncurses-devel" "libmaxminddb-devel" "gettext" "gettext-devel" "pkg-config" "automake" "autoconf")
            
            check_and_install_missing_deps deps "$PKG_MANAGER install -y \"\${missing_deps[@]}\""
            ;;
    esac
    
    log_success "依赖检查和安装完成"
}

# ================================================================================
# 主程序开始
# ================================================================================

print_title "GoAccess 编译安装脚本 v2.0"

# 创建并配置日志目录
if [ ! -d "$LOG_DIR" ]; then
    log_info "创建日志目录: $LOG_DIR"
    mkdir -p "$LOG_DIR"
fi
chown -R www:www "$LOG_DIR" 2>/dev/null || true
chmod 755 "$LOG_DIR" 2>/dev/null || true

if touch "$INSTALL_LOG" 2>/dev/null; then
    chown www:www "$INSTALL_LOG" 2>/dev/null || true
    log_success "日志目录已配置: $LOG_DIR"
else
    log_warning "无法创建安装日志文件: $INSTALL_LOG"
fi

if touch "$AUDIT_LOG" 2>/dev/null; then
    chown www:www "$AUDIT_LOG" 2>/dev/null || true
else
    log_warning "无法创建审计日志文件: $AUDIT_LOG"
fi

# 记录脚本开始信息到日志文件
log_separator "start"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [START] 开始安装 GoAccess v${GOACCESS_VERSION}" >> "$INSTALL_LOG" 2>/dev/null || true
log_separator

# 记录脚本开始执行的审计信息
log_audit_start "$@"

# --------------------------------------------------------------------------------
# 阶段 0：Git 权限修复（新增）
# --------------------------------------------------------------------------------
print_title "Git 仓库权限修复"

log_audit "GIT_PERMISSION_FIX_START"
fix_git_permissions
log_audit "GIT_PERMISSION_FIX_END"

# --------------------------------------------------------------------------------
# 阶段 1：版本检查
# --------------------------------------------------------------------------------
print_title "版本检查"

# 检查是否有 --force 参数
force_install=false
if [ "$1" = "--force" ]; then
    force_install=true
    log_warning "强制安装模式：将忽略版本检查，重新安装"
    echo ""
fi

# 如果不是强制安装，才进行版本检查
if [ "$force_install" = false ]; then
    check_update_needed
    update_needed=$?
    
    # 根据检查结果决定后续操作
    case "$update_needed" in
        1)
            log_success "系统已安装最新版本，无需重复安装"
            echo ""
            echo -e "${GREEN}如果需要重新安装，请添加 --force 参数：${NC}"
            echo "  sudo $0 --force"
            echo ""
            exit 0
            ;;
        2)
            log_warning "系统已安装更高版本，是否继续安装旧版本？"
            echo -n "继续安装请输入 'yes'，否则按任意键退出："
            read -r confirm
            if [ "$confirm" != "yes" ]; then
                log_info "用户取消安装"
                exit 0
            fi
            log_info "继续安装旧版本..."
            echo ""
            ;;
        *)
            log_info "开始安装/更新流程..."
            echo ""
            ;;
    esac
else
    log_info "开始强制安装..."
    echo ""
fi



# --------------------------------------------------------------------------------
# 阶段 2：检查运行权限并设置安装前缀
# --------------------------------------------------------------------------------
log_info "检查运行权限..."

detect_install_prefix() {
    local test_dirs=()
    
    test_dirs+=("/usr/local")
    test_dirs+=("${HOME}/.local")
    test_dirs+=("${PROJECT_DIR}/.local")
    test_dirs+=("/tmp/goaccess-install")
    
    for dir in "${test_dirs[@]}"; do
        if [ -w "$dir" ] 2>/dev/null; then
            echo "$dir"
            return 0
        fi
        
        if mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ]; then
            echo "$dir"
            return 0
        fi
    done
    
    return 1
}

INSTALL_PREFIX=$(detect_install_prefix)

if [ -z "$INSTALL_PREFIX" ]; then
    log_error "无法找到可写的安装目录"
    log_info "尝试的目录："
    log_info "  - /usr/local"
    log_info "  - ${HOME}/.local"
    log_info "  - ${PROJECT_DIR}/.local"
    log_info "  - /tmp/goaccess-install"
    exit 1
fi

if [ "$INSTALL_PREFIX" != "/usr/local" ]; then
    if [ "$EUID" -eq 0 ]; then
        IS_READONLY_FS=true
        log_warning "检测到只读文件系统或沙箱环境"
    else
        log_info "非 root 用户，使用用户级安装"
    fi
fi

log_success "安装前缀: $INSTALL_PREFIX"

if [ "$IS_READONLY_FS" = true ]; then
    log_warning "将安装到: $INSTALL_PREFIX"
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 3：系统信息检测
# --------------------------------------------------------------------------------
print_title "系统信息检测"

detect_os
detect_arch
check_selinux
echo ""

# --------------------------------------------------------------------------------
# 阶段 4：检查磁盘空间（至少需要 500MB）
# --------------------------------------------------------------------------------
log_info "检查磁盘空间..."
check_disk_space 500
log_success "磁盘空间充足"
echo ""

# --------------------------------------------------------------------------------
# 阶段 5：安装编译依赖
# --------------------------------------------------------------------------------
install_deps
echo ""

# --------------------------------------------------------------------------------
# 阶段 6：准备工作目录
# --------------------------------------------------------------------------------
log_info "准备工作目录..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
log_success "工作目录: $WORK_DIR"
echo ""

# --------------------------------------------------------------------------------
# 阶段 7：下载 GoAccess 源代码
# --------------------------------------------------------------------------------
log_info "下载 GoAccess v${GOACCESS_VERSION}..."

if [ -f "/tmp/${GOACCESS_TAR}" ]; then
    log_info "文件已存在，跳过下载"
else
    log_info "下载地址: $GOACCESS_URL"
    if ! download_with_retry "$GOACCESS_URL" "/tmp/${GOACCESS_TAR}"; then
        log_error "下载失败"
        exit 1
    fi
fi
cp "/tmp/${GOACCESS_TAR}" "$WORK_DIR/"
log_success "下载完成"
echo ""

# --------------------------------------------------------------------------------
# 阶段 8：解压源代码
# --------------------------------------------------------------------------------
log_info "解压源代码..."
tar --no-same-owner -xzf "$GOACCESS_TAR"
cd "$WORK_DIR/goaccess-${GOACCESS_VERSION}"
log_success "解压完成"
echo ""

# --------------------------------------------------------------------------------
# 阶段 9：配置编译选项
# --------------------------------------------------------------------------------
log_info "配置编译选项..."

config_args="--prefix=$INSTALL_PREFIX --enable-utf8"

if check_command pkg-config && pkg-config --exists libmaxminddb 2>/dev/null; then
    config_args="$config_args --enable-geoip=mmdb"
    log_info "GeoIP2 支持: 已启用"
else
    log_warning "GeoIP2 库未找到，将不启用 GeoIP 支持"
fi

if ! is_package_installed "gettext"; then
    log_warning "gettext 未安装，将不启用多语言支持"
    config_args="$config_args --disable-nls"
else
    log_info "多语言支持: 已启用（NLS 默认启用）"
fi

log_info "编译参数: $config_args"
echo ""

log_info "开始配置（这可能需要几分钟）..."
if ! ./configure $config_args; then
    log_error "配置失败，请检查日志"
    echo ""
    echo -e "${CYAN}提示：${NC}"
    echo "  - 检查 config.log 了解详细错误"
    echo "  - 可能缺少某些依赖库"
    exit 1
fi

log_success "配置完成"

echo ""
log_info "验证 gettext 支持..."
if grep -q "ENABLE_NLS.*1" config.h 2>/dev/null || grep -q "HAVE_LIBINTL_H" config.h 2>/dev/null; then
    log_success "✓ gettext 支持已正确配置"
else
    log_warning "⚠ gettext 支持可能未正确配置"
    log_warning "  这将导致无法使用中文界面（--lang=zh 选项）"
    log_warning "  如果需要中文支持，请检查 gettext 相关依赖是否正确安装"
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 10：编译源代码
# --------------------------------------------------------------------------------
log_info "编译源代码..."
log_info "使用 ${CPU_CORES} 个 CPU 核心进行并行编译"

if ! make -j"$CPU_CORES"; then
    log_error "编译失败"
    exit 1
fi
log_success "编译完成"
echo ""

# --------------------------------------------------------------------------------
# 阶段 11：安装到系统
# --------------------------------------------------------------------------------
log_info "安装到系统..."
if ! make install; then
    log_error "安装失败"
    exit 1
fi
log_success "安装完成"
echo ""

# --------------------------------------------------------------------------------
# 阶段 12：更新共享库缓存
# --------------------------------------------------------------------------------
if [ "$INSTALL_PREFIX" = "/usr/local" ]; then
    log_info "更新共享库缓存..."
    if check_command ldconfig; then
        ldconfig 2>/dev/null || true
        log_success "共享库缓存已更新"
    else
        log_warning "ldconfig 不可用，跳过"
    fi
else
    log_info "用户级安装，跳过 ldconfig"
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 13：验证安装
# --------------------------------------------------------------------------------
print_title "安装验证"

GOACCESS_BIN="${INSTALL_PREFIX}/bin/goaccess"

if [ -x "$GOACCESS_BIN" ]; then
    log_success "GoAccess 安装成功！"
    echo ""
    echo -e "${BLUE}版本信息:${NC}"
    "$GOACCESS_BIN" --version
    echo ""
    echo -e "${BLUE}安装路径:${NC}"
    echo "$GOACCESS_BIN"
    echo ""
    echo -e "${BLUE}编译特性检查:${NC}"
    
    gettext_check=$(strings "$GOACCESS_BIN" 2>/dev/null | grep -c "bindtextdomain" 2>/dev/null || echo "0")
    gettext_check=$(echo "$gettext_check" | tr -d '\n')
    if [ "$gettext_check" -gt 0 ]; then
        log_success "✓ gettext 支持: 已启用（可通过 LC_ALL/LANG 环境变量使用中文界面）"
    else
        log_warning "✗ gettext 支持: 未启用（不支持多语言界面）"
    fi
    
    geoip_check=$("$GOACCESS_BIN" --help 2>&1 | grep -c "geoip-database" 2>/dev/null || echo "0")
    geoip_check=$(echo "$geoip_check" | tr -d '\n')
    if [ "$geoip_check" -gt 0 ]; then
        log_success "✓ GeoIP 支持: 已启用"
    else
        log_warning "✗ GeoIP 支持: 未启用"
    fi
    
    echo ""
    echo -e "${BLUE}帮助信息（前20行）:${NC}"
    "$GOACCESS_BIN" --help 2>&1 | head -20
    
    if [ "$INSTALL_PREFIX" != "/usr/local" ]; then
        echo ""
        log_warning "GoAccess 已安装到用户目录: $INSTALL_PREFIX"
        
        if [ "$EUID" -eq 0 ] && [ "$IS_READONLY_FS" = true ]; then
            log_info "尝试将 GoAccess 复制到全局路径..."
            if cp "$GOACCESS_BIN" /usr/local/bin/goaccess && chmod +x /usr/local/bin/goaccess; then
                log_success "✓ GoAccess 已复制到 /usr/local/bin/goaccess"
                log_info "现在可以直接使用 goaccess 命令"
            else
                log_warning "无法复制到 /usr/local/bin，需要手动复制"
            fi
        else
            echo ""
            echo -e "${CYAN}请将以下内容添加到 ~/.bashrc 或 ~/.zshrc:${NC}"
            echo "    export PATH=\"\${PATH}:${INSTALL_PREFIX}/bin\""
            echo ""
            echo -e "${CYAN}或使用完整路径运行:${NC}"
            echo "    $GOACCESS_BIN"
        fi
    fi
else
    log_error "安装验证失败"
    exit 1
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 14：配置 GeoIP 数据库
# --------------------------------------------------------------------------------
print_title "配置 GeoIP 数据库"

create_goaccess_config() {
    local config_file="${INSTALL_PREFIX}/etc/goaccess.conf"
    
    log_info "配置 GoAccess 使用 GeoIP 数据库..."
    
    if [ -f "$GEOIP_CITY_DB" ]; then
        mkdir -p "$(dirname "$config_file")" 2>/dev/null || true
        
        if [ -w "$(dirname "$config_file")" ]; then
            cat > "$config_file" << EOF
# GoAccess 配置文件
# 自动生成的 GeoIP 配置

# GeoIP 数据库配置
geoip-database $GEOIP_CITY_DB
EOF
            
            if [ -f "$GEOIP_ASN_DB" ]; then
                echo "geoip-database $GEOIP_ASN_DB" >> "$config_file"
            fi
            
            chmod 644 "$config_file" 2>/dev/null || true
            log_success "GoAccess 配置文件已创建: $config_file"
            log_info "配置文件目录: ${INSTALL_PREFIX}/etc"
        else
            log_warning "无法写入配置文件目录: ${INSTALL_PREFIX}/etc"
            log_info "请手动创建配置文件"
        fi
    else
        log_info "未检测到 GeoIP 数据库文件，跳过配置"
        log_info "GeoIP 数据库文件位置: $GEOIP_DIR"
    fi
}

create_goaccess_config

echo ""

# --------------------------------------------------------------------------------
# 阶段 15：创建站点配置目录
# --------------------------------------------------------------------------------
print_title "创建站点配置目录"

readonly SITES_CONFIG_DIR="${PROJECT_DIR}/配置/站点配置"

log_info "创建站点配置目录..."
mkdir -p "$SITES_CONFIG_DIR"

readonly TEMPLATE_FILE="${PROJECT_DIR}/配置/配置模板.conf"
readonly DEST_CONFIG_FILE="${SITES_CONFIG_DIR}/配置模板.conf"

if [ -f "$TEMPLATE_FILE" ]; then
    if [ ! -f "$DEST_CONFIG_FILE" ]; then
        cp "$TEMPLATE_FILE" "$DEST_CONFIG_FILE"
        log_success "配置模板已复制到站点配置目录"
    else
        log_info "配置模板已存在，跳过复制"
    fi
    
    # 检查是否有默认站点配置，如果没有则创建一个示例
    readonly EXAMPLE_CONFIG="${SITES_CONFIG_DIR}/示例站点.conf"
    if [ ! -f "$EXAMPLE_CONFIG" ]; then
        # 复制模板并创建示例配置
        cp "$TEMPLATE_FILE" "$EXAMPLE_CONFIG"
        # 修改示例配置中的占位符
        sed -i 's/您的站点名称/示例站点/g' "$EXAMPLE_CONFIG"
        sed -i 's/您的域名/example.com/g' "$EXAMPLE_CONFIG"
        log_success "已创建示例站点配置: $EXAMPLE_CONFIG"
    else
        log_info "示例站点配置已存在，跳过创建"
    fi
else
    log_warning "配置模板文件不存在: $TEMPLATE_FILE"
    # 如果模板不存在，创建一个简单的默认配置
    readonly DEFAULT_CONFIG="${SITES_CONFIG_DIR}/默认站点.conf"
    if [ ! -f "$DEFAULT_CONFIG" ]; then
        cat > "$DEFAULT_CONFIG" << EOF
# GoAccess 站点配置文件
# 请根据实际情况修改以下配置

site_name="默认站点"
log_file="/www/wwwlogs/your-domain.log"
output_html="/www/wwwroot/your-domain/site-log.html"
log_format=COMBINED
EOF
        log_success "已创建默认站点配置: $DEFAULT_CONFIG"
    else
        log_info "默认站点配置已存在，跳过创建"
    fi
fi

log_success "站点配置目录创建完成: $SITES_CONFIG_DIR"
echo ""

# --------------------------------------------------------------------------------
# 阶段 16：完成提示
# --------------------------------------------------------------------------------
print_title "安装完成！"

echo -e "${GREEN}下一步操作：${NC}"
echo "1. 复制 配置/站点配置/配置模板.conf 并创建您的站点配置"
echo "2. 运行 脚本/分析所有站点.sh 生成报告"
echo "3. 在宝塔面板设置定时任务自动更新报告"
echo ""

if [ "$HAS_SELINUX" = true ]; then
    echo -e "${YELLOW}注意：${NC}"
    echo "SELinux 已启用，如果遇到权限问题可能需要调整设置"
    echo ""
fi

echo -e "${BLUE}详细说明请参考：README.md${NC}"
echo ""

# 记录安装完成的审计信息
log_audit "INSTALL_COMPLETE | VERSION=$GOACCESS_VERSION"

# 记录脚本结束信息到日志文件
log_separator
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [END]   GoAccess 安装完成" >> "$INSTALL_LOG" 2>/dev/null || true
log_separator "end"

log_audit_end 0
