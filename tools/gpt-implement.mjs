#!/usr/bin/env node
// Implementation par GPT (Codex CLI, GPT-6 Astra) dans le depot, sous controle de l'arbitre (AGENTS.md).
//
// Usage (pilote normalement par tools/orchestrator.mjs) :
//   node tools/gpt-implement.mjs plan "<tache>"                                      plan d'architecture, lecture seule
//   node tools/gpt-implement.mjs implement "<tache>" --plan <plan.md> [--issues <remarques.json>]
//   node tools/gpt-implement.mjs fix "<tache>" --issues <remarques.json> [--plan <plan.md>]
// Options : --model <id> (defaut GPT_IMPLEMENT_MODEL ou gpt-6-astra), --effort <low|medium|high|xhigh|max> (high),
//           --context <prefixe> (plan, repetable : dossiers ou fichiers dont le contenu est envoye en priorite).
//
// Sandbox :
// - plan : lecture seule (-s read-only), rien ne peut etre modifie. Sous Windows, Codex refuse alors aussi les
//   commandes shell de lecture : l'index du projet et le code prioritaire (budget 400 Ko) sont donc envoyes dans le
//   message, le reste de src/ se lit dans Studio par le MCP. Aucun risque d'ecriture pendant un plan ;
// - implement et fix : ecriture dans le depot (-s workspace-write) avec le sandbox Windows non eleve
//   (windows.sandbox="unelevated" ; verifie le 15/09/2026 : sans cette option, Codex retombe en lecture seule).
//
// Garde-fous calcules par l'outil, jamais declares par GPT : instantane des chemins proteges avant, verification et
// restauration exacte apres (tools/protected-paths.mjs), HEAD et index inchanges, accents abimes introduits
// (tools/text-checks.mjs), fichiers reellement changes compares a ceux que GPT declare, forme de la sortie.
//
// Resultat dans tools/reviews/<horodatage>-gpt-<mode>/ : message.md, sortie.json, garde-fous.json, resume.md.
// Le rapport de restauration est ecrit dans garde-fous.json des la fin de la restauration, avant tout autre calcul,
// puis complete ; une erreur ulterieure (sortie invalide...) le complete au lieu de le faire perdre. La ligne
// « Dossier : <chemin> » est ecrite des que garde-fous.json existe, meme en echec. Aucun arret brutal pendant le
// passage : le verrou Studio (tools/scene/.camera-lock) est toujours libere, et l'instantane n'est supprime qu'une
// fois la restauration confirmee complete ; sinon il est conserve hors depot et son emplacement est indique.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, statSync, unlinkSync, utimesSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

import { changedFiles, git, root, untrackedFiles, workHash } from "./git-state.mjs";
import { appendJournal } from "./journal.mjs";
import { checkAndRestore, disposeSnapshot, takeSnapshot } from "./protected-paths.mjs";
import { introducedMojibake, TEXT_FILE, workingCount } from "./text-checks.mjs";

const schemaPath = join(root, "tools", "gpt-implement.schema.json");
const LOCK = join(root, "tools", "scene", ".camera-lock");
const LOCK_FRESH_MS = 3 * 60 * 1000;
const LOCK_REFRESH_MS = 60 * 1000;
const LOCK_OWNER = "gpt-implement";
// Code envoye a GPT en mode plan (lecture seule) : index de tous les fichiers texte sous ces racines, puis contenu
// complet par ordre de priorite (fichiers de base, prefixes --context, dans cet ordre) dans la limite du budget.
// Tout envoyer ferait 1,5 Mo ; le code de src/ reste lisible en entier dans Studio (Rojo) par get_script_source.
const PLAN_CODE_ROOTS = ["src/", "tools/", "docs/", "default.project.json", "wally.toml"];
const PLAN_CODE_EXCLUDED = "tools/reviews/";
const PLAN_BASE_FILES = ["docs/PLAN.md", "default.project.json", "src/shared/Remotes.luau"];
const PLAN_BUDGET_BYTES = 400 * 1024;
const NUL = String.fromCharCode(0);

