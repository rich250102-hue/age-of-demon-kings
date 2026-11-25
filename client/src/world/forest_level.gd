extends Node3D
## Forêt des Cendres (prototype) : chasser les démons, vaincre le Gardien, libérer la forêt.

signal navigate(target: String)

const PICK_RADIUS_PX := 70.0  # ciblage assisté au toucher ou au clic
const CAMPS := [
	{"id": "diablotin", "center": Vector3(10, 0, 4), "count": 4},
	{"id": "diablotin", "center": Vector3(-8, 0, 12), "count": 4},
	{"id": "molosse", "center": Vector3(16, 0, -14), "count": 3},
	{"id": "molosse", "center": Vector3(-16, 0, -10), "count": 3},
	{"id": "gardien", "center": Vector3(0, 0, -28), "count": 1},
]

var hero := Hero.new()
var rig := CameraRig.new()
var hud := Hud.new()
var monsters: Array[Monster] = []
var corruption := 100.0
var liberated := false

var _ground_material: StandardMaterial3D
var _trees: Array[Node3D] = []
var _keyboard_ready := false


func _ready() -> void:
	_ensure_input_actions()
	add_child(LowPoly.environment())
	add_child(LowPoly.sun())
	_build_ground()
	_build_decor()
	hero.spawn_point = Vector3.ZERO
	hero.monsters_provider = func(): return monsters
	add_child(hero)
	_spawn_monsters()
	rig.target = hero
	add_child(rig)
	add_child(hud)
	hud.setup(hero.skills, "Mon bastion")
	hud.skill_pressed.connect(hero.use_skill)
	hud.navigate_pressed.connect(func(): navigate.emit("bastion"))
	EventBus.monster_killed.connect(_on_monster_killed)
	_update_status()
	EventBus.hero_health_changed.emit(hero.hp, int(hero.stats.max_hp))


func _process(_delta: float) -> void:
	var keys: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var stick: Vector2 = hud.joystick.output
	var dir2: Vector2 = stick if stick.length() > keys.length() else keys
	hero.input_direction = rig.screen_to_world_direction(dir2)


func _unhandled_input(event: InputEvent) -> void:
	for slot in range(1, 6):
		if event.is_action_pressed("skill_%d" % slot):
			hero.use_skill(slot)
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap(event.position)


func _on_tap(screen_pos: Vector2) -> void:
	var picked := _pick_monster(screen_pos)
	if picked:
		hero.target = picked
		hero.move_target = null
		return
	var p: Variant = rig.ground_point(screen_pos)
	if p != null:
		hero.target = null
		hero.move_target = p
		_tap_marker(p)


func _pick_monster(screen_pos: Vector2) -> Monster:
	var best: Monster = null
	var best_d := PICK_RADIUS_PX
	for m in monsters:
		if m.is_dead() or rig.camera.is_position_behind(m.global_position):
			continue
		var sp := rig.camera.unproject_position(m.global_position + Vector3(0, 0.6, 0))
		var d := sp.distance_to(screen_pos)
		if d < best_d:
			best = m
			best_d = d
	return best


func _spawn_monsters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var n := 0
	for camp in CAMPS:
		for i in int(camp.count):
			var m := Monster.new()
			var offset := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)) if int(camp.count) > 1 else Vector3.ZERO
			m.setup(String(camp.id), camp.center + offset, hero, 1000 + n)
			n += 1
			add_child(m)
			monsters.append(m)


func _on_monster_killed(id: String, gold: int) -> void:
	hud.show_message("+%d or" % gold)
	if liberated:
		return
	if GameData.monsters.get(id, {}).get("boss", false):
		set_liberated(true)
	else:
		corruption = maxf(10.0, corruption - 1.5)
		_update_status()


func set_liberated(value: bool) -> void:
	liberated = value
	corruption = 0.0 if value else 100.0
	var t := create_tween()
	t.tween_property(_ground_material, "albedo_color", Color("5f8f4e") if value else Color("4a3a5c"), 2.0)
	for tree in _trees:
		var leaves: MeshInstance3D = tree.get_meta("leaves")
		t.parallel().tween_property(leaves.material_override, "albedo_color", Color("3f8a4a") if value else Color("6b3f86"), 2.0)
	EventBus.forest_state_changed.emit(value, corruption)
	hud.show_message("La forêt est libérée !" if value else "La forêt est retombée aux mains des démons")
	_update_status()


func _update_status() -> void:
	if liberated:
		hud.set_status("Forêt des Cendres : libérée")
	else:
		hud.set_status("Forêt des Cendres : corruption %d %%  (vainquez le Gardien au nord)" % int(corruption))


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(84, 84)
	var ground := LowPoly.mesh(plane, Color("4a3a5c"))
	_ground_material = ground.material_override
	add_child(ground)
	var sanctuary := LowPoly.cylinder(4.0, 4.0, 0.08, Color("8f7440"), Vector3(0, 0.04, 0), 24)
	add_child(sanctuary)
	add_child(LowPoly.sphere(0.5, Color("ffd88a"), Vector3(0, 3.2, 0), 3.0))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3, 0)
	light.light_color = Color("ffd88a")
	light.omni_range = 7.0
	light.light_energy = 0.6
	add_child(light)


func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		var p := Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40))
		if p.length() < 7.0 or _near_camp(p):
			continue
		var tree := LowPoly.tree(rng, true)
		tree.position = p
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)
		_trees.append(tree)
	for i in 25:
		var p := Vector3(rng.randf_range(-40, 40), 0.2, rng.randf_range(-40, 40))
		if p.length() > 6.0:
			add_child(LowPoly.sphere(rng.randf_range(0.4, 1.0), Color("6d6475"), p))


func _near_camp(p: Vector3) -> bool:
	for camp in CAMPS:
		if p.distance_to(camp.center) < 6.0:
			return true
	return false


func _tap_marker(p: Vector3) -> void:
	var marker := LowPoly.cylinder(0.5, 0.5, 0.03, Color("ffe08a"), p + Vector3(0, 0.03, 0), 16)
	add_child(marker)
	var t := create_tween()
	t.tween_property(marker, "scale", Vector3(0.1, 1, 0.1), 0.35)
	t.tween_callback(marker.queue_free)


static func _ensure_input_actions() -> void:
	var map := {
		# Touches physiques : WASD en QWERTY correspond à ZQSD en AZERTY.
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"skill_1": [KEY_1], "skill_2": [KEY_2], "skill_3": [KEY_3], "skill_4": [KEY_4], "skill_5": [KEY_R],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in map[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
