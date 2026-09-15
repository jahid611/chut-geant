# Genere les images de reference des jouets (FLUX via ComfyUI deja lance), en processus detache.
# Sortie dans tools/gen3d/images.log. Saute les images deja presentes.
$log = Join-Path $PSScriptRoot 'images.log'
$out = 'C:\Users\jahidsyd\chut-geant\assets\concepts'
$sfx = ', single isolated toy object, stylized 3D game asset, Pixar toy-story style, smooth clean shapes, bright saturated colors, soft studio lighting, three-quarter view, centered, plain pure white background, no shadow, no text'
$toys = [ordered]@{
    'bloc'    = 'a wooden toy building block cube with a painted letter A'
    'voiture' = 'a small red die-cast toy race car'
    'dino'    = 'a green plastic toy t-rex dinosaur figure'
    'toupie'  = 'a colorful striped spinning top toy'
    'robot'   = 'a retro tin wind-up toy robot with antenna'
    'nounours'= 'a fluffy brown teddy bear plush with a red bow tie'
    'fusee'   = 'a toy rocket ship, white and red with round windows'
    'chateau' = 'a small toy castle with towers and a drawbridge, plastic'
    'console' = 'a golden handheld game console toy with shiny buttons'
}
"$(Get-Date -Format HH:mm:ss) debut images" | Set-Content $log
foreach ($name in $toys.Keys) {
    $file = Join-Path $out "jouet-$name.png"
    if (Test-Path $file) { "$name deja la" | Add-Content $log; continue }
    node C:\Users\jahidsyd\creator-suite\tools\imagegen.mjs ($toys[$name] + $sfx) --out $file --w 1024 --h 1024 *> $null
    "$(Get-Date -Format HH:mm:ss) image $name : $(Test-Path $file)" | Add-Content $log
}
"$(Get-Date -Format HH:mm:ss) IMAGES FINIES" | Add-Content $log
