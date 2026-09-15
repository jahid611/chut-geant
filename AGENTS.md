# AGENTS.md — constitution commune de « CHUT ! Vole le Géant »

Règles partagées par tous les agents du projet : **Claude** (Claude Code, implémente) et **GPT** (Codex CLI,
GPT-6 Astra, relit en contradictoire). Les instructions propres à chaque agent vivent ailleurs : `CLAUDE.md` pour
Claude, les consignes de `tools/gpt-review.mjs` pour GPT. En cas de conflit, ce fichier et l'utilisateur priment.

Jeu Roblox : de tout petits joueurs volent les jouets d'un bébé géant endormi. Tout le texte du jeu et des échanges
est en **français**.

- **Vérité produit et game design** : `docs/PLAN.md` (à lire à la reprise d'une session).
- **Carnet d'idées vivant** (en cours, à faire, fait et vérifié en jeu) : `docs/IDEES.md`.

## Qui fait quoi

| Rôle | Agent | Responsabilité |
|------|-------|----------------|
| Décide | l'utilisateur | demandes, priorités, validation, publication |
| Implémente | Claude ou GPT, choisi par tâche | plan, code, playtest, corrections ; ne relit jamais son propre code |
| Relit | l'autre modèle | critique du plan, relecture du code, confirmation des corrections |
| Arbitre | `tools/orchestrator.mjs`, sans IA | état de la tâche, preuves objectives, clôture, mesures |

## Architecture

```
src/server/           -> ServerScriptService/Server   (Services/ : un module par responsabilité)
src/client/           -> StarterPlayer/StarterPlayerScripts/Client   (Controllers/, Ui/)
src/shared/           -> ReplicatedStorage/Shared   (Config, Remotes, Toys, Catalog, Tuning...)
tools/scene/          recettes de construction de scène (chambre, cuisine, intérieurs des bases)
tools/                pont MCP, génération 2D/3D, téléversements, relecture GPT
docs/                 PLAN.md, IDEES.md, maquettes
assets/ui/            icônes d'interface et registres d'identifiants Roblox
assets/models|concepts|textures, docs/captures|videos : lourds, locaux seulement (hors dépôt)
```

Le mapping fait autorité dans `default.project.json` (Rojo sur le **port 34874**). Le place `.rbxl` n'est pas
versionné.

## Règles de code

- Tout le code passe par `src/` et Rojo, jamais par un script édité dans Studio.
- `--!strict` partout, services `Init()` / `Start()` chargés par `Main.server.luau`, contrôleurs par `Main.client.luau`.
- Remotes déclarés **uniquement** dans `src/shared/Remotes.luau`.
- **Anti-triche** : le client envoie une intention, le serveur valide et décide (types, bornes, cadence, droits,
  distance). Jamais de confiance dans un prix, une position, une cible ou une quantité venue du client.
- `task.*` uniquement, `Animator:LoadAnimation`, attributs et tags plutôt que des Value cachées.
- Un `Start()` de service ne doit **jamais attendre** (`WaitForChild` d'un objet créé par un autre service) : le mettre
  dans `task.spawn`. Un blocage a déjà empêché le chargement de tous les profils.
- **Jamais de ligne qui commence par `(`** après un appel (`(x :: any).Prop = ...`) : Roblox refuse le module
  (« Ambiguous syntax ») alors que selene et luau-lsp ne disent rien, et stylua fusionne les lignes. Passer par une
  variable locale.
- Tables par joueur nettoyées à `PlayerRemoving`, connexions déconnectées quand leur objet disparaît.
- Éditer les fichiers de `src/` avec un vrai outil d'édition, jamais `sed -i` ni `perl -pi` (fait crasher `rojo serve`).
- Interface : textes en français, **aucun emoji** (icônes à la place), **rien ne déborde** d'un panneau, beaucoup
  d'icônes plutôt que du texte.
- Aucune clé dans le dépôt : `.env` uniquement.

## Studio, Rojo et pont MCP

- **Un seul serveur MCP** reste attaché au plugin Studio : `node tools/mcp-daemon.mjs` (socket `127.0.0.1:58999`,
  lancé par Claude). Ne jamais lancer un second serveur MCP Roblox : le plugin décroche.
  - Claude appelle les outils par `node tools/mcpd.mjs <outil> '<json>'`.
  - GPT les appelle par le serveur MCP `roblox-studio` de Codex, qui passe par `tools/mcp-stdio-bridge.mjs` (même
    connexion ; chaque appel est journalisé dans `tools/reviews/mcp-calls.log`).
- Outils utiles : `get_place_info`, `execute_luau` (mode édition), `solo_playtest` (start/stop/status, mode play),
  `eval_server_runtime` / `eval_client_runtime` (pendant un playtest), `get_runtime_logs`.
- **Un seul agent à la fois dans Studio** (playtest, captures, caméra). Verrou caméra : `tools/scene/.camera-lock`.
  Un playtest lancé est arrêté par celui qui l'a lancé.
- **Ne jamais publier le place.** Ne jamais supprimer d'instance dans Studio sans demander : archiver dans
  `ServerStorage.Archive`. Pièces de scène `Locked`.
- Après toute modification de gameplay : playtest, lecture des journaux, corriger erreurs et avertissements.

### Limites connues du banc de test (éviter les fausses alertes)

- `Humanoid:Move` lancé par script ne fait pas avancer le personnage : les mécaniques basées sur la marche se testent
  à la main. La direction de marche remonte bien au serveur.
- L'attribut joueur `Piece` suit la position (KitchenService) : téléporter dans `Workspace.Cuisine.Jeu.ZoneCuisine`
  plutôt que poser l'attribut.
- Le bruit baisse de 5/s et des multiplicateurs d'événements s'appliquent : viser un seuil par petits pas bornés.
- Une évaluation qui attend plusieurs minutes dépasse le délai du pont : attendre côté shell, évaluer court.

## Assets

- **Aucun décor ni objet en pièces de base Studio.** Modèles générés en local ou assets gratuits reconnus (Creator
  Store, créateurs fiables), scripts et sons retirés à l'import.
- Téléversements Roblox : un seul flux, lent (30 s d'écart), jamais de rafale, jamais de renvoi d'un refus (le compte
  a déjà été banni pour des rafales).
- Vérifier le sens de chaque modèle posé par une capture avant de le montrer.
- Arrêter ComfyUI et TRELLIS avant un playtest (Rojo tombe faute de mémoire).

## Boucle Claude ↔ GPT, arbitrée par `tools/orchestrator.mjs`

Claude et GPT travaillent **à égalité** : aucun des deux ne décide seul. Un arbitre sans IA,
`tools/orchestrator.mjs`, garde l'état de la tâche (`TASK`, `PLAN`, `FILES_CHANGED`, `CLAUDE_OPINION`,
`GPT_OPINION`, `TEST_RESULTS`, `MCP_LOGS`, `REMAINING_ISSUES`, `ITERATION`) pour qu'aucun modèle n'oublie ce que
l'autre a fait. **Git est la mémoire objective** : GPT reçoit le `git diff` et le contenu des fichiers changés
calculés par l'outil, jamais le récit de Claude sur ce qu'il a modifié, et l'arbitre vérifie par l'empreinte du diff
que playtest, check et relecture portent sur le même code. (Sous Windows, Codex refuse les commandes shell de lecture :
`tools/gpt-review.mjs` lui envoie donc tout dans le message ; Studio reste accessible par le serveur MCP.) Chaque étape s'écrit dans le journal `tools/reviews/journal.md` (étiquettes ORCHESTRATEUR, CLAUDE, GPT, MCP,
CHECK, EQUIPE), qui défile dans le terminal : l'utilisateur suit sans répondre à chaque étape.

Claude Code reste l'interface de l'utilisateur : quand il demande une fonctionnalité à Claude, Claude pilote la
boucle par ces commandes.

1. **[ORCHESTRATEUR]** `node tools/orchestrator.mjs start "<demande>" --type <gameplay|ui|serveur|scene|outillage>
   --by <claude|gpt|auto>` (10 itérations au plus, `--max` pour changer). Les étapes ci-dessous décrivent Claude
   implémenteur et GPT relecteur ; l'inverse est décrit dans « Implémentation par GPT et répartition mesurée ».
2. **[CLAUDE] plan** : lit `docs/PLAN.md`, le code et Studio, écrit son plan d'architecture (fichiers, services,
   remotes, sauvegarde), puis `node tools/orchestrator.mjs plan <plan.md>`.
   **[GPT]** critique ce plan (sauvegarde, remotes, exploits, doublons avec l'existant).
3. **[CLAUDE]** répond à chaque remarque : `node tools/orchestrator.mjs answer <reponses.md>`, sections
   `## <id> — acceptée` (et ce qui change) ou `## <id> — rejetée` (et la raison vérifiée). Puis implémente.
4. **[MCP] playtest** : `node tools/orchestrator.mjs test start` (l'arbitre lance le playtest, note l'empreinte du
   code et écrit une marque de session dans le journal du serveur), Claude vérifie en jeu, puis `node tools/orchestrator.mjs test --ok` ou `--fail` (journaux lus dans Studio,
   playtest arrêté). En échec, **[GPT] diagnostic** automatique ; Claude confirme la cause, corrige et rejoue. Des
   journaux venus d'ailleurs passent par `test --fail --logs <fichier>`, pour le diagnostic seulement.
5. **[GPT] relecture** : `node tools/orchestrator.mjs review`. Relecture initiale s'il n'y a aucune remarque
   ouverte, sinon relecture finale : GPT vérifie les corrections, juge les rejets et cherche les régressions.
6. Tant qu'il reste des remarques : retour à l'étape 3 (réponses, correction, playtest, relecture).
7. **[CHECK]** `node tools/orchestrator.mjs check` (`lune run check`).
8. **[EQUIPE]** `node tools/orchestrator.mjs done` : l'arbitre refuse la clôture sans verdict GPT « approuvé »,
   sans playtest OK et check vert sur le code actuel, ou avec une remarque bloquante ou majeure ouverte. Puis commit
   (message en français) et push sur `origin/main`.

Règles d'arbitrage :
- une remarque n'est fermée que si GPT le confirme (corrigée, ou rejet dont il accepte la raison) ; un rejet contesté
  reste ouvert et bloque la clôture ;
- une relecture compte pour le code qu'elle a réellement reçu : empreinte prise avant l'envoi (commit HEAD, diff et
  fichiers nouveaux), relecture obsolète si le code change pendant qu'elle tourne, et alors archivée sans fermer
  ni ouvrir de remarque ; seul le verdict d'une relecture
  initiale ou finale compte pour la clôture, pas celui d'une critique de plan ou d'un diagnostic ;
- un playtest n'est enregistré OK que s'il a été lancé par l'arbitre, que ses journaux ont pu être lus dans Studio
  sans erreur, qu'ils contiennent la marque de session écrite au lancement, qu'ils ne montrent aucune erreur
  d'exécution depuis le lancement (hors erreurs connues, listées et justifiées dans l'arbitre, toujours affichées) et
  que le code n'a pas changé depuis ; sinon il passe en échec avec diagnostic ; un check vaut pour le code présent à son lancement et il est
  ignoré si le code change pendant qu'il tourne ;
