# Televerse les modeles 3D de la boutique une fois le televersement des icones termine (jamais deux envois en
# parallele : la moderation Roblox a deja banni le compte pour des rafales). 90 s entre deux modeles.
$root = 'C:\Users\jahidsyd\chut-geant'
Set-Location $root
$iconLog = 'tools\gen2d\upload-boutique.log'
for ($i = 0; $i -lt 720; $i++) {
    if ((Test-Path $iconLog) -and ((Get-Content $iconLog -Raw) -match 'au registre')) { break }
    Start-Sleep -Seconds 10
}
& node tools/upload-models.mjs assets/models/fbx-boutique assets/models/registry.json "Objet de la boutique du jeu CHUT" *> tools/gen3d/upload-boutique3d.log
