extends TestCase
## Comprehensive integration suite for R-03A D2 — Selective Community Work Cancellation.
## Covers traceable requirements:
## - S01-S14: Selective granularity by (selected sources ∩ category ∩ valid regional domain ∩ active tasks)
## - O01-O14: Worker order lifecycle, single legitimate final delivery (D2-B), personal orders, removals, delivery failures
## - E01-E16: Provenance mid-transfer safety, busy retry cancellation, replay idempotency, conservation,
##            blocked economy, reserved/recovery lots, ConstructOrder coexistence, reentrancy, domain guards
## - U01-U20: D2-A mineral "×" seal HUD geometry, real viewport input events, hit-testing, anti-click-through, 720p/1080p

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_DEF: ResourceDefinition = preload("res://data/resources/food.tres")


func _fixture(viewport_size: Vector2i = Vector2i(1280, 720)) -> SubViewport:
	var view := SubViewport.new()
	view.size = viewport_size
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.disable_3d = false
	view.own_world_3d = true
	view.physics_object_picking = true
	var main := MAIN_SCENE.instantiate() as MainScene
	view.add_child(main)
	add_test_child(view)
	for _i: int in range(180):
		if main.get_test_map() != null and main.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(main.get_test_map().get_navigation().is_navigation_ready(), "D2 Fixture: navigation ready")
	await wait_process_frames(4)
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false
		rig.set_target_zoom_distance(22.0, true)
	await wait_process_frames(2)
	return view


func _teardown_fixture(view: SubViewport) -> void:
	Engine.time_scale = 1.0
	if view == null or not is_instance_valid(view):
		return
	var main := view.get_child(0) as MainScene if view.get_child_count() > 0 else null
	if main != null and is_instance_valid(main):
		for u: Unit in main.get_units():
			if u != null and is_instance_valid(u):
				u.cancel_current_order(UnitOrder.REASON_CANCELLED)
		var g_in := main.get_input_controller() as AutonomousGatherInput
		if g_in != null:
			g_in.teardown_community_work()
		if main.get_community_task_dispatcher() != null:
			main.get_community_task_dispatcher().teardown()
		if main.get_community_work_board() != null:
			main.get_community_work_board().teardown()
	if view.get_parent() != null:
		view.get_parent().remove_child(view)
	view.queue_free()
	await wait_process_frames(2)
	await wait_physics_frames(1)


func _select_sources(model: SourceSelectionModel, sources: Array[ResourceSource]) -> void:
	model.clear()
	model.add_sources(sources)


func _find_src(main: MainScene, sid: StringName) -> ResourceSource:
	for s: ResourceSource in main.get_test_map().get_all_region_resource_sources():
		if s.get_source_id() == sid:
			return s
	return null


func _find_unit(main: MainScene, cid: StringName) -> Unit:
	for u: Unit in main.get_units():
		if u.get_character_id() == cid:
			return u
	return null


func _has_work_marker(src: ResourceSource) -> bool:
	if src == null or not is_instance_valid(src):
		return false
	for ch: Node in src.get_children():
		if ch.name.begins_with(AutonomousGatherInput.WORK_MARKER_PREFIX) and not ch.is_queued_for_deletion():
			return true
	return false


func _has_selection_ring(src: ResourceSource) -> bool:
	if src == null or not is_instance_valid(src):
		return false
	for ch: Node in src.get_children():
		if ch.name.begins_with("SourceSelectionRing_") and not ch.is_queued_for_deletion():
			return true
	return false


func _click_viewport(view: SubViewport, pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.shift_pressed = shift
	view.push_input(mm, true)
	await wait_process_frames(1)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		ev.shift_pressed = shift
		view.push_input(ev, true)
		await wait_process_frames(1)


func _total_resource_stock(main: MainScene, resource_id: StringName) -> int:
	var total: int = main.get_settlement_inventory().get_physical_amount(resource_id)
	for s: ResourceSource in main.get_test_map().get_all_region_resource_sources():
		if is_instance_valid(s) and s.get_resource_id() == resource_id:
			total += s.get_remaining_amount()
	for u: Unit in main.get_units():
		if is_instance_valid(u):
			total += u.get_carry_load().get_amount(resource_id)
	return total


# ==============================================================================
# S01-S06: Selective granularity by category, subset, mixed, and group isolation
# ==============================================================================
func test_d2_s01_s06_category_subset_mixed_and_group_isolation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput

	var t1 := _find_src(main, &"wood_tree_01")
	var t2 := _find_src(main, &"wood_tree_02")
	var t3 := _find_src(main, &"wood_tree_03")
	var t4 := _find_src(main, &"wood_tree_04")
	var r1 := _find_src(main, &"stone_rock_01")
	var f1 := _find_src(main, &"food_bush_01")

	# S01: Cancel wood while stone & food remain active
	_select_sources(model, [t1, r1, f1])
	assert_true(bool(agi.authorize_selected_category(&"wood").get("ok", false)), "S01: auth wood")
	assert_true(bool(agi.authorize_selected_category(&"stone").get("ok", false)), "S01: auth stone")
	assert_true(bool(agi.authorize_selected_category(&"food").get("ok", false)), "S01: auth food")
	await wait_process_frames(3)
	var task_t1 := board.get_active_task_for_source(t1)
	var task_r1 := board.get_active_task_for_source(r1)
	var task_f1 := board.get_active_task_for_source(f1)
	assert_not_null(task_t1, "S01: wood active")
	assert_not_null(task_r1, "S01: stone active")
	assert_not_null(task_f1, "S01: food active")

	var c_wood := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_wood.get("ok", false)), "S01: cancel wood ok")
	assert_eq(int(c_wood.get("cancelled_count", 0)), 1, "S01: exactly 1 wood cancelled")
	assert_eq(task_t1.state, WorkTask.State.CANCELLED, "S01: wood task closed CANCELLED")
	assert_eq(task_t1.last_reason, WorkTask.REASON_PLAYER_CANCELLED, "S01: exact player cancel reason")
	assert_null(board.get_active_task_for_source(t1), "S01: wood removed from active board")
	assert_true(task_r1.is_active(), "S01: stone remained active")
	assert_true(task_f1.is_active(), "S01: food remained active")

	# S02: Cancel stone while wood & food remain active
	assert_true(bool(agi.authorize_selected_category(&"wood").get("ok", false)), "S02: re-auth wood")
	await wait_process_frames(2)
	var task_t1_b := board.get_active_task_for_source(t1)
	var c_stone := agi.cancel_selected_category(&"stone")
	await wait_process_frames(2)
	assert_true(bool(c_stone.get("ok", false)), "S02: cancel stone ok")
	assert_eq(task_r1.state, WorkTask.State.CANCELLED, "S02: stone task CANCELLED")
	assert_true(task_t1_b.is_active(), "S02: wood remained active")
	assert_true(task_f1.is_active(), "S02: food remained active")

	# S03: Cancel food while wood & stone remain active
	assert_true(bool(agi.authorize_selected_category(&"stone").get("ok", false)), "S03: re-auth stone")
	await wait_process_frames(2)
	var task_r1_b := board.get_active_task_for_source(r1)
	var c_food := agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	assert_true(bool(c_food.get("ok", false)), "S03: cancel food ok")
	assert_eq(task_f1.state, WorkTask.State.CANCELLED, "S03: food task CANCELLED")
	assert_true(task_t1_b.is_active(), "S03: wood remained active")
	assert_true(task_r1_b.is_active(), "S03: stone remained active")

	# Clear remaining wood/stone before S04-S06
	agi.cancel_selected_category(&"wood")
	agi.cancel_selected_category(&"stone")
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 0, "Cleanup before S04")

	# S04 & S06: Authorize 4 trees together in ONE group_id, select only 2 -> cancel ONLY those 2 (never by group_id!)
	_select_sources(model, [t1, t2, t3, t4])
	var grp_auth := agi.authorize_selected_category(&"wood")
	assert_true(bool(grp_auth.get("ok", false)), "S04/S06: group of 4 trees authorized")
	await wait_process_frames(3)
	var task_1 := board.get_active_task_for_source(t1)
	var task_2 := board.get_active_task_for_source(t2)
	var task_3 := board.get_active_task_for_source(t3)
	var task_4 := board.get_active_task_for_source(t4)
	assert_eq(task_1.group_id, task_3.group_id, "S06: t1 and t3 share same group_id")
	assert_true(task_1.group_id > 0, "S06: valid group_id > 0")

	_select_sources(model, [t1, t2])
	var c_sub := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_sub.get("ok", false)), "S04/S06: subset cancel ok")
	assert_eq(int(c_sub.get("cancelled_count", 0)), 2, "S04/S06: strictly 2 selected cancelled")
	assert_eq(task_1.state, WorkTask.State.CANCELLED, "S04: t1 cancelled")
	assert_eq(task_2.state, WorkTask.State.CANCELLED, "S04: t2 cancelled")
	assert_true(task_3.is_active(), "S04/S06: t3 in SAME group_id untouched")
	assert_true(task_4.is_active(), "S04/S06: t4 in SAME group_id untouched")

	# S05: Mixed selection (t1 unauthorized + t3 authorized) -> only t3 cancelled; zero error
	_select_sources(model, [t1, t3])
	var c_mix := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_mix.get("ok", false)), "S05: mixed cancel ok")
	assert_eq(int(c_mix.get("cancelled_count", 0)), 1, "S05: only authorized t3 cancelled")
	assert_eq(task_3.state, WorkTask.State.CANCELLED, "S05: t3 cancelled")
	assert_null(board.get_active_task_for_source(t1), "S05: unauthorized t1 untouched")
	assert_true(task_4.is_active(), "S05: unselected t4 still active")

	await _teardown_fixture(view)


