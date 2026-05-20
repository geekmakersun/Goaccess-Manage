#!/bin/bash
# ================================================================================
# 脚本名称：分析所有站点.sh
# 功能描述：批量分析多个站点的 Nginx 访问日志并生成 HTML 报告
# 适用环境：宝塔面板
# 创建日期：2026-05-20
#
# 设计思路：
# 1. 使用 set -eo pipefail 确保脚本严格执行
# 2. 配置文件使用变量方式，通过 source 加载（简单灵活）
# 3. 遍历所有配置文件，逐个分析
# 4. 支持跳过失败的站点，继续处理下一个
# 5. 完整的统计输出（成功/失败/跳过数量）
# ================================================================================

# 开启严格错误处理模式
set -eo pipefail

# ================================================================================
# 常量定义区域（使用 readonly 确保常量不可修改）
# ================================================================================
readonly SCRIPT_NAME="$(basename "$0")"              # 脚本文件名
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # 脚本所在目录（绝对路径）
readonly CONFIG_DIR="$SCRIPT_DIR/站点配置"          # 站点配置目录
readonly DB_DIR="$SCRIPT_DIR/GoAccess数据库"              # 数据持久化目录（GoAccess数据库）

# ================================================================================
# ANSI 颜色代码定义（用于美化输出）
# ================================================================================
readonly RED='\033[0;31m'       # 红色（错误信息）
readonly GREEN='\033[0;32m'     # 绿色（成功信息）
readonly YELLOW='\033[1;33m'    # 黄色（警告/信息）
readonly BLUE='\033[0;34m'      # 蓝色（标题/分隔线）
readonly CYAN='\033[0;36m'      # 青色（阶段标题）
readonly NC='\033[0m'           # 恢复默认颜色

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
# log_section: 打印阶段标题（青色）
# 参数：$1 - 阶段编号，$2 - 阶段描述
# 用途：清晰的流程指示
# --------------------------------------------------------------------------------
log_section() {
    echo ""
    echo -e "${CYAN}[$1] $2${NC}"
}

