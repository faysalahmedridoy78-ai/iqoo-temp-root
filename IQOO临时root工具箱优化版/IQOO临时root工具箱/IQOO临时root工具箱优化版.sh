#!/data/data/com.termux/files/usr/bin/bash
# 临时 root工具箱优化版
# 作者：清风南辞【酷安】

# ======================== 颜色常量 ========================
GREEN='\033[32m'
RED='\033[31m'
WHITE='\033[37m'
YELLOW='\033[33m'
BLUE='\033[36m'
RESET='\033[0m'

# ======================== 全局变量 ========================
TARGET_SO_PATH="/data/local/tmp/preload.so"
DEFAULT_PORT="5555"
LOG_DIR=""
LOG_FILE=""
MAX_LOGS=5

# ======================== 工具函数（UI自适应，宽度-1防溢出） ========================
get_script_dir() {
    local script_real=$(readlink -f "$0")
    dirname "$script_real"
}

echo_green() { printf "${GREEN}%s${RESET}\n" "$1"; }
echo_red() { printf "${RED}%s${RESET}\n" "$1"; }
echo_white() { printf "${WHITE}%s${RESET}\n" "$1"; }
echo_white_n() { printf "${WHITE}%s${RESET}" "$1"; }
echo_yellow() { printf "${YELLOW}%s${RESET}\n" "$1"; }
echo_yellow_n() { printf "${YELLOW}%s${RESET}" "$1"; }
echo_blue() { printf "${BLUE}%s${RESET}\n" "$1"; }

# ---- 获取有效终端宽度（减1防止换行） ----
get_term_width() {
    local w=$(tput cols 2>/dev/null || echo 50)
    w=$((w - 1))
    [ $w -lt 10 ] && w=10
    echo "$w"
}

# ---- 自适应分隔线（等号） ----
print_line() {
    local term_width=$(get_term_width)
    local line=""
    for ((i=0; i<term_width; i++)); do line="${line}="; done
    printf "${WHITE}%s${RESET}\n" "$line"
}

