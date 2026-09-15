# CHUT ! Vole le Géant — plan

Lire ce fichier en premier à chaque reprise de session. Cocher au fur et à mesure.

## Concept

### Boutique Robux — onglet Tétines (validation en jeu en attente)

Quatre packs, séparés des achats en tétines : 2 500 pour 25 R$, 10 000 pour 79 R$,
30 000 pour 199 R$, 100 000 pour 499 R$. Les boutons restent grisés « Bientôt » tant que
leur `productId` vaut zéro dans `src/shared/RobuxProducts.luau`.

Après publication par l'utilisateur, ouvrir l'expérience dans le Creator Hub, puis
**Monétisation → Produits développeur** et créer les quatre produits aux prix ci-dessus.
Copier chaque identifiant de **produit développeur** dans le `productId` du pack correspondant,
puis déployer le code par le circuit habituel. Garder les prix `robux` affichés synchronisés avec le Hub ;
ces étiquettes sont fixes (pas de tarification régionale ou d'optimisation des prix pour ce lot).
Ne pas réutiliser un identifiant pour un autre montant : d'anciens reçus peuvent revenir.
Référence : [produits développeur Roblox](https://create.roblox.com/docs/production/monetization/developer-products).

`RobuxShopService`, chargé automatiquement par Main, est l'unique gestionnaire `ProcessReceipt`.
Il attend un joueur, un profil sauvegardable et un solde initialisé, crédite via `BaseService:AddCash`,
incrémente `robuxPurchases` et sauvegarde le solde avec `robuxReceipts` avant de confirmer l'achat.
Un échec de sauvegarde laisse le reçu en attente sans recréditer lors du prochain essai.
Le message client suit uniquement l'attribut serveur `RobuxTetinesCreditees`, après sauvegarde,
même si la boutique a été fermée. Aucun nouveau remote, aucun crédit client.

Limites du plan : historique borné aux 100 derniers reçus ; un reçu plus ancien n'est plus dédupliqué.
Les sauvegardes sont sérialisées dans un serveur, mais le DataService existant n'a pas de verrou de session
entre serveurs : les reconnexions avec chevauchement doivent être sécurisées avant une ouverture commerciale.
Avant activation : tester les reçus répétés, les pannes de sauvegarde, la reconnexion et les achats réels
sur une expérience publiée. Un achat réel n'est pas testable sur le place local non publié.

### Manches collectives (15/09/2026, implémentées, validation Studio en attente)

- Cycle serveur : attente d'un profil et de son économie, préparation 10 s, collecte **300 s**, résultat,
  pause 10 s, puis nouvelle collecte. Objectif figé au départ : **6 jouets seul, +4 par joueur supplémentaire**
  (34 à huit). Une arrivée tardive n'augmente pas cet objectif ; un départ ne le diminue pas.
- Chaque dépôt accepté dans un coffre ou un tipi ajoute une contribution au déposant. Chambre, accueil, cuisine,
  événements : même valeur, sans dépendre de la rareté. Le quatrième argument serveur `source` de `ToyDeposited`
  vaut `room` ou `stolen` : les vols entre joueurs sont exclus, y compris dans le tipi et après portage dans le sac.
  `NotifyDeposited` et `TryDeposit` prennent une source facultative (`room` par défaut pour les anciens appels).
  Restitution et rechargement de sauvegarde n'émettent pas ce signal. Aucun reçu ni deuxième chemin de consommation.
- Atteindre l'objectif ne termine pas la manche : continuer jusqu'à zéro augmente sa contribution. À l'échéance,
  le score est figé avant les paiements ; un dépôt traité à l'échéance ou après est exclu. Contributions conservées
  par UserId en cas de reconnexion sur le même serveur, jusqu'à la prochaine manche. Serveur vide : abandon sans prime.
- Prime automatique aux contributeurs présents et initialisés à la clôture, avec `c = min(contribution, 12)` :
  échec = `100c` tétines et `5c` XP ; réussite = `200c + 300` tétines et `10c + 20` XP.
  Zéro contribution = zéro prime. Aucun bonus de rang. Six dépôts réussis en solo : **1 500 tétines et 80 XP**.
  Versement par `BaseService:AddCash` et `PassService:AddXp(..., "manche")`, statistiques `roundsPlayed` / `roundsWon`
  des contributeurs payés. Pas de gain hors ligne ni de paiement rejoué au retour après la clôture.
- Argent, XP et statistiques utilisent la sauvegarde existante (une panne avant sauvegarde peut perdre un gain).
  Classement et manche restent en mémoire. Possessions, revenus, Nuits, défis, combos et records historiques persistent.
- **Périmètre réduit après critique de Claude C1-R1 à C1-R6** : aucun événement n'est annulé, aucun verrou ajouté
  au bébé. `EventService:SetPaused` saute uniquement les tirages ordinaires pendant résultat et pause. Les pièges,
  chasses et événements déjà lancés finissent normalement. À la clôture d'un échec, maman est déclenchée seulement
  si le bébé dort, qu'aucun événement ne tourne et que maman et sa porte sont présents. Sinon : bilan seul.
  Le bilan détaillé attend la fin réelle de la finale de maman, préavis compris, puis reste 6 s avant la pause.
  Réussite ou échec sans maman : résultat 6 s. Les événements ordinaires reprennent à la collecte suivante.
- Aucun nouveau remote. Attributs Workspace `MancheId`, `ManchePhase`, `MancheDebut`, `MancheFin`, `MancheObjectif`,
  `MancheProgression`, `MancheReussie`, `MancheBilanPret`, `MancheClassement`, `MancheRevision` ; instantané JSON
  cohérent avec huit premières lignes au plus. Attributs joueur `MancheId`, `MancheContribution`, `MancheRang`,
  `ManchePersonnel`, `MancheDernierResultat` (dernier versement). Publication à 2 Hz et immédiatement aux transitions.
- Barre dédiée en bas au centre, au-dessus des pouvoirs et armes : icône, progression, chrono, contribution,
  bouton local de classement. Messages de dernière minute et d'objectif atteint dans cette barre. Bilan `Ui/Modal`
  défilant, ligne personnelle même hors du top huit, montants versés. L'ouverture automatique attend la fermeture
  des autres menus, bandeaux d'événement et caméras scriptées ; le bilan reste consultable pendant la pause.
  Aucun contrôleur existant déplacé, aucune modification de caméra. Fanfare via les réglages sonores existants ;
  pulsation de réussite désactivée avec `EffetsReduits`.

**Limites reportées, à traiter dans une tâche suivante :** les coffres durablement pleins empêchent de contribuer
sans libérer de place/acheter un coffre (ou déposer dans un tipi disponible). Les joueurs sans base personnelle
ne peuvent pas contribuer : six bases selon la relecture de Claude, donc les joueurs 7 et 8 sont concernés.
Le calcul est prévu pour huit, mais **la jouabilité à huit n'est pas validée ni résolue par ce lot**.
La livraison collective de secours et l'ajout de bases sont hors de ce périmètre. Aucune chambre reconstruite.

#### Vérifications et commandes pour Claude

- `lune run test-rounds` : tests purs réussis (objectifs 1–8, limites temporelles, provenance, reconnexion par UserId,
  égalités, clôture répétée, primes, objectif dépassé et ancienne manche). Ces tests ne simulent pas le portage.
- `lune run check` : vert (sourcemap, selene, stylua, luau-lsp).
- **Aucun playtest ni capture réalisés par GPT**. Claude lance les tests par l'arbitre, puis lit les journaux
  et arrête chaque session. Pas de changement permanent des 300 secondes de production.

Appel court `eval_server_runtime` après initialisation du joueur, pour préparer un succès rapide :

```luau
local services = game:GetService("ServerScriptService").Server.Services
local round = require(services.RoundService)
local base = require(services.BaseService)
local player = game:GetService("Players"):GetPlayers()[1]
assert(round:DebugStart(12)) -- Studio seulement, 1 à 300 s ; refuse pendant sa finale maman
for _ = 1, 6 do
    base:NotifyDeposited(player, "Duck", nil, "room")
end
base:NotifyDeposited(player, "Duck", nil, "stolen") -- ne doit pas ajouter de contribution
return { fin = workspace:GetAttribute("MancheFin"), id = workspace:GetAttribute("MancheId") }
```

Lire après 0,5 s `MancheProgression` et `ManchePersonnel` (6), puis après l'échéance
`MancheDernierResultat` (1 500 tétines, 80 XP) et `MancheClassement`. Attendre côté shell entre les appels courts.
Un deuxième appel de lecture ne doit pas changer le versement. Les revenus ordinaires continuent : ne pas comparer
le solde total sans les distinguer. `NotifyDeposited` conserve ses effets historiques (stats, combo, défis, XP) :
ce script teste le signal et la manche, **pas une possession ajoutée ni le chemin réel de portage**.

Pour l'échec : `RoundService:DebugStart(3)` sans dépôt, lire les phases et vérifier maman si disponible ; recommencer
pendant `EventService:Trigger("GoldenToy")` ou `"PowerOutage"` pour constater que l'événement finit normalement,
sans deuxième maman. Faire aussi un cycle **réel de 300 s**, pause et départ suivant, puis réussite anticipée avec
dépôts supplémentaires, reconnexion avant/après clôture et serveur vide. Vérifier dépôts réels coffre/tipi/sac,
provenance volée, jouet lourd, cuisine/accueil, captures et régressions combo/défis/records/classements.
Vérifier monnaie et XP après sauvegarde/reconnexion si DataStore est disponible ; sinon persistance non vérifiée.
Captures à faire : HUD et bilan, noms longs, défi et événement simultanés, menus, réapparition et arrivée tardive.
**À tester à la main par l'utilisateur :** marche réelle, ressenti, coopération, huit joueurs et téléphone
portrait/paysage ; le banc solo ne prouve pas ces points.

### Rythme de la boucle — premier lot (15/09/2026, validation en jeu en attente)

- Chambre : remplacement 8 s après dépôt, sauf les points d'accueil à 25 s pour limiter la boucle de combo
  sans risque (20 s en cuisine), toujours un exemplaire par point.
- Furie : 3 s, recharge 20 s depuis activation, +27 studs/s, prix 750 tétines ; achats existants conservés.
- Bruit de la chambre : 8 points/s les 3 premières secondes, rampe jusqu'à 13 à 8 s ; récupération de la durée
  de course à 2 s/s sous le seuil bruyant. La plus forte contribution compte entièrement, les autres à 50 %.
  Décroissance au calme : 8 points/s, y compris sous boîte à musique (gain effectif nul). Chien : débit conservé à 13.
- Deux points d'accueil communs légers par base visés à 35–55 studs de la sortie, créés au démarrage par
  `ToySpawnService` et `WelcomePoints`, sans reconstruction. Sol/tapis vérifiés par rayon ; meubles, zones sûres,
  portes et proximité d'un autre point refusés. Aucun piège, mutation, promotion lunaire, jouet vivant ou maudit.
- Les recettes déplacent les volumes `Base` dans les intérieurs : l'origine extérieure vient donc de la
  `Destination` de l'unique porte de sortie du volume `InteriorZone` contenant la base. Une association ambiguë
  est refusée. Le tutoriel privilégie les jouets d'accueil associés à sa base ; pas d'apparition spéciale du joueur.
- La prime « Retour éclair », son interface et ses contrats de portage sont reportés dans une tâche dédiée.
  Les intervalles d'événements restent à 40–75 s.

Mesures déterministes (`lune run test-noise`, départ à zéro, vitesse 17, sans équipement ni événement) :

| Scénario | Avant | Après |
|---|---:|---:|
| Solo, marche continue jusqu'à 100 | 7,70 s | 9,81 s |
| Trois joueurs simulés, marche continue jusqu'à 100 | 2,57 s | 5,78 s |
| Solo, pic sur 12 s : 3 s marche / 3 s calme | 63 | 24 |
| Trois joueurs simulés, même scénario | 100 | 72 |

Ces simulations vérifient le calcul, pas la sensation en jeu. L'accès MCP Studio a été refusé par la politique
d'approbation de l'environnement : aucun playtest ni capture réalisés pour ce lot. Avant validation par Claude :
compter et capturer les 12 points dans les six bases, contrôler sol/collisions/trajets, mesurer la première prise
et vérifier réellement les remplacements à 8/25/20 s (chambre/accueil/cuisine), les captures, la Furie,
la boutique et la cuisine.
Marche réelle, ressenti et multijoueur : **à tester à la main par l'utilisateur**.

### Boucle générale

On est minuscule. **Un bébé géant dort dans son berceau** (choix de l'utilisateur le 14/09/2026 : tétine,
hochet, doudou, pleurs au réveil). **Look retenu : bébé D** (`assets/concepts/bebe/bebe-d.png`) — grenouillère
dino verte à capuche, bras en croix, bouche ouverte, joues rondes. Le bébé est découpé en pièces animées par tweens, pas riggé : corps sous la
couverture (respiration), tête (regarde), deux têtes yeux fermés / ouverts, main géante (attrape), tétine qui tombe. On lui vole ses jouets et on les ramène dans
sa base, où ils rapportent de l'argent en continu. Faire du bruit remplit une jauge : pleine, le géant
se réveille et traque les voleurs.

- **Boucle courte (30 s à 2 min)** : sortir de la base → se faufiler → attraper un jouet → revenir sans
  réveiller le géant.
- **Boucle moyenne** : les jouets rapportent de l'argent, qui paie les améliorations (vitesse, discrétion,
  capacité de port, sac) et les jouets plus rares.
- **Boucle longue (28 jours)** : pièces successives (chambre → cuisine → garage → école du géant),
  raretés et mutations (doré, arc-en-ciel, cosmique…), collection complète, renaissance.
- **Social** : serveurs de 6 à 8. On peut piller la base des autres (verrou temporaire à acheter). Les gros
  jouets demandent 2 ou 3 porteurs, et le bruit de l'un réveille le géant pour tout le monde.
- **Moment à clipper** : la main géante qui attrape un joueur ; le géant qui se retourne dans son sommeil.

Pourquoi : analyse de marché du 14/09/2026. Steal An Egg (1,87 M CCU) prouve la boucle collecter/voler en
petit serveur, 99 Nights et Animal Hospital la peur en coop, et l'algorithme Roblox récompense depuis
juin 2026 la rétention sur 28 jours et le jeu entre amis.

## Règles d'assets

- **Jamais de décor ni d'objets en pièces de base Studio.**
- Modèles 3D : image de référence générée par FLUX (ComfyUI, `creator-suite/tools/imagegen.mjs`), détourée
  (`tools/aicut.py`), puis image → 3D texturé avec **Hunyuan3D-2 portable** (`D:\ai\hunyuan3d`, RTX 2080 Ti).
  GLB → FBX par `tools/glb2fbx.py` (Blender), moins de 10 000 triangles par MeshPart.
- Compléments : packs gratuits libres de droits reconnus (Kenney, Quaternius, Poly Pizza en CC0) et modèles du
  Creator Store de créateurs fiables (insertion sans téléversement).
- **Téléversements Roblox uniquement par `tools/upload-slow.mjs`, en petits lots espacés** (le compte a déjà été
  banni pour une rafale). Un asset refusé n'est jamais renvoyé.
- Arrêter ComfyUI et Hunyuan3D avant un playtest Studio (mémoire).

## Phases

### Phase 0 — Mise en place
- [x] Studio ouvert sur une Baseplate vierge
- [x] Dossier projet et outillage copiés de roblox-dev (Rojo port 34874)
- [x] Rojo connecté (port 34874, sync acceptée), MCP connecté (daemon, `execute_luau` OK)
- [x] Moteur 3D principal : **TRELLIS 2 déjà installé dans ComfyUI** (`tools/toy3d.mjs <image> <nom>`,
      ~3 min par modèle une fois chargé, 9 500 faces, détourage intégré)
- [x] Hunyuan3D-2 portable décompressé dans `D:\ai\hunyuan3d\Hunyuan3D2_WinPortable` (secours ; lanceur GUI
      `RUN.bat`, modèles téléchargés au premier lancement). Ne jamais le lancer en même temps que ComfyUI (16 Go de RAM).
- [x] Premier jouet de bout en bout : canard (FLUX → TRELLIS 5 min 34, 9 486 faces → FBX → Open Cloud
      asset `71408946873237` → `InsertService:LoadAsset` dans `workspace.Jouets.Canard`, MeshPart texturé, 8 studs)
      Registre des identifiants : `assets/models/registry.json`. Envoi autorisé par l'utilisateur, `upload-models.mjs`
      fait maintenant 90 s de pause entre deux modèles et s'arrête au premier refus de modération.
      Reconnexion MCP après coupure : onglet Plugins → MCP Server → Disconnect puis Connect (daemon lancé avant).
      **Génération 3D = processus détachés** (sinon Claude Code tue tout sous 4 Go de RAM libre) :
      `Start-Process powershell -File tools/gen3d/comfy3d.ps1` puis
      `Start-Process powershell -File tools/gen3d/job3d.ps1 canard=assets/concepts/jouet-canard.png [nom=image ...]`,
      logs UTF-16 dans `tools/gen3d/*.log`. Relancer Rojo et le daemon MCP après la génération.
- [x] Place sauvegardée en fichier local : `chut-geant.rbxl` (ignoré par git, rouvrir ce fichier dans Studio)
- [x] 9 jouets 3D envoyés sur Roblox (ids dans `assets/models/registry.json`) et chargés dans
      `ServerStorage.ToyModels.<ToyId>` à l'échelle des porteurs (8 / 14 / 20 studs), pivots recentrés, orientation de
      Console et Block corrigée. Vitrine de contrôle : `workspace.Vitrine`, capture `docs/captures/vitrine-jouets.png`.
- [ ] Nounours : TRELLIS a raté la fourrure (rangé dans `assets/models/rejets`). **L'utilisateur le gère lui-même sur
      Tripo Studio** (web, 2 595 crédits ; l'API Tripo est à 0 crédit). Les GLB de Tripo web restent sur le PC du taf :
      l'extension Chrome bloque la lecture des liens signés, il faut que l'utilisateur transfère le fichier.

### Décision 3D (14/09/2026, 11 h 20)
**L'utilisateur a arrêté la 3D locale (TRELLIS) : toute la 3D restante se fait sur Tripo Studio** (web, ses crédits).
Les images de référence restent générées en local par FLUX (`assets/concepts/**`). Les enchaînements 3D ci-dessous ont
été stoppés ; seules les images des pièces du bébé ont été relancées (`tools/gen3d/images-bebe-now.ps1`).
À faire en 3D sur Tripo : nounours, 7 meubles (berceau, mobile, commode, veilleuse, coffre, étagère, hochet),
bibliothèque, 6 bases, pièces du bébé D. Les 9 jouets déjà faits par TRELLIS restent dans le jeu.

**Méthode Tripo validée sur le nounours (14/09/2026)** : l'utilisateur génère sur Tripo Studio (v3.1 Qualité Optimale,
55 crédits), exporte en GLB texture 2k, dépose dans son Drive et envoie le lien partagé. Téléchargement :
`curl -L "https://drive.usercontent.google.com/download?id=<ID>&export=download&confirm=t"` (le connecteur Drive
ne passe pas un fichier de 58 Mo). Réduction : `blender --background --python tools/decimate-glb.py -- <in.glb> <out.glb> 9500`
(1 984 544 → 9 499 triangles, fines fissures de texture visibles de près). Puis `glb2fbx.py`, `upload-models.mjs`,
`InsertService:LoadAsset`. Nounours : asset `134947548015317`, `ServerStorage.ToyModels.Teddy` (14 studs).
Page de commande pour l'utilisateur (19 objets, images à glisser dans Tripo) :
https://claude.ai/code/artifact/08cbf76c-059e-46b8-a226-04102537c834

### État au 14/09/2026, 12 h 05
- **Jeu testé en playtest** : 8 jouets apparaissent avec leur bouton « Voler », le joueur reçoit sa base, remotes créés, aucune erreur.
- **Jouets** : 10/10 dans `ServerStorage.ToyModels` (dont Teddy via Tripo).
- **Bébé** (`ServerStorage.BabyParts`) : `Pacifier` (Tripo, asset 73700170343631) et `BodySleeping` (Tripo, asset
  127087922775751, 160 studs). Images de référence retenues : `assets/concepts/bebe/pieces/corps-v2b.png` (endormi) et
  `corps-pleure.png` (même pose, qui pleure, retouche GPT Image 2.5 sur Higgsfield). Têtes réveillées et mains : 4 variantes
  chacune dans `assets/concepts/bebe/pieces/higgsfield/`, choix de l'utilisateur en attente.
- **Nouveau canal** : l'utilisateur peut glisser un GLB/FBX/ZIP directement dans Claude Code → fichier dans
  `C:\Users\jahidsyd\.claude\uploads\<session>\`. Plus besoin de Drive.
- Reste à passer dans Tripo : bébé qui pleure, 6 bases, 8 meubles (page de commande ci-dessus).

### Tripo lancé par Claude sur le Chrome du PC du taf (14/09/2026, après-midi)
Réglages : **v3.0 – Rapide & Équilibré, 10 000 polygones, texture 2K** (30 crédits l'objet). Pièges de l'interface : chaque
page neuve repasse en v3.1 ; le premier clic sur le menu des modèles ouvre une fiche « Présentation v3.1 » → survoler ailleurs,
recliquer, capture, puis `find` de l'option v3.0 ; choisir le modèle **avant** de déposer l'image. Les exports vont dans les
Téléchargements du PC du taf ; l'utilisateur les glisse ensuite dans Claude Code (`~/.claude/uploads/<session>/`).
- Reçus et traités (renommés, `decimate-glb.py`, rendus, FBX, envoi lent en cours via `tools/gen3d/upload.ps1`) :
  bebe-pleure, base-boite-chaussures, base-pantoufle, base-boite-mouchoirs, base-boite-cereales, base-tiroir, base-carton,
  meuble-berceau, meuble-mobile, meuble-commode, meuble-etagere. Planche : `docs/captures/planche-tripo-lot1-2.png`.
- Veilleuse reçue et traitée (FBX prêt, à envoyer au prochain passage de `upload-models.mjs`).
- **L'utilisateur relance lui-même sur Tripo** (PNG envoyés) : coffre (à exporter), hochet, bibliothèque, et **tous les jouets
  sauf le canard** (cube, voiture, dino, toupie, robot, fusée, château, console). À la réception : nommer `jouet-<nom>` /
  `meuble-<nom>`, `decimate-glb.py`, `glb2fbx.py`, `upload-models.mjs`, puis `node tools/load-assets.mjs` (table d'échelle
  incluse, remplace les jouets TRELLIS dans `ServerStorage.ToyModels`).

### Chambre construite par recette (14/09/2026, 14 h 45)
- **Recette rejouable** : `node tools/scene-run.mjs tools/scene/build-chambre.luau` (range l'ancienne chambre dans
  `ServerStorage.Archive`, ne détruit rien). Pièce 800 × 640 × 360 studs : sol, murs, plinthes, plafond, fenêtre + lune,
  tapis (`QuietZone`), berceau + mobile, 2 commodes + veilleuses (PointLight orange), bibliothèque v2, étagère, anneaux,
  6 bases le long du mur de face (volumes `Base`), 12 `ToySpawn` avec attribut `Rarity` + 1 légendaire sur le matelas,
  3 lattes `Creak`, 2 cachettes `HideZone`, zone `GiantRoom`, éclairage de nuit (Future, ambiance bleue lisible).
- `workspace.Geant` : modèles `Dort`, `Pleure` (caché), `Tetine`. `BabyVisualService` bascule selon `State` et fait tomber la tétine.
- `ToySpawnService` tire le jouet dans la rareté du point (attribut `Rarity`).
- Reçus : bibliothèque v2 (asset 71678755280072, remplace `DecorModels.Bookcase`), jouet à anneaux (92674271016238,
  `DecorModels.StackingRings`). Textures `assets/textures/` (papier peint nuages, parquet, tapis) en envoi lent,
  registre `assets/textures/registry.json` → à appliquer en `Texture` sur sol / murs / tapis.
- Corrections 14 h 55 (retours utilisateur) : commodes tiroirs vers le centre (-90 / +90), bibliothèque tournée de 180°,
  bébé couché sur le dos dans la longueur du berceau (`Angles(0,90°,0) * Angles(90°,0,0)`), textures posées
  (parquet `111036815924939` tuile 250, papier peint `98773939461556` tuile 320, tapis `136740012456958`).
  Tags de jeu retirés des chambres archivées, et les services ignorent les tags hors workspace (sinon 60 jouets).
  **Lampes** : l'utilisateur ne veut pas deux fois la même → champignon à gauche seulement, `DecorModels.NightLamp2`
  (autre lampe Tripo, à recevoir) à droite.
- 14 h 55 : **lissage B retenu** (`smooth-glb.py forme 40 0.5`). `tools/gen3d/lisse-tout.sh` lisse les 25 modèles du jeu
  vers `assets/models/fbx-lisse/<nom>-lisse.fbx` ; `load-assets.mjs` préfère `<nom>-lisse` au registre (voiture : alias du test B).
  Reçus : lampe créature jaune (`meuble-veilleuse2` → `NightLamp2`), coffre (`meuble-coffre` → `ToyChest`), tous deux lissés B.
  Le « hochet » envoyé est le même fichier que le jouet à anneaux (déjà `StackingRings`).
  Bébé enfoncé de 22 studs dans le matelas (hauteur du matelas par rayon, 57 studs). Baseplate rangée dans l'archive
  (sa grille transparaissait sur le parquet). Tapis : l'utilisateur en veut un plus beau → image vue de dessus (texture), pas de 3D.
- 15 h 05 : **règle utilisateur** — les objets posés subissent la gravité (rien de droit « comme un piquet »).
  `settle(model, secondes)` dans la recette : désancre, `workspace:StepPhysics` en édition, réancre (jouet à anneaux
  lâché penché → couché au sol). Orientation vérifiée objet par objet par capture de face (coffre 180°, capybara 0°,
  bibliothèque 180°, commodes ∓90°). Capybara : PointLight 3 / 90 studs, sans ombres (sinon le maillage bloque la lumière).
- 15 h 20 : **rendu réaliste** — ambiance sombre + lune (ClockTime 3, latitude 30) qui traverse murs et plafond
  (CastShadow false) pour des ombres de meubles au sol ; ColorCorrection (contraste 0.18) + Bloom léger.
  **Veilleuses = vraies lumières** : limite moteur PointLight 60 studs pour une commode de 150 → 6 sources par lampe
  (source avec ombres au-dessus + 5 lueurs sans ombre qui se chevauchent), lampe émissive (SurfaceAppearance.EmissiveStrength 3).
  Au-delà de ~6 par lampe le moteur abandonne des lumières quand elles se recouvrent à l'écran (28 → commode droite éteinte).
  Pas de source à moins de 45 studs d'un mur (disque net). Bases : tiroir 0°, pantoufle 270°, boîte de céréales redressée de 8°,
  les autres posées par gravité. Reçus : tapis lune 3D (`meuble-tapis` → `DecorModels.Rug`, remplace le cylindre),
  anneau de dentition (`meuble-hochet` → `Rattle`), envoi en file après les modèles lissés ; l'image du tapis n'est plus envoyée.
- 15 h 30 : **tapis lune 3D posé** (asset 104854208087579, écrasé à 5 studs d'épaisseur, centré z = 70, bord avant avant
  les bases ; points d'apparition posés sur le sol réel par rayon). Lattes déplacées hors du tapis.
  **Fenêtre réelle** : mur du fond percé, vitre Glass transparente, plus de boule néon ; lune du ciel Roblox
  (ClockTime 0, latitude -45, MoonAngularSize 11) dans l'axe de la fenêtre vue du sol, Atmosphere Offset 1 = ciel bleu nuit.
  La lumière de lune entre par la fenêtre : ombres des barreaux sur le tapis. **Pas de jour** : le jeu est une nuit permanente.
  Attention : `upload-models.mjs` réécrit tout le registre à chaque envoi → un envoi lancé en parallèle efface les entrées
  ajoutées entre-temps (tâche de fond qui les remet en place après le lot lissé).
- 15 h 35 : **berceau v2** (Tripo, blanc « Happy baby », couverture et oreiller ; asset 129191017681510, `DecorModels.Crib2`,
  tourné de 180° : son tour de lit plein est contre le mur et les barreaux regardent la chambre). Bébé à 80 %, couché sur
  la couverture (médiane de 9 rayons = 110 studs), tête côté oreiller. Bases reculées à z = 290.
  **Bug du pipeline : les modèles arrivent en miroir dans Roblox** (« Happy baby » lisible dans Blender sur le GLB, inversé
  dans Studio). Invisible sur les objets symétriques ; à corriger dans `glb2fbx.py` avant les prochains envois, et
  renvoyer le berceau (seul modèle avec du texte).
  Bases validées par l'utilisateur : bases où l'on entre (entrée côté chambre, collisions précises, ~60 studs, zone sûre).
  Nouvelle pantoufle à ouverture de talon : images `assets/concepts/bases/pantoufle/pantoufle-a.png` (conseillée) et `-b`,
  3D faite par l'utilisateur sur Tripo.
- 15 h 45 : **modèles lissés B chargés** (25, ids `*-lisse` au registre). Anneau de dentition (`meuble-hochet`
  130760522769810 → `Rattle`) posé par gravité entre le tapis et le berceau. **Pantoufle lapin ouverte au talon**
  (`base-pantoufle2` 93817481734891 → `BaseModels.Slipper2`, 60 studs, rotation 0 = talon côté chambre, collisions
  PreciseConvexDecomposition) remplace l'ancienne pantoufle.
  **Hypothèse du miroir réfutée** : même retourné sur X (`glb2fbx.py ... miroir`), « Happy baby » reste inversé dans
  Studio → le pipeline ne met PAS les modèles en miroir ; c'est le texte de la texture Tripo du berceau qui est à
  l'envers (ou sur la mauvaise face). Ne pas utiliser l'option `miroir` pour ça. Le berceau en place est la version
  retournée (`meuble-berceau2-lisse` 136037889914272), correcte visuellement (1er essai avec normales retournées en trop
  rejeté : vu de dedans). Tête du bébé côté bord à couronne (-X, berceau tourné à 180°), barreaux côté chambre.
- 16 h 00 : **gravité réelle**. `Workspace:StepPhysics` ne déplace rien en édition (mesuré : bébé à 55 studs au-dessus
  de la couverture malgré « posé par gravité ») → `settle(model, _, exclure, solMax)` descend l'objet par rayons jusqu'au
  premier contact sous toute son empreinte ; `solMax` ignore les appuis trop hauts (bébé : couverture + 12, pour ne pas
  rester sur les barreaux ou l'oreiller). Bébé : descente 21 studs, puis 6 studs d'enfoncement ; pantoufle : écart 0,1.
  **Ombres de contact** : image `assets/textures/ombre-contact` (Decal 84359689261234 → image 123681637407382), une tache
  douce sous chaque objet posé au sol (13). **Jouets en jeu** : `ToySpawnService.rest` les lâche 1 stud au-dessus du point,
  désancrés 1,5 s puis ancrés (sauf s'ils sont portés, attribut `CarrierUserId`) — pas encore testé en jeu.
- 16 h 50 : **intérieurs des bases** (demande utilisateur, images de référence).
  - Pantoufle : `tools/scene/build-interieur-pantoufle.luau` → étendue de fourrure sombre en dunes (terrain Grass
    78,84,96, bruit à 3 échelles, centre y = -900), lucioles qui mènent à la boîte à jouets (coffre ×70 studs, projecteur,
    étincelles, panneau « BOÎTE À JOUETS »), lumière « Retour chambre ». Les brins (Terrain.Decoration) ne se règlent pas
    par script. Zone de base renommée `Base0Pantoufle` (1er joueur servi) ; ses jouets s'exposent DANS la boîte
    (attributs `DisplayCFrame` / `DisplaySize` lus par BaseService).
  - Boîte à mouchoirs : `build-interieur-mouchoirs.luau` (x = 1600) → pièce en carton (matériau Cardboard), plafond en
    bandes de 2 studs percé d'un ovale avec lueur au-dessus, sol de feuilles et plis en tente, petites lumières au sol,
    boîte à jouets ; zone renommée `Base1Mouchoirs`.
  - Ordre des recettes : chambre → pantoufle → mouchoirs.
  - `BaseDoorService` (tag `BaseDoor`, attribut `Destination` CFrame) ; `AmbianceController` client (tag `InteriorZone`,
    attribut `Ambiance` = Pantoufle / Mouchoirs) bascule lumière, brume, ciel, étalonnage.
  - **Bug corrigé** : `workspace.FallenPartsDestroyHeight` valait -500 → le joueur mourait en entrant (intérieurs à -900)
    et réapparaissait en boucle dans sa base. La recette de la chambre le met à -3000.
  - Jouets reçus : ours culbuto (`jouet-ours-orange` 74764370726755 → `TumblerBear`), jouet musical au logo de marque
    repeint (`tools/recolor-logo.py`, `jouet-colore-rouge` → `MusicToy`) ; **ne jamais charger `jouet-colore-lisse`
    (107512102208623), il porte le logo Fisher-Price**. Koala du Drive : 1,88 M triangles, un seul modèle dans le fichier
    → à régénérer en 10 k ; le 2e jouet lourd manque.
- 16 h 52, **test en jeu** : entrée par la porte de la pantoufle OK (joueur vivant à y = -890), 4 dépôts acceptés
  dans la boîte à jouets (revenu mis à jour), entrée dans la boîte à mouchoirs OK. **Pas encore bon** : les jouets
  exposés restent cachés par la façade du coffre (seul le contour doré d'une mutation se voit) → poser les jouets
  AU-DESSUS du bord ou ouvrir la façade ; parois et trou ovale des mouchoirs invisibles en jeu (noirs) malgré
  l'ambiance et les SurfaceLight → éclairage à revoir. Pantoufle : sortie « Retour chambre » non testée.
- 17 h 15 : **maquettes d'interface générées sur Higgsfield** (GPT Image 2.5), en attente de validation :
  `docs/mockups/higgsfield/hud.png`, `icone-tetine.png`, `mes-jouets.png`, `coffre-plein.png`, `boutique.png`.
  **Monnaie = tétines** (leaderstats « Tétines », attribut interne Cash). Fourrure de la pantoufle rose (150,92,118).
  Demandes en attente de la validation : bouton « Voir les jouets » → animation d'entrée dans le coffre, vue de dessus
  avec les vrais jouets lâchés par gravité ; capacité par coffre (12 sur la maquette) ; achat d'un 2e coffre posé à
  côté. Reçus : balle émoji (`jouet-balle-emoji`) et cheval à bascule (`jouet-cheval-bascule`), envoi lent en cours.
- 17 h 30 : balle émoji (`jouet-balle-emoji` → `EmojiBall`, commun) et cheval à bascule (objet lourd proposé : Epic,
  2 porteurs, 22 studs). Le cheval portait un logo de marque (étiquette rouge et blanche) : effacé couleur + relief
  (`recolor-logo.py ... tache`), version `jouet-cheval-propre` ; **ne jamais charger `jouet-cheval-bascule-lisse`**.
  Reste un ovale en léger relief dans la géométrie, illisible. Tous les jouets qui apparaissent regardent maintenant
  vers les bases (180° ± 35°, vérifié en jeu : 13/13).
- 17 h 55 : **maquettes validées par l'utilisateur, tout est codé et testé en jeu** :
  - **Coffres réels** (`BaseService`) : 1 coffre de 12 jouets au départ, jusqu'à 4 (5 000 tétines l'un). Modèle
    ToyChest posé sur l'attribut `ChestCFrame` de la base (pas `ChestStep`, taille `ChestSize`), sol le plus haut sous
    l'empreinte, parois invisibles autour de la cavité mesurée (fond 10 %, bord 50 %), lueur par coffre. Chaque dépôt
    = copie du jouet lâchée dans le coffre (physique 3 s puis figée). Dossier `workspace.BaseChests.Base_<UserId>`.
    Testé : 12 dépôts puis refus « full », achat du n°2 posé à côté, dépôts suivants dans le n°2.
  - **Boutique** (`BuyItem` RemoteFunction) : coffre, Chaussons silencieux 2 500 (bruit ×0,6), Bras costauds 8 000
    (+2 en portant, 5 seul sur un objet lourd). Remote `ChestFull` (fenêtre « Coffre plein ! »).
  - **Client** : `Controllers/HudController` + `Ui/` (Theme, Modal, Shop, ChestFull, ChestView, Assets). Vue « Mes
    jouets » : approche puis plongée de la caméra au-dessus du coffre, jauge, revenu, flèches entre coffres, achat.
  - **Aucun emoji** (demande utilisateur) : icônes découpées dans les maquettes + icônes générées sur Higgsfield
    (`docs/mockups/higgsfield/icones/`, détourées dans `assets/ui/`, registre `assets/ui/registry.json`).
  - Ballon = objet lourd (Rare, 2 porteurs, 16 studs). Pantoufle : lumières de la boîte baissées (2,2 / 1,2).
- 19 h 40 : **difficulté / mini-jeux** (demande utilisateur).
  - `EventService` : un événement aléatoire toutes les 40-75 s (1er à 45 s), seulement si le bébé dort :
    réveil surprise (1,5 s d'alerte), « Vite, dans l'ombre ! » (5 s puis regard du bébé 2,5 s : hors ombre =
    attrapé), « Maman arrive ! » (7 s de pas dans l'escalier, porte qui s'ouvre, 3 s de regard).
    `EventService:Trigger(kind)` pour les tests.
  - Zones d'ombre : 12 disques tagués `ShadowZone` (attribut Radius) dans la recette de la chambre, affichés en violet
    côté client pendant l'événement ; les `HideZone` comptent aussi.
  - Porte de la chambre sur le mur droit (z = 180) : charnière `MomDoor`, lumière du couloir ; le battant 3D sera
    `DecorModels.BedroomDoor` (image de référence `assets/concepts/decor/porte-chambre.png`, à passer sur Tripo).
  - Jouets piégés : 12 % des apparitions (gardé côté serveur), explosion 2,5 s après la prise → réveil immédiat.
  - Attrape : plus de téléportation, le joueur est propulsé loin du berceau (115 / 70 studs/s, 1,4 s au sol).
  - Sons : pleurs 138470978418134 (volume 0,18), « Chuut » 108800532919321 (jauge ≥ 75 %), pas 9113134898,
    porte 9120839010, explosion 3149249837, bips 15675055424. Maquettes : `docs/mockups/higgsfield/evenements/`.
  - Boutique : chaussons mesurés en jeu (bruit 26,5 → 15,9), désormais ×0,5 ; bras costauds +5 (16 en portant, 8 seul
    sur un lourd). Pastilles des bonus sous le compteur de tétines.
  - Jouets reçus : cactus (`jouet-cactus` → `Cactus`), pyramide d'anneaux (`jouet-pyramide` → `RingStack`).
- Reste : placer le Rattle (anneau de dentition), tags `QuietZone` / `Creak` / `HideZone` pas encore lus par le code,
  captures `docs/captures/chambre-v4.png`.

### Enchaînements automatiques (14/09/2026, processus détachés, logs dans `tools/gen3d/`) — 3D arrêtée, voir ci-dessus
1. `after-images-3d.ps1` → image du nounours v2 et des 6 bases (`images-lot3.json`), puis 3D du nounours v2 et des 7 meubles
   (log `after-images.log` + `job3d.log`).
2. `after-bases-3d.ps1` → après (1), 3D des 6 bases et de la bibliothèque (log `after-bases.log`).
3. `after-bases-images.ps1` → après (2), redémarre ComfyUI et génère les pièces du bébé D (`images-lot4.json` : tête qui dort,
   tête qui pleure, main, corps sous la couverture, tétine, planche) (log `after-bases-images.log`).
Chaque GLB sort dans `assets/models/glb/`. Ensuite : rendus (`tools/render-model.py`), FBX (`tools/glb2fbx.py`), envoi lent
(`tools/upload-models.mjs`), chargement dans `ServerStorage` par `InsertService:LoadAsset`.

### Phase 1 — Direction artistique
**Validé par l'utilisateur le 14/09/2026 : plan de la chambre** (`docs/mockups/plan-chambre.png`) — rareté croissante
vers le berceau (communs sur le tapis, rares à mi-chemin, épiques au pied du berceau, légendaire sur le matelas),
6 bases-cachettes le long du mur (boîte à chaussures, pantoufle, boîte de mouchoirs, boîte de céréales, tiroir ouvert,
carton de déménagement), lattes qui grincent, tapis silencieux, ombre sous les commodes = cachette, veilleuses.
Maquette du HUD : `docs/mockups/hud.png` (en attente de retour).
- [ ] Planche d'ambiance : chambre du géant de nuit, échelle joueur/jouets, palette (FLUX)
- [ ] Maquette HTML → PNG du HUD (argent, jauge de bruit, sac) et de la boutique, à valider
- [ ] Miniature du jeu (le géant endormi, les petits voleurs)

### Phase 2 — Prototype jouable (le cœur)
Code serveur écrit le 14/09/2026, `lune run check` vert, **pas encore testé en playtest** :
`Shared/Toys` (catalogue), `Shared/Tuning` (équilibrage), `Shared/Zone`, services `ToySpawnService`,
`CarryService`, `NoiseService`, `GiantService`, `BaseService`. Remotes : `NoiseState`, `GiantState`, `Caught`.
Contrat de scène : modèles dans `ServerStorage.ToyModels.<ToyId>`, points `ToySpawn` (attribut ToyId facultatif),
zones `Base` (volume invisible), zone `GiantRoom`, modèle `workspace.Geant` (attribut State posé par le serveur).
Mécanique du réveil : pendant la chasse, **bouger = attrapé** (« 1, 2, 3, soleil »), à valider au playtest.
- [ ] Chambre du géant avec 10 jouets modélisés, lit, géant endormi
- [x] Ramasser / porter un jouet, vitesse réduite selon le nombre de porteurs (code)
- [x] Jauge de bruit (mouvement, atterrissage) côté serveur (code)
- [x] Réveil du géant : alerte, chasse, joueur qui bouge renvoyé à sa base en perdant son jouet (code, sans visuel)
- [x] Bases des joueurs, jouets posés qui rapportent de l'argent (code)
- [ ] HUD : jauge de bruit, état du géant, argent (maquette d'abord)
- [ ] Playtest : la boucle est-elle drôle en 2 minutes ?

### Phase 3 — Économie et social
- [ ] Sauvegarde (ProfileStore), raretés, mutations
- [ ] Vol dans la base des autres, verrou de base
- [ ] Gros jouets à plusieurs porteurs
- [ ] Améliorations et boutique

### Phase 4 — Rétention et lancement
- [ ] Deuxième pièce (cuisine), renaissance
- [ ] Quêtes quotidiennes, codes, événements
- [ ] Monétisation juste (pass et produits qui font gagner du temps ou marquent l'identité)
- [ ] Miniatures, icône, trailer court

### 14/09/2026 soir — portage, maman, chasse, sons, jouets ×3
Testé en playtest :
- **Bras levés** en portant : les épaules de ce place sont des `AnimationConstraint`, donc C0 et Attachment0 ne
  tiennent pas. `CarryController` écrit `Transform` à chaque `PreSimulation`. L'utilisateur trouve le balancement
  drôle : à garder.
- **Jouet porté** centré sur sa boîte englobante (le pivot de certains modèles est loin du modèle). **Poser (G)** :
  juste devant, au sol, par gravité. **Lancer (F)** : poids = porteurs + taille ; distance et bruit dépendent du poids.
  Mesures : jouet léger 26 studs, lourd 12 studs. Son d'impact léger ou lourd.
- **Porte** encastrée dans le mur (130 × 290 × 10). **Maman** : modèle Tripo envoyé par l'utilisateur
  (`maman-tripo-lisse`, DecorModels.Mom). Elle glisse du couloir devant la porte, et sa lampe balaie la chambre.
- **Vraies ombres** pendant « Maman arrive ! » :
  - la lune devient une lumière chaude rasante qui n'entre que par la porte (`Tuning.MOM_LIGHT_*`) ;
  - le couloir a `CastShadow = false` ;
  - attrapé seulement si on est dans cette lumière (`EventService:IsLitThroughDoor`) ;
  - plus de disques violets pour cet événement.
- **Chasse du bébé** : chaque mouvement ou saut propulse, autant de fois qu'on recommence ; seuls ceux qui bougent
  sont propulsés. Mesures : immobile 0 stud, saut propulsé à 179 studs, marche après s'être relevé propulsée de
  nouveau. Propulsion 200 / 110.
- **Jouets ×3** : 24 points d'apparition de plus, 37 jouets.

Codé, pas encore vérifié en jeu :
- mini-cinématique caméra vers la porte (`EventController.momCinematic`) ;
- badge « lourd » abaissé juste au-dessus du jouet ;
- `SoundscapeController` : berceuse, tic-tac des comptes à rebours, son de jauge qui monte ou descend ;
- `ToyInspectController` : clic sur un jouet, zoom et fiche (nom, rareté, revenu, poids), Retour. La vidéo montre
  la fiche ouverte sans le zoom caméra : à vérifier.

Suite, testé en jeu :
- **Mini-cinématique** : plan fixe face à la porte ; la maman est bien visible. Placée du côté du joueur, la caméra
  voyait le battant ouvert, qui cachait la maman.
- **Fiche jouet** : le `WaitForChild("PlayerModule")` bloquait la vue, car ce place n'a pas de PlayerModule ; les
  touches de déplacement sont maintenant avalées. Caméra juste en face du jouet (1,3 × sa taille) : capture du
  nounours face caméra et fiche à droite.
- **Contours** : plus de contour sur les jouets communs (26 affichés, limite 31).
- **Badge « lourd »** juste au-dessus du jouet (`StudsOffsetWorldSpace`).
- **Furie** (`AbilityService` + `AbilityController`) : touche R, bouton Y ou bouton tactile. +22 de vitesse pendant
  4 s, traînée rose et jaune, recharge 60 s, bruit de déplacement ×1,2. Mesures : 17 → 46 studs en 1,5 s, relance
  refusée pendant la recharge, retour à la vitesse 14. Au premier réglage (bruit ×4), la jauge était pleine en
  1,5 s.

### 14/09/2026 nuit — boutique complète et rétention (liste des 26 idées validée par l'utilisateur)
Code écrit, `lune run check` vert, **rien encore testé en playtest** :
- **Fondations** :
  - `DataService` : profils sauvegardés en DataStore. Avant, tout était perdu en quittant.
  - `Shared/Catalog` : 29 articles.
  - `ShopService` : achats, `Grant`, attributs `Owned_<id>` et `Equipped_<slot>`.
  - `BaseService` : sauvegarde des tétines, coffres et jouets, `SpendCash`/`AddCash`/`AddChest`, coffres dorés ×2,
    `AddIncomeMultiplier`, `ToyDeposited`, `ResetBase`.
  - `MenuController` : colonne de gauche.
- **Pouvoirs** (`AbilityService`/`AbilityController`, `Shared/Abilities`) :

  | Touche | Pouvoir | Prix |
  |---|---|---|
  | R | Furie | payante, 3 000 |
  | T | Tétine magique | |
  | Y | Hochet leurre | |
  | H | Doudou bouclier | |
  | V | Ventouse | |
  | C | Cape d'ombre | |
  | X | Berceuse | |

- **Améliorations** : chaussons et bras à 5 niveaux, sac à dos (2 jouets légers), aimant, oreille fine (indice
  avant les alertes).
- **Boutique** (`Ui/Shop` réécrite) et cosmétiques (`CosmeticService`, `CosmeticController`, `DanceController`) :
  traînées, contours par coffre, 3 danses procédurales (touche B).
- **Quêtes, pass et cadeaux** (`QuestService`, `PassService`, `DailyService`, `Shared/Retention`, menus) : 3 quêtes
  du jour et 3 de la semaine, pass de 30 paliers (piste premium « Bientôt »), connexion sur 7 jours, roue
  quotidienne.
- **Collection, Nuits, lune, amis et classement** (`ToyCollectionService`, `NightsService`, `MoonService`,
  `SocialService`, `LeaderboardService`, `MoonController`, `Shared/Progression`, menus) :
  - sets de collection à +5 % de revenu ;
  - Nuits : renaissance à +25 % par nuit ;
  - pleine lune toutes les 20 min (×2, plus de jouets rares) ;
  - +10 % par ami présent ;
  - classements du serveur et mondial.
- **Images** :
  - icônes générées en local (FLUX), les crédits Higgsfield étant épuisés ; lot `tools/gen2d/lot-boutique.json`,
    script `tools/gen2d/gen-lot.mjs` ; à téléverser lentement puis à reporter dans `Ui/Assets` ;
  - images d'objets 3D pour Tripo dans `assets/concepts/objets3d/`, que l'utilisateur génère en 3D.

### 15/09/2026 — retours de test : bébé, captures, ventouse, boutique, trampoline, niveaux
Code écrit, `lune run check` vert. Captures des menus faites ; le reste n'est **pas encore vérifié en jeu** :
- **Niveaux** (`LevelService`, `LevelController`, `Shared/Levels`) : XP unique via `PassService:AddXp` (événement
  `XpGained`), niveaux 1 à 100, récompenses, titres, célébration, niveau au-dessus de la tête (réduit après capture).
- **Menus** refaits sans débordement et avec des icônes (`Modal.body`, `Theme.scrollList`/`icon`/`pill`).
  Capturés un par un : les 7 menus. `Modal` publie `MenusOuverts`, qui cache la barre de pouvoirs.
- **Bébé** :
  - `BabyPovController` : bulle en bas à gauche avec la tête qui pleure vue du dessus et le compte à rebours ;
  - `BabyVisualService` : le bébé se lève et balaie la chambre (animation du modèle entier, pas de squelette).
- **Captures du joueur** (`EventController`) : onde du cri et « OUIIIN ! » pour le bébé, chausson « BONK ! » pour
  maman, étoiles d'étourdissement. Pastilles de bonus retirées (elles chevauchaient la barre d'XP).
- **Ventouse** : tir visé (raté = 3 s de recharge), 90 studs au niveau 1 puis 160 au niveau 2 (jouets lourds au
  niveau 2), jouet qui revient en arc (`CarryService:FindShot`/`PullToy`). Barre de pouvoirs collée en bas, avec
  le temps d'effet restant en direct.
- **Boutique** : disponibilité publiée par `ShopService`, une icône par article (clés `icone*`), vraies images des
  jouets dans la collection (clés `jouet*`, rendus 3D à téléverser), colonne des menus cachée pendant la vue
  « Mes jouets » (attribut `VueCoffre`).
- **Trampoline** (`TrampolineService`, `TrampolineController`, remote `Bounce`, recette build-chambre) : rebond en
  cloche sur le matelas, +22 de bruit, son « Spring ». Attend le modèle `DecorModels.Trampoline`.
- **Sons et test** : pleur remplacé par le son choisi (9113234666, volume 0,12) ; 500 000 tétines une fois par
  profil pour le compte de test 11620637288.
- **Assets** :
  - chargés dans Studio : `ShieldPlush`, `Backpack`, `GoldChest`, `DecorTrophy`, `DecorDinoPlush` (Tripo) ;
    `SuctionCup`, `DecorBeanbag`, `DecorTent` (TRELLIS) ;
  - icônes de la boutique et des menus téléversées et branchées, coffre doré compris ;
  - en cours (`tools/gen3d/lot-v3.ps1`) : rendus des jouets et des décors, icônes des traînées, danses et contours,
    3D du trampoline, des oreilles, de la lampe, de la guirlande, du tableau et de la cuisine, puis téléversements.

### 15/09/2026 fin de soirée — armes, boîte à outils, tipi, sons, visuels
Testé en jeu et capturé :
- **Armes** : barre d'armes au-dessus des pouvoirs (touches 1 à 9, Q pour ranger), barre d'outils Roblox cachée.
- **Bulle du bébé** : visage bien cadré, à partir de la pose couchée de « Dort ».
- **Achats** : armes et décors achetés ; décors posés dans la base ; sortie de base sur le parquet.

Codé, pas encore vérifié en capture :
- **Sons** : `Ui/Sfx` et `SfxController`.
- **Pleine lune** : icône qui se vide.
- **Zones d'ombre** : ombre douce, anneau et poussière d'étoiles.
- **Vitesses** : toutes ×1,21, sans changer le bruit.
- **Tipi** : `TentService`, 3 petits jouets.
- **Armes** : `WeaponService`, `WeaponController`, `Shared/Weapons`, `CatalogWeapons`.
- **Aperçus 3D** dans la boutique : `ReplicatedStorage.ApercusBoutique`.

Assets et incidents :
- **Boîte à outils** (`game:GetObjects`, scripts retirés) : 19 décors dans `ServerStorage.CosmeticModels` et 11 armes
  dans `ServerStorage.WeaponModels`. Liste dans `docs/decors-boite-a-outils.md` et `docs/armes-boite-a-outils.md`.
- **Chambre décalée** deux fois dans l'éditeur (joueurs qui tombaient dans le vide) : reconstruite, et les recettes
  verrouillent maintenant toutes les pièces (`Locked`).
- **Rojo tombe quand la mémoire manque** pendant la 3D locale : ne pas générer de 3D pendant les tests.
  Relance : `rojo serve default.project.json --port 34874`, en processus détaché, puis Connect dans Studio.
- **Reste à générer en local** : tableau du classement et 5 meubles de cuisine (`tools/gen3d/suite-v3.ps1`
  pour la suite). Icônes et 4 objets (trampoline, oreilles, lampe, guirlande) en téléversement lent.

### Nuit du 15 au 16/09/2026 — autonomie (l'utilisateur dort : « pondre un jeu bien bien amélioré »)
Règles : ne rien publier, ne rien supprimer sans demander (archiver), sauvegarder souvent, pas de 3D locale pendant
les tests Studio (Rojo tombe faute de mémoire), téléversements à 30 s d'intervalle, un seul flux.
Déjà fait :
- 30 icônes et images de jouets branchées dans `Ui/Assets` (collection, boutique) ;
- trampoline, oreilles, lampe et guirlande chargés dans Studio.

Plan :
1. **Vérifier en jeu** : trampoline (reconstruire la chambre), icônes d'armes (en téléversement), lune,
   zones d'ombre, tipi, sons, armes.
2. **Vol entre joueurs + verrou de base** (fork U) : StealService, BaseLockService, StealController.
3. **Tutoriel des nouveaux joueurs** (fork T) : TutorialService, TutorialController, Shared/Tutorial.
4. **Cuisine** débloquée à la Nuit 3 : 3D restante (tableau, frigo, table, chaise haute, plan de travail,
   cuisinière) puis la pièce.
5. **Équilibrage, corrections**, captures et vidéo pour le réveil.

À corriger :
- Place non sauvegardée depuis 20:33 : l'utilisateur teste dans Studio.
- Bonus de boutique : liste d'idées envoyée à l'utilisateur, en attente de validation (objectif : sessions d'une
  heure au moins).

Avancement à 02h30 (détail des idées : `docs/IDEES.md`) :
- **Blocage au démarrage** corrigé : StealService:Start attendait `workspace.BaseChests` (créé par BaseService
  plus tard) ; Main appelait les Start à la suite, donc aucun profil, base ni tétines. Main lance désormais chaque
  phase dans son propre fil et signale celles qui attendent. Règle ajoutée au CLAUDE.md.
- **AbilityService ne se chargeait plus** (« Ambiguous syntax » après un cast en début de ligne) : corrigé, règle
  ajoutée au CLAUDE.md.
- Vu en jeu : codes cadeaux, coffre du bébé, récompense de retour, défi chronométré (plaque moins éblouissante,
  chrono remis dans l'écran), mission de la tétine, lampe frontale.
- `lune run check` entièrement vert (42 avertissements selene et les erreurs de types nettoyés).
- Cuisine construite (`tools/scene/build-cuisine.luau`, KitchenService, DogService, DogController) : test d'entrée
  en cours.
- Messages courts (`Theme.toast`) : placés sous le bandeau d'événement s'il est affiché et empilés ; vus en jeu.

Avancement à 02h55 :
- Cuisine finie et testée (chien tourné vers la pièce, vrai panier, lumières à portée, attrape « dog » avec
  « OUAF ! ») ; place sauvegardé à 02:51.
- Nouvelles idées du carnet codées et vues en jeu : veilleuse à remonter (NightlightService), tableau des records
  de la nuit (RecordsService, RecordsController), jouets maudits (CursedToyService).
- Reste : événements du bébé affichés dans la cuisine, réveil en douceur (idée 19), revue des 100 jouets,
  intérieurs carton et chaussures.

Avancement à 03h25 :
- Revue des 118 jouets faite dans Studio : 32 pivots tournés corrigés (jouets couchés ou à l'envers en jeu),
  7 jouets remis de face ou debout, 3 remplacés ou nettoyés ; originaux dans `ServerStorage.Archive.ToyModels_avant_revue`.
  Restent à revoir : singe, soucoupe, koala, harmonica, dominos, baguette de fée, clavier rose.
- Réveil en douceur (idée 19) vu en jeu : bulle « Mmh... » et bébé qui se retourne au-delà de 80 %.
- Bandeaux du bébé masqués dans la cuisine, testé en jeu.
- Reste : intérieurs carton et chaussures, combo de discrétion, paramètres, fil d'actualité et émotes à voir en
  jeu, couinement des jouets maudits en marchant.

Avancement à 03h55 :
- Intérieurs corrigés et vérifiés en jeu : carton (arrivée dans un tas de polystyrène, tas déplacé ; sortie sans
  chute) et chaussures (lampes à portée des parois, ambiance remontée). Place sauvegardé à 03:25 par l'agent.
- Vus en jeu : combo de discrétion (x1 -> x3), fil d'actualité, émote « Bravo », paramètres (enregistrés ; sa
  propre étiquette se cache aussi maintenant).
- Écran après un dépôt : les messages courts attendent la fin de la célébration de niveau, et la célébration passe
  sous le bandeau d'événement quand il est affiché ; les deux vus en jeu.
- Reste : couinement des jouets maudits en marchant (test à la main), 7 jouets à revoir (singe, soucoupe, koala,
  harmonica, dominos, baguette de fée, clavier rose).

Avancement à 04h05 :
- 6 des 7 jouets restants réglés (singe, koala, dominos et baguette de fée remplacés ; soucoupe teintée,
  harmonica agrandi). Reste le clavier rose.
- Alerte d'intrusion (idée 24) : message vu en jeu ; détection réelle à tester à deux joueurs.
- Son non autorisé dans les journaux : il venait de koalas archivés, identifiant vidé.
- À tester à la main par l'utilisateur : couinement des jouets maudits en marchant, alerte d'intrusion à deux.

Avancement à 04h20 :
- Cuisine complétée : 12 jouets de dînette propres à la cuisine (ToysKitchen, champ kitchenOnly) et 3 événements
  (frigo qui éclaire, gamelle renversée, chien qui rêve), testés en jeu ; place sauvegardé à 03:57 par l'agent.
- Tutoriel masqué dans la cuisine (la bulle parlait du bébé), testé en jeu.
- Résumé de la nuit publié pour l'utilisateur (page privée avec captures).
- Reste : clavier rose, son non autorisé 6417837881 qui revient au lancement (probablement un cache de la session
  Studio), tests à la main (jouets maudits en marchant, alerte d'intrusion à deux).

Avancement à 04h15 :
- Clavier rose réglé : ses 4 unions ignoraient leur couleur (UsePartColor), corps rose franc et touches lisibles ;
  original dans `ServerStorage.Archive.PinkKeyboard_avant_clavier`.
- Mode photo du tableau des records (idée 25) vu en jeu : message « Nouveau record » et cadre qui pulse 6 s.
- Reste : son non autorisé au lancement (à revérifier après redémarrage de Studio), tests à la main (jouets maudits
  en marchant, alerte d'intrusion à deux).

Avancement à 04h30 :
- Collection : les 114 jouets sans image montrent maintenant leur modèle 3D (ToyPreviewService, copies à la demande
  dans ReplicatedStorage.ApercusJouets), en couleur si trouvé, silhouette sinon ; vu en jeu.
- Test d'endurance de plus de 3 min 20 sans intervention : aucune erreur ni avertissement hors le son 6417837881 déjà
  connu.
- Audit de débordement (écran 2288 × 1201, collection ouverte) : rien hors écran, aucun texte de notre interface qui
  déborde. Reste à regarder sur téléphone.

### 15/09/2026, 17 h 15 — icônes v3 et maman en colère en 3D
- **Studio a planté** (« Device removed », carte graphique saturée) : relancé sur `chut-geant.rbxl` sauvegardé à 04:12,
  code renvoyé par `tools/push-src.mjs` (Rojo pas reconnecté). **Sauvegarder la place (Ctrl+S) au retour.**
- **34 icônes v3** (`assets/ui/registry-icones-v3.json`) branchées dans `Ui/Assets`, vues en boutique. L'onglet
  Coffres était vide sur la capture alors que l'image `100871723457501` se charge (`AssetFetchStatus.Success`) :
  l'icône (coffre bleu plein de jouets, clé `ongletCoffres`) n'était sans doute pas encore chargée à la première
  ouverture ; à revérifier.
- **Jumpscare de maman en 3D haute définition** : le premier modèle Meshy (9 500 triangles, asset
  `122981112451750`) montrait trous et coutures de texture déchirées en gros plan, alors qu'il était propre de loin
  (même rendu avec ou sans CanvasGroup). Refait par `tools/decimate-split-glb.py` : 48 000 triangles en 8 morceaux,
  asset `84576689767246`, chargé dans `ReplicatedStorage.ScreamerModels.MamanColere` par
  `tools/scene/charger-maman-colere.luau`. Caméra arrêtée à 0,6 de la hauteur du buste (« éloigne-la un peu »).
  Vu en jeu, propre. L'image « femme jumpscare » (`97997221493943`) n'est plus utilisée.
- À corriger : le bandeau d'événement (« Panne de veilleuse ! ») passe sur le titre de la boutique ; avertissement
  « ToyModels.Pacifier absent » au démarrage alors que le modèle existe (ordre de chargement ?).
