extends TestCase
## Adversarial integration suite for R-03A D2 R1 (D2-A01, D2-T01, D2-P01).
## Preserves tests/integration/test_r_03a_d2_selective_work_cancellation.gd untouched and complements:
## - T01-A / A01-R1..R7: Reentrant personal order sovereignty across worker_slot_released, state_changed,
##   empty immediate/retry/deferred cancels, active residual delivery, transactional guards, and task_closed,
##   proving physical advancement (not just order reference equality).
## - T01-B: Explicit reauthorization while previous order is actively executing residual delivery
##   (both with a second worker free and with a single worker occupied in residual delivery).
## - T01-C & T01-D: Real cancellation recovery lots (CANCEL_BUFFER / CANCEL_TRANSIT) via
##   ReservedWithdrawalCoordinator, public refusal of non-free cargo, and order-level mixed-cargo
##   selective delivery preserving exact lot_id/origin/quantity/site_id/generation/custody balance.
## - T01-E / E01 / E03 / E05 / E06 / E07: Delivery transfer boundary telemetry, receipts, and replay.
## - T01-F & T01-G: Selection mutation during task_closed, multi-target batch reentrancy, and HUD batch coalescing.
## - T01-H & T01-I: Dispatcher resumption, strictly verified mid-residual-delivery removals, and invalid World3D/meta domains.
## - Reconciled original D2 requirements: S06, S11, S12, O04, O07, U02, U03, U07, U12, U14, U15, U20.

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const C = preload("res://src/economy/reserved_withdrawal_coordinator.gd")


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
	assert_true(main.get_test_map().get_navigation().is_navigation_ready(), "R1 Fixture: navigation ready")
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


func _count_work_markers(src: ResourceSource) -> int:
	if src == null or not is_instance_valid(src):
		return 0
	var count: int = 0
	for ch: Node in src.get_children():
		if ch.name.begins_with(AutonomousGatherInput.WORK_MARKER_PREFIX) and not ch.is_queued_for_deletion():
			count += 1
	return count


func _total_resource_stock(main: MainScene, resource_id: StringName) -> int:
	var total: int = main.get_settlement_inventory().get_physical_amount(resource_id)
	for s: ResourceSource in main.get_test_map().get_all_region_resource_sources():
		if is_instance_valid(s) and s.get_resource_id() == resource_id:
			total += s.get_remaining_amount()
	for u: Unit in main.get_units():
		if is_instance_valid(u):
			total += u.get_carry_load().get_amount(resource_id)
	return total


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


func _wait_for_unit_cargo(unit: Unit, res_id: StringName, min_amount: int, max_frames: int = 1200) -> bool:
	Engine.time_scale = 3.0
	var ok: bool = false
	for _i: int in range(max_frames):
		if unit.get_carry_load().get_amount(res_id) >= min_amount:
			ok = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	return ok


func _wait_for_unit_idle(unit: Unit, max_frames: int = 1800) -> bool:
	Engine.time_scale = 3.0
	var ok: bool = false
	for _i: int in range(max_frames):
		if unit.get_current_order() == null and unit.get_state() == Unit.State.IDLE:
			ok = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	return ok


func _issue_personal_move(main: MainScene, unit: Unit, goal: Vector3) -> Dictionary:
	var sm: SelectionManager = main.get_selection_manager()
	var cmd: CommandController = main.get_command_controller()
	sm.select_single(unit)
	var pick := PickResult.from_ground(goal, Vector3.UP)
	var accepted: bool = cmd.command_at(pick)
	return {"accepted": accepted, "reason": cmd.get_last_command_reason()}


func _wait_until(predicate: Callable, max_frames: int = 2400) -> bool:
	Engine.time_scale = 3.0
	var ok: bool = false
	for _i: int in range(max_frames):
		if bool(predicate.call()):
			ok = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	return ok


