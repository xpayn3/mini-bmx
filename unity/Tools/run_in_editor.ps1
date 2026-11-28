# Run play-mode tests inside the OPEN Unity editor (no UI clicks): drops Temp/run_tests.txt, the editor's TestTrigger
# (Assets/Runout/Editor/TestTrigger) starts the run, this waits for Logs/editor_tests.txt to say DONE and prints the
# WORLDTEST lines from the Editor.log.   powershell -File unity/Tools/run_in_editor.ps1 [-Filter WorldTests] [-Timeout 300]
param([string]$Filter = "WorldTests", [int]$Timeout = 300)
$project = Resolve-Path (Join-Path $PSScriptRoot "..")
$result = Join-Path $project "Logs\editor_tests.txt"
$editorLog = Join-Path $env:LOCALAPPDATA "Unity\Editor\Editor.log"
Remove-Item $result -ErrorAction SilentlyContinue
$logStart = (Get-Item $editorLog).Length
Set-Content -Path (Join-Path $project "Temp\run_tests.txt") -Value $Filter
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Seconds 3
    if ((Test-Path $result) -and (Select-String -Path $result -Pattern "^DONE" -Quiet)) { break }
}
if (Test-Path $result) { Get-Content $result } else { Write-Host "No result: the editor didn't pick up the trigger (not compiled yet? give it focus once)." }
$fs = [System.IO.File]::Open($editorLog, 'Open', 'Read', 'ReadWrite'); $fs.Seek($logStart, 'Begin') | Out-Null
$text = (New-Object System.IO.StreamReader($fs)).ReadToEnd(); $fs.Close()
$text -split "`n" | Where-Object { $_ -match "WORLDTEST|error CS|Exception" } | Select-Object -First 80
