# Renders review frames from the real game camera (needs a window, never --headless).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/capture.ps1 [-Only boss,hunt]
# Output: previews/preview_*.png (git-ignored, .gdignore: Godot does not import them).
param([string[]]$Only = @())
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
# Game windows open on the secondary (portrait) monitor so they do not disturb
# work on the main screen. Override with $env:MAWLINGS_SCREEN (Godot screen index).
$screen = if ($env:MAWLINGS_SCREEN) { $env:MAWLINGS_SCREEN } else { '1' }
$captures = Get-ChildItem (Join-Path $projectDir 'tests') -Filter 'capture_*.gd' | ForEach-Object { $_.BaseName -replace '^capture_', '' }
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })
if ($Only.Count -gt 0) { $captures = $captures | Where-Object { $Only -contains $_ } }
foreach ($name in $captures) {
	$job = Start-Job -ScriptBlock {
		param($exe, $dir, $n, $scr)
		& $exe --screen $scr --audio-driver Dummy --path $dir --script "res://tests/capture_$n.gd" 2>&1 | Select-Object -Last 2
	} -ArgumentList $godotExe, $projectDir, $name, $screen
	if (Wait-Job $job -Timeout 90) {
		Write-Output ("ok   $name :: " + ((Receive-Job $job) -join ' ').Trim())
	} else {
		Stop-Job $job
		Get-Process -Name 'Godot_v4.7.2-stable_win64_console' -ErrorAction SilentlyContinue | Stop-Process -Force
		Write-Output "FAIL $name :: timed out"
	}
	Remove-Job $job -Force
}
Get-ChildItem (Join-Path $projectDir 'previews') -Filter 'preview*.png' | Sort-Object LastWriteTime -Descending | ForEach-Object { "  previews/$($_.Name)" }
