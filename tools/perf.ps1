# Runs the MAWLINGS performance bench (tests/perf_bench.gd) in a real window
# (never --headless: nothing would render) and collects the PERF lines.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/perf.ps1 [-Quick] [-Only worst,menu] [-Seconds 20] [-Out perf.txt]
#   -Quick    only worst case, calm start and menu (no ablations)
#   The game applies its quality tier (desktop = HIGH: MSAA 2x); 'worst_noaa'
#   measures like stage 06 (no MSAA), 'worst_loot1000' a long run with 1000 loot crystals.
#   -Only     run only the named variants (see $variants below)
#   -Seconds  measuring time of the worst case; ablations use half of it
#   -Out      also write the collected lines to this file
# Values are desktop values of this machine, not Android values.
param(
	[switch]$Quick,
	[string[]]$Only = @(),
	[double]$Seconds = 20,
	[string]$Out = ''
)
$godotExe = 'C:\Users\vrxby\Documents\Codex\Godot\Godot_v4.7.2-stable_win64_console.exe'
$projectDir = Split-Path -Parent $PSScriptRoot
# Game windows open on the secondary (portrait) monitor so they do not disturb
# work on the main screen. Override with $env:MAWLINGS_SCREEN (Godot screen index).
$screen = if ($env:MAWLINGS_SCREEN) { $env:MAWLINGS_SCREEN } else { '1' }
$half = [Math]::Max(5, [Math]::Round($Seconds / 2))

# name -> bench arguments
$variants = [ordered]@{
	'worst'          = @('scene=worst', "secs=$Seconds")
	'calm'           = @('scene=calm', "secs=$half")
	'menu'           = @('scene=menu', "secs=$half")
	'menu2d'         = @('scene=menu2d', "secs=$half")
	'no_units'       = @('scene=worst', "secs=$half", 'off=units')
	'no_shadows'     = @('scene=worst', "secs=$half", 'off=shadows')
	'no_decor'       = @('scene=worst', "secs=$half", 'off=decor')
	'no_arena'       = @('scene=worst', "secs=$half", 'off=arena')
	'no_enemies'     = @('scene=worst', "secs=$half", 'off=enemies')
	'no_corpses'     = @('scene=worst', "secs=$half", 'off=corpses')
	'no_fx'          = @('scene=worst', "secs=$half", 'off=fx')
	'no_forms'       = @('scene=worst', "secs=$half", 'off=forms')
	'no_popups'      = @('scene=worst', "secs=$half", 'off=popups')
	'no_hud'         = @('scene=worst', "secs=$half", 'off=hud')
	'no_swarmcpu'    = @('scene=worst', "secs=$half", 'off=swarmcpu')
	'cap60'          = @('scene=worst', "secs=$half", 'cap=60')
	'scale70'        = @('scene=worst', "secs=$half", 'scale3d=0.7')
	'msaa2'          = @('scene=worst', "secs=$half", 'msaa=2')
	'worst_720'      = @('scene=worst', "secs=$half", 'res=720x1560')
	# Etappe 16: long run with 1000 lying loot crystals (was: 60 corpses), no MSAA (= Etappe-06 setup), tiers.
	'worst_loot1000' = @('scene=worst', "secs=$half", 'loot=1000')
	'no_loot'        = @('scene=worst', "secs=$half", 'off=loot')
	'worst_noaa'     = @('scene=worst', "secs=$half", 'msaa=0')
	'worst_medium'   = @('scene=worst', "secs=$half", 'quality=medium')
	'worst_low'      = @('scene=worst', "secs=$half", 'quality=low')
	# Etappe 08: worst case plus a full flood (160 Moorbrut, stage ~3, bites and kills).
	'flood'          = @('scene=flood', "secs=$Seconds")
}
if ($Quick) { $Only = @('worst', 'calm', 'menu') }
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$names = @($variants.Keys)
if ($Only.Count -gt 0) { $names = $names | Where-Object { $Only -contains $_ } }

$lines = @()
foreach ($name in $names) {
	$benchArgs = $variants[$name]
	$job = Start-Job -ScriptBlock {
		param($exe, $dir, $extra, $scr)
		& $exe --screen $scr --audio-driver Dummy --path $dir --script 'res://tests/perf_bench.gd' -- @extra 2>&1 | ForEach-Object { "$_" }
	} -ArgumentList $godotExe, $projectDir, $benchArgs, $screen
	if (Wait-Job $job -Timeout ([int]($Seconds * 2 + 90))) {
		$output = @(Receive-Job $job)
		$perf = @($output | Where-Object { $_ -match '^PERF' })
		$errors = @($output | Where-Object { $_ -cmatch '(SCRIPT )?ERROR:|Parse Error' } | Select-Object -First 3)
		if ($perf.Count -eq 0) {
			Write-Output "FAIL $name :: no PERF line"
			$output | Select-Object -Last 10 | ForEach-Object { Write-Output "  $_" }
		} else {
			$perf | ForEach-Object { Write-Output $_ }
			$lines += $perf
		}
		$errors | ForEach-Object { Write-Output "  (warn) $_" }
	} else {
		Stop-Job $job
		Get-Process -Name 'Godot_v4.7.2-stable_win64_console' -ErrorAction SilentlyContinue | Stop-Process -Force
		Write-Output "FAIL $name :: timed out"
	}
	Remove-Job $job -Force
}
if ($Out -ne '') { $lines | Set-Content -Encoding utf8 $Out }
