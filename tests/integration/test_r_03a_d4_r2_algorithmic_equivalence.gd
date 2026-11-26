extends TestCase
## D4-R2 Algorithmic Equivalence & Batch Safety Regression Suite:
## Covers D4-R1-A01 (GatherSlotPlanner oracle & displaced-snap guard),
## D4-R1-A02 (CommunityTaskDispatcher strict weak ordering, task-specific precheck, callback safety),
## and D4-R1-A03 (dispatch_batch_started/finished balance under mid-dispatch teardown/reconfigure).

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")


class _MockNav:
	extends WorldNavigation
	var snap_fn: Callable = Callable()
	var path_fn: Callable = Callable()
	var snap_calls: int = 0
	var path_calls: int = 0

	func is_navigation_ready() -> bool:
		return true

	func snap_to_navmesh(world_position: Vector3) -> Vector3:
		snap_calls += 1
		if snap_fn.is_valid():
			return snap_fn.call(world_position) as Vector3
		return world_position

	func find_path(from_world: Vector3, to_world: Vector3, _optimize: bool = true) -> PathResult:
		path_calls += 1
		if path_fn.is_valid():
			return path_fn.call(from_world, to_world) as PathResult
		var pr := PathResult.new()
		pr.status = QueryStatus.OK
		pr.resolved_target = to_world
		pr.path = PackedVector3Array([from_world, to_world])
		return pr


func _make_ok_path(a: Vector3, b: Vector3) -> WorldNavigation.PathResult:
	var pr := WorldNavigation.PathResult.new()
	pr.status = WorldNavigation.QueryStatus.OK
	pr.resolved_target = b
	pr.path = PackedVector3Array([a, b])
	return pr


func _make_fail_path() -> WorldNavigation.PathResult:
	var pr := WorldNavigation.PathResult.new()
	pr.status = WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE
	return pr


func _fixture() -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := MAIN_SCENE.instantiate() as MainScene
	view.add_child(main)
	for _i: int in range(120):
		if main.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(main.get_test_map().get_navigation().is_navigation_ready(), "Fixture: nav ready")
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false
	await wait_process_frames(3)
	return view


func _teardown(view: SubViewport) -> void:
	if is_instance_valid(view):
		var main := view.get_child(0) as MainScene if view.get_child_count() > 0 else null
		if main != null and is_instance_valid(main):
			for u: Unit in main.get_units():
				if is_instance_valid(u) and u.get_current_order() != null:
					u.cancel_current_order()
		view.queue_free()
	await wait_process_frames(2)


func _find_source(main: MainScene, sid: StringName) -> ResourceSource:
	for s: ResourceSource in main.get_test_map().get_all_region_resource_sources():
		if s.source_id == sid:
			return s
	return null


func test_a01_01_displaced_snap_does_not_arm_premature_early_exit() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var tree01 := _find_source(main, &"wood_tree_01")
	assert_not_null(tree01)
	var src_c: Vector3 = tree01.global_position
	var unit_pos := src_c + Vector3(-6.0, 0.0, 0.0)

	var mock := _MockNav.new()
	mock.snap_fn = func(p: Vector3) -> Vector3:
		var v := Vector2(p.x - src_c.x, p.z - src_c.z)
		var r: float = v.length()
		var ang: float = atan2(v.y, v.x)
		# Front cone within +/-30 deg snaps across thin obstacle to FAR (+x) side of tree
		if absf(wrapf(ang - PI, -PI, PI)) < 0.55:
			return Vector3(src_c.x + r, src_c.y, src_c.z)
		return p
	mock.path_fn = func(a: Vector3, b: Vector3) -> WorldNavigation.PathResult:
		return _make_ok_path(a, b)

	var res := GatherSlotPlanner.compute_source_approach_slot(unit_pos, tree01, mock, [])
	assert_true(bool(res["valid"]), "A01-01: valid slot found")
	var pos: Vector3 = res["position"] as Vector3
	var trav: float = Vector2(pos.x - unit_pos.x, pos.z - unit_pos.z).length()
	assert_lt(trav, 5.6, "A01-01: must pick near-side open angle (~5.33m), NOT far-side displaced snap (~6.87m)")
	mock.free()
	await _teardown(view)