# ==============================================================================
# T01-A / A01-R1..R7 / O08 / O09 / O10:
# Personal order sovereignty across every reentrant cancel/delivery boundary
# ==============================================================================
func test_r1_t01a_personal_order_sovereignty_and_reentrant_callbacks() -> void:
	# --- A01-R1: Personal order in worker_slot_released with real extracted FREE_GATHERED cargo ---
	var view1 := await _fixture()
	var main1 := view1.get_child(0) as MainScene
	var board1 := main1.get_community_work_board()
	var model1 := main1.get_source_selection_model()
	var agi1 := main1.get_input_controller() as AutonomousGatherInput
	var inv1 := main1.get_settlement_inventory()

	var f1 := _find_src(main1, &"food_bush_01")
	f1.set_gather_cycle_timings(0.20, 0.0)
	var inv_food_r1: int = inv1.get_physical_amount(&"food")
	_select_sources(model1, [f1])
	assert_true(bool(agi1.authorize_selected_category(&"food").get("ok", false)), "A01-R1: authorize food")
	await wait_process_frames(4)
	var task_r1 := board1.get_active_task_for_source(f1)
	assert_not_null(task_r1, "A01-R1: task active")
	var u_r1: Unit = task_r1.assigned_unit
	assert_not_null(u_r1, "A01-R1: worker assigned")
	var old_ord_r1 := u_r1.get_current_order() as GatherResourceOrder
	assert_not_null(old_ord_r1, "A01-R1: GatherResourceOrder running")
	assert_true(await _wait_for_unit_cargo(u_r1, &"food", 2), "A01-R1: worker extracted real food cargo")
	assert_eq(old_ord_r1.get_phase(), GatherResourceOrder.Phase.GATHERING, "A01-R1: still in GATHERING with partial cargo")
	assert_eq(f1.get_active_worker_count(), 1, "A01-R1: source slot reserved")

	var old_rev_r1: int = u_r1.get_order_revision()
	var cargo_snap_r1: Dictionary = u_r1.get_carry_load().provenance_snapshot()
	var f1_rem_r1: int = f1.get_remaining_amount()
	var personal_goal_r1 := Vector3(-10.0, 0.0, 8.0)
	var obs_r1 := {"fired": false, "personal_ok": false, "personal_ord": null, "target_in_cb": Vector3.INF}
	var cb_r1 := func(rel_src: ResourceSource) -> void:
		if rel_src != f1 or bool(obs_r1["fired"]):
			return
		obs_r1["fired"] = true
		var res := _issue_personal_move(main1, u_r1, personal_goal_r1)
		obs_r1["personal_ok"] = bool(res.get("accepted", false))
		obs_r1["personal_ord"] = u_r1.get_current_order()
		obs_r1["target_in_cb"] = u_r1.get_movement().get_target_position()
	f1.worker_slot_released.connect(cb_r1)
	var cancel_r1 := agi1.cancel_selected_category(&"food")
	if f1.worker_slot_released.is_connected(cb_r1):
		f1.worker_slot_released.disconnect(cb_r1)

	assert_true(bool(obs_r1["fired"]), "A01-R1: worker_slot_released callback fired")
	assert_true(bool(obs_r1["personal_ok"]), "A01-R1: personal MoveOrder accepted via CommandController")
	var p_ord_r1 := obs_r1["personal_ord"] as MoveOrder
	assert_not_null(p_ord_r1, "A01-R1: personal order is MoveOrder")
	assert_eq(u_r1.get_current_order(), p_ord_r1, "A01-R1: personal order remains active owner")
	assert_true(u_r1.get_order_revision() > old_rev_r1, "A01-R1: revision advanced strictly")
	assert_eq(u_r1.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A01-R1: movement stayed MOVING")
	assert_eq(u_r1.get_movement().get_target_position(), obs_r1["target_in_cb"], "A01-R1: target NEVER hijacked to camp")
	assert_eq(u_r1.get_movement().get_speed_context(), UnitMovement.SpeedContext.NORMAL, "A01-R1: speed context NORMAL")
	assert_null(old_ord_r1._deliver_order, "A01-R1: old order created ZERO _deliver_order")
	assert_eq(old_ord_r1.status, UnitOrder.Status.CANCELLED, "A01-R1: old order CANCELLED")
	assert_eq(int(cancel_r1.get("delivering_count", -1)), 0, "A01-R1: delivering_count == 0")
	assert_eq(int(cancel_r1.get("preserved_personal_orders_count", 0)), 1, "A01-R1: preserved_personal_orders_count == 1")
	assert_eq(task_r1.state, WorkTask.State.CANCELLED, "A01-R1: community task terminal CANCELLED")

	var dist0_r1: float = Vector2(u_r1.global_position.x - personal_goal_r1.x, u_r1.global_position.z - personal_goal_r1.z).length()
	assert_true(await _wait_until(func() -> bool: return p_ord_r1.is_finished(), 900), "A01-R1: personal order finishes physically")
	var dist1_r1: float = Vector2(u_r1.global_position.x - personal_goal_r1.x, u_r1.global_position.z - personal_goal_r1.z).length()
	assert_true(p_ord_r1.is_succeeded(), "A01-R1: personal MoveOrder SUCCEEDED")
	assert_true(dist1_r1 < dist0_r1 and dist1_r1 < 0.6, "A01-R1: unit physically arrived at personal destination (%.2f -> %.2f)" % [dist0_r1, dist1_r1])
	assert_eq(u_r1.get_carry_load().provenance_snapshot(), cargo_snap_r1, "A01-R1: cargo & provenance 100% intact")
	assert_eq(inv1.get_physical_amount(&"food"), inv_food_r1, "A01-R1: zero unintended camp delivery")
	assert_eq(f1.get_remaining_amount(), f1_rem_r1, "A01-R1: zero return extraction at cancelled bush")
	assert_null(board1.get_active_task_for_source(f1), "A01-R1: task never resurrected")

	# --- A01-R1b: Idempotent slot release when personal GatherResourceOrder targets SAME source in worker_slot_released ---
	var r1b := _find_src(main1, &"stone_rock_01")
	r1b.set_gather_cycle_timings(0.20, 0.0)
	var other_u1 := _find_unit(main1, &"leader_b") if u_r1.get_character_id() == &"leader_a" else _find_unit(main1, &"leader_a")
	other_u1.issue_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	# Drain u_r1's food first via legitimate delivery so u_r1 can gather r1b cleanly
	var clean_del := DeliverToCampOrder.new(main1.get_camp_storage_zone(), inv1, true, &"default", [])
	u_r1.issue_order(clean_del)
	assert_true(await _wait_until(func() -> bool: return clean_del.is_finished(), 1200), "A01-R1b: cleared previous cargo")
	_select_sources(model1, [r1b])
	agi1.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	assert_true(await _wait_for_unit_cargo(u_r1, &"stone", 1), "A01-R1b: extracted stone")
	var obs_r1b := {"fired": false, "personal_gather": null}
	var cb_r1b := func(rel_src: ResourceSource) -> void:
		if rel_src != r1b or bool(obs_r1b["fired"]):
			return
		obs_r1b["fired"] = true
		var p_gather := GatherResourceOrder.new(r1b, main1.get_camp_storage_zone(), inv1, 0.5, 0.0, true, &"default")
		u_r1.issue_order(p_gather)
		if u_r1.get_current_order() == p_gather:
			obs_r1b["personal_gather"] = p_gather
	r1b.worker_slot_released.connect(cb_r1b)
	agi1.cancel_selected_category(&"stone")
	if r1b.worker_slot_released.is_connected(cb_r1b):
		r1b.worker_slot_released.disconnect(cb_r1b)
	assert_true(bool(obs_r1b["fired"]), "A01-R1b: worker_slot_released fired")
	assert_not_null(obs_r1b["personal_gather"], "A01-R1b: personal GatherResourceOrder installed on same source")
	assert_eq(u_r1.get_current_order(), obs_r1b["personal_gather"], "A01-R1b: new personal GatherResourceOrder owns unit")
	assert_eq(r1b.get_active_worker_count(), 1, "A01-R1b: old order's idempotent release did NOT steal new order's worker slot")
	await _teardown_fixture(view1)

	# --- A01-R2: Personal order in unit.state_changed (-> TRANSPORTING) with real cargo ---
	var view2 := await _fixture()
	var main2 := view2.get_child(0) as MainScene
	var board2 := main2.get_community_work_board()
	var model2 := main2.get_source_selection_model()
	var agi2 := main2.get_input_controller() as AutonomousGatherInput
	var inv2 := main2.get_settlement_inventory()

	var f2 := _find_src(main2, &"food_bush_01")
	f2.set_gather_cycle_timings(0.20, 0.0)
	_select_sources(model2, [f2])
	agi2.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var task_r2 := board2.get_active_task_for_source(f2)
	var u_r2: Unit = task_r2.assigned_unit
	var old_ord_r2 := u_r2.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(u_r2, &"food", 2), "A01-R2: real food cargo extracted")
	var old_rev_r2: int = u_r2.get_order_revision()
	var cargo_snap_r2: Dictionary = u_r2.get_carry_load().provenance_snapshot()
	var personal_goal_r2 := Vector3(-10.0, 0.0, 8.0)
	var obs_r2 := {"fired": false, "personal_ok": false, "personal_ord": null, "target_in_cb": Vector3.INF}
	var cb_r2 := func(new_s: Unit.State, _old_s: Unit.State) -> void:
		if new_s != Unit.State.TRANSPORTING or bool(obs_r2["fired"]):
			return
		obs_r2["fired"] = true
		var res := _issue_personal_move(main2, u_r2, personal_goal_r2)
		obs_r2["personal_ok"] = bool(res.get("accepted", false))
		obs_r2["personal_ord"] = u_r2.get_current_order()
		obs_r2["target_in_cb"] = u_r2.get_movement().get_target_position()
	u_r2.state_changed.connect(cb_r2)
	var cancel_r2 := agi2.cancel_selected_category(&"food")
	if u_r2.state_changed.is_connected(cb_r2):
		u_r2.state_changed.disconnect(cb_r2)

	assert_true(bool(obs_r2["fired"]), "A01-R2: state_changed(TRANSPORTING) fired")
	assert_true(bool(obs_r2["personal_ok"]), "A01-R2: personal order accepted")
	var p_ord_r2 := obs_r2["personal_ord"] as MoveOrder
	assert_eq(u_r2.get_current_order(), p_ord_r2, "A01-R2: personal order preserved")
	assert_true(u_r2.get_order_revision() > old_rev_r2, "A01-R2: revision incremented")
	assert_eq(u_r2.get_movement().get_target_position(), obs_r2["target_in_cb"], "A01-R2: destination NEVER overwritten")
	assert_null(old_ord_r2._deliver_order, "A01-R2: old order created ZERO _deliver_order")
	assert_eq(int(cancel_r2.get("delivering_count", -1)), 0, "A01-R2: delivering_count == 0")
	assert_eq(int(cancel_r2.get("preserved_personal_orders_count", 0)), 1, "A01-R2: preserved_personal_orders_count == 1")
	assert_true(await _wait_until(func() -> bool: return p_ord_r2.is_finished(), 900), "A01-R2: personal order arrived")
	assert_true(p_ord_r2.is_succeeded(), "A01-R2: personal order SUCCEEDED")
	assert_eq(u_r2.get_carry_load().provenance_snapshot(), cargo_snap_r2, "A01-R2: cargo intact")
	assert_eq(inv2.get_physical_amount(&"food"), 0, "A01-R2: zero unintended deposit")
	await _teardown_fixture(view2)

	# --- A01-R3A (immediate empty), A01-R3B (RETRY_SCHEDULED empty), A01-R3C (deferred _finish_cancelled), A01-R4 (active residual delivery), A01-R5A (transactional lock) ---
	var view3 := await _fixture()
	var main3 := view3.get_child(0) as MainScene
	var board3 := main3.get_community_work_board()
	var model3 := main3.get_source_selection_model()
	var agi3 := main3.get_input_controller() as AutonomousGatherInput
	var inv3 := main3.get_settlement_inventory()

	# A01-R3A: Immediate empty cancel
	var t3 := _find_src(main3, &"wood_tree_01")
	_select_sources(model3, [t3])
	agi3.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var u_r3a: Unit = board3.get_active_task_for_source(t3).assigned_unit
	assert_eq(u_r3a.get_carry_load().get_current_weight(), 0, "A01-R3A: empty backpack")
	var goal_r3a := Vector3(-11.0, 0.0, 7.0)
	var obs_r3a := {"fired": false, "personal_ok": false, "personal_ord": null, "ms_cb": -1}
	var cb_r3a := func(rel_src: ResourceSource) -> void:
		if rel_src != t3 or bool(obs_r3a["fired"]):
			return
		obs_r3a["fired"] = true
		var res := _issue_personal_move(main3, u_r3a, goal_r3a)
		obs_r3a["personal_ok"] = bool(res.get("accepted", false))
		obs_r3a["personal_ord"] = u_r3a.get_current_order()
		obs_r3a["ms_cb"] = u_r3a.get_movement().get_move_state()
	t3.worker_slot_released.connect(cb_r3a)
	var cancel_r3a := agi3.cancel_selected_category(&"wood")
	if t3.worker_slot_released.is_connected(cb_r3a):
		t3.worker_slot_released.disconnect(cb_r3a)
	assert_true(bool(obs_r3a["fired"]), "A01-R3A: callback fired")
	assert_true(bool(obs_r3a["personal_ok"]), "A01-R3A: personal MoveOrder accepted")
	var p_ord_r3a := obs_r3a["personal_ord"] as MoveOrder
	assert_eq(u_r3a.get_current_order(), p_ord_r3a, "A01-R3A: personal order still current")
	assert_eq(p_ord_r3a.status, UnitOrder.Status.RUNNING, "A01-R3A: personal order RUNNING (not killed)")
	assert_eq(u_r3a.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A01-R3A: movement stayed MOVING")
	assert_eq(int(cancel_r3a.get("preserved_personal_orders_count", 0)), 1, "A01-R3A: preserved count == 1")
	assert_true(await _wait_until(func() -> bool: return p_ord_r3a.is_finished(), 900), "A01-R3A: personal order physically finished")
	assert_true(p_ord_r3a.is_succeeded(), "A01-R3A: personal order SUCCEEDED")

	# A01-R3B: RETRY_SCHEDULED empty cancel
	var r3b := _find_src(main3, &"stone_rock_01")
	r3b.set_gather_cycle_timings(0.10, 0.0)
	_select_sources(model3, [r3b])
	agi3.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	var u_r3b: Unit = board3.get_active_task_for_source(r3b).assigned_unit
	var ord_r3b := u_r3b.get_current_order() as GatherResourceOrder
	assert_true(await _wait_until(func() -> bool: return ord_r3b.get_phase() == GatherResourceOrder.Phase.GATHERING, 1200), "A01-R3B: reached GATHERING")
	u_r3b.get_carry_load().begin_batch()
	assert_true(await _wait_until(func() -> bool: return ord_r3b.get_active_gather_session() != null and ord_r3b.get_active_gather_session().is_retry_scheduled(), 400), "A01-R3B: entered RETRY_SCHEDULED")
	var goal_r3b := Vector3(-9.0, 0.0, 8.0)
	var obs_r3b := {"fired": false, "personal_ok": false, "personal_ord": null}
	var cb_r3b := func(rel_src: ResourceSource) -> void:
		if rel_src != r3b or bool(obs_r3b["fired"]):
			return
		obs_r3b["fired"] = true
		var res := _issue_personal_move(main3, u_r3b, goal_r3b)
		obs_r3b["personal_ok"] = bool(res.get("accepted", false))
		obs_r3b["personal_ord"] = u_r3b.get_current_order()
	r3b.worker_slot_released.connect(cb_r3b)
	var cancel_r3b := agi3.cancel_selected_category(&"stone")
	u_r3b.get_carry_load().end_batch()
	if r3b.worker_slot_released.is_connected(cb_r3b):
		r3b.worker_slot_released.disconnect(cb_r3b)
	var p_ord_r3b := obs_r3b["personal_ord"] as MoveOrder
	assert_true(bool(obs_r3b["fired"]) and bool(obs_r3b["personal_ok"]), "A01-R3B: personal order accepted in RETRY_SCHEDULED cancel")
	assert_eq(u_r3b.get_current_order(), p_ord_r3b, "A01-R3B: personal order preserved")
	assert_eq(u_r3b.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A01-R3B: movement MOVING")
	assert_eq(int(cancel_r3b.get("preserved_personal_orders_count", 0)), 1, "A01-R3B: preserved_personal_orders_count == 1")
	assert_true(await _wait_until(func() -> bool: return p_ord_r3b.is_finished(), 900) and p_ord_r3b.is_succeeded(), "A01-R3B: personal order physically arrived")

	# A01-R3C: Deferred _finish_cancelled() path via _apply_deferred_community_cancel()
	var t3c := _find_src(main3, &"wood_tree_02")
	_select_sources(model3, [t3c])
	agi3.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var u_r3c: Unit = board3.get_active_task_for_source(t3c).assigned_unit
	var ord_r3c := u_r3c.get_current_order() as GatherResourceOrder
	assert_eq(u_r3c.get_carry_load().get_current_weight(), 0, "A01-R3C: empty backpack")
	var goal_r3c := Vector3(-8.5, 0.0, 6.5)
	var obs_r3c := {"fired": false, "personal_ok": false, "personal_ord": null}
	var cb_r3c := func(rel_src: ResourceSource) -> void:
		if rel_src != t3c or bool(obs_r3c["fired"]):
			return
		obs_r3c["fired"] = true
		var res := _issue_personal_move(main3, u_r3c, goal_r3c)
		obs_r3c["personal_ok"] = bool(res.get("accepted", false))
		obs_r3c["personal_ord"] = u_r3c.get_current_order()
	t3c.worker_slot_released.connect(cb_r3c)
	ord_r3c._apply_deferred_community_cancel(u_r3c.get_movement())
	if t3c.worker_slot_released.is_connected(cb_r3c):
		t3c.worker_slot_released.disconnect(cb_r3c)
	var p_ord_r3c := obs_r3c["personal_ord"] as MoveOrder
	assert_true(bool(obs_r3c["fired"]) and bool(obs_r3c["personal_ok"]), "A01-R3C: personal order accepted in deferred _finish_cancelled")
	assert_eq(u_r3c.get_current_order(), p_ord_r3c, "A01-R3C: personal order preserved")
	assert_eq(u_r3c.get_movement().get_move_state(), UnitMovement.MoveState.MOVING, "A01-R3C: movement NOT stopped by deferred cleanup")
	assert_true(await _wait_until(func() -> bool: return p_ord_r3c.is_finished(), 900) and p_ord_r3c.is_succeeded(), "A01-R3C: personal order physically arrived")
	agi3.cancel_selected_category(&"wood")

	# A01-R4 / O09: Personal order during already-active residual delivery
	var f4 := _find_src(main3, &"food_bush_01")
	f4.set_gather_cycle_timings(0.20, 0.0)
	_select_sources(model3, [f4])
	agi3.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var task_r4 := board3.get_active_task_for_source(f4)
	var u_r4: Unit = task_r4.assigned_unit
	var ord_r4 := u_r4.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(u_r4, &"food", 2), "A01-R4: extracted food")
	var inv_food_r4: int = inv3.get_physical_amount(&"food")
	var f4_rem_r4: int = f4.get_remaining_amount()
	var cancel_r4 := agi3.cancel_selected_category(&"food")
	await wait_physics_frames(2)
	assert_eq(int(cancel_r4.get("delivering_count", 0)), 1, "A01-R4: residual delivery active")
	assert_eq(ord_r4.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "A01-R4: phase == DELIVERING_TO_CAMP")
	assert_true(ord_r4.is_stop_after_delivery_requested(), "A01-R4: stop_after_delivery == true")
	var cargo_r4: Dictionary = u_r4.get_carry_load().provenance_snapshot()
	var rev_before_r4: int = u_r4.get_order_revision()
	var goal_r4 := Vector3(-11.5, 0.0, 7.5)
	var res_r4 := _issue_personal_move(main3, u_r4, goal_r4)
	assert_true(bool(res_r4.get("accepted", false)), "A01-R4: personal order accepted during active residual delivery")
	var p_ord_r4 := u_r4.get_current_order() as MoveOrder
	assert_not_null(p_ord_r4, "A01-R4: MoveOrder installed")
	assert_true(u_r4.get_order_revision() > rev_before_r4, "A01-R4: revision advanced")
	assert_true(await _wait_until(func() -> bool: return p_ord_r4.is_finished(), 900) and p_ord_r4.is_succeeded(), "A01-R4: physically arrived at personal destination")
	for _i: int in range(30):
		await wait_physics_frames(1)
	assert_eq(u_r4.get_carry_load().provenance_snapshot(), cargo_r4, "A01-R4: cargo & provenance preserved")
	assert_eq(inv3.get_physical_amount(&"food"), inv_food_r4, "A01-R4: zero unintended delivery")
	assert_eq(f4.get_remaining_amount(), f4_rem_r4, "A01-R4: zero return to cancelled bush")
	assert_null(board3.get_active_task_for_source(f4), "A01-R4: task stayed cancelled")

	# A01-R5A: Transactional guard during real extraction amount_changed + clean acceptance right after unlock
	var clean_del_r5 := DeliverToCampOrder.new(main3.get_camp_storage_zone(), inv3, true, &"default", [])
	u_r4.issue_order(clean_del_r5)
	assert_true(await _wait_until(func() -> bool: return clean_del_r5.is_finished(), 1200), "A01-R5A: cleared prior cargo")
	var f5 := _find_src(main3, &"food_bush_02")
	f5.set_gather_cycle_timings(0.15, 0.0)
	_select_sources(model3, [f5])
	agi3.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var u_r5: Unit = board3.get_active_task_for_source(f5).assigned_unit
	var ord_r5 := u_r5.get_current_order() as GatherResourceOrder
	var obs_r5 := {"fired": false, "tx_exec": false, "coord_locked": false, "personal_ok": true, "reason": "", "cancel_def": 0}
	var cb_r5 := func(_src: ResourceSource, _rem: int, _d: int) -> void:
		if bool(obs_r5["fired"]):
			return
		obs_r5["fired"] = true
		obs_r5["tx_exec"] = ord_r5.is_provenance_transfer_executing()
		obs_r5["coord_locked"] = u_r5.get_carry_load()._coordinator_transaction_locked
		var cres := agi3.cancel_selected_category(&"food")
		obs_r5["cancel_def"] = int(cres.get("deferred_transfer_count", 0))
		var pres := _issue_personal_move(main3, u_r5, Vector3(-10.5, 0.0, 6.0))
		obs_r5["personal_ok"] = bool(pres.get("accepted", false))
		obs_r5["reason"] = String(pres.get("reason", ""))
	f5.amount_changed.connect(cb_r5)
	assert_true(await _wait_until(func() -> bool: return bool(obs_r5["fired"]), 1200), "A01-R5A: extraction amount_changed fired")
	if f5.amount_changed.is_connected(cb_r5):
		f5.amount_changed.disconnect(cb_r5)
	assert_true(bool(obs_r5["tx_exec"]), "A01-R5A: is_provenance_transfer_executing == true")
	assert_true(bool(obs_r5["coord_locked"]), "A01-R5A: coordinator transaction lock active")
	assert_eq(int(obs_r5["cancel_def"]), 1, "A01-R5A: cancel deferred during active transfer")
	assert_false(bool(obs_r5["personal_ok"]), "A01-R5A: personal order legitimately refused during active transaction")
	assert_eq(String(obs_r5["reason"]), "unit_transaction_locked", "A01-R5A: exact unit_transaction_locked reason")
	await wait_physics_frames(2)
	# Immediately after transactional unlock, personal order MUST be accepted cleanly!
	var after_unlock := _issue_personal_move(main3, u_r5, Vector3(-10.5, 0.0, 6.0))
	assert_true(bool(after_unlock.get("accepted", false)), "A01-R5A: personal order accepted immediately after unlock")
	var p_ord_r5 := u_r5.get_current_order() as MoveOrder
	assert_true(await _wait_until(func() -> bool: return p_ord_r5.is_finished(), 900) and p_ord_r5.is_succeeded(), "A01-R5A: post-unlock personal order arrived cleanly")

	# O08 (pre-existing personal order with revision + physical arrival) & A01-R7 (task_closed reentrancy)
	var u_o8 := _find_unit(main3, &"leader_a")
	var u_o8_other := _find_unit(main3, &"leader_b")
	var goal_o8 := Vector3(-11.0, 0.0, -7.0)
	var pre_res := _issue_personal_move(main3, u_o8, goal_o8)
	assert_true(bool(pre_res.get("accepted", false)), "O08: pre-existing personal order issued")
	var pre_ord := u_o8.get_current_order() as MoveOrder
	var pre_rev: int = u_o8.get_order_revision()
	var t_o8 := _find_src(main3, &"wood_tree_03")
	_select_sources(model3, [t_o8])
	agi3.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var obs_r7 := {"fired": false, "p_ok": false, "p_ord": null}
	var task_r7 := board3.get_active_task_for_source(t_o8)
	var cb_r7 := func(ct: WorkTask) -> void:
		if ct != task_r7 or bool(obs_r7["fired"]):
			return
		obs_r7["fired"] = true
		var r7_res := _issue_personal_move(main3, u_o8_other, Vector3(6.5, 0.0, -7.0))
		obs_r7["p_ok"] = bool(r7_res.get("accepted", false))
		obs_r7["p_ord"] = u_o8_other.get_current_order()
	board3.task_closed.connect(cb_r7)
	var cancel_r7 := agi3.cancel_selected_category(&"wood")
	if board3.task_closed.is_connected(cb_r7):
		board3.task_closed.disconnect(cb_r7)
	assert_eq(u_o8.get_current_order(), pre_ord, "O08: pre-existing personal order untouched")
	assert_eq(u_o8.get_order_revision(), pre_rev, "O08: pre-existing personal order revision unchanged")
	assert_true(bool(obs_r7["fired"]) and bool(obs_r7["p_ok"]), "A01-R7: personal order accepted during task_closed")
	assert_eq(int(cancel_r7.get("preserved_personal_orders_count", 0)), 1, "A01-R7: preserved_personal_orders_count == 1")
	var p_ord_r7 := obs_r7["p_ord"] as MoveOrder
	assert_true(await _wait_until(func() -> bool: return pre_ord.is_finished() and p_ord_r7.is_finished(), 1200), "O08/A01-R7: both personal orders finished physically")
	assert_true(pre_ord.is_succeeded() and p_ord_r7.is_succeeded(), "O08/A01-R7: both personal orders SUCCEEDED")

	await _teardown_fixture(view3)


# ==============================================================================
# T01-B / E13 / E14:
# Reauthorization while previous order is still actively delivering residual cargo
# ==============================================================================
func test_r1_t01b_reauthorization_during_active_residual_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()

	# Case 1: 2nd worker is free -> immediately takes fresh task while 1st worker finishes residual delivery
	var t1 := _find_src(main, &"wood_tree_01")
	t1.set_gather_cycle_timings(0.15, 0.0)
	var wood_tot0: int = _total_resource_stock(main, &"wood")
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var old_task := board.get_active_task_for_source(t1)
	var old_task_id: int = old_task.task_id
	var u1: Unit = old_task.assigned_unit
	var u2: Unit = _find_unit(main, &"leader_b") if u1.get_character_id() == &"leader_a" else _find_unit(main, &"leader_a")
	var old_ord := u1.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(u1, &"wood", 2), "T01-B1: u1 gathered wood")
	var carried_u1: int = u1.get_carry_load().get_amount(&"wood")

	var c1 := agi.cancel_selected_category(&"wood")
	assert_eq(int(c1.get("delivering_count", 0)), 1, "T01-B1: residual delivery started")
	assert_eq(old_ord.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "T01-B1: old_ord actively DELIVERING_TO_CAMP")
	assert_true(old_ord.is_stop_after_delivery_requested(), "T01-B1: stop_after_delivery active")

	# E14: Repeated cancel during active residual delivery is strictly idempotent no-op
	var c1_rep := agi.cancel_selected_category(&"wood")
	assert_false(bool(c1_rep.get("ok", true)), "E14/T01-B1: repeated cancel during residual delivery is no-op")
	assert_eq(int(c1_rep.get("cancelled_count", -1)), 0, "E14/T01-B1: 0 cancelled on repeat")

	# Reauthorize SAME tree while old_ord is still mid-delivery!
	var reauth1 := agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_true(bool(reauth1.get("ok", false)), "T01-B1: reauthorization accepted while residual delivery active")
	var new_task := board.get_active_task_for_source(t1)
	assert_not_null(new_task, "T01-B1: new task registered")
	assert_ne(new_task.task_id, old_task_id, "T01-B1: distinct new task_id")
	assert_eq(old_task.state, WorkTask.State.CANCELLED, "T01-B1: old task remained CANCELLED")
	assert_eq(new_task.assigned_unit, u2, "T01-B1: free 2nd worker dispatched to new task")
	assert_ne(new_task.assigned_order, old_ord, "T01-B1: new task created fresh order (never reused old_ord)")
	assert_false(new_task.assigned_order.is_community_cancel_requested(), "T01-B1: fresh order has no stale cancel flag")
	assert_eq(t1.get_active_worker_count(), 1, "T01-B1: strictly 1 worker slot reserved (no duplicate reservation)")

	# Wait for old_ord to finish strictly 1 delivery and become IDLE without touching new_task
	assert_true(await _wait_until(func() -> bool: return old_ord.is_finished(), 1800), "T01-B1: old_ord finished residual delivery")
	assert_true(old_ord.is_succeeded(), "T01-B1: old_ord SUCCEEDED")
	assert_eq(old_ord.get_delivered_trips(), 1, "T01-B1: strictly 1 trip on old_ord")
	assert_true(inv.get_physical_amount(&"wood") >= carried_u1, "T01-B1: residual cargo deposited to camp")
	assert_eq(new_task.state, WorkTask.State.IN_PROGRESS, "T01-B1: old_ord finish did NOT alter new_task")
	assert_eq(new_task.assigned_unit, u2, "T01-B1: u2 still assigned to new_task")
	assert_eq(_total_resource_stock(main, &"wood"), wood_tot0, "T01-B1: 100% wood conservation")

	# Cleanup Case 1
	agi.cancel_selected_category(&"wood")
	for u: Unit in main.get_units():
		u.cancel_current_order()
	await wait_process_frames(3)
	for u: Unit in main.get_units():
		if not u.get_carry_load().is_empty():
			var d := DeliverToCampOrder.new(main.get_camp_storage_zone(), inv, true, &"default", [])
			u.issue_order(d)
			await _wait_until(func() -> bool: return d.is_finished(), 1200)

	# Case 2: Single worker available (2nd worker occupied by personal MoveOrder)
	var r1 := _find_src(main, &"stone_rock_01")
	r1.set_gather_cycle_timings(0.15, 0.0)
	var stone_tot0: int = _total_resource_stock(main, &"stone")
	var busy_u := _find_unit(main, &"leader_b")
	var sole_u := _find_unit(main, &"leader_a")
	busy_u.issue_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	# Keep busy_u held on a permanent-like move or re-issue after arrival via ConstructOrder? Use Gather on distant wait:
	# Better: hold busy_u with MoveOrder far enough or check during dispatch before busy_u arrives.
	_select_sources(model, [r1])
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	var old_t2 := board.get_active_task_for_source(r1)
	assert_eq(old_t2.assigned_unit, sole_u, "T01-B2: sole_u assigned")
	var old_o2 := sole_u.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(sole_u, &"stone", 1), "T01-B2: sole_u extracted stone")
	# Keep busy_u occupied during cancel + reauth + delivery!
	busy_u.issue_order(MoveOrder.new(Vector3(12.0, 0.0, -10.0)))
	var c2 := agi.cancel_selected_category(&"stone")
	assert_eq(int(c2.get("delivering_count", 0)), 1, "T01-B2: sole_u entered residual delivery")
	assert_eq(old_o2.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "T01-B2: delivering confirmed")
	assert_true(old_o2.is_stop_after_delivery_requested(), "T01-B2: stop_after_delivery confirmed")

	# Reauthorize while sole_u is busy delivering and busy_u is occupied
	var reauth2 := agi.authorize_selected_category(&"stone")
	await wait_process_frames(3)
	assert_true(bool(reauth2.get("ok", false)), "T01-B2: reauth succeeded")
	var new_t2 := board.get_active_task_for_source(r1)
	assert_ne(new_t2.task_id, old_t2.task_id, "T01-B2: new task_id")
	assert_eq(new_t2.state, WorkTask.State.PENDING_WORKERS, "T01-B2: new task waits in PENDING_WORKERS while sole_u finishes residual delivery")
	assert_null(new_t2.assigned_unit, "T01-B2: zero premature assignment")

	# Keep busy_u occupied while sole_u completes old_o2, then confirm sole_u receives a BRAND-NEW order for new_t2!
	var keep_busy_flag := {"stop": false}
	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if busy_u.get_current_order() == null:
			busy_u.issue_order(MoveOrder.new(Vector3(-12.0 if _i % 2 == 0 else 12.0, 0.0, -10.0)))
		if new_t2.assigned_unit == sole_u:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_false(bool(keep_busy_flag["stop"]), "T01-B2: loop finished cleanly")
	assert_true(old_o2.is_succeeded(), "T01-B2: old_o2 completed residual delivery")
	assert_eq(old_o2.get_delivered_trips(), 1, "T01-B2: old_o2 made strictly 1 delivery and never returned under old_o2")
	assert_eq(new_t2.assigned_unit, sole_u, "T01-B2: sole_u dispatched to new_t2 AFTER finishing residual delivery")
	assert_ne(new_t2.assigned_order, old_o2, "T01-B2: brand-new GatherResourceOrder created for new_t2")
	assert_eq(_total_resource_stock(main, &"stone"), stone_tot0, "T01-B2: 100% stone conservation")

	await _teardown_fixture(view)