// Reserve aux erreurs d'avant le passage (arguments, verrou occupe) : aucune ressource n'est encore prise.
function fail(message) {
  console.error(`[gpt-implement] ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const [mode, request, ...rest] = argv;
  const options = { mode, request, plan: null, issues: null, model: null, effort: "high", context: [] };
  for (let i = 0; i < rest.length; i += 1) {
    const flag = rest[i];
    const value = rest[i + 1];
    if (!value) fail(`valeur manquante pour ${flag}`);
    if (flag === "--plan") options.plan = value;
    else if (flag === "--issues") options.issues = value;
    else if (flag === "--model") options.model = value;
    else if (flag === "--effort") options.effort = value;
    else if (flag === "--context") options.context.push(normalizePath(value));
    else fail(`option inconnue : ${flag}`);
    i += 1;
  }
  if (!["plan", "implement", "fix"].includes(mode)) fail("mode attendu : plan, implement ou fix");
  if (!request) fail("tache manquante");
  if (mode === "implement" && !options.plan) fail("implement demande --plan <plan.md>");
  if (mode === "fix" && !options.issues) fail("fix demande --issues <remarques.json>");
  for (const file of [options.plan, options.issues]) {
    if (file && !existsSync(file)) fail(`fichier introuvable : ${file}`);
  }
  options.model = options.model || process.env.GPT_IMPLEMENT_MODEL || "gpt-6-astra";
  return options;
}

const sha256 = (buffer) => createHash("sha256").update(buffer).digest("hex");
const signature = (file) => (existsSync(join(root, file)) ? sha256(readFileSync(join(root, file))) : "absent");
const normalizePath = (path) => String(path).replace(/\\/g, "/").replace(/^\.\//, "");

function acquireLock() {
  if (existsSync(LOCK) && Date.now() - statSync(LOCK).mtimeMs < LOCK_FRESH_MS) {
    fail(`Studio occupé (verrou ${relative(root, LOCK)} de moins de 3 min) : réessayer plus tard`);
  }
  writeFileSync(LOCK, `${LOCK_OWNER} ${new Date().toISOString()}\n`);
}

function releaseLock() {
  try {
    if (existsSync(LOCK) && readFileSync(LOCK, "utf8").startsWith(LOCK_OWNER)) unlinkSync(LOCK);
  } catch {
    // verrou deja retire : rien a faire
  }
}

// Codex s'installe en .cmd sous Windows : shell, commande en une seule chaine ; message par l'entree standard.
// Le verrou Studio est rafraichi pendant le passage pour ne pas paraitre abandonne.
function runCodex(args, input) {
  return new Promise((resolve) => {
    const quote = (arg) => (/[\s"&|<>^]/.test(arg) ? `"${arg.replace(/"/g, '""')}"` : arg);
    const stdio = ["pipe", "inherit", "inherit"];
    const child =
      process.platform === "win32"
        ? spawn(["codex", ...args.map(quote)].join(" "), { cwd: root, shell: true, stdio })
        : spawn("codex", args, { cwd: root, stdio });
    const refresh = setInterval(() => {
      try {
        const now = new Date();
        utimesSync(LOCK, now, now);
      } catch {
        // verrou retire par ailleurs : il sera verifie a la liberation
      }
    }, LOCK_REFRESH_MS);
    // Codex introuvable ou arrete tot : l'ecriture du message peut echouer (EPIPE). L'erreur est gardee et rendue a la
    // fermeture du processus, pour que main passe quand meme par ses garde-fous et son finally.
    let stdinError = null;
    child.stdin.on("error", (error) => {
      stdinError = error.message;
    });
    child.on("error", (error) => {
      clearInterval(refresh);
      resolve({ status: -1, error: error.message });
    });
    child.on("close", (code) => {
      clearInterval(refresh);
      if (stdinError) resolve({ status: code === 0 ? -1 : code, error: `envoi du message interrompu : ${stdinError}` });
      else resolve({ status: code });
    });
    child.stdin.end(input);
  });
}

