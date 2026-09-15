#!/usr/bin/env node
// Arbitre de la boucle Claude <-> GPT (AGENTS.md). Programme sans IA : il garde l'etat de la tache, fait parler
// Claude (la session Claude Code lance ces commandes) et GPT (Codex, par tools/gpt-review.mjs) a egalite, et s'appuie
// sur des sources objectives plutot que sur ce que chaque modele raconte : git (fichiers changes, diff, empreinte) et
// le pont MCP (journaux de Studio).
//
// Commandes :
//   node tools/orchestrator.mjs start "<tache>" [--max 10]
//   node tools/orchestrator.mjs plan <plan-claude.md>                  plan de Claude, puis critique de GPT
//   node tools/orchestrator.mjs answer <reponses-claude.md>            reponses de Claude aux remarques ouvertes
//   node tools/orchestrator.mjs test start                             lance le playtest par le pont (empreinte notee)
//   node tools/orchestrator.mjs test --ok|--fail                       journaux lus, playtest arrete, resultat note
//   node tools/orchestrator.mjs test --fail --logs <fichier>           diagnostic sur des journaux importes
//   node tools/orchestrator.mjs review                                 relecture GPT des changements
//   node tools/orchestrator.mjs check                                  lune run check
//   node tools/orchestrator.mjs status                                 etat de la tache
//   node tools/orchestrator.mjs done                                   cloture si toutes les conditions tiennent
//
// Etat : tools/reviews/tasks/<id>/state.json (hors depot) ; tache courante dans tools/reviews/tasks/current.
// Arbitrage :
// - une remarque n'est fermee que si GPT le confirme (corrige, ou rejet dont il accepte la raison) ; Claude repond a
//   chaque remarque mais ne la ferme pas seul ; un rejet conteste reste ouvert et bloque la cloture ;
// - une relecture vaut pour le code qu'elle a reellement recu : empreinte prise par gpt-review.mjs avant l'envoi, et
//   relecture obsolete si le code a change pendant qu'elle tournait ; seul le verdict d'une relecture (initiale ou
//   finale) compte pour la cloture, pas celui d'une critique de plan ou d'un diagnostic ;
// - un playtest n'est enregistre OK que s'il a ete lance par l'arbitre (test start), que ses journaux ont pu etre lus
//   dans Studio sans erreur, qu'ils contiennent la marque de session ecrite au lancement et que le code n'a pas change
//   depuis ; des journaux importes ne servent qu'au diagnostic ;
// - un check vaut pour le code present a son lancement, et il est ignore si le code change pendant qu'il tourne ;
// - la cloture exige : relecture approuvee, playtest OK et check vert, tous sur l'empreinte actuelle, et aucune
//   remarque bloquante ou majeure ouverte ;
// - au-dela de MAX iterations de relecture, l'arbitre s'arrete : l'utilisateur tranche.

import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

import { changedFiles, root, workHash } from "./git-state.mjs";
import { appendJournal } from "./journal.mjs";

const TASKS = join(root, "tools", "reviews", "tasks");
const CURRENT = join(TASKS, "current");

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

function loadContext() {
  if (!existsSync(CURRENT)) fail('aucune tache en cours : node tools/orchestrator.mjs start "<tache>"');
  const id = readFileSync(CURRENT, "utf8").trim();
  const dir = join(TASKS, id);
  const file = join(dir, "state.json");
  if (!existsSync(file)) fail(`etat introuvable : ${file}`);
  return { id, dir, state: JSON.parse(readFileSync(file, "utf8")) };
}

function save(ctx) {
  writeFileSync(join(ctx.dir, "state.json"), `${JSON.stringify(ctx.state, null, 2)}\n`);
}

function record(ctx, tag, message) {
  ctx.state.HISTORY.push({ at: new Date().toISOString(), tag, message });
  appendJournal(tag, message);
  save(ctx);
}

// Lance gpt-review.mjs en laissant defiler sa sortie ; rend le dossier de relecture annonce a la fin.
function gptReview(args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [join(root, "tools", "gpt-review.mjs"), ...args], { cwd: root });
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk;
      process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => process.stderr.write(chunk));
    child.on("close", (code) => {
      const match = output.match(/^Dossier : (.+)$/m);
      resolve(code === 0 && match ? join(root, match[1].trim()) : null);
    });
  });
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

