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
readonly GEOIP_DIR="/usr/share/GeoIP"
readonly SITES_CONFIG_DIR="${SCRIPT_DIR}/站点配置"

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
    echo "  -a, --all          移除所有文件（包括配置和数据库）"
    echo "  -c, --config       移除站点配置文件"
    echo "  -d, --database     移除 GeoIP 数据库"
    echo "  -C, --cron         自动清理定时任务"
    echo "  -L, --logs         自动清理日志和历史数据库"
    echo "  -D, --deps         自动卸载编译依赖（gcc make wget）"
    echo "  -m, --menu         显示交互式菜单"
    echo "  -y, --yes          跳过确认直接卸载"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $SCRIPT_NAME -y              # 跳过确认，直接卸载程序"
    echo "  $SCRIPT_NAME -a              # 完全卸载，包括所有文件"
    echo "  $SCRIPT_NAME -c -d -y        # 卸载程序并清理配置和数据库"
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
        echo "  3. 清理日志和历史数据库"
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
                log_info "执行：清理日志和历史数据库"
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
    remove_geoip_database
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
        echo "5. 移除 GeoIP 数据库"
        echo "   - 目录: $GEOIP_DIR"
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
    
    if [ "$GOACCESS_INSTALLED" = true ]; then
        log_info "正在移除 GoAccess 二进制文件..."
        
        local binary_path="$INSTALLED_PATH"
        
        if [ -f "$binary_path" ]; then
            if rm -f "$binary_path"; then
                log_removed "已移除: $binary_path"
            else
                log_error "移除失败: $binary_path"
                return 1
            fi
        fi
        
        log_info "移除可能的其他 GoAccess 相关文件..."
        local other_binaries=(
            "/usr/local/bin/goaccess"
            "/usr/bin/goaccess"
            "/bin/goaccess"
        )
        
        for bin_path in "${other_binaries[@]}"; do
            if [ -f "$bin_path" ] && [ "$bin_path" != "$binary_path" ]; then
                if rm -f "$bin_path"; then
                    log_removed "已移除: $bin_path"
                fi
            fi
        done
        
        log_success "GoAccess 主程序已移除"
    else
        log_warning "未检测到已安装的 GoAccess，跳过"
    fi
    echo ""
}

