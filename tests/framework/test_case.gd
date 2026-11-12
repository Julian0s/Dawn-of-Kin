class_name TestCase
extends Node
## Base class for Dawn of Kin unit and integration test suites.
## Provides assertion helpers, frame waiting, and tracked node cleanup.

var _failures: PackedStringArray = PackedStringArray()
var _assertion_count: int = 0
var _tracked_nodes: Array[Node] = []


## Override for one-time suite setup (supports await).
func before_all() -> void:
	pass


## Override for one-time suite teardown (supports await).
func after_all() -> void:
	pass


## Override for per-test setup (supports await).
func before_each() -> void:
	pass


## Override for per-test teardown (supports await).
func after_each() -> void:
	pass


func reset_test_state() -> void:
	_failures.clear()
	_assertion_count = 0


func get_failures() -> PackedStringArray:
	return _failures


func get_assertion_count() -> int:
	return _assertion_count


## Adds a node as a child of this suite and registers it for automatic cleanup after the test.
func add_test_child(node: Node) -> Node:
	add_child(node)
	_tracked_nodes.append(node)
	return node


func cleanup_tracked_nodes() -> void:
	for i: int in range(_tracked_nodes.size() - 1, -1, -1):
		var node: Node = _tracked_nodes[i]
		if is_instance_valid(node):
			var parent: Node = node.get_parent()
			if parent != null:
				parent.remove_child(node)
			node.free()
	_tracked_nodes.clear()


func wait_physics_frames(count: int = 1) -> void:
	for _i: int in range(maxi(count, 0)):
		await get_tree().physics_frame


func wait_process_frames(count: int = 1) -> void:
	for _i: int in range(maxi(count, 0)):
		await get_tree().process_frame


func fail(message: String) -> void:
	_assertion_count += 1
	_failures.append(message)


func assert_true(condition: bool, message: String = "") -> bool:
	_assertion_count += 1
	if condition:
		return true
	_failures.append(message if not message.is_empty() else "Expected condition to be true, got false.")
	return false


func assert_false(condition: bool, message: String = "") -> bool:
	_assertion_count += 1
	if not condition:
		return true
	_failures.append(message if not message.is_empty() else "Expected condition to be false, got true.")
	return false


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	_assertion_count += 1
	if typeof(actual) == typeof(expected) and actual == expected:
		return true
	var detail: String = "Expected <%s> (%s), got <%s> (%s)." % [
		str(expected), type_string(typeof(expected)),
		str(actual), type_string(typeof(actual)),
	]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> bool:
	_assertion_count += 1
	if typeof(actual) != typeof(unexpected) or actual != unexpected:
		return true
	var detail: String = "Expected value not to equal <%s>." % str(unexpected)
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_near(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> bool:
	_assertion_count += 1
	var diff: float = absf(actual - expected)
	if diff <= tolerance:
		return true
	var detail: String = "Expected %.6f +/- %.6f, got %.6f (diff %.6f)." % [expected, tolerance, actual, diff]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_vec2_near(actual: Vector2, expected: Vector2, tolerance: float = 0.001, message: String = "") -> bool:
	_assertion_count += 1
	var dist: float = actual.distance_to(expected)
	if dist <= tolerance:
		return true
	var detail: String = "Expected Vector2 %s +/- %.6f, got %s (dist %.6f)." % [str(expected), tolerance, str(actual), dist]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_vec3_near(actual: Vector3, expected: Vector3, tolerance: float = 0.001, message: String = "") -> bool:
	_assertion_count += 1
	var dist: float = actual.distance_to(expected)
	if dist <= tolerance:
		return true
	var detail: String = "Expected Vector3 %s +/- %.6f, got %s (dist %.6f)." % [str(expected), tolerance, str(actual), dist]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_gt(actual: float, threshold: float, message: String = "") -> bool:
	_assertion_count += 1
	if actual > threshold:
		return true
	var detail: String = "Expected %.6f > %.6f." % [actual, threshold]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_lt(actual: float, threshold: float, message: String = "") -> bool:
	_assertion_count += 1
	if actual < threshold:
		return true
	var detail: String = "Expected %.6f < %.6f." % [actual, threshold]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_null(value: Variant, message: String = "") -> bool:
	_assertion_count += 1
	if value == null:
		return true
	var detail: String = "Expected null, got <%s>." % str(value)
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_not_null(value: Variant, message: String = "") -> bool:
	_assertion_count += 1
	if value != null:
		return true
	_failures.append(message if not message.is_empty() else "Expected non-null value, got null.")
	return false


func assert_string_contains(haystack: String, needle: String, message: String = "") -> bool:
	_assertion_count += 1
	if haystack.contains(needle):
		return true
	var detail: String = "Expected \"%s\" to contain \"%s\"." % [haystack, needle]
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false


func assert_array_has(array: Array, item: Variant, message: String = "") -> bool:
	_assertion_count += 1
	if array.has(item):
		return true
	var detail: String = "Expected array to contain <%s>." % str(item)
	_failures.append("%s %s" % [message, detail] if not message.is_empty() else detail)
	return false
