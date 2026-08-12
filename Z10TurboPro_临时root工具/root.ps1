# ============================================================
#  iQOO Z10 Turbo Pro 临时 root 一键脚本 (PC 版, USB 有线)
#  流程: USB 检测 -> 门禁检测 -> 推送 so -> 息屏注入 -> 等待 su
#        -> ksud late-load 激活 KernelSU -> 验证
#  成功标志: 手机壁纸变为 "提权成功 ROOT OK" + su -c id 输出 uid=0
#  注意: 临时 root, 重启后消失, 需重新执行
#  用法: 双击 一键临时root.bat (需 USB 连接手机并开启 USB 调试)
# ============================================================

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- 颜色输出 ----------
function Info($m)  { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "[!] $m" -ForegroundColor Yellow }
function Err($m)   { Write-Host "[x] $m" -ForegroundColor Red }

# ---------- adb 定位 (脚本目录优先) ----------
$adb = Join-Path $scriptDir "adb.exe"
if (-not (Test-Path $adb)) { $adb = "adb" }
# 预热 adb server (静默启动 daemon)
& $adb start-server 2>$null | Out-Null
Start-Sleep -Milliseconds 500
function Adb {
    param([string[]]$a)
    & $adb @a 2>&1 | Out-String
}

# ---------- 1. 检测 USB 设备 (有线) ----------
Write-Host ""
Write-Host "==============================================" -ForegroundColor White
Write-Host "   vivo/iQOO 临时root 工具箱" -ForegroundColor Green
Write-Host "   (USB 有线连接, 适配 Z10 Turbo Pro)" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor White
Write-Host ""
Warn "请确认: 1) USB 数据线连接电脑 2) 手机开启 [开发者选项 -> USB 调试] 3) 弹窗允许调试"
Write-Host ""

$found = $false
for ($t = 0; $t -lt 6; $t++) {
    $devices = (Adb "devices") -split "`r?`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match "\tdevice$" }
    if ($devices) {
        $found = $true
        break
    }
    if ($t -eq 0) { Info "等待 USB 设备识别 (最多 30 秒)..." }
    Start-Sleep -Seconds 5
}
if (-not $found) {
    Err "未检测到 USB 设备"
    Err "请检查: 数据线是否支持数据传输 / USB 调试是否开启 / 手机弹窗是否允许"
    Read-Host "按回车退出"
    exit 1
}
Ok "USB 设备已连接"
$devices | ForEach-Object { Info $_.Trim() }
Adb "shell echo ok" | Out-Null

# ---------- 2. 机型/内核门禁 ----------
Write-Host ""
$device = (Adb "shell getprop ro.product.device").Trim()
$model  = (Adb "shell getprop ro.product.model").Trim()
$kver   = (Adb "shell cat /proc/version").Trim()
$build  = (Adb "shell getprop ro.build.display.id").Trim()
Info "设备: $device / $model"
Info "固件: $build"
Info "内核: $kver"

if ($device -ne "pd2453" -and $model -ne "V2453A") {
    Err "非 iQOO Z10 Turbo Pro (pd2453), 当前: $device"
    Read-Host "按回车退出"
    exit 1
}
if ($kver -match "(\d+)\.(\d+)\.(\d+)") {
    $maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3]
    if ($maj -gt 6 -or ($maj -eq 6 -and ($min -gt 6 -or ($min -eq 6 -and $pat -ge 140)))) {
        Err "内核 $maj.$min.$pat >= 6.6.140, CVE-2026-43499 已修复, 无法使用"
        Read-Host "按回车退出"
        exit 1
    }
    Ok "内核 $maj.$min.$pat 漏洞未修复, 可以继续"
}
Warn "重要: 本工具依赖 pristine boot_id, 若之前尝试过失败, 请先重启手机再运行!"
$go = Read-Host "确认已重启手机? 输入 y 继续 (其他退出)"
if ($go -ne "y") { exit 0 }

# ---------- 3. 清理残留 + 推送 so ----------
Write-Host ""
Info "清理残留 (删除旧 preload.so / 日志) ..."
Adb "shell" "rm -f /data/local/tmp/preload.so /data/local/tmp/su_daemon.log /data/local/tmp/tornado-trace.log /data/local/tmp/temp_su.sock /data/local/tmp/su" | Out-Null
Ok "残留已清理"
Info "推送 preload.so ..."
$so = Join-Path $scriptDir "preload.so"
if (-not (Test-Path $so)) { Err "缺少 preload.so (请与本脚本放同一目录)"; Read-Host "按回车退出"; exit 1 }
Adb "push" $so "/data/local/tmp/preload.so" | Out-Null
Adb "shell" "chmod 755 /data/local/tmp/preload.so" | Out-Null
$sz = (Adb "shell wc -c < /data/local/tmp/preload.so").Trim()
if ($sz -ne "162328") { Warn "so 大小校验: $sz (期望 162328)" } else { Ok "preload.so 已就位 ($sz 字节)" }

# ---------- 4. 息屏注入 (检测输出后自动息屏, 高成功率流程) ----------
Write-Host ""
Info "注入: LD_PRELOAD /system/bin/id (实时检测输出)"
Warn "流程提示: 注入时屏幕会自动熄灭 -> 等 5 秒手动打开 -> 可能再次熄灭 -> 再等 5 秒打开"
Warn "运行完成后手机会软重启 (成功标志), 软重启后重新连一次即可"
Write-Host ""

