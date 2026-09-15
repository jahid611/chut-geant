#!/usr/bin/env bash
# Lissage B (smooth-glb.py forme 40 0.5) de tous les modeles du jeu, puis FBX dans assets/models/fbx-lisse.
# Chaque sortie s'appelle <nom>-lisse : load-assets.mjs prefere cette version a l'originale.
# Televersement ensuite, a part : node tools/upload-models.mjs assets/models/fbx-lisse assets/models/registry.json "..."
set -u
cd "$(dirname "$0")/../.."
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
M=assets/models
OUT=$M/lots/lisse-tout
mkdir -p "$OUT" "$M/fbx-lisse"

# nom -> GLB deja reduit sous 10 000 triangles
declare -A SRC=(
  [canard]=$M/glb/canard.glb
  [jouet-bloc]=$M/glb/bloc.glb
  [jouet-fusee]=$M/glb/fusee.glb
  [jouet-chateau]=$M/lots/tripo-jouets1-140149/jouet-chateau.glb
  [jouet-console]=$M/lots/tripo-jouets1-140149/jouet-console.glb
  [jouet-dino]=$M/lots/tripo-jouets2-140754/jouet-dino.glb
  [jouet-toupie]=$M/lots/tripo-jouets2-140754/jouet-toupie.glb
  [jouet-robot]=$M/lots/tripo-robot-142402/jouet-robot.glb
  [jouet-nounours]=$M/lots/tripo-nounours-142702/jouet-nounours.glb
  [base-boite-cereales]=$M/lots/tripo-lot1-133912/base-boite-cereales.glb
  [base-boite-chaussures]=$M/lots/tripo-lot1-133912/base-boite-chaussures.glb
  [base-boite-mouchoirs]=$M/lots/tripo-lot1-133912/base-boite-mouchoirs.glb
  [base-pantoufle]=$M/lots/tripo-lot1-133912/base-pantoufle.glb
  [base-carton]=$M/lots/tripo-lot2-134007/base-carton.glb
  [base-tiroir]=$M/lots/tripo-lot2-134007/base-tiroir.glb
  [bebe-pleure]=$M/lots/tripo-lot1-133912/bebe-pleure.glb
  [bebe-corps-dort]=$M/lots/corps-dort-120326/bebe-corps-dort.glb
  [bebe-tetine]=$M/glb/bebe-tetine.glb
  [meuble-berceau]=$M/lots/tripo-lot2-134007/meuble-berceau.glb
  [meuble-commode]=$M/lots/tripo-lot2-134007/meuble-commode.glb
  [meuble-etagere]=$M/lots/tripo-lot2-134007/meuble-etagere.glb
  [meuble-mobile]=$M/lots/tripo-lot2-134007/meuble-mobile.glb
  [meuble-veilleuse]=$M/lots/tripo-veilleuse-134501/meuble-veilleuse.glb
  [meuble-bibliotheque-v2]=$M/lots/tripo-biblio-anneaux-143547/meuble-bibliotheque-v2.glb
  [meuble-anneaux]=$M/lots/tripo-biblio-anneaux-143547/meuble-anneaux.glb
)

for name in "${!SRC[@]}"; do
  src=${SRC[$name]}
  if [ ! -f "$src" ]; then echo "MANQUE $name ($src)"; continue; fi
  "$B" --background --python tools/smooth-glb.py -- "$src" "$OUT/$name-lisse.glb" forme 40 0.5 2>&1 | grep -E "^(lisse|ok)|Error" | tail -1
done
"$B" --background --python tools/glb2fbx.py -- "$OUT" "$M/fbx-lisse" 2>&1 | grep -cE "^converti" | sed 's/^/fbx convertis : /'
echo FIN
