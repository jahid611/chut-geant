#!/usr/bin/env node
// Arbitre de la boucle Claude <-> GPT (AGENTS.md). Programme sans IA : il garde l'etat de la tache, fait travailler
// Claude (la session Claude Code lance ces commandes) et GPT (Codex) a egalite, l'un implemente et l'autre relit, et
// s'appuie sur des sources objectives plutot que sur ce que chaque modele raconte : git (fichiers changes, diff,
// empreinte), le pont MCP (journaux de Studio) et les garde-fous calcules apres chaque passage de GPT.
//
// Commandes :
//   node tools/orchestrator.mjs start "<tache>" [--type gameplay|ui|serveur|scene|outillage] [--by claude|gpt|auto]
//                                              [--max 10]
//   node tools/orchestrator.mjs plan [<plan.md>]          Claude implementeur : son plan, critique par GPT ;
//                                                        GPT implementeur : GPT ecrit le plan (sans fichier)
//   node tools/orchestrator.mjs implement                GPT implementeur : implemente le plan retenu
//   node tools/orchestrator.mjs answer [<reponses.md>]   reponses de l'implementeur (fichier pour Claude, GPT sinon)
//   node tools/orchestrator.mjs test start               lance le playtest par le pont (empreinte et marque notees)
//   node tools/orchestrator.mjs test --ok|--fail         journaux lus, playtest arrete, resultat note
//   node tools/orchestrator.mjs test --fail --logs <f>   diagnostic sur des journaux importes
//   node tools/orchestrator.mjs review                   GPT relecteur : relecture des changements
//   node tools/orchestrator.mjs claude-review start [--mode plan|initial|final]   Claude relecteur : debut
//   node tools/orchestrator.mjs claude-review submit <remarques.json>              Claude relecteur : remarques
//   node tools/orchestrator.mjs check                    lune run check
//   node tools/orchestrator.mjs status                   etat de la tache
//   node tools/orchestrator.mjs done                     cloture si toutes les conditions tiennent, mesure ajoutee
//   node tools/orchestrator.mjs stats                    mesures par type et par implementeur
//
// Etat : tools/reviews/tasks/<id>/state.json (hors depot) ; tache courante dans tools/reviews/tasks/current.
// Mesures : docs/agents/mesures.json (versionne), ajoutees a la cloture.
// Arbitrage :
// - un modele ne relit jamais son propre code ; une remarque n'est fermee que si le relecteur le confirme (corrigee, ou
//   rejet dont il accepte la raison) ; un rejet conteste reste ouvert et bloque la cloture ;
// - une relecture vaut pour le code qu'elle a reellement recu : empreinte prise avant l'envoi (GPT) ou au debut
//   (Claude) ; un avis obsolete est archive sans fermer ni ouvrir de remarque ; seul le verdict d'une relecture
//   (initiale ou finale) compte pour la cloture ;
// - apres chaque passage de GPT en ecriture, les ecarts detectes par les garde-fous deviennent des remarques de
//   l'arbitre, que le relecteur doit confirmer resolues ;
// - un playtest n'est enregistre OK que s'il a ete lance par l'arbitre (test start), que ses journaux ont pu etre lus
//   dans Studio sans erreur, qu'ils contiennent la marque de session ecrite au lancement, qu'ils ne montrent aucune
//   erreur d'execution depuis le lancement (hors erreurs connues) et que le code n'a pas change depuis ;
// - un check vaut pour le code present a son lancement, et il est ignore si le code change pendant qu'il tourne ;
// - la cloture exige : relecture approuvee, playtest OK et check vert, tous sur l'empreinte actuelle, aucune remarque
//   bloquante ou majeure ouverte, aucun rejet conteste, aucun accent abime introduit ;
// - au-dela de MAX iterations de relecture, l'arbitre s'arrete : l'utilisateur tranche.

import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";

import { changedFiles, root, workHash } from "./git-state.mjs";
import { appendJournal } from "./journal.mjs";
import { introducedMojibake } from "./text-checks.mjs";

const TASKS = join(root, "tools", "reviews", "tasks");
const CURRENT = join(TASKS, "current");
const MEASURES = join(root, "docs", "agents", "mesures.json");
const AGENTS = ["claude", "gpt"];
const TYPES = ["gameplay", "ui", "serveur", "scene", "outillage"];
const MIN_MEASURES_FOR_AUTO = 3;
// Plan ecrit par GPT (lecture seule) : code envoye en priorite selon le type de tache (tools/gpt-implement.mjs --context).
const PLAN_CONTEXT = {
  gameplay: ["src/shared/", "src/server/Services/", "src/client/Controllers/"],
  ui: ["src/client/Ui/", "src/client/Controllers/", "src/shared/"],
  serveur: ["src/shared/", "src/server/"],
  scene: ["tools/scene/", "src/shared/"],
  outillage: ["tools/", "AGENTS.md"],
  "non-classe": ["src/shared/", "src/server/Main.server.luau", "src/client/Main.client.luau"],
};

function fail(message) {
  console.error(`[orchestrator] ${message}`);
  process.exit(1);
}

const firstLine = (text) =>
  (String(text)
    .split("\n")
    .map((line) => line.replace(/^#+\s*/, "").trim())
    .find(Boolean) ?? "")
    .slice(0, 120);
const tail = (text, count) => String(text).trimEnd().split("\n").slice(-count).join("\n");
const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const other = (agent) => (agent === "claude" ? "gpt" : "claude");
const tagOf = (agent) => (agent === "claude" ? "CLAUDE" : "GPT");
const nowStamp = () => new Date().toISOString().replace(/[:.]/g, "-");

function loadContext() {
  if (!existsSync(CURRENT)) fail('aucune tache en cours : node tools/orchestrator.mjs start "<tache>"');
  const id = readFileSync(CURRENT, "utf8").trim();
  const dir = join(TASKS, id);
  const file = join(dir, "state.json");
  if (!existsSync(file)) fail(`etat introuvable : ${file}`);
  const state = JSON.parse(readFileSync(file, "utf8"));
  // Taches ouvertes avant les roles symetriques : Claude implemente, GPT relit.
  state.IMPLEMENTER ??= "claude";
  state.REVIEWER ??= other(state.IMPLEMENTER);
  state.TYPE ??= "non-classe";
  state.STARTED_AT ??= state.HISTORY?.[0]?.at ?? new Date().toISOString();
  state.FAILED_TESTS ??= 0;
  state.SEVERE_REMARKS ??= 0;
  state.ARBITER_CALLS ??= 0;
  state.CLAUDE_REVIEW ??= null;
  return { id, dir, state };
}

function save(ctx) {
  writeFileSync(join(ctx.dir, "state.json"), `${JSON.stringify(ctx.state, null, 2)}\n`);
}

function record(ctx, tag, message) {
  ctx.state.HISTORY.push({ at: new Date().toISOString(), tag, message });
  appendJournal(tag, message);
  save(ctx);
}

// Lance un outil de tools/ en laissant defiler sa sortie ; rend separement le dossier annonce (« Dossier : ... ») et
// le code de sortie : un passage de GPT en echec peut avoir des garde-fous a integrer.
function runTool(script, args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [join(root, "tools", script), ...args], { cwd: root });
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk;
      process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => process.stderr.write(chunk));
    child.on("close", (code) => {
      const match = output.match(/^Dossier : (.+)$/m);
      resolve({ folder: match ? join(root, match[1].trim()) : null, code });
    });
  });
}

