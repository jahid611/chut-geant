#!/usr/bin/env node
/**
 * scene-run — execute un fichier Luau dans l'editeur Studio, via le daemon MCP.
 *
 *   node tools/scene-run.mjs tools/scene/build-hub.luau
 *
 * Les recettes de scene (hub, maps, decors) vivent dans tools/scene/ et se
 * rejouent : une scene construite a la main dans Studio n'existe que dans le
 * place, une scene construite par script existe dans git. Le daemon
 * (tools/mcp-daemon.mjs) doit tourner.
 */

import fs from 'node:fs';
import net from 'node:net';

const PORT = Number(process.env.MCP_DAEMON_PORT ?? 58999);
const file = process.argv[2];
if (!file) {
    console.error('usage: scene-run.mjs <fichier.luau>');
    process.exit(2);
}
/**
 * Le prelude : les briques communes a toutes les recettes (part, neon, sign,
 * light, palette). Il est colle en tete de chaque recette avant l'envoi, parce
 * qu'un script execute dans Studio ne peut pas `require` un fichier du disque.
 * Une recette qui commence par `-- sans prelude` s'en passe.
 */
const PRELUDE = 'tools/scene/_prelude.luau';
let code = fs.readFileSync(file, 'utf8');
if (!code.startsWith('-- sans prelude') && fs.existsSync(PRELUDE) && !file.endsWith('_prelude.luau')) {
    code = `${fs.readFileSync(PRELUDE, 'utf8')}\n-- ==== recette : ${file} ====\n${code}`;
}

const socket = net.connect(PORT, '127.0.0.1', () => {
    socket.write(`${JSON.stringify({ tool: 'execute_luau', args: { code } })}\n`);
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
    let text = reply.text ?? '';
    try {
        const parsed = JSON.parse(text);
        text = parsed.returnValue ?? parsed.error ?? text;
        if (parsed.output && parsed.output.length) console.log(parsed.output.join('\n'));
    } catch {}
    console.log(text);
});
socket.on('error', (e) => {
    console.error(e.code === 'ECONNREFUSED' ? `aucun daemon sur ${PORT} : lancer node tools/mcp-daemon.mjs` : `ECHEC : ${e.message}`);
    process.exit(1);
});
