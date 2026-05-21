#!/bin/bash
# ================================================================================
# 脚本名称：卸载GoAccess.sh
# 功能描述：从服务器彻底卸载和清理 GoAccess 及其相关文件
# 适用环境：宝塔面板 + CentOS/Rocky/AlmaLinux/Debian/Ubuntu/Arch/OpenSUSE
# 创建日期：2026-05-20
#
# 设计思路：
# 1. 确认卸载操作，防止误操作
# 2. 智能检测已安装的 GoAccess
# 3. 完整清理所有相关文件
# 4. 更新系统缓存
# 5. 提供详细清理报告
# ================================================================================

set -eo pipefail

# ================================================================================
# 常量定义区域
# ================================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly GOACCESS_VERSION="1.10.2"
readonly WORK_DIR="/tmp/goaccess-build"
readonly SITES_CONFIG_DIR="${SCRIPT_DIR}/站点配置"
readonly GOACCESS_CONFIG_DIR="/www/wwwroot/GoAccess-管理"

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
# 全局变量区域
# ================================================================================
REMOVE_CONFIG=false
REMOVE_DB=false
REMOVE_ALL=false
CLEANUP_CRON=false
CLEANUP_LOGS=false
REMOVE_DEPS=false
CONFIRM_UNINSTALL=false
GOACCESS_INSTALLED=false
INSTALLED_VERSION=""
INSTALLED_PATH=""
DEBUG_MODE=false

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
    echo -e "${YELLOW}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

log_removed() {
    echo -e "${RED}[REMOVED] $1${NC}"
}

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}"
    fi
}

log_step() {
    echo -e "${BLUE}[STEP] $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    fi
    return 1
}

# ================================================================================
# 获取已安装的 GoAccess 信息
# ================================================================================
get_installed_info() {
    if check_command goaccess; then
        GOACCESS_INSTALLED=true
        INSTALLED_VERSION=$(goaccess --version 2>&1 | grep -oE '([0-9]+\.){2}[0-9]+' | head -1)
        INSTALLED_PATH=$(which goaccess)
        log_info "检测到已安装的 GoAccess"
        log_info "  版本: $INSTALLED_VERSION"
        log_info "  路径: $INSTALLED_PATH"
        return 0
    else
        GOACCESS_INSTALLED=false
        return 1
    fi
}

# ================================================================================
# 显示使用方法
# ================================================================================
show_usage() {
    echo "用法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -a, --all          移除所有文件（包括配置和GoAccess配置）"
    echo "  -c, --config       移除站点配置文件"
    echo "  -d, --database     移除 GoAccess 配置文件"
    echo "  -C, --cron         自动清理定时任务"
    echo "  -L, --logs         自动清理日志和HTML报告"
    echo "  -D, --deps         自动卸载编译依赖（gcc make wget）"
    echo "  -m, --menu         显示交互式菜单"
    echo "  -y, --yes          跳过确认直接卸载"
    echo "  --debug            启用调试模式，显示详细日志"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $SCRIPT_NAME -y              # 跳过确认，直接卸载程序"
    echo "  $SCRIPT_NAME -a              # 完全卸载，包括所有文件"
    echo "  $SCRIPT_NAME -c -d -y        # 卸载程序并清理配置"
    echo "  $SCRIPT_NAME -C -L -y        # 自动清理定时任务和日志"
    echo "  $SCRIPT_NAME -a -C -L -D -y  # 完整清理，包括依赖卸载"
    echo "  $SCRIPT_NAME -m              # 显示交互式菜单"
}

