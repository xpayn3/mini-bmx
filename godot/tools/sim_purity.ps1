# The physics core (godot/sim) must stay engine-free so it ports to Unity / consoles / mobile unchanged.
# Fails if any code line there (comments skipped) mentions the engine.  powershell -File tools/sim_purity.ps1  (from godot/)
$files = Get-ChildItem -Path sim -Recurse -Filter *.cs
$bad = $files | Select-String -Pattern '\bGodot\b|\bGD\.|GodotObject|\[GlobalClass\]|\[Export\]' -CaseSensitive |
	Where-Object { $_.Line -notmatch '^\s*//' }
if ($bad) {
	$bad | ForEach-Object { Write-Output "SIMPURITY $($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
	Write-Output "SIMPURITY FAIL"; exit 1
}
Write-Output "SIMPURITY PASS ($($files.Count) files)"