# ==============================================================================
# S07-S14: All active states, markers, selection preservation, reauth, idempotency
# ==============================================================================
func test_d2_s07_s14_states_markers_selection_reauth_and_idempotency() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput

	var t1 := _find_src(main, &"wood_tree_01")
	var t2 := _find_src(main, &"wood_tree_02")
	var t3 := _find_src(main, &"wood_tree_03")
	var r1 := _find_src(main, &"stone_rock_01")

	# Authorize 3 trees (2 workers => 2 IN_PROGRESS + 1 PENDING_WORKERS)
	_select_sources(model, [t1, t2, t3])
	assert_true(bool(agi.authorize_selected_category(&"wood").get("ok", false)), "S07/S08: auth 3 trees")
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var in_prog_src: ResourceSource = null
	var pending_src: ResourceSource = null
	for src: ResourceSource in [t1, t2, t3]:
		var tk := board.get_active_task_for_source(src)
		assert_not_null(tk, "Task exists for %s" % String(src.get_source_id()))
		if tk.state == WorkTask.State.IN_PROGRESS and in_prog_src == null:
			in_prog_src = src
		elif tk.state == WorkTask.State.PENDING_WORKERS and pending_src == null:
			pending_src = src
	assert_not_null(in_prog_src, "S08: at least one IN_PROGRESS task present")
	assert_not_null(pending_src, "S07: at least one PENDING_WORKERS task present")

	# Put r1 into BLOCKED_REAUTHORIZATION deterministically
	_select_sources(model, [r1])
	assert_true(bool(agi.authorize_selected_category(&"stone").get("ok", false)), "S09: auth stone")
	await wait_process_frames(2)
	var task_blocked := board.get_active_task_for_source(r1)
	task_blocked.clear_assignment()
	task_blocked.state = WorkTask.State.BLOCKED_REAUTHORIZATION
	task_blocked.last_reason = WorkTask.REASON_ALL_WORKERS_EXCLUDED
	board.notify_task_updated(task_blocked)
	await wait_process_frames(2)
	assert_true(task_blocked.is_blocked_reauthorization(), "S09: task in BLOCKED_REAUTHORIZATION")
	assert_true(_has_work_marker(r1), "S10: blocked work marker attached before cancel")

	# S09 + S10 + S11: Cancel BLOCKED_REAUTHORIZATION -> closed CANCELLED, marker removed, selection preserved
	var c_blk := agi.cancel_selected_category(&"stone")
	await wait_process_frames(2)
	assert_true(bool(c_blk.get("ok", false)), "S09: cancel blocked task ok")
	assert_eq(task_blocked.state, WorkTask.State.CANCELLED, "S09: blocked task closed CANCELLED")
	assert_false(_has_work_marker(r1), "S10: work marker removed immediately")
	assert_true(_has_selection_ring(r1), "S11: selection ring preserved")
	assert_eq(model.get_count_for_resource(&"stone"), 1, "S11: stone remains selected in SourceSelectionModel")

	# S07: Cancel PENDING_WORKERS task
	var task_pend := board.get_active_task_for_source(pending_src)
	_select_sources(model, [pending_src])
	var c_pend := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_pend.get("ok", false)), "S07: cancel PENDING_WORKERS ok")
	assert_eq(task_pend.state, WorkTask.State.CANCELLED, "S07: PENDING_WORKERS closed CANCELLED")
	assert_false(_has_work_marker(pending_src), "S10: pending marker removed")
	assert_true(_has_work_marker(in_prog_src), "S10: other tree marker preserved")

	# S08: Cancel IN_PROGRESS task
	var task_inp := board.get_active_task_for_source(in_prog_src)
	var old_id: int = task_inp.task_id
	_select_sources(model, [in_prog_src])
	var c_inp := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_inp.get("ok", false)), "S08: cancel IN_PROGRESS ok")
	assert_eq(task_inp.state, WorkTask.State.CANCELLED, "S08: IN_PROGRESS closed CANCELLED")
	assert_false(_has_work_marker(in_prog_src), "S10: in_progress marker removed")
	assert_eq(model.get_count_for_resource(&"wood"), 1, "S11: selection preserved after cancel")

	# S13: Repeated / double cancellation is strictly idempotent no-op
	var c_again := agi.cancel_selected_category(&"wood")
	assert_false(bool(c_again.get("ok", true)), "S13: repeated cancel returns ok=false")
	assert_eq(int(c_again.get("cancelled_count", -1)), 0, "S13: 0 cancelled on repeat")
	assert_eq(String(c_again.get("reason", "")), "no_cancellable_tasks", "S13: exact no_cancellable_tasks reason")

	# S14: Cancelling unselected category returns safe no-op
	var c_unsel := agi.cancel_selected_category(&"food")
	assert_false(bool(c_unsel.get("ok", true)), "S14: unselected category returns ok=false")
	assert_eq(String(c_unsel.get("reason", "")), "no_selected_sources", "S14: exact no_selected_sources reason")

	# S12: Re-authorizing previously cancelled source creates fresh WorkTask and dispatches cleanly
	var reauth := agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_true(bool(reauth.get("ok", false)), "S12: re-authorizing cancelled source succeeds")
	var new_task := board.get_active_task_for_source(in_prog_src)
	assert_not_null(new_task, "S12: fresh active task created")
	assert_ne(new_task.task_id, old_id, "S12: fresh task_id allocated")
	assert_true(_has_work_marker(in_prog_src), "S12: marker re-attached")

	await _teardown_fixture(view)


