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
    accountGetId(id) { return { user: { id, metadata: (accounts[id] || {}).metadata || {} } }; },
  };
}

const logger = { info() {}, warn() {}, error() {}, debug() {} };

function setup() {
  const mod = loadModule();
  const rpcs = {};
  mod.InitModule({}, logger, {}, { registerRpc: (n, f) => { rpcs[n] = f; } });
  const nk = fakeNakama({ gm1: { metadata: { role: "gm" } } });
  const call = (user, name, payload) => JSON.parse(rpcs[name]({ userId: user }, logger, nk, payload ? JSON.stringify(payload) : ""));
  return { rpcs, nk, call };
}

test("enregistre les RPC attendues", () => {
  const { rpcs } = setup();
  assert.deepStrictEqual(Object.keys(rpcs).sort(), ["bastion_placer", "bastion_retirer", "butin_monstre", "gm_donner", "profil_lire", "raid_lancer", "sante"]);
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
  assert.strictEqual(call("p1", "gm_donner", { joueur: "p1", ressources: { or: 500 }, motif: "x" }).error, "acces_refuse");
  assert.strictEqual(call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 500 } }).error, "motif_obligatoire");
  assert.ok(call("gm1", "gm_donner", { joueur: "p1", ressources: { or: -5 }, motif: "x" }).error);
  assert.ok(call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 1e9 }, motif: "x" }).error);
  const ok = call("gm1", "gm_donner", { joueur: "p1", ressources: { or: 500 }, motif: "compensation panne" });
  assert.strictEqual(ok.ok, true);
  assert.strictEqual(ok.profil.resources.or, 600);
});

test("non connecté : refusé", () => {
  const { rpcs, nk } = setup();
  assert.throws(() => rpcs.profil_lire({}, logger, nk, ""), /non_connecte/);
});

test("requête mal formée : refusée", () => {
  const { rpcs, nk } = setup();
  assert.throws(() => rpcs.bastion_placer({ userId: "p1" }, logger, nk, "{oops"), /requete_invalide/);
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
