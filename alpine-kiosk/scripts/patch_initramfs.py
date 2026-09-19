#!/usr/bin/env python3
"""
Patch Alpine initramfs /init script to inject hardware LED state machine:
1. Red PWR LED blinks with 100ms delay while copying/unpacking OS image to RAM
2. Once unpacking is complete, Red turns OFF and Green ACT starts SOLID ON
"""
import sys
import os
import subprocess
import tempfile
import shutil

def patch_initramfs(initramfs_path):
    if not os.path.isfile(initramfs_path):
        print(f"[-] Error: initramfs file not found: {initramfs_path}", file=sys.stderr)
        return 1

    workdir = tempfile.mkdtemp(prefix="initramfs_patch_")
    backup_path = initramfs_path + ".orig"
    shutil.copy2(initramfs_path, backup_path)

    try:
        # Unpack cpio
        p1 = subprocess.Popen(["gzip", "-dc", backup_path], stdout=subprocess.PIPE)
        subprocess.check_call(["cpio", "-idm"], cwd=workdir, stdin=p1.stdout, stderr=subprocess.DEVNULL)
        p1.wait()

        init_file = os.path.join(workdir, "init")
        with open(init_file, "r") as f:
            content = f.read()

        target1 = "$MOCK mount -t sysfs -o noexec,nosuid,nodev sysfs /sys"
        code1 = """$MOCK mount -t sysfs -o noexec,nosuid,nodev sysfs /sys
# Video Kiosk: Red LED blinking 100ms delay while copying image to RAM
for _p in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
    if [ -d "$_p" ]; then
        echo timer > "$_p/trigger" 2>/dev/null || true
        echo 100 > "$_p/delay_on" 2>/dev/null || true
        echo 100 > "$_p/delay_off" 2>/dev/null || true
    fi
done
for _a in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
    if [ -d "$_a" ]; then
        echo none > "$_a/trigger" 2>/dev/null || true
        echo 0 > "$_a/brightness" 2>/dev/null || true
    fi
done"""

        target2 = "exec switch_root $switch_root_opts $sysroot $chart_init \"$KOPT_init\" $KOPT_init_args"
        code2 = """# Video Kiosk: Copying image to RAM complete -> Red OFF, Green SOLID ON
for _p in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
    if [ -d "$_p" ]; then
        echo none > "$_p/trigger" 2>/dev/null || true
        echo 0 > "$_p/brightness" 2>/dev/null || true
    fi
done
for _a in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
    if [ -d "$_a" ]; then
        echo none > "$_a/trigger" 2>/dev/null || true
        echo 1 > "$_a/brightness" 2>/dev/null || true
    fi
done
exec switch_root $switch_root_opts $sysroot $chart_init "$KOPT_init" $KOPT_init_args"""

        if target1 not in content:
            print("[-] Warning: target1 not found in init", file=sys.stderr)
            return 1
        if target2 not in content:
            print("[-] Warning: target2 not found in init", file=sys.stderr)
            return 1

        content = content.replace(target1, code1, 1)
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

        print(f"[+] Successfully injected LED sequence into {initramfs_path}")
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
