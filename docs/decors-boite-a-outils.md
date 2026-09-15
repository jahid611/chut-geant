# Décors récupérés dans la boîte à outils Roblox

Import du 15/09/2026, dans `ServerStorage.CosmeticModels.<id>`.

Traitement à l'import :
- modèles chargés par `game:GetObjects` ;
- scripts et objets non géométriques supprimés ;
- pièces ancrées ;
- plus grande dimension mise à la taille cible.

Articles du catalogue dans `src/shared/CatalogDecor.luau`.

Recherche : `search_assets`. Critères :
- style cartoon doux, cohérent avec une chambre de bébé la nuit ;
- gratuit, sans marque ni licence connue ;
- les mieux notés quand il y avait le choix.

`get_asset_details` marque tous les créateurs comme vérifiés, donc ce critère ne départage rien.

| id | Nom | assetId | Créateur | Pièces | Raison |
|---|---|---|---|---|---|
| DecorRubberDuck | Canard géant | 5274933317 | ScaIedo | 2 | 70 votes sur 70, simple et propre |
| DecorHeartPillow | Coussin cœur | 3896928441 | luvilys | 96 | coussin mignon, pastel |
| DecorStrawberryPillow | Coussin fraise | 104374457351984 | 8qnrz | 22 | coussin kawaii ; scripts retirés |
| DecorBuildingBlocks | Cubes de construction | 923170266 | Ashbashthesmash | 33 | jouets de chambre |
| DecorBunnyPlush | Lapin en peluche | 71981501165043 | Runealix73 | 12 | peluche douce ; scripts retirés |
| DecorAlpacaPlush | Alpaga en peluche | 80327557801802 | mattmatveev | 28 | peluche douce ; scripts retirés |
| DecorMusicBox | Boîte à musique | 419860083 | ToughGhost145 | 20 | 19 votes sur 20, thème du sommeil |
| DecorBeanbagBlue | Pouf bleu | 14395439176 | mattmatveev | 2 | 65 votes sur 70, léger |
| DecorBeanbagRed | Pouf rouge | 14398285853 | mattmatveev | 2 | 28 votes sur 30, léger |
| DecorBalloons | Ballons | 12921192622 | lotus_lass | 8 | fête d'enfant ; scripts retirés |
| DecorNurseryRug | Tapis de chambre | 2565059514 | ayatanaaa | 1 | tapis « nursery » |
| DecorStarString | Guirlande d'étoiles | 9320917020 | aka_TheCat | 86 | 8 votes sur 10, étoiles de nuit |
| DecorWoodenTrain | Petit train en bois | 75617876888384 | somegreen_guy | 21 | jouet classique |
| DecorStarMobile | Mobile étoilé | 4765460066 | lemongalaxyy | 10 | mobile de berceau |
| DecorSpaceMobile | Mobile de l'espace | 9263307366 | ILoveRats_EPIC | 19 | mobile de berceau |
| DecorToyShelf | Étagère à jouets | 12831486631 | obviousaIien | 221 | étagère de chambre (lourde en pièces) |
| DecorPlayTent | Tente de jeu | 8129939807 | EerieBun | 1 | 10 votes sur 10, style doux |
| DecorCartoonRocket | Fusée cartoon | 17368472239 | ArsenalPro2023ALT | 7 | jouet fusée cartoon |
| DecorBouncyCastle | Château gonflable | 8561021913 | BlueNebula10 | 205 | grand décor festif (lourd en pièces) |

**Écartés**
- « Cute Pink Valentine Teddy Bear » (132504128417039) : l'import n'a rendu aucune pièce.
- « dollhouse » (15830342790) : 1 166 pièces, trop lourd.
- « Pile of toy blocks » (Rainbow Friends) : licence d'un autre jeu.

Rien n'a été vérifié visuellement : pas de capture, le workspace n'est pas touché. Il faut une capture de contrôle avant la mise en boutique définitive.
