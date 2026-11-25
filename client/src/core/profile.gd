extends Node
## Profil du joueur : ressources, bastion, et toutes les actions qui les modifient.
##
## Deux modes, même interface pour le reste du jeu :
## - hors ligne : les règles tournent ici et la sauvegarde est locale (prototype, tests) ;
## - en ligne : chaque action passe par le serveur Nakama, qui fait autorité. Le client
##   n'applique que ce que le serveur renvoie.
## Les actions sont des coroutines : `var r := await Profile.place_building(...)`.
## Elles renvoient toujours {"ok": bool, "error": String, ...}.

const SAVE_PATH := "user://profile.json"
const DEVICE_ID_PATH := "user://device_id"
const DEFAULT_RESOURCES := {"or": 100, "bois": 60, "pierre": 60, "fer": 0, "essence": 0}
const REFUND_RATIO := 0.5

## Messages lisibles pour les codes d'erreur du serveur et du mode local.
const ERRORS := {
	"case_interdite": "Impossible de construire ici",
	"ressources_insuffisantes": "Ressources insuffisantes",
	"aucun_batiment": "Aucun bâtiment ici",
	"batiment_inconnu": "Bâtiment inconnu",
	"butin_trop_rapide": "Butin refusé : trop de victoires en peu de temps",
	"reseau": "Serveur injoignable",
	"non_connecte": "Non connecté au serveur",
}

var wallet := Wallet.new()
var bastion_layout: Array = []  # [{ "id": "tour", "x": 3, "y": 4 }, ...]
var client: NakamaClient = null


func _ready() -> void:
	load_profile()


func is_online() -> bool:
	return client != null and client.is_authenticated()


static func error_text(code: String) -> String:
	return String(ERRORS.get(code, code))


# --- Connexion ---------------------------------------------------------------

## Adresse du serveur : argument `--serveur=URL` après `--`, sinon variable AODK_SERVEUR,
## sinon réglage de projet aodk/serveur_url. Vide = mode hors ligne.
static func configured_server_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--serveur="):
			return arg.trim_prefix("--serveur=")
	var env := OS.get_environment("AODK_SERVEUR")
	if env != "":
		return env
	return String(ProjectSettings.get_setting("aodk/serveur_url", ""))


func connect_to_server(url: String) -> Dictionary:
	var c := NakamaClient.new(url)
	add_child(c)
	var auth := await c.authenticate_device(_device_id())
	if not auth.ok:
		c.queue_free()
		return auth
	client = c
	var res := await client.call_rpc("profil_lire")
	if res.get("ok", false):
		_apply_server_profile(res.profil)
	return res


func _device_id() -> String:
	if FileAccess.file_exists(DEVICE_ID_PATH):
		var saved := FileAccess.get_file_as_string(DEVICE_ID_PATH).strip_edges()
		if saved.length() >= 10:
			return saved
	var crypto := Crypto.new()
	var id := "aodk-" + crypto.generate_random_bytes(16).hex_encode()
	var f := FileAccess.open(DEVICE_ID_PATH, FileAccess.WRITE)
	if f:
		f.store_string(id)
	return id


func _apply_server_profile(profil: Dictionary) -> void:
	wallet = Wallet.new(profil.get("resources", {}))
	bastion_layout = profil.get("bastion", [])
	save_profile()  # copie locale, pour un affichage immédiat au prochain lancement
	_notify()


# --- Actions -----------------------------------------------------------------

func place_building(building_id: String, cell: Vector2i) -> Dictionary:
	if is_online():
		return _apply_rpc_result(await client.call_rpc("bastion_placer", {"id": building_id, "x": cell.x, "y": cell.y}))
	var grid := BastionGrid.from_layout(bastion_layout)
	var def: Dictionary = GameData.buildings.get(building_id, {})
	if def.is_empty():
		return {"ok": false, "error": "batiment_inconnu"}
	if not grid.can_place(cell):
		return {"ok": false, "error": "case_interdite"}
	if not wallet.try_spend(def.get("cost", {})):
		return {"ok": false, "error": "ressources_insuffisantes"}
	grid.place(building_id, cell)
	bastion_layout = grid.to_layout()
	_commit()
	return {"ok": true}


