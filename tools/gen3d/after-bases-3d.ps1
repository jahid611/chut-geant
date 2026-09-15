# Attend la fin de l'enchainement nounours + meubles (TOUT FINI dans after-images.log), puis
# passe en 3D les 6 bases et la bibliotheque. ComfyUI est deja en mode 3D a ce moment-la. Detache.
$d = $PSScriptRoot
$root = 'C:\Users\jahidsyd\chut-geant'
$log = Join-Path $d 'after-bases.log'
"$(Get-Date -Format HH:mm:ss) attente de la fin des meubles" | Set-Content $log
for ($i = 0; $i -lt 2880; $i++) {
    if ((Test-Path "$d\after-images.log") -and ((Get-Content "$d\after-images.log" -Raw) -match 'TOUT FINI')) { break }
    Start-Sleep -Seconds 5
}
$jobs = @()
foreach ($b in 'boite-chaussures', 'pantoufle', 'boite-mouchoirs', 'boite-cereales', 'tiroir', 'carton') {
    if (Test-Path "$root\assets\concepts\bases\$b.png") { $jobs += "base-$b=assets/concepts/bases/$b.png" }
}
if (Test-Path "$root\assets\concepts\meubles\bibliotheque.png") { $jobs += 'bibliotheque=assets/concepts/meubles/bibliotheque.png' }
"$(Get-Date -Format HH:mm:ss) 3D de : $($jobs -join ', ')" | Add-Content $log
if ($jobs.Count -gt 0) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$d\job3d.ps1" @jobs
}
"$(Get-Date -Format HH:mm:ss) TOUT FINI" | Add-Content $log
