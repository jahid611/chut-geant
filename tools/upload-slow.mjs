#!/usr/bin/env node
/**
 * Televerse un dossier d'images par petits lots, en soufflant entre chacun, et
 * reprend ce qui a echoue.
 *
 *   node tools/upload-slow.mjs <dossier> <registre.json> "<description>" [lot] [pause_s]
 *
 * La moderation automatique de Roblox se declenche sur les rafales : cent
 * motifs abstraits envoyes en deux minutes ont fait tomber le compte deux fois.
 * Par paquets de huit avec une minute de pause, elle laisse passer — et ce qui
 * echoue est repris au tour suivant plutot que perdu.
 *
 * Le registre est le meme que upload-models.mjs : une entree par fichier, avec
 * son assetId. Les entrees deja presentes ne sont pas refaites.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const [dir, registryPath, description = 'ORBIT', batchRaw = '8', pauseRaw = '60'] = process.argv.slice(2);
if (!dir || !registryPath) {
    console.log('usage : node tools/upload-slow.mjs <dossier> <registre.json> "<description>" [lot] [pause_s]');
    process.exit(2);
}
const batch = Number(batchRaw);
const pause = Number(pauseRaw) * 1000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const env = fs.readFileSync('.env', 'utf8');
const value = (key) => {
    const line = env.split('\n').find((l) => l.startsWith(key + '='));
    return line ? line.slice(key.length + 1).trim() : '';
};
const KEY = value('ROBLOX_OPEN_CLOUD_API_KEY');
const USER = value('ROBLOX_CREATOR_USER_ID');

const read = () => (fs.existsSync(registryPath) ? JSON.parse(fs.readFileSync(registryPath, 'utf8')) : {});
const write = (data) => fs.writeFileSync(registryPath, JSON.stringify(data, null, 1));

async function send(file) {
    const request = JSON.stringify({
        assetType: 'Decal',
        displayName: path.parse(file).name.slice(0, 50),
        description,
        creationContext: { creator: { userId: USER } },
    });
    const out = execFileSync(
        'curl',
        [
            '-s', '-m', '120', '-X', 'POST', 'https://apis.roblox.com/assets/v1/assets',
            '-H', `x-api-key: ${KEY}`,
            '-F', `request=${request}`,
            '-F', `fileContent=@${path.join(dir, file)};type=image/png`,
        ],
        { encoding: 'utf8' }
    );
    const started = JSON.parse(out);
    if (started.errors) {
        return { error: started.errors[0]?.message ?? 'refus' };
    }
    // L'operation est asynchrone : on attend qu'elle rende l'identifiant.
    for (let i = 0; i < 30; i += 1) {
        await sleep(2000);
        const state = JSON.parse(
            execFileSync('curl', ['-s', '-m', 60, `https://apis.roblox.com/assets/v1/operations/${started.operationId}`, '-H', `x-api-key: ${KEY}`], { encoding: 'utf8' })
        );
        if (state.done && state.response) {
            return { assetId: state.response.assetId };
        }
        if (state.error || state.errors) {
            return { error: JSON.stringify(state.error ?? state.errors).slice(0, 120) };
        }
    }
    return { error: 'delai depasse' };
}

const files = fs.readdirSync(dir).filter((f) => f.endsWith('.png'));
let done = 0;
let refused = 0;
for (let round = 1; round <= 12; round += 1) {
    const registry = read();
    const todo = files.filter((f) => registry[path.parse(f).name] === undefined);
    if (todo.length === 0) {
        console.log('tout est au registre');
        break;
    }
    console.log(`tour ${round} : ${todo.length} a envoyer`);
    const slice = todo.slice(0, batch);
    let blocked = 0;
    for (const file of slice) {
        const name = path.parse(file).name;
        const result = await send(file);
        const registryNow = read();
        if (result.assetId) {
            registryNow[name] = { assetId: String(result.assetId), uploaded: new Date().toISOString().slice(0, 10) };
            write(registryNow);
            done += 1;
            console.log(`  ok ${name} -> ${result.assetId}`);
        } else {
            refused += 1;
            blocked += 1;
            console.log(`  refus ${name} : ${result.error}`);
            if (String(result.error).includes('moderated')) {
                break;
            }
        }
    }
    if (blocked > 0) {
        console.log(`  pause longue apres refus (${Math.round(pause * 3 / 1000)} s)`);
        await sleep(pause * 3);
    } else {
        await sleep(pause);
    }
}
console.log(`${done} televerse(s), ${refused} refus, ${Object.keys(read()).length} au registre`);