# ---- 自适应居中（绿色） ----
center_green() {
    local text="$1"
    local term_width=$(get_term_width)
    local text_len=${#text}
    local pad=$(( (term_width - text_len) / 2 ))
    [ $pad -lt 0 ] && pad=0
    printf "${GREEN}%${pad}s%s${RESET}\n" "" "$text"
}

# ---- 自适应居中（无色） ----
center_text() {
    local text="$1"
    local term_width=$(get_term_width)
    local text_len=${#text}
    local pad=$(( (term_width - text_len) / 2 ))
    [ $pad -lt 0 ] && pad=0
    printf "%${pad}s%s\n" "" "$text"
}

# ---- 自适应边框（与主菜单一致，宽度-1） ----
draw_border() {
    local term_width=$(get_term_width)
    local inner_width=$((term_width - 2))
    [ $inner_width -lt 0 ] && inner_width=0
    local border=$(printf '%*s' $inner_width '' | tr ' ' '-')
    printf "${WHITE}+%s+${RESET}\n" "$border"
}

# ---- 功能标题显示（带边框居中） ----
show_func_header() {
    local title="$1"
    draw_border
    center_green "$title"
    draw_border
    echo ""
}

# ---- 获取设备友好名称（市场名 > 型号） ----
get_device_friendly_name() {
    local name=$(adb shell getprop ro.product.marketname 2>/dev/null | tr -d '\r')
    if [ -z "$name" ]; then
        name=$(adb shell getprop ro.product.vendor.marketname 2>/dev/null | tr -d '\r')
    fi
    if [ -z "$name" ]; then
        name=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    fi
    echo "$name"
}

# ======================== 计算字符串显示宽度（用于主菜单） ========================
get_display_width() {
    local str="$1"
    local len=0
    for ((i=0; i<${#str}; i++)); do
        char="${str:$i:1}"
        ord=$(printf "%d" "'$char" 2>/dev/null)
        if [ $ord -gt 127 ]; then
            len=$((len + 2))
        else
            len=$((len + 1))
        fi
    done
    echo "$len"
}

# ======================== 日志工具 ========================
init_log_dir() {
    LOG_DIR="$(get_script_dir)/log"
    mkdir -p "$LOG_DIR" 2>/dev/null
    if [ ! -d "$LOG_DIR" ]; then
        echo_red "[错误] 无法创建日志目录: $LOG_DIR"
        return 1
    fi
    clean_old_logs
    return 0
}

clean_old_logs() {
    local log_count=$(ls -1 "$LOG_DIR"/inject_*.log 2>/dev/null | wc -l)
    if [ "$log_count" -gt "$MAX_LOGS" ]; then
        local delete_count=$((log_count - MAX_LOGS))
        echo_yellow "[日志] 发现 $log_count 个日志文件，将删除最早的 $delete_count 个"
        ls -1t "$LOG_DIR"/inject_*.log 2>/dev/null | tail -n "$delete_count" | while read old_log; do
            rm -f "$old_log" 2>/dev/null
            echo_yellow "[日志] 已删除: $(basename "$old_log")"
        done
    fi
}

init_log_file() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    LOG_FILE="${LOG_DIR}/inject_${timestamp}.log"
    {
        echo "======================================================"
        echo "  ADB工具箱 - 息屏注入日志"
        echo "  作者：清风南辞"
        echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  日志文件: $(basename "$LOG_FILE")"
        echo "======================================================"
        echo ""
    } > "$LOG_FILE"
    echo_green "[日志] 已创建日志文件: $(basename "$LOG_FILE")"
    echo_green "[日志] 日志目录: $LOG_DIR"
    echo ""
}

log_write() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() { log_write "INFO" "$@"; echo_blue "[日志] $@"; }
log_ok() { log_write "OK" "$@"; echo_green "[日志] $@"; }
log_warn() { log_write "WARN" "$@"; echo_yellow "[日志] $@"; }
log_error() { log_write "ERROR" "$@"; echo_red "[日志] $@"; }
log_cmd() { local cmd="$@"; log_write "CMD" "执行命令: $cmd"; }
log_inject_output() { local line="$1"; local ts=$(date '+%Y-%m-%d %H:%M:%S'); echo "[$ts] [OUTPUT] $line" >> "$LOG_FILE"; }
log_separator() {
    local title="$1"
    log_write "SEPARATOR" "========================================"
    [ -n "$title" ] && log_write "SEPARATOR" "  $title"
    log_write "SEPARATOR" "========================================"
}

show_log_info() {
    if [ -f "$LOG_FILE" ]; then
        local file_size=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        echo ""
        print_line
        center_green "日志文件信息"
        print_line
        echo_green "文件名: $(basename "$LOG_FILE")"
        echo_green "路径:   $LOG_FILE"
        echo_green "大小:   $file_size"
        echo ""
        echo_white "日志目录中的文件（保留最新 $MAX_LOGS 个）："
        ls -lt "$LOG_DIR"/inject_*.log 2>/dev/null | head -n "$MAX_LOGS" | while read line; do
            local log_name=$(echo "$line" | awk '{print $NF}')
            local log_time=$(stat -c '%y' "$log_name" 2>/dev/null | cut -d'.' -f1)
            local log_size=$(echo "$line" | awk '{print $5}')
            echo_white "  $(basename "$log_name")  [$log_time]  [$log_size]"
        done
        print_line
        echo ""
    fi
}

# ======================== ADB 相关函数（含 clean_offline_devices） ========================
check_wireless_adb() {
    local device_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E ":[0-9]{4,}" | grep -w "device$")
    [ -n "$device_list" ]
}

clean_offline_devices() {
    local offline_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep "offline$" | awk '{print $1}')
    if [ -n "$offline_list" ]; then
        echo_yellow "[提示] 检测到离线设备，正在断开..."
        for dev in $offline_list; do
            adb disconnect "$dev" >/dev/null 2>&1
            echo_white "  已断开: $dev"
        done
        sleep 1
    fi
}

check_already_connected() {
    local connected_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E "device$")
    if [ -n "$connected_list" ]; then
        echo_green "你已连接无线调试"
        echo_white "已连接设备列表："
        adb devices 2>/dev/null | grep -v "List of devices"
        sleep 2
        return 0
    fi
    return 1
}

screen_off() {
    adb shell input keyevent 26 >/dev/null 2>&1
    [ $? -eq 0 ] && return 0
    adb shell svc power sleep >/dev/null 2>&1
    return $?
}

goto_debug_page() {
    local brand="$1"
    local ret=1
    echo_green "[识别设备品牌] $brand"
    case "$brand" in
        xiaomi|redmi|poco)
            adb shell am start -n com.android.settings/.Settings\$WirelessDebuggingActivity >/dev/null 2>&1 && ret=0
            ;;
        oppo|realme|oneplus)
            adb shell am start -n com.android.settings/.Settings\$WirelessDebuggingActivity >/dev/null 2>&1 && ret=0
            [ $ret -ne 0 ] && adb shell am start -n com.oplus.settings/.Settings\$WirelessDebuggingActivity >/dev/null 2>&1 && ret=0
            ;;
        vivo|iqoo)
            adb shell am start -n com.android.settings/.Settings\$WirelessDebuggingActivity >/dev/null 2>&1 && ret=0
            [ $ret -ne 0 ] && adb shell am start -n com.vivo.settings/.Settings\$WirelessDebuggingActivity >/dev/null 2>&1 && ret=0
            ;;
    esac
    if [ $ret -ne 0 ]; then
        case "$brand" in
            xiaomi|redmi|poco)
                adb shell am start -n com.android.settings/.Settings\$DevelopmentSettingsActivity >/dev/null 2>&1 && ret=0
                ;;
            oppo|realme|oneplus)
                adb shell am start -n com.android.settings/.Settings\$DevelopmentSettingsActivity >/dev/null 2>&1 && ret=0
                [ $ret -ne 0 ] && adb shell am start -n com.oplus.settings/.Settings\$DevelopmentSettingsActivity >/dev/null 2>&1 && ret=0
                ;;
            vivo|iqoo)
                adb shell am start -n com.android.settings/.Settings\$DevelopmentSettingsActivity >/dev/null 2>&1 && ret=0
                [ $ret -ne 0 ] && adb shell am start -n com.vivo.settings/.Settings\$DevelopmentSettingsActivity >/dev/null 2>&1 && ret=0
                ;;
        esac
        [ $ret -ne 0 ] && adb shell am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS >/dev/null 2>&1 && ret=0
    fi
    if [ $ret -ne 0 ]; then
        adb shell am start -a android.settings.SETTINGS >/dev/null 2>&1
        echo_red "[警告] 一键跳转失败，请手动开启无线调试"
    else
        echo_green "[成功] 已跳转手机无线调试页面"
    fi
}