# ================================================================================
# 交互式菜单
# ================================================================================
show_menu() {
    local choice
    while true; do
        print_title "GoAccess 卸载 - 选择操作"
        echo ""
        echo "  1. 卸载 GoAccess 主程序"
        echo "  2. 清理定时任务"
        echo "  3. 清理日志和HTML报告"
        echo "  4. 卸载编译依赖"
        echo "  5. 退出"
        echo ""
        print_separator
        read -p "请输入选项 [1-5]: " choice
        
        case "$choice" in
            1)
                echo ""
                log_info "执行：卸载 GoAccess 主程序"
                REMOVE_ALL=true
                CONFIRM_UNINSTALL=true
                CLEANUP_CRON=false
                CLEANUP_LOGS=false
                REMOVE_DEPS=false
                run_uninstall
                ;;
            2)
                echo ""
                log_info "执行：清理定时任务"
                CLEANUP_CRON=true
                CONFIRM_UNINSTALL=true
                cleanup_cron
                ;;
            3)
                echo ""
                log_info "执行：清理日志和HTML报告"
                CLEANUP_LOGS=true
                cleanup_logs
                ;;
            4)
                echo ""
                log_info "执行：卸载编译依赖"
                REMOVE_DEPS=true
                cleanup_deps
                ;;
            5)
                echo ""
                log_info "已退出"
                exit 0
                ;;
            *)
                echo ""
                log_error "无效选项，请输入 1-5"
                echo ""
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..." 
    done
}

run_uninstall() {
    get_installed_info
    
    remove_goaccess_binary
    remove_build_files
    remove_lib_files
    remove_header_files
    remove_man_pages
    remove_doc_files
    update_system_cache
    remove_config_files
    remove_goaccess_config
    cleanup_residual
    
    verify_uninstall
}

# ================================================================================
# 解析命令行参数
# ================================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                REMOVE_ALL=true
                REMOVE_CONFIG=true
                REMOVE_DB=true
                shift
                ;;
            -c|--config)
                REMOVE_CONFIG=true
                shift
                ;;
            -d|--database)
                REMOVE_DB=true
                shift
                ;;
            -C|--cron)
                CLEANUP_CRON=true
                shift
                ;;
            -L|--logs)
                CLEANUP_LOGS=true
                shift
                ;;
            -D|--deps)
                REMOVE_DEPS=true
                shift
                ;;
            -m|--menu)
                show_menu
                exit 0
                ;;
            -y|--yes)
                CONFIRM_UNINSTALL=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                log_info "调试模式已启用"
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
}

# ================================================================================
# 确认卸载
# ================================================================================
confirm_uninstall() {
    echo ""
    print_separator
    echo -e "${RED}警告：此操作将执行以下清理：${NC}"
    print_separator
    echo ""
    
    echo "1. 停止并移除 GoAccess 主程序"
    if [ "$GOACCESS_INSTALLED" = true ]; then
        echo "   - 版本: $INSTALLED_VERSION"
        echo "   - 路径: $INSTALLED_PATH"
    fi
    
    echo "2. 移除编译中间文件"
    echo "   - 临时目录: $WORK_DIR"
    
    echo "3. 移除系统缓存"
    echo "   - 更新 ldconfig"
    
    if [ "$REMOVE_CONFIG" = true ]; then
        echo "4. 移除站点配置文件"
        echo "   - 目录: $SITES_CONFIG_DIR"
    fi
    
    if [ "$REMOVE_DB" = true ]; then
        echo "5. 移除 GoAccess 配置文件"
        echo "   - 文件: ${GOACCESS_CONFIG_DIR}/goaccess.conf"
        echo "   - 注意: 仅删除配置文件，不删除项目目录"
    fi
    
    echo ""
    print_separator
    echo -e "${RED}此操作不可逆！${NC}"
    print_separator
    echo ""
    
    read -p "确定要继续吗？[y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "操作已取消"
        exit 0
    fi
}