# ==============================================================================
# T01-C & T01-D / E09 / E10 / E15:
# Real CANCEL_BUFFER / CANCEL_TRANSIT recovery lots, public refusal,
# order-level mixed cargo defense-in-depth, and multi-custody conservation
# ==============================================================================
func test_r1_t01c_t01d_recovery_lots_and_mixed_cargo_conservation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()
	var cm := main.get_construction_manager()
	var cmd := main.get_command_controller()

	# Prepare legitimate ConstructionSite and cancel it after partial work to produce REAL CancellationCustodyRecord + CANCEL_BUFFER lots
	assert_true(inv.deposit(&"wood", 12), "T01-C: deposit initial wood")
	assert_true(inv.deposit(&"stone", 6), "T01-C: deposit initial stone")
	var site_res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site_res.get("ok", false)), "T01-C: real ConstructionSite created")
	var site: ConstructionSite = site_res.get("site") as ConstructionSite
	assert_true(cmd.command_units_to_site(site, main.get_units()), "T01-C: units building site")
	assert_true(await _wait_until(func() -> bool: return site._work_progress_usec >= 15_000_000, 6500), "T01-C: real construction progress reached")

	var cancel_site_res: Dictionary = C.execute_site_cancellation(site, &"r1_t01c_site_cancel")
	assert_true(bool(cancel_site_res.get("ok", false)), "T01-C: execute_site_cancellation succeeded")
	var cancel_id: StringName = StringName(cancel_site_res["receipt"]["cancel_id"])
	var domains: Dictionary = main.get_world_3d().get_meta(C.DOMAIN_META)
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = domains[&"default"].cancellation_custodies[cancel_id]
	assert_not_null(record, "T01-C: real CancellationCustodyRecord created")
	assert_true(C.validate_custody_accounting_pure(record).ok, "T01-C: custody accounting valid after site cancel")

	# Clear active ConstructOrders and drain any in-transit CANCEL_TRANSIT lots first, or inspect them directly
	for u: Unit in main.get_units():
		u.cancel_current_order()
	await wait_physics_frames(2)

	var u_rec: Unit = _find_unit(main, &"leader_a")
	var u_other: Unit = _find_unit(main, &"leader_b")

	# Walk u_rec to anchor and legitimately recover a real CANCEL_BUFFER lot via ReservedWithdrawalCoordinator
	var approach_pt: Vector3 = record.anchor_position + Vector3(-record.footprint_size.x * 0.5 - 0.4, 0.0, 0.0)
	var walk_rec := MoveOrder.new(approach_pt)
	u_rec.issue_order(walk_rec)
	assert_true(await _wait_until(func() -> bool: return walk_rec.is_finished(), 2400) and walk_rec.is_succeeded(), "T01-C: u_rec walked to custody anchor")

	var buf_requests: Array[Dictionary] = []
	for res_k: StringName in record.local_buffer_remaining.keys():
		var amt: int = int(record.local_buffer_remaining[res_k])
		if amt > 0:
			buf_requests.append({
				"lot_id": StringName("r1_t01c_buf_%s" % String(res_k)),
				"resource_id": res_k,
				"amount": mini(amt, 2),
				"origin": CarryProvenanceLedger.CANCEL_BUFFER,
			})
			break
	assert_false(buf_requests.is_empty(), "T01-C: real local_buffer_remaining present for recovery")
	var pickup_res: Dictionary = C.recover_cancellation_materials(cancel_id, u_rec, buf_requests, &"r1_t01c_pickup")
	assert_true(bool(pickup_res.get("ok", false)), "T01-C: real CANCEL_BUFFER lot legitimately recovered onto u_rec")
	assert_true(C.validate_custody_accounting_pure(record).ok, "T01-C: custody accounting valid after recovery pickup")

	var rec_lot_id: StringName = StringName(buf_requests[0]["lot_id"])
	var rec_snap_before: Dictionary = u_rec.get_carry_load().provenance_snapshot()
	var custody_before: Dictionary = record.to_snapshot_dict()

	# PART 1 (Public path): Occupy u_other so only u_rec is idle -> public dispatcher MUST refuse u_rec with reserved_or_recovery_cargo!
	u_other.issue_order(MoveOrder.new(Vector3(10.0, 0.0, 10.0)))
	var t1 := _find_src(main, &"wood_tree_01")
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(5)
	await wait_physics_frames(3)
	var tk_pub := board.get_active_task_for_source(t1)
	assert_not_null(tk_pub, "T01-C public: task registered")
	assert_null(tk_pub.assigned_unit, "T01-C public: worker carrying CANCEL_BUFFER legitimately refused for community work")
	assert_null(u_rec.get_current_order(), "T01-C public: u_rec never received GatherResourceOrder")
	var c_pub := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_true(bool(c_pub.get("ok", false)), "T01-C public: pending task cancelled cleanly")
	assert_eq(u_rec.get_carry_load().provenance_snapshot(), rec_snap_before, "T01-C public: CANCEL_BUFFER lot 100% untouched")
	assert_eq(record.to_snapshot_dict(), custody_before, "T01-C public: CancellationCustodyRecord 100% untouched")
	assert_true(C.validate_custody_accounting_pure(record).ok, "T01-C public: custody accounting intact")

	# PART 2 (Order-level defense-in-depth with MIXED cargo: real CANCEL_BUFFER + SITE_RESERVED + FREE_GATHERED):
	# Add a SITE_RESERVED lot and a FREE_GATHERED wood lot onto u_rec, start GatherResourceOrder, and invoke cooperative cancel!
	var res_lot_id := &"r1_t01d_site_reserved_stone"
	var free_lot_id := &"r1_t01d_free_wood"
	assert_true(bool(CarryFixture.add_lot(
		u_rec.get_carry_load(), &"op_r1_t01d_res", res_lot_id, &"stone", STONE_DEF.unit_weight, 1, CarryProvenanceLedger.SITE_RESERVED, &"site_r1_t01d"
	).get("ok", false)), "T01-D: added SITE_RESERVED lot")
	assert_true(bool(CarryFixture.add_lot(
		u_rec.get_carry_load(), &"op_r1_t01d_free", free_lot_id, &"wood", WOOD_DEF.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED
	).get("ok", false)), "T01-D: added FREE_GATHERED lot (2 wood)")

	var lots_before: Dictionary = (u_rec.get_carry_load().provenance_snapshot()["ledger"]["lots"] as Dictionary).duplicate(true)
	assert_true(lots_before.has(rec_lot_id), "T01-D: CANCEL_BUFFER lot present before")
	assert_true(lots_before.has(res_lot_id), "T01-D: SITE_RESERVED lot present before")
	assert_true(lots_before.has(free_lot_id), "T01-D: FREE_GATHERED lot present before")

	var inv_wood_before: int = inv.get_physical_amount(&"wood")
	var inv_stone_before: int = inv.get_physical_amount(&"stone")
	var t1_rem_before: int = t1.get_remaining_amount()
	var mixed_ord := GatherResourceOrder.new(t1, main.get_camp_storage_zone(), inv, 0.5, 0.0, true, &"default")
	u_rec.issue_order(mixed_ord)
	assert_eq(u_rec.get_current_order(), mixed_ord, "T01-D: GatherResourceOrder installed for defense-in-depth test")
	await wait_physics_frames(2)

	var req_mixed := mixed_ord.request_community_cancel(u_rec.get_movement())
	assert_eq(String(req_mixed.get("action", "")), "transitioned_to_final_delivery", "T01-D: mixed cargo transitions to selective final delivery of FREE_GATHERED only")
	assert_true(await _wait_until(func() -> bool: return mixed_ord.is_finished(), 2400), "T01-D: selective final delivery finished")
	assert_true(mixed_ord.is_succeeded(), "T01-D: selective final delivery SUCCEEDED")
	assert_eq(inv.get_physical_amount(&"wood") - inv_wood_before, 2, "T01-D: strictly 2 FREE_GATHERED wood delivered to camp")
	assert_eq(inv.get_physical_amount(&"stone"), inv_stone_before, "T01-D: ZERO reserved/recovery stone delivered to camp")
	assert_eq(t1.get_remaining_amount(), t1_rem_before, "T01-D: zero extra extraction from source")

	var lots_after: Dictionary = (u_rec.get_carry_load().provenance_snapshot()["ledger"]["lots"] as Dictionary)
	assert_false(lots_after.has(free_lot_id), "T01-D: FREE_GATHERED lot unloaded cleanly")
	assert_true(lots_after.has(rec_lot_id), "T01-D: CANCEL_BUFFER lot preserved")
	assert_true(lots_after.has(res_lot_id), "T01-D: SITE_RESERVED lot preserved")
	assert_eq(lots_after[rec_lot_id], lots_before[rec_lot_id], "T01-D: CANCEL_BUFFER identity/origin/quantity/site_id/generation/region 100% IDENTICAL")
	assert_eq(lots_after[res_lot_id], lots_before[res_lot_id], "T01-D: SITE_RESERVED identity/origin/quantity/site_id/generation/region 100% IDENTICAL")
	assert_true(u_rec.get_carry_load().validate_provenance(), "T01-D: provenance ledger valid")
	assert_eq(record.to_snapshot_dict(), custody_before, "T01-D: CancellationCustodyRecord untouched by community delivery")
	assert_true(C.validate_custody_accounting_pure(record).ok, "T01-D: custody accounting 100% balanced")

	await _teardown_fixture(view)


