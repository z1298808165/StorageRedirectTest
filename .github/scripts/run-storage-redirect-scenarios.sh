#!/usr/bin/env bash
set -euo pipefail

APP_ID="${APP_ID:-me.fakerqu.test.storageredirect}"
CONFIG="/data/adb/modules/storage.redirect.x/config/apps/${APP_ID}.json"
LOG_PATH="/data/adb/modules/storage.redirect.x/logs/running.log"
ACTION="me.fakerqu.test.storageredirection.TEST_CASE"
RESULT_DIR="/sdcard/Android/data/${APP_ID}/files/test_case_result"
REAL_ROOT="/storage/emulated/0"
PRIVATE_ROOT="${REAL_ROOT}/Android/data/${APP_ID}/sdcard"
TEST_FILE="srt_ci_probe.txt"
PAYLOAD="storage-redirect-test:file:ci"

adb_su() {
  local command="$1"
  (adb shell su -c "$command" || adb shell su 0 sh -c "$command" || adb shell magisk su -c "$command" || adb shell /system/bin/magisk su -c "$command" || adb shell /debug_ramdisk/magisk su -c "$command") | tr -d '\r'
}

wait_boot_completed() {
  adb wait-for-device
  adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'
}

write_config() {
  local content="$1"
  adb_su "mkdir -p /data/adb/modules/storage.redirect.x/config/apps" >/dev/null
  printf '%s' "$content" | adb shell su -c "cat > '$CONFIG'" >/dev/null
}

apply_config() {
  case "$1" in
    1)
      adb_su "rm -f '$CONFIG'" >/dev/null
      ;;
    2)
      write_config '{"users":{"0":{"enabled":true}}}'
      ;;
    3)
      write_config '{"users":{"0":{"enabled":true,"path_mappings":{"Download/SrtProbe":"Download/Test"}}}}'
      ;;
    4)
      write_config '{"users":{"0":{"enabled":true,"allowed_real_paths":["Download"],"path_mappings":{"Download/SrtProbe":"Download/Test"}}}}'
      ;;
    5)
      write_config '{"users":{"0":{"enabled":true,"allowed_real_paths":["Download"]}}}'
      ;;
    *)
      echo "unknown scenario: $1" >&2
      return 1
      ;;
  esac
}

expected_prefix() {
  case "$1" in
    1|5) echo "${REAL_ROOT}/Download/SrtProbe/" ;;
    2) echo "${PRIVATE_ROOT}/Download/SrtProbe/" ;;
    3|4) echo "${REAL_ROOT}/Download/Test/" ;;
  esac
}

clean_targets() {
  adb_su "for dir in '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download'; do find \"\$dir\" -maxdepth 1 -name '$TEST_FILE' -delete 2>/dev/null || true; done" >/dev/null
  adb_su "rm -rf '$RESULT_DIR'" >/dev/null
}

latest_result() {
  adb_su "ls -t '$RESULT_DIR'/result_*.txt 2>/dev/null | head -1" | tail -1
}

run_broadcast_test() {
  local scenario="$1"
  local target_path="${REAL_ROOT}/Download/SrtProbe/${TEST_FILE}"
  adb shell am broadcast -a "$ACTION" --es test_case file_write --es file_path "$target_path" --es payload "$PAYLOAD" --es expected_payload "$PAYLOAD" >/dev/null

  local deadline=$((SECONDS + 45)) result_file=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    result_file="$(latest_result)"
    if [ -n "$result_file" ]; then
      adb_su "cat '$result_file'" | tee "scenario-${scenario}-result.txt"
      grep -q '^PASS \[file_write\]' "scenario-${scenario}-result.txt"
      return 0
    fi
    sleep 1
  done

  echo "result_timeout scenario=${scenario}"
  return 1
}

find_written_file() {
  adb_su "for dir in '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download'; do find \"\$dir\" -maxdepth 1 -name '$TEST_FILE' -print 2>/dev/null || true; done | sort" | tail -1
}

check_file_location() {
  local scenario="$1" actual expected
  expected="$(expected_prefix "$scenario")"
  actual="$(find_written_file)"
  echo "scenario=${scenario} expected_prefix=${expected} actual=${actual}"
  if [ -z "$actual" ] || [ "${actual#"$expected"}" = "$actual" ]; then
    return 1
  fi
}

check_health() {
  adb shell "count=\$(ps -A | grep -c 'com.google.android.providers.media.module' || true); echo media_count=\$count; ps -A | grep 'com.google.android.providers.media.module' || true; pid=\$(pidof com.google.android.providers.media.module 2>/dev/null || true); echo media_pid=\$pid; if [ -n \"\$pid\" ]; then echo threads=\$(ls /proc/\$pid/task 2>/dev/null | wc -l); ps -A -o PID,RSS,NAME | grep 'com.google.android.providers.media.module' || true; fi" | tee media-health.txt
  local count
  count="$(sed -n 's/^media_count=//p' media-health.txt | tail -1)"
  [ -z "$count" ] || [ "$count" -le 10 ]
}

print_diagnostics() {
  local scenario="$1"
  echo "=== scenario ${scenario} diagnostics ==="
  adb_su "echo ===config===; cat '$CONFIG' 2>/dev/null || true; echo; echo ===files===; find '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download' -maxdepth 1 -name '$TEST_FILE' -printf '%p %s %u:%g\\n' 2>/dev/null | sort; echo ===results===; cat '$RESULT_DIR'/result_*.txt 2>/dev/null || true; echo ===module_log===; tail -120 '$LOG_PATH' 2>/dev/null || true" || true
  adb logcat -d -t 500 | grep -E 'StorageRedirectTest|SRX|FATAL EXCEPTION|AndroidRuntime|PhantomProcessRecord' | tail -120 || true
}

run_scenario() {
  scenario="$1"
  echo "===== scenario ${scenario} ====="
  apply_config "$scenario"
  adb shell am force-stop "$APP_ID" >/dev/null || true
  clean_targets
  if ! run_broadcast_test "$scenario"; then
    print_diagnostics "$scenario"
    return 1
  fi
  if ! check_file_location "$scenario"; then
    print_diagnostics "$scenario"
    return 1
  fi
}

wait_boot_completed
adb shell pm grant "$APP_ID" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
adb_su ": > '$LOG_PATH' 2>/dev/null || true" >/dev/null

fail=0
for scenario in 1 2 3 4 5; do
  if ! run_scenario "$scenario"; then
    fail=1
  fi
done
check_health || fail=1

if [ "$fail" -ne 0 ]; then
  exit 1
fi