# ================================================================================
# 阶段 1：移除 GoAccess 主程序
# ================================================================================
remove_goaccess_binary() {
    print_title "阶段 1：移除 GoAccess 主程序"
    
    log_step "开始检查 GoAccess 安装状态"
    log_debug "GOACCESS_INSTALLED=$GOACCESS_INSTALLED"
    
    if [ "$GOACCESS_INSTALLED" = true ]; then
        log_info "正在移除 GoAccess 二进制文件..."
        log_debug "目标路径: $INSTALLED_PATH"
        
        local binary_path="$INSTALLED_PATH"
        
        if [ -f "$binary_path" ]; then
            log_debug "文件存在，准备删除: $binary_path"
            if rm -f "$binary_path"; then
                log_removed "已移除: $binary_path"
                log_debug "删除成功"
            else
                log_error "移除失败: $binary_path"
                log_debug "删除失败，可能权限不足"
                return 1
            fi
        else
            log_debug "文件不存在: $binary_path"
        fi
        
        log_info "移除可能的其他 GoAccess 相关文件..."
        local other_binaries=(
            "/usr/local/bin/goaccess"
            "/usr/bin/goaccess"
            "/bin/goaccess"
        )
        
        local found_count=0
        for bin_path in "${other_binaries[@]}"; do
            log_debug "检查路径: $bin_path"
            if [ -f "$bin_path" ] && [ "$bin_path" != "$binary_path" ]; then
                log_debug "发现额外文件: $bin_path"
                if rm -f "$bin_path"; then
                    log_removed "已移除: $bin_path"
                    found_count=$((found_count + 1))
                fi
            fi
        done
        
        log_debug "共移除 $found_count 个额外文件"
        log_success "GoAccess 主程序已移除"
    else
        log_warning "未检测到已安装的 GoAccess，跳过"
        log_debug "跳过主程序移除步骤"
    fi
    echo ""
}

