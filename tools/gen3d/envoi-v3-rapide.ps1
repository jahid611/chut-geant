# Reprise des televersements du lot v3 avec 30 s entre deux envois (demande de l'utilisateur du 15/09 : moins de
# 90 s). Les fichiers deja au registre sont sautes. Ecrit « SUITE V3 FINIE » dans suite-v3.log pour debloquer la file.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$log = 'tools\gen3d\suite-v3.log'
$env:UPLOAD_PAUSE_S = '30'
& node tools/upload-models.mjs assets/ui/boutique-envoi4 assets/ui/registry-boutique4.json "Icone du jeu CHUT" --images *>> $log
& node tools/upload-models.mjs assets/models/fbx-trellis-v3 assets/models/registry.json "Objet du jeu CHUT" *>> $log
"$(Get-Date -Format HH:mm:ss) SUITE V3 FINIE" | Add-Content $log
