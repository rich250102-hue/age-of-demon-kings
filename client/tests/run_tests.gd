extends SceneTree
## Lanceur de tests minimal, sans dépendance externe.
## Utilisation : godot --headless --path client --script res://tests/run_tests.gd
## Toute erreur de script pendant un test (erreur de parse, appel invalide...) compte comme un échec.

const TEST_DIR := "res://tests/"


class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		_mutex.lock()
		var copy := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return copy


var _failures: Array[String] = []
var _current := ""
var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_catcher)
	var total := 0
	for file_name in DirAccess.get_files_at(TEST_DIR):
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		_current = file_name
		var script: Script = load(TEST_DIR + file_name)
		if script == null or not script.can_instantiate():
			_failures.append("%s : le script ne compile pas %s" % [file_name, str(_catcher.take())])
			print("  ECHEC " + file_name + " (compilation)")
			continue
		_catcher.take()
		var suite: Object = script.new()
		suite.set("runner", self)
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			_current = "%s::%s" % [file_name, name]
			var before := _failures.size()
			suite.call(name)
			for err in _catcher.take():
				_failures.append("%s : erreur de script %s" % [_current, err])
			total += 1
			print(("  OK    " if _failures.size() == before else "  ECHEC ") + _current)
	print("\n%d tests, %d échec(s)" % [total, _failures.size()])
	for f in _failures:
		print("  - " + f)
	OS.remove_logger(_catcher)
	quit(0 if _failures.is_empty() else 1)


func check(condition: bool, message: String = "") -> void:
	if not condition:
		_failures.append("%s : %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_failures.append("%s : %s (obtenu %s, attendu %s)" % [_current, message, str(actual), str(expected)])
