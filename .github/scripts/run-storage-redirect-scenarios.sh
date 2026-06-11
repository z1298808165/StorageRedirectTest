#!/usr/bin/env bash
set -euo pipefail

APP_ID="${APP_ID:-me.fakerqu.test.storageredirect}"
CONFIG="/data/adb/modules/storage.redirect.x/config/apps/${APP_ID}.json"
LOG_PATH="/data/adb/modules/storage.redirect.x/logs/running.log"
ACTION="me.fakerqu.test.storageredirection.TEST_CASE"
RESULT_DIR="/sdcard/Android/data/${APP_ID}/files/test_case_result"
INTERNAL_RESULT_DIR="/data/data/${APP_ID}/files/test_case_result"
REAL_ROOT="/storage/emulated/0"
BACKEND_ROOT="/data/media/0"
PRIVATE_ROOT="${REAL_ROOT}/Android/data/${APP_ID}/sdcard"
BACKEND_PRIVATE_ROOT="${BACKEND_ROOT}/Android/data/${APP_ID}/sdcard"
SANDBOX_RESULT_DIR="${BACKEND_PRIVATE_ROOT}/Android/data/${APP_ID}/files/test_case_result"
TEST_FILE="srt_ci_probe.txt"
READ_ONLY_FILE="srt_read_only_seed.txt"
ALLOW_KEEP_FILE="keep.txt"
ALLOW_PART_FILE="srt_ci_probe.part"
PAYLOAD="storage-redirect-test:file:ci"
READ_ONLY_PAYLOAD="storage-redirect-test:file:readonly"

READ_ONLY_ROOT="${REAL_ROOT}/Download/SrtReadOnly"
MAPPED_READ_ONLY_REQUEST="${REAL_ROOT}/Download/SrtMapRO"
MAPPED_READ_ONLY_TARGET="${REAL_ROOT}/Pictures/SrtLocked"
ALLOW_ROOT="${REAL_ROOT}/Download/SrtAllow"
PRIVATE_ALLOW_ROOT="${PRIVATE_ROOT}/Download/SrtAllow"

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
    6)
      write_config '{"users":{"0":{"enabled":true,"mapping_mode_only":true,"path_mappings":{"Download/SrtOther":"Download/SrtOtherMapped"}}}}'
      ;;
    7)
      write_config '{"users":{"0":{"enabled":true,"mapping_mode_only":true,"path_mappings":{"Download/SrtProbe":"Download/SrtMapOnlyMapped"}}}}'
      ;;
    8)
      write_config '{"users":{"0":{"enabled":true,"mapping_mode_only":true,"sandboxed_paths":[".xlDownload"]}}}'
      ;;
    9)
      write_config '{"users":{"0":{"enabled":true,"read_only_paths":["Download/SrtReadOnly"]}}}'
      ;;
    10)
      write_config '{"users":{"0":{"enabled":true,"path_mappings":{"Download/SrtMapRO":"Pictures/SrtLocked"},"read_only_paths":["Pictures/SrtLocked"]}}}'
      ;;
    11)
      write_config '{"users":{"0":{"enabled":true,"allowed_real_paths":["Download/SrtAllow","!Download/SrtAllow/tmp","!Download/SrtAllow/*.part"]}}}'
      ;;
    *)
      echo "unknown scenario: $1" >&2
      return 1
      ;;
  esac
}

target_path() {
  case "$1" in
    8) echo "${REAL_ROOT}/.xldownload/${TEST_FILE}" ;;
    *) echo "${REAL_ROOT}/Download/SrtProbe/${TEST_FILE}" ;;
  esac
}

logical_dir() {
  case "$1" in
    8) echo "${REAL_ROOT}/.xldownload" ;;
    *) echo "${REAL_ROOT}/Download/SrtProbe" ;;
  esac
}

