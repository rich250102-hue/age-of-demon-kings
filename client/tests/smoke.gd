extends SceneTree
## Test de fumée : lance le vrai jeu sans écran, simule un joueur (déplacement, combat,
## compétences, bastion, raid) et échoue à la moindre erreur de script.
## Utilisation : godot --headless --path client --script res://tests/smoke.gd

const RunTests := preload("res://tests/run_tests.gd")

var _catcher := RunTests.ErrorCatcher.new()
var _frame := 0
var _main: Node
var _log: Array[String] = []


func _initialize() -> void:
	OS.add_logger(_catcher)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	_frame += 1
	var level: Node = _main.get_child(0) if _main.get_child_count() > 0 else null
	match _frame:
		5:
			_expect(level != null and level.has_method("set_liberated"), "la forêt est chargée")
			_profile().reset()
			level.hero.move_target = Vector3(8, 0, 4)
		60:
			level.hero.target = level.monsters[0]
			level.hero.global_position = level.monsters[0].global_position + Vector3(1, 0, 0)
		61:
			for slot in range(1, 6):
				level.hero.use_skill(slot)
		200:
			for m in level.monsters:
				if not m.is_boss():
					m.take_damage(9999, false)
			var boss: Node = level.monsters.back()
			boss.take_damage(9999, true)
			_expect(level.liberated, "battre le Gardien libère la forêt")
			_expect(_profile().get_amount("or") > 100, "les monstres donnent de l'or")
			_profile().add({"or": 1000, "bois": 500, "pierre": 500})
			level.navigate.emit("bastion")
		215:
			_expect(level.has_method("_start_raid"), "le bastion est chargé")
			for x in [2, 4, 7, 9]:
				for y in [2, 4, 7, 9]:
					level._on_cell_tapped(Vector2i(x, y))
			_expect(level.grid.buildings().size() == 16, "16 tours placées (%d)" % level.grid.buildings().size())
			level._start_raid()
		216:
			while level._sim != null and not level._sim.finished:
				level._sim.step()
				level._render_events()
		220:
			_expect(level._sim == null, "le raid se termine proprement")
			_expect(_profile().bastion_layout.size() == 16, "la disposition est sauvegardée")
			level.navigate.emit("forest")
		240:
			_finish()
			return true
	return false


func _profile() -> Node:
	return root.get_node("Profile")


func _expect(condition: bool, label: String) -> void:
	_log.append(("  OK    " if condition else "  ECHEC ") + label)


func _finish() -> void:
	var errors := _catcher.take()
	for line in _log:
		print(line)
	for e in errors:
		print("  ERREUR " + e)
	var failed := errors.size() + _log.filter(func(l): return l.begins_with("  ECHEC")).size()
	print("\nTest de fumée : %d vérification(s), %d problème(s)" % [_log.size(), failed])
	_profile().reset()
	OS.remove_logger(_catcher)
	quit(0 if failed == 0 else 1)