// Relecture ou diagnostic par GPT : le dossier ne compte que si l'outil a reussi.
async function runReviewTool(args) {
  const { folder, code } = await runTool("gpt-review.mjs", args);
  return code === 0 ? folder : null;
}

// Passage de GPT en ecriture : les garde-fous sont integres des qu'ils existent, meme si le passage a echoue, puis la
// suite est refusee en cas d'echec.
async function runImplementTool(ctx, args) {
  const { folder, code } = await runTool("gpt-implement.mjs", args);
  if (folder && existsSync(join(folder, "garde-fous.json"))) applyGuards(ctx, folder);
  if (code !== 0 || !folder) {
    fail("le passage de GPT a échoué (garde-fous intégrés s'ils ont pu être calculés ; voir son dossier)");
  }
  const outputFile = join(folder, "sortie.json");
  if (!existsSync(outputFile)) fail(`sortie de GPT introuvable : ${outputFile}`);
  return { folder, output: JSON.parse(readFileSync(outputFile, "utf8")) };
}

const OPEN_STATUSES = new Set(["ouverte", "non_corrige", "rejet_conteste"]);
const toSchema = (issue) => ({
  id: issue.id,
  gravite: issue.gravite,
  categorie: issue.categorie,
  fichier: issue.fichier,
  ligne: issue.ligne,
  probleme: issue.probleme,
  scenario: issue.scenario,
  correction: issue.correction,
});

// Remarques ouvertes au format des relectures, pour GPT (relecteur en finale, ou implementeur en correction).
function writeOpenIssues(ctx) {
  if (ctx.state.REMAINING_ISSUES.length === 0) return null;
  const folder = join(ctx.dir, "ouvertes");
  mkdirSync(folder, { recursive: true });
  const file = join(folder, "remarques.json");
  writeFileSync(
    file,
    `${JSON.stringify(
      {
        relu: true,
        verdict: "corrections_demandees",
        resume: "Remarques encore ouvertes pour cette tâche",
        remarques: ctx.state.REMAINING_ISSUES.map(toSchema),
        suivi: [],
      },
      null,
      2,
    )}\n`,
  );
  return { folder, file };
}

function answersPath(ctx) {
  for (const name of ["reponses-implementeur.md", "reponses-claude.md"]) {
    if (existsSync(join(ctx.dir, name))) return join(ctx.dir, name);
  }
  return null;
}

// Integre un avis du relecteur : suivi des remarques ouvertes (seul le relecteur les ferme), nouvelles remarques avec un
// identifiant unique sur toute la tache (G<n>- pour GPT, C<n>- pour Claude), et, pour une relecture, verdict et
// empreinte du code relu. Un avis obsolete (code modifie pendant qu'il travaillait) est archive sans toucher aux
// remarques : il porte sur une version qui n'existe plus.
function applyReview(ctx, folder, mode, reviewer) {
  const state = ctx.state;
  const review = JSON.parse(readFileSync(join(folder, "remarques.json"), "utf8"));
  const label = reviewer === "claude" ? "Claude" : "GPT";
  // Un avis que le relecteur n'a pas pu donner (lecture impossible...) ne compte ni comme avis ni comme iteration.
  if (review.relu !== true) {
    if (mode === "initial" || mode === "final") state.ITERATION = Math.max(state.ITERATION - 1, 0);
    state.LAST_REVIEW = relative(root, folder);
    record(ctx, "ORCHESTRATEUR", `${label} (${mode}) n'a pas pu relire : ${review.resume} (itération non comptée)`);
    process.exit(1);
  }
  state.GPT_CALLS += 1;
  state.LAST_REVIEW = relative(root, folder);
  if (existsSync(join(folder, "obsolete.txt"))) {
    state.STALE_REVIEWS = [...(state.STALE_REVIEWS ?? []), relative(root, folder)];
    if (mode === "initial" || mode === "final") state.REVIEW_HASH = null;
    record(
      ctx,
      "ORCHESTRATEUR",
      `${label} (${mode}) : avis obsolète (code modifié pendant qu'il travaillait), archivé sans fermer ni ouvrir de ` +
        "remarque ; le relancer",
    );
    return;
  }
  const byId = new Map(state.REMAINING_ISSUES.map((issue) => [issue.id, issue]));
  let closed = 0;
  for (const follow of review.suivi) {
    const issue = byId.get(follow.id);
    if (!issue) continue;
    if (follow.statut === "corrige" || follow.statut === "rejet_accepte") {
      byId.delete(follow.id);
      closed += 1;
    } else {
      issue.statut = follow.statut;
      issue.commentaire_relecteur = follow.commentaire;
    }
  }
  const prefix = reviewer === "claude" ? "C" : "G";
  for (const remark of review.remarques) {
    const id = `${prefix}${state.GPT_CALLS}-${remark.id}`;
    byId.set(id, { ...toSchema({ ...remark, id }), origine: `${reviewer}-${mode}`, statut: "ouverte" });
    if (remark.gravite === "bloquant" || remark.gravite === "majeur") state.SEVERE_REMARKS += 1;
  }
  state.REMAINING_ISSUES = [...byId.values()];
  if (reviewer === "gpt") state.GPT_OPINION = review.resume;
  else state.CLAUDE_OPINION = review.resume;
  state.GPT_VERDICT = review.verdict;
  if (mode === "initial" || mode === "final") {
    const hashFile = join(folder, "empreinte.txt");
    state.REVIEW_VERDICT = review.verdict;
    state.REVIEW_HASH = existsSync(hashFile) ? readFileSync(hashFile, "utf8").trim() : null;
  }
  record(
    ctx,
    "ORCHESTRATEUR",
    `${label} (${mode}) : ${review.verdict}, ${review.remarques.length} nouvelle(s) remarque(s), ${closed} fermée(s), ` +
      `${state.REMAINING_ISSUES.length} ouverte(s)`,
  );
}

