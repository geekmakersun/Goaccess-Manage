#!/bin/bash
# ================================================================================
# 脚本名称：安装GoAccess.sh
# 功能描述：自动从源代码编译安装最新版 GoAccess
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
readonly GOACCESS_VERSION="1.10.2"                   # GoAccess 版本号（可在此处修改）
readonly GOACCESS_TAR="goaccess-${GOACCESS_VERSION}.tar.gz"  # 源码压缩包文件名
readonly GOACCESS_URL="https://tar.goaccess.io/${GOACCESS_TAR}"  # 官方下载地址
readonly WORK_DIR="/tmp/goaccess-build"              # 临时工作目录
readonly GEOIP_DIR="/usr/share/GeoIP"                # GeoIP 数据库目录
readonly GEOIP_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"  # 免费 GeoLite2 下载地址

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
# 工具函数库（通用操作封装）
# ================================================================================

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
    echo -e "${YELLOW}[INFO] $1${NC}"
}

# --------------------------------------------------------------------------------
# log_success: 打印成功级别的日志（绿色）
# 参数：$1 - 成功信息
# --------------------------------------------------------------------------------
log_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

# --------------------------------------------------------------------------------
# log_error: 打印错误级别的日志（红色，输出到 stderr）
# 参数：$1 - 错误信息
# --------------------------------------------------------------------------------
log_error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

# --------------------------------------------------------------------------------
# log_warning: 打印警告级别的日志（黄色）
# 参数：$1 - 警告信息
# --------------------------------------------------------------------------------
log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
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
            centos|rocky|almalinux|rhel|fedora)
                OS_FAMILY="RHEL"
                if [ "$ID" = "fedora" ]; then
                    OS="Fedora"
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
# download_with_retry: 带重试的下载函数
# 参数：$1 - 下载地址，$2 - 保存路径
# 返回：0 - 下载成功，1 - 下载失败
# 设计思路：
# 1. 优先使用 wget
# 2. 如果 wget 不可用，尝试 curl
# 3. 最多重试 3 次
# --------------------------------------------------------------------------------
download_with_retry() {
    local url=$1
    local output=$2
    local max_attempts=3
    local attempt=1
    local timeout=60

    while [ $attempt -le $max_attempts ]; do
        log_info "下载尝试 ${attempt}/${max_attempts}..."
        
        # 优先使用 wget
        if check_command wget; then
            if wget --timeout="$timeout" -O "$output" "$url" 2>/dev/null; then
                return 0
            fi
        elif check_command curl; then
            if curl -L --connect-timeout "$timeout" -o "$output" "$url" 2>/dev/null; then
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
# install_deps: 安装编译依赖
# 设计思路：根据不同的系统家族安装对应的依赖
# --------------------------------------------------------------------------------
install_deps() {
    log_info "安装编译依赖..."
    
    case "$OS_FAMILY" in
        Debian)
            # Debian/Ubuntu 系统
            log_info "更新软件源..."
            $PKG_MANAGER update -y
            
            local deps=()
            deps+=("gcc")
            deps+=("make")
            deps+=("wget")
            deps+=("tar")
            
            # ncursesw（宽字符支持）
            if check_command apt-file; then
                deps+=("libncursesw5-dev")
            else
                deps+=("libncurses-dev")
            fi
            
            # GeoIP2 支持
            deps+=("libmaxminddb-dev")
            
            # pkg-config（可能需要）
            deps+=("pkg-config")
            
            log_info "安装依赖包: ${deps[*]}"
            $PKG_MANAGER install -y "${deps[@]}"
            ;;
        
        RHEL)
            # CentOS/Rocky/AlmaLinux/RHEL/Fedora 系统
            local deps=()
            deps+=("gcc")
            deps+=("make")
            deps+=("wget")
            deps+=("tar")
            
            # 先尝试安装 epel-release（如果需要）
            if [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
                if ! rpm -q epel-release &>/dev/null && [ "$ID" != "fedora" ]; then
                    log_info "安装 EPEL 仓库..."
                    $PKG_MANAGER install -y epel-release || true
                fi
            fi
            
            # ncurses-devel
            deps+=("ncurses-devel")
            
            # GeoIP2 支持
            if [ "$ID" = "fedora" ]; then
                deps+=("libmaxminddb-devel")
            else
                # 尝试多种包名
                if $PKG_MANAGER list libmaxminddb-devel &>/dev/null; then
                    deps+=("libmaxminddb-devel")
                elif $PKG_MANAGER list maxminddb-devel &>/dev/null; then
                    deps+=("maxminddb-devel")
                fi
            fi
            
            # pkgconfig
            deps+=("pkgconfig")
            
            log_info "安装依赖包: ${deps[*]}"
            $PKG_MANAGER install -y "${deps[@]}"
            ;;
        
        Arch)
            # Arch Linux 系统
            log_info "同步软件包数据库..."
            $PKG_MANAGER -Sy --noconfirm
            
            local deps=()
            deps+=("gcc")
            deps+=("make")
            deps+=("wget")
            deps+=("tar")
            deps+=("ncurses")
            deps+=("libmaxminddb")
            deps+=("pkg-config")
            
            log_info "安装依赖包: ${deps[*]}"
            $PKG_MANAGER -S --noconfirm "${deps[@]}"
            ;;
        
        SUSE)
            # openSUSE/SLES 系统
            local deps=()
            deps+=("gcc")
            deps+=("make")
            deps+=("wget")
            deps+=("tar")
            deps+=("ncurses-devel")
            deps+=("libmaxminddb-devel")
            deps+=("pkg-config")
            
            log_info "安装依赖包: ${deps[*]}"
            $PKG_MANAGER install -y "${deps[@]}"
            ;;
    esac
    
    log_success "依赖安装完成"
}

