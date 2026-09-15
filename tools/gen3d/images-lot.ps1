# Genere une serie d'images FLUX decrite dans un JSON (styles + jobs), en processus detache.
#   powershell -File tools/gen3d/images-lot.ps1 tools/gen3d/images-lot2.json
# Sortie dans tools/gen3d/images-lot.log (ANSI). Saute les images deja presentes.
param([string]$spec)
$root = 'C:\Users\jahidsyd\chut-geant'
$log = Join-Path $PSScriptRoot 'images-lot.log'
$data = Get-Content (Join-Path $root $spec) -Raw -Encoding UTF8 | ConvertFrom-Json
"$(Get-Date -Format HH:mm:ss) debut lot ($(@($data.jobs).Count) images)" | Set-Content $log
foreach ($job in $data.jobs) {
    $file = Join-Path $root $job.out
    if (Test-Path $file) { "deja la : $($job.out)" | Add-Content $log; continue }
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    $prompt = $job.prompt + $data.styles.($job.style)
    node C:\Users\jahidsyd\creator-suite\tools\imagegen.mjs $prompt --out $file --w $job.w --h $job.h *> $null
    "$(Get-Date -Format HH:mm:ss) image $($job.out) : $(Test-Path $file)" | Add-Content $log
}
"$(Get-Date -Format HH:mm:ss) LOT FINI" | Add-Content $log