func test_a01_02_open_ground_early_exit_keeps_low_query_count_and_contract() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var tree01 := _find_source(main, &"wood_tree_01")
	var src_c: Vector3 = tree01.global_position
	var unit_pos := src_c + Vector3(-6.0, 0.0, 0.0)

	var mock := _MockNav.new()
	var res := GatherSlotPlanner.compute_source_approach_slot(unit_pos, tree01, mock, [])
	assert_true(bool(res["valid"]), "A01-02: valid slot found on open ground")
	assert_eq(mock.snap_calls, 3, "A01-02: open ground evaluates only 3 angles (step 0,1,2) instead of 48")
	assert_eq(mock.path_calls, 3, "A01-02: open ground executes only 3 path queries")

	# Completely unreachable must scan all 48 and return valid=false
	mock.snap_calls = 0
	mock.path_calls = 0
	mock.path_fn = func(_a: Vector3, _b: Vector3) -> WorldNavigation.PathResult:
		return _make_fail_path()
	var unreach := GatherSlotPlanner.compute_source_approach_slot(unit_pos, tree01, mock, [])
	assert_false(bool(unreach["valid"]), "A01-02: unreachable source returns valid=false")
	assert_eq(mock.snap_calls, 48, "A01-02: unreachable exhausts all 48 candidates")

	# Fallback when all slots occupied returns valid=true fallback
	mock.path_fn = Callable()
	var r_pref: float = maxf(tree01.get_solid_radius(), 0.0) + WorldNavigation.DEFAULT_AGENT_RADIUS + 0.05
	var crowded: Array[Vector3] = []
	for k: int in range(12):
		var a: float = float(k) * (TAU / 12.0)
		crowded.append(src_c + Vector3(cos(a) * r_pref, 0.0, sin(a) * r_pref))
	var fb := GatherSlotPlanner.compute_source_approach_slot(unit_pos, tree01, mock, crowded)
	assert_true(bool(fb["valid"]), "A01-02: crowded fallback still resolves valid slot")

	mock.free()
	await _teardown(view)


func test_a02_01_near_equal_distance_uses_strict_weak_ordering_matching_baseline() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var units := main.get_units()
	var t1 := _find_source(main, &"wood_tree_01")
	var t2 := _find_source(main, &"wood_tree_02")

	units[0].global_position = Vector3(0.0, 0.0, 0.0)
	units[1].global_position = Vector3(-40.0, 0.0, 0.0)
	# dist_sq(t1) = 100.00040004 vs dist_sq(t2) = 100.0 (within is_equal_approx, but t2 is strictly closer!)
	t1.global_position = Vector3(10.00002, 0.0, 0.0)
	t2.global_position = Vector3(0.0, 0.0, 10.00000)

	var two_trees: Array[ResourceSource] = [t1, t2]
	board.register_gather_group(two_trees, 0)
	await wait_process_frames(3)

	var u0_task: WorkTask = null
	for t: WorkTask in board.get_active_tasks():
		if t.assigned_unit == units[0]:
			u0_task = t
	assert_not_null(u0_task, "A02-01: unit 0 assigned")
	assert_eq(u0_task.source_id, &"wood_tree_02", "A02-01: strictly closer wood_tree_02 must win over wood_tree_01")
	await _teardown(view)


func test_a02_02_group_fifo_and_task_specific_precheck_preserve_precedence() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var disp := main.get_community_task_dispatcher()
	var units := main.get_units()
	var t1 := _find_source(main, &"wood_tree_01")
	var r1 := _find_source(main, &"stone_rock_01")

	# Register group 1 (wood) then group 2 (stone, closer to units[0]) -> FIFO group 1 must dispatch first!
	var g1: Array[ResourceSource] = [t1]
	var g2: Array[ResourceSource] = [r1]
	board.register_gather_group(g1, 0)
	board.register_gather_group(g2, 0)
	await wait_process_frames(3)

	var t_wood := board.get_active_task_for_source(t1)
	var t_stone := board.get_active_task_for_source(r1)
	assert_not_null(t_wood.assigned_unit, "A02-02: group 1 wood dispatched")
	assert_not_null(t_stone.assigned_unit, "A02-02: group 2 stone dispatched to second worker")

	# Verify manually_overridden still precedes busy/not_idle in _check_pre_nav_eligibility
	t_wood.excluded_unit_ids[units[0].get_instance_id()] = true
	assert_eq(
		disp._check_pre_nav_eligibility(units[0], t_wood),
		"manually_overridden",
		"A02-02: manually_overridden must take precedence over busy/not_idle"
	)
	await _teardown(view)