expected_path() {
  case "$1" in
    1|5|6) echo "${REAL_ROOT}/Download/SrtProbe/${TEST_FILE}" ;;
    2) echo "${PRIVATE_ROOT}/Download/SrtProbe/${TEST_FILE}" ;;
    3|4) echo "${REAL_ROOT}/Download/Test/${TEST_FILE}" ;;
    7) echo "${REAL_ROOT}/Download/SrtMapOnlyMapped/${TEST_FILE}" ;;
    8) echo "${PRIVATE_ROOT}/.xldownload/${TEST_FILE}" ;;
    *) return 1 ;;
  esac
}

scenario_title() {
  case "$1" in
    1) echo "未启用应用配置，验证默认真实路径写入" ;;
    2) echo "启用重定向，验证写入应用私有空间" ;;
    3) echo "启用路径映射，验证 SrtProbe 写入真实 Test" ;;
    4) echo "路径映射叠加真实路径放行，验证映射优先级" ;;
    5) echo "放行真实 Download，验证保持原路径写入" ;;
    6) echo "仅映射模式，未命中映射路径应保持真实路径写入" ;;
    7) echo "仅映射模式，命中映射路径应写入映射目标" ;;
    8) echo "仅映射模式叠加 sandboxed_paths，验证 .xlDownload 别名沙盒化" ;;
    9) echo "read_only_paths 允许读取但拒绝写入、删除、mkdir、rename" ;;
    10) echo "映射目标为只读路径时，映射请求写入应被拒绝" ;;
    11) echo "allowed_real_paths 内联排除与通配符排除规则" ;;
  esac
}

clean_targets() {
  clean_results
  adb_su "rm -rf '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/SrtOther' '${REAL_ROOT}/Download/SrtOtherMapped' '${REAL_ROOT}/Download/SrtMapOnlyMapped' '${REAL_ROOT}/Download/SrtReadOnly' '${REAL_ROOT}/Download/SrtMapRO' '${REAL_ROOT}/Download/SrtAllow' '${REAL_ROOT}/Pictures/SrtLocked' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download/SrtOther' '${PRIVATE_ROOT}/Download/SrtOtherMapped' '${PRIVATE_ROOT}/Download/SrtMapOnlyMapped' '${PRIVATE_ROOT}/Download/SrtReadOnly' '${PRIVATE_ROOT}/Download/SrtMapRO' '${PRIVATE_ROOT}/Download/SrtAllow' '${PRIVATE_ROOT}/Pictures/SrtLocked'; find '${REAL_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/Test' '${REAL_ROOT}/.xldownload' '${REAL_ROOT}/.xlDownload' '${PRIVATE_ROOT}/.xldownload' '${PRIVATE_ROOT}/.xlDownload' -maxdepth 1 -name '$TEST_FILE' -delete 2>/dev/null || true" >/dev/null
  adb_su "mkdir -p '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${REAL_ROOT}/Download/SrtMapOnlyMapped' '${REAL_ROOT}/Download/SrtReadOnly' '${REAL_ROOT}/Download/SrtMapRO' '${REAL_ROOT}/Download/SrtAllow/tmp' '${REAL_ROOT}/Pictures/SrtLocked' '${REAL_ROOT}/.xldownload' '${REAL_ROOT}/.xlDownload' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtMapOnlyMapped' '${PRIVATE_ROOT}/Download/SrtReadOnly' '${PRIVATE_ROOT}/Download/SrtMapRO' '${PRIVATE_ROOT}/Download/SrtAllow/tmp' '${PRIVATE_ROOT}/Pictures/SrtLocked' '${PRIVATE_ROOT}/.xldownload' '${PRIVATE_ROOT}/.xlDownload'; chmod -R 777 '${REAL_ROOT}/Download/SrtProbe' '${REAL_ROOT}/Download/Test' '${REAL_ROOT}/Download/SrtMapOnlyMapped' '${REAL_ROOT}/Download/SrtReadOnly' '${REAL_ROOT}/Download/SrtMapRO' '${REAL_ROOT}/Download/SrtAllow' '${REAL_ROOT}/Pictures/SrtLocked' '${PRIVATE_ROOT}/Download/SrtProbe' '${PRIVATE_ROOT}/Download/Test' '${PRIVATE_ROOT}/Download/SrtMapOnlyMapped' '${PRIVATE_ROOT}/Download/SrtReadOnly' '${PRIVATE_ROOT}/Download/SrtMapRO' '${PRIVATE_ROOT}/Download/SrtAllow' '${PRIVATE_ROOT}/Pictures/SrtLocked' 2>/dev/null || true; chmod 777 '${REAL_ROOT}/.xldownload' '${REAL_ROOT}/.xlDownload' '${PRIVATE_ROOT}/.xldownload' '${PRIVATE_ROOT}/.xlDownload' 2>/dev/null || true" >/dev/null
}

