# Runs the complete automated Horde Hunters check and prints one compact line per test.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/test.ps1 [-Only smoke,boss] [-SkipPlaythrough] [-TimeoutSec 180]
# Each Godot run has its own timeout: a headless script with a runtime error can
# hang, and only that one process is killed (never other Godot instances).
param(
	[string[]]$Only = @(),
	[switch]$SkipPlaythrough,
	[int]$TimeoutSec = 180
)
$ErrorActionPreference = 'Continue'
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$tests = @('world', 'dash', 'shotgun', 'enemy_melee', 'director', 'death_restart', 'xp_level', 'upgrades', 'chests', 'result', 'waves', 'encircle', 'elite', 'boss', 'endwave', 'profile', 'menu', 'arsenal', 'pause', 'weapon_base', 'fists', 'new_weapons', 'boxer_run')
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })
if ($Only.Count -gt 0) { $tests = $tests | Where-Object { $Only -contains $_ } }

function Invoke-Godot([string[]]$GodotArgs, [int]$Limit = 0) {
	if ($Limit -le 0) { $Limit = $TimeoutSec }
	$outFile = [IO.Path]::GetTempFileName()
	$errFile = [IO.Path]::GetTempFileName()
	$quoted = $GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
	$process = Start-Process -FilePath $godotExe -ArgumentList $quoted -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
	$null = $process.Handle  # keeps ExitCode readable after exit
	$timedOut = -not $process.WaitForExit($Limit * 1000)
	if ($timedOut) {
		try { $process.Kill() } catch {}
		$process.WaitForExit()
	}
	$text = (Get-Content $outFile -Raw -Encoding UTF8) + "`n" + (Get-Content $errFile -Raw -Encoding UTF8)
	Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
	return @{ Code = $(if ($timedOut) { -1 } else { $process.ExitCode }); Out = $text; TimedOut = $timedOut }
}

function Report([string]$Name, $Run, [string]$Pattern) {
	$errors = ($Run.Out -split "`n" | Where-Object { $_ -cmatch '(^|\s)(SCRIPT )?ERROR:|Parse Error' }) -join "`n"
	if ($Run.TimedOut) {
		Write-Host "FAIL $Name (Zeitlimit $TimeoutSec s ueberschritten, Prozess beendet)"
		Write-Host (($Run.Out.Trim() -split "`n") | Select-Object -Last 12 | Out-String)
		return $false
	}
	if ($Run.Code -ne 0 -or $errors) {
		Write-Host "FAIL $Name (exit $($Run.Code))"
		Write-Host (($Run.Out.Trim() -split "`n") | Select-Object -Last 15 | Out-String)
		return $false
	}
	$lines = ($Run.Out.Trim() -split "`n") | Where-Object { $_.Trim() -ne '' }
	# Prefer a PASS line as summary; warnings on stderr may come last.
	$pass = $lines | Where-Object { $_ -match "PASS|passed|bestanden" } | Select-Object -Last 1
	$summary = if ($Pattern) { ($lines | Where-Object { $_ -match $Pattern }) -join ' | ' } elseif ($pass) { $pass } else { ($lines | Select-Object -Last 1) }
	Write-Host ("ok   $Name :: " + "$summary".Trim())
	return $true
}

& $godotExe --headless --editor --import --path $projectDir --quit *> $null
$failed = @()
foreach ($testName in $tests) {
	$run = Invoke-Godot @('--headless', '--audio-driver', 'Dummy', '--path', $projectDir, '--script', "res://tests/$testName.gd")
	if (-not (Report $testName $run '')) { $failed += $testName }
}
if (-not $SkipPlaythrough -and $Only.Count -eq 0) {
	# Playthrough and balance regression run once their scripts exist.
	if (Test-Path (Join-Path $projectDir 'tests/endless_playthrough.gd')) {
		$run = Invoke-Godot @('--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60', '--path', $projectDir, '--script', 'res://tests/endless_playthrough.gd')
		if (-not (Report 'endless_playthrough' $run 'PLAYTEST')) { $failed += 'endless_playthrough' }
	}
	if (Test-Path (Join-Path $projectDir 'tests/balance_sim.gd')) {
		$run = Invoke-Godot @('--headless', '--audio-driver', 'Dummy', '--fixed-fps', '60', '--path', $projectDir, '--script', 'res://tests/balance_sim.gd', '--', 'regress') ($TimeoutSec * 3)
		if (-not (Report 'balance_regress' $run 'BALANCE|PASS')) { $failed += 'balance_regress' }
	}
}
if ($failed.Count -gt 0) {
	Write-Output "RESULT: FAILED -> $($failed -join ', ')"
	exit 1
}
Write-Output 'RESULT: ALL PASS'
exit 0
