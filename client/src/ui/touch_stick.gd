class_name TouchStick
extends Control
## Joystick tactile multi-doigts. Renvoie une direction de longueur 0 à 1.

var output := Vector2.ZERO
var radius := 90.0

var _touch_index := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.4, radius * 2.4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center = size / 2.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var local: Vector2 = event.position - global_position
		if event.pressed and _touch_index == -1 and Rect2(Vector2.ZERO, size).has_point(local):
			_touch_index = event.index
			_update(local)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			output = Vector2.ZERO
			_knob = Vector2.ZERO
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position - global_position)
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return _touch_index != -1


func _update(local: Vector2) -> void:
	_center = size / 2.0
	var offset := (local - _center).limit_length(radius)
	_knob = offset
	output = offset / radius
	queue_redraw()


func _draw() -> void:
	_center = size / 2.0
	draw_circle(_center, radius, Color(1, 1, 1, 0.12))
	draw_arc(_center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(_center + _knob, radius * 0.4, Color(1, 0.85, 0.5, 0.55))
