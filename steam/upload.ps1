# Export the Windows build and upload it to Steam (SteamPipe).
#   .\steam\upload.ps1 -User <steam build account>            # export + upload
#   .\steam\upload.ps1 -SkipExport -User <account>              # upload the last export
#   .\steam\upload.ps1 -ExportOnly                              # just export to build\steam\windows
# Needs: Godot .NET export templates installed, and steamcmd (Steamworks SDK > tools\ContentBuilder\builder\steamcmd.exe,
# or https://developer.valvesoftware.com/wiki/SteamCMD) at $SteamCmd. Steam Guard asks for a code the first time.
param(
	[string]$User = "",
	[switch]$SkipExport,
	[switch]$ExportOnly,
	[string]$Godot = "C:\Users\Luka\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe",
	[string]$SteamCmd = "C:\steamworks_sdk\tools\ContentBuilder\builder\steamcmd.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "build\steam\windows"

if (-not $SkipExport) {
	if (Test-Path $out) { Remove-Item -Recurse -Force $out }
	New-Item -ItemType Directory -Force $out | Out-Null
	Push-Location (Join-Path $root "godot")
	& $Godot --headless --path . --export-release "Windows Desktop" "$out\Runout.exe"
	$code = $LASTEXITCODE
	Pop-Location
	if ($code -ne 0 -or -not (Test-Path "$out\Runout.exe")) { throw "Godot export failed ($code)" }
	Get-ChildItem $out -Recurse -Filter *.pdb | Remove-Item -Force
	Write-Host "Exported to $out"
}
if ($ExportOnly) { exit 0 }
if ($User -eq "") { throw "Give -User <steam account with build rights>" }
if (-not (Test-Path $SteamCmd)) { throw "steamcmd not found at $SteamCmd (pass -SteamCmd)" }
& $SteamCmd +login $User +run_app_build (Join-Path $PSScriptRoot "scripts\app_build.vdf") +quit
if ($LASTEXITCODE -ne 0) { throw "steamcmd upload failed ($LASTEXITCODE)" }
Write-Host "Uploaded. Steamworks > SteamPipe > Builds: set the build live on a branch."