clean_results() {
  adb_su "rm -rf '$RESULT_DIR' '$INTERNAL_RESULT_DIR' '$SANDBOX_RESULT_DIR'" >/dev/null
}

latest_result() {
  adb_su "ls -t '$RESULT_DIR'/result_*.txt '$INTERNAL_RESULT_DIR'/result_*.txt '$SANDBOX_RESULT_DIR'/result_*.txt 2>/dev/null | head -1" | tail -1
}

prepare_service_case() {
  local label="$1"
  adb shell am force-stop "$APP_ID" >/dev/null || true
  sleep 0.5
  adb shell am start -W -n "${APP_ID}/.MainActivity" >/dev/null
  sleep 1
  wait_storage_ready "$label" 30 >/dev/null
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

  prepare_service_case "scenario-${scenario}-${label}"
  clean_results
  adb shell am start-foreground-service -n "${APP_ID}/.TestService" -a "$ACTION" --es test_case "$test_case" "$@" >/dev/null

  local deadline=$((SECONDS + 45)) result_file=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    result_file="$(latest_result)"
    if [ -n "$result_file" ]; then
      adb_su "cat '$result_file'" | tee "$output_file"
      cat "$output_file" >>"scenario-${scenario}-result.txt"
      if [ -z "$pass_pattern" ]; then
        return 0
      fi
      if grep -q "$pass_pattern" "$output_file"; then
        return 0
      fi
      return 1
    fi
    sleep 1
  done

  echo "result_timeout scenario=${scenario} test_case=${test_case}"
  adb shell am force-stop "$APP_ID" >/dev/null || true
  return 1
}

run_write_case() {
  local scenario="$1"
  local label="$2"
  local path="$3"
  local payload="${4:-$PAYLOAD}"
  run_service_case "$scenario" "$label" "file_write" '^PASS \[file_write\]' --es file_path "$path" --es payload "$payload" --es expected_payload "$payload"
}

run_create_case() {
  local scenario="$1"
  local label="$2"
  local path="$3"
  run_service_case "$scenario" "$label" "file_create" '^PASS \[file_create\]' --es file_path "$path"
}

run_write_test() {
  local scenario="$1"
  local path
  path="$(target_path "$scenario")"
  for attempt in 1 2; do
    if run_write_case "$scenario" "write" "$path" "$PAYLOAD"; then
      return 0
    fi
    if [ "$attempt" -eq 2 ]; then
      return 1
    fi
    echo "write_retry scenario=${scenario} attempt=${attempt}"
    adb shell am force-stop "$APP_ID" >/dev/null || true
    adb shell am start -W -n "${APP_ID}/.MainActivity" >/dev/null
    wait_storage_ready "scenario-${scenario}-write-retry"
    clean_targets
  done
}

check_app_view() {
  local scenario="$1"
  local dir
  dir="$(logical_dir "$scenario")"
  expect_app_entry "$scenario" "app-view" "$dir"

  local mapped_real_dir="${REAL_ROOT}/Download/Test"
  case "$scenario" in
    3)
      expect_no_app_entry "$scenario" "app-mapped-real-view" "$mapped_real_dir"
      ;;
    4)
      expect_app_entry "$scenario" "app-mapped-real-view" "$mapped_real_dir"
      ;;
  esac
}

