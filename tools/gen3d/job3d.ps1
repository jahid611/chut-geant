# Attend que ComfyUI reponde, puis genere chaque jouet passe en argument (nom=image),
# sortie dans tools/gen3d/job3d.log.
#   powershell -File tools/gen3d/job3d.ps1 canard=assets/concepts/jouet-canard.png
$log = Join-Path $PSScriptRoot 'job3d.log'
"$(Get-Date -Format HH:mm:ss) attente de ComfyUI" | Set-Content $log
for ($i = 0; $i -lt 200; $i++) {
    try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null; break } catch { Start-Sleep -Seconds 3 }
}
Set-Location 'C:\Users\jahidsyd\chut-geant'
foreach ($pair in $args) {
    $name, $image = $pair -split '=', 2
    "$(Get-Date -Format HH:mm:ss) debut $name" | Add-Content $log
    & node tools/toy3d.mjs $image $name *>> $log
    "$(Get-Date -Format HH:mm:ss) fin $name (code $LASTEXITCODE)" | Add-Content $log
}
"$(Get-Date -Format HH:mm:ss) TOUT FINI" | Add-Content $log