// Reponses de l'implementeur (sections « ## <id> — acceptée|rejetée ») : statut des remarques, sans les fermer.
function applyAnswers(ctx, text, author) {
  writeFileSync(join(ctx.dir, "reponses-implementeur.md"), text);
  let accepted = 0;
  let rejected = 0;
  for (const issue of ctx.state.REMAINING_ISSUES) {
    const match = text.match(new RegExp(`^##\\s*${escapeRegex(issue.id)}\\s*[—–-]\\s*(accept|rejet)`, "im"));
    if (!match) continue;
    if (match[1].toLowerCase() === "accept") {
      issue.statut = "acceptee";
      accepted += 1;
    } else {
      issue.statut = "rejetee";
      rejected += 1;
    }
  }
  const unanswered = ctx.state.REMAINING_ISSUES.filter((issue) => OPEN_STATUSES.has(issue.statut)).map((i) => i.id);
  record(
    ctx,
    tagOf(author),
    `Réponses : ${accepted} acceptée(s), ${rejected} rejetée(s)` +
      (unanswered.length > 0 ? ` ; sans réponse : ${unanswered.join(", ")}` : ""),
  );
}

const answersMarkdown = (reponses) =>
  reponses
    .map((r) => `## ${r.id} — ${r.decision === "acceptee" ? "acceptée" : "rejetée"}\n\n${r.explication}\n`)
    .join("\n");

// Ecarts detectes par les garde-fous apres un passage de GPT : remarques de l'arbitre, a confirmer par le relecteur.
function applyGuards(ctx, folder) {
  const state = ctx.state;
  const guardsFile = join(folder, "garde-fous.json");
  if (!existsSync(guardsFile)) fail(`garde-fous introuvables : ${guardsFile}`);
  const raw = JSON.parse(readFileSync(guardsFile, "utf8"));
  // Rapport partiel possible (garde-fous interrompus) : listes absentes traitees comme vides.
  const listOf = (key) => (Array.isArray(raw[key]) ? raw[key] : []);
  const guards = {
    ...raw,
    copies_alterees: listOf("copies_alterees"),
    chemins_restaures: listOf("chemins_restaures"),
    fichiers_crees_supprimes: listOf("fichiers_crees_supprimes"),
    gros_fichiers_modifies: listOf("gros_fichiers_modifies"),
    accents_abimes: listOf("accents_abimes"),
    modifications_en_mode_plan: listOf("modifications_en_mode_plan"),
    modifies_non_declares: listOf("modifies_non_declares"),
  };
  const issues = [];
  const add = (gravite, fichier, probleme, correction) => issues.push({ gravite, fichier, probleme, correction });
  if (guards.erreur_garde_fous) {
    add("bloquant", "tools/gpt-implement.mjs",
      `Garde-fous interrompus avant la fin : ${guards.erreur_garde_fous}. État des chemins protégés non garanti.`,
      `Vérifier et rétablir les chemins protégés depuis l'instantané conservé : ${guards.instantane_conserve ?? "introuvable"}.`);
  }
  if (guards.sortie_invalide) {
    add("bloquant", "tools/gpt-implement.schema.json",
      `Sortie de GPT invalide (${guards.sortie_invalide}) : écarts calculés quand même, passage refusé.`,
      "Relancer le passage de GPT après avoir vérifié les écarts signalés.");
  }
  if (guards.head_modifie) {
    add("bloquant", ".git/HEAD", "HEAD a changé pendant le passage de GPT (commit ou changement de branche).",
      "Vérifier l'historique et revenir à l'état d'avant ; GPT ne doit jamais committer.");
  }
  if (guards.index_modifie) {
    add("bloquant", ".git/index", "L'index Git a changé pendant le passage de GPT.",
      "Rétablir l'index d'avant (git restore --staged sur les fichiers concernés).");
  }
  for (const path of guards.copies_alterees) {
    add("bloquant", path, "Chemin protégé modifié et copie de sauvegarde altérée : état d'avant non restauré.",
      `Rétablir ce fichier à la main ; instantané conservé : ${guards.instantane_conserve ?? "aucun"}.`);
  }
  for (const path of guards.chemins_restaures) {
    add("majeur", path, "GPT a modifié un chemin protégé ; l'état d'avant a été restauré automatiquement.",
      "Vérifier que la tâche ne dépendait pas de ce changement.");
  }
  for (const path of guards.fichiers_crees_supprimes) {
    add("majeur", path, "GPT a créé un fichier dans un chemin protégé ; il a été supprimé.",
      "Vérifier que la tâche ne dépendait pas de ce fichier.");
  }
  for (const path of guards.gros_fichiers_modifies) {
    add("bloquant", path, "Asset local ou état de l'arbitre créé, modifié ou supprimé pendant le passage de GPT (non restauré).",
      "Rétablir ce fichier depuis une sauvegarde locale ou prévenir l'utilisateur.");
  }
  for (const found of guards.accents_abimes) {
    add("bloquant", found.fichier, `Accents abîmés introduits (${found.avant} -> ${found.apres} séquences).`,
      "Réécrire ces textes en UTF-8 correct.");
  }
  for (const path of guards.modifications_en_mode_plan) {
    add("bloquant", path, "Fichier modifié alors que GPT devait seulement écrire un plan.", "Annuler cette modification.");
  }
  for (const path of guards.modifies_non_declares) {
    add("mineur", path, "Fichier modifié par GPT sans être déclaré.", "Vérifier que ce changement est voulu.");
  }
  if (issues.length === 0) {
    record(ctx, "ORCHESTRATEUR", "Garde-fous après le passage de GPT : aucun écart");
    return;
  }
  state.ARBITER_CALLS += 1;
  issues.forEach((issue, index) => {
    state.REMAINING_ISSUES.push({
      id: `A${state.ARBITER_CALLS}-${index + 1}`,
      gravite: issue.gravite,
      categorie: "regle_projet",
      fichier: issue.fichier,
      ligne: 0,
      probleme: issue.probleme,
      scenario: "Détecté par l'arbitre après le passage de GPT.",
      correction: issue.correction,
      origine: "arbitre",
      statut: "ouverte",
    });
    if (issue.gravite === "bloquant" || issue.gravite === "majeur") state.SEVERE_REMARKS += 1;
  });
  record(
    ctx,
    "ORCHESTRATEUR",
    `Garde-fous après le passage de GPT : ${issues.length} écart(s) ouvert(s) en remarques de l'arbitre ` +
      `(${issues.map((issue) => issue.gravite).join(", ")})`,
  );
}

