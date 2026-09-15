#!/usr/bin/env node
// Etat Git partage par tools/gpt-review.mjs et tools/orchestrator.mjs : fichiers changes et empreinte du code.
//
// Chemins lus en sortie -z (separes par NUL) : sans cela, Git cite et echappe les noms accentues (core.quotepath),
// et un chemin comme docs/économie.md devient illisible pour les lectures qui suivent.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { closeSync, existsSync, openSync, readSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// Commande git ; leve une erreur si elle ne peut pas tourner ou si son code n'est pas dans okCodes.
export function git(args, okCodes = [0]) {
  const result = spawnSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  if (result.error) throw new Error(`git ${args.join(" ")} : ${result.error.message}`);
  if (!okCodes.includes(result.status)) {
    throw new Error(`git ${args.join(" ")} (code ${result.status}) : ${result.stderr.trim()}`);
  }
  return result.stdout;
}

const splitNul = (text) => text.split("\0").filter(Boolean);

export function trackedChanges(base = "HEAD") {
  return splitNul(git(["diff", "--name-only", "-z", base, "--", "."]));
}

export function untrackedFiles() {
  return splitNul(git(["ls-files", "--others", "--exclude-standard", "-z"]));
}

export function changedFiles(base = "HEAD") {
  return [...new Set([...trackedChanges(base), ...untrackedFiles()])];
}

// Contenu entier d'un fichier, lu par blocs d'1 Mo : aucune taille n'est exclue de l'empreinte.
function hashFileContent(hash, path) {
  const fd = openSync(path, "r");
  const buffer = Buffer.alloc(1024 * 1024);
  try {
    let read;
    while ((read = readSync(fd, buffer, 0, buffer.length, null)) > 0) {
      hash.update(buffer.subarray(0, read));
    }
  } finally {
    closeSync(fd);
  }
}

// Empreinte objective de l'etat du code : commit HEAD, modifications suivies, noms et contenu complet des fichiers
// nouveaux. Deux etats differents du depot (autre commit, meme patch local, gros fichier modifie) ne partagent donc
// pas la meme empreinte. Une lecture impossible fait echouer le calcul (exception) au lieu d'etre ignoree.
export function workHash() {
  const hash = createHash("sha1");
  hash.update(git(["rev-parse", "HEAD"]));
  hash.update(git(["diff", "HEAD", "--binary"]));
  for (const file of untrackedFiles()) {
    const path = join(root, file);
    hash.update(`\0${file}\0`);
    if (existsSync(path)) hashFileContent(hash, path);
    else hash.update("\0(supprime pendant le calcul)\0");
  }
  return hash.digest("hex").slice(0, 12);
}
