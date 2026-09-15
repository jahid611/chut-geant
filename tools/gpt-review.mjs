#!/usr/bin/env node
// Relecture contradictoire du travail de Claude par GPT (Codex CLI). Procedure : AGENTS.md, « Boucle Claude <-> GPT ».
//
// Usage (etapes de la boucle, pilotees normalement par tools/orchestrator.mjs) :
//   node tools/gpt-review.mjs plan "<demande>" --proposal <plan-claude.md>         critique du plan avant de coder
//   node tools/gpt-review.mjs initial "<demande>" [--base <ref>]                   relecture des changements
//   node tools/gpt-review.mjs diagnostic "<demande>" --logs <journal-studio.txt>   cause probable d'une erreur de test
//   node tools/gpt-review.mjs final "<demande>" --previous <dossier> --answers <reponses-claude.md>
// Options : --model <id> (defaut GPT_REVIEW_MODEL ou gpt-6-astra), --effort <low|medium|high|xhigh|max> (defaut high).
//
// Sous Windows, la politique d'execution de Codex refuse les commandes shell en lecture seule (Get-Content bloque) :
// tout ce que GPT doit lire lui est donc envoye directement dans le message, par l'entree standard (AGENTS.md, demande,
// diff, contenu complet des fichiers changes, plan, journaux, remarques et reponses). Il garde l'acces a Studio par le
// serveur MCP « roblox-studio ».
//
// Le dossier tools/reviews/<horodatage>-<mode>/ garde : message.md (tout ce qui a ete envoye), empreinte.txt (empreinte
// du code relu, prise avant l'envoi), remarques.json (schema tools/gpt-review.schema.json), resume.md, et obsolete.txt
// si le code a change pendant la relecture (l'arbitre ne la compte alors pas pour le code actuel).

import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

import { git, root, trackedChanges, untrackedFiles, workHash } from "./git-state.mjs";
import { appendJournal } from "./journal.mjs";

const schemaPath = join(root, "tools", "gpt-review.schema.json");
// Au-dela, un fichier change est cite par son nom seulement (binaire ou trop gros pour etre utile en entier).
const MAX_INLINE_BYTES = 200 * 1024;
const TEXT_EXTENSIONS = /\.(luau|lua|mjs|js|ts|json|md|toml|py|ps1|sh|html|css|yml|yaml|txt)$|^\.gitignore$/i;

function fail(message) {
  console.error(`[gpt-review] ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const [mode, request, ...rest] = argv;
  const options = {
    mode,
    request,
    base: "HEAD",
    previous: null,
    answers: null,
    proposal: null,
    logs: null,
    model: null,
    effort: "high",
  };
  for (let i = 0; i < rest.length; i += 1) {
    const flag = rest[i];
    const value = rest[i + 1];
    if (!value) fail(`valeur manquante pour ${flag}`);
    if (flag === "--base") options.base = value;
    else if (flag === "--previous") options.previous = value;
    else if (flag === "--answers") options.answers = value;
    else if (flag === "--proposal") options.proposal = value;
    else if (flag === "--logs") options.logs = value;
    else if (flag === "--model") options.model = value;
    else if (flag === "--effort") options.effort = value;
    else fail(`option inconnue : ${flag}`);
    i += 1;
  }
  if (!["plan", "initial", "diagnostic", "final"].includes(mode)) {
    fail("mode attendu : plan, initial, diagnostic ou final");
  }
  if (!request) fail("demande de l'utilisateur manquante");
  if (mode === "plan" && !options.proposal) fail("la critique du plan demande --proposal <fichier.md>");
  if (mode === "diagnostic" && !options.logs) fail("le diagnostic demande --logs <fichier>");
  if (mode === "final" && (!options.previous || !options.answers)) {
    fail("la relecture finale demande --previous <dossier> et --answers <fichier.md>");
  }
  options.model = options.model || process.env.GPT_REVIEW_MODEL || "gpt-6-astra";
  return options;
}

// Changements depuis la base, fichiers nouveaux non suivis compris (git diff ne les montre pas). Chemins en -z.
function collectDiff(base) {
  const untracked = untrackedFiles();
  let diff = git(["diff", base, "--", "."]);
  for (const file of untracked) {
    diff += git(["diff", "--no-index", "--", "/dev/null", file], [0, 1]);
  }
  return { diff, files: [...new Set([...trackedChanges(base), ...untracked])] };
}

// Contenu complet des fichiers changes qui existent encore, pour juger dans le contexte et pas seulement le diff.
function changedFileContents(files) {
  const parts = [];
  for (const file of files) {
    const path = join(root, file);
    const name = file.split("/").pop();
    if (!existsSync(path) || !TEXT_EXTENSIONS.test(name)) continue;
    const size = statSync(path).size;
    if (size > MAX_INLINE_BYTES) {
      parts.push(`--- ${file} (${Math.round(size / 1024)} Ko, trop gros : voir le diff) ---`);
      continue;
    }
    parts.push(`--- ${file} ---\n${readFileSync(path, "utf8")}`);
  }
  return parts.join("\n\n");
}

// Codex s'installe en .cmd sous Windows : il faut passer par le shell, commande en une seule chaine. Le message part
// par l'entree standard (argument « - »), sans limite de longueur de ligne de commande.
function runCodex(args, input) {
  const windows = process.platform === "win32";
  const quote = (arg) => (/[\s"&|<>^]/.test(arg) ? `"${arg.replace(/"/g, '""')}"` : arg);
  const options = {
    cwd: root,
    encoding: "utf8",
    input,
    stdio: ["pipe", "inherit", "inherit"],
    maxBuffer: 64 * 1024 * 1024,
  };
  const result = windows
    ? spawnSync(["codex", ...args.map(quote)].join(" "), { ...options, shell: true })
    : spawnSync("codex", args, options);
  if (result.error) fail(`impossible de lancer codex : ${result.error.message}`);
  return result.status;
}

