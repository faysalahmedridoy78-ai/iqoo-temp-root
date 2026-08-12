# -*- coding: utf-8 -*-
"""完整构建: apktool b + 合并 classes5.dex + 16K对齐 + 签名
用法: python build_final.py <输出apk路径>
"""
import io, os, shutil, subprocess, sys, zipfile

# 构建环境路径: 请按本机环境修改, 或通过环境变量覆盖
import os as _os
ROOT = _os.environ.get('IQOO_BUILD_ROOT', '')            # apktool 反编译工程目录
NEWDEX = _os.environ.get('IQOO_NEWDEX', '')              # d8 编译的 classes.dex (可选)
JAVA = _os.environ.get('JAVA', 'java')
APKTOOL = _os.environ.get('IQOO_APKTOOL', 'apktool.jar')
BT35 = _os.environ.get('IQOO_ZIPALIGN', 'zipalign')
APKSIGNER = _os.environ.get('IQOO_APKSIGNER', 'apksigner')
KEYSTORE = _os.environ.get('IQOO_KEYSTORE', '')          # 签名密钥路径 (本地保管, 不公开)
TMP = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), '_build_tmp')

def run(cmd, env=None):
    print('>>', ' '.join(cmd) if isinstance(cmd, list) else cmd)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', env=env)
    if r.returncode != 0:
        print(r.stdout[-1500:] if r.stdout else '')
        print(r.stderr[-1500:] if r.stderr else '')
        raise SystemExit(f'FAILED')
    return r

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'DailyCleaner_new.apk'
    if os.path.isdir(TMP):
        shutil.rmtree(TMP)
    os.makedirs(TMP)

    # 1. 清缓存 + apktool b
    build_dir = os.path.join(ROOT, 'build')
    if os.path.isdir(build_dir):
        shutil.rmtree(build_dir)
    base = os.path.join(TMP, 'base.apk')
    run([JAVA, '-jar', APKTOOL, 'b', ROOT, '-o', base])

    # 2. 合并 classes5.dex
    merged = os.path.join(TMP, 'merged.apk')
    zin = zipfile.ZipFile(base)
    zout = zipfile.ZipFile(merged, 'w', zipfile.ZIP_DEFLATED)
    for item in zin.infolist():
        zout.writestr(item, zin.read(item.filename))
    zin.close()
    zout.write(NEWDEX, 'classes5.dex')
    zout.close()
    print('merged classes5.dex')

    # 3. 16K 对齐
    aligned = os.path.join(TMP, 'aligned.apk')
    run([BT35, '-f', '-P', '16', '4', merged, aligned])

    # 4. 签名 (密码从环境变量 IQOO_KS_PASS 读取, 不写入源码)
    env = dict(os.environ, JAVA_HOME=os.path.dirname(os.path.dirname(JAVA)))
    ks_pass = os.environ.get('IQOO_KS_PASS', '')
    if not ks_pass:
        raise SystemExit('缺少环境变量 IQOO_KS_PASS (签名密钥密码)')
    run([APKSIGNER, 'sign', '--ks', KEYSTORE, '--ks-key-alias', 'iqootool',
         '--ks-pass', f'pass:{ks_pass}', '--key-pass', f'pass:{ks_pass}',
         '--out', out, aligned], env=env)

    shutil.rmtree(TMP)
    print(f'OK: {out}')

if __name__ == '__main__':
    main()
