class_name Hud
extends CanvasLayer
## Interface commune mobile et PC : vie, ressources, compétences, joystick, messages.

signal skill_pressed(slot: int)
signal navigate_pressed

var joystick := TouchStick.new()
var _hp_bar := ProgressBar.new()
var _hp_label := Label.new()
var _resources := Label.new()
var _status := Label.new()
var _message := Label.new()
var _skill_buttons: Array[Button] = []
var _skill_names: Array[String] = []
var _cooldown_end: Array[float] = []
var _message_tween: Tween
## Racine des contrôles de l'interface : y ajouter les barres propres à chaque écran pour hériter du thème.
var ui_root: Control


func setup(skills: Array[Dictionary], nav_label: String, show_health := true) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Un CanvasLayer coupe l'héritage du thème de la fenêtre : on le pose ici.
	root.theme = UiTheme.build()
	add_child(root)
	ui_root = root

	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	_hp_bar.custom_minimum_size = Vector2(260, 26)
	_hp_bar.show_percentage = false
	_style_bar(_hp_bar, Color("c0392b"))
	top.add_child(_hp_bar)
	_hp_label.add_theme_font_size_override("font_size", 20)
	top.add_child(_hp_label)
	top.visible = show_health

	_resources.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_resources.offset_left = -560
	_resources.offset_right = -16
	_resources.offset_top = 12
	_resources.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_resources.add_theme_font_size_override("font_size", 20)
	root.add_child(_resources)

	var nav := Button.new()
	nav.text = nav_label
	nav.custom_minimum_size = Vector2(170, 56)
	nav.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	nav.offset_left = -186
	nav.offset_right = -16
	nav.offset_top = 46
	nav.offset_bottom = 102
	nav.pressed.connect(func(): navigate_pressed.emit())
	root.add_child(nav)

	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status.offset_top = 48
	_status.offset_left = -300
	_status.offset_right = 300
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	root.add_child(_status)

	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_message.offset_top = -190
	_message.offset_bottom = -150
	_message.offset_left = -400
	_message.offset_right = 400
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.modulate.a = 0.0
	root.add_child(_message)

	joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joystick.offset_left = 24
	joystick.offset_top = -244
	joystick.offset_right = 244
	joystick.offset_bottom = -24
	joystick.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	root.add_child(joystick)

	_build_skill_bar(root, skills)
	EventBus.hero_health_changed.connect(_on_health)
	EventBus.resources_changed.connect(_on_resources)
	EventBus.message.connect(show_message)
	EventBus.skill_used.connect(_on_skill_used)
	_on_resources(Profile.wallet.to_dict())


func set_status(text: String) -> void:
	_status.text = text


func show_message(text: String) -> void:
	_message.text = text
	if _message_tween:
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message_tween = create_tween()
	_message_tween.tween_interval(1.6)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in _skill_buttons.size():
		var left := _cooldown_end[i] - now
		_skill_buttons[i].text = "%s\n%.0f s" % [_skill_names[i], ceilf(left)] if left > 0.0 else _skill_names[i]
		# Bouton grisé mais opaque pendant la recharge : le décor ne doit pas transparaître.
		_skill_buttons[i].self_modulate = Color(0.55, 0.55, 0.6) if left > 0.0 else Color.WHITE


func _build_skill_bar(root: Control, skills: Array[Dictionary]) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.offset_left = -16 - 5 * 128
	bar.offset_top = -136
	bar.offset_right = -16
	bar.offset_bottom = -16
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	var keys := ["1", "2", "3", "4", "R"]
	for i in skills.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 120)
		b.focus_mode = Control.FOCUS_NONE
		var label := "%s\n[%s]" % [String(skills[i].name), keys[i]] if i < keys.size() else String(skills[i].name)
		b.text = label
		b.add_theme_font_size_override("font_size", 17)
		var slot := i + 1
		b.pressed.connect(func(): skill_pressed.emit(slot))
		bar.add_child(b)
		_skill_buttons.append(b)
		_skill_names.append(label)
		_cooldown_end.append(0.0)


func _on_health(current: int, maximum: int) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current
	_hp_label.text = "PV %d / %d" % [current, maximum]


func _on_resources(r: Dictionary) -> void:
	_resources.text = "Or %d   Bois %d   Pierre %d" % [int(r.get("or", 0)), int(r.get("bois", 0)), int(r.get("pierre", 0))]


func _on_skill_used(slot: int, cooldown: float) -> void:
	if slot >= 1 and slot <= _cooldown_end.size():
		_cooldown_end[slot - 1] = Time.get_ticks_msec() / 1000.0 + cooldown


func _style_bar(bar: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
