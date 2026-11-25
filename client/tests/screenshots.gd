extends SceneTree
## Capture des images du jeu pour vérifier le rendu (nécessite un affichage, réel ou virtuel).
## Utilisation : godot --path client --rendering-driver opengl3 --script res://tests/screenshots.gd -- <dossier>

var _frame := 0
var _main: Node
var _out := "user://screenshots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("Profile").reset()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	var level: Node = _main.get_child(0)
	match _frame:
		10:
			level.hero.global_position = Vector3(6, 0, 3)
			level.hero.target = level.monsters[0]
		90:
			_shot("1_foret.png")
			for m in level.monsters:
				m.take_damage(99999, false)
		200:
			_shot("2_foret_liberee.png")
			root.get_node("Profile").add({"or": 2000, "bois": 900, "pierre": 900})
			level.navigate.emit("bastion")
		215:
			for c in [Vector2i(3, 3), Vector2i(8, 3), Vector2i(3, 8), Vector2i(8, 8), Vector2i(5, 3), Vector2i(3, 5)]:
				level._on_cell_tapped(c)
			level._select_mode("mur")
			for c in [Vector2i(5, 8), Vector2i(6, 8), Vector2i(8, 5), Vector2i(8, 6)]:
				level._on_cell_tapped(c)
			level._start_raid()
		300:
			_shot("3_bastion_raid.png")
		301:
			root.get_node("Profile").reset()
			quit()
	return false


func _shot(file_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(file_name))
	print("capture : ", _out.path_join(file_name))