const CHECKLIST = `
Points a verifier en priorite (projet Roblox Luau, regles completes dans AGENTS.md ci-dessous) :
1. Bugs : nil non gere, courses entre threads, etat qui fuit (connexions jamais deconnectees, tables par joueur non
   nettoyees au depart), valeurs limites, code mort ou branche jamais atteinte.
2. Exploits : le client envoie une intention, le serveur valide et decide. Tout remote doit verifier types, bornes,
   cadence et droits du joueur ; aucune confiance dans une valeur venue du client (prix, position, cible, quantite).
3. Architecture : services Init/Start, un Start ne doit jamais attendre (WaitForChild d'un objet cree par un autre
   service -> task.spawn) ; remotes declares uniquement dans src/shared/Remotes.luau ; task.* uniquement ;
   attributs et tags plutot que des Value cachees ; --!strict partout.
4. Regles du projet : jamais de ligne qui commence par "(" apres un appel (Roblox refuse le module) ; textes
   d'interface en francais, sans emoji ; aucun decor en pieces de base Studio ; aucune cle dans le depot ; menus
   sans debordement.
5. Performance : boucles Heartbeat couteuses, instances creees en rafale, replication inutile vers tous les clients.
6. Outillage (fichiers tools/*.mjs) : robustesse Windows, erreurs mal gerees, etat incoherent, securite (secrets,
   commandes construites a partir d'entrees).
Ne signale pas ce que stylua et selene imposent deja (mise en forme). Chaque remarque cite fichier et ligne, decrit un
scenario concret qui declenche le defaut et propose une correction precise. Pas de remarque vague.
`;

const MODE_TEXT = {
  plan: `CRITIQUE DU PLAN : aucun code n'est encore ecrit pour cette demande (le diff peut etre vide ou sans rapport).
La section « PLAN DE CLAUDE » contient son plan d'architecture. Verifie avec AGENTS.md, le code fourni et, si utile,
Studio qu'il s'appuie sur les bons systemes (sauvegarde DataService, remotes, services existants), qu'il ne duplique
rien et qu'il n'ouvre pas de faille (progression calculee cote serveur, remotes valides, cadence bornee). Chaque
remarque est un risque ou une recommandation precise (fichier existant concerne ou nouveau fichier prevu, ligne 0 si
non applicable). « suivi » est un tableau vide. Verdict « approuve » si le plan peut etre implemente tel quel ou avec
seulement des remarques mineures.`,
  initial: `RELECTURE INITIALE : cherche les problemes dans les changements. « suivi » est un tableau vide. Verdict
« approuve » seulement s'il ne reste aucune remarque bloquante ou majeure.`,
  diagnostic: `DIAGNOSTIC : un playtest a echoue. La section « JOURNAUX DE STUDIO » contient les journaux. Trouve la
cause la plus probable en lisant le code fourni aux lignes citees et, si utile, en inspectant Studio. Chaque remarque
est une cause possible, de la plus probable a la moins probable, avec sa correction. « suivi » est un tableau vide.
Verdict « corrections_demandees » des qu'une cause est identifiee, « approuve » si les journaux ne montrent pas de
vrai probleme.`,
  final: `RELECTURE FINALE : la section « REMARQUES PRECEDENTES » contient les remarques encore ouvertes et la section
« REPONSES DE CLAUDE » ses reponses (acceptee et corrigee, ou rejetee avec sa raison). Pour chaque remarque
precedente, remplis « suivi » avec son identifiant exact : corrige, non_corrige, rejet_accepte (la raison de Claude
tient) ou rejet_conteste (explique pourquoi). Mets dans « remarques » uniquement les nouveaux problemes, en
particulier ceux introduits par les corrections. Verdict « approuve » seulement s'il ne reste ni remarque bloquante ou
majeure ni rejet conteste.`,
};

