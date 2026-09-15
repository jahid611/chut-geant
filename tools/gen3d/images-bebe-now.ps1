$d = $PSScriptRoot
$log = Join-Path $d 'images-bebe-now.log'
"$(Get-Date -Format HH:mm:ss) demarrage de ComfyUI" | Set-Content $log
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$d\comfy3d.ps1")
for ($i = 0; $i -lt 100; $i++) { try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null; break } catch { Start-Sleep -Seconds 3 } }
"$(Get-Date -Format HH:mm:ss) ComfyUI pret, pieces du bebe" | Add-Content $log
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\images-lot.ps1" 'tools/gen3d/images-lot4.json'
"$(Get-Date -Format HH:mm:ss) TOUT FINI" | Add-Content $log