// Code du projet pour le plan : fichiers texte suivis ou nouveaux (non ignores) sous PLAN_CODE_ROOTS.
function projectCode(contextPrefixes) {
  const tracked = git(["ls-files", "-z"]).split(NUL).filter(Boolean);
  const files = [...new Set([...tracked, ...untrackedFiles()])]
    .filter((file) => PLAN_CODE_ROOTS.some((prefix) => file === prefix || file.startsWith(prefix)))
    .filter((file) => !file.startsWith(PLAN_CODE_EXCLUDED) && TEXT_FILE.test(file) && existsSync(join(root, file)))
    .sort();
  const sizes = new Map(files.map((file) => [file, statSync(join(root, file)).size]));
  const wanted = [
    ...PLAN_BASE_FILES.filter((file) => sizes.has(file)),
    ...contextPrefixes.flatMap((prefix) => files.filter((file) => file === prefix || file.startsWith(prefix))),
  ];
  const included = [];
  let used = 0;
  for (const file of new Set(wanted)) {
    if (used + sizes.get(file) > PLAN_BUDGET_BYTES) continue;
    included.push(file);
    used += sizes.get(file);
  }
  const index = files
    .map((file) => `${included.includes(file) ? "[inclus] " : "         "}${file} (${Math.ceil(sizes.get(file) / 1024)} Ko)`)
    .join("\n");
  const contents = included.map((file) => `--- ${file} ---\n${readFileSync(join(root, file), "utf8")}`).join("\n\n");
  return { index, contents, count: included.length, bytes: used };
}

const MODE_TEXT = {
  plan: `PLAN : ecris le plan d'architecture de la tache (fichiers, services, remotes, sauvegarde, risques, tests prevus),
en t'appuyant sur la section « CODE DU PROJET » et, si utile, sur Studio. Rends le plan complet en markdown dans
« resume » ; « fichiers_modifies » et « reponses » sont vides.`,
  implement: `IMPLEMENTATION : implemente la tache selon la section « PLAN RETENU ». S'il y a une section « REMARQUES
OUVERTES », prends-les en compte et reponds a chacune dans « reponses » (acceptee et prise en compte, ou rejetee avec
la raison verifiee).`,
  fix: `CORRECTIONS : la section « REMARQUES OUVERTES » contient les remarques du relecteur et de l'arbitre. Pour chacune,
une entree dans « reponses » avec son identifiant exact : acceptee (et corrigee dans le code) ou rejetee (avec la
raison verifiee). Ne modifie que ce qui est necessaire.`,
};

