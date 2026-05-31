#!/usr/bin/env bash
set -euo pipefail

APP_ID="${APP_ID:-me.fakerqu.test.storageredirect}"
CONFIG="/data/adb/modules/storage.redirect.x/config/apps/${APP_ID}.json"
LOG_PATH="/data/adb/modules/storage.redirect.x/logs/running.log"
ACTION="me.fakerqu.test.storageredirection.TEST_CASE"
RESULT_DIR="/sdcard/Android/data/${APP_ID}/files/test_case_result"
INTERNAL_RESULT_DIR="/data/data/${APP_ID}/files/test_case_result"
REAL_ROOT="/storage/emulated/0"
PRIVATE_ROOT="${REAL_ROOT}/Android/data/${APP_ID}/sdcard"
TEST_FILE="srt_ci_probe.txt"
PAYLOAD="storage-redirect-test:file:ci"

adb_root() {
  local command="PATH=/debug_ramdisk:/sbin:/data/adb/magisk:\$PATH; $1"
  local quoted
  quoted="$(printf '%s' "$command" | sed "s/'/'\\\\''/g")"
  adb shell "su 0 sh -c '$quoted'" || adb shell "su -c '$quoted'"
}

adb_su() {
  local command="PATH=/debug_ramdisk:/sbin:/data/adb/magisk:\$PATH; $1"
  (adb_root "$1" || adb shell magisk su -c "$command" || adb shell /system/bin/magisk su -c "$command" || adb shell /debug_ramdisk/magisk su -c "$command") | tr -d '\r'
}

wait_boot_completed() {
  adb wait-for-device
  adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'
}

write_config() {
  local content="$1"
  adb_su "mkdir -p /data/adb/modules/storage.redirect.x/config/apps" >/dev/null
  printf '%s' "$content" | adb_root "cat > '$CONFIG'" >/dev/null
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
    3) echo "${PRIVATE_ROOT}/Download/Test/" ;;
    4) echo "${REAL_ROOT}/Download/Test/" ;;
  esac
}

scenario_title() {
  case "$1" in
    1) echo "未启用应用配置，验证默认真实路径写入" ;;
    2) echo "启用重定向，验证写入应用私有空间" ;;
    3) echo "启用路径映射，验证 SrtProbe 映射到 Test" ;;
    4) echo "路径映射叠加真实路径放行，验证映射优先级" ;;
    5) echo "放行真实 Download，验证保持原路径写入" ;;
  esac
}

clean_targets() {
  adb_su "for dir in '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download'; do find \"\$dir\" -maxdepth 1 -name '$TEST_FILE' -delete 2>/dev/null || true; done" >/dev/null
  clean_results
  adb_su "mkdir -p '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download'; chmod 777 '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download' 2>/dev/null || true" >/dev/null
}

clean_results() {
  adb_su "rm -rf '$RESULT_DIR' '$INTERNAL_RESULT_DIR'" >/dev/null
}

latest_result() {
  adb_su "ls -t '$RESULT_DIR'/result_*.txt '$INTERNAL_RESULT_DIR'/result_*.txt 2>/dev/null | head -1" | tail -1
}

wait_storage_ready() {
  local label="$1"
  local timeout_seconds="${2:-90}"
  local deadline=$((SECONDS + timeout_seconds))

  while [ "$SECONDS" -lt "$deadline" ]; do
    if adb shell "sm list-volumes all 2>/dev/null | grep -q 'emulated;0 mounted' && test -d '$REAL_ROOT'" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for emulated storage: ${label}"
  print_storage_state "${label}-storage-timeout"
  return 1
}

print_storage_state() {
  local label="$1"
  echo "=== storage state: ${label} ==="
  adb shell "date; getprop ro.build.version.sdk; getprop ro.build.version.release; getprop sys.boot_completed; getprop dev.bootcomplete; getprop init.svc.sdcard; getprop init.svc.media; sm list-volumes all 2>/dev/null || true; df -h /storage/emulated/0 /sdcard 2>&1 || true; ls -ld /storage /storage/emulated /storage/emulated/0 /sdcard 2>&1 || true; mount | grep -E ' /storage|/mnt/runtime|/mnt/user|sdcard|fuse|srx' || true" || true
  adb_su "id; ls -ld /mnt/user/0 /mnt/user/0/emulated /mnt/user/0/emulated/0 /mnt/runtime/default/emulated/0 2>&1 || true; cat /proc/mounts | grep -E ' /storage|/mnt/runtime|/mnt/user|sdcard|fuse|srx' || true" || true
}

