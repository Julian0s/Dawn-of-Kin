extends SceneTree
## Minimal headless test runner for Dawn of Kin.
## Discovers test_*.gd suites under tests/unit and tests/integration,
## executes synchronous and async (await) test_* methods, and exits non-zero on any failure.

const SEARCH_ROOTS: Array[String] = [
	"res://tests/unit",
	"res://tests/integration",
]

var _filter: String = ""
var _exact_suites: PackedStringArray = PackedStringArray()
var _discovery_only: bool = false


func _initialize() -> void:
	_parse_args()
	call_deferred("_run_all")


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.substr("--filter=".length()).strip_edges()
		elif arg.begins_with("--suites="):
			var raw: String = arg.substr("--suites=".length()).strip_edges()
			if not raw.is_empty():
				var parts: PackedStringArray = raw.split(",", false)
				for part: String in parts:
					var cleaned: String = part.strip_edges()
					if not cleaned.is_empty() and not _exact_suites.has(cleaned):
						_exact_suites.append(cleaned)
		elif arg == "--discovery-only":
			_discovery_only = true


func _run_all() -> void:
	# Wait one frame so SceneTree root is fully initialized before any test calls get_tree().
	await process_frame

	var started_usec: int = Time.get_ticks_usec()
	var suite_paths: PackedStringArray = _discover_suites()

	if _discovery_only:
		for path: String in suite_paths:
			print("DISCOVERED_SUITE %s" % path)
		print("DISCOVERED_COUNT %d" % suite_paths.size())
		quit(0)
		return

	if not _exact_suites.is_empty():
		var filtered_paths: Array[String] = []
		for requested_path: String in _exact_suites:
			if suite_paths.has(requested_path):
				filtered_paths.append(requested_path)
			else:
				push_error("Requested suite not discovered: %s" % requested_path)
				quit(1)
				return
		suite_paths = PackedStringArray(filtered_paths)

	var total_suites: int = 0
	var total_tests: int = 0
	var passed_tests: int = 0
	var failed_tests: int = 0
	var total_assertions: int = 0
	var suite_errors: int = 0
	var failure_report: PackedStringArray = PackedStringArray()

	for suite_path: String in suite_paths:
		var resource: Resource = ResourceLoader.load(suite_path)
		if not (resource is GDScript):
			suite_errors += 1
			failure_report.append("%s: Failed to load as GDScript." % suite_path)
			continue

		var script: GDScript = resource
		if not script.can_instantiate():
			suite_errors += 1
			failure_report.append("%s: Script failed to compile or cannot be instantiated." % suite_path)
			continue

		var instance: Variant = script.new()
		if not (instance is TestCase):
			suite_errors += 1
			failure_report.append("%s: Suite must extend TestCase." % suite_path)
			if instance is Node:
				(instance as Node).free()
			continue

		var suite: TestCase = instance
		var methods: PackedStringArray = _collect_test_methods(suite, suite_path)
		if methods.is_empty():
			suite.free()
			continue

		total_suites += 1
		var suite_started_usec: int = Time.get_ticks_usec()
		var suite_passed: int = 0
		var suite_failed: int = 0
		var suite_assertions: int = 0
		print("[SUITE] %s (%d tests)" % [suite_path, methods.size()])

		root.add_child(suite)
		await process_frame

		await suite.before_all()

		for method_name: String in methods:
			total_tests += 1
			suite.reset_test_state()

			await suite.before_each()
			await suite.call(method_name)
			await suite.after_each()
			suite.cleanup_tracked_nodes()

			var failures: PackedStringArray = suite.get_failures()
			var assertions: int = suite.get_assertion_count()
			total_assertions += assertions
			suite_assertions += assertions

			if failures.is_empty():
				passed_tests += 1
				suite_passed += 1
				print("  PASS %s (%d assertions)" % [method_name, assertions])
			else:
				failed_tests += 1
				suite_failed += 1
				print("  FAIL %s (%d assertions, %d failures)" % [method_name, assertions, failures.size()])
				for msg: String in failures:
					print("       -> %s" % msg)
					failure_report.append("%s::%s: %s" % [suite_path, method_name, msg])

		await suite.after_all()
		suite.queue_free()
		await process_frame
		var suite_elapsed_ms: float = (Time.get_ticks_usec() - suite_started_usec) / 1000.0
		print("[SUITE_DONE] %s | tests=%d | passed=%d | failed=%d | assertions=%d | elapsed_ms=%.1f" % [
			suite_path,
			methods.size(),
			suite_passed,
			suite_failed,
			suite_assertions,
			suite_elapsed_ms,
		])

	var elapsed_ms: float = (Time.get_ticks_usec() - started_usec) / 1000.0
	print("")
	print("=== Test Summary ===")
	print("Suites: %d | Tests: %d | Passed: %d | Failed: %d | SuiteErrors: %d | Assertions: %d | Elapsed: %.1f ms" % [
		total_suites,
		total_tests,
		passed_tests,
		failed_tests,
		suite_errors,
		total_assertions,
		elapsed_ms,
	])

	if failed_tests > 0 or suite_errors > 0:
		print("")
		print("Failures:")
		for entry: String in failure_report:
			print("  - %s" % entry)

	if total_tests == 0:
		if suite_errors == 0:
			push_error("Test runner discovered 0 matching tests.")
		quit(1)
		return

	if failed_tests > 0 or suite_errors > 0:
		quit(1)
		return

	quit(0)


func _discover_suites() -> PackedStringArray:
	var found: Array[String] = []
	for base_dir: String in SEARCH_ROOTS:
		if DirAccess.dir_exists_absolute(base_dir):
			_scan_directory(base_dir, found)
	found.sort()
	return PackedStringArray(found)


func _scan_directory(dir_path: String, out_paths: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("Unable to open test directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_scan_directory(full_path, out_paths)
			elif entry.begins_with("test_") and entry.ends_with(".gd"):
				out_paths.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_test_methods(suite: TestCase, suite_path: String) -> PackedStringArray:
	var methods: Array[String] = []
	for info: Dictionary in suite.get_method_list():
		var method_name: String = str(info.get("name", ""))
		if method_name.begins_with("test_"):
			if _filter.is_empty() or suite_path.contains(_filter) or method_name.contains(_filter):
				methods.append(method_name)
	methods.sort()
	return PackedStringArray(methods)
