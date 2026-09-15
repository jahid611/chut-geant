#!/usr/bin/env node
/**
 * Genere un lot d'images en local (ComfyUI + FLUX schnell, creator-suite/tools/imagegen.mjs) depuis un JSON
 * { style_icone, style_3d, icones: [[nom, sujet]], objets3d: [[nom, sujet]] }, une image apres l'autre.
 * Icones : assets/ui/bruts/<nom>.png puis detourage (tools/aicut.py) vers assets/ui/propres/<nom>.png.
 * Objets 3D : assets/concepts/objets3d/<nom>.png (images a donner a l'utilisateur pour Tripo).
 * Les images deja presentes sont sautees (relance sans tout refaire).
 *   node tools/gen2d/gen-lot.mjs tools/gen2d/lot-boutique.json
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '..', '..');
const IMAGEGEN = 'C:\\Users\\jahidsyd\\creator-suite\\tools\\imagegen.mjs';
const PYTHON = 'C:\\Users\\jahidsyd\\creator-suite\\tools\\comfyui\\ComfyUI_windows_portable\\python_embeded\\python.exe';

const lot = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const dirs = {
  bruts: path.join(ROOT, 'assets', 'ui', 'bruts'),
  propres: path.join(ROOT, 'assets', 'ui', 'propres'),
  objets: path.join(ROOT, 'assets', 'concepts', 'objets3d'),
};
for (const d of Object.values(dirs)) fs.mkdirSync(d, { recursive: true });

function generate(prompt, out, w, h) {
  if (fs.existsSync(out)) {
    console.log(`deja la : ${path.basename(out)}`);
    return;
  }
  execFileSync('node', [IMAGEGEN, prompt, '--out', out, '--w', String(w), '--h', String(h)], { stdio: 'inherit' });
  console.log(`ok ${path.basename(out)}`);
}

for (const [name, subject] of lot.icones) {
  const raw = path.join(dirs.bruts, `${name}.png`);
  generate(lot.style_icone + subject, raw, 1024, 1024);
  const clean = path.join(dirs.propres, `${name}.png`);
  if (!fs.existsSync(clean)) {
    execFileSync(PYTHON, [path.join(ROOT, 'tools', 'aicut.py'), raw, clean], { stdio: 'inherit' });
    console.log(`detoure ${name}`);
  }
}
for (const [name, subject] of lot.objets3d) {
  generate(lot.style_3d + subject, path.join(dirs.objets, `${name}.png`), 1024, 1024);
}
console.log('FIN');
