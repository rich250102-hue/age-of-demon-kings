class_name RaidSim
extends RefCounted
## Simulation déterministe d'un raid démoniaque contre un bastion.
## Même graine + même disposition = même résultat : le serveur peut la rejouer pour valider,
## et le client peut l'afficher en replay. 1 tick = 0,1 seconde.

const TICK_SECONDS := 0.1
const MAX_TICKS := 3000
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var grid: BastionGrid
var raid: Dictionary
var building_defs: Dictionary
var rng: DetRng

var tick := 0
var core_hp := 0
var enemies: Array[Dictionary] = []      # {id, cell, hp, max_hp, damage, speed_ticks, move_timer, alive}
var structures: Dictionary = {}          # Vector2i -> {id, hp, cooldown}
var events: Array[Dictionary] = []       # événements du dernier tick (tirs, morts...) pour l'affichage
var finished := false
var victory := false

var _distance: Dictionary = {}           # Vector2i -> distance au cœur
var _waves_spawned := 0
var _next_enemy_id := 1


func _init(p_grid: BastionGrid, p_raid: Dictionary, p_building_defs: Dictionary, seed_value: int) -> void:
	grid = p_grid
	raid = p_raid
	building_defs = p_building_defs
	rng = DetRng.new(seed_value)
	core_hp = int(raid.get("core_hp", 500))
	for b in grid.buildings():
		var def: Dictionary = building_defs.get(b.id, {})
		structures[Vector2i(b.x, b.y)] = {"id": b.id, "hp": int(def.get("hp", 1)), "cooldown": 0}
	_compute_distance_field()


func run_to_end() -> Dictionary:
	while not finished:
		step()
	return result()


func step() -> void:
	if finished:
		return
	events.clear()
	_spawn_waves()
	_structures_act()
	_enemies_act()
	enemies = enemies.filter(func(e): return e.alive)
	tick += 1
	_check_end()


func result() -> Dictionary:
	return {
		"finished": finished,
		"victory": victory,
		"ticks": tick,
		"core_hp": core_hp,
		"structures_left": structures.size(),
	}


func cell_to_world_center() -> float:
	return grid.size / 2.0


func _compute_distance_field() -> void:
	var queue: Array[Vector2i] = []
	for cell in grid.core_cells():
		_distance[cell] = 0
		queue.append(cell)
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for d in DIRS:
			var next: Vector2i = current + d
			if grid.in_bounds(next) and not _distance.has(next):
				_distance[next] = int(_distance[current]) + 1
				queue.append(next)


func _edge_cell() -> Vector2i:
	var side := rng.range_int(0, 3)
	var pos := rng.range_int(0, grid.size - 1)
	match side:
		0: return Vector2i(pos, 0)
		1: return Vector2i(pos, grid.size - 1)
		2: return Vector2i(0, pos)
		_: return Vector2i(grid.size - 1, pos)


func _spawn_waves() -> void:
	var waves: Array = raid.get("waves", [])
	while _waves_spawned < waves.size() and int(waves[_waves_spawned].get("tick", 0)) <= tick:
		var wave: Dictionary = waves[_waves_spawned]
		for i in int(wave.get("count", 0)):
			var hp := int(wave.get("hp", 10))
			enemies.append({
				"id": _next_enemy_id, "cell": _edge_cell(), "hp": hp, "max_hp": hp,
				"damage": int(wave.get("damage", 1)), "speed_ticks": maxi(1, int(wave.get("speed_ticks", 3))),
				"move_timer": 0, "alive": true,
			})
			_next_enemy_id += 1
		_waves_spawned += 1


func _structures_act() -> void:
	for cell in _sorted_structure_cells():
		var s: Dictionary = structures[cell]
		var def: Dictionary = building_defs.get(s.id, {})
		var interval := int(def.get("fire_interval", 0))
		var dmg := int(def.get("damage", 0))
		if interval <= 0 or dmg <= 0:
			continue
		s.cooldown = maxi(0, int(s.cooldown) - 1)
		if s.cooldown > 0:
			continue
		var target := _nearest_enemy(cell, float(def.get("range", 0.0)))
		if target.is_empty():
			continue
		_hit_enemy(target, dmg)
		s.cooldown = interval
		events.append({"type": "shot", "from": cell, "to": target.cell, "target": target.id})


func _enemies_act() -> void:
	for e in enemies:
		if not e.alive:
			continue
		var cell: Vector2i = e.cell
		if int(_distance.get(cell, 99)) <= 1:
			core_hp -= int(e.damage)
			events.append({"type": "core_hit", "enemy": e.id, "damage": e.damage})
			continue
		var next := _next_cell(cell)
		if structures.has(next) and bool(building_defs.get(structures[next].id, {}).get("blocks", false)):
			var s: Dictionary = structures[next]
			s.hp = int(s.hp) - int(e.damage)
			events.append({"type": "structure_hit", "cell": next, "enemy": e.id})
			if s.hp <= 0:
				structures.erase(next)
				events.append({"type": "structure_destroyed", "cell": next})
			continue
		e.move_timer = int(e.move_timer) + 1
		if e.move_timer < int(e.speed_ticks):
			continue
		e.move_timer = 0
		e.cell = next
		if structures.has(next):  # piège non bloquant
			var trap: Dictionary = structures[next]
			_hit_enemy(e, int(building_defs.get(trap.id, {}).get("damage", 0)))
			structures.erase(next)
			events.append({"type": "trap", "cell": next, "target": e.id})


func _next_cell(cell: Vector2i) -> Vector2i:
	var best := cell
	var best_d := int(_distance.get(cell, 99))
	for d in DIRS:
		var n: Vector2i = cell + d
		if grid.in_bounds(n) and int(_distance.get(n, 99)) < best_d:
			best = n
			best_d = int(_distance[n])
	return best


func _nearest_enemy(cell: Vector2i, max_range: float) -> Dictionary:
	# Distances au carré en entiers : résultat exact, identique côté serveur.
	var best: Dictionary = {}
	var best_d2 := -1
	var range2 := max_range * max_range
	for e in enemies:
		if not e.alive:
			continue
		var delta: Vector2i = e.cell - cell
		var d2 := delta.x * delta.x + delta.y * delta.y
		if d2 <= range2 and (best_d2 < 0 or d2 < best_d2 or (d2 == best_d2 and int(e.id) < int(best.id))):
			best = e
			best_d2 = d2
	return best


func _hit_enemy(e: Dictionary, dmg: int) -> void:
	e.hp = int(e.hp) - dmg
	if e.hp <= 0 and e.alive:
		e.alive = false
		events.append({"type": "enemy_killed", "target": e.id})


func _sorted_structure_cells() -> Array:
	var cells := structures.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y * grid.size + a.x < b.y * grid.size + b.x)
	return cells


func _check_end() -> void:
	var all_spawned: bool = _waves_spawned >= raid.get("waves", []).size()
	if core_hp <= 0:
		core_hp = 0
		finished = true
		victory = false
	elif all_spawned and enemies.is_empty():
		finished = true
		victory = true
	elif tick >= MAX_TICKS:
		finished = true
		victory = false