# ==============================================================================
# O01-O06: Order phases, immediate empty cancel, single final delivery (D2-B)
# ==============================================================================
func test_d2_o01_o06_worker_phases_and_single_final_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()

	var t1 := _find_src(main, &"wood_tree_01")
	var f1 := _find_src(main, &"food_bush_01")
	var r1 := _find_src(main, &"stone_rock_01")
	var leader_a := _find_unit(main, &"leader_a")
	var leader_b := _find_unit(main, &"leader_b")

	# O01 + O06: Approaching source with empty carry load -> immediate stop, slot released, 0 extracted
	var t1_rem0: int = t1.get_remaining_amount()
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var task_t1 := board.get_active_task_for_source(t1)
	assert_not_null(task_t1, "O01: task registered")
	var u1 := task_t1.assigned_unit
	assert_not_null(u1, "O01: worker assigned")
	var ord1 := u1.get_current_order() as GatherResourceOrder
	assert_not_null(ord1, "O01: GatherResourceOrder active")
	assert_eq(ord1.get_phase(), GatherResourceOrder.Phase.APPROACHING_SOURCE, "O01: worker in APPROACHING_SOURCE")
	assert_eq(u1.get_carry_load().get_current_weight(), 0, "O01: carry empty")

	var c1 := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	await wait_physics_frames(10)
	assert_eq(int(c1.get("stopped_immediately_count", 0)), 1, "O01: stopped immediately count == 1")
	assert_null(u1.get_current_order(), "O01: order cleared immediately")
	assert_eq(u1.get_state(), Unit.State.IDLE, "O01: worker IDLE immediately")
	assert_eq(t1.get_active_worker_count(), 0, "O06: worker slot released immediately")
	assert_eq(t1.get_remaining_amount(), t1_rem0, "O01: zero extraction occurred")

	# O02: In GATHERING before first extraction (empty carry load) -> immediate stop, slot released, 0 extracted
	f1.set_gather_cycle_timings(4.0, 0.0)
	var f1_rem0: int = f1.get_remaining_amount()
	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var task_f0 := board.get_active_task_for_source(f1)
	var uf0 := task_f0.assigned_unit
	assert_not_null(uf0, "O02: worker assigned")
	Engine.time_scale = 3.0
	var reached_gather_empty: bool = false
	for _i: int in range(900):
		var o := uf0.get_current_order() as GatherResourceOrder
		if o != null and o.get_phase() == GatherResourceOrder.Phase.GATHERING:
			reached_gather_empty = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(reached_gather_empty, "O02: reached GATHERING with empty backpack")
	assert_eq(uf0.get_carry_load().get_current_weight(), 0, "O02: still empty before first extraction")
	var c2 := agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	await wait_physics_frames(5)
	assert_eq(int(c2.get("stopped_immediately_count", 0)), 1, "O02: stopped immediately")
	assert_eq(uf0.get_state(), Unit.State.IDLE, "O02: worker IDLE")
	assert_eq(f1.get_active_worker_count(), 0, "O06: slot released")
	assert_eq(f1.get_remaining_amount(), f1_rem0, "O02: zero extracted")

	# O03: GATHERING with partial cargo -> single legitimate final delivery -> IDLE -> NEVER returns to source
	f1.set_gather_cycle_timings(0.25, 0.0)
	var inv_food0: int = inv.get_physical_amount(&"food")
	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var task_f1 := board.get_active_task_for_source(f1)
	var uf1 := task_f1.assigned_unit
	assert_not_null(uf1, "O03: worker assigned")
	Engine.time_scale = 3.0
	var got_partial: bool = false
	for _i: int in range(900):
		var o := uf1.get_current_order() as GatherResourceOrder
		if o != null and o.get_phase() == GatherResourceOrder.Phase.GATHERING and uf1.get_carry_load().get_amount(&"food") > 0:
			got_partial = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(got_partial, "O03: deterministically reached GATHERING with partial cargo")
	var partial_amt: int = uf1.get_carry_load().get_amount(&"food")
	var f1_rem_at_cancel: int = f1.get_remaining_amount()
	var ord_f1 := uf1.get_current_order() as GatherResourceOrder

	var c3 := agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	assert_eq(int(c3.get("delivering_count", 0)), 1, "O03: transitioned to final delivery")
	assert_eq(f1.get_active_worker_count(), 0, "O06: source slot released immediately on transition to delivery")
	assert_eq(ord_f1.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "O03: order in DELIVERING_TO_CAMP")
	assert_true(ord_f1.is_stop_after_delivery_requested(), "O03: stop_after_delivery flag active")

	Engine.time_scale = 3.0
	var finished_o3: bool = false
	for _i: int in range(1800):
		if uf1.get_current_order() == null and uf1.get_state() == Unit.State.IDLE:
			finished_o3 = true
			break
		await wait_physics_frames(1)
	for _i: int in range(60):
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(finished_o3, "O03: completed final delivery and reached IDLE")
	assert_true(ord_f1.is_succeeded(), "O03: final delivery order succeeded")
	assert_eq(ord_f1.get_delivered_trips(), 1, "O03: strictly ONE delivery trip")
	assert_eq(inv.get_physical_amount(&"food") - inv_food0, partial_amt, "O03: exact partial cargo delivered to camp")
	assert_eq(uf1.get_carry_load().get_amount(&"food"), 0, "O03: backpack unloaded cleanly")
	assert_eq(f1.get_remaining_amount(), f1_rem_at_cancel, "O03: zero additional extraction after cancel")
	assert_eq(f1.get_active_worker_count(), 0, "O03: never re-acquired worker slot")

	# O04: Already in DELIVERING_TO_CAMP -> finishes current delivery, never returns
	var inv_stone0: int = inv.get_physical_amount(&"stone")
	r1.set_gather_cycle_timings(0.15, 0.0)
	_select_sources(model, [r1])
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	var task_r1 := board.get_active_task_for_source(r1)
	var ur1 := task_r1.assigned_unit
	assert_not_null(ur1, "O04: stone worker assigned")
	Engine.time_scale = 3.0
	var reached_deliver: bool = false
	for _i: int in range(1800):
		var o := ur1.get_current_order() as GatherResourceOrder
		if o != null and o.get_phase() == GatherResourceOrder.Phase.DELIVERING_TO_CAMP:
			reached_deliver = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(reached_deliver, "O04: deterministically reached DELIVERING_TO_CAMP")
	var stone_carried: int = ur1.get_carry_load().get_amount(&"stone")
	var r1_rem_at_cancel: int = r1.get_remaining_amount()
	var ord_r1 := ur1.get_current_order() as GatherResourceOrder
	assert_true(stone_carried > 0, "O04: carrying stone while delivering")

	var c4 := agi.cancel_selected_category(&"stone")
	await wait_process_frames(2)
	assert_eq(int(c4.get("delivering_count", 0)), 1, "O04: finish_current_delivery recorded")
	Engine.time_scale = 3.0
	var finished_o4: bool = false
	for _i: int in range(1800):
		if ur1.get_current_order() == null and ur1.get_state() == Unit.State.IDLE:
			finished_o4 = true
			break
		await wait_physics_frames(1)
	for _i: int in range(60):
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(finished_o4, "O04: finished current delivery cleanly")
	assert_eq(ord_r1.get_delivered_trips(), 1, "O04: strictly 1 delivered trip")
	assert_eq(inv.get_physical_amount(&"stone") - inv_stone0, stone_carried, "O04: exact carried stone delivered")
	assert_eq(r1.get_remaining_amount(), r1_rem_at_cancel, "O04: zero return to rock")
	assert_eq(r1.get_active_worker_count(), 0, "O04: zero slot re-acquisition")

	# O05: APPROACHING_SOURCE while carrying residual FREE_GATHERED cargo -> immediate transition to delivery, 0 extra extraction
	var free_load := leader_a.get_carry_load()
	var seed_res: Dictionary = CarryFixture.add_lot(free_load, &"op_d2_o05_seed", &"lot_d2_o05_seed", &"wood", WOOD_DEF.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED)
	assert_true(bool(seed_res.get("ok", false)), "O05: seeded 2 FREE_GATHERED wood")
	# Occupy leader_b with MoveOrder so leader_a takes t1
	leader_b.issue_order(MoveOrder.new(Vector3(-8.0, 0.0, -8.0)))
	var inv_wood0: int = inv.get_physical_amount(&"wood")
	var t1_rem_o5: int = t1.get_remaining_amount()
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var ord_o5 := leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(ord_o5, "O05: leader_a assigned to t1")
	assert_eq(ord_o5.get_phase(), GatherResourceOrder.Phase.APPROACHING_SOURCE, "O05: approaching with residual cargo")
	var c5 := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_eq(int(c5.get("delivering_count", 0)), 1, "O05: transitioned directly to final delivery")
	assert_eq(ord_o5.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "O05: now DELIVERING_TO_CAMP")
	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if leader_a.get_current_order() == null and leader_a.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(inv.get_physical_amount(&"wood") - inv_wood0, 2, "O05: exact residual 2 wood delivered")
	assert_eq(t1.get_remaining_amount(), t1_rem_o5, "O05: zero extraction from cancelled tree")

	await _teardown_fixture(view)


