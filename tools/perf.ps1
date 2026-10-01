# Horde Hunters performance bench (Etappe 4 Teil D): runs tests/perf_bench.gd in a
# real window (never --headless: nothing would render) for each hero and collects
# the PERF lines. Reports land in previews/perf_<hero>.txt (or -Tag: perf_<hero>_<tag>.txt).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/perf.ps1
#          [-Heroes brann,boxer] [-Seconds 30] [-Enemies 200] [-Quality high|medium|low]
#          [-ClearCache] [-Tag before] [-Extra 'res=720x1280','overlay=off']
# Values are desktop values of this machine, not S25 values (see the report header).
param(
	[string[]]$Heroes = @('brann', 'boxer'),
	[double]$Seconds = 30,
	[int]$Enemies = 200,
	[string]$Quality = '',
	[switch]$ClearCache,
	[string]$Tag = '',
	[string[]]$Extra = @()
)
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
$screen = if ($env:HH_SCREEN) { $env:HH_SCREEN } else { '1' }
$Heroes = @($Heroes | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Extra = @($Extra | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

foreach ($hero in $Heroes) {
	$name = if ($Tag -ne '') { "perf_${hero}_$Tag" } else { "perf_$hero" }
	$benchArgs = @("hero=$hero", "secs=$Seconds", "enemies=$Enemies", "out=res://previews/$name.txt") + $Extra
	if ($Quality -ne '') { $benchArgs += "quality=$Quality" }
	if ($ClearCache) { $benchArgs += 'cache=clear' }
	$job = Start-Job -ScriptBlock {
		param($exe, $dir, $extra, $scr)
		& $exe --screen $scr --audio-driver Dummy --path $dir --script 'res://tests/perf_bench.gd' -- @extra 2>&1 | ForEach-Object { "$_" }
	} -ArgumentList $godotExe, $projectDir, $benchArgs, $screen
	if (Wait-Job $job -Timeout ([int]($Seconds * 2 + 120))) {
		$output = @(Receive-Job $job)
		$perf = @($output | Where-Object { $_ -match '^PERF' })
		$errors = @($output | Where-Object { $_ -cmatch '(SCRIPT )?ERROR:|Parse Error' } | Select-Object -First 5)
		if ($perf.Count -eq 0) {
			Write-Output "FAIL $hero :: no PERF line"
			$output | Select-Object -Last 15 | ForEach-Object { Write-Output "  $_" }
		} else {
			$perf | ForEach-Object { Write-Output $_ }
			Write-Output "  -> previews/$name.txt"
		}
		$errors | ForEach-Object { Write-Output "  (warn) $_" }
	} else {
		Stop-Job $job
		Write-Output "FAIL $hero :: timed out"
	}
	Remove-Job $job -Force
}
