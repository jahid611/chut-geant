# Enchaine, en processus detache (les taches de fond de Claude Code sont tuees quand la memoire manque) :
# 1. les icones manquantes du lot boutique (ComfyUI FLUX deja lance) ;
# 2. redemarrage de ComfyUI en mode 3D (TRELLIS 2) ;
# 3. les objets 3D faits en local (repartition convenue : l'utilisateur fait les autres sur Tripo).
# Sorties : assets/ui/propres/*.png, assets/models/glb/<nom>.glb ; journal tools/gen3d/lot-boutique-3d.log.
$root = 'C:\Users\jahidsyd\chut-geant'
$d = Join-Path $root 'tools\gen3d'
$log = Join-Path $d 'lot-boutique-3d.log'
Set-Location $root
"$(Get-Date -Format HH:mm:ss) icones a refaire" | Set-Content $log
& node tools/gen2d/gen-lot.mjs tools/gen2d/lot-boutique.json *>> $log
"$(Get-Date -Format HH:mm:ss) icones finies, ComfyUI en mode 3D" | Add-Content $log
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'ComfyUI\\main.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 5
Start-Process powershell -WindowStyle Minimized -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$d\comfy3d.ps1")
$o = 'assets/concepts/objets3d'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\job3d.ps1" `
    "boutique-ventouse=$o/3d-ventouse.png" `
    "decor-pouf=$o/3d-pouf.png" `
    "decor-tipi=$o/3d-tipi.png" `
    "decor-lampe-etoile=$o/3d-lampe-etoile.png" `
    "decor-guirlande=$o/3d-guirlande.png" `
    "decor-panneau-classement=$o/3d-panneau-classement.png" `
    "cuisine-frigo=$o/3d-frigo.png" `
    "cuisine-table=$o/3d-table-cuisine.png" `
    "cuisine-chaise-haute=$o/3d-chaise-haute.png" `
    "cuisine-plan-travail=$o/3d-plan-travail.png" `
    "cuisine-cuisiniere=$o/3d-cuisiniere.png"
"$(Get-Date -Format HH:mm:ss) LOT FINI" | Add-Content $log
