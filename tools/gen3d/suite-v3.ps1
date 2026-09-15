# Suite du lot v3 apres la pause de la 3D (15/09) : lissage + FBX + rendus d'icones des objets deja generes,
# puis televersements lents (icones de boutique-envoi4, puis modeles). Detache ; journal tools/gen3d/suite-v3.log.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$log = 'tools\gen3d\suite-v3.log'
$B = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
function Say($m) { "$(Get-Date -Format HH:mm:ss) $m" | Add-Content $log }
"$(Get-Date -Format HH:mm:ss) debut" | Set-Content $log
$out = 'assets\ui\boutique-envoi4'
$lisse = 'assets\models\lots\trellis-v3\lisse'
$fbx = 'assets\models\fbx-trellis-v3'
New-Item -ItemType Directory -Force $out, $lisse, $fbx | Out-Null
foreach ($n in 'decor-trampoline', 'boutique-oreilles-lapin', 'decor-lampe-etoile', 'decor-guirlande', 'decor-panneau-classement', 'cuisine-frigo', 'cuisine-table', 'cuisine-chaise-haute', 'cuisine-plan-travail', 'cuisine-cuisiniere') {
  if ((Test-Path "assets\models\glb\$n.glb") -and -not (Test-Path "$lisse\$n-lisse.glb")) {
    & $B --background --python tools/smooth-glb.py -- "assets\models\glb\$n.glb" "$lisse\$n-lisse.glb" forme 40 0.5 *>> $log
    Say "lisse $n"
  }
}
& $B --background --python tools/glb2fbx.py -- $lisse $fbx *>> $log
$late = [ordered]@{ 'icone-oreilles-lapin' = 'boutique-oreilles-lapin'; 'icone-decor-lampe' = 'decor-lampe-etoile'; 'icone-decor-guirlande' = 'decor-guirlande' }
foreach ($k in $late.Keys) {
  $glb = "$lisse\$($late[$k])-lisse.glb"
  if ((Test-Path $glb) -and -not (Test-Path "$out\$k.png")) { & $B --background --python tools/render-icon.py -- "$root\$glb" "$root\$out\$k.png" *>> $log; Say "rendu $k" }
}
& node tools/upload-models.mjs $out assets/ui/registry-boutique4.json "Icone du jeu CHUT" --images *>> $log
& node tools/upload-models.mjs $fbx assets/models/registry.json "Objet du jeu CHUT" *>> $log
Say 'SUITE V3 FINIE'