expect_app_entry() {
  local scenario="$1"
  local label="$2"
  local dir="$3"

  for attempt in 1 2 3 4 5; do
    if run_service_case "$scenario" "$label" "file_list_dir" '^PASS \[file_list_dir\]' --es file_dir "$dir" &&
      grep -q "entries=.*${TEST_FILE}" "scenario-${scenario}-${label}-result.txt"; then
      echo "app_view scenario=${scenario} logical_dir=${dir} expected_entry=${TEST_FILE}"
      return 0
    fi
    echo "app_view_retry scenario=${scenario} logical_dir=${dir} attempt=${attempt}"
    sleep 1
  done

  return 1
}

expect_no_app_entry() {
  local scenario="$1"
  local label="$2"
  local dir="$3"

  for attempt in 1 2 3; do
    run_service_case "$scenario" "$label" "file_list_dir" "" --es file_dir "$dir"
    if grep -q "entries=.*${TEST_FILE}" "scenario-${scenario}-${label}-result.txt"; then
      echo "app_view scenario=${scenario} logical_dir=${dir} forbidden_entry_visible=${TEST_FILE}"
      return 1
    fi
    sleep 1
  done

  echo "app_view scenario=${scenario} logical_dir=${dir} forbidden_entry=${TEST_FILE}"
}

find_written_file() {
  adb_su "for dir in '${REAL_ROOT}/Download' '${REAL_ROOT}/Pictures' '${REAL_ROOT}/.xldownload' '${REAL_ROOT}/.xlDownload' '${PRIVATE_ROOT}/Download' '${PRIVATE_ROOT}/Pictures' '${PRIVATE_ROOT}/.xldownload' '${PRIVATE_ROOT}/.xlDownload'; do find \"\$dir\" -maxdepth 5 \\( -name '$TEST_FILE' -o -name '$READ_ONLY_FILE' -o -name '$ALLOW_KEEP_FILE' -o -name '$ALLOW_PART_FILE' \\) -print 2>/dev/null || true; done | sort"
}

check_file_exists() {
  local label="$1"
  local path="$2"
  if adb_su "test -f '$path'"; then
    echo "file_exists label=${label} path=${path}"
    return 0
  fi
  echo "file_missing label=${label} path=${path}"
  return 1
}

check_file_missing() {
  local label="$1"
  local path="$2"
  if adb_su "test ! -e '$path'"; then
    echo "file_absent label=${label} path=${path}"
    return 0
  fi
  echo "file_unexpected label=${label} path=${path}"
  adb_su "ls -ld '$path' 2>/dev/null || true" || true
  return 1
}

check_file_location() {
  local scenario="$1" actual expected
  expected="$(expected_path "$scenario")"
  actual="$(find_written_file | tr '\n' ';')"
  echo "scenario=${scenario} expected_path=${expected} actual=${actual}"
  check_file_exists "scenario-${scenario}-expected" "$expected"
}

seed_read_only_targets() {
  adb_su "mkdir -p '$READ_ONLY_ROOT'; rm -f '$READ_ONLY_ROOT/write_denied.txt' '$READ_ONLY_ROOT/renamed.txt'; rm -rf '$READ_ONLY_ROOT/newdir'; printf '%s' '$READ_ONLY_PAYLOAD' > '$READ_ONLY_ROOT/$READ_ONLY_FILE'; chmod -R 777 '$READ_ONLY_ROOT' 2>/dev/null || true" >/dev/null
}

check_read_only_artifacts() {
  check_file_exists "read-only-seed" "$READ_ONLY_ROOT/$READ_ONLY_FILE" &&
    check_file_missing "read-only-write" "$READ_ONLY_ROOT/write_denied.txt" &&
    check_file_missing "read-only-mkdir" "$READ_ONLY_ROOT/newdir" &&
    check_file_missing "read-only-rename-target" "$READ_ONLY_ROOT/renamed.txt"
}

