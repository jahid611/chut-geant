/**
 * Televerse un dossier de FBX (ou d'images) sur Roblox via Open Cloud, et
 * tient un registre des identifiants obtenus.
 *
 *   node tools/upload-models.mjs <dossier> <registre.json> [description] [--images]
 *
 *   node tools/upload-models.mjs assets/weapons/fbx assets/weapons/registry.json "ORBIT armes"
 *   node tools/upload-models.mjs assets/hub assets/hub/registry.json "ORBIT hub"
 *   node tools/upload-models.mjs assets/weapons/skins assets/weapons/skins.json "ORBIT camos" --images
 *
 * Meme principe que upload-bestiary.mjs, dont ce script est la version
 * generique : l'API d'assets repond une operation, sondee jusqu'a l'identifiant.
 * Le registre fait foi — un nom deja present n'est pas renvoye, ce qui rend le
 * lot reprenable et evite de creer deux fois le meme asset. Pour forcer un
 * nouvel envoi, retirer l'entree du registre.
 *
 * Une image est televersee comme Decal ; l'identifiant d'Image (celui que
 * TextureID et ColorMap attendent) se releve ensuite dans Studio, comme pour
 * les icones (tools/upload-icons.mjs).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2).filter(a => !a.startsWith('--'));
const flags = process.argv.slice(2).filter(a => a.startsWith('--'));
if (args.length < 2) {
    console.log('usage : node tools/upload-models.mjs <dossier> <registre.json> [description] [--images]');
    process.exit(1);
}
const DIR = path.resolve(root, args[0]);
const REGISTRY = path.resolve(root, args[1]);
const DESCRIPTION = args[2] ?? 'ORBIT';
const IMAGES = flags.includes('--images');

function env(name) {
    const line = fs.readFileSync(path.join(root, '.env'), 'utf8')
        .split('\n').find(l => l.startsWith(`${name}=`));
    if (!line) throw new Error(`${name} absent de .env`);
    return line.slice(name.length + 1).trim();
}
const KEY = env('ROBLOX_OPEN_CLOUD_API_KEY');
const USER = env('ROBLOX_CREATOR_USER_ID');

const registry = fs.existsSync(REGISTRY) ? JSON.parse(fs.readFileSync(REGISTRY, 'utf8')) : {};
const save = () => fs.writeFileSync(REGISTRY, JSON.stringify(registry, null, 1));

async function poll(operationId) {
    for (let i = 0; i < 90; i += 1) {
        await new Promise(r => setTimeout(r, 4000));
        const res = await fetch(`https://apis.roblox.com/assets/v1/operations/${operationId}`,
            { headers: { 'x-api-key': KEY } });
        const data = await res.json();
        if (data.done) {
            if (data.error) throw new Error(JSON.stringify(data.error).slice(0, 300));
            return data.response.assetId;
        }
    }
    throw new Error('operation jamais terminee');
}

async function upload(name, file) {
    const ext = path.extname(file).toLowerCase();
    const form = new FormData();
    form.append('request', JSON.stringify({
        assetType: IMAGES ? 'Decal' : 'Model',
        displayName: name,
        description: DESCRIPTION,
        creationContext: { creator: { userId: USER } },
    }));
    const mime = IMAGES ? (ext === '.jpg' || ext === '.jpeg' ? 'image/jpeg' : 'image/png') : 'model/fbx';
    form.append('fileContent', new Blob([fs.readFileSync(file)], { type: mime }), path.basename(file));

    const res = await fetch('https://apis.roblox.com/assets/v1/assets',
        { method: 'POST', headers: { 'x-api-key': KEY }, body: form });
    const text = await res.text();
    if (!res.ok) throw new Error(`${res.status} ${text.slice(0, 300)}`);
    const { operationId } = JSON.parse(text);
    return poll(operationId);
}

const wanted = IMAGES ? ['.png', '.jpg', '.jpeg'] : ['.fbx'];
const files = fs.readdirSync(DIR).filter(f => wanted.includes(path.extname(f).toLowerCase())).sort();
console.log(`${files.length} fichier(s) dans ${path.relative(root, DIR)}, ${Object.keys(registry).length} deja au registre`);

let done = 0;
for (const [i, file] of files.entries()) {
    const name = path.basename(file, path.extname(file));
    if (registry[name]?.assetId) continue;
    try {
        const assetId = await upload(name, path.join(DIR, file));
        registry[name] = { assetId, uploaded: new Date().toISOString().slice(0, 10) };
        save();
        done += 1;
        console.log(`[${i + 1}/${files.length}] ${name} -> ${assetId}`);
    } catch (error) {
        console.log(`[${i + 1}/${files.length}] ECHEC ${name} : ${String(error.message).slice(0, 200)}`);
        // Un refus de moderation : on s'arrete, relancer en boucle prolonge le blocage du compte.
        if (/moderat/i.test(String(error.message))) break;
    }
    // La moderation se declenche sur le volume : on souffle entre deux envois (UPLOAD_PAUSE_S, 90 s par defaut).
    if (i < files.length - 1) {
        await new Promise(r => setTimeout(r, Number(process.env.UPLOAD_PAUSE_S ?? 90) * 1000));
    }
}
console.log(`${done} televerse(s), ${Object.keys(registry).length} au registre ${path.relative(root, REGISTRY)}`);