show_pair_tips() {
    echo ""
    print_line
    center_green "操作须知"
    print_line
    echo_green " 1.设置-关于本机：连点版本号7次解锁开发者模式"
    echo_green " 2.开发者选项内打开【无线调试】"
    echo_green " 3.点开使用配对码配对设备，记录IP地址和端口与6位验证码"
    print_line
    echo ""
}

show_connect_tips() {
    echo ""
    print_line
    center_green "操作须知"
    print_line
    echo_green " 1.打开无线调试，长按IP地址和端口并复制输入，打开状态栏如果出现已连接到无线调试则成功，完成第一步之后都从第二步进行"
    print_line
    echo ""
}

# ======================== 主菜单（自适应宽度，精确对齐） ========================
show_menu() {
    clear

    # 获取终端宽度（减1防溢出）
    local term_width=$(get_term_width)
    [ $term_width -lt 30 ] && term_width=30

    local current_time=$(date '+%Y-%m-%d %H:%M')
    local inner_width=$((term_width - 2))

    # 定义各行的显示内容（不含颜色）
    local lines=(
        "ADB 工具箱"
        "by 清风南辞"
        "⏱ $current_time"
        "[1] 无线配对"
        "[2] 设备连接"
        "[3] 推送 preload.so"
        "[4] 息屏注入"
        "[5] root 提权"
        "[6] B站主页"
        "[0] 退出程序"
    )

    local colors=(
        "$GREEN"
        "$YELLOW"
        "$BLUE"
        "$GREEN"
        "$GREEN"
        "$GREEN"
        "$GREEN"
        "$GREEN"
        "$GREEN"
        "$GREEN"
    )

    local max_disp=0
    local disp_widths=()
    for text in "${lines[@]}"; do
        local w=$(get_display_width "$text")
        disp_widths+=("$w")
        [ $w -gt $max_disp ] && max_disp=$w
    done

    [ $inner_width -lt $max_disp ] && inner_width=$max_disp

    print_border() {
        local border=$(printf '%*s' $inner_width '' | tr ' ' '-')
        printf "${WHITE}+%s+${RESET}\n" "$border"
    }

    print_border

    for i in "${!lines[@]}"; do
        local text="${lines[$i]}"
        local color="${colors[$i]}"
        local disp_w="${disp_widths[$i]}"
        local pad=$(( (inner_width - disp_w) / 2 ))
        [ $pad -lt 0 ] && pad=0
        if [ $i -lt 3 ]; then
            printf "${WHITE}|${RESET}%*s${color}%s${RESET}%*s${WHITE}|${RESET}\n" \
                $pad "" "$text" $((inner_width - disp_w - pad)) ""
        else
            printf "${WHITE}|${RESET} ${color}%s${RESET}%*s${WHITE}|${RESET}\n" \
                "$text" $((inner_width - disp_w - 1)) ""
        fi
    done

    print_border

    echo_white_n "请输入功能序号："
}

