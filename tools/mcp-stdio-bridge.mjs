#!/usr/bin/env node
/**
 * mcp-stdio-bridge — serveur MCP (stdio) qui relaie vers le daemon MCP de Studio.
 *
 * Pourquoi. Studio n'accepte qu'un serveur MCP a la fois : le plugin s'attache au premier et decroche si un autre
 * apparait. Claude passe par le daemon (tools/mcp-daemon.mjs, socket 127.0.0.1:58999). Codex (GPT) lance ses
 * serveurs MCP en stdio : cet adaptateur lui donne les memes outils, sur la meme connexion, sans second serveur.
 *
 * Declaration dans la configuration de Codex (AGENTS.md, « Pont MCP ») :
 *   command = "node", args = ["<depot>/tools/mcp-stdio-bridge.mjs"]
 *
 * Chaque appel est journalise (MCP_BRIDGE_LOG, defaut tools/reviews/mcp-calls.log) pour relire ce que le relecteur
 * a fait dans Studio. La liste des outils vient du daemon s'il sait la donner ({"list":true}), sinon d'une liste de
 * secours avec les outils utilises dans ce projet.
 */

import fs from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.env.MCP_DAEMON_PORT ?? 58999);
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOG = process.env.MCP_BRIDGE_LOG ?? path.join(root, 'tools', 'reviews', 'mcp-calls.log');

const objectSchema = (description, properties = {}, required = []) => ({
    type: 'object',
    description,
    properties,
    required,
    additionalProperties: true,
});

const FALLBACK_TOOLS = [
    {
        name: 'get_place_info',
        description: 'Informations sur le place ouvert dans Studio (verifie aussi que le plugin est connecte).',
        inputSchema: objectSchema('Aucun argument'),
    },
    {
        name: 'execute_luau',
        description:
            'Execute du Luau dans Studio en mode edition et rend la valeur retournee. Pour le relecteur : LECTURE SEULE ' +
            '(inspecter instances, attributs, positions) ; jamais de modification, de suppression ni de publication.',
        inputSchema: objectSchema('Code Luau', { code: { type: 'string' } }, ['code']),
    },
    {
        name: 'solo_playtest',
        description: 'Lance, arrete ou interroge un playtest solo. Toujours arreter un playtest que l\'on a lance.',
        inputSchema: objectSchema(
            'action start|stop|status ; mode play|run obligatoire pour start',
            {
                action: { type: 'string', enum: ['start', 'stop', 'status'] },
                mode: { type: 'string', enum: ['play', 'run'] },
            },
            ['action'],
        ),
    },
    {
        name: 'eval_server_runtime',
        description:
            'Execute du Luau cote serveur pendant un playtest. Attente courte seulement (au-dela de quelques minutes, ' +
            'le pont coupe la requete).',
        inputSchema: objectSchema('Code Luau', { code: { type: 'string' } }, ['code']),
    },
    {
        name: 'eval_client_runtime',
        description:
            'Execute du Luau cote client (joueur local) pendant un playtest. Humanoid:Move par script ne fait pas ' +
            'avancer le personnage.',
        inputSchema: objectSchema('Code Luau', { code: { type: 'string' } }, ['code']),
    },
    {
        name: 'get_runtime_logs',
        description: 'Journal de sortie de Studio (messages, avertissements, erreurs) du playtest en cours ou du dernier.',
        inputSchema: objectSchema('Aucun argument'),
    },
];

function log(line) {
    try {
        fs.mkdirSync(path.dirname(LOG), { recursive: true });
        fs.appendFileSync(LOG, `${new Date().toISOString()} ${line}\n`);
    } catch {
        // le journal ne doit jamais faire echouer un appel
    }
}

/** Une requete au daemon : une ligne JSON envoyee, une ligne JSON recue. */
function daemon(payload, timeoutMs) {
    return new Promise((resolve, reject) => {
        const socket = net.connect(PORT, '127.0.0.1', () => {
            socket.write(`${JSON.stringify(payload)}\n`);
        });
        let incoming = '';
        const timer = setTimeout(() => {
            socket.destroy();
            reject(new Error('delai depasse'));
        }, timeoutMs);
        socket.on('data', (chunk) => {
            incoming += chunk.toString();
            const index = incoming.indexOf('\n');
            if (index === -1) return;
            clearTimeout(timer);
            socket.end();
            try {
                resolve(JSON.parse(incoming.slice(0, index)));
            } catch (e) {
                reject(e);
            }
        });
        socket.on('error', (e) => {
            clearTimeout(timer);
            reject(
                e.code === 'ECONNREFUSED'
                    ? new Error(`aucun daemon MCP sur le port ${PORT} : Claude doit lancer « node tools/mcp-daemon.mjs »`)
                    : e,
            );
        });
    });
}

async function listTools() {
    try {
        const reply = await daemon({ list: true }, 15000);
        if (Array.isArray(reply.tools) && reply.tools.length > 0) return reply.tools;
    } catch {
        // daemon ancien (sans {"list":true}) ou absent : liste de secours
    }
    return FALLBACK_TOOLS;
}

async function callTool(name, args) {
    log(`appel ${name} ${JSON.stringify(args ?? {}).slice(0, 500)}`);
    try {
        const reply = await daemon({ tool: name, args: args ?? {} }, Number(process.env.MCP_TIMEOUT ?? 240000));
        if (reply.error) {
            log(`echec ${name} : ${reply.error}`);
            return { content: [{ type: 'text', text: `ECHEC : ${reply.error}` }], isError: true };
        }
        const images = (reply.images ?? []).map((image) => `[capture enregistree] ${image}`);
        const text = [reply.text ?? '', ...images].filter(Boolean).join('\n');
        if (reply.isError) log(`echec ${name} : l'outil a signale une erreur`);
        return { content: [{ type: 'text', text: text || '(aucune sortie)' }], isError: reply.isError === true };
    } catch (e) {
        log(`echec ${name} : ${e.message}`);
        return { content: [{ type: 'text', text: `ECHEC : ${e.message}` }], isError: true };
    }
}

function respond(id, result) {
    process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`);
}

function respondError(id, code, message) {
    process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } })}\n`);
}

async function handle(message) {
    const { id, method, params } = message;
    if (id === undefined) return; // notification (notifications/initialized...) : pas de reponse
    switch (method) {
        case 'initialize':
            respond(id, {
                protocolVersion: params?.protocolVersion ?? '2024-11-05',
                capabilities: { tools: {} },
                serverInfo: { name: 'roblox-studio-bridge', version: '1.0.0' },
            });
            return;
        case 'ping':
            respond(id, {});
            return;
        case 'tools/list':
            respond(id, { tools: await listTools() });
            return;
        case 'tools/call':
            respond(id, await callTool(params?.name, params?.arguments));
            return;
        default:
            respondError(id, -32601, `methode non prise en charge : ${method}`);
    }
}

let buffer = '';
process.stdin.on('data', (chunk) => {
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
        handle(message).catch((e) => {
            if (message.id !== undefined) respondError(message.id, -32603, e.message);
        });
    }
});
process.stdin.on('end', () => process.exit(0));
