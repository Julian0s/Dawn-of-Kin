extends TestCase
## Backend-only T34-AUT-08/08B/09A. No T3.4.3 order execution or waiting phases.
const COSTS: Dictionary = {&"wood": 12, &"stone": 6}
const ZERO: Dictionary = {&"wood": 0, &"stone": 0}
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")

# Keeps the real Unit.current_order/ConstructOrder identity contract while isolating
# backend tests from navigation, movement and the deferred T3.4.3 assembly loop.
class BackendOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)
	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass

func _fixture(buffer: Dictionary = COSTS) -> Dictionary:
	var host := Node3D.new()
	add_test_child(host)
	var storage := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(storage)
	var site := ConstructionSite.new()
	host.add_child(site)
	assert_true(site.configure(&"assembly_test", &"reservation_test", SHELTER, inventory))
	var units: Array[Unit] = []
	for i: int in range(3):
		var unit: Unit = UNIT_SCENE.instantiate() as Unit
		unit.definition = preload("res://data/characters/leader_a.tres").duplicate()
		unit.position = Vector3(-1.2 + i * 1.2, 0.0, 2.85)
		host.add_child(unit)
		unit.set_physics_process(false)
		unit.issue_order(BackendOrder.new(site))
		units.append(unit)
	# Fixtures inject physical cargo through the real transit/delivery API, respecting weight.
	_deliver(site, units[0], buffer)
	for i: int in range(1, 3):
		assert_true(site.assign_builder_slot_position(units[i], i - 1, units[i].position))
	return {"site": site, "units": units, "host": host}

func _deliver(site: ConstructionSite, unit: Unit, amounts: Dictionary) -> void:
	for key: Variant in amounts:
		var left: int = int(amounts[key])
		var resource: ResourceDefinition = load("res://data/resources/%s.tres" % String(key)) as ResourceDefinition
		while left > 0:
			var quantity: int = mini(left, unit.get_carry_load().get_max_additional_units(resource))
			assert_gt(float(quantity), 0.0)
			assert_true(unit.get_carry_load().add_units(resource, quantity))
			site.record_withdrawn_for_site(unit, key, quantity)
			assert_eq(int(site.accept_delivery_from_carry_load(unit, unit.get_carry_load()).get(key, 0)), quantity)
			left -= quantity

func _snapshot(site: ConstructionSite) -> Dictionary:
	return {"progress": site.get_work_progress_sec(), "buffer": site.get_delivered_buffer_amounts(),
		"consumed": site.get_consumed_amounts(), "state": site.get_site_state(), "substate": site.get_assembly_substate()}

func _reject(site: ConstructionSite, unit: Unit, delta: float, reason: String) -> void:
	var before: Dictionary = _snapshot(site)
	var result: Dictionary = site.contribute_work(unit, delta)
	assert_false(result["ok"])
	assert_eq(result["reason"], reason)
	assert_eq(result["advanced_sec"], 0.0)
	assert_eq(result["consumed"], {})
	assert_false(result["starved"])
	assert_eq(_snapshot(site), before)
	assert_true(site.verify_accounting_invariant())

func test_01_t34_aut_09a_exact_boundaries_and_pure_inputs() -> void:
	var progress: int = 0
	var used: Dictionary = ZERO.duplicate()
	var buffer: Dictionary = COSTS.duplicate()
	var expected_wood: Array[int] = [0, 1, 1, 1, 2, 11, 12]
	var expected_stone: Array[int] = [0, 0, 0, 0, 1, 5, 6]
	var targets: Array[int] = [2_499_999, 2_500_000, 2_500_001, 4_999_999, 5_000_000, 29_999_999, 30_000_000]
	for i: int in range(targets.size()):
		var before: Array = [COSTS.duplicate(), used.duplicate(), buffer.duplicate()]
		var r: Dictionary = ConstructionSite.evaluate_work_transaction_usec(progress, 30_000_000, targets[i] - progress, COSTS, used, buffer)
		assert_true(r["ok"])
		assert_eq(r["progress_usec"], targets[i])
		assert_eq([COSTS, used, buffer], before)
		for key: Variant in COSTS:
			used[key] = int(used[key]) + int(r["consumed"][key])
			buffer[key] = int(buffer[key]) - int(r["consumed"][key])
		assert_eq(used[&"wood"], expected_wood[i])
		assert_eq(used[&"stone"], expected_stone[i])
		assert_eq(r["completed"], i == targets.size() - 1)
		progress = targets[i]

