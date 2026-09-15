# Assets — chambre du géant (phase 2)

Pipeline d'un jouet : prompt FLUX (image de référence, fond blanc, objet seul, vue 3/4) → détourage
`tools/aicut.py` → image → 3D (TRELLIS 2 dans ComfyUI via `creator-suite/tools/comfyui/run3d.py`, ou
Hunyuan3D-2 portable) → GLB décimé à 9 500 faces → FBX (`tools/glb2fbx.py`) → `tools/upload-slow.mjs`.

**Suffixe de style commun à tous les prompts d'objet** (garde une direction artistique cohérente) :

> `, single isolated toy object, stylized 3D game asset, Pixar toy-story style, smooth clean shapes, bright saturated colors, soft studio lighting, three-quarter view, centered, plain pure white background, no shadow, no text`

## Jouets à voler (10)

| # | Jouet | Rareté | Porteurs | Revenu/s | Prompt (avant le suffixe) |
|---|---|---|---|---|---|
| 1 | Cube de construction | Commun | 1 | 1 | `a wooden toy building block cube with a painted letter A` |
| 2 | Canard en caoutchouc | Commun | 1 | 2 | `a yellow rubber duck bath toy` |
| 3 | Petite voiture | Commun | 1 | 3 | `a small red die-cast toy race car` |
| 4 | Dinosaure en plastique | Peu commun | 1 | 6 | `a green plastic toy t-rex dinosaur figure` |
| 5 | Toupie | Peu commun | 1 | 8 | `a colorful striped spinning top toy` |
| 6 | Robot à piles | Rare | 2 | 20 | `a retro tin wind-up toy robot with antenna` |
| 7 | Nounours | Rare | 2 | 25 | `a fluffy brown teddy bear plush with a red bow tie` |
| 8 | Fusée | Épique | 2 | 60 | `a toy rocket ship, white and red with round windows` |
| 9 | Château fort | Épique | 3 | 90 | `a small toy castle with towers and a drawbridge, plastic` |
| 10 | Console de jeu dorée | Légendaire | 3 | 250 | `a golden handheld game console toy with shiny buttons` |

Mutations (multiplicateur de revenu, appliquées en matériau/effet dans Roblox, pas de modèle en plus) :
Doré ×2, Arc-en-ciel ×5, Cosmique ×10.

## Décor de la chambre

À chercher d'abord en CC0 / Creator Store (moins de téléversements) avant de générer :
lit du géant, table de nuit + veilleuse, tapis, armoire, coffre à jouets, fenêtre avec lune, étagère.

Le géant endormi : modèle riggé nécessaire pour la main qui attrape → chercher un personnage R15 libre de droits
ou utiliser un avatar Roblox mis à l'échelle (animations natives), plutôt qu'un maillage généré non riggé.
