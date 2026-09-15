# Modeles Tripo envoyes par l'utilisateur pour la boutique (15/09/2026) : reduction sous 10 000 triangles,
# lissage B (forme 40 0.5), FBX pour le televersement et rendus de controle. Processus detache.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$B = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
$src = 'assets\models\lots\tripo-boutique'
$log = 'tools\gen3d\tripo-boutique.log'
New-Item -ItemType Directory -Force "$src\lisse", 'assets\models\fbx-boutique', 'docs\captures\boutique3d' | Out-Null
"$(Get-Date -Format HH:mm:ss) debut" | Set-Content $log
foreach ($name in 'doudou-lapin', 'sac-a-dos', 'coffre-dore', 'trophee', 'capuche-dino') {
    $fbx = Get-ChildItem "$src\$name" -Filter *.fbx | Select-Object -First 1
    & $B --background --python tools/decimate-glb.py -- $fbx.FullName "$src\$name\$name-10k.glb" 9500 *>> $log
    & $B --background --python tools/smooth-glb.py -- "$src\$name\$name-10k.glb" "$src\lisse\boutique-$name-lisse.glb" forme 40 0.5 *>> $log
    & $B --background --python tools/render-model.py -- "$root\$src\lisse\boutique-$name-lisse.glb" "$root\docs\captures\boutique3d\$name.png" *>> $log
    "$(Get-Date -Format HH:mm:ss) fini $name" | Add-Content $log
}
& $B --background --python tools/glb2fbx.py -- "$src\lisse" 'assets\models\fbx-boutique' *>> $log
"$(Get-Date -Format HH:mm:ss) TRIPO BOUTIQUE FINI" | Add-Content $log
