#!/usr/bin/env node
// Controles de texte partages par tools/gpt-implement.mjs et tools/orchestrator.mjs.
//
// Accents abimes : un texte UTF-8 relu comme Windows-1252 puis reecrit laisse des sequences typiques (e accent aigu
// devient A tilde + copyright, tiret long devient a circonflexe + euro + guillemet). Le motif est construit a
// l'execution avec String.fromCharCode : ce fichier source reste en ASCII et ne contient lui-meme aucune de ces
// sequences (verifie par le detecteur ; des sequences d'echappement ecrites telles quelles avaient ete converties en
// vrais caractères a l'enregistrement).

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { git, root } from "./git-state.mjs";

export const TEXT_FILE = /\.(luau|lua|mjs|js|ts|json|md|toml|py|ps1|sh|html|css|yml|yaml|txt)$/i;

const char = (code) => String.fromCharCode(code);
// A tilde suivi d'un caractere de 0x80 a 0xBF ; a circonflexe + euro ; A circonflexe + guillemet, degre ou espace
// insecable.
const MOJIBAKE = new RegExp(
  `${char(0xc3)}[${char(0x80)}-${char(0xbf)}]|${char(0xe2)}${char(0x20ac)}|` +
    `${char(0xc2)}[${char(0xab)}${char(0xbb)}${char(0xb0)}${char(0xa0)}]`,
  "g",
);

export const countMojibake = (text) => (String(text).match(MOJIBAKE) ?? []).length;

export function workingCount(file) {
  const path = join(root, file);
  return existsSync(path) ? countMojibake(readFileSync(path, "utf8")) : 0;
}

function headCount(file) {
  try {
    return countMojibake(git(["show", `HEAD:${file}`]));
  } catch {
    // fichier nouveau : rien dans HEAD
    return 0;
  }
}

// Fichiers texte ou le nombre de sequences d'accents abimes a augmente par rapport a la reference (compte fourni par
// fichier, sinon version de HEAD).
export function introducedMojibake(files, reference = new Map()) {
  const found = [];
  for (const file of files) {
    if (!TEXT_FILE.test(file)) continue;
    const now = workingCount(file);
    const before = reference.has(file) ? reference.get(file) : headCount(file);
    if (now > before) found.push({ fichier: file, avant: before, apres: now });
  }
  return found;
}