# ======================== 功能1：无线配对 ========================
func_pair() {
    clear
    show_func_header "功能1 无线配对"

    if check_already_connected; then return; fi
    show_pair_tips
    local brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    local model=$(get_device_friendly_name)
    echo_green "当前识别设备：$model"
    goto_debug_page "$brand"
    echo ""
    echo_white_n "输入无线调试IP:端口："
    read pair_addr
    [ -z "$pair_addr" ] && echo_red "地址不能为空" && sleep 1 && return
    echo_white_n "输入六位配对验证码："
    read pair_code
    [ -z "$pair_code" ] && echo_red "验证码不能为空" && sleep 1 && return
    echo ""
    echo_white "执行配对命令 adb pair $pair_addr $pair_code"
    local pair_result=$(adb pair "$pair_addr" "$pair_code" 2>&1)
    echo "$pair_result"
    if echo "$pair_result" | grep -qiE "Failed|Invalid port while parsing address"; then
        echo_red "[失败] 配对校验失败，请核对IP、验证码、局域网"
    else
        echo_green "[成功] 设备配对完成"
    fi
    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 功能2：设备连接（已添加断开离线设备） ========================
func_connect() {
    clear
    show_func_header "功能2 设备连接"

    # 断开离线设备
    clean_offline_devices

    # 检测是否已连接，若已连接则提示并返回
    if check_wireless_adb; then
        echo_green "[提示] 已连接无线调试，无需重复连接"
        echo_white "已连接设备列表："
        adb devices 2>/dev/null | grep -v "List of devices"
        echo ""
        echo_white_n "按下回车返回菜单"
        read
        return
    fi

    show_connect_tips
    local brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    goto_debug_page "$brand"
    echo ""
    echo_white_n "输入设备IP:端口（示例：172.30.3.76:11451）："
    read conn_addr
    [ -z "$conn_addr" ] && echo_red "地址不能为空" && sleep 1 && return
    echo ""
    echo_white "执行 adb connect $conn_addr"
    local conn_result=$(adb connect "$conn_addr" 2>&1)
    echo "$conn_result"
    if echo "$conn_result" | grep -qiE "Failed|Connection refused|bad port number"; then
        echo_red "[失败] 连接失败，检查无线调试开关与同一局域网"
    else
        echo_green "[成功] 设备连接成功"
        local model=$(get_device_friendly_name)
        echo_green "当前识别设备：$model"
        echo ""
        adb devices
    fi
    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 功能3：推送so文件（已添加断开离线设备） ========================
func_push_so() {
    clear
    show_func_header "功能3 推送preload.so"

    # 断开离线设备
    clean_offline_devices

    # 完整连接检测（与功能6一致）
    if ! check_wireless_adb; then
        echo_red "[提示] 当前未连接无线调试，将自动跳转至设备连接..."
        sleep 2
        func_connect
        if ! check_wireless_adb; then
            echo_red "[提示] 设备连接失败，请重试"
            echo ""
            echo_white_n "按下回车返回菜单"
            read
            return
        fi
        clear
        show_func_header "功能3 推送preload.so"
    fi

    local work_dir=$(get_script_dir)
    local local_so="${work_dir}/preload.so"
    echo_green "脚本运行目录：$work_dir"
    echo_green "本地so文件路径：$local_so"
    echo_green "手机目标存放路径：$TARGET_SO_PATH"
    if [ ! -f "$local_so" ]; then
        echo_red "[错误] 当前目录缺少preload.so文件，终止推送"
        echo ""
        echo_white_n "按下回车返回菜单"
        read
        return
    fi
    echo ""
    echo_white "正在删除手机上已存在的旧文件（如有）..."
    adb shell rm -f "$TARGET_SO_PATH" 2>/dev/null
    echo_white "正在推送文件至手机系统临时目录..."
    if adb push "$local_so" "$TARGET_SO_PATH"; then
        echo_green "[成功] 文件上传完毕"
        adb shell chmod 755 "$TARGET_SO_PATH"
        echo_green "[成功] 已赋予so文件可执行权限"
    else
        echo_red "[失败] 文件推送中断，检查adb无线连接"
    fi
    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 功能4：息屏注入（新增 slide-kaslr-ok 检测） ========================
func_screen_inject() {
    clear
    clean_offline_devices

    show_func_header "功能4 息屏注入（检测输出后息屏）"

    if ! init_log_dir; then
        echo_red "[错误] 日志系统初始化失败"
        echo_white_n "按下回车返回菜单"
        read
        return
    fi
    init_log_file

    log_separator "息屏注入流程开始"
    log_info "脚本版本: 临时root工具箱8.0"
    log_info "作者: 清风南辞"
    log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # 步骤0：检测ADB连接
    log_separator "步骤0：检测ADB连接状态"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo_white "步骤0：检测ADB连接状态"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "检查ADB是否可用..."
    if ! command -v adb &> /dev/null; then
        log_error "ADB命令未找到，请先安装ADB工具"
        echo_red "[错误] ADB命令未找到"
        echo ""
        show_log_info
        log_separator "注入流程终止（ADB未安装）"
        echo_white_n "按下回车返回菜单"
        read
        return
    fi
    log_ok "ADB命令可用"
    echo_green "[OK] ADB命令可用"
    echo ""

    clean_offline_devices

    log_info "检查无线调试设备连接..."
    local connected_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E "device$")
    if [[ -z "$connected_list" ]]; then
        log_error "当前未连接无线调试设备"
        echo_red "[提示] 当前未连接无线调试，将自动跳转至设备连接..."
        log_info "自动跳转至设备连接功能"
        sleep 2
        func_connect
        log_info "重新检测设备连接..."
        connected_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E "device$")
        if [[ -z "$connected_list" ]]; then
            log_error "设备连接失败，终止注入流程"
            echo_red "[提示] 设备连接失败，请重试"
            echo ""
            show_log_info
            log_separator "注入流程终止（连接失败）"
            echo_white_n "按下回车返回菜单"
            read
            return
        fi
        clear
        show_func_header "功能4 息屏注入（检测输出后息屏）"
        echo_green "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo_green "设备已连接，继续执行注入流程"
        echo_green "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi
    log_ok "已连接无线调试设备"
    echo_green "[OK] 已连接无线调试设备"
    echo ""
    log_info "已连接设备列表："
    adb devices 2>/dev/null | grep -v "List of devices" | while read line; do log_inject_output "$line"; done
    echo_white "已连接设备："
    adb devices 2>/dev/null | grep -v "List of devices"
    echo ""

    # 步骤1：获取设备信息
    log_separator "步骤1：获取设备信息"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo_white "步骤1：获取设备信息"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "正在获取设备信息..."
    log_cmd "adb shell getprop ro.product.brand"
    local device_brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    log_inject_output "$device_brand"
    # 使用友好名称
    local device_model=$(get_device_friendly_name)
    log_inject_output "$device_model"
    log_cmd "adb shell getprop ro.build.version.release"
    local device_android=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    log_inject_output "$device_android"
    log_cmd "adb shell getprop ro.build.version.sdk"
    local device_api=$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
    log_inject_output "$device_api"
    log_cmd "adb shell getprop ro.product.cpu.abi"
    local device_arch=$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    log_inject_output "$device_arch"
    log_cmd "adb shell getprop ro.build.display.id"
    local device_build=$(adb shell getprop ro.build.display.id 2>/dev/null | tr -d '\r')
    log_inject_output "$device_build"
    log_ok "设备信息获取完成"
    echo ""
    echo_white "设备信息："
    echo_green "  ┌─────────────────────────────────┐"
    echo_green "  │ 品牌:   $device_brand"
    echo_green "  │ 型号:   $device_model"
    echo_green "  │ 系统:   Android $device_android (API $device_api)"
    echo_green "  │ 架构:   $device_arch"
    echo_green "  │ 构建:   $device_build"
    echo_green "  └─────────────────────────────────┘"
    echo ""

    # 步骤2：检查目标so文件（增加大小检测）
    log_separator "步骤2：检查目标so文件"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo_white "步骤2：检查目标so文件"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "目标文件路径: $TARGET_SO_PATH"
    log_cmd "adb shell ls -la $TARGET_SO_PATH"
    local so_check=$(adb shell ls -la "$TARGET_SO_PATH" 2>&1)
    local so_check_ret=$?
    echo "$so_check" | while read line; do log_inject_output "$line"; done

    if [ $so_check_ret -ne 0 ] || echo "$so_check" | grep -qiE "No such file|cannot access"; then
        log_error "目标文件不存在: $TARGET_SO_PATH"
        log_warn "注入可能失败，请先执行功能3推送文件"
        echo_red "[警告] 目标文件不存在"
        echo_yellow "[提示] 请先执行功能3推送preload.so文件"
        echo ""
    else
        log_ok "目标文件存在"
        echo_green "[OK] 目标文件存在"
        echo ""
        echo_white "文件详情："
        echo "$so_check"
        echo ""

        # 检测文件大小是否为0
        local file_size=$(echo "$so_check" | awk '{print $5}' | head -n1)
        if [[ "$file_size" == "0" ]]; then
            log_error "目标文件大小为0，文件已损坏！"
            echo_red "[错误] 目标文件大小为0，文件已损坏！"
            echo_yellow "[提示] 请执行功能3重新推送正确的preload.so文件"
            echo ""
            show_log_info
            log_separator "注入流程终止（文件损坏）"
            echo_white_n "按下回车返回菜单"
            read
            return
        else
            log_ok "文件大小正常: $file_size 字节"
            echo_green "[OK] 文件大小正常: $file_size 字节"
        fi
    fi

    # ========== 步骤3：执行注入（检测输出后触发息屏） ==========
    log_separator "步骤3：执行注入（检测输出后息屏）"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo_white "步骤3：执行注入（检测到 'preload starting'、'slide child' 或 'slide-kaslr-ok' 时自动息屏）"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local inject_cmd="LD_PRELOAD=$TARGET_SO_PATH /system/bin/id"
    log_info "注入命令: $inject_cmd"
    log_cmd "adb shell \"$inject_cmd\""

    echo_white "正在执行注入...（实时显示输出，匹配到目标行后将自动息屏）"
    echo_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local tmp_outfile=$(mktemp)
    local tmp_retfile=$(mktemp)
    local SCREEN_FLAG="/tmp/.screen_off_done_$$"
    rm -f "$SCREEN_FLAG"

    # 执行注入，将输出保存到临时文件，同时实时显示并触发息屏
    {
        adb shell "LD_PRELOAD=$TARGET_SO_PATH /system/bin/id; echo \$? > $tmp_retfile" 2>&1
    } | tee "$tmp_outfile" | while IFS= read -r line; do
        echo "$line"
        log_inject_output "$line"
        if [ ! -f "$SCREEN_FLAG" ]; then
            # 新增 slide-kaslr-ok 检测
            if echo "$line" | grep -qiE "preload starting pid=|slide child context|slide-kaslr-ok"; then
                echo_yellow "[检测到注入启动输出，执行息屏指令]"
                log_info "检测到匹配输出: $line，执行息屏"
                adb shell input keyevent 26 >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_ok "息屏指令发送成功 (keyevent 26)"
                    echo_green "[OK] 息屏指令已发送 (keyevent 26)"
                else
                    adb shell svc power sleep >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        log_ok "息屏指令发送成功 (svc power sleep)"
                        echo_green "[OK] 息屏指令已发送 (svc power sleep)"
                    else
                        log_warn "息屏指令发送失败"
                        echo_yellow "[警告] 息屏指令发送失败"
                    fi
                fi
                touch "$SCREEN_FLAG"
            fi
        fi
    done

    # 获取返回码和完整输出
    local inject_ret=0
    if [ -f "$tmp_retfile" ]; then
        inject_ret=$(cat "$tmp_retfile" 2>/dev/null | tr -d '\r')
    fi
    local full_output=$(cat "$tmp_outfile" 2>/dev/null)
    rm -f "$tmp_outfile" "$tmp_retfile"
    rm -f "$SCREEN_FLAG"

    echo ""
    echo_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    log_info "命令返回码: $inject_ret"

    # 判断提权是否成功
    local root_success=false
    if [ $inject_ret -eq 0 ]; then
        if echo "$full_output" | grep -qE "uid=0(\(root\))?"; then
            root_success=true
        fi
    fi

    if [ "$root_success" = true ]; then
        log_ok "注入成功！已获取 root 权限"
        echo_green "[成功] ✅ 注入成功，已获取 root 权限！"
    else
        log_error "注入失败，未能获取 root 权限"
        echo_red "[失败] ❌ 注入未成功，未能获取 root 权限"
        echo_yellow "建议："
        echo_yellow "  - 检查 preload.so 文件是否适用于当前系统版本（Android 16 / API 36）"
        echo_yellow "  - 尝试重新执行功能3推送so，或更换其他版本的so文件"
        echo_yellow "重新进行息屏注入，直到设备软重启"
        echo_yellow "如果一直失败不要一直执行息屏注入，重启设备一下等待几分钟后执行😊"
    fi

    echo ""

    log_separator "注入流程结束"
    log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "完整日志已保存到: $LOG_FILE"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    center_green "注入流程完成"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    show_log_info
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 功能5：root提权获取（修复无效输入） ========================
func_ksud_lateload() {
    clear
    show_func_header "功能5 root提权获取"

    clean_offline_devices

    if ! check_wireless_adb; then
        echo_red "[提示] 当前未连接无线调试，将自动跳转至设备连接..."
        sleep 2
        func_connect
        if ! check_wireless_adb; then
            echo_red "[提示] 设备连接失败，请重试"
            echo ""
            echo_white_n "按下回车返回菜单"
            read
            return
        fi
        clear
        show_func_header "功能5 root提权获取"
    fi

    echo_white "[步骤1] 提示文本"
    echo_white "------------------------------------------------"
    echo_white "重启完后如果壁纸不变则失败，壁纸变了则成功，如果没有重启则继续进行步骤4，直到重启"
    echo_white "------------------------------------------------"
    echo ""

    # 直接进行 su 检测（步骤2）
    echo_white "------------------------------------------------"
    echo_white "[步骤2] 检测 su 命令可用性"
    echo_white "------------------------------------------------"
    
    clean_offline_devices

    local su_test=$(adb shell 'su -c "echo ROOT_OK" 2>&1' | tr -d '\r')
    
    if echo "$su_test" | grep -q "ROOT_OK"; then
        echo_green "[成功] 检测到设备已拥有 root 权限！"
        adb shell su -c "id" 2>/dev/null | while read line; do echo_white "  $line"; done
        echo ""

        # 显示辅助代码（移动至此）
        local helper_code='$(find /data/app -name libksud.so | grep "me.weishu.kernelsu" | head -n 1) late-load --allow-shell --package-name me.weishu.kernelsu'
        echo_white "辅助代码（用于给 KSU 管理器授予 root 权限）："
        echo_white "请在接下来的交互式 shell 中执行以下命令："
        print_line
        echo_green "$helper_code"
        print_line
        echo_yellow "提示：长按命令即可复制，然后在 shell 中粘贴执行。"
        echo ""

        echo_yellow "您可以直接进入 root 交互式 shell，执行辅助代码，或返回菜单。"
        echo ""
        
        # 循环选择，直到输入有效
        while true; do
            echo_white "请选择操作："
            echo_green " [1] 进入 root 交互式 shell (推荐，可执行辅助代码)"
            echo_green " [2] 进入普通 shell，手动输入 su 获取 root"
            echo_green " [0] 返回菜单"
            echo_white_n "请输入选项："
            read opt_shell
            
            case $opt_shell in
                1)
                    echo_white "正在进入 root 交互式 shell，您可以在其中输入辅助代码（复制后粘贴执行）。"
                    echo_yellow "提示：若卡住请尝试按 Ctrl+C 中断，或重新运行脚本。"
                    echo_white "------------------------------------------------"
                    adb shell -t su -
                    echo ""
                    echo_green "已退出 root shell"
                    echo ""
                    echo_white_n "按下回车返回菜单"
                    read
                    return
                    ;;
                2)
                    echo_white "正在进入普通 shell，您需要手动输入 su 并回车获取 root。"
                    echo_yellow "提示：在 shell 中输入 exit 可退出 shell 返回菜单。"
                    echo_white "------------------------------------------------"
                    adb shell
                    echo ""
                    echo_green "已退出 shell"
                    echo ""
                    echo_white_n "按下回车返回菜单"
                    read
                    return
                    ;;
                0)
                    echo_white "返回菜单"
                    return
                    ;;
                *)
                    echo_red "输入无效，请重新选择（请输入 0、1 或 2）"
                    echo ""
                    ;;
            esac
        done
    else
        echo_red "[失败] 未检测到 root 权限（su 命令不可用或无权限）"
        echo_white "您可以尝试执行【功能4：息屏注入】来获取 root 权限。"
        echo_white "按回车键将自动跳转到步骤4（息屏注入）..."
        read
        func_screen_inject
        return
    fi
}

