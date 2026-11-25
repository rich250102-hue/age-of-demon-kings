extends Node
## Point d'entrée : bascule entre la forêt et le bastion.

const ForestLevel := preload("res://src/world/forest_level.gd")
const BastionLevel := preload("res://src/bastion/bastion_level.gd")

var _current: Node


func _ready() -> void:
	show_forest()


func show_forest() -> void:
	_switch(ForestLevel.new())


func show_bastion() -> void:
	_switch(BastionLevel.new())


func _switch(level: Node) -> void:
	if _current:
		_current.queue_free()
	_current = level
	add_child(level)
	if level.has_signal("navigate"):
		level.navigate.connect(_on_navigate)


func _on_navigate(target: String) -> void:
	if target == "bastion":
		show_bastion.call_deferred()
	else:
		show_forest.call_deferred()
