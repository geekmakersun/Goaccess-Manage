#!/bin/bash
# ================================================================================
# 脚本名称：配置审计系统.sh
# 功能描述：配置系统级审计，增强 GoAccess 管理系统的安全性审计能力
# 适用环境：宝塔面板 + CentOS/Rocky/AlmaLinux/Debian/Ubuntu
# 创建日期：2026-05-22
#
# 设计思路：
# 1. 安装并配置 auditd 审计守护进程
# 2. 添加针对 GoAccess 管理目录的审计规则
# 3. 配置 sudo 日志增强
# 4. 提供审计日志查询和分析功能
# 5. 支持审计报告生成
# ================================================================================

set -eo pipefail

# ================================================================================
# 常量定义区域
# ================================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_DIR="/var/log"
readonly AUDIT_CONFIG_LOG="${LOG_DIR}/审计配置日志.log"
readonly AUDIT_RULES_FILE="/etc/audit/rules.d/goaccess-audit.rules"
readonly SUDOERS_FILE="/etc/sudoers.d/goaccess-audit"

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
OS_FAMILY=""
PKG_MANAGER=""
AUDITD_INSTALLED=false

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[OK] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $msg" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR] $msg${NC}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING] $msg${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $msg" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    fi
    return 1
}

detect_os() {
    log_info "检测操作系统..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint)
                OS_FAMILY="Debian"
                PKG_MANAGER="apt-get"
                ;;
            centos|rocky|almalinux|rhel|fedora)
                OS_FAMILY="RHEL"
                if check_command dnf; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                ;;
            arch|manjaro)
                OS_FAMILY="Arch"
                PKG_MANAGER="pacman"
                ;;
            opensuse*)
                OS_FAMILY="SUSE"
                PKG_MANAGER="zypper"
                ;;
            *)
                log_error "不支持的操作系统: $ID"
                exit 1
                ;;
        esac
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    log_success "检测到: $ID ($OS_FAMILY)"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        echo "使用方法：sudo $0"
        exit 1
    fi
    log_success "权限检查通过"
}

# ================================================================================
# 安装 auditd
# ================================================================================
install_auditd() {
    print_title "安装 auditd 审计守护进程"
    
    if check_command auditctl; then
        log_info "auditd 已安装"
        AUDITD_INSTALLED=true
        return 0
    fi
    
    log_info "正在安装 auditd..."
    
    case "$OS_FAMILY" in
        Debian)
            $PKG_MANAGER update -y
            $PKG_MANAGER install -y auditd audispd-plugins
            ;;
        RHEL)
            $PKG_MANAGER install -y audit
            ;;
        Arch)
            $PKG_MANAGER -S --noconfirm audit
            ;;
        SUSE)
            $PKG_MANAGER install -y audit
            ;;
    esac
    
    if check_command auditctl; then
        log_success "auditd 安装成功"
        AUDITD_INSTALLED=true
    else
        log_error "auditd 安装失败"
        return 1
    fi
}

# ================================================================================
# 配置 auditd 审计规则
# ================================================================================
configure_audit_rules() {
    print_title "配置审计规则"
    
    log_info "创建审计规则文件: $AUDIT_RULES_FILE"
    
    # 使用双引号 heredoc 以支持变量展开
    cat > "$AUDIT_RULES_FILE" << EOF
## GoAccess 管理系统审计规则
## 此文件由 配置审计系统.sh 自动生成
## 创建时间: $(date '+%Y-%m-%d %H:%M:%S')

# 监控 GoAccess 管理目录的所有操作
-w $PROJECT_DIR -p rwxa -k goaccess_management

# 监控脚本执行
-w $PROJECT_DIR/脚本/安装GoAccess.sh -p x -k goaccess_install
-w $PROJECT_DIR/脚本/卸载GoAccess.sh -p x -k goaccess_uninstall
-w $PROJECT_DIR/脚本/分析所有站点.sh -p x -k goaccess_analyze
-w $PROJECT_DIR/脚本/GeoIP/更新GeoLite2.sh -p x -k goaccess_geoip

# 监控配置文件变更
-w $PROJECT_DIR/配置/站点配置 -p wa -k goaccess_config
-w $PROJECT_DIR/配置/配置模板.conf -p wa -k goaccess_config

# 监控日志文件访问
-w $PROJECT_DIR/日志 -p wa -k goaccess_logs

# 监控 GeoIP 数据库变更
-w $PROJECT_DIR/数据/GeoIP -p wa -k goaccess_geoip_db

# 监控 sudo 使用（针对 www 用户）
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d -p wa -k sudoers_changes

# 监控用户切换
-a always,exit -F arch=b64 -S setuid -S setgid -k user_switch
-a always,exit -F arch=b32 -S setuid -S setgid -k user_switch
EOF
    
    chmod 640 "$AUDIT_RULES_FILE"
    log_success "审计规则文件已创建"
    
    log_info "加载审计规则..."
    if auditctl -R "$AUDIT_RULES_FILE" 2>/dev/null; then
        log_success "审计规则已加载"
    else
        log_warning "审计规则加载失败，可能需要重启 auditd 服务"
    fi
}

