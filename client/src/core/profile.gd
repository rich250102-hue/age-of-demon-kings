extends Node
## Profil local du joueur : ressources et sauvegarde.
## Dans la version en ligne, ces valeurs viendront du serveur (Nakama), qui fait autorité.

const SAVE_PATH := "user://profile.json"
const DEFAULT_RESOURCES := {"or": 100, "bois": 60, "pierre": 60, "fer": 0, "essence": 0}

var wallet := Wallet.new()
var bastion_layout: Array = []  # [{ "id": "tour", "x": 3, "y": 4 }, ...]


func _ready() -> void:
	load_profile()


func add(resources: Dictionary) -> void:
	wallet.add(resources)
	_notify()
	save_profile()


func try_spend(cost: Dictionary) -> bool:
	if not wallet.try_spend(cost):
		return false
	_notify()
	save_profile()
	return true


func get_amount(resource: String) -> int:
	return wallet.get_amount(resource)


func load_profile() -> void:
	wallet = Wallet.new(DEFAULT_RESOURCES)
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
	save_profile()
	_notify()


func _notify() -> void:
	EventBus.resources_changed.emit(wallet.to_dict())
	EventBus.gold_changed.emit(wallet.get_amount("or"))
