# Armes récupérées dans la boîte à outils Roblox

Import du 15/09/2026, dans `ServerStorage.WeaponModels.<id>`, rangées comme des `Tool`.

Traitement à l'import :
- scripts et objets non géométriques supprimés ;
- pièces non ancrées, `Massless`, sans collision ;
- une pièce `Handle` (la plus grosse si aucune ne s'appelait déjà ainsi), les autres soudées dessus ;
- plus grande dimension mise à la taille cible.

Les ids reprennent ceux de `src/shared/CatalogWeapons.luau` quand ils existent.

| id | Nom proposé | assetId | Créateur | Taille (studs) | Remarque |
|---|---|---|---|---|---|
| WeaponPinkBat | Batte rose | 16428159315 | Alika0946 | 0,4 × 4,5 × 0,4 | recolorée en rose (textures retirées) |
| WeaponFlySwatter | Tapette à mouche | 3742825376 | Sherpshooter | 1,2 × 0,1 × 4,0 | |
| WeaponPillow | Oreiller | 8528688194 | GabeWill92 | 3,5 × 0,7 × 1,3 | scripts retirés |
| WeaponFoamSword | Épée en mousse | 8734456469 | Noobboi12312 | 0,8 × 4,5 × 1,2 | |
| WeaponSlipper | Chausson géant | 139435861290340 | IMCOOL08972 | 1,4 × 0,4 × 3,0 | scripts retirés |
| WeaponWaterGun | Pistolet à eau | 105620290079728 | 3mve6 | 3,0 × 1,9 × 0,6 | scripts retirés |
| WeaponSqueakyHammer | Marteau qui couine | 10478060763 | GOLWOB | 2,1 × 1,0 × 4,0 | |
| WeaponMagicWand | Baguette magique | 10435246486 | 0x1xKs | 0,2 × 3,5 × 0,2 | |

Modèles de rechange, importés mais pas au catalogue :

| id | Nom proposé | assetId | Créateur | Taille (studs) |
|---|---|---|---|---|
| WeaponBugSwatter | Tapette à insectes | 16304119158 | Stephkinzfitchy | 0,8 × 4,0 × 0,1 |
| WeaponToyHammer | Marteau jouet | 302322242 | Dolly_Dust | 2,7 × 1,6 × 4,0 |
| WeaponFryingPan | Poêle en plastique | 593457728 | memothelemoo | 3,5 × 0,6 × 2,1 |

Rien n'a été vérifié visuellement : l'orientation de la prise en main (`Grip`) est à régler à la première capture en jeu.
