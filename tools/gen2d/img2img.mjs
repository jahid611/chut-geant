// FLUX schnell en image vers image dans ComfyUI (creator-suite/tools/comfyui, port 8188) : l'image de référence
// (rendu exact du modèle du jeu) garde la forme et les couleurs, le texte n'apporte que le style d'icône.
//
//   node tools/gen2d/img2img.mjs <reference.png> "<prompt>" <sortie.png> [--denoise 0.45] [--steps 4] [--seed N]
//
// denoise bas (0,35-0,5) = fidèle au rendu ; au-delà de 0,6 FLUX réinvente l'objet (le défaut qu'on corrige).
import fs from "node:fs";
import path from "node:path";

const HOST = process.env.COMFY_URL || "http://127.0.0.1:8188";
const args = process.argv.slice(2);
const option = (flag, fallback) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : fallback;
};
const [reference, prompt, out] = args;
if (!reference || !prompt || !out) {
  console.error('usage : node tools/gen2d/img2img.mjs <reference.png> "<prompt>" <sortie.png> [--denoise 0.45] [--steps 4] [--seed N]');
  process.exit(1);
}
const denoise = Number(option("--denoise", "0.45"));
const steps = Number(option("--steps", "4"));
const seed = Number(option("--seed", String(Math.floor(Math.random() * 1e12))));

const ready = await fetch(`${HOST}/system_stats`).then((r) => r.ok).catch(() => false);
if (!ready) {
  console.error(`ComfyUI ne répond pas sur ${HOST}`);
  process.exit(2);
}

// Envoi de la référence dans le dossier input de ComfyUI.
const form = new FormData();
form.append("image", new Blob([fs.readFileSync(reference)], { type: "image/png" }), path.basename(reference));
form.append("overwrite", "true");
const uploaded = await (await fetch(`${HOST}/upload/image`, { method: "POST", body: form })).json();

const workflow = {
  1: { class_type: "UNETLoader", inputs: { unet_name: "flux1-schnell-fp8.safetensors", weight_dtype: "fp8_e4m3fn" } },
  2: { class_type: "DualCLIPLoader", inputs: { clip_name1: "t5xxl_fp8_e4m3fn.safetensors", clip_name2: "clip_l.safetensors", type: "flux" } },
  3: { class_type: "VAELoader", inputs: { vae_name: "ae.safetensors" } },
  4: { class_type: "CLIPTextEncode", inputs: { text: prompt, clip: ["2", 0] } },
  5: { class_type: "LoadImage", inputs: { image: uploaded.name } },
  13: { class_type: "ImageScale", inputs: { image: ["5", 0], upscale_method: "lanczos", width: 1024, height: 1024, crop: "center" } },
  14: { class_type: "VAEEncode", inputs: { pixels: ["13", 0], vae: ["3", 0] } },
  6: { class_type: "BasicGuider", inputs: { model: ["1", 0], conditioning: ["4", 0] } },
  7: { class_type: "KSamplerSelect", inputs: { sampler_name: "euler" } },
  8: { class_type: "BasicScheduler", inputs: { model: ["1", 0], scheduler: "simple", steps, denoise } },
  9: { class_type: "RandomNoise", inputs: { noise_seed: seed } },
  10: { class_type: "SamplerCustomAdvanced", inputs: { noise: ["9", 0], guider: ["6", 0], sampler: ["7", 0], sigmas: ["8", 0], latent_image: ["14", 0] } },
  11: { class_type: "VAEDecode", inputs: { samples: ["10", 0], vae: ["3", 0] } },
  12: { class_type: "SaveImage", inputs: { filename_prefix: "chut/img2img", images: ["11", 0] } },
};

const queued = await (await fetch(`${HOST}/prompt`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ prompt: workflow }) })).json();
if (queued.error) {
  console.error("ComfyUI :", JSON.stringify(queued.error || queued.node_errors));
  process.exit(3);
}
const started = Date.now();
for (;;) {
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const history = await (await fetch(`${HOST}/history/${queued.prompt_id}`)).json();
  const item = history[queued.prompt_id];
  if (item?.status?.status_str === "error") {
    console.error("ComfyUI :", JSON.stringify(item.status.messages).slice(0, 800));
    process.exit(4);
  }
  const image = item ? Object.values(item.outputs || {}).flatMap((o) => o.images || [])[0] : null;
  if (image) {
    const url = `${HOST}/view?filename=${encodeURIComponent(image.filename)}&subfolder=${encodeURIComponent(image.subfolder || "")}&type=${image.type}`;
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, Buffer.from(await (await fetch(url)).arrayBuffer()));
    console.log(`ok ${out} (denoise ${denoise}, seed ${seed}, ${Math.round((Date.now() - started) / 1000)} s)`);
    break;
  }
  if (Date.now() - started > 15 * 60 * 1000) {
    console.error("délai dépassé");
    process.exit(5);
  }
}