function buildMessage(options, sections) {
  // Exemple d'accent abime construit a l'execution (String.fromCharCode) : ce fichier source ne contient lui-meme
  // aucune sequence abimee, sinon l'arbitre la signalerait.
  const mojibakeExample = `${String.fromCharCode(0xe9)} devient ${String.fromCharCode(0xc3, 0xa9)}`;
  const intro = `Tu es « GPT, implementeur » du jeu Roblox « CHUT ! Vole le Géant », a egalite avec Claude qui relira ton
travail. La constitution commune AGENTS.md ci-dessous s'applique entierement. Reponds par le JSON demande, en francais.`;
  const readOnlyRules = `Tu es en LECTURE SEULE : aucune modification n'est possible, et sous Windows la politique d'execution
refuse aussi les commandes shell. La section « INDEX DU PROJET » liste tous les fichiers texte ; ceux marques [inclus]
sont dans « CODE DU PROJET ». Le code de src/ est synchronise dans Roblox Studio par Rojo : lis les autres scripts par
le serveur MCP « roblox-studio » (grep_scripts, get_script_source). Studio : inspection seulement, jamais
set_script_source, edit_script_lines ni autre modification, jamais de publication ; arrete tout playtest que tu
lances. Si un fichier hors src/ non inclus te manque, dis-le dans le plan au lieu de supposer son contenu.`;
  const writeRules = `Tu travailles directement dans le depot (ecriture autorisee dans le dossier du depot seulement).
- Lis les fichiers avec ton outil de lecture ou \`Get-Content -Encoding utf8\` : sans -Encoding utf8, PowerShell abime
  les accents (${mojibakeExample}) et tu les recopierais casses.
- Ecris uniquement avec ton outil de modification de fichiers, jamais par redirection du shell (>, Set-Content,
  Out-File), jamais avec sed -i ni perl -pi (Rojo plante sur leurs fichiers temporaires).
- Aucun commit, aucun git add, aucun changement de branche, aucun push.
- Ne touche jamais : .env*, .git/, *.rbxl*, assets/models|concepts|textures/, docs/captures|videos/, tools/reviews/.
  Toute modification y sera annulee et signalee comme bloquante.
- Studio (serveur MCP « roblox-studio ») : inspecter et tester oui ; jamais publier, ni supprimer ou modifier
  d'instance dans le place. Arrete tout playtest que tu lances.
- Apres tes modifications, lance \`lune run check\` si tu le peux et corrige ce qu'il signale ; dans « verifications »,
  indique seulement ce que tu as reellement lance et le resultat.
- « fichiers_modifies » : liste exacte des fichiers modifies ou crees ; l'outil la comparera a l'etat reel.`;
  const header = `${intro}\n\n${options.mode === "plan" ? readOnlyRules : writeRules}\n\n${MODE_TEXT[options.mode]}`;
  const body = sections.map(([title, content]) => `\n===== ${title} =====\n${content}`).join("\n");
  return `${header}\n${body}\n`;
}

function emptyGuards() {
  return {
    head_modifie: false,
    index_modifie: false,
    chemins_restaures: [],
    fichiers_crees_supprimes: [],
    copies_alterees: [],
    gros_fichiers_modifies: [],
    accents_abimes: [],
    modifications_en_mode_plan: [],
    fichiers_reels: [],
    declares_non_modifies: [],
    modifies_non_declares: [],
    empreinte_avant: null,
    empreinte_apres: null,
    erreur_garde_fous: null,
    sortie_invalide: null,
    instantane_conserve: null,
  };
}

const EMPTY_OUTPUT = { resume: "", fichiers_modifies: [], verifications: [], reste_a_faire: [], reponses: [] };

// Sortie de GPT verifiee champ par champ : une sortie de mauvaise forme ne doit jamais faire planter l'outil.
function readOutput(file) {
  if (!existsSync(file)) return { result: EMPTY_OUTPUT, invalid: "sortie absente" };
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    return { result: EMPTY_OUTPUT, invalid: `JSON illisible (${error.message})` };
  }
  const problems = [];
  const stringList = (key) => Array.isArray(parsed?.[key]) && parsed[key].every((value) => typeof value === "string");
  if (typeof parsed?.resume !== "string") problems.push("resume");
  for (const key of ["fichiers_modifies", "verifications", "reste_a_faire"]) {
    if (!stringList(key)) problems.push(key);
  }
  const answersValid =
    Array.isArray(parsed?.reponses) &&
    parsed.reponses.every(
      (answer) =>
        typeof answer?.id === "string" &&
        ["acceptee", "rejetee"].includes(answer?.decision) &&
        typeof answer?.explication === "string",
    );
  if (!answersValid) problems.push("reponses");
  if (problems.length > 0) return { result: EMPTY_OUTPUT, invalid: `champs invalides : ${problems.join(", ")}` };
  return { result: parsed, invalid: null };
}