function buildMessage(options, sections) {
  const header = `Tu es « GPT, relecteur » du jeu Roblox « CHUT ! Vole le Géant », a egalite avec Claude qui implemente
(constitution commune AGENTS.md ci-dessous). Tu ne modifies rien. Reponds uniquement par le JSON demande, en francais.

Tout ce que tu dois lire est dans ce message : AGENTS.md, la demande, la liste des fichiers changes, le diff et le
contenu complet de ces fichiers${options.mode === "initial" ? "" : ", plus les sections propres a cette etape"}.
N'essaie pas de lire des fichiers par des commandes shell : sous Windows, la politique d'execution les refuse.

Pour l'etat reel de Roblox Studio, tu as les outils du serveur MCP « roblox-studio » (meme pont que Claude) :
get_place_info, execute_luau (mode edition, LECTURE SEULE pour toi : inspecter instances, attributs, positions ; jamais
de modification, de suppression ni de publication), solo_playtest (start/stop/status, mode play), eval_server_runtime
et eval_client_runtime pendant un playtest, get_runtime_logs. Utilise Studio quand une remarque depend de l'etat reel
plutot que de supposer. Si tu lances un playtest, arrete-le avant de repondre. Respecte les limites du banc de test
decrites dans AGENTS.md (Humanoid:Move par script n'avance pas, attente longue coupee) pour eviter les fausses alertes.

« relu » vaut vrai seulement si tu as bien lu la demande, le diff et le contenu des fichiers ci-dessous. S'il en
manque ou s'il est illisible, mets « relu » a faux, dis exactement ce qui manque dans « resume » et ne rends ni
remarque ni verdict « approuve ».

${MODE_TEXT[options.mode]}
${CHECKLIST}`;
  const body = sections.map(([title, content]) => `\n===== ${title} =====\n${content}`).join("\n");
  return `${header}${body}\n`;
}

function summarize(review, model, stale) {
  if (review.relu !== true) {
    return `RELECTURE IMPOSSIBLE (${model}) : ${review.resume}`;
  }
  const lines = [];
  if (stale) lines.push("ATTENTION : le code a changé pendant la relecture, elle ne vaut que pour la version envoyée.");
  const count = (gravite) => review.remarques.filter((r) => r.gravite === gravite).length;
  lines.push(`Verdict GPT (${model}) : ${review.verdict === "approuve" ? "APPROUVÉ" : "CORRECTIONS DEMANDÉES"}`);
  lines.push(review.resume);
  lines.push(`Remarques : ${count("bloquant")} bloquante(s), ${count("majeur")} majeure(s), ${count("mineur")} mineure(s)`);
  for (const r of review.remarques) {
    lines.push(`- [${r.id}] ${r.gravite} / ${r.categorie} — ${r.fichier}:${r.ligne}`);
    lines.push(`  Problème : ${r.probleme}`);
    lines.push(`  Scénario : ${r.scenario}`);
    lines.push(`  Correction : ${r.correction}`);
  }
  if (review.suivi.length > 0) {
    lines.push("Suivi des remarques précédentes :");
    for (const s of review.suivi) lines.push(`- [${s.id}] ${s.statut} — ${s.commentaire}`);
  }
  return lines.join("\n");
}

