// Événements pilotés par les données : créés depuis le panel Game Master, appliqués par le
// serveur sans mise à jour du jeu. Fonctions pures, testables sans Nakama.

interface GameEvent {
  id: string;
  nom: string;
  type: string;          // voir EVENT_TYPES
  multiplicateur: number;
  debut: number;         // horodatage ms
  fin: number;           // horodatage ms
}

const EVENT_TYPES: { [type: string]: string } = {
  bonus_or_chasse: "Or des monstres multiplié",
  bonus_butin_raid: "Butin des raids multiplié",
};
const EVENT_MAX_MULTIPLIER = 5;
const EVENT_MAX_DURATION_MS = 31 * 24 * 3600 * 1000;
const EVENT_MAX_COUNT = 50;

function validateEvent(e: any): string | null {
  if (!e || typeof e !== "object") return "evenement_invalide";
  if (typeof e.nom !== "string" || e.nom.trim().length < 1 || e.nom.length > 60) return "nom_invalide";
  if (!EVENT_TYPES[e.type]) return "type_inconnu";
  if (typeof e.multiplicateur !== "number" || !(e.multiplicateur >= 1 && e.multiplicateur <= EVENT_MAX_MULTIPLIER)) return "multiplicateur_invalide";
  if (typeof e.debut !== "number" || typeof e.fin !== "number" || !(e.fin > e.debut)) return "dates_invalides";
  if (e.fin - e.debut > EVENT_MAX_DURATION_MS) return "duree_trop_longue";
  return null;
}

function upsertEvent(list: GameEvent[], e: GameEvent, newId: string): { list: GameEvent[]; event: GameEvent } | { error: string } {
  const error = validateEvent(e);
  if (error) return { error: error };
  const clean: GameEvent = { id: e.id || newId, nom: e.nom.trim(), type: e.type, multiplicateur: Math.round(e.multiplicateur * 100) / 100, debut: e.debut, fin: e.fin };
  const others = list.filter(function (x) { return x.id !== clean.id; });
  if (!e.id) {
    if (others.length >= EVENT_MAX_COUNT) return { error: "trop_d_evenements" };
  } else if (others.length === list.length) {
    return { error: "evenement_introuvable" };
  }
  return { list: others.concat([clean]).sort(function (a, b) { return a.debut - b.debut; }), event: clean };
}

function activeEvents(list: GameEvent[], nowMs: number): GameEvent[] {
  return list.filter(function (e) { return e.debut <= nowMs && nowMs < e.fin; });
}

// Les bonus du même type se multiplient, plafonnés à EVENT_MAX_MULTIPLIER au total.
function eventMultiplier(list: GameEvent[], type: string, nowMs: number): number {
  let m = 1;
  const active = activeEvents(list, nowMs);
  for (let i = 0; i < active.length; i++) if (active[i].type === type) m *= active[i].multiplicateur;
  return Math.min(m, EVENT_MAX_MULTIPLIER);
}

function scaleResources(r: Resources, m: number): Resources {
  const out: Resources = {};
  for (const k in r) out[k] = Math.floor(r[k] * m);
  return out;
}
