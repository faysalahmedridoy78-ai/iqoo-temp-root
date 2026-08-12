# -*- coding: utf-8 -*-
"""
iqoo越狱工具 版本升级脚本
用法:  python bump_version.py <新版本名> [--build-only]
示例:  python bump_version.py 1.1
说明:
  1. versionCode 自动 +1 (Android 覆盖安装依据)
  2. versionName 更新为新版本名
  3. 自动重打包 + 16K 对齐 + 签名
  4. 当前版本 APK 自动归档到 releases/<旧版本>/ (保留 keystore 同签名,可覆盖升级)
"""
import io, os, re, shutil, subprocess, sys, glob

# 构建环境路径: 请按本机环境修改, 或通过环境变量覆盖
ROOT = os.environ.get('IQOO_BUILD_ROOT', '')            # apktool 反编译工程目录
OUT_DIR = os.path.dirname(os.path.abspath(__file__))    # 输出目录 = 脚本所在目录
RELEASES = os.path.join(OUT_DIR, 'releases')
KEYSTORE = os.environ.get('IQOO_KEYSTORE', '')          # 签名密钥路径 (本地保管, 不公开)
KS_PASS = os.environ.get('IQOO_KS_PASS', '')            # 签名密钥密码 (环境变量, 不写入源码)
ALIAS = 'iqootool'
JAVA = os.environ.get('JAVA', 'java')
APKTOOL = os.environ.get('IQOO_APKTOOL', 'apktool.jar')
BT35 = os.environ.get('IQOO_ZIPALIGN', 'zipalign')
APKSIGNER = os.environ.get('IQOO_APKSIGNER', 'apksigner')

def run(cmd, env=None):
    print('>>', cmd if isinstance(cmd, str) else ' '.join(cmd))
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, encoding='utf-8', errors='replace', env=env)
    if r.returncode != 0:
        print(r.stdout[-2000:] if r.stdout else '')
        print(r.stderr[-2000:] if r.stderr else '')
        raise SystemExit(f'FAILED: {cmd}')
    return r

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    new_ver = sys.argv[1]

    # 1. 读取当前版本
    yml = os.path.join(ROOT, 'apktool.yml')
    s = io.open(yml, encoding='utf-8').read()
    m = re.search(r'versionCode: (\d+)', s)
    m2 = re.search(r'versionName: (.+)', s)
    if not m or not m2:
        raise SystemExit('apktool.yml 缺少 versionInfo')
    old_code, old_name = int(m.group(1)), m2.group(1).strip()
    new_code = old_code + 1
    if old_name == new_ver:
        raise SystemExit(f'版本号未变化 ({new_ver}): 请传入新版本号,例如 bump_version.py 1.2')
    print(f'版本: {old_name} (code {old_code}) -> {new_ver} (code {new_code})')

    # 2. 更新 apktool.yml
    s = s.replace(f'versionCode: {old_code}', f'versionCode: {new_code}')
    s = s.replace(f'versionName: {old_name}', f'versionName: {new_ver}')
    io.open(yml, 'w', encoding='utf-8', newline='').write(s)

    # 3. 重打包 (先删 build 缓存,避免 manifest 版本信息不更新)
    unsigned = os.path.join(OUT_DIR, '_unsigned.apk')
    aligned = os.path.join(OUT_DIR, '_aligned.apk')
    build_dir = os.path.join(ROOT, 'build')
    if os.path.isdir(build_dir):
        shutil.rmtree(build_dir)
    run([JAVA, '-jar', APKTOOL, 'b', ROOT, '-o', unsigned])

    # 3.5 合并 classes5.dex (服务器验证客户端, 由 d8 单独编译)
    import zipfile
    NEWDEX = os.environ.get('IQOO_NEWDEX', '')  # d8 编译的 classes.dex (可选)
    if os.path.exists(NEWDEX):
        merged = os.path.join(OUT_DIR, '_merged.apk')
        zin = zipfile.ZipFile(unsigned)
        zout = zipfile.ZipFile(merged, 'w', zipfile.ZIP_DEFLATED)
        for item in zin.infolist():
            zout.writestr(item, zin.read(item.filename))
        zin.close()
        zout.write(NEWDEX, 'classes5.dex')
        zout.close()
        os.remove(unsigned)
        os.rename(merged, unsigned)
        print('merged classes5.dex (server verify client)')

    # 4. 16K 对齐
    run([BT35, '-f', '-P', '16', '4', unsigned, aligned])

    # 5. 签名 (先检查根目录目标是否已存在,防覆盖)
    out_apk = os.path.join(OUT_DIR, f'DailyCleaner_v{new_ver}.apk')
    if os.path.exists(out_apk):
        raise SystemExit(f'根目录已存在 {os.path.basename(out_apk)}: 拒绝覆盖,请先手动归档该文件')
    env = dict(os.environ, JAVA_HOME=os.path.dirname(os.path.dirname(JAVA)))
    run([APKSIGNER, 'sign', '--ks', KEYSTORE, '--ks-key-alias', ALIAS,
         '--ks-pass', f'pass:{KS_PASS}', '--key-pass', f'pass:{KS_PASS}',
         '--out', out_apk, aligned], env=env)

    # 6. 归档旧版本 (防覆盖: hash 相同跳过, 不同保留双份)
    import hashlib
    old_apk = os.path.join(OUT_DIR, f'DailyCleaner_v{old_name}.apk')
    if os.path.exists(old_apk):
        old_dir = os.path.join(RELEASES, f'v{old_name}')
        os.makedirs(old_dir, exist_ok=True)
        dest = os.path.join(old_dir, os.path.basename(old_apk))
        if os.path.exists(dest):
            h1 = hashlib.sha256(open(old_apk, 'rb').read()).hexdigest()
            h2 = hashlib.sha256(open(dest, 'rb').read()).hexdigest()
            if h1 == h2:
                os.remove(old_apk)
                print(f'归档已存在相同文件,删除根目录冗余副本')
            else:
                backup = dest + '.prev'
                if os.path.exists(backup):
                    os.remove(backup)
                shutil.move(dest, backup)
                shutil.move(old_apk, dest)
                print(f'归档目录已有不同版本,旧文件保留为 {os.path.basename(backup)}')
        else:
            shutil.move(old_apk, dest)
            print(f'已归档旧版 -> {old_dir}')
        idsig = old_apk + '.idsig'
        if os.path.exists(idsig):
            shutil.move(idsig, os.path.join(old_dir, os.path.basename(idsig)))
    else:
        print('(根目录无旧版 APK,跳过归档)')

    # 清理中间文件
    for tmp in (unsigned, aligned):
        if os.path.exists(tmp):
            os.remove(tmp)

    print(f'\n完成: {out_apk}')
    print(f'当前版本: v{new_ver} (versionCode={new_code})')

if __name__ == '__main__':
    main()