function summarize(output, guards, model, mode) {
  const lines = [`GPT (${model}) — ${mode} : ${mode === "plan" ? "plan rendu" : "passage terminé"}`];
  lines.push(mode === "plan" ? `Plan : ${output.resume.split("\n").find(Boolean) ?? ""}` : output.resume);
  if (mode !== "plan") {
    lines.push(`Fichiers réellement changés : ${guards.fichiers_reels.join(", ") || "aucun"}`);
    lines.push(`Vérifications déclarées : ${output.verifications.join(" | ") || "aucune"}`);
  }
  if (output.reponses.length > 0) {
    lines.push(`Réponses : ${output.reponses.map((r) => `${r.id} ${r.decision}`).join(", ")}`);
  }
  const alerts = [
    guards.head_modifie && "HEAD modifié",
    guards.index_modifie && "index Git modifié",
    guards.copies_alterees.length && `copies altérées : ${guards.copies_alterees.join(", ")}`,
    guards.chemins_restaures.length && `chemins protégés restaurés : ${guards.chemins_restaures.join(", ")}`,
    guards.fichiers_crees_supprimes.length && `fichiers créés supprimés : ${guards.fichiers_crees_supprimes.join(", ")}`,
    guards.gros_fichiers_modifies.length && `assets locaux touchés : ${guards.gros_fichiers_modifies.length}`,
    guards.accents_abimes.length && `accents abîmés : ${guards.accents_abimes.map((m) => m.fichier).join(", ")}`,
    guards.modifications_en_mode_plan.length && `modifications en mode plan : ${guards.modifications_en_mode_plan.join(", ")}`,
    guards.modifies_non_declares.length && `non déclarés : ${guards.modifies_non_declares.join(", ")}`,
    guards.sortie_invalide && `sortie invalide : ${guards.sortie_invalide}`,
    guards.instantane_conserve && `instantané conservé : ${guards.instantane_conserve}`,
  ].filter(Boolean);
  lines.push(alerts.length > 0 ? `GARDE-FOUS : ${alerts.join(" ; ")}` : "Garde-fous : aucun écart");
  return lines.join("\n");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const folder = join(root, "tools", "reviews", `${stamp}-gpt-${options.mode}`);
  const guardsFile = join(folder, "garde-fous.json");
  const writeGuards = (guards) => writeFileSync(guardsFile, `${JSON.stringify(guards, null, 2)}\n`);
  mkdirSync(folder, { recursive: true });

  acquireLock();
  let snapshot = null;
  let keepSnapshot = false;
  let failure = null;
  try {
    // Etat avant le passage : fichiers deja changes (contenu et accents abimes), instantane protege, empreinte.
    const dirtyBefore = changedFiles();
    const signaturesBefore = new Map(dirtyBefore.map((file) => [file, signature(file)]));
    const mojibakeBefore = new Map(dirtyBefore.filter((f) => TEXT_FILE.test(f)).map((f) => [f, workingCount(f)]));
    snapshot = takeSnapshot();
    const hashBefore = workHash();

    const agents = existsSync(join(root, "AGENTS.md")) ? readFileSync(join(root, "AGENTS.md"), "utf8") : "(absent)";
    const sections = [
      ["AGENTS.md", agents],
      ["TACHE", options.request],
      ["FICHIERS DEJA CHANGES AVANT TON PASSAGE", dirtyBefore.join("\n") || "(aucun)"],
    ];
    if (options.mode === "plan") {
      const code = projectCode(options.context);
      sections.push(["INDEX DU PROJET", code.index]);
      sections.push([`CODE DU PROJET (${code.count} fichiers, ${Math.round(code.bytes / 1024)} Ko)`, code.contents]);
    }
    if (options.plan) sections.push(["PLAN RETENU", readFileSync(options.plan, "utf8")]);
    if (options.issues) sections.push(["REMARQUES OUVERTES", readFileSync(options.issues, "utf8")]);
    const message = buildMessage(options, sections);
    writeFileSync(join(folder, "message.md"), message);

    const output = join(folder, "sortie.json");
    const sandbox =
      options.mode === "plan" ? ["-s", "read-only"] : ["-s", "workspace-write", "-c", 'windows.sandbox="unelevated"'];
    appendJournal(
      "GPT",
      `${options.mode} en cours (${options.model}, effort ${options.effort}, ${sandbox[1]}, code ${hashBefore}, ` +
        `${Math.round(message.length / 1024)} Ko de contexte)...`,
    );
    const run = await runCodex(
      [
        "exec",
        "-m",
        options.model,
        ...sandbox,
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

    // Garde-fous, que Codex ait reussi ou non.
    let report;
    try {
      report = checkAndRestore(snapshot);
    } catch (error) {
      // Restauration interrompue : l'instantane est peut-etre la seule copie des fichiers proteges d'avant.
      keepSnapshot = true;
      writeGuards({
        ...emptyGuards(),
        empreinte_avant: hashBefore,
        erreur_garde_fous: error.message,
        instantane_conserve: snapshot.dir,
      });
      throw new Error(`garde-fous interrompus (${error.message}) ; instantané conservé : ${snapshot.dir}`);
    }
    if (report.tampered.length > 0) keepSnapshot = true;

    // Rapport de restauration ecrit tout de suite, a partir des seules donnees de la restauration.
    const guards = {
      ...emptyGuards(),
      head_modifie: report.headChanged,
      index_modifie: report.indexChanged,
      chemins_restaures: report.restored,
      fichiers_crees_supprimes: report.removed,
      copies_alterees: report.tampered,
      gros_fichiers_modifies: report.largeChanged,
      empreinte_avant: hashBefore,
      instantane_conserve: keepSnapshot ? snapshot.dir : null,
    };
    writeGuards(guards);

    // Complements (fichiers changes, accents, sortie) : une erreur ici complete le rapport au lieu de le perdre.
    let result = EMPTY_OUTPUT;
    try {
      const dirtyAfter = changedFiles();
      const touched = [...new Set([...dirtyAfter, ...signaturesBefore.keys()])].filter(
        (file) => signaturesBefore.get(file) !== signature(file),
      );
      guards.fichiers_reels = touched;
      guards.accents_abimes = introducedMojibake(touched, mojibakeBefore);
      guards.modifications_en_mode_plan = options.mode === "plan" ? touched : [];
      guards.empreinte_apres = workHash();
      const read = readOutput(output);
      result = read.result;
      guards.sortie_invalide = run.status === 0 ? read.invalid : null;
      const declared = result.fichiers_modifies.map(normalizePath);
      guards.declares_non_modifies = declared.filter((file) => !touched.includes(file));
      guards.modifies_non_declares = options.mode === "plan" ? [] : touched.filter((file) => !declared.includes(file));
    } catch (error) {
      guards.erreur_garde_fous = `analyse après restauration interrompue : ${error.message}`;
      writeGuards(guards);
      throw error;
    }
    writeGuards(guards);

    if (run.status !== 0) {
      throw new Error(`codex s'est terminé avec le code ${run.status}${run.error ? ` (${run.error})` : ""}`);
    }
    if (guards.sortie_invalide) throw new Error(`sortie de GPT invalide : ${guards.sortie_invalide}`);

    const summary = summarize(result, guards, options.model, options.mode);
    writeFileSync(join(folder, "resume.md"), `${summary}\n`);
    appendJournal("GPT", summary);
  } catch (error) {
    failure = error.message;
  } finally {
    releaseLock();
    if (snapshot && !keepSnapshot) disposeSnapshot(snapshot);
  }
  // Annonce du dossier des que les garde-fous existent, meme en echec : l'arbitre doit les integrer.
  if (existsSync(guardsFile)) console.log(`Dossier : ${relative(root, folder)}`);
  if (failure) {
    appendJournal("GPT", `${options.mode} en échec : ${failure}`);
    console.error(`[gpt-implement] ${failure}`);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`[gpt-implement] ${error.message}`);
  process.exitCode = 1;
});
