# StorageRedirectTest

StorageRedirectTest 是 `srx_core` 的回归测试套件，用来验证 Storage Redirect X 在修改核心代码后，文件重定向、路径映射、真实路径放行、MediaStore 访问等功能是否仍然正常。

本地默认配合源码目录：

```text
C:\Users\12988\Desktop\srx_core
```

测试 App 包名：

```text
me.fakerqu.test.storageredirect
```

## 项目结构

- `app`：测试 App，包含 Compose 调试界面、`TestService`、广播入口和测试用例。
- `media-file-api`：被测试 App 调用的文件与 MediaStore API 封装。
- `.github/workflows/android.yml`：CI 稳定性测试流程。
- `.github/scripts/install-storage-redirect-module.sh`：CI 中给 x86_64 模拟器安装 Magisk 与 Storage Redirect X 模块。
- `.github/scripts/run-storage-redirect-scenarios.sh` / `.ps1`：CI/ADB 场景脚本，验证不同 SRX 配置下文件落点和 App 视角。

## 环境要求

- JDK 21。
- Android SDK / platform-tools，确保 `adb` 可用。
- Gradle Wrapper 使用本仓库的 `gradlew.bat` 或 `./gradlew`。
- 需要一台可用 root 的测试设备或模拟器，并已刷入 Storage Redirect X 模块。
- 如果要验证本地 `srx_core` 修改，先从 `C:\Users\12988\Desktop\srx_core` 构建并刷入本地模块包。

本项目已优先使用国内下载源：Gradle Wrapper 使用腾讯 Gradle 镜像，Gradle daemon JDK 21 使用清华 TUNA Adoptium 镜像，Maven/插件依赖优先走阿里云和腾讯 Maven 镜像，官方源仅作为兜底。

## 本地快速使用

先构建并刷入本地 `srx_core` 模块：

```powershell
cd C:\Users\12988\Desktop\srx_core
.\scripts\build-local-module.ps1
```

模块更新后需要重启设备。重启完成后确认模块存在：

```powershell
adb wait-for-device
adb shell "su -c 'cat /data/adb/modules/storage.redirect.x/module.prop'"
```

再构建并安装测试 App：

