// Enchaîne les icônes d'armes v4 depuis les rendus Studio préparés (icone-depuis-rendu.py prep) :
//   node tools/gen2d/lot-armes-v4.mjs <dossier-prep> <dossier-sortie> [--denoise 0.42] [--seeds 2]
// Pour chaque arme : <id>-<angle>-ref.png + masque -> FLUX img2img (plusieurs graines) -> icône découpée à la silhouette,
// puis une planche de comparaison rendu / variantes pour choisir avant tout téléversement.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Z]:)/, "$1")), "..", "..");
const PY = "C:/Users/jahidsyd/creator-suite/tools/comfyui/ComfyUI_windows_portable/python_embeded/python.exe";
const [prepDir, outDir] = process.argv.slice(2);
const option = (flag, fallback) => {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : fallback;
};
const denoise = option("--denoise", "0.42");
const seeds = Number(option("--seeds", "2"));
const lot = JSON.parse(fs.readFileSync(path.join(root, "tools/gen2d/lot-armes-v4.json"), "utf8"));
fs.mkdirSync(outDir, { recursive: true });

const tiles = [];
for (const arme of lot.armes) {
  const base = `${arme.id}-${arme.angle}`;
  const ref = path.join(prepDir, `${base}-ref.png`);
  const mask = path.join(prepDir, `${base}-masque.png`);
  tiles.push(ref);
  for (let s = 1; s <= seeds; s++) {
    const generated = path.join(outDir, `${base}-flux${s}.png`);
    const icon = path.join(outDir, `${arme.id}-v${s}.png`);
    const prompt = `${arme.objet}, ${lot.style}`;
    console.log(execFileSync("node", [path.join(root, "tools/gen2d/img2img.mjs"), ref, prompt, generated, "--denoise", denoise, "--seed", String(1000 * s + 7)], { encoding: "utf8" }).trim());
    console.log(execFileSync(PY, [path.join(root, "tools/gen2d/icone-depuis-rendu.py"), "final", generated, mask, icon, "512"], { encoding: "utf8" }).trim());
    tiles.push(icon);
  }
}
console.log(execFileSync(PY, [path.join(root, "tools/gen2d/icone-depuis-rendu.py"), "planche", path.join(outDir, "planche-armes-v4.png"), ...tiles], { encoding: "utf8" }).trim());
