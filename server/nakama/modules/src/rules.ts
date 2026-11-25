// Règles du jeu côté serveur. Fonctions pures : testables sans Nakama.
// Elles reprennent exactement les règles du client (client/src/gameplay/wallet.gd, client/src/bastion/bastion_grid.gd).

interface BuildingDef { name: string; cost: { [res: string]: number }; hp: number; damage: number; range: number; fire_interval: number; blocks: boolean; }
interface Resources { [res: string]: number; }
interface PlacedBuilding { id: string; x: number; y: number; }
interface PlayerState { resources: Resources; bastion: PlacedBuilding[]; }

const GRID_SIZE = 12;
const REFUND_RATIO = 0.5;
const DEFAULT_RESOURCES: Resources = { or: 100, bois: 60, pierre: 60, fer: 0, essence: 0 };
const GM_MAX_GRANT = 100000;

function newPlayerState(): PlayerState {
  const resources: Resources = {};
  for (const k in DEFAULT_RESOURCES) resources[k] = DEFAULT_RESOURCES[k];
  return { resources: resources, bastion: [] };
}

function canAfford(resources: Resources, cost: Resources): boolean {
  for (const k in cost) {
    if ((resources[k] || 0) < cost[k]) return false;
  }
  return true;
}

// Tout ou rien : renvoie de nouvelles ressources, ou null si la dépense est impossible.
function spend(resources: Resources, cost: Resources): Resources | null {
  if (!canAfford(resources, cost)) return null;
  const next: Resources = {};
  for (const k in resources) next[k] = resources[k];
  for (const k in cost) next[k] = (next[k] || 0) - cost[k];
  return next;
}

function addResources(resources: Resources, gain: Resources): Resources {
  const next: Resources = {};
  for (const k in resources) next[k] = resources[k];
  for (const k in gain) {
    const v = Math.floor(gain[k]);
    if (!(v >= 0)) throw new Error("montant invalide pour " + k);
    next[k] = (next[k] || 0) + v;
  }
  return next;
}

function coreCells(): number[][] {
  const c = Math.floor(GRID_SIZE / 2);
  return [[c - 1, c - 1], [c, c - 1], [c - 1, c], [c, c]];
}

function isCore(x: number, y: number): boolean {
  const cells = coreCells();
  for (let i = 0; i < cells.length; i++) if (cells[i][0] === x && cells[i][1] === y) return true;
  return false;
}

function canPlace(bastion: PlacedBuilding[], x: number, y: number): boolean {
  if (Math.floor(x) !== x || Math.floor(y) !== y) return false;
  if (x <= 0 || y <= 0 || x >= GRID_SIZE - 1 || y >= GRID_SIZE - 1) return false;
  if (isCore(x, y)) return false;
  for (let i = 0; i < bastion.length; i++) if (bastion[i].x === x && bastion[i].y === y) return false;
  return true;
}

type Result = { ok: true; state: PlayerState } | { ok: false; error: string };

function placeBuilding(state: PlayerState, defs: { [id: string]: BuildingDef }, id: string, x: number, y: number): Result {
  const def = defs[id];
  if (!def) return { ok: false, error: "batiment_inconnu" };
  if (!canPlace(state.bastion, x, y)) return { ok: false, error: "case_interdite" };
  const resources = spend(state.resources, def.cost);
  if (!resources) return { ok: false, error: "ressources_insuffisantes" };
  return { ok: true, state: { resources: resources, bastion: state.bastion.concat([{ id: id, x: x, y: y }]) } };
}

function removeBuilding(state: PlayerState, defs: { [id: string]: BuildingDef }, x: number, y: number): Result {
  let found = -1;
  for (let i = 0; i < state.bastion.length; i++) if (state.bastion[i].x === x && state.bastion[i].y === y) found = i;
  if (found < 0) return { ok: false, error: "aucun_batiment" };
  const removed = state.bastion[found];
  const cost = (defs[removed.id] || { cost: {} }).cost;
  const refund: Resources = {};
  for (const k in cost) refund[k] = Math.floor(cost[k] * REFUND_RATIO);
  const bastion = state.bastion.filter(function (_b, i) { return i !== found; });
  return { ok: true, state: { resources: addResources(state.resources, refund), bastion: bastion } };
}

function validateGrant(gain: Resources): string | null {
  for (const k in gain) {
    if (typeof gain[k] !== "number" || gain[k] < 0 || gain[k] > GM_MAX_GRANT) return "montant_invalide";
  }
  return null;
}
