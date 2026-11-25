// Tests du module serveur : on charge build/index.js comme le ferait Nakama,
// avec un faux runtime en mémoire (stockage versionné, comptes, journal).
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

function loadModule() {
  const code = fs.readFileSync(path.join(__dirname, "..", "build", "index.js"), "utf8");
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  return sandbox;
}

function fakeNakama(accounts) {
  const store = {};
  let counter = 0;
  return {
    store,
    storageRead(reqs) {
      return reqs.map((r) => store[r.userId + "/" + r.collection + "/" + r.key]).filter(Boolean)
        .map((o) => ({ value: JSON.parse(JSON.stringify(o.value)), version: o.version }));
    },
    storageWrite(writes) {
      for (const w of writes) {
        const k = w.userId + "/" + w.collection + "/" + w.key;
        const cur = store[k];
        if (w.version === "*" && cur) throw new Error("version conflict");
        if (w.version && w.version !== "*" && (!cur || cur.version !== w.version)) throw new Error("version conflict");
        store[k] = { value: JSON.parse(JSON.stringify(w.value)), version: "v" + ++counter };
      }
    },
    accountGetId(id) { return { user: { userId: id, username: (accounts[id] || {}).username || id, metadata: (accounts[id] || {}).metadata || {} } }; },
    usersGetId(ids) { return ids.filter((i) => accounts[i]).map((i) => this.accountGetId(i).user); },
    usersGetUsername(names) { return Object.keys(accounts).filter((i) => names.includes(accounts[i].username)).map((i) => this.accountGetId(i).user); },
  };
}

const logger = { info() {}, warn() {}, error() {}, debug() {} };

function setup() {
  const mod = loadModule();
  const rpcs = {};
  // Comme Nakama : la fonction enregistrée doit être une déclaration globale, pas une fonction fabriquée.
  const globals = new Set(Object.values(mod).filter((v) => typeof v === "function"));
  mod.InitModule({}, logger, {}, { registerRpc: (n, f) => {
    if (!globals.has(f)) throw new Error("RPC " + n + " : fonction non globale, refusée par Nakama");
    rpcs[n] = f;
  } });
  const nk = fakeNakama({ gm1: { username: "richard", metadata: { role: "gm" } }, p1: { username: "joueur1" }, p2: { username: "joueur2" } });
  const call = (user, name, payload) => JSON.parse(rpcs[name]({ userId: user }, logger, nk, payload ? JSON.stringify(payload) : ""));
  return { rpcs, nk, call };
}

test("enregistre les RPC attendues", () => {
  const { rpcs } = setup();
  assert.deepStrictEqual(Object.keys(rpcs).sort(), ["bastion_placer", "bastion_retirer", "butin_monstre", "evenements_actifs", "gm_donner", "gm_evenement_sauver", "gm_evenement_supprimer", "gm_evenements", "gm_joueur", "gm_journal", "gm_moi", "profil_lire", "raid_lancer", "sante"]);
});

test("nouveau joueur : ressources de départ", () => {
  const { call } = setup();
  const r = call("p1", "profil_lire");
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.profil.resources.or, 100);
  assert.deepStrictEqual(r.profil.bastion, []);
});

test("placer une tour débite le coût, retirer rembourse 50 %", () => {
  const { call } = setup();
  call("p1", "profil_lire");
  const p = call("p1", "bastion_placer", { id: "tour", x: 2, y: 2 });
  assert.strictEqual(p.ok, true);
  assert.strictEqual(p.profil.resources.or, 60);
  assert.strictEqual(p.profil.resources.bois, 40);
  const r = call("p1", "bastion_retirer", { x: 2, y: 2 });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.profil.resources.or, 80);
  assert.strictEqual(r.profil.bastion.length, 0);
});

test("refus : case interdite, case occupée, bâtiment inconnu, pas assez d'or", () => {
  const { call } = setup();
  assert.strictEqual(call("p1", "bastion_placer", { id: "tour", x: 0, y: 3 }).error, "case_interdite");
  assert.strictEqual(call("p1", "bastion_placer", { id: "tour", x: 5, y: 5 }).error, "case_interdite");
  assert.strictEqual(call("p1", "bastion_placer", { id: "dragon", x: 2, y: 2 }).error, "batiment_inconnu");
  call("p1", "bastion_placer", { id: "tour", x: 2, y: 2 });
  assert.strictEqual(call("p1", "bastion_placer", { id: "mur", x: 2, y: 2 }).error, "case_interdite");
  call("p1", "bastion_placer", { id: "tour", x: 3, y: 2 });
  const third = call("p1", "bastion_placer", { id: "tour", x: 4, y: 2 });
  assert.strictEqual(third.error, "ressources_insuffisantes");
});

test("le joueur ne peut pas modifier la sauvegarde d'un autre", () => {
  const { call } = setup();
  call("p1", "bastion_placer", { id: "tour", x: 2, y: 2 });
  assert.strictEqual(call("p2", "profil_lire").profil.bastion.length, 0);
});

test("gm_donner : réservé aux GM, motif obligatoire, montants bornés", () => {
  const { call } = setup();
  call("p1", "profil_lire");
  assert.strictEqual(call("p1", "gm_donner", { joueur: "p1", ressources: { or: 500 }, motif: "test" }).error, "acces_refuse");
  assert.strictEqual(call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 500 } }).error, "motif_obligatoire");
  assert.ok(call("gm1", "gm_donner", { joueur: "p1", ressources: { or: -5 }, motif: "test" }).error);
  assert.ok(call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 1e9 }, motif: "test" }).error);
  const ok = call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 500 }, motif: "compensation panne" });
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(ok.profil.resources.or, 600);
});

