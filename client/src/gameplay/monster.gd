class_name Monster
extends Node3D
## Démon de la forêt : patrouille, poursuit le héros, l'attaque, puis réapparaît.

signal died(monster: Monster)

var monster_id := "diablotin"
var def: Dictionary = {}
var hp := 1
var max_hp := 1
var hero: Hero
var home := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var _attack_timer := 0.0
var _respawn_timer := -1.0
var _label: Label3D
var _body: Node3D


func setup(id: String, position_home: Vector3, p_hero: Hero, seed_value: int) -> void:
	monster_id = id
	home = position_home
	hero = p_hero
	rng.seed = seed_value


func _ready() -> void:
	def = GameData.monsters.get(monster_id, {})
	max_hp = int(def.get("hp", 10))
	hp = max_hp
	position = home
	_build_body()
	_update_label()


func is_dead() -> bool:
	return hp <= 0


func is_boss() -> bool:
	return bool(def.get("boss", false))


func defense() -> int:
	return int(def.get("defense", 0))


func _process(delta: float) -> void:
	if is_dead():
		if _respawn_timer > 0.0:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				_respawn()
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	var speed := float(def.get("speed", 3.0))
	if hero and not hero.is_dead() and _dist(hero.global_position) <= float(def.get("aggro_range", 8.0)) and _dist_home() < 20.0:
		if _dist(hero.global_position) > float(def.get("attack_range", 1.6)):
			_step_towards(hero.global_position, speed, delta)
		elif _attack_timer <= 0.0:
			_attack_timer = float(def.get("attack_interval", 1.5))
			hero.take_damage(int(def.get("attack", 5)))
			_lunge()
	elif _dist_home() > 0.5:
		_step_towards(home, speed * 0.8, delta)


func take_damage(amount: int, crit: bool) -> void:
	if is_dead():
		return
	hp = maxi(0, hp - amount)
	_update_label()
	_popup("%d%s" % [amount, " !" if crit else ""], Color("ffd34d") if crit else Color.WHITE)
	if is_dead():
		_die()


func _die() -> void:
	EventBus.monster_killed.emit(monster_id)
	_claim_loot()
	visible = false
	var respawn := float(def.get("respawn", 10.0))
	_respawn_timer = respawn if respawn > 0.0 else -1.0
	died.emit(self)


func _respawn() -> void:
	hp = max_hp
	position = home
	visible = true
	_update_label()


func _step_towards(p: Vector3, speed: float, delta: float) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	var step := d.normalized() * minf(speed * delta, d.length())
	global_position += step
	_body.rotation.y = atan2(d.x, d.z)


func _dist(p: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(p.x, p.z))


func _dist_home() -> float:
	return _dist(home)


func _build_body() -> void:
	var s := float(def.get("scale", 1.0))
	var color := Color(String(def.get("color", "#a63d8f")))
	_body = Node3D.new()
	add_child(_body)
	_body.add_child(LowPoly.capsule(0.4 * s, 1.0 * s, color, Vector3(0, 0.5 * s, 0)))
	_body.add_child(LowPoly.cylinder(0.0, 0.1 * s, 0.35 * s, Color("e9d9c0"), Vector3(-0.2 * s, 1.1 * s, 0)))
	_body.add_child(LowPoly.cylinder(0.0, 0.1 * s, 0.35 * s, Color("e9d9c0"), Vector3(0.2 * s, 1.1 * s, 0)))
	_body.add_child(LowPoly.sphere(0.08 * s, Color("ff4d3d"), Vector3(0.12 * s, 0.75 * s, 0.33 * s), 2.0))
	_body.add_child(LowPoly.sphere(0.08 * s, Color("ff4d3d"), Vector3(-0.12 * s, 0.75 * s, 0.33 * s), 2.0))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 1.6 * s + 0.4, 0)
	_label.font_size = 40 if is_boss() else 30
	_label.pixel_size = 0.012
	_label.outline_size = 8
	_label.no_depth_test = true
	add_child(_label)


func _update_label() -> void:
	if _label:
		_label.text = ("%s  %d / %d" % [String(def.get("name", monster_id)), hp, max_hp]) if is_boss() or hp < max_hp else "%d" % hp


func _popup(text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.014
	l.outline_size = 10
	l.no_depth_test = true
	l.position = Vector3(0, 2.0 * float(def.get("scale", 1.0)), 0)
	add_child(l)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(l, "position:y", l.position.y + 1.2, 0.7)
	tween.tween_property(l, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(l.queue_free)


func _lunge() -> void:
	var tween := create_tween()
	tween.tween_property(_body, "scale", Vector3(1.15, 0.9, 1.15), 0.08)
	tween.tween_property(_body, "scale", Vector3.ONE, 0.12)


## Le butin est demandé au profil (au serveur en ligne) ; le combat continue sans l'attendre.
func _claim_loot() -> void:
	var res: Dictionary = await Profile.loot_monster(monster_id, rng.randf())
	if res.get("ok", false):
		EventBus.loot_received.emit(monster_id, int(res.get("gold", 0)))
	else:
		EventBus.loot_refused.emit(Profile.error_text(String(res.get("error", ""))))