// Mesures : docs/agents/mesures.json. Choix automatique de l'implementeur par type de tache.
function readMeasures() {
  if (!existsSync(MEASURES)) return [];
  try {
    const list = JSON.parse(readFileSync(MEASURES, "utf8"));
    return Array.isArray(list) ? list : [];
  } catch (error) {
    fail(`mesures illisibles (${MEASURES}) : ${error.message}`);
  }
}

const average = (items, key) =>
  items.length === 0 ? 0 : items.reduce((sum, item) => sum + (Number(item[key]) || 0), 0) / items.length;

function scoreOf(items) {
  return {
    taches: items.length,
    graves: average(items, "remarques_graves"),
    rates: average(items, "playtests_rates"),
    iterations: average(items, "iterations"),
  };
}

function pickImplementer(type) {
  const list = readMeasures().filter((measure) => measure.type === type);
  const claude = list.filter((measure) => measure.implementeur === "claude");
  const gpt = list.filter((measure) => measure.implementeur === "gpt");
  const last = list.at(-1);
  const alternate = () => (last?.implementeur === "claude" ? "gpt" : "claude");
  if (claude.length < MIN_MEASURES_FOR_AUTO || gpt.length < MIN_MEASURES_FOR_AUTO) {
    if (claude.length !== gpt.length) {
      return {
        agent: claude.length < gpt.length ? "claude" : "gpt",
        reason: `alternance, pas assez de mesures (${claude.length} tâche(s) Claude, ${gpt.length} GPT pour « ${type} »)`,
      };
    }
    return { agent: alternate(), reason: `alternance, pas assez de mesures (${claude.length} tâche(s) chacun)` };
  }
  const a = scoreOf(claude);
  const b = scoreOf(gpt);
  const primary = (score) => score.graves + score.rates;
  if (primary(a) !== primary(b)) {
    return {
      agent: primary(a) < primary(b) ? "claude" : "gpt",
      reason: `meilleur score (remarques graves + playtests ratés par tâche : Claude ${primary(a).toFixed(2)}, GPT ${primary(b).toFixed(2)})`,
    };
  }
  if (a.iterations !== b.iterations) {
    return {
      agent: a.iterations < b.iterations ? "claude" : "gpt",
      reason: `égalité, moins d'itérations (Claude ${a.iterations.toFixed(2)}, GPT ${b.iterations.toFixed(2)})`,
    };
  }
  return { agent: alternate(), reason: "égalité parfaite : alternance" };
}

function appendMeasure(state) {
  const list = readMeasures();
  list.push({
    date: new Date().toISOString(),
    tache: state.TASK,
    type: state.TYPE,
    implementeur: state.IMPLEMENTER,
    relecteur: state.REVIEWER,
    iterations: state.ITERATION,
    remarques_graves: state.SEVERE_REMARKS,
    playtests_rates: state.FAILED_TESTS,
    duree_min: Math.round((Date.now() - Date.parse(state.STARTED_AT)) / 60000),
  });
  mkdirSync(dirname(MEASURES), { recursive: true });
  writeFileSync(MEASURES, `${JSON.stringify(list, null, 2)}\n`);
}

function start(task, options) {
  const id = nowStamp();
  const dir = join(TASKS, id);
  mkdirSync(dir, { recursive: true });
  let implementer = options.by;
  let reason = "imposé";
  if (implementer === "auto") ({ agent: implementer, reason } = pickImplementer(options.type));
  const ctx = {
    id,
    dir,
    state: {
      TASK: task,
      TYPE: options.type,
      IMPLEMENTER: implementer,
      REVIEWER: other(implementer),
      PHASE: "plan",
      PLAN: null,
      FILES_CHANGED: [],
      CLAUDE_OPINION: null,
      GPT_OPINION: null,
      GPT_VERDICT: null,
      REVIEW_VERDICT: null,
      TEST_RESULTS: null,
      TEST_INSTANCE: null,
      TEST_RUN: null,
      MCP_LOGS: null,
      CHECK: null,
      REMAINING_ISSUES: [],
      ITERATION: 0,
      MAX_ITERATIONS: options.max,
      GPT_CALLS: 0,
      ARBITER_CALLS: 0,
      SEVERE_REMARKS: 0,
      FAILED_TESTS: 0,
      CLAUDE_REVIEW: null,
      TEST_HASH: null,
      CHECK_HASH: null,
      REVIEW_HASH: null,
      LAST_REVIEW: null,
      STARTED_AT: new Date().toISOString(),
      HISTORY: [],
    },
  };
  writeFileSync(CURRENT, id);
  record(
    ctx,
    "ORCHESTRATEUR",
    `Nouvelle tâche (${options.type}) : ${task} ; implémenteur ${implementer} (${reason}), relecteur ${other(implementer)}, ` +
      `${options.max} itérations au plus`,
  );
}

