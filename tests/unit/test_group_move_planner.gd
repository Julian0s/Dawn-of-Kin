extends TestCase
## Unit tests for GroupMovePlanner (Test F):
## single & multi-unit concentric slot spacing, snap collapse deduplication,
## reachability filtering via injected callables, non-crossing assignment, and edge cases.

const MIN_SPACING_DEFAULT: float = GroupMovePlanner.DEFAULT_AGENT_RADIUS * 2.0 + GroupMovePlanner.DEFAULT_CLEARANCE


func test_01_invalid_and_empty_inputs_fail_safely() -> void:
	var empty_units: Array[Vector3] = []
	var res_empty: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(empty_units, Vector3.ZERO)
	assert_false(res_empty.valid, "Empty unit list must yield invalid plan")
	assert_eq(res_empty.targets.size(), 0)

	var valid_units: Array[Vector3] = [Vector3.ZERO]
	var res_inf: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(valid_units, Vector3(INF, 0.0, 0.0))
	assert_false(res_inf.valid, "Non-finite target must fail cleanly")

	var bad_units: Array[Vector3] = [Vector3(NAN, 0.0, 0.0)]
	var res_bad_unit: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(bad_units, Vector3(4.0, 0.0, 4.0))
	assert_false(res_bad_unit.valid, "Non-finite unit position must fail cleanly")


func test_02_single_unit_snaps_to_target_and_honors_unreachability_contract() -> void:
	var snap_cb := func(pos: Vector3) -> Vector3:
		return Vector3(clampf(pos.x, -10.0, 10.0), 0.5, clampf(pos.z, -10.0, 10.0))
	var always_ok := func(_from: Vector3, _to: Vector3) -> bool:
		return true

	var units: Array[Vector3] = [Vector3(-2.0, 0.0, 2.0)]
	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(14.0, 0.0, -3.0),
		0.5,
		0.8,
		snap_cb,
		always_ok,
		true
	)
	assert_true(plan.valid)
	assert_true(plan.all_slots_reachable)
	assert_eq(plan.targets.size(), 1)
	assert_vec3_near(plan.targets[0], Vector3(10.0, 0.5, -3.0), 0.001, "Single unit must snap without lateral formation offset")

	# Unreachable ground click (allow_snapped_anchor_on_unreachable = false) must keep original target
	var never_ok := func(_from: Vector3, _to: Vector3) -> bool:
		return false
	var unreachable_plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(-16.0, 0.0, 12.0),
		0.5,
		0.8,
		snap_cb,
		never_ok,
		false
	)
	assert_true(unreachable_plan.valid)
	assert_false(unreachable_plan.all_slots_reachable, "Unreachable ground target must report all_slots_reachable = false")
	assert_false(unreachable_plan.requested_target_reachable)
	assert_vec3_near(unreachable_plan.targets[0], Vector3(-16.0, 0.0, 12.0), 0.001)


func test_03_two_units_maintain_min_separation_around_destination() -> void:
	var units: Array[Vector3] = [Vector3(-2.5, 0.0, 2.5), Vector3(2.5, 0.0, 2.5)]
	var click_target := Vector3(0.0, 0.0, -6.0)
	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(units, click_target)

	assert_true(plan.valid)
	assert_eq(plan.targets.size(), 2)
	var sep_xz: float = _dist_xz(plan.targets[0], plan.targets[1])
	assert_true(sep_xz >= MIN_SPACING_DEFAULT - 0.002, "Pair targets must stay separated by at least 2*radius + clearance")
	assert_true(sep_xz >= 1.0, "Pair separation must exceed 2 * agent_radius (1.0 m)")

	# Left unit should receive the left target (x < 0), right unit the right target (x > 0)
	assert_lt(plan.targets[0].x, plan.targets[1].x, "Pair assignment must preserve left-to-right order without crossing")


