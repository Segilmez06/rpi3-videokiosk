#!/usr/bin/env python3
"""
Patch Alpine initramfs /init script to inject hardware LED state machine & early boot splash:
1. Red PWR LED OFF, Green ACT starts blinking with 100ms delay
2. Display boot splash screen immediately on HDMI framebuffer (/dev/fb0) via freestanding fbdraw
3. Once unpacking is complete, Red stays OFF and Green ACT starts SOLID ON
"""
import sys
import os
import subprocess
import tempfile
import shutil
from PIL import Image

def patch_initramfs(initramfs_path):
    if not os.path.isfile(initramfs_path):
        print(f"[-] Error: initramfs file not found: {initramfs_path}", file=sys.stderr)
        return 1

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(os.path.dirname(script_dir))
    boot_png = os.path.join(root_dir, "assets", "booting.png")
    fbdraw_c = os.path.join(script_dir, "fbdraw.c")

    workdir = tempfile.mkdtemp(prefix="initramfs_patch_")
    backup_path = initramfs_path + ".orig"
    shutil.copy2(initramfs_path, backup_path)

    try:
        # Unpack cpio
        p1 = subprocess.Popen(["gzip", "-dc", backup_path], stdout=subprocess.PIPE)
        subprocess.check_call(["cpio", "-idm"], cwd=workdir, stdin=p1.stdout, stderr=subprocess.DEVNULL)
        p1.wait()

        # Compile freestanding aarch64 fbdraw utility
        fbdraw_bin = os.path.join(workdir, "bin", "fbdraw")
        if os.path.isfile(fbdraw_c):
            print("[*] Compiling freestanding fbdraw utility for direct framebuffer splash...")
            cmd = [
                "clang", "-target", "aarch64-linux-gnu", "-fuse-ld=lld",
                "-static", "-nostdlib", "-fno-stack-protector", "-O2",
                fbdraw_c, "-o", fbdraw_bin
            ]
            subprocess.check_call(cmd)
            try:
                subprocess.check_call(["llvm-strip", fbdraw_bin], stderr=subprocess.DEVNULL)
            except Exception:
                pass
            os.chmod(fbdraw_bin, 0o755)
            usr_bin_fbdraw = os.path.join(workdir, "usr", "bin", "fbdraw")
            if not os.path.exists(usr_bin_fbdraw):
                try:
                    shutil.copy2(fbdraw_bin, usr_bin_fbdraw)
                except Exception:
                    pass
            print(f"[+] Compiled freestanding fbdraw: {os.path.getsize(fbdraw_bin)} bytes")

        # Convert boot splash image to Netpbm PPM for fbdraw
        if os.path.isfile(boot_png):
            print(f"[*] Injecting early boot splash from {boot_png} into initramfs...")
            im = Image.open(boot_png).convert("RGB")
            ppm_path = os.path.join(workdir, "splash.ppm")
            im.save(ppm_path, format="PPM")
            print(f"[+] Created {ppm_path} ({os.path.getsize(ppm_path)} bytes)")

        # Prune DRM modules from initramfs so simplefb stays active without unbinding
        print("[*] Pruning DRM drivers from initramfs to preserve firmware framebuffer...")
        modules_dir = os.path.join(workdir, "usr", "lib", "modules")
        if os.path.isdir(modules_dir):
            for kver in os.listdir(modules_dir):
                kpath = os.path.join(modules_dir, kver)
                drm_path = os.path.join(kpath, "kernel", "drivers", "gpu", "drm")
                if os.path.isdir(drm_path):
                    shutil.rmtree(drm_path)
                    print(f"[+] Removed DRM modules from initramfs: {drm_path}")

                dep_file = os.path.join(kpath, "modules.dep")
                if os.path.isfile(dep_file):
                    with open(dep_file, "r") as f:
                        lines = f.readlines()
                    filtered_dep = [l for l in lines if "kernel/drivers/gpu/drm" not in l]
                    with open(dep_file, "w") as f:
                        f.writelines(filtered_dep)
                    print(f"[+] Filtered {len(lines) - len(filtered_dep)} DRM entries from modules.dep")

                alias_file = os.path.join(kpath, "modules.alias")
                if os.path.isfile(alias_file):
                    with open(alias_file, "r") as f:
                        lines = f.readlines()
                    filtered_alias = [l for l in lines if not any(d in l for d in ["vc4", "v3d", "simpledrm", "udl", "gud"])]
                    with open(alias_file, "w") as f:
                        f.writelines(filtered_alias)
                    print(f"[+] Filtered {len(lines) - len(filtered_alias)} DRM aliases from modules.alias")

        # Add blacklist rules to initramfs modprobe.d
        blacklist_file = os.path.join(workdir, "etc", "modprobe.d", "blacklist.conf")
        if os.path.isfile(blacklist_file):
            with open(blacklist_file, "a") as f:
                f.write("\n# Video Kiosk: Prevent DRM from unbinding firmware framebuffer during early boot\n")
                f.write("blacklist vc4\nblacklist v3d\nblacklist simpledrm\nblacklist udl\nblacklist gud\n")
            print("[+] Appended DRM blacklists to initramfs blacklist.conf")

        init_file = os.path.join(workdir, "init")
        with open(init_file, "r") as f:
            content = f.read()

        target1 = "$MOCK mount -t sysfs -o noexec,nosuid,nodev sysfs /sys"
        code1 = """$MOCK mount -t sysfs -o noexec,nosuid,nodev sysfs /sys
# Video Kiosk: Green ACT blinking 100ms delay while copying image to RAM; Red PWR OFF
for _a in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
    if [ -d "$_a" ]; then
        echo timer > "$_a/trigger" 2>/dev/null || true
        echo 100 > "$_a/delay_on" 2>/dev/null || true
        echo 100 > "$_a/delay_off" 2>/dev/null || true
    fi
done
for _p in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
    if [ -d "$_p" ]; then
        echo none > "$_p/trigger" 2>/dev/null || true
        echo 0 > "$_p/brightness" 2>/dev/null || true
    fi
done"""

        target_dev = "$MOCK mount -t devtmpfs -o exec,nosuid,mode=0755,size=2M devtmpfs /dev 2>/dev/null \\\n\t|| $MOCK mount -t tmpfs -o exec,nosuid,mode=0755,size=2M tmpfs /dev"
        code_dev = """$MOCK mount -t devtmpfs -o exec,nosuid,mode=0755,size=2M devtmpfs /dev 2>/dev/null \\
\t|| $MOCK mount -t tmpfs -o exec,nosuid,mode=0755,size=2M tmpfs /dev
# Video Kiosk: Immediately paint boot splash image to HDMI framebuffer
if [ -x /bin/fbdraw ] && [ -f /splash.ppm ]; then
    for _try in 1 2 3 4 5 6 7 8 9 10; do
        if [ -e /dev/fb0 ] || [ -e /dev/fb/0 ]; then
            /bin/fbdraw /splash.ppm /dev/fb0 2>/dev/null && break
        fi
        sleep 0.05
    done
fi"""

        target_modprobe = '$MOCK modprobe -a $(echo "$KOPT_modules $rootfstype" | tr \',\' \' \' ) loop squashfs simpledrm 2> /dev/null'
        code_modprobe = '$MOCK modprobe -a $(echo "$KOPT_modules $rootfstype" | tr \',\' \' \' ) loop squashfs 2> /dev/null'

        target_media = 'ebegin "Mounting boot media"'
        code_media = """# Video Kiosk: Ensure boot splash remains active before copying to RAM
[ -x /bin/fbdraw ] && [ -f /splash.ppm ] && [ -e /dev/fb0 ] && /bin/fbdraw /splash.ppm /dev/fb0 2>/dev/null || true
ebegin "Mounting boot media" """

        target2 = "exec switch_root $switch_root_opts $sysroot $chart_init \"$KOPT_init\" $KOPT_init_args"
        code2 = """# Video Kiosk: Copying image to RAM complete -> Green ACT STABLE (SOLID ON), Red PWR OFF
for _a in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
    if [ -d "$_a" ]; then
        echo none > "$_a/trigger" 2>/dev/null || true
        echo 1 > "$_a/brightness" 2>/dev/null || true
    fi
done
for _p in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
    if [ -d "$_p" ]; then
        echo none > "$_p/trigger" 2>/dev/null || true
        echo 0 > "$_p/brightness" 2>/dev/null || true
    fi
done
[ -x /bin/fbdraw ] && [ -f /splash.ppm ] && [ -e /dev/fb0 ] && /bin/fbdraw /splash.ppm /dev/fb0 2>/dev/null || true
exec switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args"""

        if target1 not in content:
            print("[-] Warning: target1 not found in init", file=sys.stderr)
            return 1
        if target_dev not in content:
            print("[-] Warning: target_dev not found in init", file=sys.stderr)
            return 1
        if target2 not in content:
            print("[-] Warning: target2 not found in init", file=sys.stderr)
            return 1

        content = content.replace(target1, code1, 1)
        content = content.replace(target_dev, code_dev, 1)
        if target_modprobe in content:
            content = content.replace(target_modprobe, code_modprobe, 1)
            print("[+] Removed simpledrm from early modprobe list in init")
        if target_media in content:
            content = content.replace(target_media, code_media, 1)
            print("[+] Injected splash refresh before mounting boot media in init")
        content = content.replace(target2, code2, 1)

        with open(init_file, "w") as f:
            f.write(content)
        os.chmod(init_file, 0o755)

        # Repack cpio with gzip
        find_proc = subprocess.Popen(["find", "."], cwd=workdir, stdout=subprocess.PIPE)
        cpio_proc = subprocess.Popen(["cpio", "-H", "newc", "-o"], cwd=workdir, stdin=find_proc.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        find_proc.stdout.close()
        with open(initramfs_path, "wb") as out_f:
            gzip_proc = subprocess.Popen(["gzip", "-9"], stdin=cpio_proc.stdout, stdout=out_f)
            cpio_proc.stdout.close()
            gzip_proc.communicate()

        print(f"[+] Successfully injected LED sequence, DRM pruning, and fbdraw splash into {initramfs_path}")
        os.unlink(backup_path)
        return 0
    finally:
        shutil.rmtree(workdir)
        if os.path.exists(backup_path):
            os.unlink(backup_path)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: patch_initramfs.py <path_to_initramfs>", file=sys.stderr)
        sys.exit(1)
    sys.exit(patch_initramfs(sys.argv[1]))
