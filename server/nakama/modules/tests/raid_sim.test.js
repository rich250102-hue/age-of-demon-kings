// Le serveur doit simuler exactement comme le client (client/tests/test_bastion.gd).
// Les valeurs de référence ci-dessous sont les mêmes des deux côtés.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "build", "index.js"), "utf8") +
  "\nthis.DetRng = DetRng; this.simulateRaid = simulateRaid; this.RAIDS = RAIDS; this.BUILDINGS = BUILDINGS; this.lootMonster = lootMonster; this.MONSTERS = MONSTERS; this.loseRatio = loseRatio;", sandbox);
const S = sandbox;

const towers = (cells) => cells.map(([x, y]) => ({ id: "tour", x, y }));
const SMALL = towers([[3, 3], [8, 3], [3, 8], [8, 8]]).concat([{ id: "mur", x: 5, y: 3 }, { id: "piege", x: 6, y: 8 }]);
const RING = [];
for (let i = 2; i <= 9; i++) for (const [x, y] of [[i, 2], [i, 9]]) RING.push({ id: "tour", x, y });

test("xorshift32 : mêmes valeurs que le client", () => {
  const r = new S.DetRng(42);
  assert.deepStrictEqual([r.nextU32(), r.nextU32(), r.nextU32()], [11355432, 2836018348, 476557059]);
});

test("raid de référence (petit bastion, graine 1234) identique au client", () => {
  const r = S.simulateRaid(SMALL, S.RAIDS.raid_1, S.BUILDINGS, 1234);
  assert.deepStrictEqual({ ...r }, { finished: true, victory: false, ticks: 83, core_hp: 0, structures_left: 5 });
});

test("raid de référence (anneau de 16 tours, graine 7) identique au client", () => {
  const r = S.simulateRaid(RING, S.RAIDS.raid_1, S.BUILDINGS, 7);
  console.log("anneau:", JSON.stringify(r));
  assert.strictEqual(r.victory, true);
});

test("raid déterministe", () => {
  const a = S.simulateRaid(SMALL, S.RAIDS.raid_1, S.BUILDINGS, 99);
  const b = S.simulateRaid(SMALL, S.RAIDS.raid_1, S.BUILDINGS, 99);
  assert.deepStrictEqual({ ...a }, { ...b });
});

test("bâtiments invalides ignorés (bord, cœur, doublon, inconnu)", () => {
  const junk = [{ id: "tour", x: 0, y: 0 }, { id: "tour", x: 5, y: 5 }, { id: "dragon", x: 2, y: 2 }];
  const a = S.simulateRaid(junk, S.RAIDS.raid_1, S.BUILDINGS, 5);
  const b = S.simulateRaid([], S.RAIDS.raid_1, S.BUILDINGS, 5);
  assert.deepStrictEqual({ ...a }, { ...b });
});

test("butin plafonné par minute et tiré dans la fourchette", () => {
  let state = { resources: { or: 0 }, bastion: [] };
  const t0 = 1_000_000;
  const r1 = S.lootMonster(state, S.MONSTERS, "gardien", t0, 0.5);
  assert.ok(r1.ok && r1.gold >= 120 && r1.gold <= 160);
  const r2 = S.lootMonster(r1.state, S.MONSTERS, "gardien", t0 + 1000, 0.5);
  assert.strictEqual(r2.error, "butin_trop_rapide");
  const r3 = S.lootMonster(r1.state, S.MONSTERS, "gardien", t0 + 61000, 0.99999);
  assert.ok(r3.ok && r3.gold === 160);
  assert.strictEqual(S.lootMonster(state, S.MONSTERS, "dragon", t0, 0.5).error, "monstre_inconnu");
});

test("pillage : au plus le ratio, arrondi vers le bas", () => {
  const r = S.loseRatio({ or: 101, bois: 4, pierre: 0 }, 0.2);
  assert.deepStrictEqual({ ...r.resources }, { or: 81, bois: 4, pierre: 0 });
  assert.deepStrictEqual({ ...r.lost }, { or: 20 });
});
