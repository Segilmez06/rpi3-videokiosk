#!/usr/bin/env python3
"""
Patch Alpine initramfs /init script to inject hardware LED state machine & early boot splash:
1. Red PWR LED OFF, Green ACT starts blinking with 100ms delay
2. Display boot splash screen immediately on HDMI framebuffer (/dev/fb0)
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

    workdir = tempfile.mkdtemp(prefix="initramfs_patch_")
    backup_path = initramfs_path + ".orig"
    shutil.copy2(initramfs_path, backup_path)

    try:
        # Unpack cpio
        p1 = subprocess.Popen(["gzip", "-dc", backup_path], stdout=subprocess.PIPE)
        subprocess.check_call(["cpio", "-idm"], cwd=workdir, stdin=p1.stdout, stderr=subprocess.DEVNULL)
        p1.wait()

        # Convert boot splash image to Netpbm PPM for busybox fbsplash
        if os.path.isfile(boot_png):
            print(f"[*] Injecting early boot splash from {boot_png} into initramfs...")
            im = Image.open(boot_png).convert("RGB")
            ppm_path = os.path.join(workdir, "splash.ppm")
            im.save(ppm_path, format="PPM")
            print(f"[+] Created {ppm_path} ({os.path.getsize(ppm_path)} bytes)")

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
if [ -f /splash.ppm ]; then
    for _fb in /dev/fb0 /dev/fb/0; do
        if [ -e "$_fb" ]; then
            fbsplash -s /splash.ppm -c -d "$_fb" 2>/dev/null || true
            break
        fi
    done
fi"""

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

        print(f"[+] Successfully injected LED sequence and boot splash into {initramfs_path}")
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