# ==============================================================================
# O07-O14: Multi-worker isolation, personal orders, reassignment, removals, delivery failures
# ==============================================================================
func test_d2_o07_o14_personal_orders_reassignment_removals_and_delivery_failures() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()

	var t1 := _find_src(main, &"wood_tree_01")
	var r1 := _find_src(main, &"stone_rock_01")
	var f1 := _find_src(main, &"food_bush_01")
	var t2 := _find_src(main, &"wood_tree_02")

	# O07 + O09: 2 workers on wood & stone + pending food -> cancel stone -> wood untouched, freed worker takes food
	_select_sources(model, [t1, r1, f1])
	agi.authorize_selected_category(&"wood")
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var tw := board.get_active_task_for_source(t1)
	var ts := board.get_active_task_for_source(r1)
	var uw := tw.assigned_unit
	var us := ts.assigned_unit
	assert_not_null(uw, "O07: wood worker assigned")
	assert_not_null(us, "O07: stone worker assigned")
	var ord_w := uw.get_current_order()
	agi.authorize_selected_category(&"food")
	await wait_process_frames(3)
	var tf := board.get_active_task_for_source(f1)
	assert_eq(tf.state, WorkTask.State.PENDING_WORKERS, "O09: food waiting for free worker")

	agi.cancel_selected_category(&"stone")
	await wait_process_frames(5)
	await wait_physics_frames(2)
	assert_true(tw.is_active() and tw.assigned_unit == uw and uw.get_current_order() == ord_w, "O07: wood worker 100% uninterrupted")
	assert_eq(tf.assigned_unit, us, "O09: freed stone worker automatically reassigned to pending food")

	# O08: Personal manual order is NEVER interrupted by community cancellation
	var personal_move := MoveOrder.new(Vector3(-6.0, 0.0, 6.0))
	us.issue_order(personal_move)
	await wait_process_frames(2)
	assert_eq(us.get_current_order(), personal_move, "O08: worker holds personal MoveOrder")
	var c_food := agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	assert_eq(us.get_current_order(), personal_move, "O08: personal MoveOrder preserved untouched")
	assert_true(personal_move.is_active(), "O08: personal order still running")
	assert_true(bool(c_food.get("ok", false)), "O08: food task closed cleanly despite worker personal override")
	us.cancel_current_order()
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(3)

	# O12: Worker finishes single final delivery after cancel -> becomes eligible and dispatched to another active task
	f1.set_gather_cycle_timings(0.20, 0.0)
	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var tf12 := board.get_active_task_for_source(f1)
	var uf12 := tf12.assigned_unit
	var other_u := _find_unit(main, &"leader_b") if uf12.get_character_id() == &"leader_a" else _find_unit(main, &"leader_a")
	# Keep other_u busy on r1 so uf12 is the only worker who can pick up t2 after finishing delivery
	_select_sources(model, [r1])
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	Engine.time_scale = 3.0
	for _i: int in range(900):
		if uf12.get_carry_load().get_amount(&"food") > 0:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(uf12.get_carry_load().get_amount(&"food") > 0, "O12: partial food gathered")
	_select_sources(model, [t2])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(2)
	var tt2 := board.get_active_task_for_source(t2)
	assert_eq(tt2.state, WorkTask.State.PENDING_WORKERS, "O12: t2 pending")
	_select_sources(model, [f1])
	agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if tt2.assigned_unit == uf12:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(tt2.assigned_unit, uf12, "O12: worker reassigned to pending t2 after finishing single final delivery")
	assert_null(board.get_active_task_for_source(f1), "O12: cancelled f1 never resurrected")

	# O11: Cancelled source removed/depleted during worker's final delivery -> delivery still completes cleanly
	var ext_tree := TREE_SCENE.instantiate() as ResourceSource
	ext_tree.name = "D2_O11_Tree"
	ext_tree.source_id = &"d2_o11_tree"
	ext_tree.position = Vector3(4.0, 0.0, -4.0)
	ext_tree.set_gather_cycle_timings(0.15, 0.0)
	main.get_test_map().add_child(ext_tree)
	await wait_physics_frames(2)
	# Stop all current tasks
	_select_sources(model, [r1, t2])
	agi.cancel_selected_category(&"stone")
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(3)
	for u: Unit in main.get_units():
		u.cancel_current_order()
	await wait_process_frames(2)

	var wood_inv_o11: int = inv.get_physical_amount(&"wood")
	_select_sources(model, [ext_tree])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var to11 := board.get_active_task_for_source(ext_tree)
	var uo11 := to11.assigned_unit
	assert_not_null(uo11, "O11: worker assigned to ext_tree")
	Engine.time_scale = 3.0
	for _i: int in range(900):
		if uo11.get_carry_load().get_amount(&"wood") > 0:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	var carried_o11: int = uo11.get_carry_load().get_amount(&"wood")
	assert_true(carried_o11 > 0, "O11: partial wood gathered")
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	# Remove cancelled source while worker is on final delivery!
	ext_tree.get_parent().remove_child(ext_tree)
	ext_tree.queue_free()
	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if uo11.get_current_order() == null and uo11.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(inv.get_physical_amount(&"wood") - wood_inv_o11, carried_o11, "O11: final delivery succeeded even after cancelled source removed")
	assert_eq(board.get_active_tasks().size(), 0, "O11: zero resurrected tasks")

	# O13: Final delivery fails due to full/no-slot camp storage -> physical cargo preserved, IDLE, never returns
	var camp_o13 := main.get_camp_storage_zone()
	camp_o13.set_custom_position_validator(func(_p: Vector3) -> bool: return false)
	var food_before_o13: int = inv.get_physical_amount(&"food")
	var u13 := _find_unit(main, &"leader_a")
	other_u = _find_unit(main, &"leader_b")
	other_u.issue_order(MoveOrder.new(Vector3(-9.0, 0.0, -9.0)))
	assert_true(bool(CarryFixture.add_lot(u13.get_carry_load(), &"op_d2_o13", &"lot_d2_o13", &"food", FOOD_DEF.unit_weight, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)), "O13: seeded 3 food")
	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var f1_rem_o13: int = f1.get_remaining_amount()
	agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if u13.get_current_order() == null and u13.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(u13.get_state(), Unit.State.IDLE, "O13: worker IDLE after full-camp rejection")
	assert_eq(u13.get_carry_load().get_amount(&"food"), 3, "O13: ZERO cargo loss when camp full")
	assert_true(u13.get_carry_load().validate_provenance(), "O13: provenance still valid")
	assert_eq(inv.get_physical_amount(&"food"), food_before_o13, "O13: full inventory untouched")
	assert_eq(f1.get_remaining_amount(), f1_rem_o13, "O13: never returned to cancelled source")
	camp_o13.set_custom_position_validator(Callable())
	other_u.cancel_current_order()

	# O10: Worker removed from tree mid-final-delivery -> zero errors, zero task resurrection
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var to10 := board.get_active_task_for_source(t1)
	var uo10 := to10.assigned_unit
	assert_not_null(uo10, "O10: worker assigned")
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(1)
	uo10.get_parent().remove_child(uo10)
	uo10.queue_free()
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_eq(board.get_active_tasks().size(), 0, "O10: board stays clean after worker removed")

	# O14: Camp storage zone removed/invalid during final delivery -> fails cleanly, cargo preserved, zero crash
	var u14 := main.get_units()[0]
	var load14 := u14.get_carry_load()
	if load14.get_amount(&"food") == 0:
		CarryFixture.add_lot(load14, &"op_d2_o14", &"lot_d2_o14", &"food", FOOD_DEF.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED)
	var carried14: int = load14.get_amount(&"food")
	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	agi.cancel_selected_category(&"food")
	var camp := main.get_camp_storage_zone()
	camp.get_parent().remove_child(camp)
	camp.queue_free()
	Engine.time_scale = 3.0
	for _i: int in range(600):
		if u14.get_current_order() == null and u14.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(u14.get_state(), Unit.State.IDLE, "O14: worker IDLE after camp removed")
	assert_eq(u14.get_carry_load().get_amount(&"food"), carried14, "O14: cargo 100% preserved")
	assert_eq(board.get_active_tasks().size(), 0, "O14: zero resurrected tasks")
	assert_not_null(dispatcher, "O14: dispatcher intact")

	await _teardown_fixture(view)