run_service_case() {
  local scenario="$1"
  local label="$2"
  local test_case="$3"
  local pass_pattern="$4"
  shift 4
  local output_file="scenario-${scenario}-${label}-result.txt"

  clean_results
  adb shell am start-foreground-service -n "${APP_ID}/.TestService" -a "$ACTION" --es test_case "$test_case" "$@" >/dev/null

  local deadline=$((SECONDS + 45)) result_file=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    result_file="$(latest_result)"
    if [ -n "$result_file" ]; then
      adb_su "cat '$result_file'" | tee "$output_file"
      cat "$output_file" >>"scenario-${scenario}-result.txt"
      grep -q "$pass_pattern" "$output_file"
      return 0
    fi
    sleep 1
  done

  echo "result_timeout scenario=${scenario} test_case=${test_case}"
  return 1
}

run_write_test() {
  local scenario="$1"
  local target_path="${REAL_ROOT}/Download/SrtProbe/${TEST_FILE}"
  run_service_case "$scenario" "write" "file_write" '^PASS \[file_write\]' --es file_path "$target_path" --es payload "$PAYLOAD" --es expected_payload "$PAYLOAD"
}

check_app_view() {
  local scenario="$1"
  local logical_dir="${REAL_ROOT}/Download/SrtProbe"
  run_service_case "$scenario" "app-view" "file_list_dir" '^PASS \[file_list_dir\]' --es file_dir "$logical_dir"
  echo "app_view scenario=${scenario} logical_dir=${logical_dir} expected_entry=${TEST_FILE}"
  grep -q "entries=.*${TEST_FILE}" "scenario-${scenario}-app-view-result.txt"
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
  print_storage_state "scenario-${scenario}-failure"
  adb_su "echo ===config===; cat '$CONFIG' 2>/dev/null || true; echo; echo ===module_state===; ls -la /data/adb/modules/storage.redirect.x 2>/dev/null || true; echo; mount | grep -E 'srx|storage.redirect' || true; echo; echo ===logs===; for log in running.log app_status.log file_monitor.log media_provider_state.log; do echo ---\$log---; tail -80 /data/adb/modules/storage.redirect.x/logs/\$log 2>/dev/null || true; done; echo ===files===; find '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download' -maxdepth 1 -name '$TEST_FILE' -printf '%p %s %u:%g\\n' 2>/dev/null | sort; echo ===results===; cat '$RESULT_DIR'/result_*.txt '$INTERNAL_RESULT_DIR'/result_*.txt 2>/dev/null || true" || true
  adb logcat -d -t 1200 | grep -Ei 'StorageRedirectTest|srx|StorageRedirect|Magisk|zygisk|FATAL EXCEPTION|AndroidRuntime|PhantomProcessRecord|ExternalStorage|StorageManager|MediaProvider|vold|sdcard|fuse|Transport endpoint' | tail -260 || true
}

run_scenario() {
  scenario="$1"
  : >"scenario-${scenario}-result.txt"
  echo "step 1/7: 应用场景配置"
  apply_config "$scenario"
  echo "step 2/7: 重启测试应用"
  adb shell am force-stop "$APP_ID" >/dev/null || true
  adb shell am start -W -n "${APP_ID}/.MainActivity" >/dev/null
  sleep 1
  echo "step 3/7: 等待共享存储可用"
  wait_storage_ready "scenario-${scenario}"
  echo "step 4/7: 清理测试目标"
  clean_targets
  echo "step 5/7: 从应用进程写入文件"
  if ! run_write_test "$scenario"; then
    return 1
  fi
  echo "step 6/7: 校验应用视角可见文件"
  if ! check_app_view "$scenario"; then
    return 1
  fi
  echo "step 7/7: 校验 root 视角物理落点"
  if ! check_file_location "$scenario"; then
    return 1
  fi
}

wait_boot_completed
adb shell pm grant "$APP_ID" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.WRITE_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_AUDIO >/dev/null 2>&1 || true
wait_storage_ready "initial"
adb_su ": > '$LOG_PATH' 2>/dev/null || true" >/dev/null

fail=0
export APP_ID CONFIG LOG_PATH ACTION RESULT_DIR INTERNAL_RESULT_DIR REAL_ROOT PRIVATE_ROOT TEST_FILE PAYLOAD
export -f adb_root adb_su wait_boot_completed write_config apply_config expected_prefix scenario_title clean_targets clean_results latest_result wait_storage_ready print_storage_state run_service_case run_write_test check_app_view find_written_file check_file_location check_health print_diagnostics run_scenario

for scenario in 1 2 3 4 5; do
  echo "::group::scenario ${scenario}: $(scenario_title "$scenario")"
  if ! timeout --foreground 240s bash -c 'run_scenario "$1"' _ "$scenario"; then
    echo "scenario ${scenario}: failed or timed out"
    timeout --foreground 90s bash -c 'print_diagnostics "$1"' _ "$scenario" || true
    fail=1
  fi
  echo "::endgroup::"
done
check_health || fail=1

if [ "$fail" -ne 0 ]; then
  exit 1
fi