const options = parseArgs(process.argv.slice(2));
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const folder = join(root, "tools", "reviews", `${stamp}-${options.mode}`);
mkdirSync(folder, { recursive: true });

let hashBefore;
let diff;
let files;
try {
  // Empreinte prise avant la collecte et reverifiee apres : la relecture porte exactement sur ce code-la.
  hashBefore = workHash();
  ({ diff, files } = collectDiff(options.base));
} catch (error) {
  fail(error.message);
}
if (files.length === 0 && (options.mode === "initial" || options.mode === "final")) {
  fail(`aucun changement depuis ${options.base} : rien a relire`);
}

const agents = existsSync(join(root, "AGENTS.md")) ? readFileSync(join(root, "AGENTS.md"), "utf8") : "(AGENTS.md absent)";
const sections = [
  ["AGENTS.md", agents],
  ["DEMANDE DE L'UTILISATEUR", options.request],
  ["FICHIERS CHANGES", files.join("\n") || "(aucun)"],
  ["DIFF", diff || "(vide)"],
  ["CONTENU COMPLET DES FICHIERS CHANGES", changedFileContents(files) || "(aucun fichier texte)"],
];
if (options.mode === "plan") {
  if (!existsSync(options.proposal)) fail(`plan introuvable : ${options.proposal}`);
  copyFileSync(options.proposal, join(folder, "plan-claude.md"));
  sections.push(["PLAN DE CLAUDE", readFileSync(options.proposal, "utf8")]);
}
if (options.mode === "diagnostic") {
  if (!existsSync(options.logs)) fail(`journaux introuvables : ${options.logs}`);
  copyFileSync(options.logs, join(folder, "journal-studio.txt"));
  sections.push(["JOURNAUX DE STUDIO", readFileSync(options.logs, "utf8")]);
}
if (options.mode === "final") {
  const previous = join(options.previous, "remarques.json");
  if (!existsSync(previous)) fail(`remarques precedentes introuvables : ${previous}`);
  if (!existsSync(options.answers)) fail(`reponses de Claude introuvables : ${options.answers}`);
  copyFileSync(previous, join(folder, "remarques-precedentes.json"));
  copyFileSync(options.answers, join(folder, "reponses-claude.md"));
  sections.push(["REMARQUES PRECEDENTES", readFileSync(previous, "utf8")]);
  sections.push(["REPONSES DE CLAUDE", readFileSync(options.answers, "utf8")]);
}

const message = buildMessage(options, sections);
try {
  if (workHash() !== hashBefore) fail("le code a changé pendant la collecte du contexte : relancer la relecture");
} catch (error) {
  fail(error.message);
}
writeFileSync(join(folder, "message.md"), message);
writeFileSync(join(folder, "empreinte.txt"), `${hashBefore}\n`);

const output = join(folder, "remarques.json");
const LABELS = { plan: "critique du plan", initial: "relecture", diagnostic: "diagnostic", final: "relecture finale" };
appendJournal(
  "GPT",
  `${LABELS[options.mode]} en cours (${options.model}, effort ${options.effort}, ${files.length} fichier(s), ` +
    `${Math.round(message.length / 1024)} Ko de contexte, code ${hashBefore})...`,
);
const status = runCodex(
  [
    "exec",
    "-m",
    options.model,
    "-s",
    "read-only",
    "-C",
    root,
    "--output-schema",
    schemaPath,
    "-o",
    output,
    "-c",
    `model_reasoning_effort=${options.effort}`,
    "-",
  ],
  message,
);
if (status !== 0) fail(`codex s'est termine avec le code ${status} (dossier : ${folder})`);
if (!existsSync(output)) fail(`codex n'a pas ecrit ${output}`);

let review;
try {
  review = JSON.parse(readFileSync(output, "utf8"));
} catch (error) {
  fail(`reponse illisible (${error.message}) : ${output}`);
}

let stale = false;
try {
  const hashAfter = workHash();
  if (hashAfter !== hashBefore) {
    stale = true;
    writeFileSync(join(folder, "obsolete.txt"), `code relu ${hashBefore}, code au retour ${hashAfter}\n`);
  }
} catch (error) {
  fail(error.message);
}

const summary = summarize(review, options.model, stale);
writeFileSync(join(folder, "resume.md"), `${summary}\n`);
appendJournal("GPT", `${LABELS[options.mode]} terminée\n${summary}`);
console.log(`Dossier : ${relative(root, folder)}`);