run_read_only_scenario() {
  local scenario="$1"
  seed_read_only_targets
  run_service_case "$scenario" "read-only-read" "file_read" '^PASS \[file_read\]' --es file_path "$READ_ONLY_ROOT/$READ_ONLY_FILE" --es expected_payload "$READ_ONLY_PAYLOAD" &&
    run_service_case "$scenario" "read-only-write-denied" "file_write_denied" '^PASS \[file_write_denied\]' --es file_path "$READ_ONLY_ROOT/write_denied.txt" --es payload "$PAYLOAD" &&
    run_service_case "$scenario" "read-only-mkdir-denied" "file_mkdir_denied" '^PASS \[file_mkdir_denied\]' --es file_dir "$READ_ONLY_ROOT/newdir" &&
    run_service_case "$scenario" "read-only-rename-denied" "file_rename_denied" '^PASS \[file_rename_denied\]' --es file_path "$READ_ONLY_ROOT/$READ_ONLY_FILE" --es target_file_path "$READ_ONLY_ROOT/renamed.txt" &&
    run_service_case "$scenario" "read-only-delete-denied" "file_delete_denied" '^PASS \[file_delete_denied\]' --es file_path "$READ_ONLY_ROOT/$READ_ONLY_FILE" &&
    check_read_only_artifacts
}

prepare_mapped_read_only_targets() {
  adb_su "mkdir -p '$MAPPED_READ_ONLY_REQUEST' '$MAPPED_READ_ONLY_TARGET'; rm -f '$MAPPED_READ_ONLY_REQUEST/$TEST_FILE' '$MAPPED_READ_ONLY_TARGET/$TEST_FILE'; chmod -R 777 '$MAPPED_READ_ONLY_REQUEST' '$MAPPED_READ_ONLY_TARGET' 2>/dev/null || true" >/dev/null
}

run_mapped_read_only_scenario() {
  local scenario="$1"
  prepare_mapped_read_only_targets
  run_service_case "$scenario" "mapped-read-only-write-denied" "file_write_denied" '^PASS \[file_write_denied\]' --es file_path "$MAPPED_READ_ONLY_REQUEST/$TEST_FILE" --es payload "$PAYLOAD" &&
    check_file_missing "mapped-read-only-request" "$MAPPED_READ_ONLY_REQUEST/$TEST_FILE" &&
    check_file_missing "mapped-read-only-target" "$MAPPED_READ_ONLY_TARGET/$TEST_FILE"
}