# ================================================================================
# 阶段 2：移除编译文件
# ================================================================================
remove_build_files() {
    print_title "阶段 2：移除编译文件"
    
    log_step "开始清理编译中间文件"
    log_debug "WORK_DIR=$WORK_DIR"
    
    if [ -d "$WORK_DIR" ]; then
        log_debug "编译目录存在，准备删除: $WORK_DIR"
        if rm -rf "$WORK_DIR"; then
            log_removed "已移除: $WORK_DIR"
            log_success "编译文件清理完成"
        else
            log_error "移除失败: $WORK_DIR"
            log_debug "删除失败，可能目录被占用或权限不足"
        fi
    else
        log_info "编译目录不存在，跳过"
        log_debug "目录不存在: $WORK_DIR"
    fi
    
    log_info "清理源码包..."
    local tar_file="/tmp/goaccess-${GOACCESS_VERSION}.tar.gz"
    log_debug "检查源码包: $tar_file"
    if [ -f "$tar_file" ]; then
        rm -f "$tar_file"
        log_removed "已移除: $tar_file"
    else
        log_debug "源码包不存在: $tar_file"
    fi
    
    local build_dir="/tmp/goaccess-${GOACCESS_VERSION}"
    log_debug "检查编译目录: $build_dir"
    if [ -d "$build_dir" ]; then
        rm -rf "$build_dir"
        log_removed "已移除: $build_dir"
    else
        log_debug "编译目录不存在: $build_dir"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 3：移除已编译的库文件
# ================================================================================
remove_lib_files() {
    print_title "阶段 3：移除已编译的库文件"
    
    log_step "开始清理 lib 文件"
    
    local lib_files=(
        "/usr/local/lib/libgoaccess.a"
        "/usr/local/lib/libgoaccess.la"
        "/usr/local/lib/libgoaccess.so"
        "/usr/local/lib/libgoaccess.so.0"
        "/usr/local/lib/libgoaccess.so.0.0.0"
    )
    
    local removed_count=0
    local checked_count=0
    
    for lib_path in "${lib_files[@]}"; do
        checked_count=$((checked_count + 1))
        log_debug "检查库文件 [$checked_count/${#lib_files[@]}]: $lib_path"
        if [ -f "$lib_path" ]; then
            log_debug "发现库文件，准备删除: $lib_path"
            rm -f "$lib_path"
            log_removed "已移除: $lib_path"
            removed_count=$((removed_count + 1))
        fi
    done
    
    log_debug "共检查 $checked_count 个文件，移除 $removed_count 个"
    
    if [ $removed_count -gt 0 ]; then
        log_success "已移除 $removed_count 个库文件"
    else
        log_info "未找到 lib 文件"
    fi
    
    log_info "清理 pkg-config 文件..."
    local pc_file="/usr/local/lib/pkgconfig/goaccess.pc"
    log_debug "检查 pkg-config 文件: $pc_file"
    if [ -f "$pc_file" ]; then
        rm -f "$pc_file"
        log_removed "已移除: $pc_file"
    else
        log_debug "pkg-config 文件不存在: $pc_file"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 4：移除头文件
# ================================================================================
remove_header_files() {
    print_title "阶段 4：移除头文件"
    
    log_step "开始清理 include 目录"
    
    local include_dir="/usr/local/include/goaccess"
    log_debug "检查头文件目录: $include_dir"
    
    if [ -d "$include_dir" ]; then
        log_debug "头文件目录存在，准备删除: $include_dir"
        rm -rf "$include_dir"
        log_removed "已移除: $include_dir"
        log_success "头文件清理完成"
    else
        log_info "include 目录不存在，跳过"
        log_debug "头文件目录不存在: $include_dir"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 5：移除 man 页面
# ================================================================================
remove_man_pages() {
    print_title "阶段 5：移除 man 页面"
    
    log_step "开始清理 man 页面"
    
    local man_pages=(
        "/usr/local/share/man/man1/goaccess.1"
        "/usr/local/share/man/man8/goaccess.8"
    )
    
    local removed_count=0
    local checked_count=0
    
    for man_path in "${man_pages[@]}"; do
        checked_count=$((checked_count + 1))
        log_debug "检查 man 页面 [$checked_count/${#man_pages[@]}]: $man_path"
        if [ -f "$man_path" ]; then
            log_debug "发现 man 页面，准备删除: $man_path"
            rm -f "$man_path"
            log_removed "已移除: $man_path"
            removed_count=$((removed_count + 1))
        fi
        if [ -f "${man_path}.gz" ]; then
            log_debug "发现压缩 man 页面，准备删除: ${man_path}.gz"
            rm -f "${man_path}.gz"
            log_removed "已移除: ${man_path}.gz"
            removed_count=$((removed_count + 1))
        fi
    done
    
    log_debug "共检查 $checked_count 个路径，移除 $removed_count 个文件"
    
    if [ $removed_count -gt 0 ]; then
        log_success "已移除 $removed_count 个 man 页面"
    else
        log_info "未找到 man 页面"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 6：移除文档文件
# ================================================================================
remove_doc_files() {
    print_title "阶段 6：移除文档文件"
    
    log_step "开始清理文档目录"
    
    local doc_dirs=(
        "/usr/local/share/doc/goaccess"
        "/usr/local/share/doc/goaccess-${GOACCESS_VERSION}"
    )
    
    local removed_count=0
    local checked_count=0
    
    for doc_path in "${doc_dirs[@]}"; do
        checked_count=$((checked_count + 1))
        log_debug "检查文档目录 [$checked_count/${#doc_dirs[@]}]: $doc_path"
        if [ -d "$doc_path" ]; then
            log_debug "发现文档目录，准备删除: $doc_path"
            rm -rf "$doc_path"
            log_removed "已移除: $doc_path"
            removed_count=$((removed_count + 1))
        fi
    done
    
    log_debug "共检查 $checked_count 个目录，移除 $removed_count 个"
    
    if [ $removed_count -gt 0 ]; then
        log_success "已移除 $removed_count 个文档目录"
    else
        log_info "未找到文档目录"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 7：更新系统缓存
# ================================================================================
update_system_cache() {
    print_title "阶段 7：更新系统缓存"
    
    log_step "开始更新系统缓存"
    
    log_info "更新 ldconfig 缓存..."
    log_debug "检查 ldconfig 命令是否可用"
    
    if check_command ldconfig; then
        log_debug "ldconfig 命令可用，执行 ldconfig"
        ldconfig 2>/dev/null || true
        log_success "共享库缓存已更新"
    else
        log_info "ldconfig 不可用，跳过"
        log_debug "ldconfig 命令不存在"
    fi
    
    log_info "清理 locate 数据库..."
    log_debug "检查 updatedb 命令是否可用"
    
    if check_command updatedb; then
        log_debug "updatedb 命令可用，执行 updatedb"
        updatedb 2>/dev/null || true
        log_info "locate 数据库已更新"
    else
        log_debug "updatedb 命令不存在，跳过"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 8：移除配置文件
# ================================================================================
remove_config_files() {
    print_title "阶段 8：移除配置文件"
    
    log_step "开始处理配置文件"
    log_debug "REMOVE_CONFIG=$REMOVE_CONFIG"
    
    if [ "$REMOVE_CONFIG" = true ]; then
        log_info "正在移除站点配置文件..."
        log_debug "站点配置目录: $SITES_CONFIG_DIR"
        
        if [ -d "$SITES_CONFIG_DIR" ]; then
            local config_count=$(find "$SITES_CONFIG_DIR" -name "*.conf" 2>/dev/null | wc -l)
            log_debug "发现 $config_count 个配置文件"
            
            if rm -rf "$SITES_CONFIG_DIR"; then
                log_removed "已移除: $SITES_CONFIG_DIR"
                log_success "已清理 $config_count 个配置文件"
            else
                log_error "移除失败: $SITES_CONFIG_DIR"
                log_debug "删除失败，可能目录被占用或权限不足"
            fi
        else
            log_info "站点配置目录不存在，跳过"
            log_debug "目录不存在: $SITES_CONFIG_DIR"
        fi
        
        log_info "清理可能残留的 GoAccess 配置..."
        local residual_configs=(
            "/etc/goaccess.conf"
            "/usr/local/etc/goaccess.conf"
            "~/.goaccessrc"
        )
        
        local found_count=0
        for config_path in "${residual_configs[@]}"; do
            log_debug "检查残留配置: $config_path"
            expanded_path="${config_path/#\~/$HOME}"
            if [ -f "$expanded_path" ]; then
                log_debug "发现残留配置，准备删除: $expanded_path"
                rm -f "$expanded_path"
                log_removed "已移除: $expanded_path"
                found_count=$((found_count + 1))
            fi
        done
        
        log_debug "共发现并移除 $found_count 个残留配置"
    else
        log_info "跳过配置文件移除（使用 -c 或 --all 选项可移除）"
        log_debug "REMOVE_CONFIG=false，跳过此步骤"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 9：移除 GoAccess 配置文件
# ================================================================================
remove_goaccess_config() {
    print_title "阶段 9：移除 GoAccess 配置文件"
    
    log_step "开始处理 GoAccess 配置文件"
    log_debug "REMOVE_DB=$REMOVE_DB"
    
    if [ "$REMOVE_DB" = true ]; then
        log_info "正在移除 GoAccess 配置文件..."
        
        local config_file="${GOACCESS_CONFIG_DIR}/goaccess.conf"
        log_debug "配置文件路径: $config_file"
        
        if [ -f "$config_file" ]; then
            log_debug "配置文件存在，准备删除: $config_file"
            rm -f "$config_file"
            log_removed "已移除: $config_file"
        else
            log_info "GoAccess 配置文件不存在，跳过"
            log_debug "配置文件不存在: $config_file"
        fi
        
        log_info "清理用户目录下的配置..."
        local home_db="${HOME}/.config/goaccess/GeoLite2-City.mmdb"
        log_debug "检查用户目录配置: $home_db"
        
        if [ -f "$home_db" ]; then
            log_debug "发现用户目录配置，准备删除: $home_db"
            rm -f "$home_db"
            log_removed "已移除: $home_db"
        else
            log_debug "用户目录配置不存在: $home_db"
        fi
        
        log_info "注意：配置文件目录 $GOACCESS_CONFIG_DIR 为项目目录，不会删除整个目录"
    else
        log_info "跳过 GoAccess 配置文件移除（使用 -d 或 --all 选项可移除）"
        log_debug "REMOVE_DB=false，跳过此步骤"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 10：清理残留数据
# ================================================================================
cleanup_residual() {
    print_title "阶段 10：清理残留数据"
    
    log_step "开始清理残留数据"
    
    log_info "清理可能的缓存文件..."
    
    local cache_dirs=(
        "/tmp/goaccess-*"
        "/var/cache/goaccess"
        "/var/tmp/goaccess*"
    )
    
    local cache_count=0
    for cache_pattern in "${cache_dirs[@]}"; do
        log_debug "检查缓存模式: $cache_pattern"
        if ls $cache_pattern 1> /dev/null 2>&1; then
            log_debug "发现匹配的缓存: $cache_pattern"
            rm -rf $cache_pattern 2>/dev/null || true
            log_removed "已清理: $cache_pattern"
            cache_count=$((cache_count + 1))
        fi
    done
    
    log_debug "共清理 $cache_count 个缓存目录"
    
    log_success "残留数据清理完成"
    echo ""
}

# ================================================================================
# 阶段 11：验证卸载结果
# ================================================================================
verify_uninstall() {
    print_title "阶段 11：验证卸载结果"
    
    log_step "开始验证卸载结果"
    
    local verify_passed=true
    
    log_debug "检查 GoAccess 命令是否仍然存在"
    if check_command goaccess; then
        log_error "GoAccess 仍然存在: $(which goaccess)"
        log_debug "验证失败：GoAccess 命令仍然可用"
        verify_passed=false
    else
        log_success "GoAccess 二进制文件已完全移除"
        log_debug "验证通过：GoAccess 命令已不存在"
    fi
    
    log_debug "检查编译目录是否仍然存在"
    if [ -d "$WORK_DIR" ]; then
        log_warning "编译目录未完全清理: $WORK_DIR"
        log_debug "验证失败：编译目录仍然存在"
        verify_passed=false
    else
        log_success "编译目录已清理"
        log_debug "验证通过：编译目录已清理"
    fi
    
    log_debug "检查站点配置目录是否仍然存在"
    if [ "$REMOVE_CONFIG" = true ] && [ -d "$SITES_CONFIG_DIR" ]; then
        log_warning "站点配置目录未完全清理: $SITES_CONFIG_DIR"
        log_debug "验证失败：站点配置目录仍然存在"
        verify_passed=false
    fi
    
    echo ""
    
    if [ "$verify_passed" = true ]; then
        log_debug "所有验证通过"
        print_title "卸载完成！"
        return 0
    else
        log_debug "部分验证未通过"
        print_title "卸载完成（部分残留，见上方警告）"
        return 1
    fi
}

# ================================================================================
# 清理定时任务
# ================================================================================
cleanup_cron() {
    print_title "清理定时任务"
    
    log_step "开始清理定时任务"
    log_debug "CLEANUP_CRON=$CLEANUP_CRON"
    
    if [ "$CLEANUP_CRON" = true ]; then
        log_info "正在清理定时任务..."
        log_debug "检查 crontab 命令是否可用"
        
        if check_command crontab; then
            log_debug "crontab 命令可用"
            local cron_list=$(sudo crontab -l 2>/dev/null || true)
            log_debug "当前定时任务列表长度: ${#cron_list}"
            
            if [ -n "$cron_list" ]; then
                log_debug "发现定时任务，开始过滤 GoAccess 相关任务"
                local filtered_cron=$(echo "$cron_list" | grep -v "GoAccess" | grep -v "goaccess" || true)
                log_debug "过滤后定时任务长度: ${#filtered_cron}"
                
                if [ -n "$filtered_cron" ]; then
                    echo "$filtered_cron" | sudo crontab -
                    log_success "定时任务已清理（保留非 GoAccess 相关任务）"
                else
                    log_debug "过滤后无剩余任务，删除所有定时任务"
                    sudo crontab -r 2>/dev/null || true
                    log_success "所有定时任务已清理"
                fi
            else
                log_info "未发现定时任务"
            fi
        else
            log_warning "crontab 不可用，跳过定时任务清理"
            log_debug "crontab 命令不存在"
        fi
    else
        log_info "跳过定时任务清理（使用 -C 选项可自动清理）"
        log_debug "CLEANUP_CRON=false，跳过此步骤"
        
        echo -e "${CYAN}如果之前配置了定时任务，请手动清理：${NC}"
        echo ""
        echo "1. 登录宝塔面板"
        echo "2. 进入 [计划任务] 设置"
        echo "3. 删除与 GoAccess 相关的定时任务"
        echo ""
    fi
    
    echo ""
}

# ================================================================================
# 清理日志和HTML报告
# ================================================================================
cleanup_logs() {
    print_title "清理日志和HTML报告"
    
    log_step "开始清理日志和HTML报告"
    log_debug "CLEANUP_LOGS=$CLEANUP_LOGS"
    
    log_debug "搜索 HTML 报告文件..."
    local html_count=$(find /www/wwwroot -name '*-log.html' 2>/dev/null | wc -l)
    log_debug "发现 $html_count 个 HTML 报告文件"
    
    echo ""
    echo "  发现 $html_count 个 HTML 报告文件"
    echo ""
    
    if [ "$CLEANUP_LOGS" = true ]; then
        log_info "自动清理模式已启用"
        log_info "正在清理日志文件..."
        
        if [ "$html_count" -gt 0 ]; then
            log_debug "开始删除 HTML 报告文件..."
            find /www/wwwroot -name '*-log.html' -delete
            log_removed "已清理 $html_count 个 HTML 报告文件"
        else
            log_info "未找到 HTML 报告文件"
        fi
        
        log_success "日志清理完成"
    else
        log_debug "进入交互选择模式"
        local choice
        echo "  1. 清理所有 HTML 报告"
        echo "  2. 跳过清理"
        echo ""
        read -p "  请选择清理选项 [1-2]: " choice
        log_debug "用户选择: $choice"
        
        case "$choice" in
            1)
                if [ "$html_count" -gt 0 ]; then
                    log_debug "执行：清理 HTML 报告文件"
                    find /www/wwwroot -name '*-log.html' -delete
                    log_success "已清理 $html_count 个 HTML 报告文件"
                else
                    log_info "未找到 HTML 报告文件"
                fi
                ;;
            2)
                log_info "跳过日志清理"
                log_debug "用户选择跳过清理"
                ;;
            *)
                log_error "无效选项"
                log_debug "用户输入无效选项: $choice"
                ;;
        esac
    fi
    
    echo ""
}

# ================================================================================
# 卸载编译依赖
# ================================================================================
cleanup_deps() {
    print_title "卸载编译依赖"
    
    log_step "开始卸载编译依赖"
    log_debug "REMOVE_DEPS=$REMOVE_DEPS"
    
    log_debug "检查编译工具是否存在..."
    if check_command gcc || check_command make || check_command wget; then
        log_info "检测到以下编译工具:"
        check_command gcc && echo "  - gcc" && log_debug "gcc 存在"
        check_command make && echo "  - make" && log_debug "make 存在"
        check_command wget && echo "  - wget" && log_debug "wget 存在"
        echo ""
        
        local system_type=""
        local pkg_cmd=""
        
        log_debug "检测系统包管理器..."
        if check_command apt-get; then
            system_type="Debian/Ubuntu"
            pkg_cmd="sudo apt-get remove --purge gcc make wget"
            log_debug "检测到 apt-get 包管理器"
        elif check_command dnf; then
            system_type="Fedora"
            pkg_cmd="sudo dnf remove gcc make wget"
            log_debug "检测到 dnf 包管理器"
        elif check_command yum; then
            system_type="CentOS/Rocky/AlmaLinux"
            pkg_cmd="sudo yum remove gcc make wget"
            log_debug "检测到 yum 包管理器"
        fi
        
        if [ -n "$system_type" ]; then
            echo "  系统类型: $system_type"
            echo "  卸载命令: $pkg_cmd"
            echo ""
            
            if [ "$REMOVE_DEPS" = true ]; then
                log_info "自动卸载编译依赖..."
                log_debug "执行卸载命令: $pkg_cmd -y"
                sudo $pkg_cmd -y
                log_success "编译依赖已卸载"
            else
                local choice
                echo "  是否卸载编译依赖 (gcc make wget)?"
                echo ""
                read -p "  确认卸载? [y/N]: " choice
                log_debug "用户选择: $choice"
                
                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    log_info "正在卸载编译依赖..."
                    log_debug "执行卸载命令: $pkg_cmd -y"
                    sudo $pkg_cmd -y
                    log_success "编译依赖已卸载"
                else
                    log_info "跳过编译依赖卸载"
                    log_debug "用户选择不卸载"
                fi
            fi
        else
            log_error "无法识别包管理器，跳过依赖卸载"
            log_debug "未检测到支持的包管理器"
        fi
    else
        log_info "未检测到 gcc、make、wget，跳过编译依赖卸载"
        log_debug "编译工具不存在，跳过卸载"
    fi
    
    echo ""
}

# ================================================================================
# 主函数
# ================================================================================
main() {
    echo ""
    print_title "GoAccess 彻底卸载脚本"
    echo ""
    
    log_step "脚本启动"
    log_debug "脚本目录: $SCRIPT_DIR"
    log_debug "GoAccess 版本: $GOACCESS_VERSION"
    log_debug "工作目录: $WORK_DIR"
    log_debug "配置目录: $GOACCESS_CONFIG_DIR"
    log_debug "站点配置目录: $SITES_CONFIG_DIR"
    
    log_info "解析命令行参数..."
    parse_args "$@"
    log_debug "参数解析完成"
    log_debug "REMOVE_CONFIG=$REMOVE_CONFIG, REMOVE_DB=$REMOVE_DB, REMOVE_ALL=$REMOVE_ALL"
    log_debug "CLEANUP_CRON=$CLEANUP_CRON, CLEANUP_LOGS=$CLEANUP_LOGS, REMOVE_DEPS=$REMOVE_DEPS"
    
    log_info "检测 GoAccess 安装状态..."
    if ! get_installed_info; then
        log_warning "未检测到已安装的 GoAccess"
        log_debug "GOACCESS_INSTALLED=false"
        
        if [ "$REMOVE_CONFIG" = false ] && [ "$REMOVE_DB" = false ]; then
            log_info "将仅清理残留文件..."
            log_debug "启用配置和数据库清理选项"
            REMOVE_CONFIG=true
            REMOVE_DB=true
        fi
    fi
    
    if [ "$CONFIRM_UNINSTALL" = false ]; then
        log_debug "需要用户确认卸载"
        confirm_uninstall
    else
        log_debug "跳过确认步骤（CONFIRM_UNINSTALL=true）"
    fi
    
    log_step "开始执行卸载流程..."
    
    remove_goaccess_binary
    remove_build_files
    remove_lib_files
    remove_header_files
    remove_man_pages
    remove_doc_files
    update_system_cache
    remove_config_files
    remove_goaccess_config
    cleanup_residual
    
    cleanup_cron
    cleanup_logs
    cleanup_deps
    
    verify_uninstall
    
    log_step "卸载流程完成"
    exit 0
}

main "$@"