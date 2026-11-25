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

const implSante: nkruntime.RpcFunction = function (_ctx, _logger, _nk, _payload) {
  return JSON.stringify({ ok: true, jeu: "Age of Demon Kings", version: "0.1.0" });
};

const implProfilLire: nkruntime.RpcFunction = function (ctx, _logger, nk, _payload) {
  const userId = requireUser(ctx);
  const read = readState(nk, userId);
  if (read.version === "*") writeState(nk, userId, read.state, "*");
  return JSON.stringify({ ok: true, profil: publicState(read.state) });
};

const implBastionPlacer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const userId = requireUser(ctx);
  const req = parse(payload);
  const read = readState(nk, userId);
  const result = placeBuilding(read.state, BUILDINGS, String(req.id), Number(req.x), Number(req.y));
  if (!result.ok) return JSON.stringify(result);
  writeState(nk, userId, result.state, read.version);
  logger.info("bastion_placer %s %s (%d,%d)", userId, req.id, req.x, req.y);
  return JSON.stringify({ ok: true, profil: publicState(result.state) });
};

const implBastionRetirer: nkruntime.RpcFunction = function (ctx, _logger, nk, payload) {
  const userId = requireUser(ctx);
  const req = parse(payload);
  const read = readState(nk, userId);
  const result = removeBuilding(read.state, BUILDINGS, Number(req.x), Number(req.y));
  if (!result.ok) return JSON.stringify(result);
  writeState(nk, userId, result.state, read.version);
  return JSON.stringify({ ok: true, profil: publicState(result.state) });
};

const implButinMonstre: nkruntime.RpcFunction = function (ctx, _logger, nk, payload) {
  const userId = requireUser(ctx);
  const req = parse(payload);
  const read = readState(nk, userId);
  const now = Date.now();
  const result = lootMonster(read.state, MONSTERS, String(req.monstre), now, Math.random(), eventMultiplier(readEvents(nk).list, "bonus_or_chasse", now));
  if (!result.ok) return JSON.stringify(result);
  writeState(nk, userId, result.state, read.version);
  return JSON.stringify({ ok: true, or: result.gold, profil: publicState(result.state) });
};

// Le serveur choisit la graine et décide de l'issue ; le client rejoue la même graine pour l'afficher.
const implRaidLancer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) {
  const userId = requireUser(ctx);
  const req = parse(payload);
  const raidId = String(req.raid || "raid_1");
  const raid = RAIDS[raidId];
  if (!raid) return JSON.stringify({ ok: false, error: "raid_inconnu" });
  const read = readState(nk, userId);
  const seed = Math.floor(Math.random() * 0x7fffffff) + 1;
  const outcome = simulateRaid(read.state.bastion, raid, BUILDINGS, seed);
  let resources: Resources, lost: Resources = {}, loot: Resources = {};
  if (outcome.victory) {
    loot = scaleResources(raid.loot_on_win, eventMultiplier(readEvents(nk).list, "bonus_butin_raid", Date.now()));
    resources = addResources(read.state.resources, loot);
  } else {
    const loss = loseRatio(read.state.resources, raid.max_loss_ratio);
    resources = loss.resources; lost = loss.lost;
  }
  const state: PlayerState = { resources: resources, bastion: read.state.bastion, chasse: read.state.chasse };
  writeState(nk, userId, state, read.version);
  logger.info("raid %s %s graine=%d victoire=%s", userId, raidId, seed, String(outcome.victory));
  return JSON.stringify({ ok: true, raid: raidId, graine: seed, victoire: outcome.victory, resultat: outcome,
    butin: loot, perte: lost, profil: publicState(state) });
};

// Ce que le client voit de son état (l'historique de chasse reste côté serveur).
function publicState(state: PlayerState): { resources: Resources; bastion: PlacedBuilding[] } {
  return { resources: state.resources, bastion: state.bastion };
}

// Toute RPC renvoie {ok:false, error:code} au lieu d'une exception : le client reçoit un code
// lisible et jamais de trace interne. Nakama exige que registerRpc reçoive une fonction déclarée
// au niveau global (pas une fonction fabriquée à la volée) : d'où un enveloppeur explicite par RPC.
function guarded(impl: nkruntime.RpcFunction, ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  try {
    return impl(ctx, logger, nk, payload);
  } catch (e) {
    const message = String((e && (e as any).message) || e);
    if (/^[a-z_]+$/.test(message)) return JSON.stringify({ ok: false, error: message });
    logger.error("RPC en échec : %s", message);
    return JSON.stringify({ ok: false, error: "erreur_serveur" });
  }
}

const rpcSante: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implSante, ctx, logger, nk, payload); };
const rpcProfilLire: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implProfilLire, ctx, logger, nk, payload); };
const rpcBastionPlacer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implBastionPlacer, ctx, logger, nk, payload); };
const rpcBastionRetirer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implBastionRetirer, ctx, logger, nk, payload); };
const rpcButinMonstre: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implButinMonstre, ctx, logger, nk, payload); };
const rpcRaidLancer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implRaidLancer, ctx, logger, nk, payload); };
const rpcEvenementsActifs: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implEvenementsActifs, ctx, logger, nk, payload); };
const rpcGmMoi: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmMoi, ctx, logger, nk, payload); };
const rpcGmJoueur: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmJoueur, ctx, logger, nk, payload); };
const rpcGmDonner: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmDonner, ctx, logger, nk, payload); };
const rpcGmEvenements: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmEvenements, ctx, logger, nk, payload); };
const rpcGmEvenementSauver: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmEvenementSauver, ctx, logger, nk, payload); };
const rpcGmEvenementSupprimer: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmEvenementSupprimer, ctx, logger, nk, payload); };
const rpcGmJournal: nkruntime.RpcFunction = function (ctx, logger, nk, payload) { return guarded(implGmJournal, ctx, logger, nk, payload); };

const InitModule: nkruntime.InitModule = function (_ctx, logger, _nk, initializer) {
  initializer.registerRpc("sante", rpcSante);
  initializer.registerRpc("profil_lire", rpcProfilLire);
  initializer.registerRpc("bastion_placer", rpcBastionPlacer);
  initializer.registerRpc("bastion_retirer", rpcBastionRetirer);
  initializer.registerRpc("evenements_actifs", rpcEvenementsActifs);
  initializer.registerRpc("gm_moi", rpcGmMoi);
  initializer.registerRpc("gm_joueur", rpcGmJoueur);
  initializer.registerRpc("gm_donner", rpcGmDonner);
  initializer.registerRpc("gm_evenements", rpcGmEvenements);
  initializer.registerRpc("gm_evenement_sauver", rpcGmEvenementSauver);
  initializer.registerRpc("gm_evenement_supprimer", rpcGmEvenementSupprimer);
  initializer.registerRpc("gm_journal", rpcGmJournal);
  initializer.registerRpc("butin_monstre", rpcButinMonstre);
  initializer.registerRpc("raid_lancer", rpcRaidLancer);
  logger.info("Age of Demon Kings : module serveur chargé");
};

// Nakama cherche InitModule dans la portée globale.
