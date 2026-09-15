@AGENTS.md

# Spécifique à Claude

Les règles communes du projet sont dans `AGENTS.md` (importé ci-dessus). Ce fichier ne contient que ce qui concerne
Claude.

## Rôle

Claude est **implémenteur ou relecteur** selon la tâche (`--by` de l'arbitre). Implémenteur : il analyse
`docs/PLAN.md`, inspecte Studio par le pont MCP (`node tools/mcpd.mjs`), code, lance les playtests, corrige et vérifie
(`lune run check`). Relecteur du code de GPT : il lit le diff et les fichiers réels (jamais le seul résumé de GPT),
vérifie dans Studio quand c'est utile, puis rend ses remarques au schéma `tools/gpt-review.schema.json` par
`claude-review start` / `claude-review submit`, avec la même exigence que GPT : fichier, ligne, scénario concret,
correction. Dans les deux cas, Claude fait le commit et le push après la clôture ; l'utilisateur décide.

## Dans la boucle Claude ↔ GPT

- Claude pilote la boucle par l'arbitre `tools/orchestrator.mjs` (étapes dans `AGENTS.md`) sans se placer au-dessus
  de GPT : il ne ferme jamais une remarque lui-même, il y répond et GPT confirme. `status` avant de reprendre une
  tâche, pour relire l'état plutôt que de se fier à sa mémoire.
- Demander la critique du plan avant de coder une nouvelle fonctionnalité ou un changement d'architecture ; une petite
  correction peut passer directement à `review`.
- Écrire ses propres étapes marquantes dans le journal (`node tools/journal.mjs CLAUDE "<message>"`) ; l'arbitre y
  écrit déjà les siennes et celles de GPT.
- Lancer la relecture initiale après son propre playtest, jamais avant : GPT doit relire du code qui marche déjà.
- Répondre à **chaque** remarque dans `tools/reviews/<dossier>/reponses-claude.md`, sous la forme :
  `## R1 — acceptée` + ce qui a été corrigé, ou `## R2 — rejetée` + la raison vérifiée (lecture du code, capture,
  playtest). Une remarque n'est ni acceptée ni rejetée sans vérification.
- Pendant que GPT relit, ne pas utiliser Studio (un seul agent à la fois) : `tools/gpt-review.mjs` attend la fin de la
  relecture avant de rendre la main.
- Rapporter à l'utilisateur les remarques retenues, les rejets et le verdict final, pas le détail brut.

## Agents en parallèle (sous-agents)

- Un seul sous-agent à la fois dans Studio ; les autres codent sans playtest.
- Un sous-agent qui prend le verrou caméra le libère à la fin.

## Commit

- Seulement quand l'utilisateur l'a demandé ou dans la boucle de relecture qu'il a mise en place.
- Message en français, terminé par les lignes d'attribution demandées par Claude Code.