# ==============================================================================
# E01-E05: Real mid-transfer cancellation, busy retry cancel, replay, delivery tx, regional busy
# ==============================================================================
func test_d2_e01_e05_provenance_mid_transfer_busy_retry_replay_and_delivery_tx() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()

	var f1 := _find_src(main, &"food_bush_01")
	var r1 := _find_src(main, &"stone_rock_01")
	var t1 := _find_src(main, &"wood_tree_01")
	var leader_a := _find_unit(main, &"leader_a")
	var leader_b := _find_unit(main, &"leader_b")

	# E01: Real mid-transfer cancellation inside ResourceSource.amount_changed while is_provenance_transfer_executing() == true!
	f1.set_gather_cycle_timings(0.15, 0.0)
	var total_food_before: int = _total_resource_stock(main, &"food")
	var f1_rem_before: int = f1.get_remaining_amount()
	var inv_food_before: int = inv.get_physical_amount(&"food")

	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var task_e1 := board.get_active_task_for_source(f1)
	var u_e1 := task_e1.assigned_unit
	var ord_e1 := u_e1.get_current_order() as GatherResourceOrder
	assert_not_null(ord_e1, "E01: GatherResourceOrder active")

	var e1_obs := {
		"hook_fired": false,
		"tx_executing_at_hook": false,
		"cancel_res": {},
		"remaining_at_hook": -1,
	}
	var on_amount_changed := func(_src: ResourceSource, remaining: int, _delta: int) -> void:
		if bool(e1_obs["hook_fired"]):
			return
		e1_obs["hook_fired"] = true
		e1_obs["tx_executing_at_hook"] = ord_e1.is_provenance_transfer_executing()
		e1_obs["remaining_at_hook"] = remaining
		e1_obs["cancel_res"] = agi.cancel_selected_category(&"food")
	f1.amount_changed.connect(on_amount_changed)

	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if bool(e1_obs["hook_fired"]) and u_e1.get_current_order() == null and u_e1.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
	for _i: int in range(60):
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	if f1.amount_changed.is_connected(on_amount_changed):
		f1.amount_changed.disconnect(on_amount_changed)

	assert_true(bool(e1_obs["hook_fired"]), "E01: amount_changed hook fired during real extraction")
	assert_true(bool(e1_obs["tx_executing_at_hook"]), "E01: is_provenance_transfer_executing() was TRUE at cancel call")
	var e1_res: Dictionary = e1_obs["cancel_res"] as Dictionary
	assert_true(bool(e1_res.get("ok", false)), "E01: cancel accepted cleanly")
	assert_eq(int(e1_res.get("deferred_transfer_count", 0)), 1, "E01: cancel deferred during active commit")
	assert_eq(task_e1.state, WorkTask.State.CANCELLED, "E01: task closed CANCELLED")
	assert_eq(ord_e1.get_extraction_cycles_completed(), 1, "E01: strictly 1 cycle committed (ZERO second cycle)")
	assert_eq(ord_e1.get_delivered_trips(), 1, "E01: strictly 1 final delivery completed")
	assert_true(ord_e1.is_succeeded(), "E01: order finished SUCCEEDED after final delivery")
	assert_eq(f1.get_remaining_amount(), int(e1_obs["remaining_at_hook"]), "E01: zero extraction after hooked commit")
	assert_eq(inv.get_physical_amount(&"food") - inv_food_before, f1_rem_before - f1.get_remaining_amount(), "E01: exact extracted amount delivered to camp")
	assert_eq(_total_resource_stock(main, &"food"), total_food_before, "E01: 100% food conservation")
	assert_true(u_e1.get_carry_load().validate_provenance(), "E01: carry provenance valid")
	assert_false(ord_e1.last_extraction_receipt.is_empty(), "E01: extraction receipt recorded")
	assert_false(ord_e1.last_delivery_receipt.is_empty(), "E01: delivery receipt recorded")

	# E03: Replay idempotency on committed operation_id never duplicates stock or carry load
	var op_id: StringName = StringName(ord_e1.last_extraction_receipt.get("operation_id", &""))
	var lot_id: StringName = StringName(ord_e1.last_extraction_receipt.get("lot_id", &""))
	var replay_res := f1.transfer_to_carry_load_with_provenance(u_e1.get_carry_load(), op_id, lot_id, f1.max_extract_per_operation)
	assert_true(bool(replay_res.get("ok", false)), "E03: replay ok")
	assert_true(bool(replay_res.get("replayed", false)), "E03: replay flagged")
	assert_eq(int(replay_res.get("extracted", -1)), 0, "E03: replay extracted == 0 (no duplication)")
	assert_eq(_total_resource_stock(main, &"food"), total_food_before, "E03: conservation unchanged after replay")

	# E02 + E05: Real cancellation while GatherTransferSession is in RETRY_SCHEDULED ("busy")
	r1.set_gather_cycle_timings(0.10, 0.0)
	var r1_rem_e2: int = r1.get_remaining_amount()
	# Keep leader_b busy so leader_a takes r1
	leader_b.issue_order(MoveOrder.new(Vector3(-8.0, 0.0, -8.0)))
	_select_sources(model, [r1])
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	var task_e2 := board.get_active_task_for_source(r1)
	var u_e2 := task_e2.assigned_unit
	var ord_e2 := u_e2.get_current_order() as GatherResourceOrder
	assert_not_null(ord_e2, "E02: order active")
	# Wait until worker enters GATHERING, then lock carry load via begin_batch() to force legitimate "busy" -> RETRY_SCHEDULED!
	Engine.time_scale = 3.0
	var in_gathering_e2: bool = false
	for _i: int in range(1200):
		if ord_e2.get_phase() == GatherResourceOrder.Phase.GATHERING:
			in_gathering_e2 = true
			break
		await wait_physics_frames(1)
	assert_true(in_gathering_e2, "E02: reached GATHERING")
	u_e2.get_carry_load().begin_batch()
	var entered_retry: bool = false
	for _i: int in range(300):
		var sess: GatherTransferSession = ord_e2.get_active_gather_session()
		if sess != null and sess.is_retry_scheduled():
			entered_retry = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(entered_retry, "E02: GatherTransferSession deterministically entered RETRY_SCHEDULED on busy")
	var busy_sess: GatherTransferSession = ord_e2.get_active_gather_session()
	var c_e2 := agi.cancel_selected_category(&"stone")
	await wait_process_frames(2)
	u_e2.get_carry_load().end_batch()
	await wait_physics_frames(30)
	assert_true(bool(c_e2.get("ok", false)), "E02/E05: cancel succeeded during busy retry")
	assert_eq(task_e2.state, WorkTask.State.CANCELLED, "E02/E05: task closed CANCELLED")
	assert_eq(busy_sess.state, GatherTransferSession.State.CANCELLED, "E02: uncommitted retry session cancelled cleanly")
	assert_eq(r1.get_remaining_amount(), r1_rem_e2, "E02/E05: ZERO phantom extraction after batch unlocked")
	assert_eq(u_e2.get_state(), Unit.State.IDLE, "E02/E05: worker IDLE with zero return")
	leader_b.cancel_current_order()

	# E04: Real cancellation during active delivery provenance transfer (hooked inside inventory_changed)
	t1.set_gather_cycle_timings(0.10, 0.0)
	var inv_wood_e4: int = inv.get_physical_amount(&"wood")
	var t1_rem_e4: int = t1.get_remaining_amount()
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var task_e4 := board.get_active_task_for_source(t1)
	var u_e4 := task_e4.assigned_unit
	var ord_e4 := u_e4.get_current_order() as GatherResourceOrder
	var e4_obs := {"fired": false, "cancel_res": {}, "rem_at_hook": -1}
	var on_inv_changed := func() -> void:
		if bool(e4_obs["fired"]):
			return
		if ord_e4.get_phase() == GatherResourceOrder.Phase.DELIVERING_TO_CAMP:
			e4_obs["fired"] = true
			e4_obs["rem_at_hook"] = t1.get_remaining_amount()
			e4_obs["cancel_res"] = agi.cancel_selected_category(&"wood")
	inv.inventory_changed.connect(on_inv_changed)
	Engine.time_scale = 3.0
	for _i: int in range(2400):
		if bool(e4_obs["fired"]) and u_e4.get_current_order() == null and u_e4.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
	for _i: int in range(60):
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	if inv.inventory_changed.is_connected(on_inv_changed):
		inv.inventory_changed.disconnect(on_inv_changed)

	assert_true(bool(e4_obs["fired"]), "E04: inventory_changed hook fired during active delivery")
	assert_eq(task_e4.state, WorkTask.State.CANCELLED, "E04: task closed CANCELLED during delivery tx")
	assert_true(ord_e4.is_succeeded(), "E04: delivery completed cleanly")
	assert_eq(ord_e4.get_delivered_trips(), 1, "E04: strictly 1 delivery trip, zero return")
	assert_eq(t1.get_remaining_amount(), int(e4_obs["rem_at_hook"]), "E04: zero return extraction")
	assert_eq(inv.get_physical_amount(&"wood") - inv_wood_e4, t1_rem_e4 - t1.get_remaining_amount(), "E04: exact wood conservation")

	await _teardown_fixture(view)