# --------------------------------------------------------------------------------
# validate_config_file: 简单的配置文件验证
# 参数：$1 - 配置文件路径
# 返回：错误数量（0 = 无错误）
# 说明：当前未完全使用，但框架已保留
# --------------------------------------------------------------------------------
validate_config_file() {
    local config_file=$1
    local errors=0

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    # 逐行读取配置文件
    while IFS= read -r line || [ -n "$line" ]; do
        # 去除首尾空白字符
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 跳过空行和注释行（#开头）
        if [[ "$line" =~ ^#.*$ ]] || [ -z "$line" ]; then
            continue
        fi

        # 检查是否是 key=value 格式
        if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
            local key="${line%%=*}"    # 提取 key（等号左边）
            local value="${line#*=}"   # 提取 value（等号右边）
            value=$(echo "$value" | sed 's/^["'\'']//;s/["'\'']$//')  # 去除引号

            # 检查必需项是否为空
            case "$key" in
                log_file|db_path|output_html)
                    if [ -z "$value" ]; then
                        log_warning "配置项 '$key' 值为空"
                        errors=$((errors + 1))
                    fi
                    ;;
            esac
        fi
    done < "$config_file"

    return $errors
}

# --------------------------------------------------------------------------------
# parse_and_validate_config: 解析并验证配置文件
# 参数：$1 - 配置文件路径
# 返回：0 - 成功，1 - 失败
# 设计思路：
# 1. 先清除可能残留的变量（防止污染）
# 2. 使用 source 加载配置（最简洁的方式）
# 3. 验证必需配置项是否存在
# --------------------------------------------------------------------------------
parse_and_validate_config() {
    local config_file=$1

    # 清除所有可能用到的配置变量（防止上次分析残留影响）
    unset log_file db_path output_html log_format
    unset time_format date_format
    unset enable_panel disable_panel
    unset exclude_extension include_extension
    unset ignore_crawlers ignore_ip ignore_host ignore_referer
    unset after before
    unset keep_db keep_last
    unset html_report_title real_time_html ws_url
    unset geoip_database
    unset max_items num_tests no_validation
    unset anonymize_ip double_decode color no_progress with_output_resolver
    unset site_name

    # 使用 source 加载配置文件（变量会自动设置到当前 Shell）
    # 2>/dev/null: 隐藏错误输出，我们会自己处理
    if ! source "$config_file" 2>/dev/null; then
        log_error "配置文件语法错误: $config_file"
        return 1
    fi

    # 验证必需配置项：日志路径、数据库路径、输出路径
    if [ -z "$log_file" ] || [ -z "$db_path" ] || [ -z "$output_html" ]; then
        log_error "配置不完整，缺少必需项"
        return 1
    fi

    return 0
}

# ================================================================================
# 主程序开始
# ================================================================================

print_title "GoAccess 多站点分析脚本 v1.2"

log_info "脚本目录: $SCRIPT_DIR"
echo ""

# --------------------------------------------------------------------------------
# 阶段 1/5：检查环境
# 设计说明：
# 1. 检查 GoAccess 是否安装
# 2. 检查配置目录是否存在
# 3. 确保数据目录存在
# --------------------------------------------------------------------------------
log_section "1/5" "检查环境"

# 检查运行用户（建议使用 www 用户运行，以匹配网站运行身份）
# 说明：以 www 用户运行可确保生成的文件权限正确，避免网站无法访问报告
if [ "$EUID" -eq 0 ]; then
    log_warning "=========================================="
    log_warning "警告：建议使用 www 用户运行此脚本"
    log_warning "以 root 运行可能导致文件权限问题"
    log_warning "=========================================="
    log_info "推荐运行方式："
    echo "  su - www -s /bin/bash -c '$SCRIPT_DIR/分析所有站点.sh'"
    echo ""
fi

# 检查 GoAccess 命令是否存在
if ! command -v goaccess &> /dev/null; then
    log_error "GoAccess 未安装"
    echo "请先运行：安装GoAccess.sh"
    exit 1
fi
log_success "GoAccess 已安装"

# 获取 GoAccess 版本并检查是否支持 --keep-db 选项
GOACCESS_VERSION=$(goaccess --version 2>&1 | head -n 1 | sed -n 's/.*GoAccess v\?\([0-9]*\.[0-9]*\).*/\1/p')
GOACCESS_MAJOR=${GOACCESS_VERSION%%.*}
GOACCESS_MINOR=${GOACCESS_VERSION#*.}
GOACCESS_MINOR=${GOACCESS_MINOR%%.*}
KEEP_DB_SUPPORTED=false
if [ -n "$GOACCESS_MAJOR" ] && [ -n "$GOACCESS_MINOR" ]; then
    if [ "$GOACCESS_MAJOR" -gt 1 ] || { [ "$GOACCESS_MAJOR" -eq 1 ] && [ "$GOACCESS_MINOR" -ge 3 ]; }; then
        KEEP_DB_SUPPORTED=true
    fi
fi

# 检查配置目录是否存在
if [ ! -d "$CONFIG_DIR" ]; then
    log_error "配置目录不存在: $CONFIG_DIR"
    exit 1
fi
log_success "配置目录正常: $CONFIG_DIR"

# 检查配置目录是否可读
if [ ! -r "$CONFIG_DIR" ]; then
    log_error "配置目录不可读: $CONFIG_DIR"
    exit 1
fi

# 确保数据目录存在
if [ ! -d "$DB_DIR" ]; then
    log_info "创建数据目录: $DB_DIR"
    mkdir -p "$DB_DIR"
    chmod 777 "$DB_DIR" 2>/dev/null || true
fi
echo ""

# --------------------------------------------------------------------------------
# 阶段 2/5：扫描配置
# 设计说明：
# 1. 使用通配符查找所有 .conf 文件
# 2. 检查是否找到了配置文件
# 3. 如果没有，给出友好提示
# --------------------------------------------------------------------------------
log_section "2/5" "扫描配置"

# 查找所有配置文件（存到数组中）
CONFIG_FILES=("$CONFIG_DIR"/*.conf)

# 检查是否找到了配置文件
# 注意：如果没有文件，通配符会保留原样，所以需要检查第一个元素是否真的存在
if [ ${#CONFIG_FILES[@]} -eq 0 ] || [ ! -f "${CONFIG_FILES[0]}" ]; then
    log_warning "未找到任何站点配置文件"
    echo ""
    echo -e "${CYAN}提示：${NC}"
    echo "1. 请在 $CONFIG_DIR 目录下创建站点配置文件"
    echo "2. 可以复制 配置模板.conf 到 站点配置/ 目录进行修改"
    echo "3. 然后运行 部署配置.sh 部署配置"
    exit 0
fi

log_success "找到 ${#CONFIG_FILES[@]} 个站点配置"
echo ""

# --------------------------------------------------------------------------------
# 阶段 3/5：分析站点
# 设计说明：
# 1. 遍历每个配置文件
# 2. 解析并验证配置
# 3. 检查日志文件是否存在
# 4. 确保输出目录存在
# 5. 构建 GoAccess 命令参数
# 6. 执行分析
# 7. 统计结果
# --------------------------------------------------------------------------------
log_section "3/5" "分析站点"

# 初始化统计变量
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# 遍历所有配置文件
for CONFIG_FILE in "$CONFIG_DIR"/*.conf; do
    # 跳过不存在的文件（防止通配符问题）
    if [ ! -f "$CONFIG_FILE" ]; then
        continue
    fi

    # 获取站点名称（配置文件名去掉 .conf 后缀）
    SITE_NAME=$(basename "$CONFIG_FILE" .conf)

    # 输出当前处理的站点
    echo ""
    print_separator
    echo -e "${YELLOW}处理站点: $SITE_NAME${NC}"
    print_separator

    # 解析并验证配置
    if ! parse_and_validate_config "$CONFIG_FILE"; then
        log_error "配置验证失败，跳过"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # 检查日志文件是否存在
    if [ ! -f "$log_file" ]; then
        log_warning "日志文件不存在: $log_file"
        log_info "跳过此站点（如需统计，请创建日志文件或检查路径）"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # 检查日志文件是否可读
    if [ ! -r "$log_file" ]; then
        log_warning "日志文件不可读: $log_file"
        log_info "请检查文件权限，或确保以 www 用户运行此脚本"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # 确保 HTML 报告的输出目录存在（使用 777 权限确保 www 用户可写）
    OUTPUT_DIR=$(dirname "$output_html")
    if [ ! -d "$OUTPUT_DIR" ]; then
        log_info "创建输出目录: $OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
        chmod 777 "$OUTPUT_DIR" 2>/dev/null || true
    fi

    # 检查输出目录是否可写
    if [ ! -w "$OUTPUT_DIR" ]; then
        log_warning "输出目录不可写: $OUTPUT_DIR"
        log_info "请检查目录权限：chmod 777 $OUTPUT_DIR"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # 确保数据库的父目录存在（使用 777 权限确保 www 用户可写）
    DB_PARENT=$(dirname "$db_path")
    if [ ! -d "$DB_PARENT" ]; then
        mkdir -p "$DB_PARENT"
        chmod 777 "$DB_PARENT" 2>/dev/null || true
    fi

    # 检查数据库目录是否可写
    if [ ! -w "$DB_PARENT" ]; then
        log_warning "数据库目录不可写: $DB_PARENT"
        log_info "请检查目录权限：chmod 777 $DB_PARENT"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # 设置默认值（如果配置文件中没有指定）
    [ -z "$log_format" ] && log_format="COMBINED"  # 默认：Nginx 组合格式
    [ -z "$keep_db" ] && keep_db="true"           # 默认：保留历史数据
    [ -z "$site_name" ] && site_name="$SITE_NAME" # 默认：站点名使用配置文件名

    # 输出当前配置信息（方便调试）
    echo -e "  ${BLUE}日志文件:${NC} $log_file"
    echo -e "  ${BLUE}数据库:${NC}   $db_path"
    echo -e "  ${BLUE}报告:${NC}     $output_html"
    echo -e "  ${BLUE}格式:${NC}      $log_format"

    # 构建 GoAccess 命令参数（使用数组，避免空格问题）
    GOACCESS_ARGS=()
    GOACCESS_ARGS+=("$log_file")                    # 日志文件路径
    GOACCESS_ARGS+=("-o" "$output_html")            # 输出 HTML 文件
    GOACCESS_ARGS+=("--log-format=$log_format")    # 日志格式
    GOACCESS_ARGS+=("--db-path=$db_path")          # 数据持久化路径

    # 数据持久化相关
    [ "$keep_db" = "true" ] || [ "$keep_db" = "1" ] && [ "$KEEP_DB_SUPPORTED" = "true" ] && GOACCESS_ARGS+=("--keep-db=1")
    [ -n "$keep_last" ] && GOACCESS_ARGS+=("--keep-last=$keep_last")

    # 日志格式相关（自定义格式）
    [ -n "$time_format" ] && GOACCESS_ARGS+=("--time-format=$time_format")
    [ -n "$date_format" ] && GOACCESS_ARGS+=("--date-format=$date_format")

    # 面板显示相关
    [ -n "$enable_panel" ] && GOACCESS_ARGS+=("--enable-panel=$enable_panel")
    [ -n "$disable_panel" ] && GOACCESS_ARGS+=("--disable-panel=$disable_panel")

    # 过滤相关
    [ -n "$exclude_extension" ] && GOACCESS_ARGS+=("--exclude-extension=$exclude_extension")
    [ -n "$include_extension" ] && GOACCESS_ARGS+=("--include-extension=$include_extension")
    [ "$ignore_crawlers" = "true" ] || [ "$ignore_crawlers" = "1" ] && GOACCESS_ARGS+=("--ignore-crawlers")

    # 忽略 IP（支持多个，逗号分隔）
    if [ -n "$ignore_ip" ]; then
        IFS=',' read -ra IP_ARRAY <<< "$ignore_ip"  # 按逗号分割到数组
        for ip in "${IP_ARRAY[@]}"; do
            ip=$(echo "$ip" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # 去除首尾空格
            [ -n "$ip" ] && GOACCESS_ARGS+=("--ignore-ip=$ip")
        done
    fi

    # 忽略 Host（支持多个，逗号分隔）
    if [ -n "$ignore_host" ]; then
        IFS=',' read -ra HOST_ARRAY <<< "$ignore_host"
        for host in "${HOST_ARRAY[@]}"; do
            host=$(echo "$host" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -n "$host" ] && GOACCESS_ARGS+=("--ignore-host=$host")
        done
    fi

    # 时间过滤
    [ -n "$after" ] && GOACCESS_ARGS+=("--after=$after")
    [ -n "$before" ] && GOACCESS_ARGS+=("--before=$before")

    # 输出相关
    [ -n "$html_report_title" ] && GOACCESS_ARGS+=("--html-report-title=$html_report_title")
    [ "$real_time_html" = "true" ] || [ "$real_time_html" = "1" ] && GOACCESS_ARGS+=("--real-time-html")
    [ -n "$ws_url" ] && GOACCESS_ARGS+=("--ws-url=$ws_url")

    # GeoIP 相关
    [ -n "$geoip_database" ] && GOACCESS_ARGS+=("--geoip-database=$geoip_database")

    # 性能相关
    [ -n "$max_items" ] && GOACCESS_ARGS+=("--max-items=$max_items")
    [ -n "$num_tests" ] && GOACCESS_ARGS+=("--num-tests=$num_tests")
    [ "$no_validation" = "true" ] || [ "$no_validation" = "1" ] && GOACCESS_ARGS+=("--no-validation")

    # 其他选项
    [ "$anonymize_ip" = "true" ] || [ "$anonymize_ip" = "1" ] && GOACCESS_ARGS+=("--anonymize-ip")
    [ "$double_decode" = "true" ] || [ "$double_decode" = "1" ] && GOACCESS_ARGS+=("--double-decode")
    [ "$color" = "true" ] || [ "$color" = "1" ] && GOACCESS_ARGS+=("--color")
    [ "$no_progress" = "true" ] || [ "$no_progress" = "1" ] && GOACCESS_ARGS+=("--no-progress")
    [ "$with_output_resolver" = "true" ] || [ "$with_output_resolver" = "1" ] && GOACCESS_ARGS+=("--with-output-resolver")

    # 禁用颜色输出（因为我们使用脚本自己的颜色）
    GOACCESS_ARGS+=("--no-color")

    # 执行 GoAccess 分析
    echo -e "  ${GREEN}执行分析...${NC}"

    goaccess_rc=0
    goaccess "${GOACCESS_ARGS[@]}" 2> >(tee -a "$SCRIPT_DIR/goaccess-error.log" >&2) || goaccess_rc=$?
    if [ $goaccess_rc -eq 0 ]; then
        log_success "完成: $output_html"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "分析失败（详细日志: $SCRIPT_DIR/goaccess-error.log）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done
echo ""

# --------------------------------------------------------------------------------
# 阶段 4/5：统计结果
# 设计说明：输出成功/失败/跳过的站点数量
# --------------------------------------------------------------------------------
log_section "4/5" "统计结果"

echo -e "  ${GREEN}成功:${NC} $SUCCESS_COUNT 个站点"
[ $FAIL_COUNT -gt 0 ] && echo -e "  ${RED}失败:${NC} $FAIL_COUNT 个站点"
[ $SKIP_COUNT -gt 0 ] && echo -e "  ${YELLOW}跳过:${NC} $SKIP_COUNT 个站点"
echo ""

# --------------------------------------------------------------------------------
# 阶段 5/5：完成
# 设计说明：
# 1. 给用户友好的提示
# 2. 如果有失败的站点，警告并返回非零退出码
# --------------------------------------------------------------------------------
log_section "5/5" "完成"

echo -e "${CYAN}访问报告：${NC}"
echo "在浏览器中打开各站点的 site-log.html 查看分析报告"
echo ""

# 如果有失败的站点，退出码为 1（让脚本可以被检测到失败）
if [ $FAIL_COUNT -gt 0 ]; then
    log_warning "有 $FAIL_COUNT 个站点分析失败，请检查配置文件"
    exit 1
fi

exit 0