# ==============================================================================
# T01-E / E01 / E03 / E05 / E06 / E07 / A01-R5B / A01-R6:
# Pre-commit, post-commit receipts, delivery transfer boundary telemetry & replay
# ==============================================================================
func test_r1_t01e_delivery_transfer_boundary_telemetry_and_receipts() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()

	# E01: Cancel strictly before extraction commit -> empty extraction receipt, 0 cycles
	var r_pre := _find_src(main, &"stone_rock_01")
	r_pre.set_gather_cycle_timings(5.0, 0.0)
	var r_pre_rem: int = r_pre.get_remaining_amount()
	_select_sources(model, [r_pre])
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	var u_pre: Unit = board.get_active_task_for_source(r_pre).assigned_unit
	var ord_pre := u_pre.get_current_order() as GatherResourceOrder
	assert_true(await _wait_until(func() -> bool: return ord_pre.get_phase() == GatherResourceOrder.Phase.GATHERING, 1200), "E01: reached GATHERING pre-commit")
	var c_pre := agi.cancel_selected_category(&"stone")
	assert_eq(int(c_pre.get("stopped_immediately_count", 0)), 1, "E01: stopped immediately pre-commit")
	assert_true(ord_pre.last_extraction_receipt.is_empty(), "E01: zero extraction receipt committed")
	assert_eq(ord_pre.get_extraction_cycles_completed(), 0, "E01: 0 extraction cycles")
	assert_eq(r_pre.get_remaining_amount(), r_pre_rem, "E01: source untouched")

	# T01-E / E03 / E05 / E06 / E07 / A01-R5B / A01-R6:
	# Real delivery transfer boundary telemetry inside inventory_changed + delivery receipt + delivery replay idempotency
	var t1 := _find_src(main, &"wood_tree_01")
	t1.set_gather_cycle_timings(0.10, 0.0)
	var wood_tot0: int = _total_resource_stock(main, &"wood")
	var inv_wood0: int = inv.get_physical_amount(&"wood")
	_select_sources(model, [t1])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var task_e := board.get_active_task_for_source(t1)
	var u_e: Unit = task_e.assigned_unit
	var ord_e := u_e.get_current_order() as GatherResourceOrder

	var obs := {
		"fired": false,
		"tx_exec": false,
		"deliver_exec": false,
		"region_exec": false,
		"coord_locked": false,
		"inv_at_cb": -1,
		"carry_at_cb": -1,
		"personal_ok": true,
		"personal_reason": "",
		"cancel_res": {},
		"rem_at_cb": -1,
	}
	var on_inv := func() -> void:
		if bool(obs["fired"]):
			return
		if ord_e.get_phase() == GatherResourceOrder.Phase.DELIVERING_TO_CAMP:
			obs["fired"] = true
			obs["tx_exec"] = ord_e.is_provenance_transfer_executing()
			obs["deliver_exec"] = ord_e._deliver_order != null and ord_e._deliver_order.is_selective_transfer_executing()
			var domains: Dictionary = main.get_world_3d().get_meta(C.DOMAIN_META, {})
			var auth: Variant = domains.get(&"default", null)
			obs["region_exec"] = auth != null and bool(auth.is_executing)
			obs["coord_locked"] = u_e.get_carry_load()._coordinator_transaction_locked
			obs["inv_at_cb"] = inv.get_physical_amount(&"wood")
			obs["carry_at_cb"] = u_e.get_carry_load().get_amount(&"wood")
			obs["rem_at_cb"] = t1.get_remaining_amount()
			var p_res := _issue_personal_move(main, u_e, Vector3(-9.0, 0.0, 7.0))
			obs["personal_ok"] = bool(p_res.get("accepted", false))
			obs["personal_reason"] = String(p_res.get("reason", ""))
			obs["cancel_res"] = agi.cancel_selected_category(&"wood")
	inv.inventory_changed.connect(on_inv)
	assert_true(await _wait_until(func() -> bool: return bool(obs["fired"]) and u_e.get_current_order() == null and u_e.get_state() == Unit.State.IDLE, 2400), "T01-E: delivery completed cleanly")
	if inv.inventory_changed.is_connected(on_inv):
		inv.inventory_changed.disconnect(on_inv)
	for _i: int in range(30):
		await wait_physics_frames(1)

	# Assert exact post-commit-under-active-transactional-lock telemetry (E06/E07/A01-R5B/A01-R6)
	assert_true(bool(obs["fired"]), "T01-E: inventory_changed fired during delivery")
	assert_true(bool(obs["tx_exec"]), "T01-E: order.is_provenance_transfer_executing() == true")
	assert_true(bool(obs["deliver_exec"]), "T01-E: _deliver_order.is_provenance_transfer_executing() == true")
	assert_true(bool(obs["region_exec"]), "T01-E/E07: RegionalAuthority.is_executing == true")
	assert_true(bool(obs["coord_locked"]), "T01-E/A01-R6: _coordinator_transaction_locked == true")
	assert_true(int(obs["inv_at_cb"]) > inv_wood0 and int(obs["carry_at_cb"]) == 0, "T01-E: signal confirmed post-commit while lock still held")
	assert_false(bool(obs["personal_ok"]), "T01-E/A01-R6: personal order legitimately blocked under lock")
	assert_eq(String(obs["personal_reason"]), "unit_transaction_locked", "T01-E: exact lock refusal reason")
	assert_eq(task_e.state, WorkTask.State.CANCELLED, "T01-E: task closed CANCELLED")
	assert_true(ord_e.is_succeeded(), "T01-E: delivery order SUCCEEDED")
	assert_eq(ord_e.get_delivered_trips(), 1, "T01-E: strictly 1 delivery trip")
	assert_eq(t1.get_remaining_amount(), int(obs["rem_at_cb"]), "T01-E: zero return to tree")
	assert_eq(_total_resource_stock(main, &"wood"), wood_tot0, "T01-E: 100% wood conservation")

	# E03 & E05: Verify extraction receipt + delivery receipt + delivery replay idempotency
	assert_false(ord_e.last_extraction_receipt.is_empty(), "E03: extraction receipt populated")
	assert_false(ord_e.last_delivery_receipt.is_empty(), "E03/T01-E: delivery receipt populated")
	var del_op_id: StringName = StringName(ord_e.last_delivery_receipt.get("operation_id", &""))
	assert_ne(del_op_id, &"", "T01-E: delivery receipt has valid operation_id")
	var inv_before_replay: int = inv.get_physical_amount(&"wood")
	var del_coord := SelectiveCampDeliveryCoordinator.new()
	var del_replay: Dictionary = del_coord.execute_selective_camp_delivery(inv, main.get_camp_storage_zone(), u_e, &"default", del_op_id, [])
	assert_true(bool(del_replay.get("ok", false)) and bool(del_replay.get("replayed", false)), "E05/T01-E: delivery replay flagged idempotent")
	assert_eq(inv.get_physical_amount(&"wood"), inv_before_replay, "E05/T01-E: delivery replay added ZERO duplicate stock")
	assert_eq(_total_resource_stock(main, &"wood"), wood_tot0, "E05/T01-E: total conservation unchanged after replay")

	await _teardown_fixture(view)