# ================================================================================
# 启动 auditd 服务
# ================================================================================
start_auditd_service() {
    print_title "启动 auditd 服务"
    
    log_info "启用 auditd 开机自启动..."
    case "$OS_FAMILY" in
        Debian)
            systemctl enable auditd 2>/dev/null || true
            systemctl start auditd 2>/dev/null || service auditd start 2>/dev/null || true
            ;;
        RHEL)
            systemctl enable auditd 2>/dev/null || true
            systemctl start auditd 2>/dev/null || service auditd start 2>/dev/null || true
            ;;
        Arch)
            systemctl enable auditd 2>/dev/null || true
            systemctl start auditd 2>/dev/null || true
            ;;
        SUSE)
            systemctl enable auditd 2>/dev/null || true
            systemctl start auditd 2>/dev/null || true
            ;;
    esac
    
    if systemctl is-active auditd &>/dev/null || service auditd status &>/dev/null; then
        log_success "auditd 服务已启动"
    else
        log_warning "auditd 服务启动状态未知，请手动检查"
    fi
}

# ================================================================================
# 配置 sudo 日志增强
# ================================================================================
configure_sudo_logging() {
    print_title "配置 sudo 日志增强"
    
    log_info "创建 sudoers 配置文件: $SUDOERS_FILE"
    
    cat > "$SUDOERS_FILE" << EOF
# GoAccess 管理系统 sudo 审计配置
# 此文件由 配置审计系统.sh 自动生成

# 启用详细日志
Defaults logfile="/var/log/sudo.log"
Defaults log_year
Defaults log_host
Defaults syslog=auth

# 记录命令输入/输出（可选，会产生大量日志）
# Defaults log_input,log_output
# Defaults iolog_dir="/var/log/sudo-io"

# 针对 GoAccess 相关命令的特殊配置
Cmnd_Alias GOACCESS_CMDS = $PROJECT_DIR/脚本/*.sh

# 记录所有 GoAccess 相关的 sudo 操作
Defaults!GOACCESS_CMDS log_output
EOF
    
    chmod 440 "$SUDOERS_FILE"
    log_success "sudoers 配置文件已创建"
    
    log_info "验证 sudoers 配置语法..."
    if visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        log_success "sudoers 配置语法正确"
    else
        log_error "sudoers 配置语法错误，请检查"
        rm -f "$SUDOERS_FILE"
        return 1
    fi
}

# ================================================================================
# 创建日志目录
# ================================================================================
create_log_directories() {
    print_title "创建日志目录"
    
    local log_dirs=(
        "/var/log/sudo-io"
        "$LOG_DIR"
    )
    
    for dir in "${log_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_info "创建目录: $dir"
            mkdir -p "$dir"
            chmod 750 "$dir"
        fi
    done
    
    log_success "日志目录创建完成"
}

# ================================================================================
# 显示审计状态
# ================================================================================
show_audit_status() {
    print_title "审计系统状态"
    
    echo -e "${CYAN}=== auditd 服务状态 ===${NC}"
    if systemctl is-active auditd &>/dev/null; then
        echo -e "  ${GREEN}● auditd 服务运行中${NC}"
    else
        echo -e "  ${RED}○ auditd 服务未运行${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}=== 当前审计规则 ===${NC}"
    if check_command auditctl; then
        auditctl -l 2>/dev/null | head -20
        local rule_count=$(auditctl -l 2>/dev/null | wc -l)
        echo ""
        echo -e "  ${YELLOW}共 $rule_count 条规则${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}=== 审计日志文件 ===${NC}"
    echo "  - 系统审计日志: /var/log/audit/audit.log"
    echo "  - sudo 日志: /var/log/sudo.log"
    echo "  - 项目审计日志: $LOG_DIR/审计日志.log"
    echo "  - sudo 系统日志: /var/log/auth.log (Debian) 或 /var/log/secure (RHEL)"
    echo ""
}

# ================================================================================
# 查询审计日志
# ================================================================================
query_audit_logs() {
    print_title "查询审计日志"
    
    echo -e "${CYAN}最近 24 小时的 GoAccess 相关审计事件：${NC}"
    echo ""
    
    if check_command ausearch; then
        echo -e "${YELLOW}=== auditd 审计日志 ===${NC}"
        ausearch -k goaccess_management -ts recent 2>/dev/null | head -50 || echo "  无相关记录"
        echo ""
    fi
    
    echo -e "${YELLOW}=== sudo 审计日志 ===${NC}"
    if [ -f "/var/log/sudo.log" ]; then
        tail -20 /var/log/sudo.log
    else
        echo "  sudo 日志文件不存在"
    fi
    echo ""
    
    echo -e "${YELLOW}=== 项目审计日志 ===${NC}"
    if [ -f "$LOG_DIR/审计日志.log" ]; then
        tail -20 "$LOG_DIR/审计日志.log"
    else
        echo "  项目审计日志文件不存在"
    fi
    echo ""
    
    echo -e "${YELLOW}=== 系统认证日志 ===${NC}"
    if [ -f "/var/log/auth.log" ]; then
        grep -E "(sudo|goaccess|www)" /var/log/auth.log | tail -20
    elif [ -f "/var/log/secure" ]; then
        grep -E "(sudo|goaccess|www)" /var/log/secure | tail -20
    else
        echo "  系统认证日志文件不存在"
    fi
}

# ================================================================================
# 生成审计报告
# ================================================================================
generate_audit_report() {
    print_title "生成审计报告"
    
    local report_file="${LOG_DIR}/审计报告_$(date '+%Y%m%d_%H%M%S').txt"
    
    log_info "正在生成审计报告: $report_file"
    
    {
        echo "========================================"
        echo "GoAccess 管理系统审计报告"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
        echo ""
        
        echo "=== 1. 审计系统状态 ==="
        echo ""
        if systemctl is-active auditd &>/dev/null; then
            echo "auditd 服务状态: 运行中"
        else
            echo "auditd 服务状态: 未运行"
        fi
        echo ""
        
        echo "=== 2. 审计规则统计 ==="
        echo ""
        if check_command auditctl; then
            local rule_count=$(auditctl -l 2>/dev/null | wc -l)
            echo "当前审计规则数量: $rule_count"
            echo ""
            echo "规则列表:"
            auditctl -l 2>/dev/null
        fi
        echo ""
        
        echo "=== 3. 最近审计事件 ==="
        echo ""
        if check_command ausearch; then
            echo "最近 GoAccess 管理目录访问:"
            ausearch -k goaccess_management -ts recent 2>/dev/null | tail -20 || echo "无相关记录"
        fi
        echo ""
        
        echo "=== 4. sudo 操作记录 ==="
        echo ""
        if [ -f "/var/log/sudo.log" ]; then
            echo "最近 sudo 操作:"
            tail -20 /var/log/sudo.log
        fi
        echo ""
        
        echo "=== 5. 项目审计日志 ==="
        echo ""
        if [ -f "$LOG_DIR/审计日志.log" ]; then
            echo "最近项目审计记录:"
            tail -30 "$LOG_DIR/审计日志.log"
        fi
        echo ""
        
        echo "=== 6. 安全建议 ==="
        echo ""
        echo "- 定期检查审计日志，及时发现异常操作"
        echo "- 建议设置日志轮转，避免日志文件过大"
        echo "- 定期备份审计日志到安全位置"
        echo "- 监控 sudo 使用频率，发现异常提权行为"
        echo ""
        
        echo "========================================"
        echo "报告生成完成"
        echo "========================================"
    } > "$report_file"
    
    log_success "审计报告已生成: $report_file"
    echo ""
    echo -e "${CYAN}查看报告：${NC}"
    echo "  cat $report_file"
    echo ""
}

# ================================================================================
# 显示使用方法
# ================================================================================
show_usage() {
    echo "用法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --install      安装并配置审计系统"
    echo "  -s, --status       显示审计系统状态"
    echo "  -q, --query        查询审计日志"
    echo "  -r, --report       生成审计报告"
    echo "  -a, --all          执行所有操作（安装、状态、查询、报告）"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $SCRIPT_NAME -i           # 安装审计系统"
    echo "  $SCRIPT_NAME -s           # 显示状态"
    echo "  $SCRIPT_NAME -q           # 查询日志"
    echo "  $SCRIPT_NAME -r           # 生成报告"
    echo "  $SCRIPT_NAME -a           # 执行所有操作"
}

# ================================================================================
# 主函数
# ================================================================================
main() {
    local install_mode=false
    local status_mode=false
    local query_mode=false
    local report_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--install)
                install_mode=true
                shift
                ;;
            -s|--status)
                status_mode=true
                shift
                ;;
            -q|--query)
                query_mode=true
                shift
                ;;
            -r|--report)
                report_mode=true
                shift
                ;;
            -a|--all)
                install_mode=true
                status_mode=true
                query_mode=true
                report_mode=true
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
    
    if [ "$install_mode" = false ] && [ "$status_mode" = false ] && [ "$query_mode" = false ] && [ "$report_mode" = false ]; then
        show_usage
        exit 0
    fi
    
    echo ""
    print_title "GoAccess 管理系统审计配置工具"
    
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    echo "========================================" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始配置审计系统" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
    echo "========================================" >> "$AUDIT_CONFIG_LOG" 2>/dev/null || true
    
    if [ "$install_mode" = true ]; then
        check_root
        detect_os
        install_auditd
        configure_audit_rules
        start_auditd_service
        configure_sudo_logging
        create_log_directories
        echo ""
    fi
    
    if [ "$status_mode" = true ]; then
        show_audit_status
    fi
    
    if [ "$query_mode" = true ]; then
        query_audit_logs
    fi
    
    if [ "$report_mode" = true ]; then
        generate_audit_report
    fi
    
    echo -e "${GREEN}操作完成！${NC}"
    echo ""
}

main "$@"