- au-delà de la limite d'itérations, l'arbitre s'arrête et l'utilisateur tranche.
`node tools/orchestrator.mjs status` affiche l'état à tout moment. Les appels bas niveau de GPT restent possibles
directement par `tools/gpt-review.mjs` (plan, initial, diagnostic, final).

## Implémentation par GPT et répartition mesurée

GPT peut implémenter : Codex tourne alors en écriture dans le dépôt (`-s workspace-write` avec
`windows.sandbox="unelevated"` ; sans cette option, Codex reste en lecture seule sous Windows). Claude relit son travail.

- `node tools/orchestrator.mjs plan` : GPT écrit le plan en lecture seule (`-s read-only`), avec l'index du projet et
  le code prioritaire pour le type de tâche dans le message (400 Ko au plus), le reste de `src/` se lisant dans Studio
  par `get_script_source` ; Claude le critique par
  `claude-review start --mode plan` puis `claude-review submit <remarques.json>` (même schéma que GPT,
  `tools/gpt-review.schema.json`).
- `node tools/orchestrator.mjs implement` : GPT implémente le plan retenu et répond aux remarques ouvertes.
- `test start`, `test --ok|--fail` et `check` : comme lorsque Claude implémente.
- Relecture par Claude : `claude-review start` (empreinte notée) puis `claude-review submit <fichier>`, refusée si le
  code a changé entre les deux. Claude lit le diff et les fichiers réels, jamais le seul résumé de GPT.