# ================================================================================
# 主程序开始
# ================================================================================

print_title "GoAccess 编译安装脚本 v2.0"

# --------------------------------------------------------------------------------
# 阶段 1：检查运行权限
# --------------------------------------------------------------------------------
log_info "检查运行权限..."
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 权限运行此脚本"
    echo "使用方法：sudo $0"
    exit 1
fi
log_success "权限检查通过"
echo ""

# --------------------------------------------------------------------------------
# 阶段 2：系统信息检测
# --------------------------------------------------------------------------------
print_title "系统信息检测"

detect_os
detect_arch
check_selinux
echo ""

# --------------------------------------------------------------------------------
# 阶段 3：检查磁盘空间（至少需要 500MB）
# --------------------------------------------------------------------------------
log_info "检查磁盘空间..."
check_disk_space 500
log_success "磁盘空间充足"
echo ""

# --------------------------------------------------------------------------------
# 阶段 4：安装编译依赖
# --------------------------------------------------------------------------------
install_deps
echo ""

# --------------------------------------------------------------------------------
# 阶段 5：准备工作目录
# --------------------------------------------------------------------------------
log_info "准备工作目录..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
log_success "工作目录: $WORK_DIR"
echo ""

# --------------------------------------------------------------------------------
# 阶段 6：下载 GoAccess 源代码
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
# 阶段 7：解压源代码
# --------------------------------------------------------------------------------
log_info "解压源代码..."
tar -xzf "$GOACCESS_TAR"
cd "$WORK_DIR/goaccess-${GOACCESS_VERSION}"
log_success "解压完成"
echo ""

# --------------------------------------------------------------------------------
# 阶段 8：配置编译选项
# --------------------------------------------------------------------------------
log_info "配置编译选项..."

# 基础编译参数
config_args="--enable-utf8"

# 检查是否有 GeoIP2 库
if check_command pkg-config && pkg-config --exists libmaxminddb 2>/dev/null; then
    config_args="$config_args --enable-geoip=mmdb"
    log_info "GeoIP2 支持: 已启用"
else
    log_warning "GeoIP2 库未找到，将不启用 GeoIP 支持"
fi

log_info "编译参数: $config_args"

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

# --------------------------------------------------------------------------------
# 阶段 9：编译源代码
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
# 阶段 10：安装到系统
# --------------------------------------------------------------------------------
log_info "安装到系统..."
if ! make install; then
    log_error "安装失败"
    exit 1
fi
log_success "安装完成"
echo ""

# --------------------------------------------------------------------------------
# 阶段 11：更新共享库缓存
# --------------------------------------------------------------------------------
log_info "更新共享库缓存..."
if check_command ldconfig; then
    ldconfig
    log_success "共享库缓存已更新"
else
    log_warning "ldconfig 不可用，跳过"
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 12：验证安装
# --------------------------------------------------------------------------------
print_title "安装验证"

if check_command goaccess; then
    log_success "GoAccess 安装成功！"
    echo ""
    echo -e "${BLUE}版本信息:${NC}"
    goaccess --version
    echo ""
    echo -e "${BLUE}安装路径:${NC}"
    which goaccess
    echo ""
    echo -e "${BLUE}编译特性:${NC}"
    goaccess --help | head -20
else
    log_error "安装验证失败"
    exit 1
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 13：下载免费版 GeoLite2 数据库
# --------------------------------------------------------------------------------
print_title "下载免费版 GeoLite2"

mkdir -p "$GEOIP_DIR"

GEOIP_FILE="${GEOIP_DIR}/GeoLite2-City.mmdb"

if [ -f "$GEOIP_FILE" ]; then
    log_info "数据库文件已存在，跳过下载"
else
    log_info "下载地址: $GEOIP_URL"
    if download_with_retry "$GEOIP_URL" "$GEOIP_FILE"; then
        log_success "GeoLite2 数据库下载成功"
    else
        log_warning "GeoLite2 下载失败，但不影响 GoAccess 使用"
    fi
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 14：完成提示
# --------------------------------------------------------------------------------
print_title "安装完成！"

echo -e "${GREEN}下一步操作：${NC}"
echo "1. 复制 站点配置/配置模板.conf 并创建您的站点配置"
echo "2. 运行 部署配置.sh 部署配置"
echo "3. 运行 分析所有站点.sh 生成报告"
echo "4. 在宝塔面板设置定时任务自动更新报告"
echo ""

if [ "$HAS_SELINUX" = true ]; then
    echo -e "${YELLOW}注意：${NC}"
    echo "SELinux 已启用，如果遇到权限问题可能需要调整设置"
    echo ""
fi

echo -e "${BLUE}详细说明请参考：README.md${NC}"
echo ""
