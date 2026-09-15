#!/usr/bin/env node
/**
 * mcp-daemon — garde un seul serveur MCP en vie, et lui fait passer les appels.
 *
 * Pourquoi. Le plugin Studio s'attache au serveur qu'il trouve, puis ne se
 * rattache plus quand celui-ci disparait : il faut rouvrir son panneau et
 * cliquer « Connect ». Or `mcp-cli` lance un serveur neuf a chaque appel et le
 * tue en sortant. Le pair est donc perdu des le deuxieme appel, et toute la
 * session se passe a recliquer.
 *
 * Ce daemon inverse le rapport : le serveur vit tant que le daemon vit, le
 * plugin reste attache, et les appels arrivent par une socket locale. Un
 * playtest complet — demarrer, equiper, mesurer, lire les logs, arreter —
 * tient dans une seule vie de serveur.
 *
 * Usage :
 *   node tools/mcp-daemon.mjs          # a lancer en tache de fond
 *   node tools/mcpd.mjs <outil> '<json>'
 */

import fs from 'node:fs';
import net from 'node:net';
import { spawn } from 'node:child_process';

const PORT = Number(process.env.MCP_DAEMON_PORT ?? 58999);

/** Charge .env, comme mcp-cli : les outils Open Cloud en ont besoin. */
function loadEnv() {
    if (!fs.existsSync('.env')) return;
    for (const line of fs.readFileSync('.env', 'utf8').split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eq = trimmed.indexOf('=');
        if (eq === -1) continue;
        process.env[trimmed.slice(0, eq)] = trimmed.slice(eq + 1);
    }
}
loadEnv();

const child = spawn(
    'npx',
    ['-y', process.env.MCP_PACKAGE ?? '@chrrxs/robloxstudio-mcp@3.1.2'],
    { stdio: ['pipe', 'pipe', 'pipe'], shell: true },
);

let buffer = '';
const pending = new Map();
let nextId = 1;

child.stdout.on('data', (chunk) => {
    buffer += chunk.toString();
    let index;
    while ((index = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (!line) continue;
        let message;
        try {
            message = JSON.parse(line);
        } catch {
            continue;
        }
        const entry = pending.get(message.id);
        if (entry === undefined) continue;
        pending.delete(message.id);
        if (message.error) entry.reject(new Error(message.error.message ?? 'erreur MCP'));
        else entry.resolve(message.result);
    }
});

child.stderr.on('data', (chunk) => process.stderr.write(chunk));
child.on('exit', (code) => {
    console.error(`serveur MCP termine (code ${code})`);
    process.exit(1);
});

function send(method, params) {
    const id = nextId++;
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        setTimeout(() => {
            if (pending.delete(id)) reject(new Error('delai depasse'));
        }, Number(process.env.MCP_TIMEOUT ?? 240000));
    });
}

function notify(method, params) {
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
}

/**
 * Attend que le plugin se presente.
 *
 * Le serveur repond des son lancement, mais sans pair tout appel renvoie
 * « No Studio Peer ». On sonde jusqu'a ce qu'il soit la plutot que de laisser
 * le premier appel echouer.
 */
async function waitForPeer(deadlineMs) {
    const deadline = Date.now() + deadlineMs;
    let last = '';
    while (Date.now() < deadline) {
        try {
            const probe = await send('tools/call', { name: 'get_place_info', arguments: {} });
            last = (probe.content ?? []).map((c) => c.text ?? '').join('');
            if (!last.includes('No Studio Peer')) return true;
        } catch (e) {
            last = e.message;
        }
        await new Promise((r) => setTimeout(r, 2000));
    }
    console.error(`aucun pair Studio : ${last.slice(0, 200)}`);
    return false;
}

await send('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'mcp-daemon', version: '1.0.0' },
});
notify('notifications/initialized', {});

const ok = await waitForPeer(Number(process.env.MCP_WAIT_MS ?? 180000));
console.log(ok ? 'pair Studio attache' : 'demarre sans pair : les appels echoueront tant que le plugin ne vient pas');

const server = net.createServer((socket) => {
    let incoming = '';
    // Un client qui raccroche brutalement (ECONNRESET) ne doit pas emporter
    // le daemon avec lui : sans ce gestionnaire, l'evenement est fatal.
    socket.on('error', (e) => {
        console.log(`client parti : ${e.code ?? e.message}`);
    });
    socket.on('data', async (chunk) => {
        incoming += chunk.toString();
        let index;
        while ((index = incoming.indexOf('\n')) !== -1) {
            const line = incoming.slice(0, index).trim();
            incoming = incoming.slice(index + 1);
            if (!line) continue;
            let request;
            try {
                request = JSON.parse(line);
            } catch (e) {
                socket.write(`${JSON.stringify({ error: `json invalide : ${e.message}` })}\n`);
                continue;
            }
            try {
                const result = await send('tools/call', {
                    name: request.tool,
                    arguments: request.args ?? {},
                });
                const text = (result.content ?? [])
                    .filter((c) => c.type === 'text')
                    .map((c) => c.text)
                    .join('\n');
                // Les images sont ecrites sur le disque : une capture comptee en
                // octets dans la reponse ne sert a personne.
                const images = [];
                for (const item of result.content ?? []) {
                    if (item.type !== 'image' || !item.data) continue;
                    const dir = process.env.MCP_SHOT_DIR ?? 'tools/shots';
                    fs.mkdirSync(dir, { recursive: true });
                    const ext = (item.mimeType ?? 'image/jpeg').split('/')[1] ?? 'jpg';
                    const name = `${dir}/shot-${new Date().toISOString().replace(/[:.]/g, '-')}.${ext}`;
                    fs.writeFileSync(name, Buffer.from(item.data, 'base64'));
                    images.push(name);
                }
                socket.write(`${JSON.stringify({ text, images })}\n`);
            } catch (e) {
                socket.write(`${JSON.stringify({ error: e.message })}\n`);
            }
        }
    });
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`daemon a l'ecoute sur 127.0.0.1:${PORT}`);
});