async function plan(file) {
  const ctx = loadContext();
  const state = ctx.state;
  if (state.IMPLEMENTER === "claude") {
    if (!file) fail("Claude implémente : node tools/orchestrator.mjs plan <plan-claude.md>");
    if (!existsSync(file)) fail(`plan introuvable : ${file}`);
    const text = readFileSync(file, "utf8");
    writeFileSync(join(ctx.dir, "plan.md"), text);
    state.PLAN = text;
    state.CLAUDE_OPINION = `Plan : ${firstLine(text)}`;
    record(ctx, "CLAUDE", `Plan proposé : ${firstLine(text)}`);
    const folder = await runReviewTool(["plan", state.TASK, "--proposal", join(ctx.dir, "plan.md")]);
    if (!folder) fail("la critique du plan a échoué");
    applyReview(ctx, folder, "plan", "gpt");
    state.PHASE = "implementation";
    save(ctx);
    return;
  }
  if (file) fail("GPT implémente : « plan » sans fichier, c'est GPT qui écrit le plan");
  record(ctx, "ORCHESTRATEUR", "GPT écrit le plan...");
  const context = (PLAN_CONTEXT[state.TYPE] ?? PLAN_CONTEXT["non-classe"]).flatMap((prefix) => ["--context", prefix]);
  const { output } = await runImplementTool(ctx, ["plan", state.TASK, ...context]);
  writeFileSync(join(ctx.dir, "plan.md"), output.resume);
  state.PLAN = output.resume;
  state.GPT_OPINION = `Plan : ${firstLine(output.resume)}`;
  record(ctx, "GPT", `Plan proposé : ${firstLine(output.resume)} (${relative(root, join(ctx.dir, "plan.md"))})`);
  state.PHASE = "critique du plan";
  record(ctx, "ORCHESTRATEUR", "Claude critique le plan : claude-review start --mode plan, puis claude-review submit <fichier>");
}

async function implement() {
  const ctx = loadContext();
  const state = ctx.state;
  if (state.IMPLEMENTER !== "gpt") fail("Claude implémente dans sa session : pas de commande « implement » pour lui");
  const planFile = join(ctx.dir, "plan.md");
  if (!existsSync(planFile)) fail("pas de plan retenu : node tools/orchestrator.mjs plan");
  const args = ["implement", state.TASK, "--plan", planFile];
  const open = writeOpenIssues(ctx);
  if (open) args.push("--issues", open.file);
  const { output } = await runImplementTool(ctx, args);
  state.GPT_OPINION = output.resume;
  state.FILES_CHANGED = changedFiles();
  state.PHASE = "implementation";
  record(ctx, "GPT", `Implémentation : ${firstLine(output.resume)} (${output.fichiers_modifies.length} fichier(s) déclaré(s))`);
  if (output.reponses.length > 0) applyAnswers(ctx, answersMarkdown(output.reponses), "gpt");
}

async function answer(file) {
  const ctx = loadContext();
  const state = ctx.state;
  if (state.IMPLEMENTER === "claude") {
    if (!file) fail("Claude implémente : node tools/orchestrator.mjs answer <reponses.md>");
    if (!existsSync(file)) fail(`réponses introuvables : ${file}`);
    const text = readFileSync(file, "utf8");
    state.CLAUDE_OPINION = text;
    applyAnswers(ctx, text, "claude");
    return;
  }
  if (file) fail("GPT implémente : « answer » sans fichier, c'est GPT qui corrige et répond");
  const open = writeOpenIssues(ctx);
  if (!open) fail("aucune remarque ouverte");
  const args = ["fix", state.TASK, "--issues", open.file];
  const planFile = join(ctx.dir, "plan.md");
  if (existsSync(planFile)) args.push("--plan", planFile);
  const { output } = await runImplementTool(ctx, args);
  state.GPT_OPINION = output.resume;
  state.FILES_CHANGED = changedFiles();
  applyAnswers(ctx, answersMarkdown(output.reponses), "gpt");
}

