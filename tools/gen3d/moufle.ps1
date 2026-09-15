$root = 'C:\Users\jahidsyd\chut-geant\assets\concepts\bebe\pieces'
$log = Join-Path $PSScriptRoot 'moufle.log'
$style = ', 3D Pixar animated movie style, soft studio lighting, isolated on plain pure white background, no text'
$p1 = 'a single giant cute baby arm reaching forward to grab, the hand covered by a fuzzy light-green dinosaur mitten with a small row of soft rounded spikes and two little black dot eyes, plump wrist, onesie sleeve, three-quarter view' + $style
$p2 = 'a chubby cute baby hand wearing a round light-green dinosaur mitten shaped like a dino head with tiny white felt teeth, open like a mouth ready to grab, soft green sleeve cuff, side three-quarter view' + $style
"$(Get-Date -Format HH:mm:ss) debut moufles" | Set-Content $log
node C:\Users\jahidsyd\creator-suite\tools\imagegen.mjs $p1 --out "$root\moufle-a.png" --w 1024 --h 1024 *> $null
"$(Get-Date -Format HH:mm:ss) moufle-a : $(Test-Path "$root\moufle-a.png")" | Add-Content $log
node C:\Users\jahidsyd\creator-suite\tools\imagegen.mjs $p2 --out "$root\moufle-b.png" --w 1024 --h 1024 *> $null
"$(Get-Date -Format HH:mm:ss) moufle-b : $(Test-Path "$root\moufle-b.png")" | Add-Content $log
"$(Get-Date -Format HH:mm:ss) MOUFLES FINIES" | Add-Content $log
