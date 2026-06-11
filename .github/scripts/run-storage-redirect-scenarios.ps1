param(
    [string]$Serial = $env:ANDROID_SERIAL,
    [string]$AppId = "me.fakerqu.test.storageredirect",
    [switch]$SkipBasicAll
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = (& adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "`tdevice" })
    if ($devices.Count -eq 1) {
        $Serial = ($devices[0] -split "\s+")[0]
    } else {
        throw "Multiple or no devices detected. Pass -Serial explicitly."
    }
}

$Action = "me.fakerqu.test.storageredirection.TEST_CASE"
$Config = "/data/adb/modules/storage.redirect.x/config/apps/$AppId.json"
$LogPath = "/data/adb/modules/storage.redirect.x/logs/running.log"
$ResultDir = "/sdcard/Android/data/$AppId/files/test_case_result"
$InternalResultDir = "/data/data/$AppId/files/test_case_result"
$RealRoot = "/storage/emulated/0"
$PrivateRoot = "$RealRoot/Android/data/$AppId/sdcard"
$BackendRoot = "/data/media/0"
$BackendPrivateRoot = "$BackendRoot/Android/data/$AppId/sdcard"
$SandboxResultDir = "$BackendPrivateRoot/Android/data/$AppId/files/test_case_result"
$TestFile = "srt_ci_probe.txt"
$ReadOnlyFile = "srt_read_only_seed.txt"
$AllowKeepFile = "keep.txt"
$AllowPartFile = "srt_ci_probe.part"
$Payload = "storage-redirect-test:file:ci"
$ReadOnlyPayload = "storage-redirect-test:file:readonly"

$ReadOnlyRoot = "$RealRoot/Download/SrtReadOnly"
$MappedReadOnlyRequest = "$RealRoot/Download/SrtMapRO"
$MappedReadOnlyTarget = "$RealRoot/Pictures/SrtLocked"
$AllowRoot = "$RealRoot/Download/SrtAllow"
$PrivateAllowRoot = "$PrivateRoot/Download/SrtAllow"

$script:Summary = New-Object System.Collections.Generic.List[object]
$script:Failures = New-Object System.Collections.Generic.List[string]

function Invoke-Adb {
    param([string[]]$Arguments)
    & adb -s $Serial @Arguments | ForEach-Object { $_ -replace "`r", "" }
}

function Invoke-Su {
    param([string]$Command)
    $escaped = $Command.Replace("'", "'\''")
    & adb -s $Serial shell "su -c '$escaped'" | ForEach-Object { $_ -replace "`r", "" }
}

function Test-Su {
    param([string]$Command)
    $escaped = $Command.Replace("'", "'\''")
    & adb -s $Serial shell "su -c '$escaped'" | Out-Null
    $LASTEXITCODE -eq 0
}

function Write-DeviceConfig {
    param([string]$Json)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Json))
    Invoke-Su "mkdir -p /data/adb/modules/storage.redirect.x/config/apps; printf '%s' '$encoded' | base64 -d > '$Config'; chmod 644 '$Config'" | Out-Null
}

function Apply-ScenarioConfig {
    param([int]$Scenario)
    switch ($Scenario) {
        1 { Invoke-Su "rm -f '$Config'" | Out-Null }
        2 { Write-DeviceConfig '{"users":{"0":{"enabled":true}}}' }
        3 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"path_mappings":{"Download/SrtProbe":"Download/Test"}}}}' }
        4 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"allowed_real_paths":["Download"],"path_mappings":{"Download/SrtProbe":"Download/Test"}}}}' }
        5 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"allowed_real_paths":["Download"]}}}' }
        6 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"mapping_mode_only":true,"path_mappings":{"Download/SrtOther":"Download/SrtOtherMapped"}}}}' }
        7 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"mapping_mode_only":true,"path_mappings":{"Download/SrtProbe":"Download/SrtMapOnlyMapped"}}}}' }
        8 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"mapping_mode_only":true,"sandboxed_paths":[".xlDownload"]}}}' }
        9 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"read_only_paths":["Download/SrtReadOnly"]}}}' }
        10 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"path_mappings":{"Download/SrtMapRO":"Pictures/SrtLocked"},"read_only_paths":["Pictures/SrtLocked"]}}}' }
        11 { Write-DeviceConfig '{"users":{"0":{"enabled":true,"allowed_real_paths":["Download/SrtAllow","!Download/SrtAllow/tmp","!Download/SrtAllow/*.part"]}}}' }
        default { throw "Unknown scenario $Scenario" }
    }
}

