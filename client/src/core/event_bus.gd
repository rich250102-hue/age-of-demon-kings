extends Node
## Bus d'événements global : les systèmes communiquent sans se connaître.

signal gold_changed(amount: int)
signal resources_changed(resources: Dictionary)
signal hero_health_changed(current: int, maximum: int)
signal hero_died
signal monster_killed(monster_id: String, gold: int)
signal skill_used(slot: int, cooldown: float)
signal forest_state_changed(liberated: bool, corruption: float)
signal message(text: String)
