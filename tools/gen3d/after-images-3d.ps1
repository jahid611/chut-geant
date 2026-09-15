# Attend la fin de la serie d'images (LOT FINI), genere l'image du nounours v2 tant que FLUX
# est charge, redemarre ComfyUI a vide puis passe en 3D le nounours et les meubles. Detache.
$d = $PSScriptRoot
$log = Join-Path $d 'after-images.log'
"$(Get-Date -Format HH:mm:ss) attente de la fin des images" | Set-Content $log
for ($i = 0; $i -lt 1440; $i++) {
    if ((Test-Path "$d\images-lot.log") -and ((Get-Content "$d\images-lot.log" -Raw) -match 'LOT FINI')) { break }
    Start-Sleep -Seconds 5
}
Start-Sleep -Seconds 3
"$(Get-Date -Format HH:mm:ss) images finies, image du nounours v2" | Add-Content $log
Copy-Item "$d\images-lot.log" "$d\images-lot2-final.log" -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\images-lot.ps1" 'tools/gen3d/images-lot3.json'

"$(Get-Date -Format HH:mm:ss) redemarrage de ComfyUI pour la 3D" | Add-Content $log
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 5
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$d\comfy3d.ps1")

$jobs = @('nounours=assets/concepts/jouet-nounours-v2.png')
foreach ($m in 'berceau', 'mobile', 'commode', 'veilleuse', 'coffre', 'etagere', 'hochet') {
    if (Test-Path "C:\Users\jahidsyd\chut-geant\assets\concepts\meubles\$m.png") { $jobs += "$m=assets/concepts/meubles/$m.png" }
}
"$(Get-Date -Format HH:mm:ss) 3D de : $($jobs -join ', ')" | Add-Content $log
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\job3d.ps1" @jobs
"$(Get-Date -Format HH:mm:ss) TOUT FINI" | Add-Content $log
