/**
 * push-src.mjs — le filet de securite quand le greffon Rojo lache.
 *
 *     node tools/push-src.mjs           # pousse ce qui a change
 *     node tools/push-src.mjs --all     # pousse tout, meme l'identique
 *     node tools/push-src.mjs src/shared/Icons.luau   # un seul fichier
 *
 * Rojo synchronise le code, et c'est lui qui fait autorite : ce script ne le
 * remplace pas. Mais sa liaison WebSocket tombe (« Une connexion existante a
 * du etre fermee par l'hote distant »), et il faut alors cliquer Connect dans
 * Studio. Tant que personne ne clique, Studio tourne sur du code d'hier et
 * chaque test ment.
 *
 * Ce script recopie donc src/ dans Studio par le MCP, avec la meme carte que
 * default.project.json. Il ne supprime rien : un fichier efface sur le disque
 * reste dans Studio jusqu'a la prochaine vraie synchronisation. C'est voulu —
 * detruire des instances dans Studio ne se fait pas sans demander.
 *
 * Il compare une empreinte posee en attribut, donc relancer ne coute rien.
 */

import { createHash } from 'node:crypto'
import net from 'node:net'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative, resolve, sep } from 'node:path'

const ROOT = resolve(import.meta.dirname, '..')

/** La carte de default.project.json : dossier du disque -> chemin dans Studio. */
const MAP = [
  ['src/server', 'game.ServerScriptService', 'Server'],
  ['src/shared', 'game.ReplicatedStorage', 'Shared'],
  ['src/client', 'game.StarterPlayer.StarterPlayerScripts', 'Client'],
]

/**
 * Le nom et la classe d'un fichier, selon la convention Rojo.
 * `X.server.luau` est un Script, `X.client.luau` un LocalScript, le reste un
 * ModuleScript. `init.luau` devient le dossier lui-meme.
 */
function instanceOf(file) {
  if (file === 'init.luau') return { name: null, className: 'ModuleScript' }
  if (file.endsWith('.server.luau')) return { name: file.slice(0, -12), className: 'Script' }
  if (file.endsWith('.client.luau')) return { name: file.slice(0, -12), className: 'LocalScript' }
  if (file.endsWith('.luau')) return { name: file.slice(0, -5), className: 'ModuleScript' }
  return null
}

/** Tous les .luau d'un dossier, en profondeur. */
function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, out)
    else if (entry.endsWith('.luau')) out.push(full)
  }
  return out
}

/**
 * Une source Luau, en litteral de chaine Luau.
 *
 * Pas de crochets longs : les sources en contiennent (chaque docstring finit
 * par `]]`). Tout ce qui n'est pas de l'ASCII imprimable passe en echappement
 * decimal, ce qui rend les accents des commentaires francais sans surprise.
 */
function luaString(text) {
  let out = '"'
  for (const byte of Buffer.from(text, 'utf8')) {
    if (byte === 34 || byte === 92) out += '\\' + String.fromCharCode(byte)
    else if (byte >= 32 && byte < 127) out += String.fromCharCode(byte)
    else out += '\\' + byte
  }
  return out + '"'
}

const PORT = Number(process.env.MCP_DAEMON_PORT ?? 58999)

/**
 * On parle au daemon en direct, sans passer par mcpd.mjs.
 *
 * Une source echappee fait cent mille caracteres, et Windows refuse une ligne
 * de commande de plus de trente-deux mille : le passer en argument coupe avec
 * un ENAMETOOLONG. La prise reseau, elle, n'a pas cette limite.
 */
function call(tool, args) {
  return new Promise((done, fail) => {
    const socket = net.connect(PORT, '127.0.0.1', () => {
      socket.write(`${JSON.stringify({ tool, args })}\n`)
    })
    let incoming = ''
    socket.on('data', (chunk) => {
      incoming += chunk.toString()
      const index = incoming.indexOf('\n')
      if (index === -1) return
      const reply = JSON.parse(incoming.slice(0, index))
      socket.end()
      if (reply.error) return fail(new Error(reply.error))
      const line = (reply.text ?? '').trim().split('\n').filter((l) => l.trim().startsWith('{')).pop()
      try {
        done(JSON.parse(line))
      } catch {
        done({ success: false, message: (reply.text ?? '').slice(0, 300) })
      }
    })
    socket.on('error', (e) => {
      fail(
        e.code === 'ECONNREFUSED'
          ? new Error(`aucun daemon sur le port ${PORT} : lancer d'abord « node tools/mcp-daemon.mjs »`)
          : e
      )
    })
  })
}

const args = process.argv.slice(2)
const forceAll = args.includes('--all')
const only = args.filter((a) => !a.startsWith('--')).map((a) => resolve(ROOT, a))

/** Ce qu'il faut ecrire dans Studio, un objet par fichier. */
const jobs = []
for (const [folder, parent, rootName] of MAP) {
  const base = join(ROOT, folder)
  for (const file of walk(base)) {
    if (only.length > 0 && !only.includes(file)) continue
    const parts = relative(base, file).split(sep)
    const leaf = instanceOf(parts.pop())
    if (leaf == null) continue
    // init.luau devient le dossier qui le contient.
    const path = [rootName, ...parts]
    if (leaf.name != null) path.push(leaf.name)
    const source = readFileSync(file, 'utf8')
    jobs.push({
      parent,
      path,
      className: leaf.className,
      source,
      hash: createHash('sha1').update(source).digest('hex').slice(0, 16),
      file: relative(ROOT, file),
    })
  }
}

if (jobs.length === 0) {
  console.error('aucun fichier a pousser')
  process.exit(1)
}

/**
 * Un fichier par appel.
 *
 * Une source fait jusqu'a quarante mille caracteres, et l'echappement la
 * gonfle : tout envoyer d'un coup depasse ce que le pont accepte.
 */
let written = 0
let skipped = 0
const failures = []

for (const job of jobs) {
  const code = `
local parent = ${job.parent}
local path = { ${job.path.map((p) => luaString(p)).join(', ')} }
local node = parent
for index = 1, #path - 1 do
    local next = node:FindFirstChild(path[index])
    if next == nil then
        next = Instance.new("Folder")
        next.Name = path[index]
        next.Parent = node
    end
    node = next
end
local leaf = path[#path]
local found = node:FindFirstChild(leaf)
if found ~= nil and found.ClassName ~= "${job.className}" then
    return "classe differente: " .. found:GetFullName() .. " est " .. found.ClassName
end
if found ~= nil and ${forceAll ? 'false' : 'true'} and found:GetAttribute("PushHash") == "${job.hash}" then
    return "inchange"
end
if found == nil then
    found = Instance.new("${job.className}")
    found.Name = leaf
    found.Parent = node
end
found.Source = ${luaString(job.source)}
found:SetAttribute("PushHash", "${job.hash}")
return "ecrit"
`
  const result = await call('execute_luau', { code })
  const value = result.returnValue ?? result.message ?? '?'
  if (value === 'inchange') skipped += 1
  else if (value === 'ecrit') {
    written += 1
    console.log(`  ${job.file}`)
  } else {
    failures.push(`${job.file}: ${value}`)
  }
}

console.log(`${written} ecrits, ${skipped} inchanges, ${failures.length} en echec`)
for (const failure of failures) console.log(`  ! ${failure}`)
process.exit(failures.length > 0 ? 1 : 0)
