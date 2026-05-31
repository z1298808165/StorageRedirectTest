#!/usr/bin/env bash
set -eu

MODULE_ZIP="$(find core -maxdepth 1 -name '*x86_64.zip' -print -quit)"
if [ -z "$MODULE_ZIP" ]; then
  echo "No Storage Redirect X x86_64 module zip was downloaded."
  exit 1
fi

ROOT_AVD_DIR="$RUNNER_TEMP/rootAVD"
rm -rf "$ROOT_AVD_DIR"
mkdir -p "$ROOT_AVD_DIR"
mkdir -p "$ROOT_AVD_DIR/Apps"
cp .github/vendor/rootAVD/rootAVD.sh "$ROOT_AVD_DIR/rootAVD.sh"
cp .github/vendor/rootAVD/rootAVD.bat "$ROOT_AVD_DIR/rootAVD.bat"
chmod +x "$ROOT_AVD_DIR/rootAVD.sh"

MAGISK_JSON="${MAGISK_JSON:-https://raw.githubusercontent.com/topjohnwu/magisk-files/master/stable.json}"
MAGISK_URL="$(python3 - <<PY
import json
import urllib.request

with urllib.request.urlopen("$MAGISK_JSON", timeout=30) as response:
    print(json.load(response)["magisk"]["link"])
PY
)"
curl -fsSL "$MAGISK_URL" -o "$ROOT_AVD_DIR/Magisk.zip"

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
  if [ -n "${EMULATOR_LOG:-}" ] && [ -f "$EMULATOR_LOG" ]; then
    echo "=== emulator log tail ==="
    tail -200 "$EMULATOR_LOG" || true
  fi
  return 1
}

wait_for_emulator_shutdown() {
  local timeout_seconds="${1:-60}"
  local deadline=$((SECONDS + timeout_seconds))

  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! adb devices | grep -q '^emulator-'; then
      return 0
    fi
    adb emu kill >/dev/null 2>&1 || true
    sleep 2
  done

  echo "Timed out waiting for previous emulator shutdown."
  adb devices -l || true
  return 1
}

start_emulator() {
  local avd_name="${AVD_NAME:-test}"
  local emulator_port="${EMULATOR_PORT:-5554}"
  EMULATOR_LOG="${RUNNER_TEMP:-/tmp}/rooted-emulator.log"

  nohup "$ANDROID_HOME/emulator/emulator" -port "$emulator_port" -avd "$avd_name" -no-window -gpu swiftshader_indirect -no-snapshot-load -no-snapshot-save -noaudio -no-boot-anim >"$EMULATOR_LOG" 2>&1 &
  sleep 5
  if [ -f "$EMULATOR_LOG" ]; then
    tail -80 "$EMULATOR_LOG" || true
  fi
}

adb_su() {
  local command="$1"
  adb shell su -c "$command" || adb shell magisk su -c "$command" || adb shell /system/bin/magisk su -c "$command"
}

ROOTAVD_NONINTERACTIVE=1 ROOTAVD_MAGISK_CHOICE=1 "$ROOT_AVD_DIR/rootAVD.sh" "$RAMDISK_REL"
wait_for_emulator_shutdown 90
adb kill-server >/dev/null 2>&1 || true
start_emulator
wait_for_boot 300

echo "Waiting for Magisk to initialize..."
sleep 10

magisk_ready_attempts="${MAGISK_READY_ATTEMPTS:-18}"
for i in $(seq 1 "$magisk_ready_attempts"); do
  echo "Attempt $i/$magisk_ready_attempts: Checking Magisk root availability..."
  if adb_su 'id' >/dev/null 2>&1; then
    echo "Magisk root is available."
    break
  fi
  if [ "$i" -eq "$magisk_ready_attempts" ]; then
    echo "Magisk root is not available after rootAVD."
    adb shell getprop | grep -i magisk || true
    adb shell ls -la /system/bin/su || true
    adb shell ls -la /system/bin/magisk || true
    adb shell ls -la /sbin || true
    exit 1
  fi
  echo "Magisk not ready yet, waiting 10s..."
  sleep 10
done

adb_su 'magisk --sqlite "REPLACE INTO settings (key,value) VALUES('"'"'zygisk'"'"',1);"'
adb shell mkdir -p /sdcard/Download
adb push "$MODULE_ZIP" /sdcard/Download/storage-redirect-x.zip
adb_su 'magisk --install-module /sdcard/Download/storage-redirect-x.zip'
adb reboot
wait_for_boot 300

if ! adb_su 'magisk --sqlite "SELECT value FROM settings WHERE key='"'"'zygisk'"'"';"' | grep -q 1; then
  echo "Zygisk is not enabled after reboot."
  exit 1
fi

adb_su 'ls /data/adb/modules | grep -i "storage"' >/dev/null
