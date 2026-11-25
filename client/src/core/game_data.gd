extends Node
## Charge les données de jeu (JSON) une seule fois au démarrage.
## Toutes les valeurs d'équilibrage vivent dans res://data, jamais dans le code.

const DATA_DIR := "res://data/"

var classes: Dictionary = {}
var skills: Dictionary = {}
var monsters: Dictionary = {}
var buildings: Dictionary = {}
var raids: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	classes = load_json("classes.json")
	skills = load_json("skills.json")
	monsters = load_json("monsters.json")
	buildings = load_json("buildings.json")
	raids = load_json("raids.json")


static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameData: impossible d'ouvrir %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: JSON invalide dans %s" % path)
		return {}
	return parsed


func skills_for_class(class_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill_id in classes.get(class_id, {}).get("skills", []):
		var skill: Dictionary = skills.get(skill_id, {}).duplicate()
		skill["id"] = skill_id
		result.append(skill)
	return result
