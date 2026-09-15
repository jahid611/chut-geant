# Enchaine : attendre la fin des images FLUX, redemarrer ComfyUI a vide (FLUX dehors),
# puis generer en 3D tous les jouets passes en argument (nom=image). Processus detache.
#   powershell -File tools/gen3d/batch3d.ps1 bloc=assets/concepts/jouet-bloc.png ...
$d = $PSScriptRoot
$log = Join-Path $d 'batch3d.log'
"$(Get-Date -Format HH:mm:ss) attente des images" | Set-Content $log
for ($i = 0; $i -lt 360; $i++) {
    if ((Test-Path "$d\images.log") -and ((Get-Content "$d\images.log" -Raw) -match 'IMAGES FINIES')) { break }
    Start-Sleep -Seconds 5
}
"$(Get-Date -Format HH:mm:ss) images finies, redemarrage de ComfyUI" | Add-Content $log
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 5
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$d\comfy3d.ps1")
"$(Get-Date -Format HH:mm:ss) ComfyUI relance, generation 3D" | Add-Content $log
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\job3d.ps1" @args
"$(Get-Date -Format HH:mm:ss) BATCH FINI" | Add-Content $log
