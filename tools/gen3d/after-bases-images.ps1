# Attend la fin de la 3D des bases (TOUT FINI dans after-bases.log), redemarre ComfyUI a vide
# (la RAM de TRELLIS dehors), puis genere les pieces du bebe D avec FLUX. Detache.
$d = $PSScriptRoot
$log = Join-Path $d 'after-bases-images.log'
"$(Get-Date -Format HH:mm:ss) attente de la fin des bases" | Set-Content $log
for ($i = 0; $i -lt 4320; $i++) {
    if ((Test-Path "$d\after-bases.log") -and ((Get-Content "$d\after-bases.log" -Raw) -match 'TOUT FINI')) { break }
    Start-Sleep -Seconds 5
}
"$(Get-Date -Format HH:mm:ss) bases finies, redemarrage de ComfyUI" | Add-Content $log
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 5
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$d\comfy3d.ps1")
for ($i = 0; $i -lt 100; $i++) {
    try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null; break } catch { Start-Sleep -Seconds 3 }
}
"$(Get-Date -Format HH:mm:ss) ComfyUI pret, pieces du bebe" | Add-Content $log
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\images-lot.ps1" 'tools/gen3d/images-lot4.json'
"$(Get-Date -Format HH:mm:ss) TOUT FINI" | Add-Content $log
