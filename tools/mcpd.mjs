#!/usr/bin/env node
/**
 * mcpd — envoie un appel d'outil au daemon MCP.
 *
 *   node tools/mcpd.mjs execute_luau '{"code":"return 1+1"}'
 *
 * Le daemon doit tourner (`node tools/mcp-daemon.mjs`). Sans lui, mieux vaut
 * dire pourquoi que laisser une erreur de connexion brute : le cas arrive a
 * chaque redemarrage de Studio.
 */

import net from 'node:net';

const PORT = Number(process.env.MCP_DAEMON_PORT ?? 58999);
const [, , tool, rawArgs] = process.argv;

if (!tool) {
    console.error("usage: mcpd.mjs <outil> '<json>'");
    process.exit(2);
}

const socket = net.connect(PORT, '127.0.0.1', () => {
    socket.write(`${JSON.stringify({ tool, args: rawArgs ? JSON.parse(rawArgs) : {} })}\n`);
});

let incoming = '';
socket.on('data', (chunk) => {
    incoming += chunk.toString();
    const index = incoming.indexOf('\n');
    if (index === -1) return;
    const reply = JSON.parse(incoming.slice(0, index));
    socket.end();
    if (reply.error) {
        console.error(`ECHEC : ${reply.error}`);
        process.exit(1);
    }
    if (reply.text) console.log(reply.text);
    for (const image of reply.images ?? []) console.log(`[image] ${image}`);
    if (reply.isError) {
        console.error(`ECHEC : l'outil ${tool} a signale une erreur`);
        process.exit(1);
    }
});

socket.on('error', (e) => {
    if (e.code === 'ECONNREFUSED') {
        console.error(`aucun daemon sur le port ${PORT} : lancer d'abord « node tools/mcp-daemon.mjs »`);
    } else {
        console.error(`ECHEC : ${e.message}`);
    }
    process.exit(1);
});
