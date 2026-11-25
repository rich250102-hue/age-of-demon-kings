extends RefCounted

var runner


func test_damage_never_below_minimum() -> void:
	var r := CombatRules.compute_damage(1, 500, 0.1, 0.0, 0.9)
	runner.check_eq(r.amount, CombatRules.MIN_DAMAGE)


func test_defense_reduces_damage() -> void:
	var low: int = CombatRules.compute_damage(50, 0, 1.0, 0.0, 0.9).amount
	var high: int = CombatRules.compute_damage(50, 20, 1.0, 0.0, 0.9).amount
	runner.check(high < low, "plus de défense = moins de dégâts")
	runner.check_eq(low, 50)


func test_crit_multiplies_damage() -> void:
	var normal := CombatRules.compute_damage(40, 0, 1.0, 0.1, 0.5)
	var crit := CombatRules.compute_damage(40, 0, 1.0, 0.1, 0.05)
	runner.check(not normal.crit and crit.crit)
	runner.check_eq(crit.amount, 60)


func test_derived_stats_grow_with_level() -> void:
	var base := {"force": 8, "agilite": 5, "vigueur": 8, "esprit": 2, "precision": 5}
	var l1 := CombatRules.derive_stats(base, 1)
	var l10 := CombatRules.derive_stats(base, 10)
	runner.check(l10.max_hp > l1.max_hp and l10.attack > l1.attack)
	runner.check_eq(l1.max_hp, 80 + 8 * 12 + 10)


func test_gold_roll_stays_in_range() -> void:
	for roll in [0.0, 0.25, 0.5, 0.99999, 1.0]:
		var g := CombatRules.roll_gold([3, 6], roll)
		runner.check(g >= 3 and g <= 6, "or hors limites pour %s" % roll)
	runner.check_eq(CombatRules.roll_gold([3, 6], 0.0), 3)
	runner.check_eq(CombatRules.roll_gold([3, 6], 0.999), 6)


func test_cooldowns_tick_down() -> void:
	var c := Cooldowns.new()
	c.start("frappe", 3.0)
	runner.check(not c.is_ready("frappe"))
	c.tick(1.0)
	runner.check(is_equal_approx(c.remaining("frappe"), 2.0))
	c.tick(5.0)
	runner.check(c.is_ready("frappe"))
	runner.check(c.is_ready("inconnu"), "une compétence jamais lancée est prête")