# ==============================================================================
# T01-F & T01-G / S13 / E12 / E14 / D2-P01 HUD batch coalescing:
# Selection mutation during callback + multi-target batch reentrancy
# ==============================================================================
func test_r1_t01f_t01g_batch_reentrancy_selection_mutation_and_multi_target_callbacks() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var hud := main.get_community_selection_actions_hud()

	var t1 := _find_src(main, &"wood_tree_01")
	var t2 := _find_src(main, &"wood_tree_02")
	var t3 := _find_src(main, &"wood_tree_03")
	var t4 := _find_src(main, &"wood_tree_04")
	var t5 := _find_src(main, &"wood_tree_05")
	var r1 := _find_src(main, &"stone_rock_01")
	var r2 := _find_src(main, &"stone_rock_02")
	var f1 := _find_src(main, &"food_bush_01")
	var f2 := _find_src(main, &"food_bush_02")

	# --- T01-F / S13: Mutate SourceSelectionModel during task_closed ---
	_select_sources(model, [t1, t2, t3, t4, t5])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var tk1 := board.get_active_task_for_source(t1)
	var tk2 := board.get_active_task_for_source(t2)
	var tk3 := board.get_active_task_for_source(t3)
	var tk4 := board.get_active_task_for_source(t4)
	var tk5 := board.get_active_task_for_source(t5)

	# Select only [t1, t2]; when t1 closes, mutate selection to add t3, t4 and remove t2!
	_select_sources(model, [t1, t2])
	var mutated := {"done": false}
	var cb_f := func(closed_t: WorkTask) -> void:
		if closed_t == tk1 and not bool(mutated["done"]):
			mutated["done"] = true
			model.add_sources([t3, t4])
			model.deselect_source(t2)
	board.task_closed.connect(cb_f)
	var hud_ref_before: int = hud.get_refresh_invocation_count()
	var c_f := agi.cancel_selected_category(&"wood")
	var hud_ref_after: int = hud.get_refresh_invocation_count()
	if board.task_closed.is_connected(cb_f):
		board.task_closed.disconnect(cb_f)

	assert_true(bool(mutated["done"]), "T01-F: selection mutated during task_closed")
	assert_eq(int(c_f.get("cancelled_count", 0)), 2, "T01-F: strictly original snapshot [t1, t2] cancelled")
	assert_eq(tk1.state, WorkTask.State.CANCELLED, "T01-F: t1 cancelled")
	assert_eq(tk2.state, WorkTask.State.CANCELLED, "T01-F: t2 cancelled (snapshot immutable)")
	assert_true(tk3.is_active(), "T01-F: newly selected t3 NOT cancelled")
	assert_true(tk4.is_active(), "T01-F: newly selected t4 NOT cancelled")
	assert_true(tk5.is_active(), "T01-F: unselected t5 NOT cancelled")
	assert_true(model.is_selected(t3) and model.is_selected(t4), "T01-F: new legitimate selections preserved")
	assert_false(model.is_selected(t2), "T01-F: callback deselection of t2 preserved")
	assert_eq(hud_ref_after - hud_ref_before, 1, "D2-P01/T01-F: HUD coalesced multi-task cancel + selection change into 1 refresh")
	assert_eq(hud.get_last_refresh_count(), 1, "D2-P01: get_last_refresh_count() == 1")
	assert_eq(hud.get_category_cancel_count(&"wood"), 2, "T01-F: HUD reflects exact final cancellable count (t3, t4)")

	# Cleanup before T01-G
	_select_sources(model, [t3, t4, t5])
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(3)
	assert_eq(board.get_active_tasks().size(), 0, "T01-G pre-clean")

	# --- T01-G: Multi-target batch reentrancy ---
	_select_sources(model, [t1, t2, t3, r1, r2, f1])
	agi.authorize_selected_category(&"wood")
	agi.authorize_selected_category(&"stone")
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var g_t1 := board.get_active_task_for_source(t1)
	var g_t2 := board.get_active_task_for_source(t2)
	var g_t3 := board.get_active_task_for_source(t3)
	var g_r1 := board.get_active_task_for_source(r1)
	var g_r2 := board.get_active_task_for_source(r2)
	var g_f1 := board.get_active_task_for_source(f1)
	var active_u: Unit = g_t1.assigned_unit if g_t1.assigned_unit != null else _find_unit(main, &"leader_a")

	var close_counts: Dictionary = {}
	var g_obs := {"reentered": false, "repeat_wood_ok": true, "stone_cancel_cnt": 0, "new_food_ok": false, "personal_ok": false, "personal_ord": null}
	var cb_g := func(closed_t: WorkTask) -> void:
		close_counts[closed_t.task_id] = int(close_counts.get(closed_t.task_id, 0)) + 1
		if closed_t == g_t1 and not bool(g_obs["reentered"]):
			g_obs["reentered"] = true
			# 1. Repeated wood cancel (overlapping subset [t2, t3])
			var rep_sub := main.get_community_task_dispatcher().cancel_tasks_for_sources([t1, t2], &"wood")
			g_obs["repeat_wood_ok"] = bool(rep_sub.get("ok", false))
			# 2. Explicit stone cancel
			var st_c := agi.cancel_selected_category(&"stone")
			g_obs["stone_cancel_cnt"] = int(st_c.get("cancelled_count", 0))
			# 3. New authorization of f2 during callback
			model.add_sources([f2])
			var nf := agi.authorize_selected_category(&"food")
			g_obs["new_food_ok"] = bool(nf.get("ok", false))
			# 4. Personal order on active worker
			var pr := _issue_personal_move(main, active_u, Vector3(-10.0, 0.0, 8.0))
			g_obs["personal_ok"] = bool(pr.get("accepted", false))
			g_obs["personal_ord"] = active_u.get_current_order()
	board.task_closed.connect(cb_g)
	var c_g := agi.cancel_selected_category(&"wood")
	if board.task_closed.is_connected(cb_g):
		board.task_closed.disconnect(cb_g)
	await wait_process_frames(3)

	assert_true(bool(g_obs["reentered"]), "T01-G: multi-target batch callback executed")
	assert_eq(int(g_obs["stone_cancel_cnt"]), 2, "T01-G: explicit nested stone cancel closed 2 rocks")
	assert_true(bool(g_obs["new_food_ok"]), "T01-G: new authorization of f2 admitted separately")
	assert_true(bool(g_obs["personal_ok"]), "T01-G: personal order accepted in callback")
	assert_eq(g_t1.state, WorkTask.State.CANCELLED, "T01-G: t1 closed")
	assert_eq(g_t2.state, WorkTask.State.CANCELLED, "T01-G: t2 closed")
	assert_eq(g_t3.state, WorkTask.State.CANCELLED, "T01-G: t3 closed")
	assert_eq(g_r1.state, WorkTask.State.CANCELLED, "T01-G: r1 closed")
	assert_eq(g_r2.state, WorkTask.State.CANCELLED, "T01-G: r2 closed")
	assert_true(g_f1.is_active(), "T01-G: original food task f1 untouched")
	assert_not_null(board.get_active_task_for_source(f2), "T01-G: newly authorized f2 active with distinct identity")
	# Strictly ONE task_closed emission per terminal task!
	for tid_v: Variant in close_counts.keys():
		assert_eq(int(close_counts[tid_v]), 1, "T01-G: task_id %d closed strictly ONCE" % int(tid_v))
	assert_true(int(c_g.get("cancelled_count", 0)) >= 2, "T01-G: outer batch returned valid cancelled count")
	var p_ord_g := g_obs["personal_ord"] as MoveOrder
	assert_eq(active_u.get_current_order(), p_ord_g, "T01-G: personal order preserved after nested batches")
	assert_true(await _wait_until(func() -> bool: return p_ord_g.is_finished(), 1200) and p_ord_g.is_succeeded(), "T01-G: personal order physically arrived")

	await _teardown_fixture(view)