run_allow_exclusion_scenario() {
  local scenario="$1"
  local keep_path="$ALLOW_ROOT/$ALLOW_KEEP_FILE"
  local keep_private="$PRIVATE_ALLOW_ROOT/$ALLOW_KEEP_FILE"
  local tmp_path="$ALLOW_ROOT/tmp/$TEST_FILE"
  local tmp_private="$PRIVATE_ALLOW_ROOT/tmp/$TEST_FILE"
  local part_path="$ALLOW_ROOT/$ALLOW_PART_FILE"
  local part_private="$PRIVATE_ALLOW_ROOT/$ALLOW_PART_FILE"

  run_write_case "$scenario" "allow-real-write" "$keep_path" "$PAYLOAD" &&
    check_file_exists "allow-real" "$keep_path" &&
    check_file_missing "allow-real-private" "$keep_private" &&
    run_write_case "$scenario" "allow-excluded-dir-write" "$tmp_path" "$PAYLOAD" &&
    check_file_exists "allow-excluded-dir-private" "$tmp_private" &&
    check_file_missing "allow-excluded-dir-real" "$tmp_path" &&
    run_create_case "$scenario" "allow-excluded-glob-create" "$part_path" &&
    check_file_exists "allow-excluded-glob-private" "$part_private" &&
    check_file_missing "allow-excluded-glob-real" "$part_path"
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
  adb_su "echo ===config===; cat '$CONFIG' 2>/dev/null || true; echo; echo ===module_state===; ls -la /data/adb/modules/storage.redirect.x 2>/dev/null || true; echo; mount | grep -E 'srx|storage.redirect' || true; echo; echo ===logs===; for log in running.log app_status.log file_monitor.log media_provider_state.log; do echo ---\$log---; tail -80 /data/adb/modules/storage.redirect.x/logs/\$log 2>/dev/null || true; done; echo ===files===; for dir in '${REAL_ROOT}/Download' '${REAL_ROOT}/Pictures' '${REAL_ROOT}/.xldownload' '${REAL_ROOT}/.xlDownload' '${PRIVATE_ROOT}/Download' '${PRIVATE_ROOT}/Pictures' '${PRIVATE_ROOT}/.xldownload' '${PRIVATE_ROOT}/.xlDownload'; do find \"\$dir\" -maxdepth 5 \\( -name '$TEST_FILE' -o -name '$READ_ONLY_FILE' -o -name '$ALLOW_KEEP_FILE' -o -name '$ALLOW_PART_FILE' \\) -printf '%p %s %u:%g\\n' 2>/dev/null || true; done | sort; echo ===results===; cat '$RESULT_DIR'/result_*.txt '$INTERNAL_RESULT_DIR'/result_*.txt 2>/dev/null || true" || true
  adb logcat -d -t 1200 | grep -Ei 'StorageRedirectTest|srx|StorageRedirect|Magisk|zygisk|FATAL EXCEPTION|AndroidRuntime|PhantomProcessRecord|ExternalStorage|StorageManager|MediaProvider|vold|sdcard|fuse|Transport endpoint' | tail -260 || true
}

run_standard_scenario() {
  local scenario="$1"
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

run_scenario() {
  local scenario="$1"
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
  case "$scenario" in
    9)
      echo "step 5/7: 预置只读路径并执行拒绝类用例"
      run_read_only_scenario "$scenario"
      ;;
    10)
      echo "step 5/7: 预置映射只读路径并执行拒绝类用例"
      run_mapped_read_only_scenario "$scenario"
      ;;
    11)
      echo "step 5/7: 执行放行、排除目录写入和通配符排除创建"
      run_allow_exclusion_scenario "$scenario"
      ;;
    *)
      run_standard_scenario "$scenario"
      ;;
  esac
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
export APP_ID CONFIG LOG_PATH ACTION RESULT_DIR INTERNAL_RESULT_DIR REAL_ROOT BACKEND_ROOT PRIVATE_ROOT BACKEND_PRIVATE_ROOT SANDBOX_RESULT_DIR TEST_FILE READ_ONLY_FILE ALLOW_KEEP_FILE ALLOW_PART_FILE PAYLOAD READ_ONLY_PAYLOAD READ_ONLY_ROOT MAPPED_READ_ONLY_REQUEST MAPPED_READ_ONLY_TARGET ALLOW_ROOT PRIVATE_ALLOW_ROOT
export -f adb_root adb_su wait_boot_completed write_config apply_config target_path logical_dir expected_path scenario_title clean_targets clean_results latest_result prepare_service_case wait_storage_ready print_storage_state run_service_case run_write_case run_write_test check_app_view expect_app_entry expect_no_app_entry find_written_file check_file_exists check_file_missing check_file_location seed_read_only_targets check_read_only_artifacts run_read_only_scenario prepare_mapped_read_only_targets run_mapped_read_only_scenario run_allow_exclusion_scenario check_health print_diagnostics run_standard_scenario run_scenario

for scenario in 1 2 3 4 5 6 7 8 9 10 11; do
  echo "::group::scenario ${scenario}: $(scenario_title "$scenario")"
  if ! timeout --foreground 360s bash -c 'run_scenario "$1"' _ "$scenario"; then
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