func test_02_t34_aut_09a_required_starvation_and_atomic_abort() -> void:
	var r: Dictionary = ConstructionSite.evaluate_work_transaction_usec(0, 30_000_000, 6_000_000, COSTS, ZERO, {&"wood": 2, &"stone": 0})
	assert_true(r["ok"])
	assert_eq(r["progress_usec"], 4_999_999)
	assert_eq(r["consumed"], {&"wood": 1, &"stone": 0})
	assert_true(r["starved"])
	# Invalid incorporated state would require a negative debit: reject the whole plan.
	var buffer: Dictionary = {&"wood": 2, &"stone": 0}
	var before: Dictionary = buffer.duplicate()
	r = ConstructionSite.evaluate_work_transaction_usec(0, 30_000_000, 1, COSTS, {&"wood": 1, &"stone": 0}, buffer)
	assert_false(r["ok"])
	assert_eq(r["reason"], "insufficient_buffer_transaction_aborted")
	assert_eq(r["consumed"], {})
	assert_eq(buffer, before)

func test_03_t34_aut_08_ordered_guards_and_delta_values() -> void:
	var fx: Dictionary = _fixture()
	var site: ConstructionSite = fx["site"]
	var units: Array[Unit] = fx["units"]
	for value: float in [0.0, -0.1, NAN, INF, -INF, 0.250001, 6.0]:
		_reject(site, units[1], value, "invalid_delta")
	_reject(site, null, 0.1, "invalid_unit")
	var detached := Unit.new()
	_reject(site, detached, 0.1, "invalid_unit")
	detached.free()
	site.unregister_worker(units[2])
	_reject(site, units[2], 0.1, "worker_not_registered")
	_reject(site, units[0], 0.1, "worker_not_builder")
	site._builder_slot_positions.clear()
	_reject(site, units[1], 0.1, "builder_slot_position_not_assigned")
	assert_true(site.assign_builder_slot_position(units[1], 0, units[1].position))
	# Same worker, active ConstructOrder, but a different site target.
	var order: ConstructOrder = units[1].get_current_order() as ConstructOrder
	order.site = null
	_reject(site, units[1], 0.1, "invalid_active_order")
	order.site = site
	for state: ConstructionSite.SiteState in [ConstructionSite.SiteState.UNCONFIGURED, ConstructionSite.SiteState.COMPLETING, ConstructionSite.SiteState.COMPLETED, ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE, ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR]:
		site._site_state = state
		_reject(site, units[1], 0.1, "completion_pending_retry" if state == ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE else ("site_completing_or_completed" if state in [ConstructionSite.SiteState.COMPLETING, ConstructionSite.SiteState.COMPLETED] else "invalid_site_state"))
	site._site_state = ConstructionSite.SiteState.ACTIVE

func test_04_t34_aut_08b_opposite_slot_and_physical_obstruction() -> void:
	var fx: Dictionary = _fixture()
	var site: ConstructionSite = fx["site"]
	var unit: Unit = fx["units"][1]
	unit.position = Vector3(0.0, 0.0, -2.85)
	assert_true(BuildSlotPlanner.is_unit_in_site_dropoff_range(unit.position, site))
	_reject(site, unit, 0.1, "worker_not_in_assigned_slot")
	unit.position = Vector3(0.0, 0.86, 2.85)
	_reject(site, unit, 0.1, "worker_not_in_assigned_slot")
	unit.position = Vector3(0.0, 0.0, 2.85)
	var wall := StaticBody3D.new()
	wall.collision_layer = CollisionLayers.MASK_OBSTACLES
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 0.1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.55, 2.4)
	fx["host"].add_child(wall)
	await wait_physics_frames(2)
	_reject(site, unit, 0.1, "worker_out_of_reach")

func test_05_t34_aut_08_duplicate_frame_two_distinct_workers_and_reentrancy() -> void:
	var fx: Dictionary = _fixture()
	var site: ConstructionSite = fx["site"]
	var units: Array[Unit] = fx["units"]
	var nested: Array[Dictionary] = []
	var callback: Callable = func(_site: ConstructionSite) -> void:
		nested.append(site.contribute_work(units[1], 0.1))
	site.buffer_changed.connect(callback)
	assert_true(site.contribute_work(units[1], 0.25)["ok"])
	site.buffer_changed.disconnect(callback)
	assert_eq(nested[0]["reason"], "duplicate_cycle_contribution")
	_reject(site, units[1], 0.25, "duplicate_cycle_contribution")
	assert_true(site.contribute_work(units[2], 0.25)["ok"])
	assert_eq(site.get_work_progress_sec(), 0.5)
	await wait_physics_frames(1)
	assert_true(site.contribute_work(units[1], 0.25)["ok"])
	assert_eq(site.get_work_progress_sec(), 0.75)

