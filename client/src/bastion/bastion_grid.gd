class_name BastionGrid
extends RefCounted
## Grille du bastion : où l'on peut construire. Logique pure.

const CORE_ID := "coeur"

var size: int
var _cells: Dictionary = {}  # Vector2i -> building id


func _init(grid_size: int = 12) -> void:
	size = grid_size
	for cell in core_cells():
		_cells[cell] = CORE_ID


func core_cells() -> Array[Vector2i]:
	var c := int(size / 2.0)
	return [Vector2i(c - 1, c - 1), Vector2i(c, c - 1), Vector2i(c - 1, c), Vector2i(c, c)]


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size


func is_free(cell: Vector2i) -> bool:
	return in_bounds(cell) and not _cells.has(cell)


func building_at(cell: Vector2i) -> String:
	return String(_cells.get(cell, ""))


## Les bords restent libres : c'est par là qu'arrivent les démons.
func can_place(cell: Vector2i) -> bool:
	return is_free(cell) and cell.x > 0 and cell.y > 0 and cell.x < size - 1 and cell.y < size - 1


func place(building_id: String, cell: Vector2i) -> bool:
	if not can_place(cell):
		return false
	_cells[cell] = building_id
	return true


func remove(cell: Vector2i) -> String:
	var id := building_at(cell)
	if id == "" or id == CORE_ID:
		return ""
	_cells.erase(cell)
	return id


func buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in _cells:
		if _cells[cell] != CORE_ID:
			result.append({"id": _cells[cell], "x": cell.x, "y": cell.y})
	result.sort_custom(func(a, b): return a.y * size + a.x < b.y * size + b.x)
	return result


func to_layout() -> Array:
	return buildings()


static func from_layout(layout: Array, grid_size: int = 12) -> BastionGrid:
	var grid := BastionGrid.new(grid_size)
	for entry in layout:
		grid.place(String(entry.get("id", "")), Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1))))
	return grid
