extends TestCase
## Integration tests for R-03B B3:
## - D01 (13 cases): T6a (sync + async MoveOrder SUCCEEDED), T6b (failed/cancelled/non-MoveOrder/community/recovery/wait=0),
##   T7 (timeout), T8 (new personal order cancels & rearms), T0 (refused order preserves wait), T9 (admin cancel / null)
## - D02: Experimental 3/8/15 s config affects future waits only, D2SimulationPauseController pause/resume freezes timer,
##   stale timeout callbacks ignored, max 1 timeout connection, zero timer on COMMUNITY units & MainScene startup
## - F01: Removal from tree, definition downgrade (COMMUNITY / BABY), and controlled teardown during PERSONAL_POST_MOVE_WAIT.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")


class UnsupportedPersonalOrderB3 extends UnitOrder:
	func get_order_name() -> String:
		return "UnsupportedPersonalOrderB3"


func before_each() -> void:
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 1.0


func after_each() -> void:
	if get_tree() != null:
		get_tree().paused = false
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


func _boot_main(wait_sec: float = 0.20) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(320, 180)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = true
	main.automatic_cancellation_recovery = true
	main.use_d2_2_hud = false
	main.experimental_personal_post_move_wait_sec = wait_sec
	vp.add_child(main)
	await wait_process_frames(2)
	await wait_physics_frames(2)

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	for _i: int in range(360):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready(), "Navigation ready")

	return {
		"vp": vp,
		"main": main,
		"nav": nav,
		"board": main.get_community_work_board(),
		"dispatcher": main.get_community_task_dispatcher(),
		"cmd": main.get_command_controller(),
		"inv": main.get_settlement_inventory(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"leader_a": main.get_node("Units/LeaderA") as Unit,
		"leader_b": main.get_node("Units/LeaderB") as Unit,
		"region_id": main.get_construction_manager().get_region_id(),
	}


func _teardown_main(ctx: Dictionary) -> void:
	if get_tree() != null:
		get_tree().paused = false
	var main: MainScene = ctx.get("main") as MainScene
	var vp: SubViewport = ctx.get("vp") as SubViewport
	if main != null and is_instance_valid(main):
		main.request_controlled_teardown()
	if vp != null and is_instance_valid(vp):
		if vp.get_parent() != null:
			vp.get_parent().remove_child(vp)
		vp.queue_free()
	await wait_process_frames(2)


func _find_source(main: MainScene, sid: StringName) -> ResourceSource:
	for s: ResourceSource in main.get_test_map().get_resource_sources():
		if s.get_source_id() == sid:
			return s
	return null


func _until(predicate: Callable, max_frames: int = 1200) -> bool:
	for _i: int in range(max_frames):
		if predicate.call():
			return true
		await wait_physics_frames(1)
	return predicate.call()


func _make_def(
	cid: StringName,
	display: String,
	aff: CharacterDefinition.HouseAffiliation,
	orig: CharacterDefinition.FoundingHouseOrigin,
	age: CharacterDefinition.AgeStage
) -> CharacterDefinition:
	var def := CharacterDefinition.new()
	def.character_id = cid
	def.display_name = display
	def.house_affiliation = aff
	def.founding_house_origin = orig
	def.age_stage = age
	return def


# ==============================================================================
# D01: All 13 cases of T6a, T6b, T7, T8, T0, T9
# ==============================================================================
func test_d01_all_personal_wait_entry_exit_and_non_entry_cases() -> void:
	var ctx := await _boot_main(0.25)
	var main: MainScene = ctx["main"] as MainScene
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var bush: ResourceSource = _find_source(main, &"food_bush_01")
	var inv: SettlementInventory = ctx["inv"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var region_id: StringName = ctx["region_id"] as StringName

	# Startup lazy invariant: ZERO wait timers exist on MainScene startup.
	assert_false(leader_a.has_personal_wait_timer(), "D01/D02: MainScene startup must have zero wait timers on LeaderA")
	assert_false(leader_b.has_personal_wait_timer(), "D01/D02: MainScene startup must have zero wait timers on LeaderB")

	var transitions: Array[Dictionary] = []
	leader_a.control_mode_changed.connect(func(n: UnitControlState.ControlMode, p: UnitControlState.ControlMode) -> void:
		transitions.append({"new": n, "prev": p})
	)

	# Case 1 (T6a async): Personal MoveOrder SUCCEEDED enters PERSONAL_POST_MOVE_WAIT.
	var async_mv := MoveOrder.new(leader_a.global_position + Vector3(0.6, 0.0, 0.0))
	assert_true(leader_a.issue_personal_order(async_mv))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	assert_true(await _until(func() -> bool: return not async_mv.is_active(), 600), "Case 1 async MoveOrder finishes")
	assert_true(async_mv.is_succeeded())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "D01-01: async MoveOrder SUCCEEDED -> PERSONAL_POST_MOVE_WAIT")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_null(leader_a.get_current_order())
	assert_false(leader_a.is_community_dispatch_eligible())
	assert_true(leader_a.is_personal_wait_timer_active())
	assert_gt(leader_a.get_personal_wait_time_left(), 0.0)

	# Case 2 (T0): Rejected order during PERSONAL_POST_MOVE_WAIT preserves mode, token, and remaining time intact.
	var token_before_t0: int = leader_a.get_personal_wait_token_id()
	var rev_before_t0: int = leader_a.get_order_revision()
	var left_before_t0: float = leader_a.get_personal_wait_time_left()
	assert_false(leader_a.issue_personal_order(UnsupportedPersonalOrderB3.new()), "D01-11: unsupported personal order rejected (T0)")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "T0 preserves PERSONAL_POST_MOVE_WAIT")
	assert_eq(leader_a.get_personal_wait_token_id(), token_before_t0, "T0 preserves wait token")
	assert_eq(leader_a.get_order_revision(), rev_before_t0, "T0 preserves order revision")
	assert_true(leader_a.is_personal_wait_timer_active(), "T0 keeps timer running")
	assert_true(leader_a.get_personal_wait_time_left() <= left_before_t0 + 0.02 and leader_a.get_personal_wait_time_left() > 0.0)

	# Case 3 (T8): New admitted personal MoveOrder during wait cancels wait timer, transitions to PERSONAL_ACTIVE,
	# and upon synchronous completion (target == current pos) rearms PERSONAL_POST_MOVE_WAIT with a NEW token!
	var sync_mv := MoveOrder.new(leader_a.global_position)
	assert_true(leader_a.issue_personal_order(sync_mv), "D01-02/10: sync MoveOrder at current pos admitted (T8 -> T6a)")
	assert_true(sync_mv.is_succeeded())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "D01-02: sync MoveOrder SUCCEEDED enters/rearms PERSONAL_POST_MOVE_WAIT")
	assert_gt(leader_a.get_personal_wait_token_id(), token_before_t0, "T8 + rearm advances wait token")
	assert_true(leader_a.is_personal_wait_timer_active())

	# Case 4 (T9 cancel_current_order): cancels wait immediately -> COMMUNITY_FREE, bumps revision.
	var rev_before_t9: int = leader_a.get_order_revision()
	leader_a.cancel_current_order()
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-12: cancel_current_order() during wait -> COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())
	assert_gt(leader_a.get_order_revision(), rev_before_t9, "T9 bumps revision")

	# Case 5 (T9 issue_order(null)): also cancels wait cleanly -> COMMUNITY_FREE.
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_true(leader_a.issue_order(null))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-12b: issue_order(null) during wait -> COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 6 (T6b MoveOrder FAILED): invalid target -> directly COMMUNITY_FREE, zero wait.
	assert_false(leader_a.issue_personal_order(MoveOrder.new(Vector3(NAN, 0.0, 0.0))))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-03: failed MoveOrder -> COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 7 (T6b MoveOrder CANCELLED): cancelled before arrival -> directly COMMUNITY_FREE, zero wait.
	var far_mv := MoveOrder.new(Vector3(-14.0, 0.0, -14.0))
	assert_true(leader_a.issue_personal_order(far_mv))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	leader_a.cancel_current_order()
	assert_eq(far_mv.status, UnitOrder.Status.CANCELLED)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-04: cancelled MoveOrder -> COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 8 (T6b personal GatherResourceOrder): finishing GatherResourceOrder -> COMMUNITY_FREE, NO wait!
	bush.configure(bush.source_id, bush.get_definition(), 1, 1, 1)
	bush.set_gather_cycle_timings(0.02, 0.0)
	leader_a.global_position = bush.global_position + Vector3(-1.4, 0.0, 0.0)
	var p_gather := GatherResourceOrder.new(bush, camp, inv, -1.0, -1.0, true, region_id)
	assert_true(leader_a.issue_personal_order(p_gather))
	assert_true(await _until(func() -> bool: return not p_gather.is_active(), 1200), "Case 8 personal GatherResourceOrder finishes")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-05: personal GatherResourceOrder never enters wait")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 9 (T6b personal DeliverToCampOrder): finishing DeliverToCampOrder -> COMMUNITY_FREE, NO wait!
	var p_deliver := DeliverToCampOrder.new(camp, inv, true, region_id)
	leader_a.issue_personal_order(p_deliver)
	assert_true(await _until(func() -> bool: return not p_deliver.is_active(), 300))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-06: personal DeliverToCampOrder never enters wait")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 10 (T6b personal ConstructOrder cancelled/finished): -> COMMUNITY_FREE, NO wait!
	var cmd: CommandController = ctx["cmd"] as CommandController
	inv.deposit(&"wood", 12)
	inv.deposit(&"stone", 6)
	var site_res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(site_res.get("ok", false)), "Case 10 site created")
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	assert_true(cmd.command_units_to_site(site, [leader_a]), "Case 10 personal ConstructOrder issued via CommandController")
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_ACTIVE)
	leader_a.cancel_current_order()
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-07: personal ConstructOrder never enters wait")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 11 (T6b wait == 0.0 technical configuration): sync MoveOrder SUCCEEDED goes straight to COMMUNITY_FREE.
	leader_a.personal_post_move_wait_sec = 0.0
	var zero_wait_mv := MoveOrder.new(leader_a.global_position)
	assert_true(leader_a.issue_personal_order(zero_wait_mv))
	assert_true(zero_wait_mv.is_succeeded())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01-13: wait=0.0 goes directly to COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())

	# Case 12 (T7 legitimate timeout): short wait expires cleanly -> COMMUNITY_FREE with single signal.
	leader_a.personal_post_move_wait_sec = 0.08
	transitions.clear()
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_eq(transitions.size(), 1)
	assert_eq(transitions[0]["new"], UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	await get_tree().create_timer(0.18).timeout
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D01/T7: timeout transitions to COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())
	assert_eq(transitions.size(), 2)
	assert_eq(transitions[1]["prev"], UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_eq(transitions[1]["new"], UnitControlState.ControlMode.COMMUNITY_FREE)

	await _teardown_main(ctx)


# ==============================================================================
# D02: Experimental 3/8/15 s, D2SimulationPauseController pause/resume, stale callbacks, max 1 conn, COMMUNITY no timer
# ==============================================================================
func test_d02_pause_resume_experimental_durations_stale_callbacks_and_community_no_timer() -> void:
	var ctx := await _boot_main(3.0)
	var main: MainScene = ctx["main"] as MainScene
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var board: CommunityWorkBoard = ctx["board"] as CommunityWorkBoard
	var disp: CommunityTaskDispatcher = ctx["dispatcher"] as CommunityTaskDispatcher
	var bush: ResourceSource = _find_source(main, &"food_bush_01")

	# Spawn a COMMUNITY adult worker and verify it NEVER instantiates a wait timer even after community work.
	var comm_unit: Unit = UNIT_SCENE.instantiate() as Unit
	comm_unit.name = "CommAdultD02"
	comm_unit.definition = _make_def(&"comm_adult_d02", "Morador D02", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT)
	comm_unit.position = bush.global_position + Vector3(-1.5, 0.0, 0.0)
	main.get_node("Units").add_child(comm_unit)
	comm_unit.set_world_navigation(ctx["nav"] as WorldNavigation)
	ReservedWithdrawalCoordinator.admit_empty_provenance_units(
		[comm_unit], main.get_node("Units"), ctx["camp"] as CampStorageZone, ctx["inv"] as SettlementInventory, ctx["region_id"] as StringName
	)
	assert_false(comm_unit.has_personal_wait_timer(), "D02: COMMUNITY unit must not create Timer on spawn")
	assert_false(comm_unit.issue_personal_order(MoveOrder.new(comm_unit.global_position)))
	assert_false(comm_unit.has_personal_wait_timer(), "D02: COMMUNITY unit must never create Timer")

	# Verify 3 / 8 / 15 s experimental options configure future waits without mutating an active timer!
	leader_a.personal_post_move_wait_sec = 3.0
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	var left_3s: float = leader_a.get_personal_wait_time_left()
	assert_true(left_3s > 2.5 and left_3s <= 3.01, "Active 3.0 s timer starts near 3.0 s (got %.3f)" % left_3s)

	# Changing export to 15.0 while timer is active must NOT alter the currently running 3.0 s wait!
	leader_a.personal_post_move_wait_sec = 15.0
	assert_true(leader_a.get_personal_wait_time_left() <= 3.01, "Changing personal_post_move_wait_sec affects ONLY future waits")
	leader_a.cancel_current_order()

	# Next wait uses 15.0 s, and another uses 8.0 s!
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_gt(leader_a.get_personal_wait_time_left(), 14.0, "Future wait uses 15.0 s option")
	leader_a.personal_post_move_wait_sec = 8.0
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	var left_8s: float = leader_a.get_personal_wait_time_left()
	assert_true(left_8s > 7.2 and left_8s <= 8.01, "Future wait uses 8.0 s provisional option (got %.3f)" % left_8s)

	# Repeated rearming must maintain strictly <= 1 connection on _wait_timer.timeout!
	for _i: int in range(5):
		assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a._wait_timer.timeout.get_connections().size(), 1, "D02: Max 1 timeout connection across repeated rearms")

	# Stale callback with outdated token or revision is strictly ignored!
	var cur_token: int = leader_a.get_personal_wait_token_id()
	var cur_rev: int = leader_a.get_order_revision()
	leader_a._on_personal_wait_timeout(cur_token - 1, cur_rev)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "Stale token ignored")
	leader_a._on_personal_wait_timeout(cur_token, cur_rev - 1)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "Stale revision ignored")

	# Pause/resume via real D2SimulationPauseController freezes D-05 timer!
	var pause_ctrl := D2SimulationPauseController.new()
	main.add_child(pause_ctrl)
	pause_ctrl.configure(main.get_node("RtsCameraRig") as RtsCameraRig, main.get_economy_clock())

	leader_a.cancel_current_order()
	leader_a.personal_post_move_wait_sec = 0.14
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_eq(leader_a._wait_timer.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_false(leader_a._wait_timer.ignore_time_scale)

	# Pause simulation and wait longer than 0.14 s in real wall time -> timer MUST remain frozen!
	assert_true(pause_ctrl.request_pause(&"b3_d02_pause"))
	assert_true(get_tree().paused, "D2SimulationPauseController pauses SceneTree")
	var left_at_pause: float = leader_a.get_personal_wait_time_left()
	# Also verify manual callback invocation while paused is rejected by Guard #7!
	leader_a._on_personal_wait_timeout(leader_a.get_personal_wait_token_id(), leader_a.get_order_revision())
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "Guard #7 blocks timeout while paused")
	await get_tree().create_timer(0.24, true).timeout
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT, "D02: Timer must NOT expire while paused")
	assert_near(leader_a.get_personal_wait_time_left(), left_at_pause, 0.03, "D02: Remaining wait time frozen during pause")

	# Resume simulation -> timer finishes remaining duration and transitions to COMMUNITY_FREE!
	assert_true(pause_ctrl.release_pause(&"b3_d02_pause"))
	assert_false(get_tree().paused)
	await get_tree().create_timer(0.24, true).timeout
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "D02: Resuming simulation lets D-05 expire cleanly")
	assert_false(leader_a.is_personal_wait_timer_active())
	pause_ctrl.unbind()

	# Clean up unused vars check
	assert_not_null(leader_b)
	assert_not_null(board)
	assert_not_null(disp)
	await _teardown_main(ctx)


