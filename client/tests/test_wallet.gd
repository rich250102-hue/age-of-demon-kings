extends RefCounted

var runner


func test_spend_is_all_or_nothing() -> void:
	var w := Wallet.new({"or": 50, "bois": 5})
	runner.check(not w.try_spend({"or": 10, "bois": 10}), "dépense refusée si une ressource manque")
	runner.check_eq(w.get_amount("or"), 50, "l'or ne doit pas bouger")
	runner.check(w.try_spend({"or": 10, "bois": 5}), "dépense acceptée")
	runner.check_eq(w.to_dict(), {"or": 40, "bois": 0})


func test_lose_ratio_caps_losses() -> void:
	var w := Wallet.new({"or": 101, "pierre": 3})
	var lost := w.lose_ratio(0.2)
	runner.check_eq(lost, {"or": 20}, "20 % arrondis vers le bas")
	runner.check_eq(w.get_amount("or"), 81)
	runner.check_eq(w.get_amount("pierre"), 3)


func test_negative_initial_values_are_clamped() -> void:
	var w := Wallet.new({"or": -5})
	runner.check_eq(w.get_amount("or"), 0)