function mcpd(tool, args) {
  return spawnSync(process.execPath, [join(root, "tools", "mcpd.mjs"), tool, JSON.stringify(args)], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
}

// Lance le playtest par le pont, note l'empreinte du code et ecrit une marque unique dans le journal serveur de cette
// session. Le pont ne fournit pas d'identifiant de session (instanceId identique d'un playtest a l'autre, verifie le
// 15/09/2026) : la marque en tient lieu. Verifie : marque presente dans la session ecrite, absente de la suivante.
const SESSION_READY_TRIES = 12;
const SESSION_READY_DELAY_MS = 2000;

// Erreurs connues et sans rapport avec le code teste : toujours affichees dans le journal, mais elles ne font pas
// echouer un playtest. Chaque entree dit pourquoi ; en ajouter une demande la meme justification, verifiee.
const KNOWN_BENIGN_ERRORS = [
  {
    pattern: /Failed to load sound rbxassetid:\/\/6417837881/,
    reason: "son d'un modèle archivé, plus utilisé nulle part ; requête restée en cache de la session Studio",
  },
  {
    pattern: /enregistrement automatique est en cours/,
    reason: "sauvegarde manuelle du place refusée pendant l'enregistrement automatique de Studio",
  },
];

async function testStart() {
  const ctx = loadContext();
  const hash = workHash();
  // Horodatage des journaux de Studio (secondes) : seules les erreurs posterieures au lancement comptent pour ce test.
  const startTs = Date.now() / 1000;
  const result = mcpd("solo_playtest", { action: "start", mode: "play" });
  if (result.status !== 0 || /"success"\s*:\s*false/.test(result.stdout)) {
    ctx.state.TEST_RUN = null;
    record(ctx, "MCP", `Lancement du playtest impossible : ${firstLine(result.stderr || result.stdout)}`);
    process.exit(1);
  }
  const marker = `arbitre-${randomUUID()}`;
  const code = `print("[ARBITRE] session ${marker}") return "marque-ecrite"`;
  let written = false;
  // Le serveur du playtest met quelques secondes a accepter les evaluations.
  for (let attempt = 0; attempt < SESSION_READY_TRIES && !written; attempt += 1) {
    const printed = mcpd("eval_server_runtime", { code });
    written = printed.status === 0 && printed.stdout.includes("marque-ecrite");
    if (!written) await new Promise((resolve) => setTimeout(resolve, SESSION_READY_DELAY_MS));
  }
  if (!written) {
    mcpd("solo_playtest", { action: "stop" });
    ctx.state.TEST_RUN = null;
    record(ctx, "MCP", "Playtest arrêté : impossible d'écrire la marque de session dans le journal du serveur");
    process.exit(1);
  }
  ctx.state.TEST_RUN = { hash, marker, startTs, startedAt: new Date().toISOString() };
  record(ctx, "MCP", `Playtest lancé par l'arbitre (code ${hash}, marque ${marker})`);
}

async function testEnd(flags) {
  const ctx = loadContext();
  const state = ctx.state;
  // let : un --ok dont les journaux montrent des erreurs d'execution devient un echec avec diagnostic.
  let ok = flags.includes("--ok");
  let failed = flags.includes("--fail");
  if (ok === failed) fail("préciser --ok ou --fail");
  const index = flags.indexOf("--logs");
  let logs;
  let provenance;
  if (index !== -1) {
    // Journaux importes sans provenance Studio : acceptes pour un diagnostic, jamais comme preuve d'un playtest OK.
    if (ok) fail("--logs ne sert qu'au diagnostic (--fail) : un playtest OK se prouve par « test start » puis « test --ok »");
    if (!flags[index + 1] || !existsSync(flags[index + 1])) fail("fichier de journaux introuvable");
    logs = readFileSync(flags[index + 1], "utf8");
    provenance = "journaux importés";
    state.TEST_HASH = null;
  } else {
    const run = state.TEST_RUN;
    if (!run) fail("aucun playtest lancé par l'arbitre : node tools/orchestrator.mjs test start");
    // Journaux lus avant l'arret : ce sont ceux de ce lancement.
    const result = mcpd("get_runtime_logs", {});
    const stop = mcpd("solo_playtest", { action: "stop" });
    state.TEST_RUN = null;
    if (stop.status !== 0) {
      record(ctx, "MCP", `Arrêt du playtest à vérifier : ${firstLine(stop.stderr || stop.stdout)}`);
    }
    const hashNow = workHash();
    if (result.status !== 0 || !result.stdout.trim()) {
      const reason = firstLine(result.stderr || result.stdout || `code ${result.status}`);
      if (ok) {
        state.TEST_RESULTS = null;
        state.TEST_HASH = null;
        record(ctx, "MCP", `Playtest non enregistré : journaux de Studio illisibles (${reason})`);
        process.exit(1);
      }
      logs = `journaux de Studio indisponibles : ${reason}`;
    } else {
      logs = result.stdout;
    }
    if (ok && hashNow !== run.hash) {
      state.TEST_RESULTS = null;
      state.TEST_HASH = null;
      record(
        ctx,
        "MCP",
        `Playtest non enregistré : le code a changé depuis son lancement (${run.hash} -> ${hashNow}), le rejouer`,
      );
      process.exit(1);
    }
    // Journaux d'une autre session (playtest relance hors de l'arbitre) : la marque ecrite au lancement est absente.
    if (ok && !(run.marker && logs.includes(run.marker))) {
      state.TEST_RESULTS = null;
      state.TEST_HASH = null;
      record(
        ctx,
        "MCP",
        "Playtest non enregistré : la marque de session est absente des journaux (autre session ?), le rejouer",
      );
      process.exit(1);
    }
    provenance = `lancé à ${run.startedAt} sur le code ${run.hash}, marque ${run.marker ?? "absente"}`;
    // Erreurs d'execution depuis le lancement : un playtest qui plante n'est jamais OK, quoi qu'en dise --ok.
    if (ok) {
      let entries = null;
      try {
        const parsed = JSON.parse(logs);
        entries = Array.isArray(parsed.entries) ? parsed.entries : null;
      } catch {
        entries = null;
      }
      if (!entries) {
        state.TEST_RESULTS = null;
        state.TEST_HASH = null;
        record(ctx, "MCP", "Playtest non enregistré : format des journaux illisible, vérification des erreurs impossible");
        process.exit(1);
      }
      const since = (run.startTs ?? 0) - 1;
      const errors = entries.filter((entry) => entry.level === "ERR" && Number(entry.ts) >= since);
      const benign = errors.filter((entry) =>
        KNOWN_BENIGN_ERRORS.some((known) => known.pattern.test(String(entry.message ?? ""))),
      );
      const real = errors.filter((entry) => !benign.includes(entry));
      if (benign.length > 0) {
        record(ctx, "MCP", `Erreurs connues ignorées : ${benign.map((entry) => firstLine(entry.message)).join(" | ")}`);
      }
      if (real.length > 0) {
        record(
          ctx,
          "MCP",
          `Erreurs d'exécution dans le playtest : ${real.map((entry) => firstLine(entry.message)).join(" | ")} ; ` +
            "enregistré en échec",
        );
        ok = false;
        failed = true;
      }
    }
    state.TEST_HASH = ok ? run.hash : null;
  }
  const logsFile = join(ctx.dir, `journaux-studio-${Date.now()}.txt`);
  writeFileSync(logsFile, logs);
  let instance = null;
  try {
    instance = JSON.parse(logs).instanceId ?? null;
  } catch {
    // journaux en texte : pas d'identifiant d'instance
  }
  state.TEST_RESULTS = ok ? "OK" : "ÉCHEC";
  if (!ok) state.FAILED_TESTS += 1;
  state.TEST_INSTANCE = instance;
  state.MCP_LOGS = tail(logs, 40);
  record(ctx, "MCP", `Playtest ${ok ? "OK" : "en échec"} (${provenance} ; journaux : ${relative(root, logsFile)})`);
  if (failed) {
    const folder = await runReviewTool(["diagnostic", state.TASK, "--logs", logsFile]);
    if (!folder) fail("le diagnostic a échoué");
    applyReview(ctx, folder, "diagnostic", "gpt");
  }
}

async function review() {
  const ctx = loadContext();
  const state = ctx.state;
  if (state.REVIEWER === "claude") {
    fail("Claude relit cette tâche : node tools/orchestrator.mjs claude-review start, puis claude-review submit <fichier>");
  }
  if (state.ITERATION >= state.MAX_ITERATIONS) {
    record(ctx, "ORCHESTRATEUR", `Limite de ${state.MAX_ITERATIONS} itérations atteinte : l'utilisateur tranche.`);
    process.exit(1);
  }
  state.FILES_CHANGED = changedFiles();
  state.ITERATION += 1;
  record(
    ctx,
    "ORCHESTRATEUR",
    `Itération ${state.ITERATION}/${state.MAX_ITERATIONS} : ${state.FILES_CHANGED.length} fichier(s) changé(s)`,
  );
  let args;
  let mode;
  const open = writeOpenIssues(ctx);
  if (!open) {
    mode = "initial";
    args = ["initial", state.TASK];
  } else {
    const answers = answersPath(ctx);
    if (!answers) fail("répondre d'abord aux remarques : node tools/orchestrator.mjs answer");
    mode = "final";
    args = ["final", state.TASK, "--previous", open.folder, "--answers", answers];
  }
  const folder = await runReviewTool(args);
  if (!folder) fail("la relecture a échoué");
  applyReview(ctx, folder, mode, "gpt");
}

function claudeReviewStart(modeFlag) {
  const ctx = loadContext();
  const state = ctx.state;
  if (state.REVIEWER !== "claude") fail("GPT relit cette tâche : node tools/orchestrator.mjs review");
  const defaultMode =
    state.PHASE === "critique du plan" ? "plan" : state.REMAINING_ISSUES.length === 0 ? "initial" : "final";
  const mode = modeFlag ?? defaultMode;
  if (!["plan", "initial", "final"].includes(mode)) fail("--mode attendu : plan, initial ou final");
  if (mode !== "plan") {
    if (state.ITERATION >= state.MAX_ITERATIONS) {
      record(ctx, "ORCHESTRATEUR", `Limite de ${state.MAX_ITERATIONS} itérations atteinte : l'utilisateur tranche.`);
      process.exit(1);
    }
    state.ITERATION += 1;
    state.FILES_CHANGED = changedFiles();
  }
  state.CLAUDE_REVIEW = { mode, hash: workHash(), startedAt: new Date().toISOString() };
  record(
    ctx,
    "CLAUDE",
    `Relecture ${mode} commencée sur le code ${state.CLAUDE_REVIEW.hash}` +
      (mode === "plan" ? "" : ` (itération ${state.ITERATION}/${state.MAX_ITERATIONS})`),
  );
}

// Meme exigence de forme que pour GPT (tools/gpt-review.schema.json), verifiee a la main.
function validateReview(review) {
  const problems = [];
  if (review?.relu !== true) problems.push("« relu » doit valoir true");
  if (!["approuve", "corrections_demandees"].includes(review?.verdict)) problems.push("verdict invalide");
  if (typeof review?.resume !== "string" || !review.resume) problems.push("resume manquant");
  if (!Array.isArray(review?.remarques)) problems.push("remarques doit être un tableau");
  if (!Array.isArray(review?.suivi)) problems.push("suivi doit être un tableau");
  for (const remark of review?.remarques ?? []) {
    for (const key of ["id", "gravite", "categorie", "fichier", "probleme", "scenario", "correction"]) {
      if (typeof remark?.[key] !== "string" || !remark[key]) problems.push(`remarque ${remark?.id ?? "?"} : ${key} manquant`);
    }
    if (!Number.isInteger(remark?.ligne)) problems.push(`remarque ${remark?.id ?? "?"} : ligne entière attendue`);
    if (!["bloquant", "majeur", "mineur"].includes(remark?.gravite)) problems.push(`remarque ${remark?.id ?? "?"} : gravité invalide`);
  }
  for (const follow of review?.suivi ?? []) {
    const valid =
      typeof follow?.id === "string" &&
      ["corrige", "non_corrige", "rejet_accepte", "rejet_conteste"].includes(follow?.statut) &&
      typeof follow?.commentaire === "string";
    if (!valid) problems.push(`suivi ${follow?.id ?? "?"} invalide`);
  }
  return problems;
}

function claudeReviewSubmit(file) {
  const ctx = loadContext();
  const state = ctx.state;
  const run = state.CLAUDE_REVIEW;
  if (!run) fail("aucune relecture commencée : node tools/orchestrator.mjs claude-review start");
  if (!file || !existsSync(file)) fail("fichier de remarques introuvable");
  let review;
  try {
    review = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    fail(`JSON illisible : ${error.message}`);
  }
  const problems = validateReview(review);
  if (problems.length > 0) fail(`remarques invalides : ${problems.join(" ; ")}`);
  const hashNow = workHash();
  if (hashNow !== run.hash) {
    state.CLAUDE_REVIEW = null;
    if (run.mode !== "plan") state.ITERATION = Math.max(state.ITERATION - 1, 0);
    record(
      ctx,
      "ORCHESTRATEUR",
      `Relecture de Claude refusée : le code a changé depuis son début (${run.hash} -> ${hashNow}), la recommencer`,
    );
    process.exit(1);
  }
  const folder = join(root, "tools", "reviews", `${nowStamp()}-claude-${run.mode}`);
  mkdirSync(folder, { recursive: true });
  writeFileSync(join(folder, "remarques.json"), `${JSON.stringify(review, null, 2)}\n`);
  writeFileSync(join(folder, "empreinte.txt"), `${run.hash}\n`);
  state.CLAUDE_REVIEW = null;
  applyReview(ctx, folder, run.mode, "claude");
  if (run.mode === "plan") {
    state.PHASE = "implementation";
    save(ctx);
  }
}

function check() {
  const ctx = loadContext();
  record(ctx, "CHECK", "lune run check...");
  const hashBefore = workHash();
  // Sous Windows, lune passe par le shell : commande en une seule chaine (des arguments separes avec shell sont
  // concatenes sans echappement, et Node le signale).
  const options = { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 };
  const result =
    process.platform === "win32"
      ? spawnSync("lune run check", { ...options, shell: true })
      : spawnSync("lune", ["run", "check"], options);
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.replace(/\x1b\[[0-9;]*m/g, "");
  const ok = result.status === 0;
  if (ok && workHash() !== hashBefore) {
    ctx.state.CHECK = null;
    ctx.state.CHECK_HASH = null;
    record(ctx, "CHECK", "code modifié pendant le check : résultat ignoré, le relancer");
    process.exit(1);
  }
  ctx.state.CHECK = ok ? "vert" : "échec";
  ctx.state.CHECK_HASH = ok ? hashBefore : null;
  record(ctx, "CHECK", ok ? "sourcemap ✓  selene ✓  stylua ✓  luau-lsp ✓" : `échec :\n${tail(output, 20)}`);
  if (!ok) process.exit(1);
}

function status() {
  const { state } = loadContext();
  const issues =
    state.REMAINING_ISSUES.map(
      (issue) =>
        `    - ${issue.id} [${issue.gravite}] ${issue.fichier}:${issue.ligne} ${issue.probleme} (${issue.statut})`,
    ).join("\n") || "    aucune";
  const hash = workHash();
  const fresh = (value) => (value === hash ? "à jour" : value ? "code modifié depuis" : "jamais");
  console.log(
    [
      `TASK              ${state.TASK}`,
      `TYPE              ${state.TYPE}`,
      `IMPLEMENTER       ${state.IMPLEMENTER}   REVIEWER ${state.REVIEWER}`,
      `PHASE             ${state.PHASE}`,
      `PLAN              ${state.PLAN ? firstLine(state.PLAN) : "-"}`,
      `FILES_CHANGED     ${changedFiles().join(", ") || "-"}`,
      `CLAUDE_OPINION    ${state.CLAUDE_OPINION ? firstLine(state.CLAUDE_OPINION) : "-"}`,
      `GPT_OPINION       ${state.GPT_OPINION ? firstLine(state.GPT_OPINION) : "-"} (${state.GPT_VERDICT ?? "-"})`,
      `CLAUDE_REVIEW     ${state.CLAUDE_REVIEW ? `${state.CLAUDE_REVIEW.mode} en cours (code ${state.CLAUDE_REVIEW.hash})` : "-"}`,
      `TEST_RESULTS      ${state.TEST_RESULTS ?? "-"} (${fresh(state.TEST_HASH)})` +
        (state.TEST_INSTANCE ? ` instance ${state.TEST_INSTANCE}` : ""),
      `MCP_LOGS          ${state.MCP_LOGS ? `${state.MCP_LOGS.split("\n").length} dernières lignes gardées` : "-"}`,
      `CHECK             ${state.CHECK ?? "-"} (${fresh(state.CHECK_HASH)})`,
      `REVIEW            ${state.REVIEW_VERDICT ?? "-"} (${fresh(state.REVIEW_HASH)}) ${state.LAST_REVIEW ?? ""}`,
      `REMAINING_ISSUES  ${state.REMAINING_ISSUES.length}`,
      issues,
      `ITERATION         ${state.ITERATION}/${state.MAX_ITERATIONS}`,
      `MESURES           ${state.SEVERE_REMARKS} remarque(s) grave(s), ${state.FAILED_TESTS} playtest(s) raté(s)`,
      `CODE              ${hash}`,
    ].join("\n"),
  );
}

function done() {
  const ctx = loadContext();
  const state = ctx.state;
  const hash = workHash();
  const blockers = [];
  if (state.REVIEW_VERDICT !== "approuve" || state.REVIEW_HASH !== hash) {
    blockers.push(`pas de relecture approuvée par ${state.REVIEWER} sur le code actuel`);
  }
  if (state.REMAINING_ISSUES.some((issue) => issue.gravite !== "mineur")) {
    blockers.push("remarques bloquantes ou majeures encore ouvertes");
  }
  if (state.REMAINING_ISSUES.some((issue) => issue.statut === "rejet_conteste")) {
    blockers.push("rejet contesté par le relecteur encore ouvert");
  }
  if (state.TEST_RESULTS !== "OK" || state.TEST_HASH !== hash) blockers.push("pas de playtest OK sur le code actuel");
  if (state.CHECK !== "vert" || state.CHECK_HASH !== hash) blockers.push("pas de check vert sur le code actuel");
  const mojibake = introducedMojibake(changedFiles());
  if (mojibake.length > 0) {
    blockers.push(`accents abîmés introduits : ${mojibake.map((found) => found.fichier).join(", ")}`);
  }
  if (blockers.length > 0) {
    record(ctx, "ORCHESTRATEUR", `Clôture refusée : ${blockers.join(" ; ")}`);
    process.exit(1);
  }
  appendMeasure(state);
  state.PHASE = "terminee";
  record(ctx, "EQUIPE", `Tâche terminée : ${state.TASK} (mesure ajoutée à ${relative(root, MEASURES)})`);
}

function stats() {
  const list = readMeasures();
  if (list.length === 0) {
    console.log(`Aucune mesure : elles s'ajoutent à chaque tâche close (${relative(root, MEASURES)}).`);
    return;
  }
  const lines = ["TYPE          IMPLEMENTEUR  TACHES  GRAVES/T  RATES/T  ITER/T"];
  for (const type of [...new Set(list.map((measure) => measure.type))]) {
    for (const agent of AGENTS) {
      const items = list.filter((measure) => measure.type === type && measure.implementeur === agent);
      if (items.length === 0) continue;
      const score = scoreOf(items);
      lines.push(
        `${String(type).padEnd(13)} ${agent.padEnd(13)} ${String(score.taches).padEnd(7)} ` +
          `${score.graves.toFixed(2).padEnd(9)} ${score.rates.toFixed(2).padEnd(8)} ${score.iterations.toFixed(2)}`,
      );
    }
    const pick = pickImplementer(type);
    lines.push(`  -> --by auto choisirait ${pick.agent} : ${pick.reason}`);
  }
  console.log(lines.join("\n"));
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  const option = (name) => {
    const index = rest.indexOf(name);
    return index === -1 ? undefined : rest[index + 1];
  };
  switch (command) {
    case "start": {
      const task = rest[0];
      if (!task || task.startsWith("--")) fail('usage : node tools/orchestrator.mjs start "<tache>" [--type T] [--by claude|gpt|auto] [--max 10]');
      const max = option("--max") === undefined ? 10 : Number(option("--max"));
      if (!Number.isInteger(max) || max < 1) fail("--max attend un entier positif");
      const by = option("--by") ?? "claude";
      if (![...AGENTS, "auto"].includes(by)) fail("--by attend claude, gpt ou auto");
      const type = option("--type");
      if (type !== undefined && !TYPES.includes(type)) fail(`--type attend ${TYPES.join(", ")}`);
      if (by === "auto" && type === undefined) fail("--by auto demande --type, pour comparer des tâches de même nature");
      start(task, { max, by, type: type ?? "non-classe" });
      break;
    }
    case "plan":
      await plan(rest[0]);
      break;
    case "implement":
      await implement();
      break;
    case "answer":
      await answer(rest[0]);
      break;
    case "test":
      if (rest[0] === "start") await testStart();
      else await testEnd(rest);
      break;
    case "review":
      await review();
      break;
    case "claude-review":
      if (rest[0] === "start") claudeReviewStart(option("--mode"));
      else if (rest[0] === "submit") claudeReviewSubmit(rest[1]);
      else fail("usage : claude-review start [--mode plan|initial|final] | claude-review submit <remarques.json>");
      break;
    case "check":
      check();
      break;
    case "status":
      status();
      break;
    case "done":
      done();
      break;
    case "stats":
      stats();
      break;
    default:
      fail("commande attendue : start, plan, implement, answer, test, review, claude-review, check, status, done ou stats");
  }
}

// Une commande git en echec (depot absent, HEAD introuvable...) arrete l'arbitre avec son message.
main().catch((error) => fail(error.message));
