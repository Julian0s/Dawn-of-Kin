extends TestCase
## Self-test suite verifying TestCase assertions, lifecycle hooks, node tracking,
## async await execution, and T1.0 core constant integrity.

var _before_all_count: int = 0
var _before_each_count: int = 0
var _after_each_count: int = 0
var _async_timer_fired: bool = false
var _async_timer_completed: bool = false


func before_all() -> void:
	_before_all_count += 1


func before_each() -> void:
	_before_each_count += 1


func after_each() -> void:
	_after_each_count += 1


func test_01_lifecycle_hooks_executed() -> void:
	assert_eq(_before_all_count, 1, "before_all should run once per suite")
	assert_gt(float(_before_each_count), 0.0, "before_each should run before tests")
	assert_eq(_after_each_count, _before_each_count - 1, "after_each should lag before_each by 1 during test")


func test_02_sync_assertions_pass() -> void:
	assert_true(2 + 2 == 4)
	assert_false(false)
	assert_eq(42, 42)
	assert_eq("dawn", "dawn")
	assert_ne(10, 20)
	assert_near(1.0004, 1.0, 0.001)
	assert_vec2_near(Vector2(1.0, 2.0), Vector2(1.0005, 1.9995), 0.001)
	assert_vec3_near(Vector3(1.0, 2.0, 3.0), Vector3(1.0, 2.0004, 3.0), 0.001)
	assert_gt(5.0, 3.0)
	assert_lt(1.0, 2.0)
	assert_null(null)
	assert_not_null(self)
	assert_string_contains("Dawn of Kin", "Kin")
	assert_array_has(["a", "b", "c"], "b")


func test_03_isolated_probe_records_failures() -> void:
	var probe: TestCase = TestCase.new()
	probe.assert_true(false, "forced false")
	probe.assert_eq(1, 2)
	probe.assert_eq(1, 1.0) # Different Variant types must fail strict assert_eq
	probe.assert_near(10.0, 12.0, 0.5)
	probe.fail("explicit fail")

	var recorded: PackedStringArray = probe.get_failures()
	assert_eq(recorded.size(), 5, "Probe must record all 5 failed assertions")
	assert_eq(probe.get_assertion_count(), 5)
	probe.free()


func test_04_tracked_child_node_lifecycle() -> void:
	var child: Node = Node.new()
	child.name = "TrackedDummy"
	var added: Node = add_test_child(child)
	assert_eq(added, child)
	assert_true(child.is_inside_tree(), "Tracked child should be inside SceneTree during test")


func test_05_async_physics_frames() -> void:
	var start_frame: int = Engine.get_physics_frames()
	await wait_physics_frames(3)
	var end_frame: int = Engine.get_physics_frames()
	assert_gt(float(end_frame - start_frame), 2.0, "Runner must await all 3 physics frames")


func test_06_async_timer_await() -> void:
	await wait_process_frames(2)
	_async_timer_fired = false
	var timer: SceneTreeTimer = get_tree().create_timer(0.05)
	timer.timeout.connect(func() -> void: _async_timer_fired = true)
	assert_false(_async_timer_fired, "Timer must not have fired before await")
	await timer.timeout
	assert_true(_async_timer_fired, "Runner must wait for SceneTreeTimer.timeout before resuming")
	_async_timer_completed = true


func test_07_async_completed_before_next_test() -> void:
	assert_true(_async_timer_completed, "Runner must complete previous async test before starting next test")


func test_08_core_registries_integrity() -> void:
	var masks: Array[int] = [
		CollisionLayers.MASK_TERRAIN,
		CollisionLayers.MASK_OBSTACLES,
		CollisionLayers.MASK_UNITS,
		CollisionLayers.MASK_SELECTION,
		CollisionLayers.MASK_BUILDINGS,
		CollisionLayers.MASK_RESOURCES,
	]
	var seen: Dictionary = {}
	for mask: int in masks:
		assert_gt(float(mask), 0.0, "Collision mask must be positive")
		assert_eq(mask & (mask - 1), 0, "Collision mask must be power of two")
		assert_false(seen.has(mask), "Collision masks must be unique")
		seen[mask] = true

	var actions: Array[StringName] = InputActions.get_all_actions()
	assert_eq(actions.size(), 13)
	for action: StringName in actions:
		assert_true(InputMap.has_action(action), "InputMap missing action: %s" % str(action))
