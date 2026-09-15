# chut-geant — CHUT ! Vole le Géant

Jeu Roblox piloté depuis Claude Code. Rojo synchronise le code, le MCP manipule la scène.
Outillage et conventions repris de `C:\Users\jahidsyd\roblox-dev` (voir son CLAUDE.md pour le détail).

**À la reprise d'une session : lire `docs/PLAN.md` avant toute chose.**

## Architecture

```
src/server/           -> ServerScriptService/Server   (Services/ : un module par responsabilité)
src/client/           -> StarterPlayer/StarterPlayerScripts/Client   (Controllers/)
src/shared/           -> ReplicatedStorage/Shared   (Config, Remotes, types, constantes)
src/starter-gui/      -> StarterGui
assets/concepts/      images de référence FLUX et détourages
assets/models/        GLB générés, FBX prêts à téléverser, registres d'identifiants
docs/PLAN.md          concept, règles d'assets, phases
```

Le mapping fait autorité dans `default.project.json` (Rojo sur le **port 34874**).

## Règles

- Tout le code passe par `src/` et Rojo, jamais par un script édité dans Studio.
- `--!strict` partout, services `Init()` / `Start()`, remotes déclarés dans `src/shared/Remotes.luau` uniquement.
- Le client envoie une intention, le serveur valide et décide. Anti-triche sur toute action client.
- `task.*` uniquement, `Animator:LoadAnimation`, attributs et tags plutôt que des Value cachées.
- Éditer les fichiers de `src/` avec Edit, jamais `sed -i` ni `perl -pi` (fait crasher `rojo serve`).
- Jamais de ligne qui commence par `(` après un appel (`(x :: any).Prop = ...`) : Roblox refuse le module
  (« Ambiguous syntax ») alors que selene et luau-lsp ne disent rien, et stylua fusionne les deux lignes. Passer
  par une variable locale.
- Un `Start()` de service ne doit jamais attendre (`WaitForChild` d'un objet créé par un autre service) : le
  mettre dans `task.spawn`.
- Après toute modification de gameplay : playtest via le MCP, lire les logs, corriger erreurs et warnings.
- `lune run check` vert avant commit.
- Ne jamais publier le place, ne jamais supprimer d'instance dans Studio sans demander.
- Aucune clé dans le dépôt : `.env` uniquement.

## Assets

- **Aucun décor ni objet en pièces de base Studio.** Modèles générés en local (FLUX → détourage → Hunyuan3D-2 dans
  `D:\ai\hunyuan3d`) ou assets gratuits reconnus (CC0, Creator Store de créateurs fiables).
- Téléversements Roblox : `tools/upload-slow.mjs` en petits lots espacés, jamais de rafale, jamais de renvoi d'un refus.
- Arrêter ComfyUI et Hunyuan3D avant un playtest Studio.

## Démarrage d'une session

1. `rojo serve default.project.json` en tâche de fond, puis Connect dans le panneau Rojo de Studio.
2. `node tools/mcp-daemon.mjs` en tâche de fond, puis les appels via `node tools/mcpd.mjs <outil> '<json>'`.
   Si le plugin est déconnecté : onglet Plugins → « MCP Server » → Connect pendant que le daemon tourne.
