# Exports a debug APK and installs it on a connected phone (USB debugging on).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/export_android.ps1 [-NoInstall]
# Only checks and reports when a prerequisite is missing; it never downloads anything.
param([switch]$NoInstall)
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$version = '4.7.2.stable'
$templates = Join-Path $env:APPDATA "Godot\export_templates\$version"
$settingsFile = Join-Path $env:APPDATA 'Godot\editor_settings-4.7.tres'
$problems = @()

if (-not (Test-Path (Join-Path $templates 'android_debug.apk'))) {
	$problems += "Exportvorlagen fehlen: $templates (Godot-Editor > Editor > Exportvorlagen verwalten > Herunterladen, Version $version)."
}
$settings = if (Test-Path $settingsFile) { Get-Content $settingsFile -Raw } else { '' }
$sdkMatch = [regex]::Match($settings, 'export/android/android_sdk_path = "([^"]*)"')
$sdkPath = if ($sdkMatch.Success) { $sdkMatch.Groups[1].Value -replace '\\\\', '\' -replace '/', '\' } else { '' }
if (-not $sdkPath -or -not (Test-Path (Join-Path $sdkPath 'platform-tools\adb.exe'))) {
	$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
	$hint = if ($adb) { Split-Path (Split-Path $adb) } else { '<Android-SDK-Ordner>' }
	$problems += "Android-SDK-Pfad in den Godot-Editoreinstellungen ungueltig ('$sdkPath'). Im Editor unter Editoreinstellungen > Export > Android > Android Sdk Path auf '$hint' setzen."
}
$javaMatch = [regex]::Match($settings, 'export/android/java_sdk_path = "([^"]*)"')
if ($javaMatch.Success -and $javaMatch.Groups[1].Value -match '\.exe$') {
	$problems += "Java-SDK-Pfad zeigt auf eine .exe ('$($javaMatch.Groups[1].Value)'); erwartet wird der JDK-Ordner (ohne \bin\java.exe)."
}
if ($problems.Count -gt 0) {
	Write-Output 'ANDROID-EXPORT NICHT MOEGLICH:'
	$problems | ForEach-Object { Write-Output "  - $_" }
	exit 2
}

New-Item -ItemType Directory -Force (Join-Path $projectDir 'build\android') | Out-Null
$apk = Join-Path $projectDir 'build\android\hordehunters-debug.apk'
& $godotExe --headless --path $projectDir --export-debug 'Android' $apk 2>&1 | Select-Object -Last 15
if (-not (Test-Path $apk)) { Write-Output 'EXPORT FEHLGESCHLAGEN'; exit 1 }
Write-Output ("APK: $apk (" + [math]::Round((Get-Item $apk).Length / 1MB, 1) + ' MB)')
if ($NoInstall) { exit 0 }
$devices = (& adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' }
if (-not $devices) { Write-Output 'Kein Geraet verbunden (USB-Debugging aktivieren, Kabel anschliessen, Freigabe am Handy bestaetigen).'; exit 0 }
& adb install -r $apk
& adb shell monkey -p com.hordehunters.game -c android.intent.category.LAUNCHER 1 | Out-Null
Write-Output 'Installiert und gestartet.'