// Integre un avis de GPT : suivi des remarques ouvertes (seul GPT les ferme), nouvelles remarques avec un identifiant
// unique sur toute la tache (G<numero d'appel>-<id GPT>), et, pour une relecture, verdict et empreinte du code relu.
// Un avis obsolete (code modifie pendant que GPT travaillait) est archive sans toucher aux remarques : il porte sur une
// version qui n'existe plus, il ne ferme donc rien et n'ouvre rien.
function applyReview(ctx, folder, mode) {
  const state = ctx.state;
  const review = JSON.parse(readFileSync(join(folder, "remarques.json"), "utf8"));
  // Un avis que GPT n'a pas pu donner (lecture impossible...) ne compte ni comme avis ni comme iteration.
  if (review.relu !== true) {
    if (mode === "initial" || mode === "final") state.ITERATION = Math.max(state.ITERATION - 1, 0);
    state.LAST_REVIEW = relative(root, folder);
    record(ctx, "ORCHESTRATEUR", `GPT (${mode}) n'a pas pu relire : ${review.resume} (itération non comptée)`);
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
      `GPT (${mode}) : avis obsolète (code modifié pendant qu'il travaillait), archivé sans fermer ni ouvrir de ` +
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
      issue.commentaire_gpt = follow.commentaire;
    }
  }
  for (const remark of review.remarques) {
    const id = `G${state.GPT_CALLS}-${remark.id}`;
    byId.set(id, { ...toSchema({ ...remark, id }), origine: mode, statut: "ouverte" });
  }
  state.REMAINING_ISSUES = [...byId.values()];
  state.GPT_OPINION = review.resume;
  state.GPT_VERDICT = review.verdict;
  if (mode === "initial" || mode === "final") {
    const hashFile = join(folder, "empreinte.txt");
    state.REVIEW_VERDICT = review.verdict;
    state.REVIEW_HASH = existsSync(hashFile) ? readFileSync(hashFile, "utf8").trim() : null;
  }
  record(
    ctx,
    "ORCHESTRATEUR",
    `GPT (${mode}) : ${review.verdict}, ${review.remarques.length} nouvelle(s) remarque(s), ${closed} fermée(s), ` +
      `${state.REMAINING_ISSUES.length} ouverte(s)`,
  );
}

function start(task, max) {
  const id = new Date().toISOString().replace(/[:.]/g, "-");
  const dir = join(TASKS, id);
  mkdirSync(dir, { recursive: true });
  const ctx = {
    id,
    dir,
    state: {
      TASK: task,
      PHASE: "plan",
      PLAN: null,
      FILES_CHANGED: [],
      CLAUDE_OPINION: null,
      GPT_OPINION: null,
      GPT_VERDICT: null,
      REVIEW_VERDICT: null,
      TEST_RESULTS: null,
      TEST_INSTANCE: null,
      MCP_LOGS: null,
      CHECK: null,
      REMAINING_ISSUES: [],
      ITERATION: 0,
      MAX_ITERATIONS: max,
      GPT_CALLS: 0,
      TEST_HASH: null,
      CHECK_HASH: null,
      REVIEW_HASH: null,
      LAST_REVIEW: null,
      HISTORY: [],
    },
  };
  writeFileSync(CURRENT, id);
  record(ctx, "ORCHESTRATEUR", `Nouvelle tâche : ${task} (${max} itérations au plus)`);
}

async function plan(file) {
  const ctx = loadContext();
  if (!existsSync(file)) fail(`plan introuvable : ${file}`);
  const text = readFileSync(file, "utf8");
  writeFileSync(join(ctx.dir, "plan-claude.md"), text);
  ctx.state.PLAN = text;
  ctx.state.CLAUDE_OPINION = `Plan : ${firstLine(text)}`;
  record(ctx, "CLAUDE", `Plan proposé : ${firstLine(text)}`);
  const folder = await gptReview(["plan", ctx.state.TASK, "--proposal", join(ctx.dir, "plan-claude.md")]);
  if (!folder) fail("la critique du plan a échoué");
  applyReview(ctx, folder, "plan");
  ctx.state.PHASE = "implementation";
  save(ctx);
}

function answer(file) {
  const ctx = loadContext();
  if (!existsSync(file)) fail(`réponses introuvables : ${file}`);
  const text = readFileSync(file, "utf8");
  writeFileSync(join(ctx.dir, "reponses-claude.md"), text);
  ctx.state.CLAUDE_OPINION = text;
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
    "CLAUDE",
    `Réponses : ${accepted} acceptée(s), ${rejected} rejetée(s)` +
      (unanswered.length > 0 ? ` ; sans réponse : ${unanswered.join(", ")}` : ""),
  );
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
// 15/09/2026) : la marque en tient lieu. Les journaux lus a la fin doivent la contenir, sinon ils viennent d'une autre
// session (playtest relance hors de l'arbitre). Verifie : marque presente dans la session ecrite, absente de la
// session relancee ensuite.
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
  state.TEST_INSTANCE = instance;
  state.MCP_LOGS = tail(logs, 40);
  record(ctx, "MCP", `Playtest ${ok ? "OK" : "en échec"} (${provenance} ; journaux : ${relative(root, logsFile)})`);
  if (failed) {
    const folder = await gptReview(["diagnostic", state.TASK, "--logs", logsFile]);
    if (!folder) fail("le diagnostic a échoué");
    applyReview(ctx, folder, "diagnostic");
  }
}

