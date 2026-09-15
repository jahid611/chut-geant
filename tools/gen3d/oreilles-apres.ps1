# Oreilles de lapin en 3D locale (plus assez de credits Tripo) : attend la fin du lot boutique-3d, puis TRELLIS 2.
$root = 'C:\Users\jahidsyd\chut-geant'
$d = Join-Path $root 'tools\gen3d'
for ($i = 0; $i -lt 1440; $i++) {
    if ((Test-Path "$d\lot-boutique-3d.log") -and ((Get-Content "$d\lot-boutique-3d.log" -Raw) -match 'LOT FINI')) { break }
    Start-Sleep -Seconds 10
}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$d\job3d.ps1" "boutique-oreilles-lapin=assets/concepts/objets3d/3d-oreilles-lapin.png"
"$(Get-Date -Format HH:mm:ss) OREILLES FINIES" | Add-Content "$d\lot-boutique-3d.log"