func test_06_backend_starvation_delivery_unblocks_and_conserves() -> void:
	var fx: Dictionary = _fixture({&"wood": 2, &"stone": 0})
	var site: ConstructionSite = fx["site"]
	var units: Array[Unit] = fx["units"]
	for i: int in range(20):
		await wait_physics_frames(1)
		var r: Dictionary = site.contribute_work(units[1], 0.25)
		assert_true(r["ok"])
		assert_eq(r["starved"], i == 19)
		assert_true(site.verify_accounting_invariant())
	assert_eq(site.get_work_progress_sec(), 4.999999)
	assert_eq(site.get_consumed_amounts(), {&"wood": 1, &"stone": 0})
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	await wait_physics_frames(1)
	var before: Dictionary = _snapshot(site)
	var r: Dictionary = site.contribute_work(units[1], 0.25)
	assert_eq(r["advanced_sec"], 0.0)
	assert_true(r["starved"])
	assert_eq(_snapshot(site), before)
	_reject(site, units[1], 6.0, "invalid_delta")
	_deliver(site, units[0], {&"stone": 1})
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.ASSEMBLING)
	await wait_physics_frames(1)
	assert_true(site.contribute_work(units[1], 0.000001)["ok"])
	assert_eq(site.get_work_progress_sec(), 5.0)
	assert_eq(site.get_consumed_amounts(), {&"wood": 2, &"stone": 1})
	assert_true(site.verify_accounting_invariant())

func test_07_role_changes_invalidate_anchors_and_no_workers_state() -> void:
	var fx: Dictionary = _fixture()
	var site: ConstructionSite = fx["site"]
	var units: Array[Unit] = fx["units"]
	assert_true(site.contribute_work(units[1], 0.1)["ok"])
	site.unregister_worker(units[1])
	assert_false(site._builder_slot_positions.has(units[1].get_instance_id()))
	# Slot 1 moved to slot 0; its old spatial assignment cannot be reused.
	assert_false(site._builder_slot_positions.has(units[2].get_instance_id()))
	site.unregister_worker(units[2])
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_NO_WORKERS)

func test_08_backend_full_consumption_stops_at_completing_without_building() -> void:
	var fx: Dictionary = _fixture()
	var site: ConstructionSite = fx["site"]
	var units: Array[Unit] = fx["units"]
	for i: int in range(120):
		await wait_physics_frames(1)
		assert_true(site.contribute_work(units[1], 0.25)["ok"])
		assert_true(site.verify_accounting_invariant())
	assert_eq(site.get_work_progress_sec(), 30.0)
	assert_eq(site.get_progress_ratio(), 1.0)
	assert_eq(site.get_consumed_amounts(), COSTS)
	assert_eq(site.get_delivered_buffer_amounts(), ZERO)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_true(site.is_inside_tree())
	_reject(site, units[2], 0.25, "site_completing_or_completed")


func test_09_guard_slot_limits_order_identity_and_anchor_cleanup() -> void:
	var fx: Dictionary = _fixture()
	var site: ConstructionSite = fx["site"]
	var unit: Unit = fx["units"][1]
	assert_false(site.assign_builder_slot_position(unit, 1, unit.position))
	assert_false(site.assign_builder_slot_position(unit, 0, Vector3(NAN, 0, 0)))
	assert_false(site.assign_builder_slot_position(unit, 0, Vector3.ZERO))
	var original: Dictionary = site._builder_slot_positions[unit.get_instance_id()].duplicate()
	site._builder_slot_positions[unit.get_instance_id()]["slot_idx"] = 9
	_reject(site, unit, 0.1, "builder_slot_position_not_assigned")
	site._builder_slot_positions[unit.get_instance_id()] = original
	var real_order: UnitOrder = unit.get_current_order()
	unit._current_order = MoveOrder.new(Vector3.ZERO)
	_reject(site, unit, 0.1, "invalid_active_order")
	unit._current_order = BackendOrder.new(site)
	_reject(site, unit, 0.1, "invalid_active_order")
	unit._current_order = real_order
	var definition: BuildingDefinition = site.definition
	site.definition = definition.duplicate()
	site.definition.max_builders = 1
	_reject(site, fx["units"][2], 0.1, "invalid_builder_slot")
	site.definition = definition
	# Pruning an inactive order invalidates its spatial identity as well.
	real_order.mark_succeeded()
	site.get_worker_role(unit)
	assert_false(site._builder_slot_positions.has(unit.get_instance_id()))

