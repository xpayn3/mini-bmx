# Bakes every card picture a fresh install shows (garage, rider room, ride setup) into godot/assets/thumbs/
# so they ship with the game: a new player never waits for them. Pictures of their own changes are still made
# on their machine and cached in user://cache/thumbs.
#
# Runs the game three times (ride setup menu, garage, rider room) with BMX_BAKE_THUMBS set, on an EMPTY user
# folder (APPDATA pointed at a temp dir), so it sees exactly what a fresh install sees, not your saves.
# Re-run after bumping PartThumbs.THUMB_VER or changing how any pictured thing looks; steam/upload.ps1 runs it
# before every export.
#   .\godot\tools\bake_thumbs.ps1
param(
	[string]$Godot = "C:\Users\Luka\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$game = Split-Path -Parent $PSScriptRoot          # godot/
$out = Join-Path $game "assets\thumbs"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("runout_bake_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $out, $tmp | Out-Null
Get-ChildItem $out -Filter *.thumb -ErrorAction SilentlyContinue | Remove-Item -Force

$saved = @{ APPDATA = $env:APPDATA; BMX_BAKE_THUMBS = $env:BMX_BAKE_THUMBS; BMX_OFFSCREEN = $env:BMX_OFFSCREEN }
try {
	$env:APPDATA = $tmp                 # a fresh install: no saves, no picture cache
	$env:BMX_BAKE_THUMBS = $out
	$env:BMX_OFFSCREEN = "1"
	$ErrorActionPreference = "Continue"   # Godot's warnings on stderr are not failures
	foreach ($pass in @(@("--bakethumbs"), @("--garage"), @("--rider"))) {
		Write-Host "bake pass: $pass"
		& $Godot --path $game -- @pass 2>&1 | Select-String -Pattern "^BAKE|SCRIPT ERROR" | ForEach-Object { Write-Host "  $_" }
		if ($LASTEXITCODE -ne 0) { Write-Warning "pass $pass exited with $LASTEXITCODE" }
	}
} finally {
	foreach ($k in $saved.Keys) {
		if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] }
	}
	Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
$files = Get-ChildItem $out -Filter *.thumb
$mb = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "Baked $($files.Count) pictures ($mb MB) into $out"