function Clear-Results {
    Invoke-Su "rm -rf '$ResultDir' '$InternalResultDir' '$SandboxResultDir'" | Out-Null
}

function Get-LatestResult {
    $path = Invoke-Su "ls -t '$ResultDir'/result_*.txt '$InternalResultDir'/result_*.txt '$SandboxResultDir'/result_*.txt 2>/dev/null | head -1"
    $path | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -First 1
}

function Invoke-ServiceCase {
    param(
        [string]$Scenario,
        [string]$Label,
        [string]$TestCase,
        [hashtable]$Extras,
        [string]$PassRegex
    )

    Write-Host "  - ${Scenario}/${Label}: $TestCase"
    Prepare-ServiceCase "$Scenario/$Label"
    Clear-Results
    $args = @("shell", "am", "start-foreground-service", "-n", "$AppId/.TestService", "-a", $Action, "--es", "test_case", $TestCase)
    foreach ($key in $Extras.Keys) {
        $args += @("--es", [string]$key, [string]$Extras[$key])
    }
    Invoke-Adb $args | Out-Null

    $deadline = (Get-Date).AddSeconds(75)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $resultPath = Get-LatestResult
        if ($resultPath) {
            $content = @(Invoke-Su "cat '$resultPath'")
            $text = $content -join "`n"
            $ok = if ($PassRegex) { $text -match $PassRegex } else { $true }
            if (-not $ok) {
                $script:Failures.Add("$Scenario/$Label expected $PassRegex, got: $($text -replace "`n", " | ")")
                Write-Host "    FAIL $Scenario/$Label"
            } else {
                Write-Host "    PASS $Scenario/$Label"
            }
            return [pscustomobject]@{ Ok = $ok; Text = $text; Path = $resultPath }
        }
    }

    $script:Failures.Add("$Scenario/$Label result timeout for $TestCase")
    Write-Host "    TIMEOUT $Scenario/$Label"
    Invoke-Adb @("shell", "am", "force-stop", $AppId) | Out-Null
    [pscustomobject]@{ Ok = $false; Text = "timeout"; Path = "" }
}

function Prepare-ServiceCase {
    param([string]$Label)
    Invoke-Adb @("shell", "am", "force-stop", $AppId) | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-Adb @("shell", "am", "start", "-W", "-n", "$AppId/.MainActivity") | Out-Null
    Start-Sleep -Milliseconds 800
    Wait-Storage $Label | Out-Null
}

function Test-FileExists {
    param([string]$Path)
    Test-Su "test -f '$(Convert-ToBackendPath $Path)'"
}

function Test-PathMissing {
    param([string]$Path)
    Test-Su "test ! -e '$(Convert-ToBackendPath $Path)'"
}

function Convert-ToBackendPath {
    param([string]$Path)
    if ($Path.StartsWith($RealRoot)) {
        return $BackendRoot + $Path.Substring($RealRoot.Length)
    }
    $Path
}

function Require-File {
    param([string]$Scenario, [string]$Label, [string]$Path)
    if (Test-FileExists $Path) { return $true }
    $script:Failures.Add("$Scenario/$Label missing file: $Path")
    $false
}

function Require-Missing {
    param([string]$Scenario, [string]$Label, [string]$Path)
    if (Test-PathMissing $Path) { return $true }
    $script:Failures.Add("$Scenario/$Label unexpected path exists: $Path")
    $false
}

function Wait-Storage {
    param([string]$Label)
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        & adb -s $Serial shell "sm list-volumes all 2>/dev/null | grep -q 'emulated;0 mounted' && test -d '$RealRoot'" | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 2
    }
    $script:Failures.Add("$Label storage not ready")
    $false
}

function Clear-Targets {
    Invoke-Su "rm -rf '$BackendRoot/Download/SrtProbe' '$BackendRoot/Download/SrtOther' '$BackendRoot/Download/SrtOtherMapped' '$BackendRoot/Download/SrtMapOnlyMapped' '$BackendRoot/Download/SrtReadOnly' '$BackendRoot/Download/SrtMapRO' '$BackendRoot/Download/SrtAllow' '$BackendRoot/Pictures/SrtLocked' '$BackendPrivateRoot/Download/SrtProbe' '$BackendPrivateRoot/Download/SrtOther' '$BackendPrivateRoot/Download/SrtOtherMapped' '$BackendPrivateRoot/Download/SrtMapOnlyMapped' '$BackendPrivateRoot/Download/SrtReadOnly' '$BackendPrivateRoot/Download/SrtMapRO' '$BackendPrivateRoot/Download/SrtAllow' '$BackendPrivateRoot/Pictures/SrtLocked'; rm -f '$BackendRoot/Download/Test/$TestFile' '$BackendPrivateRoot/Download/Test/$TestFile' '$BackendRoot/.xldownload/$TestFile' '$BackendRoot/.xlDownload/$TestFile' '$BackendPrivateRoot/.xldownload/$TestFile' '$BackendPrivateRoot/.xlDownload/$TestFile'" | Out-Null
    Invoke-Su "mkdir -p '$BackendRoot/Download/SrtProbe' '$BackendRoot/Download/Test' '$BackendRoot/Download/SrtMapOnlyMapped' '$BackendRoot/Download/SrtReadOnly' '$BackendRoot/Download/SrtMapRO' '$BackendRoot/Download/SrtAllow/tmp' '$BackendRoot/Pictures/SrtLocked' '$BackendRoot/.xldownload' '$BackendRoot/.xlDownload' '$BackendPrivateRoot/Download/SrtProbe' '$BackendPrivateRoot/Download/Test' '$BackendPrivateRoot/Download/SrtMapOnlyMapped' '$BackendPrivateRoot/Download/SrtReadOnly' '$BackendPrivateRoot/Download/SrtMapRO' '$BackendPrivateRoot/Download/SrtAllow/tmp' '$BackendPrivateRoot/Pictures/SrtLocked' '$BackendPrivateRoot/.xldownload' '$BackendPrivateRoot/.xlDownload'; chmod -R 777 '$BackendRoot/Download/SrtProbe' '$BackendRoot/Download/Test' '$BackendRoot/Download/SrtMapOnlyMapped' '$BackendRoot/Download/SrtReadOnly' '$BackendRoot/Download/SrtMapRO' '$BackendRoot/Download/SrtAllow' '$BackendRoot/Pictures/SrtLocked' '$BackendPrivateRoot/Download/SrtProbe' '$BackendPrivateRoot/Download/Test' '$BackendPrivateRoot/Download/SrtMapOnlyMapped' '$BackendPrivateRoot/Download/SrtReadOnly' '$BackendPrivateRoot/Download/SrtMapRO' '$BackendPrivateRoot/Download/SrtAllow' '$BackendPrivateRoot/Pictures/SrtLocked' 2>/dev/null || true; chmod 777 '$BackendRoot/.xldownload' '$BackendRoot/.xlDownload' '$BackendPrivateRoot/.xldownload' '$BackendPrivateRoot/.xlDownload' 2>/dev/null || true" | Out-Null
}

function Restart-App {
    param([string]$Label)
    Invoke-Adb @("shell", "am", "force-stop", $AppId) | Out-Null
    Invoke-Adb @("shell", "am", "start", "-n", "$AppId/.MainActivity") | Out-Null
    Start-Sleep -Seconds 2
    Wait-Storage $Label | Out-Null
}

function Get-TargetPath {
    param([int]$Scenario)
    if ($Scenario -eq 8) { return "$RealRoot/.xldownload/$TestFile" }
    "$RealRoot/Download/SrtProbe/$TestFile"
}

function Get-LogicalDir {
    param([int]$Scenario)
    if ($Scenario -eq 8) { return "$RealRoot/.xldownload" }
    "$RealRoot/Download/SrtProbe"
}

function Get-ExpectedPath {
    param([int]$Scenario)
    switch ($Scenario) {
        1 { "$RealRoot/Download/SrtProbe/$TestFile" }
        2 { "$PrivateRoot/Download/SrtProbe/$TestFile" }
        3 { "$RealRoot/Download/Test/$TestFile" }
        4 { "$RealRoot/Download/Test/$TestFile" }
        5 { "$RealRoot/Download/SrtProbe/$TestFile" }
        6 { "$RealRoot/Download/SrtProbe/$TestFile" }
        7 { "$RealRoot/Download/SrtMapOnlyMapped/$TestFile" }
        8 { "$PrivateRoot/.xldownload/$TestFile" }
    }
}

function Get-ScenarioTitle {
    param([int]$Scenario)
    switch ($Scenario) {
        1 { "no config keeps real path" }
        2 { "default redirect to private" }
        3 { "path mapping to Download/Test" }
        4 { "mapping priority over allow Download" }
        5 { "allow Download keeps real path" }
        6 { "mapping_mode_only unmatched stays real" }
        7 { "mapping_mode_only mapped path maps" }
        8 { "mapping_mode_only sandboxed .xlDownload alias" }
        9 { "read_only_paths deny writes" }
        10 { "mapped target read-only deny write" }
        11 { "allow with inline exclusions and wildcard" }
    }
}

function Invoke-WriteCase {
    param([int]$Scenario, [string]$Label, [string]$Path, [string]$Data)
    Invoke-ServiceCase "scenario-$Scenario" $Label "file_write" @{ file_path = $Path; payload = $Data; expected_payload = $Data } "^PASS \[file_write\]"
}

function Invoke-CreateCase {
    param([int]$Scenario, [string]$Label, [string]$Path)
    Invoke-ServiceCase "scenario-$Scenario" $Label "file_create" @{ file_path = $Path } "^PASS \[file_create\]"
}

function Expect-AppEntry {
    param([int]$Scenario, [string]$Label, [string]$Dir, [string]$FileName)
    $result = Invoke-ServiceCase "scenario-$Scenario" $Label "file_list_dir" @{ file_dir = $Dir } "^PASS \[file_list_dir\]"
    if (-not $result.Ok) { return $false }
    if ($result.Text -match "entries=.*$([regex]::Escape($FileName))") { return $true }
    $script:Failures.Add("scenario-$Scenario/$Label app view missing $FileName in $Dir :: $($result.Text -replace "`n", " | ")")
    $false
}

function Expect-NoAppEntry {
    param([int]$Scenario, [string]$Label, [string]$Dir, [string]$FileName)
    $result = Invoke-ServiceCase "scenario-$Scenario" $Label "file_list_dir" @{ file_dir = $Dir } ""
    if ($result.Text -match "entries=.*$([regex]::Escape($FileName))") {
        $script:Failures.Add("scenario-$Scenario/$Label app view unexpectedly sees $FileName in $Dir")
        return $false
    }
    $true
}

function Invoke-StandardScenario {
    param([int]$Scenario)
    $ok = (Invoke-WriteCase $Scenario "write" (Get-TargetPath $Scenario) $Payload).Ok
    $ok = (Expect-AppEntry $Scenario "app-view" (Get-LogicalDir $Scenario) $TestFile) -and $ok
    if ($Scenario -eq 3) { $ok = (Expect-NoAppEntry $Scenario "mapped-real-view" "$RealRoot/Download/Test" $TestFile) -and $ok }
    if ($Scenario -eq 4) { $ok = (Expect-AppEntry $Scenario "mapped-real-view" "$RealRoot/Download/Test" $TestFile) -and $ok }
    $ok = (Require-File "scenario-$Scenario" "expected-location" (Get-ExpectedPath $Scenario)) -and $ok
    switch ($Scenario) {
        2 { $ok = (Require-Missing "scenario-$Scenario" "real-request" "$RealRoot/Download/SrtProbe/$TestFile") -and $ok }
        3 { $ok = (Require-Missing "scenario-$Scenario" "real-request" "$RealRoot/Download/SrtProbe/$TestFile") -and $ok }
        7 { $ok = (Require-Missing "scenario-$Scenario" "real-request" "$RealRoot/Download/SrtProbe/$TestFile") -and $ok }
        8 { $ok = (Require-Missing "scenario-$Scenario" "real-request" "$RealRoot/.xldownload/$TestFile") -and $ok }
    }
    $ok
}

function Set-ReadOnlySeed {
    $root = Convert-ToBackendPath $ReadOnlyRoot
    Invoke-Su "mkdir -p '$root'; rm -f '$root/write_denied.txt' '$root/renamed.txt'; rm -rf '$root/newdir'; printf '%s' '$ReadOnlyPayload' > '$root/$ReadOnlyFile'; chmod -R 777 '$root' 2>/dev/null || true" | Out-Null
}

function Invoke-ReadOnlyScenario {
    param([int]$Scenario)
    $ok = $true
    $ok = (Invoke-ServiceCase "scenario-$Scenario" "read" "file_read" @{ file_path = "$ReadOnlyRoot/$ReadOnlyFile"; expected_payload = $ReadOnlyPayload } "^PASS \[file_read\]").Ok -and $ok
    $ok = (Invoke-ServiceCase "scenario-$Scenario" "write-denied" "file_write_denied" @{ file_path = "$ReadOnlyRoot/write_denied.txt"; payload = $Payload } "^PASS \[file_write_denied\]").Ok -and $ok
    $ok = (Invoke-ServiceCase "scenario-$Scenario" "mkdir-denied" "file_mkdir_denied" @{ file_dir = "$ReadOnlyRoot/newdir" } "^PASS \[file_mkdir_denied\]").Ok -and $ok
    $ok = (Invoke-ServiceCase "scenario-$Scenario" "rename-denied" "file_rename_denied" @{ file_path = "$ReadOnlyRoot/$ReadOnlyFile"; target_file_path = "$ReadOnlyRoot/renamed.txt" } "^PASS \[file_rename_denied\]").Ok -and $ok
    $ok = (Invoke-ServiceCase "scenario-$Scenario" "delete-denied" "file_delete_denied" @{ file_path = "$ReadOnlyRoot/$ReadOnlyFile" } "^PASS \[file_delete_denied\]").Ok -and $ok
    $ok = (Require-File "scenario-$Scenario" "seed-still-exists" "$ReadOnlyRoot/$ReadOnlyFile") -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "write-target" "$ReadOnlyRoot/write_denied.txt") -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "mkdir-target" "$ReadOnlyRoot/newdir") -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "rename-target" "$ReadOnlyRoot/renamed.txt") -and $ok
    $ok
}

