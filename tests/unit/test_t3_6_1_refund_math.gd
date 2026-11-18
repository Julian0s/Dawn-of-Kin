extends TestCase
const MathD3 = preload("res://src/buildings/construction_cancellation_math.gd")

func _item(required: int, reserved: int, transit: int, buffer: int, incorporated: int, missing: int) -> Dictionary:
	return {"required": required, "reserved": reserved, "in_transit": transit, "buffer": buffer, "incorporated": incorporated, "missing": missing}

func _snapshot(progress: int, wood: Dictionary, stone: Dictionary) -> Dictionary:
	return {"progress": progress, "total_work": 30000000, "resources": {&"wood": wood, &"stone": stone}}

func test_normative_snapshots() -> void:
	var cases: Array = [
		[_snapshot(0, _item(12, 0, 0, 12, 0, 0), _item(6, 0, 0, 6, 0, 0)), [12, 6, 0, 0]],
		[_snapshot(15000000, _item(12, 0, 0, 6, 6, 0), _item(6, 0, 0, 3, 3, 0)), [7, 3, 1, 0]],
		[_snapshot(27000000, _item(12, 0, 0, 1, 11, 0), _item(6, 0, 0, 0, 6, 0)), [1, 0, 0, 0]],
		[_snapshot(27000000, _item(12, 0, 0, 2, 10, 0), _item(6, 0, 0, 1, 5, 0)), [2, 1, 0, 0]]]
	for case: Array in cases:
		var before: Dictionary = case[0].duplicate(true)
		var r: Dictionary = MathD3.evaluate_snapshot(case[0])
		assert_true(r.ok)
		assert_false(r.physical_verified)
		assert_eq(r.resources[&"wood"].total_predicted, case[1][0])
		assert_eq(r.resources[&"stone"].total_predicted, case[1][1])
		assert_eq(r.resources[&"wood"].incorporated_recovered, case[1][2])
		assert_eq(r.resources[&"stone"].incorporated_recovered, case[1][3])
		assert_eq(case[0], before)
		r.resources[&"wood"].buffer = 999
		assert_eq(case[0], before)
		assert_ne(MathD3.evaluate_snapshot(case[0]).resources[&"wood"].buffer, 999)

func test_categories_and_accounting() -> void:
	var s := _snapshot(15000000, _item(12, 2, 3, 1, 4, 2), _item(6, 0, 0, 0, 3, 3))
	var r: Dictionary = MathD3.evaluate_snapshot(s)
	assert_true(r.ok)
	var wood: Dictionary = r.resources[&"wood"]
	assert_eq(wood.reservation_release, 2)
	assert_eq(wood.in_transit, 3)
	assert_eq(wood.buffer, 1)
	assert_eq(wood.incorporated_recovered, 1)
	assert_eq(wood.demolition_loss, 3)
	assert_eq(wood.missing, 2)
	assert_eq(wood.future_physical_return, 5)
	assert_eq(wood.total_predicted, 7)
	s.resources[&"wood"].missing = 1
	assert_eq(MathD3.evaluate_snapshot(s).reason, "accounting_mismatch")

func test_exact_integer_boundaries() -> void:
	# Independent exact values: integer arithmetic floor(C*(W-P)/(2*W)).
	for vector: Array in [[12, 0, 30000000, 6], [12, 30000000, 30000000, 0],
		[6, 2499999, 30000000, 2], [6, 2500000, 30000000, 2], [6, 2500001, 30000000, 2],
		[12, 14999999, 30000000, 3], [12, 15000000, 30000000, 3], [12, 15000001, 30000000, 2],
		[3000000000, 0, 1000000000, 1500000000], [9223372036854775807, 1, 1, 0]]:
		var r: Dictionary = MathD3.evaluate_refund(vector[0], vector[1], vector[2])
		assert_true(r.ok)
		assert_eq(r.value, vector[3])
	assert_eq(MathD3.evaluate_refund(9223372036854775807, 0, 2).reason, "overflow")
	assert_eq(MathD3.evaluate_refund(1, 0, 0).reason, "invalid_range")
	assert_eq(MathD3.evaluate_refund(1, -1, 2).reason, "invalid_range")
	assert_eq(MathD3.evaluate_refund(1, 3, 2).reason, "invalid_range")
	assert_eq(MathD3.evaluate_refund(-1, 0, 2).reason, "invalid_range")
	assert_eq(MathD3.evaluate_refund(1.0, 0, 2).reason, "invalid_type")

func test_invalid_snapshots() -> void:
	var s := _snapshot(0, _item(12, 0, 0, 12, 0, 0), _item(6, 0, 0, 6, 0, 0))
	for invalid: Variant in [-1, 1.0, true, "1", null]:
		var copy: Dictionary = s.duplicate(true)
		copy.resources[&"wood"].buffer = invalid
		assert_false(MathD3.evaluate_snapshot(copy).ok)
	var overflow := _snapshot(0, _item(9223372036854775807, 9223372036854775807, 1, 0, 0, 0), _item(6, 0, 0, 6, 0, 0))
	assert_eq(MathD3.evaluate_snapshot(overflow).reason, "overflow")
	var bad: Dictionary = s.duplicate(true)
	bad.resources[&"wood"].extra = 0
	assert_false(MathD3.evaluate_snapshot(bad).ok)
	bad = s.duplicate(true)
	bad.resources[42] = bad.resources[&"wood"]
	assert_false(MathD3.evaluate_snapshot(bad).ok)
	bad = s.duplicate(true)
	bad.resources[&"wood"].erase("buffer")
	assert_false(MathD3.evaluate_snapshot(bad).ok)

func test_state_contract_and_idempotence() -> void:
	var state = MathD3.State
	var edges: Array = [[state.ACTIVE, state.REQUESTED], [state.REQUESTED, state.PREVALIDATING],
		[state.PREVALIDATING, state.FREEZING], [state.FREEZING, state.RECOVERY_PENDING],
		[state.RECOVERY_PENDING, state.RETURNING], [state.RETURNING, state.RETURN_BLOCKED],
		[state.RETURN_BLOCKED, state.RETURNING], [state.RETURNING, state.SETTLED],
		[state.FREEZING, state.ACTIVE]]
	for edge: Array in edges:
		assert_true(MathD3.plan_transition(edge[0], edge[1]).ok)
	for from: int in range(state.RECOVERY_PENDING, state.SETTLED + 1):
		assert_false(MathD3.plan_transition(from, state.ACTIVE).ok)
		var same: Dictionary = MathD3.plan_transition(from, from)
		assert_true(same.ok)
		assert_false(same.changed)
		assert_true(same.committed)
		assert_eq(same, MathD3.plan_transition(from, from))
	assert_false(MathD3.plan_transition(state.ACTIVE, state.SETTLED).ok)
	assert_false(MathD3.plan_transition(state.SETTLED, state.RETURNING).ok)
	assert_false(MathD3.plan_transition(1.0, state.ACTIVE).ok)
