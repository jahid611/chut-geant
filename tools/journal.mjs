#!/usr/bin/env node
// Journal de tache de la boucle Claude <-> GPT (AGENTS.md) : chaque etape s'y ecrit avec une etiquette et s'affiche
// dans le terminal, pour que l'utilisateur suive le travail sans repondre a chaque etape.
//
//   node tools/journal.mjs <ETIQUETTE> "<message>"
//
// Etiquettes : ORCHESTRATEUR, CLAUDE, GPT, MCP, CHECK, EQUIPE. Fichier : tools/reviews/journal.md (hors depot).
// tools/gpt-review.mjs l'utilise aussi (appendJournal) pour les etapes de GPT.

import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const JOURNAL = join(root, "tools", "reviews", "journal.md");
export const TAGS = ["ORCHESTRATEUR", "CLAUDE", "GPT", "MCP", "CHECK", "EQUIPE"];

export function appendJournal(tag, message) {
  const label = String(tag).toUpperCase();
  const time = new Date().toLocaleTimeString("fr-FR", { hour12: false });
  const line = `[${label}] ${time} ${message}`;
  mkdirSync(dirname(JOURNAL), { recursive: true });
  appendFileSync(JOURNAL, `${line}\n`);
  console.log(line);
}

// Lance en ligne de commande (et pas importe) : la casse de la lettre de lecteur varie sous Windows.
const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href.toLowerCase() : "";
if (import.meta.url.toLowerCase() === invokedPath) {
  const [tag, ...words] = process.argv.slice(2);
  if (!tag || words.length === 0) {
    console.error('usage : node tools/journal.mjs <ETIQUETTE> "<message>"');
    process.exit(2);
  }
  if (!TAGS.includes(tag.toUpperCase())) {
    console.error(`etiquette inconnue : ${tag} (attendu : ${TAGS.join(", ")})`);
    process.exit(2);
  }
  appendJournal(tag, words.join(" "));
}