# ==============================================================================
# F01: Removal from tree, definition downgrade, and controlled teardown during PERSONAL_POST_MOVE_WAIT
# ==============================================================================
func test_f01_lifecycle_removal_definition_downgrade_and_teardown_during_wait() -> void:
	var ctx := await _boot_main(0.30)
	var main: MainScene = ctx["main"] as MainScene
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# 1. Definition downgrade FOUNDING_HOUSE -> COMMUNITY during PERSONAL_POST_MOVE_WAIT -> T9 cancels wait immediately.
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	var a_modes: Array[UnitControlState.ControlMode] = []
	leader_a.control_mode_changed.connect(func(n: UnitControlState.ControlMode, _p: UnitControlState.ControlMode) -> void:
		a_modes.append(n)
	)
	var rev_before_downgrade: int = leader_a.get_order_revision()
	var comm_def := _make_def(&"leader_a_comm", "Ex-Lider", CharacterDefinition.HouseAffiliation.COMMUNITY, CharacterDefinition.FoundingHouseOrigin.NONE, CharacterDefinition.AgeStage.ADULT)
	leader_a.apply_definition(comm_def)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "F01: downgrade to COMMUNITY cancels wait -> COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active())
	assert_gt(leader_a.get_order_revision(), rev_before_downgrade)
	assert_eq(a_modes.size(), 1)

	# 2. Definition downgrade FOUNDING_HOUSE -> BABY during PERSONAL_POST_MOVE_WAIT -> T9 cancels wait immediately.
	assert_true(leader_b.issue_personal_order(MoveOrder.new(leader_b.global_position)))
	assert_eq(leader_b.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	var baby_def := _make_def(&"leader_b_baby", "Bebe", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT, CharacterDefinition.AgeStage.BABY)
	leader_b.apply_definition(baby_def)
	assert_eq(leader_b.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "F01: downgrade to BABY cancels wait -> COMMUNITY_FREE")
	assert_false(leader_b.is_personal_wait_timer_active())

	# 3. Restore founding house on leader_a, enter wait, then remove from tree -> timer stopped & disconnected cleanly.
	var founder_def := _make_def(&"leader_a_restored", "Ayla", CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE, CharacterDefinition.FoundingHouseOrigin.ORIGINAL_FOUNDER, CharacterDefinition.AgeStage.ADULT)
	leader_a.apply_definition(founder_def)
	assert_true(leader_a.issue_personal_order(MoveOrder.new(leader_a.global_position)))
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	assert_true(leader_a.is_personal_wait_timer_active())
	leader_a.get_parent().remove_child(leader_a)
	assert_eq(leader_a.get_control_mode(), UnitControlState.ControlMode.COMMUNITY_FREE, "F01: removal during wait stabilizes COMMUNITY_FREE")
	assert_false(leader_a.is_personal_wait_timer_active(), "F01: timer stopped on tree exit")
	assert_true(leader_a._wait_timer.timeout.get_connections().is_empty(), "F01: timer callback disconnected on tree exit")
	leader_a.queue_free()

	# 4. Controlled teardown during active PERSONAL_POST_MOVE_WAIT on a fresh MainScene succeeds cleanly.
	await _teardown_main(ctx)
	var ctx2 := await _boot_main(2.0)
	var la2: Unit = ctx2["leader_a"] as Unit
	assert_true(la2.issue_personal_order(MoveOrder.new(la2.global_position)))
	assert_eq(la2.get_control_mode(), UnitControlState.ControlMode.PERSONAL_POST_MOVE_WAIT)
	var td_res: Dictionary = (ctx2["main"] as MainScene).request_controlled_teardown()
	assert_true(bool(td_res.get("ok", false)), "F01: controlled teardown succeeds during active PERSONAL_POST_MOVE_WAIT")
	await _teardown_main(ctx2)