func test_04_concentric_rings_scale_and_stay_deterministic_for_larger_groups() -> void:
	var counts: Array[int] = [3, 6, 10]
	for count: int in counts:
		var units: Array[Vector3] = []
		for i: int in range(count):
			@warning_ignore("integer_division")
			var centered_idx: int = i - count / 2
			units.append(Vector3(float(centered_idx) * 2.0, 0.0, 8.0))

		var click_pos := Vector3(4.0, 0.0, -4.0)
		var plan_a: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(units, click_pos)
		var plan_b: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(units, click_pos)

		assert_true(plan_a.valid, "Plan must be valid for %d units" % count)
		assert_eq(plan_a.targets.size(), count)

		for i: int in range(count):
			assert_vec3_near(plan_a.targets[i], plan_b.targets[i], 0.0001, "Planner must be deterministic")
			for j: int in range(i + 1, count):
				var pair_dist: float = _dist_xz(plan_a.targets[i], plan_a.targets[j])
				assert_true(pair_dist >= MIN_SPACING_DEFAULT - 0.002, "Slots %d and %d too close for count=%d" % [i, j, count])


func test_05_snap_collapse_and_reachability_filter_prevent_overlapping_slots() -> void:
	# Simulate an obstacle wall occupying x > 0.0 and blocked zone z > 2.0.
	# Snapping pushes x > 0.0 back onto x = 0.0, which would stack multiple units if not deduplicated.
	var snap_to_wall_edge := func(pos: Vector3) -> Vector3:
		return Vector3(minf(pos.x, 0.0), 0.25, clampf(pos.z, -12.0, 12.0))

	var reachability_filter := func(_from: Vector3, to: Vector3) -> bool:
		return to.z <= 2.0 and to.x <= 0.01

	var units: Array[Vector3] = [
		Vector3(-4.0, 0.0, -2.0),
		Vector3(-3.0, 0.0, -4.0),
		Vector3(-2.0, 0.0, -6.0),
		Vector3(-5.0, 0.0, 0.0),
	]
	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(1.5, 0.0, 1.8),
		0.5,
		0.8,
		snap_to_wall_edge,
		reachability_filter,
		true
	)

	assert_true(plan.valid)
	assert_true(plan.all_slots_reachable)
	assert_eq(plan.targets.size(), 4)

	for i: int in range(4):
		var target: Vector3 = plan.targets[i]
		assert_true(target.x <= 0.01, "All slots must lie outside the blocked wall")
		assert_true(target.z <= 2.01, "All slots must satisfy reachability filter")
		for j: int in range(i + 1, 4):
			var dist_xz: float = _dist_xz(target, plan.targets[j])
			assert_true(dist_xz >= MIN_SPACING_DEFAULT - 0.002, "Snapped slots collapsed closer than min_spacing")


func test_06_assignment_avoids_crossed_paths() -> void:
	var slots: Array[Vector3] = [
		Vector3(3.0, 0.0, 0.0),
		Vector3(-3.0, 0.0, 0.0),
	]
	# Unit 0 is on the left (x=-4), Unit 1 is on the right (x=+4)
	var unit_positions: Array[Vector3] = [
		Vector3(-4.0, 0.0, 6.0),
		Vector3(4.0, 0.0, 6.0),
	]
	var assigned: Array[Vector3] = GroupMovePlanner.assign_slots_minimum_distance(unit_positions, slots)
	assert_eq(assigned.size(), 2)
	assert_vec3_near(assigned[0], Vector3(-3.0, 0.0, 0.0), 0.001, "Left unit should receive left slot")
	assert_vec3_near(assigned[1], Vector3(3.0, 0.0, 0.0), 0.001, "Right unit should receive right slot")

	# Reversed initial order must also avoid crossing
	var swapped_units: Array[Vector3] = [
		Vector3(4.0, 0.0, 6.0),
		Vector3(-4.0, 0.0, 6.0),
	]
	var assigned_swapped: Array[Vector3] = GroupMovePlanner.assign_slots_minimum_distance(swapped_units, slots)
	assert_vec3_near(assigned_swapped[0], Vector3(3.0, 0.0, 0.0), 0.001)
	assert_vec3_near(assigned_swapped[1], Vector3(-3.0, 0.0, 0.0), 0.001)