```powershell
cd C:\Users\12988\Desktop\StorageRedirectTest
.\gradlew.bat --no-daemon :app:testDebugUnitTest :media-file-api:testDebugUnitTest :app:assembleDebug
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

授予测试 App 必要权限：

```powershell
adb shell pm grant me.fakerqu.test.storageredirect android.permission.READ_EXTERNAL_STORAGE 2>$null
adb shell pm grant me.fakerqu.test.storageredirect android.permission.WRITE_EXTERNAL_STORAGE 2>$null
adb shell pm grant me.fakerqu.test.storageredirect android.permission.READ_MEDIA_IMAGES 2>$null
adb shell pm grant me.fakerqu.test.storageredirect android.permission.READ_MEDIA_VIDEO 2>$null
adb shell pm grant me.fakerqu.test.storageredirect android.permission.READ_MEDIA_AUDIO 2>$null
adb shell pm grant me.fakerqu.test.storageredirect android.permission.POST_NOTIFICATIONS 2>$null
adb shell appops set me.fakerqu.test.storageredirect MANAGE_EXTERNAL_STORAGE allow
```

给 SRX 写入测试 App 配置，最小配置表示开启完整隔离模式：

```powershell
$config = '{"users":{"0":{"enabled":true}}}'
adb shell "su -c 'mkdir -p /data/adb/modules/storage.redirect.x/config/apps'"
$config | adb shell "su -c 'cat > /data/adb/modules/storage.redirect.x/config/apps/me.fakerqu.test.storageredirect.json'"
adb shell am force-stop me.fakerqu.test.storageredirect
```

运行默认回归用例：

```powershell
adb shell am start-foreground-service -n me.fakerqu.test.storageredirect/.TestService -a me.fakerqu.test.storageredirection.TEST_CASE --es test_case all
```

查看日志和结果：

```powershell
adb logcat -d -s StorageRedirectTest
adb shell "su -c 'ls -t /sdcard/Android/data/me.fakerqu.test.storageredirect/files/test_case_result/result_*.txt 2>/dev/null | head -1'"
adb shell "su -c 'cat /sdcard/Android/data/me.fakerqu.test.storageredirect/files/test_case_result/result_*.txt 2>/dev/null | tail -80'"
```

`test_case=all` 会运行查询、创建、读取、写入、`stat`、`access`、`truncate`、`ftruncate` 和文件 API 的主要路径，但不会自动执行 MediaStore 删除、缩略图、chmod、link 或 symlink 用例。它会创建 `srt_*` 开头的测试媒体文件，建议在测试机或可清理环境中运行。

## 单个用例

测试入口支持通过 `test_case` 和额外参数运行单个用例。

常用用例 id：

- `all`
- `mediastore_query_image`
- `mediastore_query_video`
- `mediastore_query_audio`
- `mediastore_query_file`
- `mediastore_query_download`
- `mediastore_query_path_image`
- `mediastore_query_path_video`
- `mediastore_query_path_audio`
- `mediastore_query_path_file`
- `mediastore_query_path_download`
- `mediastore_create_image`
- `mediastore_read_image`
- `mediastore_write_image`
- `mediastore_delete_image`
- `mediastore_thumbnail_image`
- `file_list_dir`
- `file_create`
- `file_read`
- `file_write`
- `file_write_denied`
- `file_delete`
- `file_delete_denied`
- `file_mkdir`
- `file_mkdir_denied`
- `file_rename`
- `file_rename_denied`
- `file_stat`
- `file_access`
- `file_readlink`
- `file_truncate`
- `file_truncate_denied`
- `file_ftruncate`
- `file_ftruncate_denied`
- `file_chmod`
- `file_chmod_denied`
- `file_fchmod`
- `file_fchmod_denied`
- `file_link`
- `file_link_denied`
- `file_symlink`
- `file_symlink_denied`

File API 示例：

```powershell
adb shell am start-foreground-service -n me.fakerqu.test.storageredirect/.TestService -a me.fakerqu.test.storageredirection.TEST_CASE --es test_case file_write --es file_path /storage/emulated/0/Download/SrtProbe/srt_ci_probe.txt --es payload "storage-redirect-test:file:manual" --es expected_payload "storage-redirect-test:file:manual"
```

只读或拒绝类用例用于验证 `srx_core` 是否正确阻止写操作。例如：

```powershell
adb shell am start-foreground-service -n me.fakerqu.test.storageredirect/.TestService -a me.fakerqu.test.storageredirection.TEST_CASE --es test_case file_write_denied --es file_path /storage/emulated/0/Download/SrtReadOnly/write_denied.txt --es payload "blocked"

adb shell am start-foreground-service -n me.fakerqu.test.storageredirect/.TestService -a me.fakerqu.test.storageredirection.TEST_CASE --es test_case file_rename_denied --es file_path /storage/emulated/0/Download/SrtReadOnly/srt_read_only_seed.txt --es target_file_path /storage/emulated/0/Download/SrtReadOnly/renamed.txt
```

MediaStore 读写类用例需要先运行对应的 create 用例，从结果中的 `uri=` 取出 `content://...`，再作为 `media_uri` 传入：

```powershell
adb shell am start-foreground-service -n me.fakerqu.test.storageredirect/.TestService -a me.fakerqu.test.storageredirection.TEST_CASE --es test_case mediastore_create_image

adb shell am start-foreground-service -n me.fakerqu.test.storageredirect/.TestService -a me.fakerqu.test.storageredirection.TEST_CASE --es test_case mediastore_read_image --es media_uri "content://media/external/images/media/12345"
```

支持参数：

- `media_uri`：MediaStore 读、写、删、缩略图用例的目标 URI。
- `file_path`：文件读、写、删、创建、重命名源路径等用例的目标路径。
- `target_file_path`：`file_rename` / `file_rename_denied` 的目标路径。
- `file_dir`：目录列表和 mkdir 类用例的目标目录。
- `file_name`：MediaStore 创建用例的文件名，或 `mediastore_query_path_*` 用例用于定位目标行的文件名。
- `payload`：写入内容。
- `expected_payload`：读回校验内容。
- `expected_path`：`file_readlink` 的期望链接目标，或 `mediastore_query_path_*` 的期望 cursor `DATA` 路径。
- `length`：`file_truncate` / `file_ftruncate` 的目标长度。
- `mode`：`file_access`、`file_chmod`、`file_fchmod` 的访问模式或权限模式；支持十进制、`0600` 八进制和 `0o600` 八进制写法。

