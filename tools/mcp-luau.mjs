#!/usr/bin/env node
/**
 * mcp-luau — execute un fichier Luau dans Studio via le serveur MCP.
 *
 * Echapper du Luau a la main dans du JSON en ligne de commande est une source
 * d'erreurs sans fin. On ecrit le code dans un fichier, ce script construit le
 * JSON et delegue a mcp-cli.
 *
 * Usage :
 *   node tools/mcp-luau.mjs <fichier.luau> [outil]
 *   outil : execute_luau (defaut), eval_server_runtime, eval_client_runtime
 */

import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const [, , file, tool = 'execute_luau'] = process.argv;

if (!file) {
    console.error('usage: mcp-luau.mjs <fichier.luau> [outil]');
    process.exit(2);
}

const code = readFileSync(file, 'utf8');
const cli = path.join(path.dirname(fileURLToPath(import.meta.url)), 'mcp-cli.mjs');

const child = spawn(process.execPath, [cli, 'call', tool, JSON.stringify({ code })], {
    stdio: 'inherit',
    env: process.env,
});

child.on('close', (c) => process.exit(c ?? 1));
