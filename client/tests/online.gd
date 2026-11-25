extends SceneTree
## Test d'intégration avec un vrai serveur Nakama (module AODK chargé).
## Utilisation : godot --headless --path client --script res://tests/online.gd -- --serveur=http://127.0.0.1:7350
## Vérifie que chaque action du jeu passe par le serveur et que le raid affiché = raid décidé par le serveur.

const RunTests := preload("res://tests/run_tests.gd")

var _catcher := RunTests.ErrorCatcher.new()
var _log: Array[String] = []


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	var profile: Node = root.get_node("Profile")
	var url: String = profile.configured_server_url()
	_expect(url != "", "adresse du serveur fournie (%s)" % url)
	var res: Dictionary = await profile.connect_to_server(url)
	_expect(res.get("ok", false), "connexion et lecture du profil (%s)" % str(res.get("error", "")))
	_expect(profile.is_online(), "mode en ligne actif")
	if not profile.is_online():
		_finish()
		return

	var gold_before: int = profile.get_amount("or")
	var cell := Vector2i(1, 1)
	# Nettoie une éventuelle tour d'un lancement précédent du test.
	if BastionGrid.from_layout(profile.bastion_layout).building_at(cell) != "":
		await profile.remove_building(cell)
		gold_before = profile.get_amount("or")
	res = await profile.place_building("mur", cell)
	_expect(res.ok, "le serveur accepte un mur (%s)" % res.error)
	_expect(profile.get_amount("or") == gold_before - 10, "le serveur a débité 10 or")
	res = await profile.place_building("mur", Vector2i(0, 0))
	_expect(not res.ok and res.error == "case_interdite", "le serveur refuse une case du bord")

	var before_loot: int = profile.get_amount("or")
	res = await profile.loot_monster("diablotin", 0.0)
	_expect(res.ok and res.gold >= 3 and res.gold <= 6, "butin tiré par le serveur (%d)" % int(res.get("gold", -1)))
	_expect(profile.get_amount("or") == before_loot + int(res.gold), "or mis à jour depuis le serveur")

	res = await profile.launch_raid("raid_1")
	_expect(res.ok, "le serveur décide du raid (graine %d)" % int(res.get("seed", 0)))
	var replay := RaidSim.new(BastionGrid.from_layout(profile.bastion_layout), root.get_node("GameData").raids.raid_1, root.get_node("GameData").buildings, int(res.seed)).run_to_end()
	_expect(replay.victory == res.victory, "le raid rejoué par le client = résultat du serveur")
	profile.apply_raid(res)

	# Relecture indépendante : l'état du serveur est bien celui que le client affiche.
	var fresh: Dictionary = await profile.client.call_rpc("profil_lire")
	var same := true
	for k in fresh.profil.resources:
		same = same and int(fresh.profil.resources[k]) == profile.get_amount(k)
	_expect(same, "ressources identiques client / serveur %s / %s" % [fresh.profil.resources, profile.wallet.to_dict()])
	_expect(fresh.profil.bastion.size() == profile.bastion_layout.size(), "bastion identique client / serveur")

	await profile.remove_building(cell)
	_finish()


func _expect(condition: bool, label: String) -> void:
	_log.append(("  OK    " if condition else "  ECHEC ") + label)


func _finish() -> void:
	for line in _log:
		print(line)
	var failures := _log.filter(func(l: String): return l.begins_with("  ECHEC")).size() + _catcher.errors.size()
	for e in _catcher.errors:
		print("  ERREUR ", e)
	print("\nTest en ligne : %d vérification(s), %d problème(s)" % [_log.size(), failures])
	quit(1 if failures > 0 else 0)
