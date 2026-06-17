# StorageRedirectTest Agent Notes

这个仓库是 `srx_core` 的回归测试套件，本地 `srx_core` 源码默认在：

```text
C:\Users\12988\Desktop\srx_core
```

## 工作原则

- 先阅读本仓库实际脚本、Gradle 配置和测试用例，再修改说明或代码。
- 本仓库测试 App 包名是 `me.fakerqu.test.storageredirect`。
- 修改测试行为时，要考虑它是否仍能验证 `srx_core` 的文件重定向、路径映射、真实路径放行和 MediaStore hook 行为。
- 新增 `srx_core` 功能回归时，优先沿用 `TestCase` + `TestService` + `.github/scripts/run-storage-redirect-scenarios.sh` 的现有结构；脚本中的设备侧断言要同时检查 App 视角和 root 视角的物理落点或拒绝结果。
- 如果调整、新增或删除测试项、场景脚本、用例 id、参数语义或覆盖范围，除了更新本项目 README、脚本注释等说明，还必须同步更新 `C:\Users\12988\Desktop\srx_core\docs\device-testing.md`，保持两边测试文档一致。
- 依赖、Gradle、JDK toolchain 下载优先使用国内镜像；不要无故把 `settings.gradle.kts`、`gradle/wrapper/gradle-wrapper.properties` 或 `gradle/gradle-daemon-jvm.properties` 改回海外源。
- 文档和脚本说明要贴合当前代码，不要把旧的 `org.srx.testapp` 命令照搬进来。

## 提交和 PR 规则

- 本项目的 `origin` 是用户自己的 fork：`https://github.com/z1298808165/StorageRedirectTest.git`。
- 当本项目发生修改并需要提交时，只提交到用户自己的 fork。
- 不要向原仓库提交 PR，不要创建面向原仓库的 pull request，除非用户明确要求这样做。
- 如果用户只说“提交”“推送”“保存到远端”，默认理解为提交并推送到自己的 fork。

## 同步上游规则

如果原仓库有更新，不能直接机械合并。同步前需要结合本项目现状核查：

- 查看当前工作区状态，保护用户或本地已有修改。
- 比较上游变更范围，重点检查 Gradle、`.github/workflows/android.yml`、`.github/scripts/*.sh`、测试入口、用例 id、结果格式和 App 包名。
- 判断上游变更是否会破坏本项目作为 `srx_core` 测试套件的用途。
- 如需合并，优先在单独分支处理冲突，保留本项目的 fork 提交流程和本地 `srx_core` 配合说明。
- 同步后至少运行 `:app:testDebugUnitTest`、`:media-file-api:testDebugUnitTest` 和 `:app:assembleDebug`。
- 如果同步修改了设备侧测试脚本或测试用例语义，还需要在可用的 root 设备或模拟器上跑相关 ADB 场景。

## 常用验证命令

```powershell
.\gradlew.bat --no-daemon :app:testDebugUnitTest :media-file-api:testDebugUnitTest :app:assembleDebug
```

本地验证 `srx_core` 改动时，先在 `C:\Users\12988\Desktop\srx_core` 构建并刷入模块，再安装本测试 App，按 `README.md` 运行 `TestService` 用例或 CI 场景脚本。