func test_10_pure_nondivisible_costs_integer_limits_and_partition_invariance() -> void:
	# Non-divisible thresholds: first unit of a 3-cost/10-usec recipe falls at 4 usec.
	var costs: Dictionary = {&"a": 3, &"b": 2}
	var r: Dictionary = ConstructionSite.evaluate_work_transaction_usec(0, 10, 10, costs, {}, {&"a": 1, &"b": 0})
	assert_eq(r["progress_usec"], 4)
	assert_eq(r["consumed"], {&"a": 1, &"b": 0})
	assert_true(r["starved"])
	for bad: Array in [[-1, 10, 1], [0, 0, 1], [11, 10, 1], [0, 10, 0], [0, 9223372036854775807, 1]]:
		r = ConstructionSite.evaluate_work_transaction_usec(bad[0], bad[1], bad[2], costs, {}, {&"a": 3, &"b": 2})
		assert_false(r["ok"])
		assert_eq(r["consumed"], {})
	var used: Dictionary = ZERO.duplicate()
	var buffer: Dictionary = COSTS.duplicate()
	var progress: int = 0
	for step: int in [1, 2_499_998, 1, 2_500_001, 7_654_321, 17_345_679]:
		r = ConstructionSite.evaluate_work_transaction_usec(progress, 30_000_000, step, COSTS, used, buffer)
		assert_true(r["ok"])
		progress = int(r["progress_usec"])
		for key: Variant in COSTS:
			used[key] = int(used[key]) + int(r["consumed"][key])
			buffer[key] = int(buffer[key]) - int(r["consumed"][key])
	assert_eq(progress, 30_000_000)
	assert_eq(used, COSTS)
	assert_eq(buffer, ZERO)


