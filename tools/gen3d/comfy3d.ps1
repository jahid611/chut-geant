# Lance ComfyUI en mode 3D (sans --lowvram : les modeles TRELLIS restent sur la RTX),
# en processus detache, sortie dans tools/gen3d/comfy3d.log.
$log = Join-Path $PSScriptRoot 'comfy3d.log'
Set-Location 'C:\Users\jahidsyd\creator-suite\tools\comfyui\ComfyUI_windows_portable'
& .\python_embeded\python.exe -s ComfyUI\main.py --windows-standalone-build --listen 127.0.0.1 --port 8188 --reserve-vram 1 --cache-none --disable-auto-launch *> $log
