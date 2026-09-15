# Icone « Coffre dore » = rendu de notre coffre dore 3D (un seul visuel par chose), televersee apres les envois en
# cours (jamais deux flux de televersement en parallele).
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$B = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
$log = 'tools\gen3d\icone-coffre-dore.log'
& $B --background --python tools/render-icon.py -- "$root\assets\models\lots\tripo-boutique\lisse\boutique-coffre-dore-lisse.glb" "$root\assets\ui\boutique-envoi3\coffre-dore.png" *> $log
for ($i = 0; $i -lt 720; $i++) {
    if ((Test-Path 'tools\gen3d\envoi-suite.log') -and ((Get-Content 'tools\gen3d\envoi-suite.log' -Raw) -match 'ENVOI SUITE FINI')) { break }
    Start-Sleep -Seconds 10
}
& node tools/upload-models.mjs assets/ui/boutique-envoi3 assets/ui/registry-boutique3.json "Icone du jeu CHUT" --images *>> $log
"ICONE COFFRE DORE FINIE" | Add-Content $log
