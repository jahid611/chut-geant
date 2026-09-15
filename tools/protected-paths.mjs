#!/usr/bin/env node
// Chemins proteges pendant qu'un agent ecrit dans le depot (tools/gpt-implement.mjs). Controle independant de Git :
// fichiers ignores et metadonnees .git compris, avant et apres chaque passage.
//
// - Petits fichiers sensibles : .env* et place .rbxl* a la racine, metadonnees .git (config, HEAD, packed-refs, refs/,
//   hooks/, info/). Existence et contenu copies avant le passage dans un instantane hors depot et hors dossiers
//   inscriptibles par le sandbox de Codex (%LOCALAPPDATA%), l'empreinte sha256 de chaque copie restant en memoire.
//   Apres le passage, l'etat exact est restaure : contenu d'avant pour un fichier modifie ou supprime, suppression
//   seulement pour un fichier qui n'existait pas avant. Une copie alteree n'est jamais restauree.
// - Index Git : compare logiquement (git ls-files --stage), un simple git status pouvant reecrire ses octets.
// - Gros dossiers d'assets locaux (~1,5 Go) et etat de l'arbitre : inventaire chemin + taille + date de modification
//   (hacher tout a chaque passage serait trop long, limite assumee) ; toute difference est signalee, sans restauration.
// Les contenus ne sont jamais ecrits dans les journaux : seuls les chemins le sont.

import { createHash, randomUUID } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";

import { git, root } from "./git-state.mjs";

const LARGE_DIRS = [
  "assets/models",
  "assets/concepts",
  "assets/textures",
  "docs/captures",
  "docs/videos",
  "tools/reviews/tasks",
];
const GIT_META_FILES = [".git/config", ".git/HEAD", ".git/packed-refs"];
const GIT_META_DIRS = [".git/refs", ".git/hooks", ".git/info"];

const sha256 = (buffer) => createHash("sha256").update(buffer).digest("hex");
const toRepoPath = (full) => relative(root, full).replace(/\\/g, "/");

function walk(dir, out) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) walk(path, out);
    else if (entry.isFile()) out.push(path);
  }
  return out;
}

// Petits fichiers proteges : liste fixe (meme absents) + fichiers presents a cet instant qui correspondent aux motifs.
function smallProtectedPaths() {
  const paths = new Set(GIT_META_FILES);
  for (const name of readdirSync(root)) {
    if (/^\.env/.test(name) || /\.rbxlx?(\.lock)?$/.test(name)) paths.add(name);
  }
  for (const dir of GIT_META_DIRS) {
    for (const file of walk(join(root, dir), [])) paths.add(toRepoPath(file));
  }
  return paths;
}

function largeInventory() {
  const inventory = new Map();
  for (const dir of LARGE_DIRS) {
    for (const file of walk(join(root, dir), [])) {
      const stat = statSync(file);
      inventory.set(toRepoPath(file), `${stat.size}:${stat.mtimeMs}`);
    }
  }
  return inventory;
}

const logicalIndex = () => sha256(git(["ls-files", "--stage", "-z"]));
const currentHead = () => git(["rev-parse", "HEAD"]).trim();

export function takeSnapshot() {
  const base = process.env.LOCALAPPDATA ?? join(root, "..");
  const dir = join(base, "chut-geant-protect", randomUUID());
  mkdirSync(dir, { recursive: true });
  try {
    const small = new Map();
    for (const path of smallProtectedPaths()) {
      const full = join(root, path);
      if (!existsSync(full)) {
        small.set(path, { exists: false });
        continue;
      }
      // Empreinte du contenu exactement copie (une seule lecture) : la copie et sa reference ne peuvent pas diverger.
      const content = readFileSync(full);
      const copy = join(dir, path);
      mkdirSync(dirname(copy), { recursive: true });
      writeFileSync(copy, content);
      small.set(path, { exists: true, hash: sha256(content), copy });
    }
    return { dir, small, large: largeInventory(), index: logicalIndex(), head: currentHead() };
  } catch (error) {
    // Instantane inacheve : aucun passage n'a encore eu lieu, les originaux sont intacts, la copie partielle part.
    rmSync(dir, { recursive: true, force: true });
    throw error;
  }
}

// Compare l'etat actuel a l'instantane, restaure les petits fichiers proteges et rend le rapport (chemins seulement).
export function checkAndRestore(snapshot) {
  const report = {
    restored: [],
    removed: [],
    tampered: [],
    largeChanged: [],
    indexChanged: false,
    headChanged: false,
  };
  const paths = new Set([...snapshot.small.keys(), ...smallProtectedPaths()]);
  for (const path of paths) {
    const before = snapshot.small.get(path) ?? { exists: false };
    const full = join(root, path);
    const existsNow = existsSync(full);
    if (!before.exists) {
      // cree pendant le passage : seul cas ou l'on supprime
      if (existsNow) {
        unlinkSync(full);
        report.removed.push(path);
      }
      continue;
    }
    if (existsNow && sha256(readFileSync(full)) === before.hash) continue;
    if (!existsSync(before.copy) || sha256(readFileSync(before.copy)) !== before.hash) {
      report.tampered.push(path);
      continue;
    }
    mkdirSync(dirname(full), { recursive: true });
    copyFileSync(before.copy, full);
    report.restored.push(path);
  }
  const large = largeInventory();
  for (const [path, signature] of large) {
    if (snapshot.large.get(path) !== signature) report.largeChanged.push(path);
  }
  for (const path of snapshot.large.keys()) {
    if (!large.has(path)) report.largeChanged.push(path);
  }
  report.indexChanged = logicalIndex() !== snapshot.index;
  report.headChanged = currentHead() !== snapshot.head;
  return report;
}

export function disposeSnapshot(snapshot) {
  rmSync(snapshot.dir, { recursive: true, force: true });
}
