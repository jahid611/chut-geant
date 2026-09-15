#!/usr/bin/env node
/**
 * mcp-session — enchaine plusieurs appels MCP dans UN seul serveur.
 *
 * Pourquoi : le serveur MCP ne vit que le temps du processus. Lance pour une
 * commande isolee, il meurt avant que les pairs d'un playtest (serveur, clients)
 * aient eu le temps de s'y rattacher — d'ou les "ConnectFail" en boucle et un
 * playtest invisible pour le MCP. Ici le serveur reste vivant du premier au
 * dernier appel, ce qui laisse aux pairs le temps d'apparaitre.
 *
 * Usage :
 *   node tools/mcp-session.mjs <script.json>
 *
 * Le script est une liste d'etapes :
 *   [
 *     { "tool": "multiplayer_playtest", "args": { "action": "start", "numPlayers": 2 } },
 *     { "waitRole": "server", "timeoutMs": 90000 },
 *     { "tool": "eval_server_runtime", "file": "tools/scratch/which-map.luau" }
 *   ]
 */

import { spawn } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';

const [, , scriptPath] = process.argv;
if (!scriptPath) {
    console.error('usage: mcp-session.mjs <script.json>');
    process.exit(2);
}

/**
 * Charge .env dans l environnement du serveur MCP.
 *
 * Les cles Open Cloud n ont pas leur place dans une ligne de commande : elles
 * apparaitraient dans l historique du shell et dans les journaux. Le fichier
 * est ignore par git, c est la convention du projet.
 */
function loadEnv() {
    if (!existsSync('.env')) return;
    for (const line of readFileSync('.env', 'utf8').split(String.fromCharCode(10))) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eq = trimmed.indexOf('=');
        if (eq === -1) continue;
        process.env[trimmed.slice(0, eq)] = trimmed.slice(eq + 1);
    }
}
loadEnv();

const steps = JSON.parse(readFileSync(scriptPath, 'utf8'));
const TIMEOUT_MS = Number(process.env.MCP_TIMEOUT ?? 240000);

const child = spawn('npx', ['-y', process.env.MCP_PACKAGE ?? '@chrrxs/robloxstudio-mcp@3.1.2'], {
    stdio: ['pipe', 'pipe', 'pipe'],
    shell: true,
});

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
        if (message.id !== undefined && pending.has(message.id)) {
            const { resolve, reject } = pending.get(message.id);
            pending.delete(message.id);
            if (message.error) reject(new Error(JSON.stringify(message.error)));
            else resolve(message.result);
        }
    }
});

child.stderr.on('data', () => {});

function send(method, params) {
    const id = nextId++;
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        setTimeout(() => {
            if (pending.has(id)) {
                pending.delete(id);
                reject(new Error(`${method} : delai depasse`));
            }
        }, TIMEOUT_MS);
    });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function callTool(name, args) {
    const result = await send('tools/call', { name, arguments: args ?? {} });
    return (result.content ?? []).map((c) => c.text ?? `[${c.type}]`).join('\n');
}

/** Attend qu'un role (edit, server, client) apparaisse parmi les pairs connectes. */
async function waitRole(role, timeoutMs) {
    const deadline = Date.now() + (timeoutMs ?? 90000);
    let last = '';
    while (Date.now() < deadline) {
        last = await callTool('get_connected_instances', {});
        if (last.includes(`"${role}"`)) return `role ${role} present`;
        await sleep(3000);
    }
    return `role ${role} ABSENT apres attente — ${last.slice(0, 300)}`;
}

try {
    await send('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'mcp-session', version: '1.0.0' },
    });
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} })}\n`);

    /**
     * Attend que le plugin Studio se presente.
     *
     * Le plugin se rattache par sondage, et il ne le fait pas dans la seconde
     * qui suit le demarrage du serveur : une attente fixe echouait une fois sur
     * deux. On sonde jusqu a ce qu il reponde, plutot que de parier sur un delai.
     */
    async function waitForPeer() {
        const deadline = Date.now() + Number(process.env.MCP_PEER_TIMEOUT ?? 150000);
        let last = '';
        while (Date.now() < deadline) {
            last = await callTool('get_place_info', {});
            if (!last.includes('No Studio Peer')) {
                console.log('--- plugin Studio connecte');
                return true;
            }
            await sleep(4000);
        }
        console.error('--- plugin Studio absent apres attente : ' + last.slice(0, 200));
        return false;
    }
    await waitForPeer();

    for (const [i, step] of steps.entries()) {
        if (step.sleepMs) {
            await sleep(step.sleepMs);
            console.log(`--- etape ${i + 1} : pause ${step.sleepMs} ms`);
            continue;
        }
        if (step.waitRole) {
            console.log(`--- etape ${i + 1} : attente du role ${step.waitRole}`);
            console.log(await waitRole(step.waitRole, step.timeoutMs));
            continue;
        }
        const args = step.file ? { ...step.args, code: readFileSync(step.file, 'utf8') } : step.args;
        console.log(`--- etape ${i + 1} : ${step.tool}`);
        console.log((await callTool(step.tool, args)).slice(0, 4000));
    }
} catch (error) {
    console.error(`ECHEC : ${error.message}`);
    child.kill();
    process.exit(1);
}

child.kill();
process.exit(0);
