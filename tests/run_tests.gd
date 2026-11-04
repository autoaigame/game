## Runs every tests/**/test_*.gd. Usage: godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree


func _init() -> void:
	var files: Array[String] = []
	_collect("res://tests", files)
	files.sort()
	var passed := 0
	var failed := 0
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: cannot load script" % path)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t: TestCase = script.new()
			t.call(name)
			if t.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in t.failures:
					print("FAIL %s::%s: %s" % [path.get_file(), name, f])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_collect(dir_path.path_join(d), out)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