# ======================== 功能6：打开B站主页（已添加 clean_offline_devices + 完整连接检测） ========================
func_open_author() {
    clear
    show_func_header "功能6 打开B站主页"

    # 清理离线设备
    clean_offline_devices

    # 完整连接检测（与功能3完全一致）
    if ! check_wireless_adb; then
        echo_red "[提示] 当前未连接无线调试，将自动跳转至设备连接..."
        sleep 2
        func_connect
        if ! check_wireless_adb; then
            echo_red "[提示] 设备连接失败，请重试"
            echo ""
            echo_white_n "按下回车返回菜单"
            read
            return
        fi
        clear
        show_func_header "功能6 打开B站主页"
    fi

    echo ""
    echo_white "正在打开 B站主页..."
    echo_white "原始链接: https://b23.tv/oHaJda2"
    echo ""

    local short_url="https://b23.tv/oHaJda2"
    local target_url="$short_url"

    # 解析短链接
    if command -v curl &>/dev/null; then
        echo_white "[重定向] 正在解析短链接..."
        local real_url=$(curl -s -L -o /dev/null -w '%{url_effective}' "$short_url" 2>/dev/null)
        if [ -n "$real_url" ] && [ "$real_url" != "$short_url" ]; then
            echo_green "[重定向] 解析到真实地址: $real_url"
            target_url="$real_url"
        else
            echo_yellow "[重定向] 解析失败，使用原始链接"
        fi
    else
        echo_yellow "[提示] 未安装 curl，直接使用短链接"
    fi

    echo ""
    echo_white "最终打开地址: $target_url"
    echo ""

    # 使用方法2：adb shell am start
    echo_white "[方法2] 使用 adb shell am start ..."
    local adb_cmd="adb shell am start -a android.intent.action.VIEW -d '$target_url' --activity-clear-task --user 0"
    local adb_output=$(eval "$adb_cmd" 2>&1)
    local adb_ret=$?
    if [ $adb_ret -eq 0 ]; then
        echo_green "[成功] 已通过 adb 发送打开指令"
    else
        echo_red "[失败] adb 执行失败：$adb_output"
        echo_white "请检查手机是否已授权 USB 调试，或尝试手动复制链接："
        echo_yellow "   $target_url"
    fi

    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 检查工具箱是否已解压 ========================
check_extracted() {
    local work_dir=$(get_script_dir)
    local so_file="${work_dir}/preload.so"
    if [ ! -f "$so_file" ]; then
        echo_red "错误：未找到 preload.so 文件！"
        echo_red "请确保已将工具箱压缩包解压到当前目录，且所有文件（包括 preload.so）在同一目录下。"
        echo_red "当前脚本所在目录: $work_dir"
        echo_red "请解压后重新运行脚本。"
        exit 1
    fi
}

# ======================== 检查环境 ========================
check_adb_env() {
    if ! command -v adb &> /dev/null; then
        echo_red "未找到adb命令，请先安装adb工具"
        sleep 2
        exit 1
    fi
}

# ======================== 主循环 ========================
check_adb_env
check_extracted
while true; do
    show_menu
    read opt
    case $opt in
        1) func_pair ;;
        2) func_connect ;;
        3) func_push_so ;;
        4) func_screen_inject ;;
        5) func_ksud_lateload ;;
        6) func_open_author ;;
        0) clear; center_green "工具箱退出 | 作者：清风南辞"; exit 0 ;;
        *) echo_red "输入序号无效，请选择0~6之间数字"; sleep 1 ;;
    esac
done