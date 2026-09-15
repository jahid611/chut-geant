# Icones des armes (demande du 15/09 : l'onglet Armes montrait un poids) : FLUX local + detourage, puis
# televersement lent apres la file en cours (suite-v3). Detache ; journal tools/gen3d/lot-armes.log.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$log = 'tools\gen3d\lot-armes.log'
$comfy = 'C:\Users\jahidsyd\creator-suite\tools\comfyui'
function Say($m) { "$(Get-Date -Format HH:mm:ss) $m" | Add-Content $log }
"$(Get-Date -Format HH:mm:ss) debut" | Set-Content $log
$up = $true
try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null } catch { $up = $false }
if (-not $up) {
  Start-Process -FilePath "$comfy\start.bat" -WorkingDirectory $comfy -WindowStyle Minimized
  for ($i = 0; $i -lt 200; $i++) { try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null; break } catch { Start-Sleep 3 } }
}
& node tools/gen2d/gen-lot.mjs tools/gen2d/lot-armes.json *>> $log
# ComfyUI arrete aussitot : la memoire manque sinon pour Studio et Rojo
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
$out = 'assets\ui\boutique-envoi5'
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem 'assets\ui\propres' -Filter 'icone-arme-*.png' | Copy-Item -Destination $out
Say 'icones generees'
for ($i = 0; $i -lt 1440; $i++) {
  if ((Test-Path 'tools\gen3d\suite-v3.log') -and ((Get-Content 'tools\gen3d\suite-v3.log' -Raw) -match 'SUITE V3 FINIE')) { break }
  Start-Sleep 10
}
# 30 s entre deux envois (l'utilisateur a demande moins de 90 s le 15/09)
$env:UPLOAD_PAUSE_S = '30'
& node tools/upload-models.mjs $out assets/ui/registry-armes.json "Icone du jeu CHUT" --images *>> $log
Say 'LOT ARMES FINI'
