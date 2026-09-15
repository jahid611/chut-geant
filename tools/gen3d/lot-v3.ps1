# Lot du 15/09 (detache) : rendus d'icones depuis les modeles 3D (jouets de la collection, decors), icones FLUX
# (traînees, danses, contours), image + 3D du trampoline et des objets restants (TRELLIS 2), puis televersements
# lents une fois la file actuelle videe. Journal : tools/gen3d/lot-v3.log.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$log = 'tools\gen3d\lot-v3.log'
$B = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
$comfy = 'C:\Users\jahidsyd\creator-suite\tools\comfyui'
function Say($m) { "$(Get-Date -Format HH:mm:ss) $m" | Add-Content $log }
function StopComfy { Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; Start-Sleep 5 }
function WaitComfy { for ($i = 0; $i -lt 200; $i++) { try { Invoke-WebRequest http://127.0.0.1:8188/system_stats -UseBasicParsing -TimeoutSec 3 | Out-Null; return } catch { Start-Sleep 3 } } }
"$(Get-Date -Format HH:mm:ss) debut" | Set-Content $log
$out = 'assets\ui\boutique-envoi4'
New-Item -ItemType Directory -Force $out | Out-Null

# 1. Rendus des jouets (vraies images de la collection) et des decors deja en 3D
$renders = [ordered]@{
  'jouet-Block' = 'assets\models\lots\lisse-tout\jouet-bloc-lisse.glb'
  'jouet-Duck' = 'assets\models\lots\lisse-tout\canard-lisse.glb'
  'jouet-Dino' = 'assets\models\lots\lisse-tout\jouet-dino-lisse.glb'
  'jouet-Top' = 'assets\models\lots\lisse-tout\jouet-toupie-lisse.glb'
  'jouet-Robot' = 'assets\models\lots\lisse-tout\jouet-robot-lisse.glb'
  'jouet-Teddy' = 'assets\models\lots\lisse-tout\jouet-nounours-lisse.glb'
  'jouet-TumblerBear' = 'assets\models\lots\lisse-jouets3\jouet-ours-orange-lisse.glb'
  'jouet-EmojiBall' = 'assets\models\lots\lisse-jouets4\jouet-balle-emoji-lisse.glb'
  'jouet-Cactus' = 'assets\models\lots\lisse-jouets5\jouet-cactus-lisse.glb'
  'jouet-RingStack' = 'assets\models\lots\lisse-jouets5\jouet-pyramide-lisse.glb'
  'jouet-RockingHorse' = 'assets\models\lots\propre-cheval\jouet-cheval-propre-lisse.glb'
  'jouet-Rocket' = 'assets\models\lots\lisse-tout\jouet-fusee-lisse.glb'
  'jouet-Castle' = 'assets\models\lots\lisse-tout\jouet-chateau-lisse.glb'
  'jouet-Console' = 'assets\models\lots\lisse-tout\jouet-console-lisse.glb'
  'icone-decor-trophee' = 'assets\models\lots\tripo-boutique\lisse\boutique-trophee-lisse.glb'
  'icone-decor-dino' = 'assets\models\lots\tripo-boutique\lisse\boutique-capuche-dino-lisse.glb'
  'icone-decor-pouf' = 'assets\models\lots\trellis-boutique\lisse\decor-pouf-lisse.glb'
  'icone-decor-tipi' = 'assets\models\lots\trellis-boutique\lisse\decor-tipi-lisse.glb'
}
$car = Get-ChildItem assets\models -Recurse -Filter 'jouet-voiture*.glb' | Sort-Object { $_.Name -notmatch 'lisse' } | Select-Object -First 1
if ($car) { $renders['jouet-Car'] = $car.FullName.Substring($root.Length + 1) }
foreach ($k in $renders.Keys) {
  if (Test-Path $renders[$k]) { & $B --background --python tools/render-icon.py -- "$root\$($renders[$k])" "$root\$out\$k.png" *>> $log; Say "rendu $k" } else { Say "MANQUE $k" }
}

# 2. Icones FLUX + image du trampoline
Start-Process -FilePath "$comfy\start.bat" -WorkingDirectory $comfy -WindowStyle Minimized
WaitComfy
& node tools/gen2d/gen-lot.mjs tools/gen2d/lot-v3.json *>> $log
foreach ($n in 'icone-trainee-arc', 'icone-trainee-etoiles', 'icone-trainee-coeurs', 'icone-danse-joie', 'icone-danse-robot', 'icone-danse-toupie', 'icone-contour-dore', 'icone-contour-arc') {
  Copy-Item "assets\ui\propres\$n.png" $out -ErrorAction SilentlyContinue
}
Say 'icones FLUX finies'

# 3. 3D restante en local (TRELLIS 2)
StopComfy
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools\gen3d\comfy3d.ps1')
$o = 'assets/concepts/objets3d'
& powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen3d\job3d.ps1 "decor-trampoline=$o/3d-trampoline.png" "boutique-oreilles-lapin=$o/3d-oreilles-lapin.png" "decor-lampe-etoile=$o/3d-lampe-etoile.png" "decor-guirlande=$o/3d-guirlande.png" "decor-panneau-classement=$o/3d-panneau-classement.png" "cuisine-frigo=$o/3d-frigo.png" "cuisine-table=$o/3d-table-cuisine.png" "cuisine-chaise-haute=$o/3d-chaise-haute.png" "cuisine-plan-travail=$o/3d-plan-travail.png" "cuisine-cuisiniere=$o/3d-cuisiniere.png"
StopComfy
Say '3D finie'

# 4. Lissage, FBX et rendus d'icones des nouveaux objets
$lisse = 'assets\models\lots\trellis-v3\lisse'
New-Item -ItemType Directory -Force $lisse, 'assets\models\fbx-trellis-v3' | Out-Null
foreach ($n in 'decor-trampoline', 'boutique-oreilles-lapin', 'decor-lampe-etoile', 'decor-guirlande', 'decor-panneau-classement', 'cuisine-frigo', 'cuisine-table', 'cuisine-chaise-haute', 'cuisine-plan-travail', 'cuisine-cuisiniere') {
  if (Test-Path "assets\models\glb\$n.glb") { & $B --background --python tools/smooth-glb.py -- "assets\models\glb\$n.glb" "$lisse\$n-lisse.glb" forme 40 0.5 *>> $log }
}
& $B --background --python tools/glb2fbx.py -- $lisse 'assets\models\fbx-trellis-v3' *>> $log
$late = [ordered]@{ 'icone-oreilles-lapin' = 'boutique-oreilles-lapin'; 'icone-decor-lampe' = 'decor-lampe-etoile'; 'icone-decor-guirlande' = 'decor-guirlande' }
foreach ($k in $late.Keys) {
  $glb = "$lisse\$($late[$k])-lisse.glb"
  if (Test-Path $glb) { & $B --background --python tools/render-icon.py -- "$root\$glb" "$root\$out\$k.png" *>> $log }
}
Say 'lissage et rendus finis'

# 5. Televersements lents (apres la file en cours)
for ($i = 0; $i -lt 1440; $i++) {
  if ((Test-Path 'tools\gen3d\icone-coffre-dore.log') -and ((Get-Content 'tools\gen3d\icone-coffre-dore.log' -Raw) -match 'ICONE COFFRE DORE FINIE')) { break }
  Start-Sleep 10
}
& node tools/upload-models.mjs $out assets/ui/registry-boutique4.json "Icone du jeu CHUT" --images *>> $log
& node tools/upload-models.mjs assets/models/fbx-trellis-v3 assets/models/registry.json "Objet du jeu CHUT" *>> $log
Say 'LOT V3 FINI'