func test_a03_01_teardown_and_reconfigure_mid_dispatch_never_freeze_hud() -> void:
	# Part A: agi.teardown_community_work() inside task_assigned callback
	var view_a := await _fixture()
	var main_a := view_a.get_child(0) as MainScene
	var agi_a := main_a.get_input_controller() as AutonomousGatherInput
	var hud_a := main_a.get_community_selection_actions_hud()
	var disp_a := main_a.get_community_task_dispatcher()
	var model_a := main_a.get_source_selection_model()
	var trees_a: Array[ResourceSource] = []
	for s: ResourceSource in main_a.get_test_map().get_all_region_resource_sources():
		if s.get_resource_id() == &"wood":
			trees_a.append(s)
	model_a.add_sources(trees_a)

	var st_a := {"fired": false}
	disp_a.task_assigned.connect(func(_t, _u, _o) -> void:
		if not bool(st_a["fired"]):
			st_a["fired"] = true
			agi_a.teardown_community_work()
	)
	agi_a.authorize_selected_category(&"wood")
	await wait_process_frames(3)

	assert_true(bool(st_a["fired"]), "A03-01A: mid-dispatch teardown callback fired")
	assert_eq(hud_a._batch_refresh_depth, 0, "A03-01A: HUD _batch_refresh_depth must return to 0")
	assert_false(hud_a.is_panel_visible(), "A03-01A: HUD refreshed immediately on teardown selection clear")
	var rc_before: int = hud_a.get_refresh_invocation_count()
	model_a.select_single(trees_a[0])
	assert_gt(float(hud_a.get_refresh_invocation_count()), float(rc_before), "A03-01A: HUD remains live and refreshes on new selection")
	await _teardown(view_a)

	# Part B: agi.configure_community_work(..., null) inside task_assigned callback
	var view_b := await _fixture()
	var main_b := view_b.get_child(0) as MainScene
	var agi_b := main_b.get_input_controller() as AutonomousGatherInput
	var hud_b := main_b.get_community_selection_actions_hud()
	var board_b := main_b.get_community_work_board()
	var disp_b := main_b.get_community_task_dispatcher()
	var fb_b := main_b.get_autonomous_gather_feedback()
	var model_b := main_b.get_source_selection_model()
	var trees_b: Array[ResourceSource] = []
	for s: ResourceSource in main_b.get_test_map().get_all_region_resource_sources():
		if s.get_resource_id() == &"wood":
			trees_b.append(s)
	model_b.add_sources(trees_b)

	var st_b := {"fired": false}
	disp_b.task_assigned.connect(func(_t, _u, _o) -> void:
		if not bool(st_b["fired"]):
			st_b["fired"] = true
			agi_b.configure_community_work(board_b, disp_b, fb_b, main_b.use_provenance_economy, main_b.get_economy_admission_reason(), null)
	)
	agi_b.authorize_selected_category(&"wood")
	await wait_process_frames(3)

	assert_true(bool(st_b["fired"]), "A03-01B: mid-dispatch reconfigure callback fired")
	assert_eq(hud_b._batch_refresh_depth, 0, "A03-01B: detached HUD _batch_refresh_depth must return to 0")
	await _teardown(view_b)


func test_a03_02_empty_flush_preserves_last_refresh_count_and_nested_batch_safety() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var agi := main.get_input_controller() as AutonomousGatherInput
	var hud := main.get_community_selection_actions_hud()
	var board := main.get_community_work_board()
	var disp := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var all_sources := main.get_test_map().get_all_region_resource_sources()
	model.add_sources(all_sources)

	var board_signals := {"reg": 0, "upd": 0, "cls": 0}
	board.task_registered.connect(func(_t): board_signals["reg"] = int(board_signals["reg"]) + 1)
	board.task_updated.connect(func(_t): board_signals["upd"] = int(board_signals["upd"]) + 1)
	board.task_closed.connect(func(_t): board_signals["cls"] = int(board_signals["cls"]) + 1)

	# Nested outer batch + authorize -> 0 intermediate refreshes, 1 final refresh
	hud.begin_batch_refresh()
	var rc0: int = hud.get_refresh_invocation_count()
	agi.authorize_selected_category(&"wood")
	assert_eq(hud.get_refresh_invocation_count() - rc0, 0, "A03-02: nested outer batch suppresses intermediate refresh")
	hud.end_batch_refresh()
	assert_eq(hud.get_refresh_invocation_count() - rc0, 1, "A03-02: outer batch end triggers single consolidated refresh")
	assert_eq(int(board_signals["reg"]), 6, "A03-02: individual board.task_registered signals preserved (6)")
	await wait_process_frames(3)

	# Cancel all wood -> empty deferred flush must NOT clobber get_last_refresh_count() == 1
	agi.cancel_selected_category(&"wood")
	assert_eq(hud.get_last_refresh_count(), 1, "A03-02: cancel batch reports 1 refresh")
	await wait_process_frames(3)
	assert_eq(hud.get_last_refresh_count(), 1, "A03-02: empty deferred flush preserves last_refresh_count == 1")
	assert_eq(int(board_signals["cls"]), 6, "A03-02: individual board.task_closed signals preserved (6)")
	assert_eq(hud._batch_refresh_depth, 0, "A03-02: HUD batch depth balanced at 0")
	assert_false(hud.is_processing(), "A03-02: HUD zero polling")
	assert_false(disp.is_processing(), "A03-02: Dispatcher zero polling")

	# Mid-dispatch dispatcher.teardown() must keep dispatch_batch_started/finished balanced and depth == 0
	var st_td := {"starts": 0, "ends": 0, "fired": false}
	disp.dispatch_batch_started.connect(func(): st_td["starts"] = int(st_td["starts"]) + 1)
	disp.dispatch_batch_finished.connect(func(): st_td["ends"] = int(st_td["ends"]) + 1)
	disp.task_assigned.connect(func(_t, _u, _o):
		if not bool(st_td["fired"]):
			st_td["fired"] = true
			disp.teardown()
	)
	agi.authorize_selected_category(&"stone")
	await wait_process_frames(3)
	assert_true(bool(st_td["fired"]), "A03-02: mid-dispatch disp.teardown() fired")
	assert_eq(int(st_td["starts"]), int(st_td["ends"]), "A03-02: dispatch_batch_started == dispatch_batch_finished")
	assert_eq(hud._batch_refresh_depth, 0, "A03-02: HUD depth == 0 after mid-dispatch dispatcher teardown")

	await _teardown(view)