# ==============================================================================
# T01-H, T01-I (O11, O12), & E16:
# Dispatcher resumption, strictly verified mid-residual-delivery removals,
# divergent World3D / metadata-less domain rejection
# ==============================================================================
func test_r1_t01h_t01i_dispatcher_resumption_verified_removals_and_invalid_domains() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var inv := main.get_settlement_inventory()

	# --- T01-H: Dispatcher resumes cleanly after batch cancel (zero polling) ---
	assert_false(dispatcher.is_processing() or dispatcher.is_physics_processing(), "T01-H: zero dispatcher polling")
	var t1 := _find_src(main, &"wood_tree_01")
	var t2 := _find_src(main, &"wood_tree_02")
	var r1 := _find_src(main, &"stone_rock_01")
	var r2 := _find_src(main, &"stone_rock_02")
	_select_sources(model, [t1, t2, r1, r2])
	agi.authorize_selected_category(&"wood")
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(4)
	assert_eq(board.get_active_task_for_source(r1).state, WorkTask.State.PENDING_WORKERS, "T01-H: r1 pending")
	assert_eq(board.get_active_task_for_source(r2).state, WorkTask.State.PENDING_WORKERS, "T01-H: r2 pending")
	agi.cancel_selected_category(&"wood")
	await wait_process_frames(6)
	await wait_physics_frames(2)
	assert_eq(board.get_active_task_for_source(r1).state, WorkTask.State.IN_PROGRESS, "T01-H: dispatcher resumed and assigned r1")
	assert_eq(board.get_active_task_for_source(r2).state, WorkTask.State.IN_PROGRESS, "T01-H: dispatcher resumed and assigned r2")

	# --- E16: Divergent World3D and external source without regional metadata rejected ---
	var other_view := SubViewport.new()
	other_view.own_world_3d = true
	var other_world_tree := TREE_SCENE.instantiate() as ResourceSource
	other_world_tree.source_id = &"r1_e16_other_world_tree"
	other_view.add_child(other_world_tree)
	add_test_child(other_view)
	await wait_physics_frames(1)
	var res_world := dispatcher.cancel_tasks_for_sources([other_world_tree], &"wood")
	assert_false(bool(res_world.get("ok", true)), "E16: divergent World3D rejected")
	assert_eq(String(res_world.get("reason", "")), "region_mismatch", "E16: exact region_mismatch on World3D")
	assert_eq(int(res_world.get("rejected_domain_count", 0)), 1, "E16: rejected_domain_count == 1")
	other_view.get_parent().remove_child(other_view)
	other_view.queue_free()

	var external_no_meta := TREE_SCENE.instantiate() as ResourceSource
	external_no_meta.source_id = &"r1_e16_external_no_meta"
	main.add_child(external_no_meta) # Unregistered external source without regional metadata in same World3D
	await wait_physics_frames(1)
	var res_nometa := dispatcher.cancel_tasks_for_sources([external_no_meta], &"wood")
	assert_false(bool(res_nometa.get("ok", true)), "E16: unregistered external source without regional metadata safely no-ops")
	assert_eq(String(res_nometa.get("reason", "")), "no_cancellable_tasks", "E16: exact no_cancellable_tasks for unregistered same-world source")
	external_no_meta.set_meta(&"region_id", &"foreign_region_gamma")
	var res_foreign_meta := dispatcher.cancel_tasks_for_sources([external_no_meta], &"wood")
	assert_false(bool(res_foreign_meta.get("ok", true)), "E16: foreign region_id metadata explicitly rejected")
	assert_eq(String(res_foreign_meta.get("reason", "")), "region_mismatch", "E16: exact region_mismatch for foreign region_id")
	assert_eq(int(res_foreign_meta.get("rejected_domain_count", 0)), 1, "E16: rejected_domain_count == 1 for foreign region_id")
	assert_not_null(board.get_active_task_for_source(r1), "E16: valid region tasks untouched")
	external_no_meta.get_parent().remove_child(external_no_meta)
	external_no_meta.queue_free()

	# Clean stone tasks before T01-I
	agi.cancel_selected_category(&"stone")
	await wait_process_frames(3)

	# --- T01-I / O12: Source removed STRICTLY AFTER verifying active residual delivery ---
	var custom_tree := TREE_SCENE.instantiate() as ResourceSource
	custom_tree.name = "R1_T01I_Tree"
	custom_tree.source_id = &"r1_t01i_tree"
	custom_tree.position = Vector3(4.0, 0.0, -4.0)
	custom_tree.set_gather_cycle_timings(0.15, 0.0)
	main.get_test_map().add_child(custom_tree)
	await wait_physics_frames(2)
	var inv_w_before: int = inv.get_physical_amount(&"wood")
	_select_sources(model, [custom_tree])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	var u_src_rm: Unit = board.get_active_task_for_source(custom_tree).assigned_unit
	var ord_src_rm := u_src_rm.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(u_src_rm, &"wood", 2), "T01-I(O12): real wood extracted")
	var carried_o12: int = u_src_rm.get_carry_load().get_amount(&"wood")
	var c_o12 := agi.cancel_selected_category(&"wood")
	assert_eq(int(c_o12.get("delivering_count", 0)), 1, "T01-I(O12): delivering_count == 1")
	# STRICT PRECONDITION: confirm residual delivery is ALREADY active BEFORE removing source!
	assert_eq(ord_src_rm.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "T01-I(O12): strictly in DELIVERING_TO_CAMP before source removal")
	assert_true(ord_src_rm.is_stop_after_delivery_requested(), "T01-I(O12): stop_after_delivery == true before source removal")
	custom_tree.get_parent().remove_child(custom_tree)
	custom_tree.queue_free()
	assert_true(await _wait_for_unit_idle(u_src_rm), "T01-I(O12): delivery completed cleanly after source removed")
	assert_true(ord_src_rm.is_succeeded(), "T01-I(O12): order SUCCEEDED")
	assert_false(ord_src_rm.last_delivery_receipt.is_empty(), "T01-I(O12): delivery receipt recorded")
	assert_eq(inv.get_physical_amount(&"wood") - inv_w_before, carried_o12, "T01-I(O12): exact cargo delivered to camp")
	assert_eq(board.get_active_tasks().size(), 0, "T01-I(O12): zero task resurrection")

	# --- T01-I / O11: Worker removed STRICTLY AFTER verifying active residual delivery ---
	var f1 := _find_src(main, &"food_bush_01")
	f1.set_gather_cycle_timings(0.15, 0.0)
	_select_sources(model, [f1])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var u_rm: Unit = board.get_active_task_for_source(f1).assigned_unit
	var ord_u_rm := u_rm.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(u_rm, &"food", 2), "T01-I(O11): worker extracted food")
	var c_o11 := agi.cancel_selected_category(&"food")
	assert_eq(int(c_o11.get("delivering_count", 0)), 1, "T01-I(O11): residual delivery started")
	# STRICT PRECONDITION: confirm residual delivery is ALREADY active BEFORE removing worker!
	assert_eq(ord_u_rm.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "T01-I(O11): strictly in DELIVERING_TO_CAMP before worker removal")
	assert_true(ord_u_rm.is_stop_after_delivery_requested(), "T01-I(O11): stop_after_delivery == true before worker removal")
	var inv_food_before_rm: int = inv.get_physical_amount(&"food")
	u_rm.get_parent().remove_child(u_rm)
	u_rm.queue_free()
	await wait_process_frames(4)
	await wait_physics_frames(3)
	assert_eq(inv.get_physical_amount(&"food"), inv_food_before_rm, "T01-I(O11): no artificial camp credit on worker removal")
	assert_eq(board.get_active_tasks().size(), 0, "T01-I(O11): zero task resurrection or orphan references")

	# --- T01-I: Camp removed STRICTLY AFTER verifying active residual delivery ---
	var u_surv := main.get_units()[0]
	var f2 := _find_src(main, &"food_bush_02")
	f2.set_gather_cycle_timings(0.15, 0.0)
	_select_sources(model, [f2])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var ord_camp := u_surv.get_current_order() as GatherResourceOrder
	assert_true(await _wait_for_unit_cargo(u_surv, &"food", 2), "T01-I(camp): extracted food")
	var carried_camp: int = u_surv.get_carry_load().get_amount(&"food")
	agi.cancel_selected_category(&"food")
	assert_eq(ord_camp.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP, "T01-I(camp): strictly in DELIVERING_TO_CAMP before camp removal")
	assert_true(ord_camp.is_stop_after_delivery_requested(), "T01-I(camp): stop_after_delivery == true")
	var camp := main.get_camp_storage_zone()
	camp.get_parent().remove_child(camp)
	camp.queue_free()
	assert_true(await _wait_for_unit_idle(u_surv), "T01-I(camp): worker failed gracefully to IDLE")
	assert_eq(u_surv.get_carry_load().get_amount(&"food"), carried_camp, "T01-I(camp): cargo 100% preserved")
	assert_eq(board.get_active_tasks().size(), 0, "T01-I(camp): board clean")

	await _teardown_fixture(view)