test("non connecté : refusé", () => {
  const { rpcs, nk } = setup();
  assert.strictEqual(JSON.parse(rpcs.profil_lire({}, logger, nk, "")).error, "non_connecte");
});

test("requête mal formée : refusée", () => {
  const { rpcs, nk } = setup();
  assert.strictEqual(JSON.parse(rpcs.bastion_placer({ userId: "p1" }, logger, nk, "{oops")).error, "requete_invalide");
});

test("raid_lancer : le serveur décide et applique butin ou pillage", () => {
  const { call } = setup();
  call("p1", "profil_lire");
  const r = call("p1", "raid_lancer", { raid: "raid_1" });
  assert.strictEqual(r.ok, true);
  assert.ok(r.graine > 0);
  assert.strictEqual(r.victoire, false); // bastion vide : le cœur tombe
  assert.strictEqual(r.profil.resources.or, 80);
  assert.strictEqual(r.perte.or, 20);
  assert.strictEqual(call("p1", "raid_lancer", { raid: "x" }).error, "raid_inconnu");
});

test("butin_monstre : gain borné, historique de chasse non exposé", () => {
  const { call } = setup();
  const r = call("p1", "butin_monstre", { monstre: "diablotin" });
  assert.ok(r.ok && r.or >= 3 && r.or <= 6);
  assert.strictEqual(r.profil.resources.or, 100 + r.or);
  assert.strictEqual(r.profil.chasse, undefined);
});


test("gm : recherche de joueur, don journalisé, joueur inconnu refusé", () => {
  const { call } = setup();
  assert.strictEqual(call("gm1", "gm_moi").gm.role, "gm");
  const found = call("gm1", "gm_joueur", { recherche: "joueur1" });
  assert.strictEqual(found.joueur.id, "p1");
  assert.strictEqual(found.profil.resources.or, 100);
  assert.strictEqual(call("gm1", "gm_joueur", { recherche: "personne" }).error, "joueur_introuvable");
  assert.strictEqual(call("gm1", "gm_donner", { joueur: "fantome", ressources: { or: 5 }, motif: "test" }).error, "joueur_introuvable");
  call("gm1", "gm_donner", { joueur: "p1", ressources: { bois: 50 }, motif: "compensation" });
  const j = call("gm1", "gm_journal");
  assert.strictEqual(j.entrees[0].action, "don");
  assert.strictEqual(j.entrees[0].gm, "richard");
  assert.strictEqual(call("p1", "gm_journal").error, "acces_refuse");
});

test("événements : création validée, bonus appliqué au butin, suppression", () => {
  const { call } = setup();
  const now = Date.now();
  const bad = call("gm1", "gm_evenement_sauver", { evenement: { nom: "x", type: "bonus_or_chasse", multiplicateur: 50, debut: now, fin: now + 1000 } });
  assert.strictEqual(bad.error, "multiplicateur_invalide");
  assert.strictEqual(call("gm1", "gm_evenement_sauver", { evenement: { nom: "x", type: "pluie", multiplicateur: 2, debut: now, fin: now + 1 } }).error, "type_inconnu");
  const ok = call("gm1", "gm_evenement_sauver", { evenement: { nom: "Week-end de l'or", type: "bonus_or_chasse", multiplicateur: 2, debut: now - 1000, fin: now + 3600000 } });
  assert.strictEqual(ok.ok, true);
  const actifs = call("p1", "evenements_actifs");
  assert.strictEqual(actifs.evenements.length, 1);
  assert.strictEqual(actifs.evenements[0].nom, "Week-end de l'or");
  const loot = call("p1", "butin_monstre", { monstre: "gardien" });
  assert.ok(loot.or >= 240 && loot.or <= 320, "or doublé : " + loot.or);
  const edit = call("gm1", "gm_evenement_sauver", { evenement: { ...ok.evenement, multiplicateur: 3 } });
  assert.strictEqual(edit.evenements.length, 1);
  assert.strictEqual(edit.evenements[0].multiplicateur, 3);
  assert.strictEqual(call("gm1", "gm_evenement_sauver", { evenement: { ...ok.evenement, id: "inconnu" } }).error, "evenement_introuvable");
  call("gm1", "gm_evenement_supprimer", { id: ok.evenement.id });
  assert.strictEqual(call("p1", "evenements_actifs").evenements.length, 0);
  const actions = call("gm1", "gm_journal").entrees.map((e) => e.action);
  assert.deepStrictEqual(actions, ["evenement_supprime", "evenement_modifie", "evenement_cree"]);
});

test("événement de butin de raid : multiplie le butin de victoire", () => {
  const { call, rpcs, nk } = setup();
  const now = Date.now();
  call("gm1", "gm_evenement_sauver", { evenement: { nom: "Raid généreux", type: "bonus_butin_raid", multiplicateur: 2, debut: now - 1, fin: now + 60000 } });
  call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 2000, bois: 2000, pierre: 2000 }, motif: "test raid" });
  for (let i = 2; i <= 9; i++) for (const y of [2, 9]) call("p1", "bastion_placer", { id: "tour", x: i, y });
  let r;
  for (let n = 0; n < 5; n++) { r = call("p1", "raid_lancer", { raid: "raid_1" }); if (r.victoire) break; }
  assert.strictEqual(r.victoire, true);
  assert.deepStrictEqual({ ...r.butin }, { or: 120, bois: 60, pierre: 60 });
});

test("erreur interne : code générique, sans trace", () => {
  const { rpcs } = setup();
  const broken = { storageRead() { throw new Error("TypeError: boom at index.js:12"); } };
  assert.strictEqual(JSON.parse(rpcs.profil_lire({ userId: "p1" }, logger, broken, "")).error, "erreur_serveur");
});
