# Headless test of the procedural world (Assets/Runout/Tests/PlayMode/WorldTests.cs): builds the World scene from its seed,
# rides it 20 s, checks the physics stays finite and on the ground, checks streaming, saves screenshots to unity/Logs/world_*.png.
# Only one Unity may have a project open: this refuses while the editor has it open (close the editor first, or run the
# test from the editor's own Test Runner window instead). Never starts Unity Hub.
#   powershell -File unity/Tools/test_world.ps1 [-Filter WorldTests]
param([string]$Filter = "WorldTests")

$ErrorActionPreference = "Stop"
$unity = "C:\Program Files\Unity\Hub\Editor\6000.3.10f1\Editor\Unity.exe"
$project = Resolve-Path (Join-Path $PSScriptRoot "..")
$logs = Join-Path $project "Logs"
New-Item -ItemType Directory -Force $logs | Out-Null

# one Unity per project: the editor holds Temp/UnityLockfile while it has the project open
$lock = Join-Path $project "Temp\UnityLockfile"
$open = $false
if (Test-Path $lock) {
    try { $f = [System.IO.File]::Open($lock, 'Open', 'ReadWrite', 'None'); $f.Close() } catch { $open = $true }
}
if ($open) {
    Write-Host "Unity already has $project open. Close the editor first (or run '$Filter' from its Test Runner window)." -ForegroundColor Yellow
    exit 2
}

$results = Join-Path $logs "world_test.xml"
$log = Join-Path $logs "world_test.log"
Remove-Item $results, $log -ErrorAction SilentlyContinue
Write-Host "Running $Filter headless (first run imports the project: slow once)..."
$t0 = Get-Date
& $unity -batchmode -projectPath $project -runTests -testPlatform PlayMode -testFilter $Filter -testResults $results -logFile $log | Out-Null
$code = $LASTEXITCODE
$secs = [int]((Get-Date) - $t0).TotalSeconds

if (Test-Path $log) { Select-String -Path $log -Pattern "WORLDTEST|error CS|Exception" | ForEach-Object { $_.Line } | Select-Object -First 30 }
if (Test-Path $results) {
    [xml]$x = Get-Content $results
    $run = $x.'test-run'
    Write-Host ("RESULT {0}: {1} passed, {2} failed ({3} s)" -f $run.result, $run.passed, $run.failed, $secs)
    foreach ($c in $x.SelectNodes("//test-case[@result='Failed']")) { Write-Host ("FAILED {0}: {1}" -f $c.name, $c.failure.message.'#cdata-section') -ForegroundColor Red }
} else {
    Write-Host "No results (exit $code): see $log" -ForegroundColor Red
}
Get-ChildItem $logs -Filter "world_*.png" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("SHOT " + $_.FullName) }
exit $code