## 场景脚本

已经安装模块和测试 App 后，可以使用 CI 同款场景脚本。Windows 下建议用 Git Bash 或 WSL 执行：

```bash
cd /c/Users/12988/Desktop/StorageRedirectTest
bash .github/scripts/run-storage-redirect-scenarios.sh
```

脚本会遍历 15 个场景：

- 未启用应用配置，验证默认真实路径写入。
- 启用重定向，验证写入应用私有空间。
- 启用路径映射，验证 `Download/SrtProbe` 写入真实 `Download/Test`。
- 路径映射叠加真实路径放行，验证映射优先级。
- 放行真实 `Download`，验证保持原路径写入。
- 启用 `mapping_mode_only` 且未命中映射，验证保持真实路径写入。
- 启用 `mapping_mode_only` 且命中映射，验证写入映射目标。
- 启用 `mapping_mode_only` + `sandboxed_paths`，验证 `.xlDownload`/`.xldownload` 沙盒化。
- 启用 `read_only_paths`，验证可读、可 `stat`/`access`，但拒绝写入、truncate、ftruncate、chmod、fchmod、link、symlink、删除、mkdir、rename。
- 启用路径映射且映射目标为只读路径，验证从映射请求写入会被拒绝。
- 启用 `allowed_real_paths` 内联排除和通配符排除，验证放行路径保持真实写入、排除目录可写入私有空间、通配符排除会命中并创建到应用私有空间。
- 启用旧版 `excluded_real_paths` 字段，验证它会并入 `allowed_real_paths` 排除规则。
- 启用 `allowed_real_paths` 的 `?` 通配符，验证单字符匹配放行、多字符不匹配时仍进入私有空间。
- 启用多条 `path_mappings`，验证最长前缀映射优先。
- 启用字符串形式 `sandboxed_paths` 且同路径也命中 `path_mappings`，验证映射优先于局部沙盒。

脚本输出 `scenario-*-result.txt` 和 `media-health.txt`。失败时会抓取模块配置、模块日志、存储挂载状态和相关 logcat。

## CI 行为

GitHub Actions 当前会：

- 在 API 31、33、34、35、36 的 x86_64 模拟器上运行。
- 下载 `Kindness-Kismet/Storage-redirection-X-Public` 的最新 x86_64 Release 模块。
- 构建测试 App 和 AndroidTest APK。
- root 模拟器、安装 Magisk、安装 Storage Redirect X 模块、安装测试 App。
- 执行 `.github/scripts/run-storage-redirect-scenarios.sh`。

注意：当前 CI 默认验证的是上游 Release 模块，不会自动使用本地 `C:\Users\12988\Desktop\srx_core` 的未发布修改。本地验证 `srx_core` 改动时，以本 README 的本地快速使用流程为准。

## 维护和提交规则

本仓库是个人 fork 工作区。当前 `origin` 指向：

```text
https://github.com/z1298808165/StorageRedirectTest.git
```

当 StorageRedirectTest 本身发生修改并需要提交时，只提交并推送到自己的 fork。不要向原仓库提交 PR，除非用户明确要求“向原仓库提交 PR”。

如果原仓库更新，需要同步到本项目：

- 先确认当前工作区是否有未提交修改，避免覆盖本地工作。
- 先阅读上游变更内容，尤其是 Gradle、测试脚本、包名、CI、测试用例和结果格式相关变更。
- 根据本项目作为 `srx_core` 回归测试套件的用途判断是否应该同步，不要机械合并。
- 同步前后都要验证关键路径，至少运行 Gradle 单元测试和测试 App 构建。
- 如果同步影响 `.github/scripts/run-storage-redirect-scenarios.sh` 或测试用例语义，需要在设备或模拟器上跑一遍相关场景。
- 解决冲突时保留本项目已有的本地使用方式、fork 提交流程和 `srx_core` 配合测试说明。