function Set-MappedReadOnlyTargets {
    $request = Convert-ToBackendPath $MappedReadOnlyRequest
    $target = Convert-ToBackendPath $MappedReadOnlyTarget
    Invoke-Su "mkdir -p '$request' '$target'; rm -f '$request/$TestFile' '$target/$TestFile'; chmod -R 777 '$request' '$target' 2>/dev/null || true" | Out-Null
}

function Invoke-MappedReadOnlyScenario {
    param([int]$Scenario)
    $ok = (Invoke-ServiceCase "scenario-$Scenario" "mapped-write-denied" "file_write_denied" @{ file_path = "$MappedReadOnlyRequest/$TestFile"; payload = $Payload } "^PASS \[file_write_denied\]").Ok
    $ok = (Require-Missing "scenario-$Scenario" "request-file" "$MappedReadOnlyRequest/$TestFile") -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "target-file" "$MappedReadOnlyTarget/$TestFile") -and $ok
    $ok
}

function Invoke-AllowExclusionScenario {
    param([int]$Scenario)
    $keepPath = "$AllowRoot/$AllowKeepFile"
    $keepPrivate = "$PrivateAllowRoot/$AllowKeepFile"
    $tmpPath = "$AllowRoot/tmp/$TestFile"
    $tmpPrivate = "$PrivateAllowRoot/tmp/$TestFile"
    $partPath = "$AllowRoot/$AllowPartFile"
    $partPrivate = "$PrivateAllowRoot/$AllowPartFile"

    $ok = (Invoke-WriteCase $Scenario "allow-real-write" $keepPath $Payload).Ok
    $ok = (Require-File "scenario-$Scenario" "allow-real" $keepPath) -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "allow-real-private" $keepPrivate) -and $ok
    $ok = (Invoke-WriteCase $Scenario "excluded-dir-write" $tmpPath $Payload).Ok -and $ok
    $ok = (Require-File "scenario-$Scenario" "excluded-dir-private" $tmpPrivate) -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "excluded-dir-real" $tmpPath) -and $ok
    $ok = (Invoke-CreateCase $Scenario "excluded-glob-create" $partPath).Ok -and $ok
    $ok = (Require-File "scenario-$Scenario" "excluded-glob-private" $partPrivate) -and $ok
    $ok = (Require-Missing "scenario-$Scenario" "excluded-glob-real" $partPath) -and $ok
    $ok
}

