class_name Wallet
extends RefCounted
## Portefeuille de ressources. Logique pure, testable et réutilisable côté serveur.

var _amounts: Dictionary = {}


func _init(initial: Dictionary = {}) -> void:
	for key in initial:
		_amounts[key] = maxi(0, int(initial[key]))


func get_amount(resource: String) -> int:
	return int(_amounts.get(resource, 0))


func add(resources: Dictionary) -> void:
	for key in resources:
		var value := int(resources[key])
		assert(value >= 0, "Wallet.add: montant négatif interdit")
		_amounts[key] = get_amount(key) + maxi(0, value)


func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if get_amount(key) < int(cost[key]):
			return false
	return true


## Dépense tout ou rien : si une ressource manque, rien n'est retiré.
func try_spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for key in cost:
		_amounts[key] = get_amount(key) - int(cost[key])
	return true


## Retire au plus `ratio` de chaque ressource (pillage). Retourne ce qui a été perdu.
func lose_ratio(ratio: float) -> Dictionary:
	var lost := {}
	var r := clampf(ratio, 0.0, 1.0)
	for key in _amounts:
		var amount := int(floor(get_amount(key) * r))
		if amount > 0:
			_amounts[key] = get_amount(key) - amount
			lost[key] = amount
	return lost


func to_dict() -> Dictionary:
	return _amounts.duplicate()