# ================================================================================
# 阶段 2：移除编译文件
# ================================================================================
remove_build_files() {
    print_title "阶段 2：移除编译文件"
    
    log_info "正在清理编译中间文件..."
    
    if [ -d "$WORK_DIR" ]; then
        if rm -rf "$WORK_DIR"; then
            log_removed "已移除: $WORK_DIR"
            log_success "编译文件清理完成"
        else
            log_error "移除失败: $WORK_DIR"
        fi
    else
        log_info "编译目录不存在，跳过"
    fi
    
    log_info "清理源码包..."
    local tar_file="/tmp/goaccess-${GOACCESS_VERSION}.tar.gz"
    if [ -f "$tar_file" ]; then
        rm -f "$tar_file"
        log_removed "已移除: $tar_file"
    fi
    
    local build_dir="/tmp/goaccess-${GOACCESS_VERSION}"
    if [ -d "$build_dir" ]; then
        rm -rf "$build_dir"
        log_removed "已移除: $build_dir"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 3：移除已编译的库文件
# ================================================================================
remove_lib_files() {
    print_title "阶段 3：移除已编译的库文件"
    
    log_info "清理 lib 文件..."
    
    local lib_files=(
        "/usr/local/lib/libgoaccess.a"
        "/usr/local/lib/libgoaccess.la"
        "/usr/local/lib/libgoaccess.so"
        "/usr/local/lib/libgoaccess.so.0"
        "/usr/local/lib/libgoaccess.so.0.0.0"
    )
    
    local removed_count=0
    for lib_path in "${lib_files[@]}"; do
        if [ -f "$lib_path" ]; then
            rm -f "$lib_path"
            log_removed "已移除: $lib_path"
            removed_count=$((removed_count + 1))
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        log_success "已移除 $removed_count 个库文件"
    else
        log_info "未找到 lib 文件"
    fi
    
    log_info "清理 pkg-config 文件..."
    if [ -f "/usr/local/lib/pkgconfig/goaccess.pc" ]; then
        rm -f "/usr/local/lib/pkgconfig/goaccess.pc"
        log_removed "已移除: /usr/local/lib/pkgconfig/goaccess.pc"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 4：移除头文件
# ================================================================================
remove_header_files() {
    print_title "阶段 4：移除头文件"
    
    log_info "清理 include 目录..."
    
    local include_dir="/usr/local/include/goaccess"
    if [ -d "$include_dir" ]; then
        rm -rf "$include_dir"
        log_removed "已移除: $include_dir"
        log_success "头文件清理完成"
    else
        log_info "include 目录不存在，跳过"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 5：移除 man 页面
# ================================================================================
remove_man_pages() {
    print_title "阶段 5：移除 man 页面"
    
    log_info "清理 man 页面..."
    
    local man_pages=(
        "/usr/local/share/man/man1/goaccess.1"
        "/usr/local/share/man/man8/goaccess.8"
    )
    
    local removed_count=0
    for man_path in "${man_pages[@]}"; do
        if [ -f "$man_path" ]; then
            rm -f "$man_path"
            log_removed "已移除: $man_path"
            removed_count=$((removed_count + 1))
        fi
        if [ -f "${man_path}.gz" ]; then
            rm -f "${man_path}.gz"
            log_removed "已移除: ${man_path}.gz"
            removed_count=$((removed_count + 1))
        fi
    done
    
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
    
    log_info "清理文档目录..."
    
    local doc_dirs=(
        "/usr/local/share/doc/goaccess"
        "/usr/local/share/doc/${GOACCESS_TAR%.tar.gz}"
    )
    
    local removed_count=0
    for doc_path in "${doc_dirs[@]}"; do
        if [ -d "$doc_path" ]; then
            rm -rf "$doc_path"
            log_removed "已移除: $doc_path"
            removed_count=$((removed_count + 1))
        fi
    done
    
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
    
    log_info "更新 ldconfig 缓存..."
    
    if check_command ldconfig; then
        ldconfig 2>/dev/null || true
        log_success "共享库缓存已更新"
    else
        log_info "ldconfig 不可用，跳过"
    fi
    
    log_info "清理 locate 数据库..."
    if check_command updatedb; then
        updatedb 2>/dev/null || true
        log_info "locate 数据库已更新"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 8：移除配置文件
# ================================================================================
remove_config_files() {
    print_title "阶段 8：移除配置文件"
    
    if [ "$REMOVE_CONFIG" = true ]; then
        log_info "正在移除站点配置文件..."
        
        if [ -d "$SITES_CONFIG_DIR" ]; then
            local config_count=$(find "$SITES_CONFIG_DIR" -name "*.conf" 2>/dev/null | wc -l)
            
            if rm -rf "$SITES_CONFIG_DIR"; then
                log_removed "已移除: $SITES_CONFIG_DIR"
                log_success "已清理 $config_count 个配置文件"
            else
                log_error "移除失败: $SITES_CONFIG_DIR"
            fi
        else
            log_info "站点配置目录不存在，跳过"
        fi
        
        log_info "清理可能残留的 GoAccess 配置..."
        local residual_configs=(
            "/etc/goaccess.conf"
            "/usr/local/etc/goaccess.conf"
            "~/.goaccessrc"
        )
        
        for config_path in "${residual_configs[@]}"; do
            expanded_path="${config_path/#\~/$HOME}"
            if [ -f "$expanded_path" ]; then
                rm -f "$expanded_path"
                log_removed "已移除: $expanded_path"
            fi
        done
    else
        log_info "跳过配置文件移除（使用 -c 或 --all 选项可移除）"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 9：移除 GeoIP 数据库
# ================================================================================
remove_geoip_database() {
    print_title "阶段 9：移除 GeoIP 数据库"
    
    if [ "$REMOVE_DB" = true ]; then
        log_info "正在移除 GeoIP 数据库..."
        
        if [ -d "$GEOIP_DIR" ]; then
            local db_files=$(find "$GEOIP_DIR" -name "*.mmdb" 2>/dev/null | wc -l)
            
            if rm -rf "$GEOIP_DIR"; then
                log_removed "已移除: $GEOIP_DIR"
                log_success "已清理 $db_files 个 GeoIP 数据库文件"
            else
                log_error "移除失败: $GEOIP_DIR"
            fi
        else
            log_info "GeoIP 目录不存在，跳过"
        fi
        
        log_info "清理用户目录下的数据库..."
        local home_db="${HOME}/.config/goaccess/GeoLite2-City.mmdb"
        if [ -f "$home_db" ]; then
            rm -f "$home_db"
            log_removed "已移除: $home_db"
        fi
    else
        log_info "跳过 GeoIP 数据库移除（使用 -d 或 --all 选项可移除）"
    fi
    
    echo ""
}

# ================================================================================
# 阶段 10：清理残留数据
# ================================================================================
cleanup_residual() {
    print_title "阶段 10：清理残留数据"
    
    log_info "清理可能的缓存文件..."
    
    local cache_dirs=(
        "/tmp/goaccess-*"
        "/var/cache/goaccess"
        "/var/tmp/goaccess*"
    )
    
    for cache_pattern in "${cache_dirs[@]}"; do
        if ls $cache_pattern 1> /dev/null 2>&1; then
            rm -rf $cache_pattern 2>/dev/null || true
            log_removed "已清理: $cache_pattern"
        fi
    done
    
    log_info "清理历史数据目录..."
    local history_dirs=(
        "${SCRIPT_DIR}/历史数据"
        "${SCRIPT_DIR}/goaccess_history"
    )
    
    for history_path in "${history_dirs[@]}"; do
        if [ -d "$history_path" ]; then
            local db_count=$(find "$history_path" -name "*.db" 2>/dev/null | wc -l)
            rm -rf "$history_path"
            log_removed "已移除: $history_path ($db_count 个数据库文件)"
        fi
    done
    
    log_success "残留数据清理完成"
    echo ""
}

# ================================================================================
# 阶段 11：验证卸载结果
# ================================================================================
verify_uninstall() {
    print_title "阶段 11：验证卸载结果"
    
    local verify_passed=true
    
    if check_command goaccess; then
        log_error "GoAccess 仍然存在: $(which goaccess)"
        verify_passed=false
    else
        log_success "GoAccess 二进制文件已完全移除"
    fi
    
    if [ -d "$WORK_DIR" ]; then
        log_warning "编译目录未完全清理: $WORK_DIR"
        verify_passed=false
    else
        log_success "编译目录已清理"
    fi
    
    if [ "$REMOVE_DB" = true ] && [ -d "$GEOIP_DIR" ]; then
        log_warning "GeoIP 目录未完全清理: $GEOIP_DIR"
        verify_passed=false
    fi
    
    if [ "$REMOVE_CONFIG" = true ] && [ -d "$SITES_CONFIG_DIR" ]; then
        log_warning "站点配置目录未完全清理: $SITES_CONFIG_DIR"
        verify_passed=false
    fi
    
    echo ""
    
    if [ "$verify_passed" = true ]; then
        print_title "卸载完成！"
        return 0
    else
        print_title "卸载完成（部分残留，见上方警告）"
        return 1
    fi
}

# ================================================================================
# 清理定时任务
# ================================================================================
cleanup_cron() {
    print_title "清理定时任务"
    
    if [ "$CLEANUP_CRON" = true ]; then
        log_info "正在清理定时任务..."
        
        if check_command crontab; then
            local cron_list=$(sudo crontab -l 2>/dev/null || true)
            if [ -n "$cron_list" ]; then
                local filtered_cron=$(echo "$cron_list" | grep -v "GoAccess" | grep -v "goaccess" || true)
                if [ -n "$filtered_cron" ]; then
                    echo "$filtered_cron" | sudo crontab -
                    log_success "定时任务已清理（保留非 GoAccess 相关任务）"
                else
                    sudo crontab -r 2>/dev/null || true
                    log_success "所有定时任务已清理"
                fi
            else
                log_info "未发现定时任务"
            fi
        else
            log_warning "crontab 不可用，跳过定时任务清理"
        fi
    else
        log_info "跳过定时任务清理（使用 -C 选项可自动清理）"
        
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
# 清理日志和历史数据库
# ================================================================================
cleanup_logs() {
    print_title "清理日志和历史数据库"
    
    if [ "$CLEANUP_LOGS" = true ]; then
        log_info "正在清理日志文件..."
        
        local db_count=$(find /www/wwwroot -name '*.db' -path '*历史数据*' 2>/dev/null | wc -l)
        if [ "$db_count" -gt 0 ]; then
            find /www/wwwroot -name '*.db' -path '*历史数据*' -delete
            log_removed "已清理 $db_count 个历史数据库文件"
        else
            log_info "未找到历史数据库文件"
        fi
        
        local html_count=$(find /www/wwwroot -name '*-log.html' 2>/dev/null | wc -l)
        if [ "$html_count" -gt 0 ]; then
            find /www/wwwroot -name '*-log.html' -delete
            log_removed "已清理 $html_count 个 HTML 报告文件"
        else
            log_info "未找到 HTML 报告文件"
        fi
        
        log_success "日志和历史数据库清理完成"
    else
        log_info "跳过日志清理（使用 -L 选项可自动清理）"
        
        echo -e "${CYAN}如果需要清理日志文件，请运行：${NC}"
        echo ""
        echo "  # 清理所有 .db 历史数据库"
        echo "  find /www/wwwroot -name '*.db' -path '*历史数据*' -delete"
        echo ""
        echo "  # 清理所有 HTML 报告"
        echo "  find /www/wwwroot -name '*-log.html' -delete"
        echo ""
    fi
    
    echo ""
}

# ================================================================================
# 卸载编译依赖
# ================================================================================
cleanup_deps() {
    print_title "卸载编译依赖"
    
    if [ "$REMOVE_DEPS" = true ]; then
        log_info "正在卸载编译依赖..."
        
        if check_command apt-get; then
            log_info "检测到 Debian/Ubuntu 系统"
            sudo apt-get remove --purge -y gcc make wget
            log_success "编译依赖已卸载"
        elif check_command yum; then
            log_info "检测到 CentOS/Rocky/AlmaLinux 系统"
            sudo yum remove -y gcc make wget
            log_success "编译依赖已卸载"
        elif check_command dnf; then
            log_info "检测到 Fedora 系统"
            sudo dnf remove -y gcc make wget
            log_success "编译依赖已卸载"
        else
            log_error "无法识别包管理器，跳过依赖卸载"
            echo -e "${CYAN}如果需要完全卸载编译依赖，请运行：${NC}"
            echo ""
            echo "  # Debian/Ubuntu"
            echo "  sudo apt-get remove --purge gcc make wget"
            echo ""
            echo "  # CentOS/Rocky/AlmaLinux"
            echo "  sudo yum remove gcc make wget"
            echo ""
        fi
    else
        log_info "跳过编译依赖卸载（使用 -D 选项可自动卸载）"
        
        echo -e "${CYAN}如果需要完全卸载编译依赖，请运行：${NC}"
        echo ""
        echo "  # Debian/Ubuntu"
        echo "  sudo apt-get remove --purge gcc make wget"
        echo ""
        echo "  # CentOS/Rocky/AlmaLinux"
        echo "  sudo yum remove gcc make wget"
        echo ""
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
    
    parse_args "$@"
    
    if ! get_installed_info; then
        log_warning "未检测到已安装的 GoAccess"
        
        if [ "$REMOVE_CONFIG" = false ] && [ "$REMOVE_DB" = false ]; then
            log_info "将仅清理残留文件..."
            REMOVE_CONFIG=true
            REMOVE_DB=true
        fi
    fi
    
    if [ "$CONFIRM_UNINSTALL" = false ]; then
        confirm_uninstall
    fi
    
    remove_goaccess_binary
    remove_build_files
    remove_lib_files
    remove_header_files
    remove_man_pages
    remove_doc_files
    update_system_cache
    remove_config_files
    remove_geoip_database
    cleanup_residual
    
    cleanup_cron
    cleanup_logs
    cleanup_deps
    
    verify_uninstall
    
    exit 0
}

main "$@"