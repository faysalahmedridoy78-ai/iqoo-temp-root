# vivo/iQOO 临时 Root 工具箱

> 免解锁、免刷机、临时 root（重启失效）。
> 核心原理：CVE-2026-43499（futex PI UAF）内核利用 + KernelSU 临时加载。

## 支持机型（App 版）

| 机型 | 设备代号 | 载荷 |
|---|---|---|
| iQOO Z10 Turbo | `z10t` / `iqooz10t` / `V2452A` / `pd2452` | preload_z10t.so (156KB) |
| iQOO Z10 Turbo Pro | `V2453A` / `pd2453` | preload_neo11.so (162KB) |
| iQOO Z10 Turbo+ | `pd2405` / `pd2507` | preload_z10t.so (156KB) |
| iQOO 13 | `V2408A` / `pd2408` | preload_neo11.so |
| iQOO Neo11 | `V2520A` / `pd2520` | preload_neo11.so |
| iQOO Neo10 Pro+ | `V2463A` / `pd2463` | preload_neo11.so |
| vivo X200 | `pd2415`（独立七阶段链路） | glt/w2host 体系 |

## 目录结构

| 路径 | 说明 |
|---|---|
| `README_交接.md` | 详细使用/维护文档 |
| `build_final.py` / `bump_version.py` | 构建与版本升级脚本 |
| `临时root工具箱iQOO.sh` | Termux 版工具箱脚本 |
| `IQOO临时root工具箱(1)/` | Termux 版全套（含 X200 模式，见 `x200/`） |
| `IQOO临时root工具箱优化版/` | 优化版工具箱脚本 |
| `vivo_iqoo临时root工具箱/` | Windows PC 版（USB 有线）脚本 |
| `Z10TurboPro_临时root工具/` | Z10 Turbo Pro 专用 PC 版脚本 |
| `releases/` | 版本归档说明 |

> 仓库仅托管**源码与脚本**；APK、zip、载荷 so、ksud 等二进制产物不在仓库内。

## 提权流程（高成功率方法）

1. 重启手机（关键：**pristine boot_id**）
2. 推送提权载荷（自动识别机型选择对应 so）
3. 执行提权：检测到注入输出 → 自动息屏 → 等 5 秒打开屏幕（可能重复一次）
4. 运行完 → 手机**软重启 = 成功标志**
5. 重新连接 → 验证 root（`uid=0` 即成功）→ 加载 KernelSU

## 限制与风险

- **临时 root**：每次冷启动后需重跑（约 1-2 分钟），重启即失效
- 内核 >= 6.6.140 已修复 CVE，不可用（脚本自动拒绝）
- 失败后必须**重启手机再试**，连续尝试无效
- 不写系统分区、不改 bootloader、无变砖风险（最坏内核 panic，重启恢复）

## 构建

```bash
# 签名密钥与密码通过环境变量提供（不随仓库公开）
export IQOO_KEYSTORE=/path/to/your.keystore
export IQOO_KS_PASS=your-keystore-password
python build_final.py out.apk
```

## 免责声明

本工具仅供学习与安全研究使用，请仅用于本人设备。使用者须自行承担风险与法律责任。

## 第三方组件

见 `IQOO临时root工具箱(1)/THIRD_PARTY.md`（GhostLock-X200 链路：Apache-2.0 / GPL-2.0-only；KernelSU：GPL-2.0-only）。