func remove_building(cell: Vector2i) -> Dictionary:
	if is_online():
		return _apply_rpc_result(await client.call_rpc("bastion_retirer", {"x": cell.x, "y": cell.y}))
	var grid := BastionGrid.from_layout(bastion_layout)
	var id := grid.remove(cell)
	if id == "":
		return {"ok": false, "error": "aucun_batiment"}
	var cost: Dictionary = GameData.buildings.get(id, {}).get("cost", {})
	var refund := {}
	for k in cost:
		refund[k] = int(floor(int(cost[k]) * REFUND_RATIO))
	wallet.add(refund)
	bastion_layout = grid.to_layout()
	_commit()
	return {"ok": true}


## `roll` (0..1) ne sert qu'hors ligne ; en ligne, le serveur tire lui-même le montant.
func loot_monster(monster_id: String, roll: float) -> Dictionary:
	if is_online():
		var res := _apply_rpc_result(await client.call_rpc("butin_monstre", {"monstre": monster_id}))
		res["gold"] = int(res.get("or", 0))
		return res
	var gold := CombatRules.roll_gold(GameData.monsters.get(monster_id, {}).get("gold", [0, 0]), roll)
	wallet.add({"or": gold})
	_commit()
	return {"ok": true, "gold": gold}


## Décide de l'issue d'un raid SANS l'appliquer : le bastion rejoue la graine pour l'afficher,
## puis appelle apply_raid() à la fin de l'animation.
## Renvoie {ok, seed, victory, loot, lost, profil}.
func launch_raid(raid_id: String) -> Dictionary:
	if is_online():
		var res := await client.call_rpc("raid_lancer", {"raid": raid_id})
		if not res.get("ok", false):
			return res
		return {"ok": true, "seed": int(res.graine), "victory": bool(res.victoire),
			"loot": res.get("butin", {}), "lost": res.get("perte", {}), "profil": res.profil}
	var raid: Dictionary = GameData.raids.get(raid_id, {})
	if raid.is_empty():
		return {"ok": false, "error": "raid_inconnu"}
	var seed_value := randi_range(1, 0x7FFFFFFF)
	var outcome := RaidSim.new(BastionGrid.from_layout(bastion_layout), raid, GameData.buildings, seed_value).run_to_end()
	var after := Wallet.new(wallet.to_dict())
	var loot: Dictionary = {}
	var lost: Dictionary = {}
	if outcome.victory:
		loot = raid.get("loot_on_win", {})
		after.add(loot)
	else:
		lost = after.lose_ratio(float(raid.get("max_loss_ratio", 0.2)))
	return {"ok": true, "seed": seed_value, "victory": outcome.victory, "loot": loot, "lost": lost,
		"profil": {"resources": after.to_dict(), "bastion": bastion_layout}}


func apply_raid(result: Dictionary) -> void:
	_apply_server_profile(result.profil)


func _apply_rpc_result(res: Dictionary) -> Dictionary:
	if res.get("ok", false) and res.has("profil"):
		_apply_server_profile(res.profil)
	if not res.has("error"):
		res["error"] = ""
	return res


# --- Sauvegarde locale -------------------------------------------------------

## Réservé au mode hors ligne et aux tests (en ligne, seul le serveur crée des ressources).
func add(resources: Dictionary) -> void:
	wallet.add(resources)
	_commit()


func get_amount(resource: String) -> int:
	return wallet.get_amount(resource)


func load_profile() -> void:
	wallet = Wallet.new(DEFAULT_RESOURCES)
	bastion_layout = []
	if FileAccess.file_exists(SAVE_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if typeof(data) == TYPE_DICTIONARY:
			wallet = Wallet.new(data.get("resources", DEFAULT_RESOURCES))
			bastion_layout = data.get("bastion", [])
	_notify()


func save_profile() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"resources": wallet.to_dict(), "bastion": bastion_layout}))


func reset() -> void:
	wallet = Wallet.new(DEFAULT_RESOURCES)
	bastion_layout = []
	_commit()


func _commit() -> void:
	save_profile()
	_notify()


func _notify() -> void:
	EventBus.resources_changed.emit(wallet.to_dict())
	EventBus.gold_changed.emit(wallet.get_amount("or"))
