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

RAMDISK="$ANDROID_HOME/system-images/android-${ANDROID_API_LEVEL}/${ANDROID_TARGET}/${ANDROID_ARCH}/ramdisk.img"
if [ ! -f "$RAMDISK" ]; then
  "$ROOT_AVD_DIR/rootAVD.sh" ListAllAVDs
  echo "No ramdisk.img found at $RAMDISK."
  exit 1
fi

printf '\n' | "$ROOT_AVD_DIR/rootAVD.sh" "$RAMDISK"
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'

if ! adb shell su -c 'id' >/dev/null 2>&1; then
  echo "Magisk root is not available after rootAVD."
  exit 1
fi

adb shell su -c 'magisk --sqlite "REPLACE INTO settings (key,value) VALUES('"'"'zygisk'"'"',1);"'
adb shell mkdir -p /sdcard/Download
adb push "$MODULE_ZIP" /sdcard/Download/storage-redirect-x.zip
adb shell su -c 'magisk --install-module /sdcard/Download/storage-redirect-x.zip'
adb reboot
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'

if ! adb shell su -c 'magisk --sqlite "SELECT value FROM settings WHERE key='"'"'zygisk'"'"';"' | grep -q 1; then
  echo "Zygisk is not enabled after reboot."
  exit 1
fi

adb shell su -c 'ls /data/adb/modules | grep -i "storage"' >/dev/null