- `node tools/orchestrator.mjs answer` : GPT corrige et répond aux remarques de Claude.
- `done`, le commit et le push restent faits par Claude après la clôture ; GPT ne committe jamais.

Garde-fous calculés après chaque passage de GPT (`tools/gpt-implement.mjs`, `tools/protected-paths.mjs`,
`tools/text-checks.mjs`), jamais déclarés par GPT :
- instantané, avant le passage, des fichiers protégés (`.env*`, place `.rbxl*`, métadonnées `.git` hors objets), hors
  dépôt et hors dossiers inscriptibles par le sandbox ; après le passage, restauration de l'état exact (contenu d'avant,
  suppression seulement d'un fichier créé pendant le passage), jamais depuis une copie altérée ;
- HEAD et index Git (comparaison logique) inchangés ;
- gros dossiers d'assets locaux et état de l'arbitre : inventaire taille et date de modification (hacher 1,5 Go à
  chaque passage serait trop long) ;
- accents abîmés introduits dans les fichiers texte changés ;
- fichiers réellement changés pendant le passage comparés à ceux que GPT déclare.
Chaque écart devient une remarque de l'arbitre (bloquante pour les chemins protégés, Git et les accents), que le
relecteur doit confirmer résolue. `done` revérifie aussi les accents abîmés. Pendant un passage de GPT, le verrou Studio
`tools/scene/.camera-lock` est tenu.

Répartition : à chaque clôture, l'arbitre ajoute une mesure à `docs/agents/mesures.json` (type, implémenteur,
itérations, remarques bloquantes ou majeures reçues, playtests ratés, durée). `node tools/orchestrator.mjs stats`
affiche le tableau. Avec `--by auto`, l'arbitre alterne tant que chaque modèle a moins de 3 tâches mesurées pour ce
type, puis confie le type au meilleur score (moins de remarques graves et de playtests ratés par tâche, puis moins
d'itérations). L'utilisateur peut toujours imposer `--by claude` ou `--by gpt`.

## Vérification

- `lune run check` : sourcemap, selene, stylua, luau-lsp. Vert avant tout commit.
- Captures de vérification : `docs/captures/` (locales).

## Démarrage d'une session

1. `rojo serve default.project.json` en tâche de fond, puis Connect dans le panneau Rojo de Studio (port 34874).
2. `node tools/mcp-daemon.mjs` en tâche de fond. Si le plugin est déconnecté : onglet Plugins → « MCP Server » →
   Connect pendant que le daemon tourne.
