// Panel Game Master : RPC réservées aux comptes dont les métadonnées portent role = "gm" ou "admin".
// Chaque action qui modifie le jeu est inscrite au journal (qui, quoi, quand, motif).

const SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
const CONFIG_COLLECTION = "config";
const EVENTS_KEY = "evenements";
const JOURNAL_KEY = "journal_gm";
const JOURNAL_MAX = 500;

function requireGm(ctx: nkruntime.Context, nk: nkruntime.Nakama): { id: string; role: string; username: string } {
  const id = requireUser(ctx);
  const user = nk.accountGetId(id).user;
  const role = (user.metadata || {})["role"];
  if (role !== "gm" && role !== "admin") throw new Error("acces_refuse");
  return { id: id, role: role, username: user.username };
}

function readSystem(nk: nkruntime.Nakama, key: string, empty: any): { value: any; version: string } {
  const objs = nk.storageRead([{ collection: CONFIG_COLLECTION, key: key, userId: SYSTEM_USER }]);
  if (objs.length === 0) return { value: empty, version: "*" };
  return { value: objs[0].value, version: objs[0].version };
}

function writeSystem(nk: nkruntime.Nakama, key: string, value: any, version: string): void {
  nk.storageWrite([{ collection: CONFIG_COLLECTION, key: key, userId: SYSTEM_USER, value: value, version: version, permissionRead: 0, permissionWrite: 0 }]);
}

function readEvents(nk: nkruntime.Nakama): { list: GameEvent[]; version: string } {
  const r = readSystem(nk, EVENTS_KEY, { liste: [] });
  return { list: r.value.liste || [], version: r.version };
}

function journal(nk: nkruntime.Nakama, logger: nkruntime.Logger, gm: { id: string; username: string }, action: string, details: any): void {
  const r = readSystem(nk, JOURNAL_KEY, { entrees: [] });
  const entries = (r.value.entrees || []).concat([{ quand: Date.now(), gm: gm.username, gm_id: gm.id, action: action, details: details }]);
  writeSystem(nk, JOURNAL_KEY, { entrees: entries.slice(-JOURNAL_MAX) }, r.version);
  logger.warn("GM %s : %s %s", gm.username, action, JSON.stringify(details));
}

function newId(): string {
  return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36);
}

// Ouvert à tous les joueurs : le jeu affiche les événements en cours.
const implEvenementsActifs: nkruntime.RpcFunction = function (ctx, _logger, nk, _payload) {
  requireUser(ctx);
  const now = Date.now();
  const list = activeEvents(readEvents(nk).list, now).map(function (e) {
    return { nom: e.nom, type: e.type, description: EVENT_TYPES[e.type], multiplicateur: e.multiplicateur, fin: e.fin };
  });
  return JSON.stringify({ ok: true, maintenant: now, evenements: list });
};

const implGmMoi: nkruntime.RpcFunction = function (ctx, _logger, nk, _payload) {
  const gm = requireGm(ctx, nk);
  return JSON.stringify({ ok: true, gm: gm, types_evenement: EVENT_TYPES, ressources: Object.keys(DEFAULT_RESOURCES) });
};

// Recherche par nom d'utilisateur exact ou par identifiant.
const implGmJoueur: nkruntime.RpcFunction = function (ctx, _logger, nk, payload) {
  requireGm(ctx, nk);
  const q = String(parse(payload).recherche || "").trim();
  if (!q) return JSON.stringify({ ok: false, error: "recherche_vide" });
  let users: nkruntime.User[] = [];
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(q)) {
    try { users = nk.usersGetId([q]); } catch (e) { users = []; }
  }
  if (users.length === 0) {
    try { users = nk.usersGetUsername([q]); } catch (e) { users = []; }
  }
  if (users.length === 0) return JSON.stringify({ ok: false, error: "joueur_introuvable" });
  const u = users[0];
  return JSON.stringify({ ok: true, joueur: { id: u.userId, nom: u.username, role: (u.metadata || {})["role"] || "joueur" }, profil: publicState(readState(nk, u.userId).state) });
};

const implGmDonner: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const gm = requireGm(ctx, nk);
  const req = parse(payload);
  const error = validateGrant(req.ressources || {});
  if (error) return JSON.stringify({ ok: false, error: error });
  if (!req.motif || String(req.motif).trim().length < 3) return JSON.stringify({ ok: false, error: "motif_obligatoire" });
  const target = String(req.joueur || "");
  try { if (nk.usersGetId([target]).length === 0) return JSON.stringify({ ok: false, error: "joueur_introuvable" }); }
  catch (e) { return JSON.stringify({ ok: false, error: "joueur_introuvable" }); }
  const read = readState(nk, target);
  const state: PlayerState = { resources: addResources(read.state.resources, req.ressources), bastion: read.state.bastion, chasse: read.state.chasse };
  writeState(nk, target, state, read.version);
  journal(nk, logger, gm, "don", { joueur: target, ressources: req.ressources, motif: String(req.motif) });
  return JSON.stringify({ ok: true, profil: publicState(state) });
};

const implGmEvenements: nkruntime.RpcFunction = function (ctx, _logger, nk, _payload) {
  requireGm(ctx, nk);
  return JSON.stringify({ ok: true, maintenant: Date.now(), evenements: readEvents(nk).list, types: EVENT_TYPES });
};

const implGmEvenementSauver: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const gm = requireGm(ctx, nk);
  const req = parse(payload);
  const read = readEvents(nk);
  const res = upsertEvent(read.list, req.evenement, newId());
  if ("error" in res) return JSON.stringify({ ok: false, error: res.error });
  writeSystem(nk, EVENTS_KEY, { liste: res.list }, read.version);
  journal(nk, logger, gm, req.evenement && req.evenement.id ? "evenement_modifie" : "evenement_cree", res.event);
  return JSON.stringify({ ok: true, evenement: res.event, evenements: res.list });
};

const implGmEvenementSupprimer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const gm = requireGm(ctx, nk);
  const id = String(parse(payload).id || "");
  const read = readEvents(nk);
  const removed = read.list.filter(function (e) { return e.id === id; });
  if (removed.length === 0) return JSON.stringify({ ok: false, error: "evenement_introuvable" });
  const list = read.list.filter(function (e) { return e.id !== id; });
  writeSystem(nk, EVENTS_KEY, { liste: list }, read.version);
  journal(nk, logger, gm, "evenement_supprime", removed[0]);
  return JSON.stringify({ ok: true, evenements: list });
};

const implGmJournal: nkruntime.RpcFunction = function (ctx, _logger, nk, _payload) {
  requireGm(ctx, nk);
  const entries = readSystem(nk, JOURNAL_KEY, { entrees: [] }).value.entrees || [];
  return JSON.stringify({ ok: true, entrees: entries.slice(-100).reverse() });
};
