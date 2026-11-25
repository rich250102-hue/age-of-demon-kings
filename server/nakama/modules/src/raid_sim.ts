// Portage exact de client/src/bastion/raid_sim.gd : même bastion + même graine = même résultat.
// Le serveur s'en sert pour décider de l'issue d'un raid ; le client rejoue la même graine pour l'afficher.

interface RaidWave { tick: number; count: number; hp: number; damage: number; speed_ticks: number; }
interface RaidDef { name: string; core_hp: number; waves: RaidWave[]; loot_on_win: Resources; max_loss_ratio: number; }
interface RaidResult { finished: boolean; victory: boolean; ticks: number; core_hp: number; structures_left: number; }

const RAID_MAX_TICKS = 3000;
const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]];

function simulateRaid(bastion: PlacedBuilding[], raid: RaidDef, defs: { [id: string]: BuildingDef }, seed: number): RaidResult {
  const size = GRID_SIZE;
  const key = function (x: number, y: number): number { return y * size + x; };
  const inBounds = function (x: number, y: number): boolean { return x >= 0 && y >= 0 && x < size && y < size; };
  const rng = new DetRng(seed);

  // Mêmes règles de placement que BastionGrid.from_layout : on ignore ce qui serait invalide.
  const structures: { [k: number]: { id: string; hp: number; cooldown: number; x: number; y: number } } = {};
  const sorted = bastion.slice().sort(function (a, b) { return key(a.x, a.y) - key(b.x, b.y); });
  const placed: PlacedBuilding[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const b = sorted[i];
    if (!defs[b.id] || !canPlace(placed, b.x, b.y)) continue;
    placed.push(b);
    structures[key(b.x, b.y)] = { id: b.id, hp: defs[b.id].hp, cooldown: 0, x: b.x, y: b.y };
  }

  // Champ de distance (BFS) jusqu'au cœur.
  const dist: { [k: number]: number } = {};
  const queue: number[][] = [];
  const core = coreCells();
  for (let i = 0; i < core.length; i++) { dist[key(core[i][0], core[i][1])] = 0; queue.push(core[i]); }
  while (queue.length > 0) {
    const cur = queue.shift() as number[];
    for (let d = 0; d < DIRS.length; d++) {
      const nx = cur[0] + DIRS[d][0], ny = cur[1] + DIRS[d][1];
      if (inBounds(nx, ny) && dist[key(nx, ny)] === undefined) { dist[key(nx, ny)] = dist[key(cur[0], cur[1])] + 1; queue.push([nx, ny]); }
    }
  }
  const distAt = function (x: number, y: number): number { const v = dist[key(x, y)]; return v === undefined ? 99 : v; };

  interface Enemy { id: number; x: number; y: number; hp: number; damage: number; speed: number; timer: number; alive: boolean; }
  let enemies: Enemy[] = [];
  let tick = 0, coreHp = raid.core_hp, wavesSpawned = 0, nextId = 1, finished = false, victory = false;

  const edgeCell = function (): number[] {
    const side = rng.rangeInt(0, 3);
    const pos = rng.rangeInt(0, size - 1);
    if (side === 0) return [pos, 0];
    if (side === 1) return [pos, size - 1];
    if (side === 2) return [0, pos];
    return [size - 1, pos];
  };
  const hit = function (e: Enemy, dmg: number): void {
    e.hp -= dmg;
    if (e.hp <= 0 && e.alive) e.alive = false;
  };
  const structureKeys = function (): number[] {
    const ks: number[] = [];
    for (const k in structures) ks.push(Number(k));
    return ks.sort(function (a, b) { return a - b; });
  };

  while (!finished) {
    // Vagues
    while (wavesSpawned < raid.waves.length && raid.waves[wavesSpawned].tick <= tick) {
      const w = raid.waves[wavesSpawned];
      for (let i = 0; i < w.count; i++) {
        const c = edgeCell();
        enemies.push({ id: nextId++, x: c[0], y: c[1], hp: w.hp, damage: w.damage, speed: Math.max(1, w.speed_ticks), timer: 0, alive: true });
      }
      wavesSpawned++;
    }
    // Tours
    const ks = structureKeys();
    for (let i = 0; i < ks.length; i++) {
      const s = structures[ks[i]];
      if (!s) continue;
      const def = defs[s.id];
      if (def.fire_interval <= 0 || def.damage <= 0) continue;
      s.cooldown = Math.max(0, s.cooldown - 1);
      if (s.cooldown > 0) continue;
      const range2 = def.range * def.range;
      let best: Enemy | null = null, bestD2 = -1;
      for (let j = 0; j < enemies.length; j++) {
        const e = enemies[j];
        if (!e.alive) continue;
        const dx = e.x - s.x, dy = e.y - s.y, d2 = dx * dx + dy * dy;
        if (d2 <= range2 && (bestD2 < 0 || d2 < bestD2 || (d2 === bestD2 && best !== null && e.id < best.id))) { best = e; bestD2 = d2; }
      }
      if (!best) continue;
      hit(best, def.damage);
      s.cooldown = def.fire_interval;
    }
    // Démons
    for (let j = 0; j < enemies.length; j++) {
      const e = enemies[j];
      if (!e.alive) continue;
      if (distAt(e.x, e.y) <= 1) { coreHp -= e.damage; continue; }
      let bx = e.x, by = e.y, bd = distAt(e.x, e.y);
      for (let d = 0; d < DIRS.length; d++) {
        const nx = e.x + DIRS[d][0], ny = e.y + DIRS[d][1];
        if (inBounds(nx, ny) && distAt(nx, ny) < bd) { bx = nx; by = ny; bd = distAt(nx, ny); }
      }
      const nk = key(bx, by);
      const blocking = structures[nk];
      if (blocking && defs[blocking.id].blocks) {
        blocking.hp -= e.damage;
        if (blocking.hp <= 0) delete structures[nk];
        continue;
      }
      e.timer++;
      if (e.timer < e.speed) continue;
      e.timer = 0;
      e.x = bx; e.y = by;
      const trap = structures[nk];
      if (trap) { hit(e, defs[trap.id].damage); delete structures[nk]; }
    }
    enemies = enemies.filter(function (e) { return e.alive; });
    tick++;
    if (coreHp <= 0) { coreHp = 0; finished = true; victory = false; }
    else if (wavesSpawned >= raid.waves.length && enemies.length === 0) { finished = true; victory = true; }
    else if (tick >= RAID_MAX_TICKS) { finished = true; victory = false; }
  }
  return { finished: true, victory: victory, ticks: tick, core_hp: coreHp, structures_left: structureKeys().length };
}

// Pillage plafonné : identique à Wallet.lose_ratio côté client.
function loseRatio(resources: Resources, ratio: number): { resources: Resources; lost: Resources } {
  const r = Math.min(1, Math.max(0, ratio));
  const next: Resources = {}, lost: Resources = {};
  for (const k in resources) {
    const amount = Math.floor(resources[k] * r);
    next[k] = resources[k] - (amount > 0 ? amount : 0);
    if (amount > 0) lost[k] = amount;
  }
  return { resources: next, lost: lost };
}