# ==============================================================================
# E06-E10: 3-resource conservation, flags, blocked economy, reserved lots, ConstructOrder coexistence
# ==============================================================================
func test_d2_e06_e10_conservation_blocked_economy_reserved_lots_and_construct_coexistence() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var hud := main.get_community_selection_actions_hud()
	var inv := main.get_settlement_inventory()
	var cm := main.get_construction_manager()
	var cmd := main.get_command_controller()

	# E07: Verify canonical production flags untouched
	assert_true(main.use_provenance_economy, "E07: use_provenance_economy == true")
	assert_true(main.automatic_cancellation_recovery, "E07: automatic_cancellation_recovery == true")
	assert_false(main.use_d2_2_hud, "E07: use_d2_2_hud == false preserved")

	# E06: Record 3-resource totals before mixed gather/cancel/reauth workload
	var wood_tot0: int = _total_resource_stock(main, &"wood")
	var stone_tot0: int = _total_resource_stock(main, &"stone")
	var food_tot0: int = _total_resource_stock(main, &"food")

	var t1 := _find_src(main, &"wood_tree_01")
	var r1 := _find_src(main, &"stone_rock_01")
	var f1 := _find_src(main, &"food_bush_01")
	t1.set_gather_cycle_timings(0.15, 0.0)
	r1.set_gather_cycle_timings(0.15, 0.0)
	f1.set_gather_cycle_timings(0.15, 0.0)

	_select_sources(model, [t1, r1, f1])
	agi.authorize_selected_category(&"wood")
	agi.authorize_selected_category(&"stone")
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	Engine.time_scale = 3.0
	for _i: int in range(360):
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	agi.cancel_selected_category(&"stone")
	agi.cancel_selected_category(&"wood")
	agi.cancel_selected_category(&"food")
	Engine.time_scale = 3.0
	for _i: int in range(2000):
		var all_idle: bool = true
		for u: Unit in main.get_units():
			if u.get_current_order() != null or u.get_state() != Unit.State.IDLE:
				all_idle = false
		if all_idle:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_eq(_total_resource_stock(main, &"wood"), wood_tot0, "E06: exact wood conservation")
	assert_eq(_total_resource_stock(main, &"stone"), stone_tot0, "E06: exact stone conservation")
	assert_eq(_total_resource_stock(main, &"food"), food_tot0, "E06: exact food conservation")

	# E09: Worker carrying ONLY SITE_RESERVED lots -> cancel does NOT trigger free delivery & preserves lots!
	var leader_a := _find_unit(main, &"leader_a")
	var leader_b := _find_unit(main, &"leader_b")
	leader_b.issue_order(MoveOrder.new(Vector3(-8.0, 0.0, -8.0)))
	var lot_res: Dictionary = CarryFixture.add_lot(
		leader_a.get_carry_load(), &"op_d2_e09_res", &"lot_d2_e09_res", &"stone", STONE_DEF.unit_weight, 2, CarryProvenanceLedger.SITE_RESERVED, &"site_d2_e09"
	)
	assert_true(bool(lot_res.get("ok", false)), "E09: seeded SITE_RESERVED lot")
	var snap_e9_before: Dictionary = leader_a.get_carry_load().provenance_snapshot()
	var ord_e9 := GatherResourceOrder.new(f1, main.get_camp_storage_zone(), inv, 0.5, 0.0, true, cm.get_region_id())
	leader_a.issue_order(ord_e9)
	await wait_physics_frames(2)
	var req_e9 := ord_e9.request_community_cancel(leader_a.get_movement())
	assert_eq(String(req_e9.get("action", "")), "cancel_immediately", "E09: SITE_RESERVED-only cargo does NOT trigger free-lot delivery")
	leader_a.cancel_current_order(GatherResourceOrder.REASON_COMMUNITY_WORK_CANCELLED)
	assert_eq(leader_a.get_carry_load().provenance_snapshot(), snap_e9_before, "E09: SITE_RESERVED lot 100% preserved untouched")
	assert_true(leader_a.get_carry_load().validate_provenance(), "E09: provenance intact")
	leader_b.cancel_current_order()

	# E10: Coexistence with concurrent ConstructOrder
	inv.deposit(&"wood", 10)
	inv.deposit(&"stone", 6)
	var site_res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, -5.0))
	assert_true(bool(site_res.get("ok", false)), "E10: ConstructionSite created legitimately")
	var site: ConstructionSite = site_res.get("site") as ConstructionSite
	assert_not_null(site, "E10: ConstructionSite valid")
	assert_true(cmd.command_units_to_site(site, [leader_b]), "E10: leader_b assigned ConstructOrder")
	var construct_ord := leader_b.get_current_order()
	assert_true(construct_ord is ConstructOrder, "E10: ConstructOrder active on leader_b")
	var t2 := _find_src(main, &"wood_tree_02")
	var r2 := _find_src(main, &"stone_rock_02")
	_select_sources(model, [t2])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var c_e10 := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_e10.get("ok", false)), "E10: community wood cancelled cleanly")
	assert_eq(leader_b.get_current_order(), construct_ord, "E10: leader_b ConstructOrder 100% intact")
	assert_true(construct_ord.is_active(), "E10: ConstructOrder still active")
	leader_b.cancel_current_order()

	# E08: Blocked economy refuses new authorization, but ALLOWS administrative cancellation of existing valid task!
	_select_sources(model, [r2])
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(3)
	var task_e8 := board.get_active_task_for_source(r2)
	assert_not_null(task_e8, "E08: task registered before economy block")
	# Simulate blocked admission on input + dispatcher + HUD
	agi.configure_community_work(board, dispatcher, main.get_autonomous_gather_feedback(), true, "simulated_blocked_economy", hud)
	hud.configure(model, board, true, "simulated_blocked_economy")
	await wait_process_frames(2)
	assert_eq(hud.get_category_visual_state(&"stone"), CommunitySelectionActionsHud.STATE_ECONOMY_BLOCKED, "E08: slab in STATE_ECONOMY_BLOCKED")
	assert_true(hud.get_category_button(&"stone").disabled, "E08: authorize slab disabled")
	assert_true(hud.is_category_cancel_visible(&"stone"), "E08: cancel seal STILL visible under blocked economy")
	assert_false(hud.get_category_cancel_button(&"stone").disabled, "E08: cancel seal STILL enabled under blocked economy")
	var refused_auth := agi.authorize_selected_category(&"stone")
	assert_false(bool(refused_auth.get("ok", true)), "E08: new authorization still refused")
	assert_eq(String(refused_auth.get("reason", "")), "economy_blocked", "E08: exact refusal reason")
	var ok_cancel := agi.cancel_selected_category(&"stone")
	await wait_process_frames(2)
	assert_true(bool(ok_cancel.get("ok", false)), "E08: administrative cancellation of existing task SUCCEEDS under blocked economy")
	assert_eq(task_e8.state, WorkTask.State.CANCELLED, "E08: task closed CANCELLED")
	assert_false(hud.is_category_cancel_visible(&"stone"), "E08: seal hidden once cancelled")

	await _teardown_fixture(view)


