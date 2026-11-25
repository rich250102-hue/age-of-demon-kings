extends RefCounted

var runner
var _data := preload("res://src/core/game_data.gd")


func _buildings() -> Dictionary:
	return _data.load_json("buildings.json")


func _raid() -> Dictionary:
	return _data.load_json("raids.json").raid_1


func test_cannot_build_on_edges_or_core() -> void:
	var g := BastionGrid.new(12)
	runner.check(not g.place("tour", Vector2i(0, 4)), "bord interdit")
	runner.check(not g.place("tour", Vector2i(5, 5)), "cœur interdit")
	runner.check(g.place("tour", Vector2i(3, 3)))
	runner.check(not g.place("mur", Vector2i(3, 3)), "case déjà occupée")


func test_layout_round_trip() -> void:
	var g := BastionGrid.new(12)
	g.place("tour", Vector2i(3, 3))
	g.place("mur", Vector2i(4, 2))
	var copy := BastionGrid.from_layout(g.to_layout())
	runner.check_eq(copy.to_layout(), g.to_layout())


func test_raid_is_deterministic() -> void:
	var g := BastionGrid.new(12)
	for cell in [Vector2i(3, 3), Vector2i(8, 3), Vector2i(3, 8), Vector2i(8, 8)]:
		g.place("tour", cell)
	var a := RaidSim.new(g, _raid(), _buildings(), 42).run_to_end()
	var b := RaidSim.new(g, _raid(), _buildings(), 42).run_to_end()
	runner.check_eq(a, b, "même graine, même résultat")
	runner.check(a.finished)


func test_empty_bastion_loses() -> void:
	var r := RaidSim.new(BastionGrid.new(12), _raid(), _buildings(), 7).run_to_end()
	runner.check(r.finished and not r.victory, "sans défense, le cœur tombe")
	runner.check_eq(r.core_hp, 0)


func test_well_defended_bastion_wins() -> void:
	var g := BastionGrid.new(12)
	for x in [2, 4, 7, 9]:
		for y in [2, 4, 7, 9]:
			g.place("tour", Vector2i(x, y))
	var r := RaidSim.new(g, _raid(), _buildings(), 7).run_to_end()
	runner.check(r.victory, "16 tours doivent tenir le premier raid (résultat : %s)" % str(r))


func test_raid_always_terminates() -> void:
	for seed_value in range(20):
		var r := RaidSim.new(BastionGrid.new(12), _raid(), _buildings(), seed_value).run_to_end()
		runner.check(r.finished and r.ticks <= RaidSim.MAX_TICKS)
