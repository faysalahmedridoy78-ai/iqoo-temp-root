# THIRD_PARTY — 第三方组件与来源

本工具箱包含第三方组件, 来源与许可如下。

## GhostLock-X200 (vivo X200 临时 root 链路)

- **来源**: https://github.com/xiaohj233/ghostlock-x200-root (v1.0, tag v1.0.0)
- **用途**: X200 (PD2415, b57 内核) 临时 root 七阶段提权链
- **集成方式**: 独立扩展 (x200/ 目录 + x200_mode.sh), 不影响 iQOO 原有机型路径

| 组件 | 来源标记 | 许可 |
|---|---|---|
| glt / w2host (exploit 源码 → NDK 构建) | DERIVED (自上游构建) | Apache-2.0 |
| offsets_auto.py / patch_ko_all.py / rootcmd_client.py / patch_vermagic.py | COPIED | Apache-2.0 |
| win_offs_b57.json | GENERATED (镜像固有偏移) | Apache-2.0 |
| permissive_restore.ko (+ 源码思路) | COPIED (上游预编译) | GPL-2.0-only |
| kernelsu.ko (官方 KernelSU v3.2.5 + vermagic 适配) | COPIED (UPSTREAM) | GPL-2.0-only |
| ksud (官方 KernelSU v3.2.5 APK libksud.so) | COPIED (UPSTREAM) | GPL-2.0-only |
| x200_mode.sh (bash 移植编排) | DERIVED (自上游 root_full_permissive_restore.ps1 逻辑移植) | Apache-2.0 |
| README_X200.md | LOCAL | Apache-2.0 |

上游许可文本见 `x200/LICENSE-Apache-2.0.txt` 与 `x200/LICENSE-GPL-2.0-only.txt`;
上游声明见 `x200/NOTICE-ghostlock-x200.txt`。

## 其他 (iQOO 原有机型链路)

iQOO 机型链路 (preload.so 息屏注入 / KernelSU late-load) 为原工具箱自有资产, 非本第三方记录范围。
