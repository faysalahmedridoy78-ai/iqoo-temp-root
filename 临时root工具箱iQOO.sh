#!/data/data/com.termux/files/usr/bin/bash
# 临时 root工具箱8.0
# 作者：清风南辞{酷安}

# ======================== 颜色常量 ========================
GREEN='\033[32m'
RED='\033[31m'
WHITE='\033[37m'
RESET='\033[0m'

# ======================== 全局变量 ========================
TARGET_SO_PATH="/data/local/tmp/preload.so"
DEFAULT_PORT="5555"
LINE_WIDTH=50 # 分割线宽度，控制整体界面宽度

# ======================== 工具函数 ========================
# 获取脚本所在目录
get_script_dir() {
    local script_real=$(readlink -f "$0")
    dirname "$script_real"
}

# 绿色输出
echo_green() {
    printf "${GREEN}%s${RESET}\n" "$1"
}

# 红色输出
echo_red() {
    printf "${RED}%s${RESET}\n" "$1"
}

# 白色输出
echo_white() {
    printf "${WHITE}%s${RESET}\n" "$1"
}

# 白色不换行输出（用于提示输入）
echo_white_n() {
    printf "${WHITE}%s${RESET}" "$1"
}

# 生成等宽分割线
print_line() {
    local line=""
    for ((i=0; i<LINE_WIDTH; i++)); do
        line="${line}="
    done
    printf "${WHITE}%s${RESET}\n" "$line"
}

# 文字居中（纯ASCII宽度计算）
center_text() {
    local text="$1"
    local text_len=${#text}
    local pad=$(( (LINE_WIDTH - text_len) / 2 ))
    printf "%${pad}s%s\n" "" "$text"
}

# 绿色居中输出
center_green() {
    local text="$1"
    local text_len=${#text}
    local pad=$(( (LINE_WIDTH - text_len) / 2 ))
    printf "${GREEN}%${pad}s%s${RESET}\n" "" "$text"
}

# 校验无线adb设备
check_wireless_adb() {
    local device_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E ":[0-9]{4,}")
    if [[ -z "$device_list" ]]; then
        echo_red "[错误] 当前无无线调试设备，请先配对/连接手机"
        return 1
    fi
    return 0
}

# 检查是否已有已连接的无线调试设备
check_already_connected() {
    local connected_list=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -E "device$")
    if [[ -n "$connected_list" ]]; then
        echo_green "你已连接无线调试"
        echo_white "已连接设备列表："
        adb devices 2>/dev/null | grep -v "List of devices"
        sleep 2
        return 0
    fi
    return 1
}

# 多重息屏指令
screen_off() {
    adb shell input keyevent 26 >/dev/null 2>&1
    [ $? -eq 0 ] && return 0
    adb shell svc power sleep >/dev/null 2>&1
    return $?
}

# 跳转无线调试页面（小米/红米/POCO、OPPO/realme/一加、vivo/iQOO）
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

    # 兜底：开发者选项主页
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

    # 最终兜底：设置首页
    if [ $ret -ne 0 ]; then
        adb shell am start -a android.settings.SETTINGS >/dev/null 2>&1
        echo_red "[警告] 一键跳转失败，请手动开启无线调试"
    else
        echo_green "[成功] 已跳转手机无线调试页面"
    fi
}

# 无线配对操作需知
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

# 设备连接操作需知
show_connect_tips() {
    echo ""
    print_line
    center_green "操作须知"
    print_line
    echo_green " 1.打开无线调试，长按IP地址和端口并复制输入，打开状态栏如果出现已连接到无线调试则成功，完成第一步之后都从第二步进行"
    print_line
    echo ""
}

# ======================== 主菜单（居中对称） ========================
show_menu() {
    clear
    print_line
    center_green "ADB工具箱 | 临时root注入工具"
    center_green "by 清风南辞"
    print_line
    echo_green " [1] 无线配对"
    echo_green " [2] 设备连接"
    echo_green " [3] 推送preload.so至手机目录"
    echo_green " [4] 息屏注入"
    echo_green " [5] root提权获取"
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
    
    # 检查是否已连接无线调试
    if check_already_connected; then
        return
    fi
    
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
    
    # 检测多种错误信息
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
    
    # 检查是否已连接无线调试
    if check_already_connected; then
        return
    fi
    
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
    
    # 检测多种错误信息
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
        echo ""
        echo_white_n "按下回车返回菜单"
        read
        return
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

# ======================== 功能4：息屏注入 ========================
func_screen_inject() {
    clear
    print_line
    center_green "功能4 息屏注入"
    print_line
    if ! check_wireless_adb; then
        echo ""
        echo_white_n "按下回车返回菜单"
        read
        return
    fi
    echo_white "[步骤1] 下发息屏电源指令"
    screen_off
    [ $? -eq 0 ] && echo_green "[成功] 息屏指令发送完成" || echo_red "[异常] 息屏指令未生效"
    echo_green "[步骤2] 等待3秒延时缓冲"
    sleep 3
    echo ""
    echo_white "[步骤3] 启动LD_PRELOAD注入程序"
    adb shell "LD_PRELOAD=$TARGET_SO_PATH /system/bin/id"
    echo_green "[完成] 全部注入流程执行结束"
    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 功能5：KernelSU加载 ========================
func_ksud_lateload() {
    clear
    print_line
    center_green "功能5 root提权获取"
    print_line
    if ! check_wireless_adb; then
        echo ""
        echo_white_n "按下回车返回菜单"
        read
        return
    fi

    echo_white "[步骤1] 执行 adb shell su"
    echo_white "------------------------------------------------"
    
    # 辅助代码
    local helper_code='$(find /data/app -name libksud.so | grep "me.weishu.kernelsu" | head -n 1) \ late-load --allow-shell --package-name me.weishu.kernelsu'
    
    print_line
    echo_green "【辅助代码】"
    echo_green "长按选取我在点我一下即可复制"
    echo_green "$helper_code"
    print_line
    echo_white "------------------------------------------------"
    
    echo_white "[步骤2] 自动执行 adb shell su"
    echo_white "------------------------------------------------"
    
    # 执行 adb shell su
    adb shell su
    
    # 显示提示文本
    echo_white ""
    echo_white "------------------------------------------------"
    echo_white "【提示文本】"
    echo_white "重启完后如果壁纸不变则失败，壁纸变了则成功，如果没有重启则继续进行步骤4，直到重启"
    echo_white "------------------------------------------------"

    echo ""
    echo_white_n "按下回车返回菜单"
    read
}

# ======================== 主循环 ========================
check_adb_env() {
    if ! command -v adb &> /dev/null; then
        echo_red "未找到adb命令，请先安装adb工具"
        sleep 2
        exit 1
    fi
}

check_adb_env
while true; do
    show_menu
    read opt
    case $opt in
        1) func_pair ;;
        2) func_connect ;;
        3) func_push_so ;;
        4) func_screen_inject ;;
        5) func_ksud_lateload ;;
        0) clear; center_green "工具箱退出 | 作者：清风南辞"; exit 0 ;;
        *) echo_red "输入序号无效，请选择0~5之间数字"; sleep 1 ;;
    esac
done