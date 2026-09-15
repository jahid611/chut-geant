# Releve RAM / fichier d'echange / VRAM toutes les 10 s pendant 30 min, dans tools/gen3d/ram.log.
$log = Join-Path $PSScriptRoot 'ram.log'
Remove-Item $log -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 180; $i++) {
    $os = Get-CimInstance Win32_OperatingSystem
    $page = (Get-CimInstance Win32_PageFileUsage | Measure-Object CurrentUsage -Sum).Sum
    $py = (Get-Process python -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum
    $v = nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits
    "$(Get-Date -Format HH:mm:ss) libre=$([math]::Round($os.FreePhysicalMemory/1MB,1))Go echange=${page}Mo python=$([math]::Round($py/1GB,1))Go vram=${v}Mo" | Add-Content $log
    Start-Sleep -Seconds 10
}