# ==============================================================================
# E11-E16: Reentrancy (dispatch + task_closed), rapid reauth, teardown, group-FIFO, domain guards
# ==============================================================================
func test_d2_e11_e16_reentrancy_rapid_reauth_group_fifo_and_domain_guards() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput

	var t1 := _find_src(main, &"wood_tree_01")
	var t2 := _find_src(main, &"wood_tree_02")
	var t3 := _find_src(main, &"wood_tree_03")
	var r1 := _find_src(main, &"stone_rock_01")
	var leader_a := _find_unit(main, &"leader_a")
	var leader_b := _find_unit(main, &"leader_b")

	# E11 (GREEN proof of RED-05): Reentrant cancel during _try_dispatch_unit_to_task() MUST NOT resurrect task or leave orphan order!
	leader_b.issue_order(MoveOrder.new(Vector3(-9.0, 0.0, -9.0)))
	var reg11 := board.register_gather_task(t1)
	var task11 := reg11.get("task") as WorkTask
	_select_sources(model, [t1])
	var e11_fired := {"called": false}
	var on_state11 := func(_new_s: Unit.State, _old_s: Unit.State) -> void:
		if bool(e11_fired["called"]):
			return
		e11_fired["called"] = true
		agi.cancel_selected_category(&"wood")
	leader_a.state_changed.connect(on_state11)
	var dispatched11: bool = bool(dispatcher.call("_try_dispatch_unit_to_task", task11, leader_a))
	if leader_a.state_changed.is_connected(on_state11):
		leader_a.state_changed.disconnect(on_state11)
	await wait_process_frames(2)

	assert_true(bool(e11_fired["called"]), "E11: reentrant callback fired during dispatch")
	assert_false(dispatched11, "E11: _try_dispatch_unit_to_task returned false")
	assert_eq(task11.state, WorkTask.State.CANCELLED, "E11: task stayed CANCELLED (NEVER resurrected to IN_PROGRESS)")
	assert_null(board.get_active_task_for_source(t1), "E11: task absent from active board")
	assert_null(leader_a.get_current_order(), "E11: orphan order immediately unwound")
	assert_eq(leader_a.get_state(), Unit.State.IDLE, "E11: worker IDLE")
	assert_eq(t1.get_active_worker_count(), 0, "E11: zero orphan source reservation")
	leader_b.cancel_current_order()

	# E12: Reentrancy during board.task_closed (recursive cancel + manual order issuance inside listener)
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var task12 := board.get_active_task_for_source(t1)
	var u12 := task12.assigned_unit
	assert_not_null(u12, "E12: worker assigned")
	var reentrant_move := MoveOrder.new(Vector3(6.0, 0.0, 6.0))
	var e12_state := {"fired": false, "recursive_ok": true}
	var on_closed12 := func(closed_t: WorkTask) -> void:
		if closed_t != task12 or bool(e12_state["fired"]):
			return
		e12_state["fired"] = true
		var rec_res := agi.cancel_selected_category(&"wood")
		e12_state["recursive_ok"] = bool(rec_res.get("ok", true))
		u12.issue_order(reentrant_move)
	board.task_closed.connect(on_closed12)
	var c12 := agi.cancel_selected_category(&"wood")
	if board.task_closed.is_connected(on_closed12):
		board.task_closed.disconnect(on_closed12)
	await wait_process_frames(2)
	assert_true(bool(e12_state["fired"]), "E12: task_closed listener fired")
	assert_false(bool(e12_state["recursive_ok"]), "E12: recursive cancel was safe idempotent no-op")
	assert_eq(u12.get_current_order(), reentrant_move, "E12: personal order issued during task_closed was PRESERVED")
	assert_eq(int(c12.get("preserved_personal_orders_count", 0)), 1, "E12: preserved_personal_orders_count == 1")
	u12.cancel_current_order()

	# E13: Rapid cancel -> immediate reauthorization in same frame
	_select_sources(model, [t2])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var t13_old := board.get_active_task_for_source(t2)
	agi.cancel_selected_category(&"wood")
	var reauth13 := agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_true(bool(reauth13.get("ok", false)), "E13: rapid reauth ok")
	var t13_new := board.get_active_task_for_source(t2)
	assert_not_null(t13_new, "E13: new active task present")
	assert_ne(t13_new.task_id, t13_old.task_id, "E13: distinct task_id")
	assert_not_null(t13_new.assigned_unit, "E13: worker dispatched to new task")
	var ord13 := t13_new.assigned_order
	assert_not_null(ord13, "E13: fresh order created")
	assert_false(ord13.is_community_cancel_requested(), "E13: zero stale cancel flag on fresh order")
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(3)

	# E15: Group-FIFO fairness preserved after partial cancel
	leader_b.issue_order(MoveOrder.new(Vector3(-9.0, 0.0, -9.0)))
	leader_a.issue_order(MoveOrder.new(Vector3(-8.0, 0.0, -9.0)))
	_select_sources(model, [t1, t2])
	agi.authorize_selected_category(&"wood") # Group 1
	_select_sources(model, [r1])
	agi.authorize_selected_category(&"stone") # Group 2
	await wait_process_frames(2)
	# Cancel only t1 from Group 1 -> t2 (remaining in Group 1) must still dispatch before Group 2 (r1)
	_select_sources(model, [t1])
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	leader_a.cancel_current_order() # Free 1 worker
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_eq(board.get_active_task_for_source(t2).assigned_unit, leader_a, "E15: remaining Group 1 task dispatched ahead of Group 2")
	assert_null(board.get_active_task_for_source(r1).assigned_unit, "E15: Group 2 still waiting behind Group 1")
	leader_b.cancel_current_order()

	# E16: Invalid regional domain source explicitly rejected without affecting valid regional tasks
	var foreign_tree := TREE_SCENE.instantiate() as ResourceSource
	foreign_tree.name = "D2_E16_ForeignTree"
	foreign_tree.source_id = &"d2_e16_foreign_tree"
	foreign_tree.set_meta(&"region_id", &"foreign_region_beta")
	main.get_test_map().add_child(foreign_tree)
	await wait_physics_frames(1)
	var foreign_cancel := dispatcher.cancel_tasks_for_sources([foreign_tree], &"wood")
	assert_false(bool(foreign_cancel.get("ok", true)), "E16: foreign domain cancel rejected")
	assert_eq(String(foreign_cancel.get("reason", "")), "region_mismatch", "E16: exact region_mismatch reason")
	assert_eq(int(foreign_cancel.get("rejected_domain_count", 0)), 1, "E16: rejected_domain_count == 1")
	assert_not_null(board.get_active_task_for_source(t2), "E16: valid region task untouched")
	foreign_tree.get_parent().remove_child(foreign_tree)
	foreign_tree.queue_free()

	# E14: Clean teardown leaves zero tasks/errors
	agi.teardown_community_work()
	dispatcher.teardown()
	board.teardown()
	assert_eq(board.get_active_tasks().size(), 0, "E14: board clean after teardown")
	await _teardown_fixture(view)


