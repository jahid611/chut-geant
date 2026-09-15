# Attend la fin du lot 3D (BATCH FINI dans batch3d.log), redemarre ComfyUI a vide
# pour liberer la RAM de TRELLIS, puis lance la serie d'images FLUX. Processus detache.
$d = $PSScriptRoot
$log = Join-Path $d 'after3d.log'
"$(Get-Date -Format HH:mm:ss) attente de la fin du lot 3D" | Set-Content $log
for ($i = 0; $i -lt 1440; $i++) {
    if ((Test-Path "$d\batch3d.log") -and ((Get-Content "$d\batch3d.log" -Raw) -match 'BATCH FINI')) { break }
    Start-Sleep -Seconds 5
}
"$(Get-Date -Format HH:mm:ss) lot 3D fini, redemarrage de ComfyUI" | Add-Content $log
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 5
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$d\comfy3d.ps1")
for ($i = 0; $i -lt 100; $i++) {
    try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null; break } catch { Start-Sleep -Seconds 3 }
}
"$(Get-Date -Format HH:mm:ss) ComfyUI pret, lancement des images" | Add-Content $log
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\images-lot.ps1" 'tools/gen3d/images-lot2.json'
"$(Get-Date -Format HH:mm:ss) TOUT FINI" | Add-Content $log