async function review() {
  const ctx = loadContext();
  const state = ctx.state;
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
  if (state.REMAINING_ISSUES.length === 0) {
    mode = "initial";
    args = ["initial", state.TASK];
  } else {
    const answers = join(ctx.dir, "reponses-claude.md");
    if (!existsSync(answers)) fail("répondre d'abord aux remarques : node tools/orchestrator.mjs answer <fichier>");
    const open = join(ctx.dir, "ouvertes");
    mkdirSync(open, { recursive: true });
    writeFileSync(
      join(open, "remarques.json"),
      `${JSON.stringify(
        {
          relu: true,
          verdict: "corrections_demandees",
          resume: "Remarques encore ouvertes pour cette tâche",
          remarques: state.REMAINING_ISSUES.map(toSchema),
          suivi: [],
        },
        null,
        2,
      )}\n`,
    );
    mode = "final";
    args = ["final", state.TASK, "--previous", open, "--answers", answers];
  }
  const folder = await gptReview(args);
  if (!folder) fail("la relecture a échoué");
  applyReview(ctx, folder, mode);
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
      `PHASE             ${state.PHASE}`,
      `PLAN              ${state.PLAN ? firstLine(state.PLAN) : "-"}`,
      `FILES_CHANGED     ${changedFiles().join(", ") || "-"}`,
      `CLAUDE_OPINION    ${state.CLAUDE_OPINION ? firstLine(state.CLAUDE_OPINION) : "-"}`,
      `GPT_OPINION       ${state.GPT_OPINION ?? "-"} (${state.GPT_VERDICT ?? "-"})`,
      `TEST_RESULTS      ${state.TEST_RESULTS ?? "-"} (${fresh(state.TEST_HASH)})` +
        (state.TEST_INSTANCE ? ` instance ${state.TEST_INSTANCE}` : ""),
      `MCP_LOGS          ${state.MCP_LOGS ? `${state.MCP_LOGS.split("\n").length} dernières lignes gardées` : "-"}`,
      `CHECK             ${state.CHECK ?? "-"} (${fresh(state.CHECK_HASH)})`,
      `REVIEW            ${state.REVIEW_VERDICT ?? "-"} (${fresh(state.REVIEW_HASH)}) ${state.LAST_REVIEW ?? ""}`,
      `REMAINING_ISSUES  ${state.REMAINING_ISSUES.length}`,
      issues,
      `ITERATION         ${state.ITERATION}/${state.MAX_ITERATIONS}`,
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
    blockers.push("pas de relecture GPT approuvée sur le code actuel");
  }
  if (state.REMAINING_ISSUES.some((issue) => issue.gravite !== "mineur")) {
    blockers.push("remarques bloquantes ou majeures encore ouvertes");
  }
  if (state.REMAINING_ISSUES.some((issue) => issue.statut === "rejet_conteste")) {
    blockers.push("rejet contesté par GPT encore ouvert");
  }
  if (state.TEST_RESULTS !== "OK" || state.TEST_HASH !== hash) blockers.push("pas de playtest OK sur le code actuel");
  if (state.CHECK !== "vert" || state.CHECK_HASH !== hash) blockers.push("pas de check vert sur le code actuel");
  if (blockers.length > 0) {
    record(ctx, "ORCHESTRATEUR", `Clôture refusée : ${blockers.join(" ; ")}`);
    process.exit(1);
  }
  state.PHASE = "terminee";
  record(ctx, "EQUIPE", `Tâche terminée : ${state.TASK}`);
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  switch (command) {
    case "start": {
      const task = rest[0];
      if (!task) fail('usage : node tools/orchestrator.mjs start "<tache>" [--max 10]');
      const maxIndex = rest.indexOf("--max");
      const max = maxIndex === -1 ? 10 : Number(rest[maxIndex + 1]);
      if (!Number.isInteger(max) || max < 1) fail("--max attend un entier positif");
      start(task, max);
      break;
    }
    case "plan":
      if (!rest[0]) fail("usage : node tools/orchestrator.mjs plan <plan-claude.md>");
      await plan(rest[0]);
      break;
    case "answer":
      if (!rest[0]) fail("usage : node tools/orchestrator.mjs answer <reponses-claude.md>");
      answer(rest[0]);
      break;
    case "test":
      if (rest[0] === "start") await testStart();
      else await testEnd(rest);
      break;
    case "review":
      await review();
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
    default:
      fail("commande attendue : start, plan, answer, test, review, check, status ou done");
  }
}

// Une commande git en echec (depot absent, HEAD introuvable...) arrete l'arbitre avec son message.
main().catch((error) => fail(error.message));