# ==============================================================================
# U01-U20: D2-A Mineral "×" Seal HUD Geometry, Real Input Events, Anti-Click-Through, 720p & 1080p
# ==============================================================================
func test_d2_u01_u20_hud_cancel_seal_geometry_real_input_and_layouts() -> void:
	for vp_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var tag: String = "%dx%d" % [vp_size.x, vp_size.y]
		var view := await _fixture(vp_size)
		var main := view.get_child(0) as MainScene
		var hud := main.get_community_selection_actions_hud()
		var board := main.get_community_work_board()
		var model := main.get_source_selection_model()
		var agi := main.get_input_controller() as AutonomousGatherInput

		var t1 := _find_src(main, &"wood_tree_01")
		var t2 := _find_src(main, &"wood_tree_02")
		var t3 := _find_src(main, &"wood_tree_03")
		var t4 := _find_src(main, &"wood_tree_04")
		var r1 := _find_src(main, &"stone_rock_01")
		var f1 := _find_src(main, &"food_bush_01")

		# U01 + U16: No global stop button, D2.2 atlas intact, zero polling
		assert_false(hud.has_stop_button(), "%s U01: no global cancel-all stop button" % tag)
		assert_true(hud.is_atlas_loaded(), "%s U16: D2.2 atlas loaded" % tag)
		assert_eq(hud.get_atlas_region_key(), "slab_cmd_basalt", "%s U16: slab_cmd_basalt preserved" % tag)
		assert_false(hud.is_processing(), "%s U16: zero _process polling" % tag)
		assert_false(hud.is_physics_processing(), "%s U16: zero _physics_process polling" % tag)

		# U02: Selected sources with zero active tasks -> ALL cancel seals hidden
		_select_sources(model, [t1, r1, f1])
		await wait_process_frames(2)
		assert_false(hud.is_category_cancel_visible(&"wood"), "%s U02: wood seal hidden" % tag)
		assert_false(hud.is_category_cancel_visible(&"stone"), "%s U02: stone seal hidden" % tag)
		assert_false(hud.is_category_cancel_visible(&"food"), "%s U02: food seal hidden" % tag)

		# Record exact baseline slab rects BEFORE any seal appears (U07)
		var rect_w_base: Rect2 = hud.get_category_button(&"wood").get_global_rect()
		var rect_s_base: Rect2 = hud.get_category_button(&"stone").get_global_rect()
		var rect_f_base: Rect2 = hud.get_category_button(&"food").get_global_rect()

		# U09 + U03 + U06 + U07: Click wood authorize slab via REAL viewport input -> ONLY wood seal appears above wood slab, ZERO slab shift
		var w_btn_center: Vector2 = rect_w_base.get_center()
		await _click_viewport(view, w_btn_center, MOUSE_BUTTON_LEFT)
		await wait_process_frames(3)
		assert_not_null(board.get_active_task_for_source(t1), "%s U09: real click on wood slab authorized wood" % tag)
		assert_true(hud.is_category_cancel_visible(&"wood"), "%s U03: wood seal visible" % tag)
		assert_false(hud.is_category_cancel_visible(&"stone"), "%s U03: stone seal still hidden" % tag)
		assert_false(hud.is_category_cancel_visible(&"food"), "%s U03: food seal still hidden" % tag)
		assert_eq(hud.get_category_cancel_text(&"wood"), "×", "%s U05: full category shows ×" % tag)
		assert_eq(hud.get_category_cancel_count(&"wood"), 1, "%s U05: cancel count == 1" % tag)

		var w_seal: Button = hud.get_category_cancel_button(&"wood")
		assert_true(is_equal_approx(w_seal.size.x, CommunitySelectionActionsHud.SEAL_WIDTH_SINGLE), "%s U05: single width 34px" % tag)
		assert_eq(w_seal.tooltip_text, "Cancelar corte de madeira (1)", "%s U15: Portuguese tooltip" % tag)

		# U06: Geometry check — seal strictly centered above slab with 6 px gap to solid stone
		var w_seal_rect: Rect2 = w_seal.get_global_rect()
		var w_slab_rect: Rect2 = hud.get_category_button(&"wood").get_global_rect()
		assert_true(absf(w_seal_rect.get_center().x - w_slab_rect.get_center().x) <= 0.6, "%s U06: seal horizontally centered above slab" % tag)
		var solid_slab_top_y: float = w_slab_rect.position.y + CommunitySelectionActionsHud.SLAB_SHADOW_PAD_SCALED
		var gap_px: float = solid_slab_top_y - w_seal_rect.end.y
		assert_true(gap_px >= 5.5 and gap_px <= 6.5, "%s U06: 6px gap between seal and solid stone (got %.2f)" % [tag, gap_px])

		# U07: Zero horizontal/vertical shift of slabs
		assert_eq(hud.get_category_button(&"wood").get_global_rect(), rect_w_base, "%s U07: wood slab zero shift" % tag)
		assert_eq(hud.get_category_button(&"stone").get_global_rect(), rect_s_base, "%s U07: stone slab zero shift" % tag)
		assert_eq(hud.get_category_button(&"food").get_global_rect(), rect_f_base, "%s U07: food slab zero shift" % tag)

		# U10: Gap point does not hit seal or slab
		var gap_pt := Vector2(w_seal_rect.get_center().x, w_seal_rect.end.y + 3.0)
		assert_false(bool(w_seal.call("contains_global_point", gap_pt)), "%s U10: gap not inside seal" % tag)
		assert_false(bool(hud.get_category_button(&"wood").call("contains_global_point", gap_pt)), "%s U10: gap not inside slab" % tag)

		# U12: Polygonal hit-testing on seal (center inside, chamfered corner outside)
		assert_true(bool(w_seal.call("contains_local_point", w_seal.size * 0.5)), "%s U12: center inside octagon" % tag)
		assert_false(bool(w_seal.call("contains_local_point", Vector2(0.5, 0.5))), "%s U12: top-left chamfered corner outside octagon" % tag)

		# U13 + U14: Real RMB, MMB, and scroll wheel on seal NEVER trigger cancel
		await _click_viewport(view, w_seal_rect.get_center(), MOUSE_BUTTON_RIGHT)
		await _click_viewport(view, w_seal_rect.get_center(), MOUSE_BUTTON_MIDDLE)
		await _click_viewport(view, w_seal_rect.get_center(), MOUSE_BUTTON_WHEEL_UP)
		await wait_process_frames(2)
		assert_not_null(board.get_active_task_for_source(t1), "%s U13/U14: RMB/MMB/scroll did not cancel" % tag)

		# U18: LMB press inside seal + drag outside + release outside NEVER triggers cancel
		var press_ev := InputEventMouseButton.new()
		press_ev.button_index = MOUSE_BUTTON_LEFT
		press_ev.position = w_seal_rect.get_center()
		press_ev.global_position = w_seal_rect.get_center()
		press_ev.pressed = true
		view.push_input(press_ev, true)
		await wait_process_frames(1)
		var out_pt := w_seal_rect.get_center() + Vector2(0.0, -45.0)
		var drag_ev := InputEventMouseMotion.new()
		drag_ev.position = out_pt
		drag_ev.global_position = out_pt
		view.push_input(drag_ev, true)
		await wait_process_frames(1)
		var rel_ev := InputEventMouseButton.new()
		rel_ev.button_index = MOUSE_BUTTON_LEFT
		rel_ev.position = out_pt
		rel_ev.global_position = out_pt
		rel_ev.pressed = false
		view.push_input(rel_ev, true)
		await wait_process_frames(2)
		assert_not_null(board.get_active_task_for_source(t1), "%s U18: press-in release-out did not cancel" % tag)

		# Authorize stone & food too -> U19/U20 zero overlap with all 3 seals visible!
		await _click_viewport(view, rect_s_base.get_center(), MOUSE_BUTTON_LEFT)
		await _click_viewport(view, rect_f_base.get_center(), MOUSE_BUTTON_LEFT)
		await wait_process_frames(3)
		assert_true(hud.is_category_cancel_visible(&"wood") and hud.is_category_cancel_visible(&"stone") and hud.is_category_cancel_visible(&"food"), "%s U17: all 3 seals visible" % tag)
		assert_eq(hud.get_category_cancel_button(&"stone").tooltip_text, "Cancelar mineração (1)", "%s U15: stone tooltip" % tag)
		assert_eq(hud.get_category_cancel_button(&"food").tooltip_text, "Cancelar colheita (1)", "%s U15: food tooltip" % tag)

		var vp_rect := Rect2(Vector2.ZERO, Vector2(vp_size))
		var hud_rect := hud.get_panel_rect()
		assert_true(vp_rect.encloses(hud_rect), "%s U19/U20: HUD with 3 seals strictly inside viewport" % tag)
		var ui_layer := main.get_node_or_null("UiLayer")
		if ui_layer != null:
			for ch: Node in ui_layer.get_children():
				if ch == hud or not (ch is Control) or not (ch as Control).visible:
					continue
				if ch.has_method("get_panel_rect"):
					var other_r: Rect2 = ch.call("get_panel_rect") as Rect2
					if other_r.size.x > 0.0 and other_r.size.y > 0.0:
						assert_false(hud_rect.intersects(other_r), "%s U19/U20: zero overlap with %s" % [tag, ch.name])

		# U08 + U17: Real LMB click on stone seal cancels ONLY stone, keeps wood & food active, keeps selection, zero slab shift
		var s_seal_center: Vector2 = hud.get_category_cancel_button(&"stone").get_global_rect().get_center()
		await _click_viewport(view, s_seal_center, MOUSE_BUTTON_LEFT)
		await wait_process_frames(3)
		assert_null(board.get_active_task_for_source(r1), "%s U08/U17: stone cancelled via real click" % tag)
		assert_not_null(board.get_active_task_for_source(t1), "%s U17: wood preserved" % tag)
		assert_not_null(board.get_active_task_for_source(f1), "%s U17: food preserved" % tag)
		assert_false(hud.is_category_cancel_visible(&"stone"), "%s U08: stone seal hidden" % tag)
		assert_true(hud.is_category_cancel_visible(&"wood"), "%s U17: wood seal still visible" % tag)
		assert_true(hud.is_category_cancel_visible(&"food"), "%s U17: food seal still visible" % tag)
		assert_eq(hud.get_category_button(&"stone").get_global_rect(), rect_s_base, "%s U07: stone slab zero shift after cancel" % tag)

		# U05 partial: 2 of 4 trees authorized -> seal displays "×2" and width 44px
		_select_sources(model, [t1, t2])
		agi.authorize_selected_category(&"wood")
		_select_sources(model, [t1, t2, t3, t4])
		await wait_process_frames(2)
		assert_eq(hud.get_category_cancel_text(&"wood"), "×2", "%s U05: partial displays ×2" % tag)
		assert_eq(hud.get_category_cancel_count(&"wood"), 2, "%s U05: partial cancel count == 2" % tag)
		assert_true(is_equal_approx(hud.get_category_cancel_button(&"wood").size.x, CommunitySelectionActionsHud.SEAL_WIDTH_PARTIAL), "%s U05: partial width 44px" % tag)

		# U04 + U11: BLOCKED_REAUTHORIZATION & ECONOMY_BLOCKED both show enabled seal, real click cancels cleanly
		var tk_w := board.get_active_task_for_source(t1)
		tk_w.clear_assignment()
		tk_w.state = WorkTask.State.BLOCKED_REAUTHORIZATION
		tk_w.last_reason = WorkTask.REASON_ALL_WORKERS_EXCLUDED
		board.notify_task_updated(tk_w)
		_select_sources(model, [t1])
		await wait_process_frames(2)
		assert_true(hud.is_category_cancel_visible(&"wood"), "%s U04: seal visible for BLOCKED_REAUTHORIZATION" % tag)

		hud.configure(model, board, true, "simulated_econ_block_u11")
		await wait_process_frames(2)
		assert_true(hud.get_category_button(&"wood").disabled, "%s U11: authorize disabled under economy block" % tag)
		assert_true(hud.is_category_cancel_visible(&"wood") and not hud.get_category_cancel_button(&"wood").disabled, "%s U11: cancel seal enabled under economy block" % tag)
		await _click_viewport(view, hud.get_category_cancel_button(&"wood").get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		await wait_process_frames(3)
		assert_null(board.get_active_task_for_source(t1), "%s U11: real click on seal cancelled blocked task under economy block" % tag)
		assert_false(hud.is_category_cancel_visible(&"wood"), "%s U11: seal hidden after cancel" % tag)

		await _teardown_fixture(view)