function Invoke-Scenario {
    param([int]$Scenario)
    Write-Host "== scenario ${Scenario}: $(Get-ScenarioTitle $Scenario) =="
    Apply-ScenarioConfig $Scenario
    Clear-Targets
    if ($Scenario -eq 9) { Set-ReadOnlySeed }
    if ($Scenario -eq 10) { Set-MappedReadOnlyTargets }
    Restart-App "scenario-$Scenario"
    $before = $script:Failures.Count
    $ok = switch ($Scenario) {
        9 { Invoke-ReadOnlyScenario $Scenario }
        10 { Invoke-MappedReadOnlyScenario $Scenario }
        11 { Invoke-AllowExclusionScenario $Scenario }
        default { Invoke-StandardScenario $Scenario }
    }
    $newFailures = $script:Failures.Count - $before
    $script:Summary.Add([pscustomobject]@{ Scenario = $Scenario; Title = (Get-ScenarioTitle $Scenario); Passed = ($ok -and $newFailures -eq 0); NewFailures = $newFailures }) | Out-Null
}

function Invoke-BasicAll {
    Write-Host "== basic all suite with default redirect enabled =="
    Write-DeviceConfig '{"users":{"0":{"enabled":true}}}'
    Clear-Targets
    Restart-App "all-basic"
    $before = $script:Failures.Count
    $result = Invoke-ServiceCase "basic" "all" "all" @{} "^PASS "
    $failedLines = @()
    if ($result.Text) {
        $failedLines = $result.Text -split "`n" | Where-Object { $_ -match "^FAIL " }
    }
    foreach ($line in $failedLines) {
        $script:Failures.Add("basic/all $line")
    }
    $ok = $result.Ok -and $failedLines.Count -eq 0
    $script:Summary.Add([pscustomobject]@{ Scenario = "basic"; Title = "all except delete/thumbnail"; Passed = $ok; NewFailures = ($script:Failures.Count - $before) }) | Out-Null
}