# ==============================================================================
# Reconciled Original D2 Gaps: S06, S11, S12, O04, O07, U02, U03, U07, U12, U14, U15, U20
# ==============================================================================
func test_r1_reconciled_s06_s11_s12_o04_o07_u12_u14_u20() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var hud := main.get_community_selection_actions_hud()
	var inv := main.get_settlement_inventory()

	var t1 := _find_src(main, &"wood_tree_01")
	var t2 := _find_src(main, &"wood_tree_02")
	var t3 := _find_src(main, &"wood_tree_03")
	var t4 := _find_src(main, &"wood_tree_04")
	var t5 := _find_src(main, &"wood_tree_05")
	var f1 := _find_src(main, &"food_bush_01")
	var r1 := _find_src(main, &"stone_rock_01")

	# S06 (exact original spec: 5 sources selected, 2 authorized -> cancel strictly 2)
	_select_sources(model, [t1, t2])
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(4)
	_select_sources(model, [t1, t2, t3, t4, t5])
	await wait_process_frames(2)
	assert_eq(hud.get_category_cancel_text(&"wood"), "×2", "S06: 5 selected / 2 authorized shows ×2")
	assert_true(is_equal_approx(hud.get_category_cancel_button(&"wood").size.x, CommunitySelectionActionsHud.SEAL_WIDTH_PARTIAL), "S06: seal width 44px")
	var c_s06 := agi.cancel_selected_category(&"wood")
	await wait_process_frames(2)
	assert_eq(int(c_s06.get("cancelled_count", 0)), 2, "S06: cancelled strictly 2 of 5")
	assert_eq(model.get_count_for_resource(&"wood"), 5, "S06: all 5 trees remain selected")

	# S11: Invalid category explicitly refused
	var c_inv_agi := agi.cancel_selected_category(&"gold_invalid")
	assert_false(bool(c_inv_agi.get("ok", true)), "S11: invalid category refused by input")
	assert_eq(String(c_inv_agi.get("reason", "")), "unsupported_resource", "S11: exact unsupported_resource reason")
	var c_inv_disp := dispatcher.cancel_tasks_for_sources([t1], &"gold_invalid")
	assert_false(bool(c_inv_disp.get("ok", true)), "S11: invalid category refused by dispatcher")

	# S12: Depleted source and removed-from-tree source passed to cancel -> safe no-op
	var dep_tree := TREE_SCENE.instantiate() as ResourceSource
	dep_tree.source_id = &"r1_s12_depleted"
	dep_tree.position = Vector3(3.0, 0.0, -5.0)
	main.get_test_map().add_child(dep_tree)
	await wait_physics_frames(1)
	while not dep_tree.is_depleted():
		dep_tree.extract(dep_tree.get_remaining_amount())
	assert_true(dep_tree.is_depleted(), "S12: source depleted")
	var c_dep := dispatcher.cancel_tasks_for_sources([dep_tree], &"wood")
	assert_false(bool(c_dep.get("ok", true)), "S12: depleted source safe no-op")
	dep_tree.get_parent().remove_child(dep_tree)
	var c_rem := dispatcher.cancel_tasks_for_sources([dep_tree], &"wood")
	assert_false(bool(c_rem.get("ok", true)), "S12: removed-from-tree source safe no-op")
	dep_tree.queue_free()

	# U02 (explicit PENDING_WORKERS seal) + U03 (explicit IN_PROGRESS seal) + U07 (real click wood seal preserves food) + U12 (marker count == 1) + U15 (0 authorize emitted)
	_select_sources(model, [t1, t2, t3, f1])
	agi.authorize_selected_category(&"wood")
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	var tk_in_prog := board.get_active_task_for_source(t1)
	var tk_pending := board.get_active_task_for_source(t3)
	assert_eq(tk_in_prog.state, WorkTask.State.IN_PROGRESS, "U03: t1 explicitly IN_PROGRESS")
	assert_eq(tk_pending.state, WorkTask.State.PENDING_WORKERS, "U02: t3 explicitly PENDING_WORKERS")
	_select_sources(model, [t3])
	await wait_process_frames(2)
	assert_true(hud.is_category_cancel_visible(&"wood"), "U02: cancel seal visible for explicit PENDING_WORKERS task")
	_select_sources(model, [t1, f1])
	await wait_process_frames(2)
	assert_true(hud.is_category_cancel_visible(&"wood"), "U03: cancel seal visible for explicit IN_PROGRESS task")
	assert_eq(_count_work_markers(t1), 1, "U12: strictly 1 work marker before cancel")

	var auth_emitted := {"n": 0}
	var on_auth := func(_rid: StringName) -> void:
		auth_emitted["n"] = int(auth_emitted["n"]) + 1
	hud.category_authorize_requested.connect(on_auth)
	var w_seal_pt: Vector2 = hud.get_category_cancel_button(&"wood").get_global_rect().get_center()
	await _click_viewport(view, w_seal_pt, MOUSE_BUTTON_LEFT)
	await wait_process_frames(3)
	if hud.category_authorize_requested.is_connected(on_auth):
		hud.category_authorize_requested.disconnect(on_auth)
	assert_eq(int(auth_emitted["n"]), 0, "U15: clicking X emitted ZERO category_authorize_requested")
	assert_null(board.get_active_task_for_source(t1), "U07: real click on wood X cancelled wood")
	assert_not_null(board.get_active_task_for_source(f1), "U07: real click on wood X preserved food")
	assert_eq(_count_work_markers(t1), 0, "U10: cancelled wood marker removed")
	assert_eq(_count_work_markers(f1), 1, "U11: preserved food marker count == 1")

	# U12: Reauthorizing restores strictly 1 work marker (zero duplication even after repeat cycles)
	agi.authorize_selected_category(&"wood")
	await wait_process_frames(2)
	assert_eq(_count_work_markers(t1), 1, "U12: reauthorization restored strictly 1 marker (zero duplication)")

	# U14: Real LMB click in transparent 6 px gap passes through to ground (deselects without cancelling or authorizing!)
	var w_seal_r := hud.get_category_cancel_button(&"wood").get_global_rect()
	var gap_pt := Vector2(w_seal_r.get_center().x, w_seal_r.end.y + 3.0)
	await _click_viewport(view, gap_pt, MOUSE_BUTTON_LEFT)
	await wait_process_frames(2)
	assert_not_null(board.get_active_task_for_source(t1), "U14: click in transparent 6px gap did NOT cancel wood")
	assert_eq(model.get_selected_sources().size(), 0, "U14: click in transparent 6px gap reached ground and cleared selection")

	# U20: Zero overlap with ALL visible UiLayer controls (including active AutonomousGatherFeedback banner) in 720p & 1080p
	for vp_sz: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		view.size = vp_sz
		await wait_process_frames(2)
		_select_sources(model, [t1, r1, f1])
		agi.authorize_selected_category(&"stone")
		main.get_autonomous_gather_feedback().show_message("Feedback ativo para validação U20.")
		await wait_process_frames(2)
		var hud_r := hud.get_panel_rect()
		assert_true(Rect2(Vector2.ZERO, Vector2(vp_sz)).encloses(hud_r), "U20(%dx%d): HUD enclosed in viewport" % [vp_sz.x, vp_sz.y])
		var ui_layer := main.get_node("UiLayer")
		for ch: Node in ui_layer.get_children():
			if ch == hud or not (ch is Control) or not (ch as Control).visible:
				continue
			var ctrl := ch as Control
			var check_r := Rect2()
			if ctrl.has_method("get_panel_rect"):
				check_r = ctrl.call("get_panel_rect") as Rect2
			else:
				for sub: Node in ctrl.get_children():
					if sub is Control and (sub as Control).visible:
						var sr := (sub as Control).get_global_rect()
						if sr.size.x > 0.0 and sr.size.y > 0.0 and sr.size.x < float(vp_sz.x) * 0.9:
							assert_false(hud_r.intersects(sr), "U20(%dx%d): zero overlap with %s/%s" % [vp_sz.x, vp_sz.y, ctrl.name, sub.name])
			if check_r.size.x > 0.0 and check_r.size.y > 0.0:
				assert_false(hud_r.intersects(check_r), "U20(%dx%d): zero overlap with %s" % [vp_sz.x, vp_sz.y, ctrl.name])

	# Cleanup all tasks before O04 & O07
	_select_sources(model, [t1, t2, t3, r1, f1])
	agi.cancel_selected_category(&"wood")
	agi.cancel_selected_category(&"stone")
	agi.cancel_selected_category(&"food")
	for u: Unit in main.get_units():
		u.cancel_current_order()
	await wait_process_frames(3)

	# O04 (full backpack explicit verification) + O07 (cancel during return to source after 1st completed trip!)
	var f_o7 := _find_src(main, &"food_bush_01")
	f_o7.set_gather_cycle_timings(0.10, 0.0)
	var inv_food_o7: int = inv.get_physical_amount(&"food")
	var u_a := _find_unit(main, &"leader_a")
	var u_b := _find_unit(main, &"leader_b")
	u_b.issue_order(MoveOrder.new(Vector3(-12.0, 0.0, -10.0)))
	# Reduce base capacity to 4 so backpack fills deterministically fast
	assert_true(u_a.get_carry_load().set_base_capacity(4), "O04/O07: base capacity set to 4")
	_select_sources(model, [f_o7])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var ord_o7 := u_a.get_current_order() as GatherResourceOrder
	assert_not_null(ord_o7, "O07: GatherResourceOrder started")

	# Wait until 1st full trip completes AND worker enters APPROACHING_SOURCE returning to source with empty backpack!
	assert_true(await _wait_until(func() -> bool:
		return ord_o7.get_delivered_trips() == 1 and ord_o7.get_phase() == GatherResourceOrder.Phase.APPROACHING_SOURCE and u_a.get_carry_load().is_empty()
	, 2400), "O07: worker completed 1st trip and is returning to source")
	var rem_on_return: int = f_o7.get_remaining_amount()
	var c_o7 := agi.cancel_selected_category(&"food")
	await wait_process_frames(2)
	await wait_physics_frames(20)
	assert_eq(int(c_o7.get("stopped_immediately_count", 0)), 1, "O07: stopped immediately during return to source")
	assert_eq(u_a.get_state(), Unit.State.IDLE, "O07: worker IDLE")
	assert_eq(f_o7.get_active_worker_count(), 0, "O07: slot released")
	assert_eq(f_o7.get_remaining_amount(), rem_on_return, "O07: zero 2nd extraction occurred")
	assert_true(inv.get_physical_amount(&"food") > inv_food_o7, "O07: 1st trip already in camp")

	# O04: Fill backpack to exact max capacity (can_fit_one == false) -> cancel preserves full load and delivers once without returning
	var f_o4 := _find_src(main, &"food_bush_02")
	f_o4.set_gather_cycle_timings(0.10, 0.0)
	var inv_food_o4: int = inv.get_physical_amount(&"food")
	_select_sources(model, [f_o4])
	agi.authorize_selected_category(&"food")
	await wait_process_frames(4)
	var ord_o4 := u_a.get_current_order() as GatherResourceOrder
	assert_true(await _wait_until(func() -> bool:
		return not u_a.get_carry_load().can_fit_one(f_o4.get_definition()) and u_a.get_carry_load().get_amount(&"food") > 0
	, 2400), "O04: backpack deterministically reached FULL capacity (can_fit_one == false)")
	var full_amt: int = u_a.get_carry_load().get_amount(&"food")
	var rem_o4: int = f_o4.get_remaining_amount()
	var c_o4 := agi.cancel_selected_category(&"food")
	assert_eq(int(c_o4.get("delivering_count", 0)), 1, "O04: full backpack continues final delivery")
	assert_true(await _wait_for_unit_idle(u_a), "O04: full backpack finished final delivery")
	assert_true(ord_o4.is_succeeded(), "O04: order SUCCEEDED")
	assert_eq(ord_o4.get_delivered_trips(), 1, "O04: strictly 1 trip")
	assert_eq(inv.get_physical_amount(&"food") - inv_food_o4, full_amt, "O04: exact full load delivered to camp")
	assert_eq(f_o4.get_remaining_amount(), rem_o4, "O04: zero return after full delivery")

	await _teardown_fixture(view)
