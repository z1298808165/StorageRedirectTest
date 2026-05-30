#!/usr/bin/env bash
set -eu

MODULE_ZIP="$(find core -maxdepth 1 -name '*x86_64.zip' -print -quit)"
if [ -z "$MODULE_ZIP" ]; then
  echo "No Storage Redirect X x86_64 module zip was downloaded."
  exit 1
fi

ROOT_AVD_DIR="$RUNNER_TEMP/rootAVD"
if [ ! -d "$ROOT_AVD_DIR" ]; then
  git clone --depth 1 https://github.com/newbit1/rootAVD.git "$ROOT_AVD_DIR"
fi
chmod +x "$ROOT_AVD_DIR/rootAVD.sh"

RAMDISK_REL="system-images/android-${ANDROID_API_LEVEL}/${ANDROID_TARGET}/${ANDROID_ARCH}/ramdisk.img"
RAMDISK="$ANDROID_HOME/$RAMDISK_REL"
if [ ! -f "$RAMDISK" ]; then
  echo "No ramdisk.img found at expected Android SDK system image path."
  exit 1
fi

wait_for_boot() {
  local timeout_seconds="${1:-300}"
  local deadline=$((SECONDS + timeout_seconds))
  local boot_completed=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    boot_completed="$(timeout 10s adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [ "$boot_completed" = "1" ]; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for emulator boot."
  adb devices -l || true
  return 1
}

start_emulator() {
  local avd_name="${AVD_NAME:-test}"
  local emulator_port="${EMULATOR_PORT:-5554}"
  local emulator_log="${RUNNER_TEMP:-/tmp}/rooted-emulator.log"

  nohup "$ANDROID_HOME/emulator/emulator" -port "$emulator_port" -avd "$avd_name" -no-window -gpu swiftshader_indirect -no-snapshot -noaudio -no-boot-anim >"$emulator_log" 2>&1 &
}

printf '\n' | "$ROOT_AVD_DIR/rootAVD.sh" "$RAMDISK_REL"
adb kill-server >/dev/null 2>&1 || true
start_emulator
wait_for_boot 300

# 等待 Magisk 初始化
echo "Waiting for Magisk to initialize..."
sleep 10

# 检查 Magisk 是否可用，最多重试 6 次
for i in {1..6}; do
  echo "Attempt $i: Checking Magisk root availability..."
  if adb shell su -c 'id' >/dev/null 2>&1; then
    echo "Magisk root is available."
    break
  fi
  if [ "$i" -eq 6 ]; then
    echo "Magisk root is not available after rootAVD."
    adb shell getprop | grep -i magisk || true
    adb shell ls -la /system/bin/su || true
    adb shell ls -la /sbin || true
    exit 1
  fi
  echo "Magisk not ready yet, waiting 10s..."
  sleep 10
done

adb shell su -c 'magisk --sqlite "REPLACE INTO settings (key,value) VALUES('"'"'zygisk'"'"',1);"'
adb shell mkdir -p /sdcard/Download
adb push "$MODULE_ZIP" /sdcard/Download/storage-redirect-x.zip
adb shell su -c 'magisk --install-module /sdcard/Download/storage-redirect-x.zip'
adb reboot
wait_for_boot 300

if ! adb shell su -c 'magisk --sqlite "SELECT value FROM settings WHERE key='"'"'zygisk'"'"';"' | grep -q 1; then
  echo "Zygisk is not enabled after reboot."
  exit 1
fi

adb shell su -c 'ls /data/adb/modules | grep -i "storage"' >/dev/null
