class_name Hero
extends Node3D
## Le héros du joueur. Même logique sur mobile et PC : le serveur (plus tard) appliquera les mêmes règles.

const RESPAWN_DELAY := 3.0
const ASSIST_RADIUS := 1.5  # tolérance du ciblage assisté, en mètres

var class_id := "lame"
var level := 5
var stats: Dictionary = {}
var hp := 1
var move_speed := 6.0
var attack_range := 2.2
var attack_interval := 1.0

var target: Node3D            # monstre ciblé
var move_target: Variant = null  # Vector3 ou null
var input_direction := Vector3.ZERO  # joystick ou clavier, déjà en coordonnées du monde
var monsters_provider: Callable   # renvoie la liste des monstres vivants
var spawn_point := Vector3.ZERO

var skills: Array[Dictionary] = []
var cooldowns := Cooldowns.new()
var rng := RandomNumberGenerator.new()

var _attack_timer := 0.0
var _buff_timer := 0.0
var _buff_power := 0.0
var _dead_timer := 0.0
var _body: Node3D


func _ready() -> void:
	var def: Dictionary = GameData.classes.get(class_id, {})
	stats = CombatRules.derive_stats(def.get("base_stats", {}), level)
	hp = int(stats.max_hp)
	move_speed = float(def.get("move_speed", 6.0))
	attack_range = float(def.get("attack_range", 2.2))
	attack_interval = float(def.get("attack_interval", 1.0)) / float(stats.attack_speed)
	skills = GameData.skills_for_class(class_id)
	_build_body()
	EventBus.hero_health_changed.emit(hp, int(stats.max_hp))


func is_dead() -> bool:
	return hp <= 0


func _process(delta: float) -> void:
	cooldowns.tick(delta)
	_buff_timer = maxf(0.0, _buff_timer - delta)
	if is_dead():
		_dead_timer -= delta
		if _dead_timer <= 0.0:
			_respawn()
		return
	if target and (not is_instance_valid(target) or target.is_dead()):
		target = null
	_move(delta)
	_auto_attack(delta)


func _move(delta: float) -> void:
	var dir := Vector3.ZERO
	if input_direction.length() > 0.1:
		dir = input_direction
		move_target = null
	elif target and _flat_distance(target) > attack_range:
		dir = _flat_dir_to(target.global_position)
	elif move_target != null:
		if _flat_distance_to(move_target) < 0.2:
			move_target = null
		else:
			dir = _flat_dir_to(move_target)
	if dir.length() > 0.01:
		dir = dir.normalized() * minf(1.0, dir.length())
		global_position += dir * move_speed * delta
		global_position.x = clampf(global_position.x, -38.0, 38.0)
		global_position.z = clampf(global_position.z, -38.0, 38.0)
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), clampf(12.0 * delta, 0.0, 1.0))


func _auto_attack(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if target == null or _attack_timer > 0.0 or _flat_distance(target) > attack_range + ASSIST_RADIUS * 0.5:
		return
	_attack_timer = attack_interval
	_hit(target, 1.0)
	_face(target.global_position)


## Lance la compétence de l'emplacement 1 à 5. Renvoie true si elle a été lancée.
func use_skill(slot: int) -> bool:
	if is_dead() or slot < 1 or slot > skills.size():
		return false
	var skill: Dictionary = skills[slot - 1]
	var id: String = skill.id
	if not cooldowns.is_ready(id):
		return false
	var used := false
	match String(skill.kind):
		"single":
			var t := _assist_target(float(skill.range))
			if t:
				_hit(t, float(skill.power))
				target = t
				used = true
		"area_self":
			for m in _monsters_within(float(skill.radius)):
				_hit(m, float(skill.power))
			_flash_ring(float(skill.radius))
			used = true
		"dash":
			var t := _assist_target(float(skill.range))
			if t:
				var dir := _flat_dir_to(t.global_position)
				global_position = t.global_position - dir.normalized() * 1.2
				_hit(t, float(skill.power))
				target = t
				used = true
		"buff":
			_buff_power = float(skill.power)
			_buff_timer = float(skill.get("duration", 5.0))
			used = true
	if used:
		cooldowns.start(id, float(skill.cooldown))
		EventBus.skill_used.emit(slot, float(skill.cooldown))
	else:
		EventBus.message.emit("Aucune cible à portée")
	return used


func take_damage(amount: int) -> void:
	if is_dead():
		return
	var dmg := CombatRules.compute_damage(amount, int(stats.defense), 1.0, 0.0, 1.0)
	hp = maxi(0, hp - int(dmg.amount))
	EventBus.hero_health_changed.emit(hp, int(stats.max_hp))
	if is_dead():
		_dead_timer = RESPAWN_DELAY
		target = null
		visible = false
		EventBus.hero_died.emit()
		EventBus.message.emit("Vous êtes tombé. Retour au Sanctuaire...")


func _respawn() -> void:
	hp = int(stats.max_hp)
	global_position = spawn_point
	visible = true
	EventBus.hero_health_changed.emit(hp, int(stats.max_hp))


func _hit(monster: Node3D, power: float) -> void:
	var attack := int(round(float(stats.attack) * (1.0 + (_buff_power if _buff_timer > 0.0 else 0.0))))
	var r := CombatRules.compute_damage(attack, monster.defense(), power, float(stats.crit_chance), rng.randf())
	monster.take_damage(int(r.amount), bool(r.crit))


func _assist_target(skill_range: float) -> Node3D:
	if target and is_instance_valid(target) and not target.is_dead() and _flat_distance(target) <= skill_range + ASSIST_RADIUS:
		return target
	var best: Node3D = null
	var best_d := skill_range + ASSIST_RADIUS
	for m in _monsters_within(skill_range + ASSIST_RADIUS):
		var d := _flat_distance(m)
		if d < best_d:
			best = m
			best_d = d
	return best


func _monsters_within(radius: float) -> Array:
	var result := []
	if not monsters_provider.is_valid():
		return result
	for m in monsters_provider.call():
		if not m.is_dead() and _flat_distance(m) <= radius:
			result.append(m)
	return result


func _flat_distance(node: Node3D) -> float:
	return _flat_distance_to(node.global_position)


func _flat_distance_to(p: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(p.x, p.z))


func _flat_dir_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


func _face(p: Vector3) -> void:
	var d := _flat_dir_to(p)
	if d != Vector3.ZERO:
		_body.rotation.y = atan2(d.x, d.z)


func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)
	_body.add_child(LowPoly.capsule(0.45, 1.6, Color("d9893a"), Vector3(0, 0.8, 0)))
	_body.add_child(LowPoly.box(Vector3(0.12, 0.12, 1.3), Color("d8d8e0"), Vector3(0.45, 0.9, 0.55)))
	_body.add_child(LowPoly.sphere(0.25, Color("f2c48d"), Vector3(0, 1.75, 0)))
	var ring := LowPoly.cylinder(0.75, 0.75, 0.04, Color("ffd27a"), Vector3(0, 0.03, 0), 16)
	add_child(ring)


func _flash_ring(radius: float) -> void:
	var ring := LowPoly.cylinder(radius, radius, 0.05, Color(1.0, 0.75, 0.3, 0.6), Vector3(0, 0.05, 0), 24)
	(ring.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(1.1, 1.0, 1.1), 0.25)
	tween.tween_callback(ring.queue_free)