$outFile = Join-Path $env:TEMP "inject_out.txt"
Remove-Item $outFile -Force -ErrorAction SilentlyContinue
$screenOff = $false
$proc = Start-Process $adb -ArgumentList @("shell", "LD_PRELOAD=/data/local/tmp/preload.so /system/bin/id") -NoNewWindow -RedirectStandardOutput $outFile -PassThru

# 轮询输出: 匹配关键词后自动息屏 (仅一次)
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $outFile) {
        $content = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            # 实时显示新增行 (简单方式: 显示最后 3 行)
            $lines = $content -split "`r?`n" | Where-Object { $_ -ne "" }
            if ($lines.Count -gt 0) {
                $show = $lines | Select-Object -Last 1
                if ($show -ne $lastShown) { Write-Host "  $show" -ForegroundColor DarkGray; $lastShown = $show }
            }
            if (-not $screenOff -and $content -match "preload starting pid=|slide child context|slide-kaslr-ok") {
                Write-Host ""
                Ok "检测到注入输出, 自动息屏"
                Adb "shell" "input keyevent 26" | Out-Null
                $screenOff = $true
                Warn "请等 5 秒后手动打开屏幕; 若再次熄灭再等 5 秒打开"
                Start-Sleep -Seconds 5
            }
        }
    }
    if ($proc.HasExited) { break }
}
if (-not $screenOff) {
    Warn "未检测到注入输出 (可能已静默完成), 等待 su 出现 ..."
}
Ok "注入流程结束, 等待软重启 ..."

# ---------- 4.5 等待软重启 (设备断开 -> 重新上线) ----------
$rebooted = $false
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 5
    $devNow = (Adb "devices") -split "`r?`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match "	device$" }
    if (-not $devNow) {
        Warn "检测到设备断开 (软重启中) ..."
        for ($j = 0; $j -lt 40; $j++) {
            Start-Sleep -Seconds 5
            $dev2 = (Adb "devices") -split "`r?`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match "	device$" }
            if ($dev2) { $rebooted = $true; break }
        }
        break
    }
    $suChk = (Adb "shell" "ls /data/local/tmp/su 2>/dev/null").Trim()
    if ($suChk -match "su") { $rebooted = $true; break }
}
if ($rebooted) {
    Ok "设备已重新上线"
    Warn "若刚软重启: 请重新确认 USB 授权弹窗 (允许调试)"
} else {
    Warn "未检测到软重启, 继续检查 su ..."
}

# ---------- 5. 等待 su (120秒) ----------
$found = $false
for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Seconds 5
    $su = (Adb "shell ls -la /data/local/tmp/su 2>/dev/null").Trim()
    if ($su -match "su") {
        $found = $true
        break
    }
    Write-Host "   等待提权 [$($i+1)/24] ..." -ForegroundColor DarkGray
}
if (-not $found) {
    Err "su 未出现, 提权可能失败"
    Write-Host "--- 诊断 ---"
    Write-Host (Adb "shell ls -la /data/local/tmp/preload.so /data/local/tmp/su_daemon.log 2>&1")
    Write-Host (Adb "shell tail -c 2000 /data/local/tmp/su_daemon.log 2>/dev/null")
    Read-Host "按回车退出"
    exit 1
}
Ok "su 已出现!"

$id = (Adb "shell /data/local/tmp/su -c id").Trim()
Write-Host "root 验证: $id"
if ($id -notmatch "uid=0") {
    Err "未获得 root 权限"
    Read-Host "按回车退出"
    exit 1
}
Ok "临时 root 已获得 (uid=0)!"
Warn "手机壁纸应已变为 '提权成功' 画面 (成功信号)"

# ---------- 6. ksud late-load 激活 KernelSU ----------
Write-Host ""
Info "推送 ksud 并激活 KernelSU ..."
$ksud = Join-Path $scriptDir "ksud"
if (-not (Test-Path $ksud)) { Warn "缺少 ksud 文件, 跳过 KSU 激活 (仅临时 root)"; exit 0 }
Adb "push $ksud /data/local/tmp/ksud" | Out-Null
Adb "shell chmod 755 /data/local/tmp/ksud" | Out-Null
$ksudSz = (Adb "shell wc -c < /data/local/tmp/ksud").Trim()
Ok "ksud 已就位 ($ksudSz 字节)"

$pkg = Read-Host "请输入 KernelSU 管理器包名 [默认 me.weishu.kernelsu]"
if (-not $pkg) { $pkg = "me.weishu.kernelsu" }
Info "执行 ksud late-load (需等待数十秒) ..."
$late = Adb "shell" "/data/local/tmp/su -c \"/data/local/tmp/ksud late-load --allow-shell --package-name $pkg\""
Write-Host $late
Start-Sleep -Seconds 10

# ---------- 7. 最终验证 ----------
Write-Host ""
$final = (Adb "shell /data/local/tmp/su -c id").Trim()
Info "最终 root 验证: $final"
if ($final -match "uid=0") {
    Ok "=== 完成: 临时 root + KernelSU 已激活 ==="
    Ok "打开 KernelSU 管理器授权即可使用; 重启后 root 消失需重跑"
} else {
    Warn "root 验证失败, 但 su 可能存在, 请手动检查"
}
Write-Host ""
Read-Host "按回车退出"
