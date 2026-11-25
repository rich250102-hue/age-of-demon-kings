// Module serveur d'Age of Demon Kings pour Nakama.
// Le serveur fait autorité : le client demande, le serveur vérifie et enregistre.

const COLLECTION = "profil";
const KEY = "etat";

function readState(nk: nkruntime.Nakama, userId: string): { state: PlayerState; version: string } {
  const objs = nk.storageRead([{ collection: COLLECTION, key: KEY, userId: userId }]);
  if (objs.length === 0) return { state: newPlayerState(), version: "*" };
  return { state: objs[0].value as PlayerState, version: objs[0].version };
}

// `version` empêche deux requêtes simultanées d'écraser la même sauvegarde (double dépense).
function writeState(nk: nkruntime.Nakama, userId: string, state: PlayerState, version: string): void {
  nk.storageWrite([{ collection: COLLECTION, key: KEY, userId: userId, value: state, version: version, permissionRead: 1, permissionWrite: 0 }]);
}

function parse(payload: string): any {
  if (!payload) return {};
  try { return JSON.parse(payload); } catch (e) { throw new Error("requete_invalide"); }
}

function requireUser(ctx: nkruntime.Context): string {
  if (!ctx.userId) throw new Error("non_connecte");
  return ctx.userId;
}

const rpcSante: nkruntime.RpcFunction = function (_ctx, _logger, _nk, _payload) {
  return JSON.stringify({ ok: true, jeu: "Age of Demon Kings", version: "0.1.0" });
};

const rpcProfilLire: nkruntime.RpcFunction = function (ctx, _logger, nk, _payload) {
  const userId = requireUser(ctx);
  const read = readState(nk, userId);
  if (read.version === "*") writeState(nk, userId, read.state, "*");
  return JSON.stringify({ ok: true, profil: read.state });
};

const rpcBastionPlacer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const userId = requireUser(ctx);
  const req = parse(payload);
  const read = readState(nk, userId);
  const result = placeBuilding(read.state, BUILDINGS, String(req.id), Number(req.x), Number(req.y));
  if (!result.ok) return JSON.stringify(result);
  writeState(nk, userId, result.state, read.version);
  logger.info("bastion_placer %s %s (%d,%d)", userId, req.id, req.x, req.y);
  return JSON.stringify({ ok: true, profil: result.state });
};

const rpcBastionRetirer: nkruntime.RpcFunction = function (ctx, _logger, nk, payload) {
  const userId = requireUser(ctx);
  const req = parse(payload);
  const read = readState(nk, userId);
  const result = removeBuilding(read.state, BUILDINGS, Number(req.x), Number(req.y));
  if (!result.ok) return JSON.stringify(result);
  writeState(nk, userId, result.state, read.version);
  return JSON.stringify({ ok: true, profil: result.state });
};

// Panel Game Master : réservé aux comptes dont les métadonnées portent role = "gm".
const rpcGmDonner: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const gmId = requireUser(ctx);
  const role = (nk.accountGetId(gmId).user.metadata || {})["role"];
  if (role !== "gm" && role !== "admin") return JSON.stringify({ ok: false, error: "acces_refuse" });
  const req = parse(payload);
  const error = validateGrant(req.ressources || {});
  if (error) return JSON.stringify({ ok: false, error: error });
  if (!req.motif) return JSON.stringify({ ok: false, error: "motif_obligatoire" });
  const read = readState(nk, String(req.joueur));
  const state: PlayerState = { resources: addResources(read.state.resources, req.ressources), bastion: read.state.bastion };
  writeState(nk, String(req.joueur), state, read.version);
  logger.warn("GM %s a donné %s à %s, motif : %s", gmId, JSON.stringify(req.ressources), req.joueur, req.motif);
  return JSON.stringify({ ok: true, profil: state });
};

const InitModule: nkruntime.InitModule = function (_ctx, logger, _nk, initializer) {
  initializer.registerRpc("sante", rpcSante);
  initializer.registerRpc("profil_lire", rpcProfilLire);
  initializer.registerRpc("bastion_placer", rpcBastionPlacer);
  initializer.registerRpc("bastion_retirer", rpcBastionRetirer);
  initializer.registerRpc("gm_donner", rpcGmDonner);
  logger.info("Age of Demon Kings : module serveur chargé");
};

// Nakama cherche InitModule dans la portée globale.
