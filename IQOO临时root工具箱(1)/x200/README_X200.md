# vivo X200 临时 root 模式说明

> 本模式为独立扩展链路, 不影响工具箱内 iQOO 机型的任何功能。
> 移植自 [ghostlock-x200-root](https://github.com/xiaohj233/ghostlock-x200-root) v1.0
> (Apache-2.0 / GPL-2.0-only, 详见 NOTICE-ghostlock-x200.txt 与 THIRD_PARTY.md)

## 支持范围

| 设备 | 内核 | 状态 |
|---|---|---|
| vivo X200 (PD2415) | `6.6.89-android15-8-gb57af212129c`(构建 b57) | ✅ 可尝试 |
| 其他 | 内核 >= 6.6.140 已修复 CVE-2026-43499 | ❌ 不可用 |

**检查内核**:
```bash
adb shell cat /proc/version
# 期望: 6.6.89-android15-8-gb57af212129c-...
# 若 >= 6.6.140, 漏洞已修复, 工具会提示并退出
```

## 使用步骤

1. 进入工具箱菜单 → `[6] vivo X200 临时root`
2. 脚本自动: 识别设备 → 版本门禁 → 资产检查 → 七阶段提权 → 验证
3. 成功标志: `SELinux: Permissive` + rootcmd 在线 + 网络正常
4. **重启后 root 消失**, 需重新运行本功能 (临时 root 特性)

## 流程说明 (七阶段)

```
STAGE1  关闭 SELinux (glt 写 selinux_state, 最多5轮)
STAGE2  kptr_restrict=0 (暴露内核符号)
STAGE3  KASLR base 校验
STAGE3.4 动态偏移 (设备 kallsyms + BTF + win_offs_b57.json, 零硬编码)
STAGE3.5 ko 重定位 (patch_ko_all.py) + 推送
STAGE4+5 w2host cred 泄漏 → glt 写 capsym → CAPSROOT (最多3轮)
STAGE6   rootcmd → INSMOD permissive_restore (清零GL宿主, 无限提权) → kernelsu
STAGE7   25s 后验证 Permissive + 网络
```

## 依赖

- Termux: `pkg install python` + `pip install pyelftools` (脚本会自动检查/提示)
- adb (工具箱自带)

## 资产清单 (x200/)

| 文件 | 来源 | 许可 |
|---|---|---|
| `glt` | NDK 构建 (exploit/src, build_glt_esync.sh) | Apache-2.0 (DERIVED) |
| `w2host` | NDK 构建 (exploit/src/w2host.c) | Apache-2.0 (LOCAL) |
| `ksud` | 官方 KernelSU v3.2.5 APK `libksud.so` | GPL-2.0-only |
| `permissive_restore.ko` | 随上游仓库预编译 | GPL-2.0-only |
| `kernelsu.ko` | 官方 KernelSU v3.2.5 + vermagic 适配 | GPL-2.0-only |
| `win_offs_b57.json` | 镜像固有偏移 (设备派生) | Apache-2.0 (GENERATED) |
| `offsets_auto.py` / `patch_ko_all.py` / `rootcmd_client.py` / `patch_vermagic.py` | 上游工具 | Apache-2.0 (COPIED) |

## 已知限制 / FAQ

- **临时 root**: 每次冷启动后需重跑 (约 1-2 分钟)
- **root 通道**: 默认 rootcmd socket (不用 KernelSU su, 防 vivo 检测 panic)
- **网络**: permissive_restore 加载后网络/热点正常; 不加载则可能异常
- **变砖风险**: 无 (不写系统分区, 最坏内核 panic, 重启恢复)
- **异常重启**: 可能损坏 /data inode (脚本用唯一后缀缓解; 蓝牙配对可能需重做)
- **不要升级系统**: 新构建可能修复 CVE-2026-43499 (>= 6.6.140)

## 日志

运行日志位于 `log/inject_*.log`, 与 iQOO 模式共用日志体系。
