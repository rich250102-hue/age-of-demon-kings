class_name CameraRig
extends Node3D
## Caméra isométrique 2.5D qui suit une cible. Zoom : molette (PC) ou pincement (tactile).

const MIN_DISTANCE := 10.0
const MAX_DISTANCE := 32.0

var target: Node3D
var distance := 20.0
var follow_speed := 8.0
var camera := Camera3D.new()

var _touches: Dictionary = {}
var _pinch_start := 0.0
var _distance_start := 0.0


func _ready() -> void:
	rotation_degrees = Vector3(0, 45, 0)
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 200.0
	add_child(camera)
	_apply_distance()
	if target:
		global_position = target.global_position


func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, clampf(follow_speed * delta, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_distance(distance - 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_distance(distance + 1.5)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			_pinch_start = _touch_spread()
			_distance_start = distance
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch_start > 0.0:
			set_distance(_distance_start * _pinch_start / maxf(1.0, _touch_spread()))


func set_distance(value: float) -> void:
	distance = clampf(value, MIN_DISTANCE, MAX_DISTANCE)
	_apply_distance()


## Point du sol (y = 0) sous une position de l'écran, ou null.
func ground_point(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


## Direction du joystick ou du clavier convertie en direction dans le monde, relative à la caméra.
func screen_to_world_direction(input: Vector2) -> Vector3:
	var dir := Vector3(input.x, 0.0, input.y)
	return dir.rotated(Vector3.UP, rotation.y)


func _apply_distance() -> void:
	var pitch := deg_to_rad(52.0)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


func _touch_spread() -> float:
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)
