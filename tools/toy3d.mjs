#!/usr/bin/env node
/**
 * Transforme une image de reference en maillage texture, avec le graphe
 * TRELLIS 2 de ComfyUI, et range le GLB dans assets/models/glb.
 *
 *   node tools/toy3d.mjs <image.png> <nom>
 *
 * ComfyUI doit tourner (creator-suite/tools/comfyui/start.bat). Le graphe
 * detoure l'objet lui-meme (BiRefNet) et decime a 9 500 faces, sous le plafond
 * de 10 000 triangles d'une MeshPart Roblox. On ne touche qu'a deux noeuds :
 * l'image chargee et le prefixe du fichier ecrit.
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const COMFY = 'C:/Users/jahidsyd/creator-suite/tools/comfyui';
const PORTABLE = path.join(COMFY, 'ComfyUI_windows_portable');
const INPUT = path.join(PORTABLE, 'ComfyUI', 'input');
const OUTPUT = path.join(PORTABLE, 'ComfyUI', 'output');
const GRAPH = path.join(COMFY, 'trellis2-api.json');
const DEST = path.join(root, 'assets', 'models', 'glb');

const [image, name] = process.argv.slice(2);
if (!image || !name) {
    console.log('usage : node tools/toy3d.mjs <image.png> <nom>');
    process.exit(2);
}

const inputName = `chut_${name}.png`;
fs.copyFileSync(path.resolve(image), path.join(INPUT, inputName));

const graph = JSON.parse(fs.readFileSync(GRAPH, 'utf8'));
for (const node of Object.values(graph)) {
    if (node.class_type === 'LoadImage') node.inputs.image = inputName;
    if (node.class_type === 'SaveGLB') node.inputs.filename_prefix = `chut/${name}`;
}
const graphPath = path.join(os.tmpdir(), `chut_${name}.json`);
fs.writeFileSync(graphPath, JSON.stringify(graph));

const started = Date.now();
execFileSync(path.join(PORTABLE, 'python_embeded', 'python.exe'), [path.join(COMFY, 'run3d.py'), graphPath], {
    stdio: 'inherit',
});

// Le plus recent GLB du prefixe, ecrit apres le lancement.
const outDir = path.join(OUTPUT, 'chut');
const produced = fs
    .readdirSync(outDir)
    .filter((f) => f.startsWith(`${name}_`) && f.endsWith('.glb'))
    .map((f) => ({ f, t: fs.statSync(path.join(outDir, f)).mtimeMs }))
    .filter((e) => e.t >= started)
    .sort((a, b) => b.t - a.t)[0];
if (!produced) {
    console.log('aucun GLB produit');
    process.exit(1);
}
fs.mkdirSync(DEST, { recursive: true });
const target = path.join(DEST, `${name}.glb`);
fs.copyFileSync(path.join(outDir, produced.f), target);
console.log(`GLB -> ${target} (${(fs.statSync(target).size / 1048576).toFixed(1)} Mo)`);