func test_07_single_unit_adjusts_around_occupied_position() -> void:
	var identity_snap := func(pos: Vector3) -> Vector3:
		return pos
	var always_ok := func(_from: Vector3, _to: Vector3) -> bool:
		return true

	var units: Array[Vector3] = [Vector3(-5.0, 0.0, 0.0)]
	var occupied: Array[Vector3] = [Vector3(0.0, 0.0, 0.0)]

	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(0.1, 0.0, 0.1),
		0.5,
		0.8,
		identity_snap,
		always_ok,
		false,
		occupied
	)

	assert_true(plan.valid)
	assert_true(plan.all_slots_reachable)
	assert_true(plan.requested_target_reachable)
	assert_true(plan.adjusted_for_occupancy, "Overlapping occupied slot must trigger occupancy adjustment")
	assert_eq(plan.targets.size(), 1)
	assert_true(
		_dist_xz(plan.targets[0], occupied[0]) >= MIN_SPACING_DEFAULT - 0.002,
		"Adjusted single-unit slot must preserve min_spacing from occupied position"
	)

	# Far occupied position must leave single-unit target unadjusted
	var far_occupied: Array[Vector3] = [Vector3(10.0, 0.0, 10.0)]
	var clear_plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(0.0, 0.0, 0.0),
		0.5,
		0.8,
		identity_snap,
		always_ok,
		false,
		far_occupied
	)
	assert_true(clear_plan.valid)
	assert_false(clear_plan.adjusted_for_occupancy, "Distant occupied position must not alter requested target")
	assert_vec3_near(clear_plan.targets[0], Vector3.ZERO, 0.001)


func test_08_group_move_respects_external_occupied_positions() -> void:
	var identity_snap := func(pos: Vector3) -> Vector3:
		return pos
	var always_ok := func(_from: Vector3, _to: Vector3) -> bool:
		return true

	var units: Array[Vector3] = [
		Vector3(-6.0, 0.0, -1.0),
		Vector3(-6.0, 0.0, 1.0),
	]
	# External unit is parked near the left slot around (0,0,0)
	var occupied: Array[Vector3] = [Vector3(-1.0, 0.0, 0.0)]

	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(0.0, 0.0, 0.0),
		0.5,
		0.8,
		identity_snap,
		always_ok,
		false,
		occupied
	)

	assert_true(plan.valid)
	assert_true(plan.all_slots_reachable)
	assert_eq(plan.targets.size(), 2)
	assert_true(
		_dist_xz(plan.targets[0], plan.targets[1]) >= MIN_SPACING_DEFAULT - 0.002,
		"Group targets must stay spaced apart from each other"
	)
	for slot: Vector3 in plan.targets:
		assert_true(
			_dist_xz(slot, occupied[0]) >= MIN_SPACING_DEFAULT - 0.002,
			"Group slots must stay clear of external occupied positions"
		)


func test_09_unreachable_target_with_occupied_positions_preserves_unreachable_contract() -> void:
	var snap_inside_enclosure := func(pos: Vector3) -> Vector3:
		return pos
	var block_enclosure := func(_from: Vector3, to: Vector3) -> bool:
		return to.x < 10.0

	var units: Array[Vector3] = [Vector3(-4.0, 0.0, 0.0)]
	var occupied: Array[Vector3] = [Vector3(12.0, 0.0, 0.0)]

	var plan: GroupMovePlanner.PlanResult = GroupMovePlanner.plan_targets(
		units,
		Vector3(12.0, 0.0, 0.0),
		0.5,
		0.8,
		snap_inside_enclosure,
		block_enclosure,
		false,
		occupied
	)

	assert_true(plan.valid)
	assert_false(plan.requested_target_reachable, "Unreachable target must remain marked unreachable")
	assert_false(plan.all_slots_reachable, "Unreachable enclosure must not claim reachable slots")
	assert_false(plan.adjusted_for_occupancy, "Unreachable target must not masquerade as occupancy adjustment")
	assert_vec3_near(plan.targets[0], Vector3(12.0, 0.0, 0.0), 0.001)


static func _dist_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
