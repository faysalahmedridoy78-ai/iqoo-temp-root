#!/data/data/com.termux/files/usr/bin/bash
# 临时 root工具箱8.0
# 作者：清风南辞{酷安}

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
LINE_WIDTH=50
LOG_DIR=""
LOG_FILE=""
MAX_LOGS=5

# ======================== 工具函数 ========================
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

print_line() {
    local line=""
    for ((i=0; i<LINE_WIDTH; i++)); do line="${line}="; done
    printf "${WHITE}%s${RESET}\n" "$line"
}

center_text() {
    local text="$1"
    local text_len=${#text}
    local pad=$(( (LINE_WIDTH - text_len) / 2 ))
    printf "%${pad}s%s\n" "" "$text"
}

center_green() {
    local text="$1"
    local text_len=${#text}
    local pad=$(( (LINE_WIDTH - text_len) / 2 ))
    printf "${GREEN}%${pad}s%s${RESET}\n" "" "$text"
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

# ======================== ADB 相关函数 ========================
# 修改：只识别状态为 "device" 的无线连接，忽略 offline 等
check_wireless_adb() {
    local device_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E ":[0-9]{4,}" | grep -w "device$")
    [ -n "$device_list" ]
}

# 新增：自动断开所有 offline 设备
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

# ======================== 主菜单 ========================
show_menu() {
    clear
    print_line
    center_green "ADB工具箱 | 临时root注入工具"
    center_green "by 清风南辞"
    print_line
    echo_green " [1] 无线配对"
    echo_green " [2] 设备连接"
    echo_green " [3] 推送preload.so至手机目录"
    echo_green " [4] 息屏注入（含日志）"
    echo_green " [5] root提权获取"
    if [ -f "$X200_MODE_SCRIPT" ]; then
        echo_green " [6] vivo X200 临时root"
    fi
    echo_green " [0] 退出程序"
    print_line
    echo_white_n "请输入功能序号："
}

# ======================== 功能1：无线配对 ========================
func_pair() {
    clear
    print_line
    center_green "功能1 无线配对"
    print_line
    if check_already_connected; then return; fi
    show_pair_tips
    local brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    local model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
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

# ======================== 功能2：设备连接 ========================
func_connect() {
    clear
    print_line
    center_green "功能2 设备连接"
    print_line
    if check_already_connected; then return; fi
    show_connect_tips
    local brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    local model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    echo_green "当前识别设备：$model"
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
        echo_green "[成功] 设备连接成功，已连接列表："
        adb devices
    fi
    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 功能3：推送so文件 ========================
func_push_so() {
    clear
    print_line
    center_green "功能3 推送preload.so"
    print_line
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
        print_line
        center_green "功能3 推送preload.so"
        print_line
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

# ======================== 功能4：息屏注入（检测输出后息屏） ========================
func_screen_inject() {
    clear
    # 清理离线设备，避免多设备冲突
    clean_offline_devices

    print_line
    center_green "功能4 息屏注入（检测输出后息屏）"
    print_line
    echo ""

    # 初始化日志
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

    # 再次清理，确保只保留在线设备
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
        print_line
        center_green "功能4 息屏注入（检测输出后息屏）"
        print_line
        echo ""
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
    log_cmd "adb shell getprop ro.product.model"
    local device_model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
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

    # 步骤2：检查目标so文件
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
    fi

    # ========== 步骤3：执行注入（检测输出后触发息屏） ==========
    log_separator "步骤3：执行注入（检测输出后息屏）"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo_white "步骤3：执行注入（检测到 'preload starting' 或 'slide child' 时自动息屏）"
    echo_white "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local inject_cmd="LD_PRELOAD=$TARGET_SO_PATH /system/bin/id"
    log_info "注入命令: $inject_cmd"
    log_cmd "adb shell \"$inject_cmd\""

    echo_white "正在执行注入...（实时显示输出，匹配到目标行后将自动息屏）"
    echo_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local inject_ret=0
    local tmp_output=$(mktemp)
    local SCREEN_FLAG="/tmp/.screen_off_done_$$"   # 临时标记文件，避免重复息屏
    rm -f "$SCREEN_FLAG"

    {
        adb shell "LD_PRELOAD=$TARGET_SO_PATH /system/bin/id; exit" 2>&1
        echo $? > "$tmp_output.ret"
    } | while IFS= read -r line; do
        # 实时显示到屏幕
        echo "$line"
        # 实时写入日志
        log_inject_output "$line"

        # 检测是否匹配目标字符串（且尚未执行息屏）
        if [ ! -f "$SCREEN_FLAG" ]; then
            # 匹配模式：包含 "preload starting pid=" 或 "slide child context"
            if echo "$line" | grep -qiE "preload starting pid=|slide child context"; then
                echo_yellow "[检测到注入启动输出，执行息屏指令]"
                log_info "检测到匹配输出: $line，执行息屏"

                # 尝试多种息屏方式
                adb shell input keyevent 26 >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_ok "息屏指令发送成功 (keyevent 26) 于检测到输出后"
                    echo_green "[OK] 息屏指令已发送 (keyevent 26)"
                else
                    adb shell svc power sleep >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        log_ok "息屏指令发送成功 (svc power sleep) 于检测到输出后"
                        echo_green "[OK] 息屏指令已发送 (svc power sleep)"
                    else
                        log_warn "息屏指令发送失败"
                        echo_yellow "[警告] 息屏指令发送失败"
                    fi
                fi

                # 创建标记文件，确保只执行一次
                touch "$SCREEN_FLAG"
            fi
        fi
    done

    # 获取返回码
    if [ -f "$tmp_output.ret" ]; then
        inject_ret=$(cat "$tmp_output.ret")
        rm -f "$tmp_output.ret"
    fi
    rm -f "$tmp_output"
    rm -f "$SCREEN_FLAG"   # 清理标记文件

    echo ""
    echo_yellow "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    log_info "命令返回码: $inject_ret"
    if [ $inject_ret -eq 0 ]; then
        log_ok "注入命令执行完成"
        echo_green "[完成] 注入命令执行完成"
    else
        log_error "注入命令执行失败，返回码: $inject_ret"
        echo_red "[失败] 注入命令执行失败，返回码: $inject_ret"
    fi
    echo ""

    # 完成
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

# ======================== 功能5：root提权获取（已添加清理离线设备） ========================
func_ksud_lateload() {
    clear
    print_line
    center_green "功能5 root提权获取"
    print_line

    # 清理离线设备，避免多个设备冲突
    clean_offline_devices

    # ----- 步骤0：检测无线调试，若无则跳转连接 -----
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
        print_line
        center_green "功能5 root提权获取"
        print_line
    fi

    # ----- 步骤1：显示提示文本（原步骤1） -----
    echo_white "[步骤1] 提示文本"
    echo_white "------------------------------------------------"
    echo_white "重启完后如果壁纸不变则失败，壁纸变了则成功，如果没有重启则继续进行步骤4，直到重启"
    echo_white "------------------------------------------------"
    echo ""

    # ----- 步骤2：显示辅助代码（原步骤2） -----
    echo_white "[步骤2] 辅助代码（用于加载KernelSU，仅在需要时执行）"
    echo_white "------------------------------------------------"
    local helper_code='第一条$(find /data/app -name libksud.so | grep "me.weishu.kernelsu" | head -n 1) \
    第二条late-load --allow-shell --package-name me.weishu.kernelsu'
    print_line
    echo_green "【辅助代码】"
    echo_green "长按选取即可复制"
    echo_green "$helper_code"
    print_line
    echo_white "注意：以上代码通常用于KernelSU的late-load操作，您可以在获得root权限后，在root交互式shell中执行。"
    echo_white "------------------------------------------------"
    echo ""

    # ----- 步骤3：检测su命令状态 -----
    echo_white "------------------------------------------------"
    echo_white "[步骤3] 检测su命令可用性"
    echo_white "------------------------------------------------"
    
    # 再次清理，确保只有一个设备
    clean_offline_devices

    local su_test=$(adb shell 'su -c "echo ROOT_OK" 2>&1' | tr -d '\r')
    
    if echo "$su_test" | grep -q "ROOT_OK"; then
        # ---------- 有root权限 ----------
        echo_green "[成功] 检测到设备已拥有 root 权限！"
        adb shell su -c "id" 2>/dev/null | while read line; do echo_white "  $line"; done
        echo ""
        echo_yellow "您可以直接进入 root 交互式 shell，执行辅助代码，或返回菜单。"
        echo ""
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
                ;;
            2)
                echo_white "正在进入普通 shell，您需要手动输入 su 并回车获取 root。"
                echo_yellow "提示：在 shell 中输入 exit 可退出 shell 返回菜单。"
                echo_white "------------------------------------------------"
                adb shell
                echo ""
                echo_green "已退出 shell"
                ;;
            0|*)
                echo_white "返回菜单"
                ;;
        esac
        echo ""
        echo_white_n "按下回车返回菜单"
        read
        return
    else
        # ---------- 无root权限 ----------
        echo_red "[失败] 未检测到 root 权限（su 命令不可用或无权限）"
        echo_white "您可以尝试执行【功能4：息屏注入】来获取 root 权限。"
        echo_white "按回车键将自动跳转到步骤4（息屏注入）..."
        read   # 等待用户按回车确认
        func_screen_inject   # 执行息屏注入
        return
    fi
}

# ======================== 检查工具箱是否已解压（检测 preload.so 是否存在） ========================
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

# ======================== X200 模式加载 (独立文件, 不影响 iQOO 功能) ========================
X200_MODE_SCRIPT="$(get_script_dir)/x200/x200_mode.sh"
if [ -f "$X200_MODE_SCRIPT" ]; then
    source "$X200_MODE_SCRIPT"
fi

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
        6) func_x200_root ;;
        0) clear; center_green "工具箱退出 | 作者：清风南辞"; exit 0 ;;
        *) echo_red "输入序号无效，请选择0~5之间数字"; sleep 1 ;;
    esac
done