func test_11_no_redundant_signals_in_paused_starved_and_legitimate_resume() -> void:
	var fx: Dictionary = _fixture({&"wood": 2, &"stone": 0})
	var site: ConstructionSite = fx["site"]
	var units: Array[Unit] = fx["units"]
	var buffer_signals: Array[int] = [0]
	var state_signals: Array[int] = [0]
	site.buffer_changed.connect(func(_s: ConstructionSite) -> void: buffer_signals[0] += 1)
	site.state_changed.connect(func(_s: ConstructionSite) -> void: state_signals[0] += 1)

	# Cycles 1..20: advance to 4_999_999 usec (1 wood consumed, 0 stone) and transition to PAUSED_STARVED.
	for i: int in range(20):
		await wait_physics_frames(1)
		var r: Dictionary = site.contribute_work(units[1], 0.25)
		assert_true(r["ok"])
		assert_eq(r["starved"], i == 19)
	assert_eq(site.get_work_progress_sec(), 4.999999)
	assert_eq(site.get_consumed_amounts(), {&"wood": 1, &"stone": 0})
	assert_eq(site.get_delivered_buffer_amounts(), {&"wood": 1, &"stone": 0})
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	assert_eq(buffer_signals[0], 20)
	assert_eq(state_signals[0], 20)

	# 4 subsequent valid calls across distinct physics frames while already PAUSED_STARVED:
	# zero progress, starved=true, invariant valid, zero redundant buffer/state emissions.
	for _idle_idx: int in range(4):
		await wait_physics_frames(1)
		var r_idle: Dictionary = site.contribute_work(units[1], 0.25)
		assert_true(r_idle["ok"])
		assert_eq(r_idle["advanced_sec"], 0.0)
		assert_true(r_idle["starved"])
		assert_eq(site.get_work_progress_sec(), 4.999999)
		assert_eq(site.get_consumed_amounts(), {&"wood": 1, &"stone": 0})
		assert_eq(site.get_delivered_buffer_amounts(), {&"wood": 1, &"stone": 0})
		assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
		assert_true(site.verify_accounting_invariant())
		assert_eq(buffer_signals[0], 20, "Idle PAUSED_STARVED calls must not emit redundant buffer_changed")
		assert_eq(state_signals[0], 20, "Idle PAUSED_STARVED calls must not emit redundant state_changed")

	# Direct 0-advance transition into PAUSED_STARVED emits state_changed once and 0 buffer_changed.
	var fx_zero: Dictionary = _fixture(ZERO)
	var site_zero: ConstructionSite = fx_zero["site"]
	var units_zero: Array[Unit] = fx_zero["units"]
	for _j: int in range(9):
		await wait_physics_frames(1)
		assert_true(site_zero.contribute_work(units_zero[1], 0.25)["ok"])
	await wait_physics_frames(1)
	assert_true(site_zero.contribute_work(units_zero[1], 0.249999)["ok"])
	assert_eq(site_zero.get_work_progress_sec(), 2.499999)
	assert_eq(site_zero.get_assembly_substate(), ConstructionSite.AssemblySubstate.ASSEMBLING)
	var z_buf: Array[int] = [0]
	var z_state: Array[int] = [0]
	site_zero.buffer_changed.connect(func(_s: ConstructionSite) -> void: z_buf[0] += 1)
	site_zero.state_changed.connect(func(_s: ConstructionSite) -> void: z_state[0] += 1)
	await wait_physics_frames(1)
	var rz1: Dictionary = site_zero.contribute_work(units_zero[1], 0.25)
	assert_true(rz1["ok"])
	assert_eq(rz1["advanced_sec"], 0.0)
	assert_true(rz1["starved"])
	assert_eq(site_zero.get_assembly_substate(), ConstructionSite.AssemblySubstate.PAUSED_STARVED)
	assert_eq(z_buf[0], 0, "0-advance transition to PAUSED_STARVED must not emit buffer_changed")
	assert_eq(z_state[0], 1, "0-advance transition to PAUSED_STARVED must emit state_changed once")
	await wait_physics_frames(1)
	var rz2: Dictionary = site_zero.contribute_work(units_zero[1], 0.25)
	assert_true(rz2["ok"])
	assert_eq(z_buf[0], 0)
	assert_eq(z_state[0], 1, "Repeated 0-advance call in PAUSED_STARVED must emit 0 state_changed")

	# Physical delivery of 1 stone emits legitimate delivery signals (record_withdrawn -> state_changed,
	# accept_delivery -> buffer_changed + state_changed), unblocks and resumes exact assembly.
	_deliver(site, units[0], {&"stone": 1})
	assert_eq(buffer_signals[0], 21)
	assert_eq(state_signals[0], 22)
	assert_eq(site.get_assembly_substate(), ConstructionSite.AssemblySubstate.ASSEMBLING)

	# Reentrancy guard + duplicate same-worker/frame + two distinct workers in same frame.
	var reentrant_results: Array[Dictionary] = []
	var reentrant_cb: Callable = func(_s: ConstructionSite) -> void:
		reentrant_results.append(site.contribute_work(units[2], 0.1))
	site.state_changed.connect(reentrant_cb)
	await wait_physics_frames(1)
	var r_resume: Dictionary = site.contribute_work(units[1], 0.000001)
	site.state_changed.disconnect(reentrant_cb)
	assert_true(r_resume["ok"])
	assert_eq(site.get_work_progress_sec(), 5.0)
	assert_eq(site.get_consumed_amounts(), {&"wood": 2, &"stone": 1})
	assert_eq(site.get_delivered_buffer_amounts(), ZERO)
	assert_eq(buffer_signals[0], 22)
	assert_eq(state_signals[0], 23)
	assert_eq(reentrant_results.size(), 1)
	assert_false(reentrant_results[0]["ok"])
	assert_eq(reentrant_results[0]["reason"], "duplicate_cycle_contribution")
	_reject(site, units[1], 0.1, "duplicate_cycle_contribution")

	# Two distinct builders in the same frame after commit: deliver +1w/+1s and contribute with units[2].
	_deliver(site, units[0], {&"wood": 1, &"stone": 1})
	var r_second_worker: Dictionary = site.contribute_work(units[2], 0.25)
	assert_true(r_second_worker["ok"])
	assert_eq(site.get_work_progress_sec(), 5.25)
	assert_true(site.verify_accounting_invariant())
