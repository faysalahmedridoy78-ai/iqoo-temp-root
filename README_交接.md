# vivo/iQOO 临时 root 工具箱 — 交接文档

> 本工具用于 vivo/iQOO 部分机型**免解锁、免刷机、临时 root**(重启失效)。
> 核心原理: CVE-2026-43499(futex PI UAF)内核利用 + KernelSU 临时加载。

---

## 一、交付物清单

| 文件 | 位置 | 说明 |
|---|---|---|
| **DailyCleaner_v1.12.apk** | `iqoo/` 根目录 | **最新版 App**(推荐使用) |
| 历史版本 | `iqoo/releases/v1.0~v1.12/` | 全部归档 |
| PC 一键脚本 | `iqoo/vivo_iqoo临时root工具箱_v1.0.zip` | Windows 电脑版(USB 有线) |
| Termux 工具箱 | `iqoo/临时root工具箱_v8_X200.zip` | 手机 Termux 版(含 X200 模式) |
| 签名密钥 | 本地保管(keystore), **不随仓库公开**, 密码勿外泄 | **永不更换**(换密钥=无法覆盖安装) |
| App 工程 | 本地 `tools/v12_base/` | apktool 工程(反编译态,可改后重打包) |

## 二、支持机型(App 版)

| 机型 | 设备代号 | 载荷 |
|---|---|---|
| iQOO Z10 Turbo | `z10t` / `iqooz10t` / `V2452A` / `pd2452` | preload_z10t.so (156KB) |
| iQOO Z10 Turbo Pro | `V2453A` / `pd2453` | preload_neo11.so (162KB) |
| iQOO Z10 Turbo+ | `pd2405` / `pd2507` | preload_z10t.so (156KB) |
| iQOO 13 | `V2408A` / `pd2408` | preload_neo11.so |
| iQOO Neo11 | `V2520A` / `pd2520` | preload_neo11.so |
| iQOO Neo10 Pro+ | `V2463A` / `pd2463` | preload_neo11.so |
| vivo X200 | `pd2415`(独立七阶段链路) | glt/w2host 体系 |

> 另: Termux 工具箱版 (临时root工具箱_v8_X200.zip) 支持 iQOO 全系 + X200, 通过菜单操作。

## 三、App 使用指南(推荐流程)

### 首次使用
1. 安装 `DailyCleaner_v1.12.apk`(覆盖安装需同签名)
2. 打开 App → 按提示**先点"清理残留"按钮** → 重启手机
3. 重启后: 安装并启动 **Shizuku**(App 内置安装入口)→ 开发者选项 → 无线调试 → 配对激活 → 回到 App 请求权限

### 提权流程(高成功率方法)
1. 确认已重启手机(关键: **pristine boot_id**)
2. App 内: 推送提权文件(自动识别机型选择对应 so)
3. 点 **"App 内执行提权"**:
   - 检测到注入输出 → **自动息屏**
   - **等 5 秒手动打开屏幕**
   - **可能再次熄屏 → 再等 5 秒打开**
   - 运行完 → 手机**软重启 = 成功标志**
4. 重启后重新连接 → **验证 root**(日志区显示 `uid=0` 即成功)
5. 点 **"加载 KernelSU"** → ksud late-load 激活(壁纸会变为"提权成功 ROOT OK"画面)

### 成功标志
- 手机壁纸变为 **"提权成功 / ROOT OK / KSU READY"** 自定义画面
- App 日志区: `✓ 已获得临时 root (su 可用)` + root 验证 uid=0
- 软重启

## 四、已知问题与限制

| 项 | 说明 |
|---|---|
| **临时 root** | 每次冷启动后需重跑(约 1-2 分钟),重启即失效 |
| **pristine boot_id** | 失败后必须**重启手机再试**,连续尝试无效 |
| **内核门禁** | 内核 >= 6.6.140 已修复 CVE,不可用(脚本/App 会自动拒绝) |
| **卡死重启** | kernelsu.ko 与内核不匹配时可能出现;建议只加载 permissive_restore 或用临时 root 不加载 KSU |
| **Z10 Turbo+ (6.6.127)** | 高成功率流程已整合;若仍失败,日志区会显示 su_daemon.log 便于定位 |
| **变砖风险** | 无(不写系统分区,最坏内核 panic,重启恢复) |

## 五、维护指南

### 版本管理
- 升级: 改本地 `tools/v12_base/apktool.yml` 版本号 → 重打包 → 签名 → 旧版移入 releases
- **构建命令**(参考): apktool b → 合并 classes5.dex(d8 编译的 Java 助手类)→ zipalign -P 16 → apksigner 签名

### 关键文件
| 文件 | 用途 |
|---|---|
| `v12_base\assets\preload_z10t.so` | Z10 Turbo / Turbo+ 载荷(156KB, 指纹 pd2405_mt6991) |
| `v12_base\assets\preload_neo11.so` | 骁龙 8 Elite 系载荷(162KB, 指纹 pd2520-bp2a) |
| `v12_base\assets\ksud` | KernelSU daemon(6.3MB) |
| `v12_base\assets\x200\` | X200 链路资产(glt/w2host/rootcmd_cli/ko/json) |
| `v12_base\assets\wallpaper.webp` | 成功壁纸(自定义文字,可改) |
| `iqoo/IQOO临时root工具箱(1)/x200/` | Termux 版 X200 资产 |

### 壁纸自定义
改 `gen_wallpaper.py`(文字/颜色)→ 生成 WebP → 等长替换 so 内嵌数据 → 重打包。
(App 兜底: WallpaperHelper 提权成功后自动写壁纸)

## 六、第三方组件与许可
- GhostLock-X200(七阶段链路): Apache-2.0 / GPL-2.0-only(见 `THIRD_PARTY.md`)
- KernelSU: GPL-2.0-only
- permissive_restore.ko: GPL-2.0-only(上游原创)
- 详见 `IQOO临时root工具箱(1)/THIRD_PARTY.md`

---

**交接要点**: 核心交付 = `DailyCleaner_v1.12.apk`(App 版)+ `vivo_iqoo临时root工具箱_v1.0.zip`(PC 版)+ 高成功率流程(清理残留 → 重启 → 检测输出息屏 → 软重启)。签名密钥勿丢。真机验证以 Z10 Turbo+(pd2507)为准,其他机型需各自实测。
