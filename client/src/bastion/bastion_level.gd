extends Node3D
## Bastion (prototype) : placer des défenses puis repousser un raid démoniaque simulé.

signal navigate(target: String)

const CELL := 2.0
const STEP_SECONDS := RaidSim.TICK_SECONDS
const RAID_ID := "raid_1"

var grid: BastionGrid
var rig := CameraRig.new()
var hud := Hud.new()
var selected_building := "tour"
var removing := false

var _building_nodes: Dictionary = {}   # Vector2i -> Node3D
var _enemy_nodes: Dictionary = {}      # id -> Node3D
var _sim: RaidSim
var _sim_accumulator := 0.0
var _core_label: Label3D
var _mode_buttons: Dictionary = {}
var _raid_button: Button
var _raid_result: Dictionary = {}
var _busy := false


func _ready() -> void:
	grid = BastionGrid.from_layout(Profile.bastion_layout)
	add_child(LowPoly.environment())
	add_child(LowPoly.sun())
	_build_board()
	for b in grid.buildings():
		_spawn_building_node(String(b.id), Vector2i(int(b.x), int(b.y)))
	var center := Node3D.new()
	add_child(center)
	rig.target = center
	rig.distance = 30.0
	add_child(rig)
	add_child(hud)
	hud.setup([], "Aller en forêt", false)
	hud.joystick.visible = false
	hud.navigate_pressed.connect(func(): navigate.emit("forest"))
	_build_toolbar()
	hud.set_status("Bastion : placez vos défenses, puis lancez le raid")


func _process(delta: float) -> void:
	if _sim == null:
		return
	_sim_accumulator += delta
	while _sim_accumulator >= STEP_SECONDS and not _sim.finished:
		_sim_accumulator -= STEP_SECONDS
		_sim.step()
		_render_events()
	_render_enemies(delta)
	_core_label.text = "Cœur %d" % _sim.core_hp
	if _sim.finished:
		_finish_raid()


func _unhandled_input(event: InputEvent) -> void:
	if _sim != null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Variant = rig.ground_point(event.position)
		if p != null:
			_on_cell_tapped(world_to_cell(p))


func world_to_cell(p: Vector3) -> Vector2i:
	var half := grid.size * CELL / 2.0
	return Vector2i(int(floor((p.x + half) / CELL)), int(floor((p.z + half) / CELL)))


func cell_to_world(cell: Vector2i) -> Vector3:
	var half := grid.size * CELL / 2.0
	return Vector3(cell.x * CELL - half + CELL / 2.0, 0.0, cell.y * CELL - half + CELL / 2.0)


func _on_cell_tapped(cell: Vector2i) -> void:
	if not grid.in_bounds(cell) or _busy:
		return
	_busy = true  # une seule demande à la fois (le serveur peut mettre un instant à répondre)
	if removing:
		if grid.building_at(cell) != "" and grid.building_at(cell) != BastionGrid.CORE_ID:
			var res: Dictionary = await Profile.remove_building(cell)
			if res.ok:
				grid.remove(cell)
				_building_nodes[cell].queue_free()
				_building_nodes.erase(cell)
			else:
				hud.show_message(Profile.error_text(res.error))
		_busy = false
		return
	if not grid.can_place(cell):
		hud.show_message(Profile.error_text("case_interdite"))
		_busy = false
		return
	var building := selected_building
	var res: Dictionary = await Profile.place_building(building, cell)
	if res.ok:
		grid.place(building, cell)
		_spawn_building_node(building, cell)
	elif res.error == "ressources_insuffisantes":
		hud.show_message("Ressources insuffisantes : %s" % _cost_text(GameData.buildings.get(building, {}).get("cost", {})))
	else:
		hud.show_message(Profile.error_text(res.error))
	_busy = false


func _start_raid() -> void:
	if _sim != null or _busy:
		return
	_busy = true
	_raid_button.disabled = true
	var res: Dictionary = await Profile.launch_raid(RAID_ID)
	_busy = false
	if not res.get("ok", false):
		_raid_button.disabled = false
		hud.show_message(Profile.error_text(String(res.get("error", ""))))
		return
	# On rejoue exactement le raid décidé (par le serveur en ligne), avec la même graine.
	_raid_result = res
	_sim = RaidSim.new(grid, GameData.raids[RAID_ID], GameData.buildings, int(res.seed))
	_sim_accumulator = 0.0
	hud.set_status("Raid en cours : %s" % String(GameData.raids[RAID_ID].name))


func _finish_raid() -> void:
	if _sim.victory != bool(_raid_result.victory):
		push_error("Le raid affiché diverge du résultat officiel (graine %d)" % int(_raid_result.seed))
	Profile.apply_raid(_raid_result)
	if _raid_result.victory:
		hud.show_message("Victoire ! Butin : %s" % _cost_text(_raid_result.loot))
	else:
		var lost: Dictionary = _raid_result.lost
		hud.show_message("Défaite. Pillé : %s" % (_cost_text(lost) if not lost.is_empty() else "rien"))
	for id in _enemy_nodes:
		_enemy_nodes[id].queue_free()
	_enemy_nodes.clear()
	# Le bastion réel est celui du profil : les défenses détruites pendant le raid reviennent.
	for cell in _building_nodes:
		_building_nodes[cell].visible = true
	_sim = null
	_raid_result = {}
	_raid_button.disabled = false
	_core_label.text = "Cœur"
	hud.set_status("Bastion : placez vos défenses, puis lancez le raid")


