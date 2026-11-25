class_name CombatRules
extends RefCounted
## Formules de combat. Fonctions pures : mêmes résultats sur mobile, PC et serveur.

const MIN_DAMAGE := 1


## Statistiques dérivées à partir des caractéristiques de base et du niveau.
static func derive_stats(base: Dictionary, level: int) -> Dictionary:
	var force := int(base.get("force", 1))
	var agilite := int(base.get("agilite", 1))
	var vigueur := int(base.get("vigueur", 1))
	var esprit := int(base.get("esprit", 1))
	var precision := int(base.get("precision", 1))
	var lvl := maxi(1, level)
	return {
		"max_hp": 80 + vigueur * 12 + lvl * 10,
		"attack": 6 + force * 2 + lvl,
		"defense": vigueur + int(lvl / 2.0),
		"crit_chance": clampf(0.02 + precision * 0.005, 0.0, 0.5),
		"attack_speed": 1.0 + agilite * 0.02,
		"max_mana": 30 + esprit * 8,
	}


## Dégâts d'un coup. `roll` dans [0, 1) est fourni par l'appelant (déterministe en test).
static func compute_damage(attack: int, defense: int, power: float, crit_chance: float, roll: float) -> Dictionary:
	var raw := attack * power
	var reduced := raw * (100.0 / (100.0 + maxf(0.0, defense) * 5.0))
	var is_crit := roll < crit_chance
	if is_crit:
		reduced *= 1.5
	return {"amount": maxi(MIN_DAMAGE, int(round(reduced))), "crit": is_crit}


## Or lâché par un monstre, entre gold[0] et gold[1] inclus.
static func roll_gold(gold_range: Array, roll: float) -> int:
	if gold_range.size() < 2:
		return 0
	var low := int(gold_range[0])
	var high := int(gold_range[1])
	return low + int(floor(clampf(roll, 0.0, 0.9999) * (high - low + 1)))
