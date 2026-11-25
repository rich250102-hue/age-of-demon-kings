class_name Cooldowns
extends RefCounted
## Gestion des temps de recharge, indépendante de la plateforme et du nombre d'images par seconde.

var _remaining: Dictionary = {}


func is_ready(key: String) -> bool:
	return remaining(key) <= 0.0


func remaining(key: String) -> float:
	return float(_remaining.get(key, 0.0))


func start(key: String, duration: float) -> void:
	_remaining[key] = maxf(0.0, duration)


func tick(delta: float) -> void:
	for key in _remaining.keys():
		_remaining[key] = maxf(0.0, float(_remaining[key]) - delta)