func _render_events() -> void:
	for e in _sim.events:
		match String(e.type):
			"shot":
				_shot(cell_to_world(e.from) + Vector3(0, 2.2, 0), cell_to_world(e.to) + Vector3(0, 0.6, 0))
			"structure_destroyed", "trap":
				if _building_nodes.has(e.cell):
					_building_nodes[e.cell].visible = false


func _render_enemies(delta: float) -> void:
	var alive := {}
	for e in _sim.enemies:
		alive[e.id] = true
		if not _enemy_nodes.has(e.id):
			var n := LowPoly.capsule(0.35, 0.9, Color("a63d8f"), Vector3.ZERO)
			n.position = cell_to_world(e.cell) + Vector3(0, 0.45, 0)
			add_child(n)
			_enemy_nodes[e.id] = n
		var node: Node3D = _enemy_nodes[e.id]
		node.position = node.position.lerp(cell_to_world(e.cell) + Vector3(0, 0.45, 0), clampf(8.0 * delta, 0.0, 1.0))
	for id in _enemy_nodes.keys():
		if not alive.has(id):
			_enemy_nodes[id].queue_free()
			_enemy_nodes.erase(id)


func _shot(from: Vector3, to: Vector3) -> void:
	var bolt := LowPoly.sphere(0.15, Color("ffe08a"), from, 2.0)
	add_child(bolt)
	var t := create_tween()
	t.tween_property(bolt, "position", to, 0.12)
	t.tween_callback(bolt.queue_free)


func _spawn_building_node(id: String, cell: Vector2i) -> void:
	var node := Node3D.new()
	match id:
		"tour":
			node.add_child(LowPoly.cylinder(0.6, 0.75, 2.2, Color("b8a58a"), Vector3(0, 1.1, 0), 8))
			node.add_child(LowPoly.cylinder(0.0, 0.85, 0.9, Color("8b3a2a"), Vector3(0, 2.65, 0), 8))
		"mur":
			node.add_child(LowPoly.box(Vector3(CELL * 0.95, 1.2, CELL * 0.95), Color("8d8477"), Vector3(0, 0.6, 0)))
		"piege":
			for i in 4:
				node.add_child(LowPoly.cylinder(0.0, 0.12, 0.4, Color("c9c9d1"), Vector3(-0.4 + i * 0.27, 0.2, 0.0), 4))
	node.position = cell_to_world(cell)
	add_child(node)
	_building_nodes[cell] = node


func _build_board() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(grid.size * CELL + 8.0, grid.size * CELL + 8.0)
	add_child(LowPoly.mesh(plane, Color("4a3a5c"), Vector3(0, -0.02, 0)))
	for x in grid.size:
		for y in grid.size:
			var edge := x == 0 or y == 0 or x == grid.size - 1 or y == grid.size - 1
			var color := Color("3b2f49") if edge else (Color("6f8a5a") if (x + y) % 2 == 0 else Color("67824f"))
			add_child(LowPoly.box(Vector3(CELL * 0.96, 0.1, CELL * 0.96), color, cell_to_world(Vector2i(x, y))))
	var core_center := (cell_to_world(grid.core_cells()[0]) + cell_to_world(grid.core_cells()[3])) / 2.0
	add_child(LowPoly.box(Vector3(CELL * 1.8, 1.6, CELL * 1.8), Color("8d7a62"), core_center + Vector3(0, 0.8, 0)))
	add_child(LowPoly.sphere(0.7, Color("ffcf6b"), core_center + Vector3(0, 2.4, 0), 2.5))
	_core_label = Label3D.new()
	_core_label.text = "Cœur"
	_core_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_core_label.font_size = 48
	_core_label.pixel_size = 0.015
	_core_label.outline_size = 10
	_core_label.no_depth_test = true
	_core_label.position = core_center + Vector3(0, 3.6, 0)
	add_child(_core_label)


func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -470
	bar.offset_right = 470
	bar.offset_top = -110
	bar.offset_bottom = -20
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	hud.ui_root.add_child(bar)
	for id in GameData.buildings:
		var def: Dictionary = GameData.buildings[id]
		var b := Button.new()
		b.toggle_mode = true
		b.text = "%s\n%s" % [String(def.name), _cost_text(def.cost)]
		b.custom_minimum_size = Vector2(170, 86)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_mode.bind(String(id)))
		bar.add_child(b)
		_mode_buttons[id] = b
	var remove := Button.new()
	remove.toggle_mode = true
	remove.text = "Retirer\n(50 % remboursé)"
	remove.custom_minimum_size = Vector2(170, 86)
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(_select_mode.bind("retirer"))
	bar.add_child(remove)
	_mode_buttons["retirer"] = remove
	_raid_button = Button.new()
	_raid_button.text = "Lancer le raid"
	_raid_button.custom_minimum_size = Vector2(190, 86)
	_raid_button.focus_mode = Control.FOCUS_NONE
	_raid_button.pressed.connect(_start_raid)
	bar.add_child(_raid_button)
	_select_mode("tour")


func _select_mode(mode: String) -> void:
	removing = mode == "retirer"
	if not removing:
		selected_building = mode
	for id in _mode_buttons:
		_mode_buttons[id].button_pressed = id == mode


static func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(parts)