Invoke-Adb @("shell", "pm", "grant", $AppId, "android.permission.READ_EXTERNAL_STORAGE") | Out-Null
Invoke-Adb @("shell", "pm", "grant", $AppId, "android.permission.WRITE_EXTERNAL_STORAGE") | Out-Null
Invoke-Adb @("shell", "pm", "grant", $AppId, "android.permission.READ_MEDIA_IMAGES") | Out-Null
Invoke-Adb @("shell", "pm", "grant", $AppId, "android.permission.READ_MEDIA_VIDEO") | Out-Null
Invoke-Adb @("shell", "pm", "grant", $AppId, "android.permission.READ_MEDIA_AUDIO") | Out-Null
Invoke-Adb @("shell", "appops", "set", $AppId, "MANAGE_EXTERNAL_STORAGE", "allow") | Out-Null
Invoke-Adb @("logcat", "-c") | Out-Null
Invoke-Su ": > '$LogPath' 2>/dev/null || true" | Out-Null
Wait-Storage "initial" | Out-Null

if (-not $SkipBasicAll) {
    Invoke-BasicAll
}

foreach ($scenario in 1..11) {
    Invoke-Scenario $scenario
}

Write-Host "== summary =="
$script:Summary | Format-Table -AutoSize | Out-String | Write-Host

if ($script:Failures.Count -gt 0) {
    Write-Host "== failures =="
    $script:Failures | ForEach-Object { Write-Host $_ }
    Write-Host "== module log tail =="
    Invoke-Su 'for log in running.log app_status.log file_monitor.log media_provider_state.log; do echo ---$log---; tail -80 /data/adb/modules/storage.redirect.x/logs/$log 2>/dev/null || true; done' | Write-Host
    Write-Host "== relevant logcat tail =="
    & adb -s $Serial logcat -d -t 500 |
        Select-String -Pattern "StorageRedirectTest|srx|StorageRedirect|FATAL EXCEPTION|AndroidRuntime|MediaProvider|ExternalStorage|fuse|Transport endpoint" |
        Select-Object -Last 160 |
        ForEach-Object { Write-Host $_.Line }
    exit 1
}

Write-Host "ALL_SCENARIOS_PASSED"
