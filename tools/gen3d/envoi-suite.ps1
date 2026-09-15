# Suite des televersements (un seul flux, 90 s entre deux envois) : 5 icones refaites, puis les objets 3D locaux
# deja generes (TRELLIS 2) apres lissage B et conversion FBX.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$log = 'tools\gen3d\envoi-suite.log'
"$(Get-Date -Format HH:mm:ss) icones" | Set-Content $log
& node tools/upload-models.mjs assets/ui/boutique-envoi2 assets/ui/registry-boutique2.json "Icone du jeu CHUT" --images *>> $log
$B = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
foreach ($name in 'boutique-ventouse', 'decor-pouf', 'decor-tipi') {
    & $B --background --python tools/smooth-glb.py -- "assets\models\glb\$name.glb" "assets\models\lots\trellis-boutique\lisse\$name-lisse.glb" forme 40 0.5 *>> $log
}
& $B --background --python tools/glb2fbx.py -- 'assets\models\lots\trellis-boutique\lisse' 'assets\models\fbx-trellis' *>> $log
& node tools/upload-models.mjs assets/models/fbx-trellis assets/models/registry.json "Objet de la boutique du jeu CHUT" *>> $log
"$(Get-Date -Format HH:mm:ss) ENVOI SUITE FINI" | Add-Content $log
