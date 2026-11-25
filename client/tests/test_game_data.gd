extends RefCounted
## Vérifie la cohérence des fichiers de données : une erreur ici casserait le jeu au lancement.

var runner
var _data := preload("res://src/core/game_data.gd")


func test_every_class_skill_exists() -> void:
	var classes: Dictionary = _data.load_json("classes.json")
	var skills: Dictionary = _data.load_json("skills.json")
	runner.check(not classes.is_empty() and not skills.is_empty())
	for class_id in classes:
		var list: Array = classes[class_id].skills
		runner.check_eq(list.size(), 5, "4 compétences + 1 ultime pour %s" % class_id)
		for skill_id in list:
			runner.check(skills.has(skill_id), "compétence inconnue %s" % skill_id)


func test_monsters_are_valid() -> void:
	for id in _data.load_json("monsters.json").values():
		runner.check(int(id.hp) > 0 and float(id.speed) > 0.0)
		runner.check(id.gold.size() == 2 and int(id.gold[0]) <= int(id.gold[1]))


func test_buildings_have_costs() -> void:
	for b in _data.load_json("buildings.json").values():
		runner.check(not b.cost.is_empty(), "%s doit coûter quelque chose" % b.name)
