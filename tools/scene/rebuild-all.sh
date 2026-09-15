#!/usr/bin/env bash
# Reconstruit toute la scene dans l'ordre : la chambre (qui recree les zones de base Base1..Base6), puis chaque
# interieur de base (qui renomme sa zone et la deplace devant sa boite a jouets). A lancer depuis la racine du projet,
# Studio ouvert avec le plugin MCP connecte (daemon tools/mcp-daemon.mjs en route) :
#   bash tools/scene/rebuild-all.sh
set -u
cd "$(dirname "$0")/../.."
for recipe in \
  build-chambre \
  build-interieur-pantoufle \
  build-interieur-mouchoirs \
  build-interieur-chaussures \
  build-interieur-cereales \
  build-interieur-tiroir \
  build-interieur-carton \
  build-cuisine; do
  echo "== $recipe"
  node tools/scene-run.mjs "tools/scene/$recipe.luau" 2>&1 | tail -c 400
  echo
done
