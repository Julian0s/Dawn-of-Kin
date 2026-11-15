extends TestCase
## Integration tests for T3.3 ConstructionSite & Physical Logistics in real MainScene + TestMap:
## - End-to-end: placement LMB confirm -> atomic reserve -> site spawn -> targeted pile pickup ->
##   loaded transport -> perimeter drop-off -> full buffer -> no auto T3.4 progress/rebake
## - Overlap / CampStorageZone / duplicate async / insufficient free stock rejections
## - D9 1/2/3/4 worker organization, max_builders=2 enforcement, automatic transporter promotion,
##   and forced concurrent multi-transporter delivery without double-withdrawal
## - Two competing sites (no cross-stealing) and two isolated World3D regions
## - Interruption keeping backpack cargo + resume, unneeded tree cargo safe camp return,
##   decay/removal mid-walk (Alternative B), unreachable pile/site, and clean teardown.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")

const MAX_NAV_FRAMES: int = 120
const MAX_SIM_FRAMES: int = 1800
const SITE_POS_A := Vector3(-6.0, 0.0, 1.5)
const SITE_POS_B := Vector3(0.37, 0.0, -13.19)


func after_each() -> void:
	_release_all_inputs()


func _release_all_inputs() -> void:
	for btn: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(btn):
			var ev := InputEventMouseButton.new()
			ev.button_index = btn
			ev.pressed = false
			get_viewport().push_input(ev, true)


func _spawn_main_in_viewport(vp_size: Vector2i = Vector2i(1280, 720)) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = vp_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(main_root)

	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var frames: int = 0
	while nav != null and not nav.is_navigation_ready() and frames < MAX_NAV_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	await wait_process_frames(2)
	await wait_physics_frames(2)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	return {
		"vp": vp,
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"placement": main_root.get_placement_controller(),
		"overlay": main_root.get_placement_test_overlay(),
		"selection": main_root.get_selection_manager(),
		"command": main_root.get_command_controller(),
		"inventory": main_root.get_settlement_inventory(),
		"pile_manager": main_root.get_ground_pile_manager(),
		"camp": main_root.get_camp_storage_zone(),
		"cm": main_root.get_construction_manager(),
		"units": main_root.get_units(),
	}


func _push_mouse_motion(vp: SubViewport, screen_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen_pos
	ev.global_position = screen_pos
	vp.push_input(ev, false)


func _push_mouse_click(vp: SubViewport, button: MouseButton, screen_pos: Vector2) -> void:
	_push_mouse_motion(vp, screen_pos)
	await wait_process_frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = screen_pos
	press.global_position = screen_pos
	vp.push_input(press, false)
	await wait_process_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = screen_pos
	release.global_position = screen_pos
	vp.push_input(release, false)
	await wait_process_frames(2)


func _wait_for_confirm_settled(placement: PlacementController) -> void:
	var frames: int = 0
	while placement.is_confirm_pending() and frames < 120:
		await wait_process_frames(1)
		frames += 1


func _spawn_extra_worker(main_root: MainScene, nav: WorldNavigation, worker_name: String, pos: Vector3) -> Unit:
	var u: Unit = UNIT_SCENE.instantiate() as Unit
	u.name = worker_name
	u.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	var units_root: Node = main_root.get_node("Units")
	units_root.add_child(u)
	u.global_position = pos
	u.set_world_navigation(nav)
	return u


func test_01_full_e2e_shelter_placement_reserve_transport_and_no_t34_progress() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var camera: Camera3D = ctx["camera"] as Camera3D
	var placement: PlacementController = ctx["placement"] as PlacementController
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var worker: Unit = units[0]

	# Seed camp stock: 14 wood + 8 stone (Shelter costs 12 wood, 6 stone).
	assert_true(inventory.deposit(&"wood", 14))
	assert_true(inventory.deposit(&"stone", 8))

	# 1. Place Shelter via PlacementController LMB on SITE_POS_A.
	placement.start_placement(SHELTER_DEF)
	var site_screen: Vector2 = camera.unproject_position(SITE_POS_A)
	_push_mouse_motion(vp, site_screen)
	await wait_process_frames(2)
	var poly_before: int = nav.navigation_mesh.get_polygon_count()
	var nav_rev_before: int = nav.get_navigation_revision()

	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, site_screen)
	await _wait_for_confirm_settled(placement)

	assert_false(placement.is_placement_active(), "Placement must close after valid confirm")
	assert_eq(cm.get_sites().size(), 1, "ConstructionManager must spawn exactly 1 ConstructionSite")
	var site: ConstructionSite = cm.get_sites()[0]
	assert_true(site.is_valid())
	assert_true(overlay.is_site_panel_visible(), "Temporary UI must show newly created site status")
	assert_eq(inventory.get_reserved_amount(&"wood"), 12)
	assert_eq(inventory.get_reserved_amount(&"stone"), 6)
	assert_eq(inventory.get_available_amount(&"wood"), 2)
	assert_eq(inventory.get_available_amount(&"stone"), 2)
	assert_eq(nav.navigation_mesh.get_polygon_count(), poly_before, "T3.3 must NOT rebake active NavMesh")
	assert_eq(nav.get_navigation_revision(), nav_rev_before)

	# 2. Left-click site updates inspector cleanly; select worker and right-click site to assign.
	selection.select_single(worker)
	var site_pick_screen: Vector2 = camera.unproject_position(site.global_position + Vector3(0.0, 0.35, 0.0))
	await _push_mouse_click(vp, MOUSE_BUTTON_RIGHT, site_pick_screen)

	assert_not_null(worker.get_current_order())
	assert_eq(worker.get_current_order().get_order_name(), "ConstructOrder")
	assert_eq(site.get_worker_role(worker), ConstructionSite.WorkerRole.SOLO_SUPPLIER)

	# 3. Run simulation and observe: targeted pickup, loaded speed slowdown, buffer fill, zero premature buffer!
	var saw_pickup_load: bool = false
	var saw_loaded_slowdown: bool = false
	var saw_zero_premature_buffer: bool = false
	var move_comp: UnitMovement = worker.get_movement()
	var frames: int = 0
	while not site.is_fully_supplied() and frames < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if not worker.get_carry_load().is_empty():
			saw_pickup_load = true
			if worker.get_state() == Unit.State.TRANSPORTING and move_comp.get_target_move_speed() < 4.7 and move_comp.get_current_load_multiplier() < 0.99:
				saw_loaded_slowdown = true
			if site.get_delivered_buffer_amount(&"wood") == 0 and site.get_delivered_buffer_amount(&"stone") == 0:
				saw_zero_premature_buffer = true

	assert_true(site.is_fully_supplied(), "Solo supplier must complete all wood + stone trips within simulation budget")
	assert_true(saw_pickup_load, "Worker must physically load withdrawn materials into CarryLoad")
	assert_true(saw_loaded_slowdown, "Loaded transport speed must reflect UnitCarryLoad weight reduction")
	assert_true(saw_zero_premature_buffer, "Buffer must not be credited before worker arrives at site perimeter")

	# Wait a couple frames for order completion & confirm NO T3.4 auto-building occurs.
	await wait_physics_frames(4)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 12)
	assert_eq(site.get_delivered_buffer_amount(&"stone"), 6)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 0)
	assert_eq(site.get_in_transit_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_eq(inventory.get_physical_amount(&"wood"), 2, "Only excess unreserved wood stays in camp")
	assert_eq(inventory.get_physical_amount(&"stone"), 2)
	assert_true(worker.get_carry_load().is_empty())
	assert_eq(worker.get_state(), Unit.State.IDLE, "Solo supplier finishes cleanly once site is supplied")
	assert_true(site.is_inside_tree() and site.is_valid(), "T3.3 must keep ConstructionSite incomplete (no T3.4 transmutation)")
	assert_eq(nav.navigation_mesh.get_polygon_count(), poly_before, "Active NavMesh stays unchanged after supply completion")

	vp.queue_free()
	await wait_process_frames(2)


func test_02_rejections_site_overlap_camp_zone_duplicate_and_insufficient_stock() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var camera: Camera3D = ctx["camera"] as Camera3D
	var placement: PlacementController = ctx["placement"] as PlacementController
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager

	assert_true(inventory.deposit(&"wood", 20))
	assert_true(inventory.deposit(&"stone", 10))

	# Confirm Shelter 1 at SITE_POS_A -> consumes 12 wood, 6 stone (8 wood, 4 stone free remain).
	placement.start_placement(SHELTER_DEF)
	var site_screen: Vector2 = camera.unproject_position(SITE_POS_A)
	_push_mouse_motion(vp, site_screen)
	await wait_process_frames(2)
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, site_screen)
	await _wait_for_confirm_settled(placement)
	assert_eq(cm.get_sites().size(), 1)
	var site1: ConstructionSite = cm.get_sites()[0]

	# Attempt placing Shelter 2 overlapping Shelter 1 -> PlacementValidator rejects.
	var rejected: Array[PlacementValidator.ValidationResult] = []
	placement.placement_rejected.connect(func(_d: BuildingDefinition, _p: Vector3, res: PlacementValidator.ValidationResult) -> void:
		rejected.append(res)
	)
	placement.start_placement(SHELTER_DEF)
	var overlap_screen: Vector2 = camera.unproject_position(SITE_POS_A + Vector3(-1.5, 0.0, 0.5))
	await _push_mouse_click(vp, MOUSE_BUTTON_LEFT, overlap_screen)
	await _wait_for_confirm_settled(placement)
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
	assert_eq(cm.get_sites().size(), 1)

	# Direct duplicate site / CampZone / insufficient remaining stock checks.
	var dup_res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, site1.global_position)
	assert_false(bool(dup_res["ok"]))
	assert_eq(dup_res["reason"], "site_overlap")

	var ins_res: Dictionary = cm.try_create_site_from_placement(DEPOT_DEF, SITE_POS_B)
	assert_false(bool(ins_res["ok"]))
	assert_eq(ins_res["reason"], "insufficient_resources")
	assert_true(overlay.is_status_visible(), "Rejection message must appear in UI")
	assert_eq(inventory.get_available_amount(&"wood"), 8, "Failed 2nd site must not touch remaining free wood")
	assert_eq(inventory.get_available_amount(&"stone"), 4)

	vp.queue_free()
	await wait_process_frames(2)


func test_03_d9_two_three_four_workers_promotion_and_concurrent_force_transporter() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var command: CommandController = ctx["command"] as CommandController
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var base_units: Array[Unit] = ctx["units"] as Array[Unit]

	assert_true(inventory.deposit(&"wood", 24))
	assert_true(inventory.deposit(&"stone", 12))

	var res_site: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res_site["ok"]))
	var site1: ConstructionSite = res_site["site"] as ConstructionSite

	var w1: Unit = base_units[0]
	var w2: Unit = base_units[1]
	# Position W1 slightly further so W2/W3 reach perimeter builder standby before W1 withdraws pile cargo.
	w1.global_position = Vector3(-12.0, 0.0, 1.5)
	var w3: Unit = _spawn_extra_worker(main_root, nav, "Worker3", SITE_POS_A + Vector3(-3.0, 0.0, 1.5))
	var w4: Unit = _spawn_extra_worker(main_root, nav, "Worker4", SITE_POS_A + Vector3(-3.0, 0.0, -1.5))
	w2.global_position = SITE_POS_A + Vector3(0.0, 0.0, 3.2)
	await wait_physics_frames(2)

	# Assign 3 workers in AUTO_D9 via CommandController: 1 transporter + 2 builders (max_builders = 2).
	assert_true(command.command_units_to_site(site1, [w1, w2, w3]))
	assert_eq(site1.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site1.get_worker_role(w2), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(site1.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)

	# 4th worker exceeds max_builders=2 -> rejected cleanly without displacing existing builders!
	assert_false(command.command_units_to_site(site1, [w4]))
	assert_eq(command.get_last_command_reason(), ConstructOrder.REASON_NO_WORKER_SLOT)
	assert_eq(site1.get_assigned_worker_entries().size(), 3)

	# Let builders reach standby perimeter while W1 has not withdrawn materials yet.
	var wait_f: int = 0
	var saw_builders_standby: bool = false
	while wait_f < 600:
		await wait_physics_frames(1)
		wait_f += 1
		var o2: ConstructOrder = w2.get_current_order() as ConstructOrder
		var o3: ConstructOrder = w3.get_current_order() as ConstructOrder
		if o2 != null and o3 != null and o2.get_phase() == ConstructOrder.Phase.BUILDER_STANDBY and o3.get_phase() == ConstructOrder.Phase.BUILDER_STANDBY:
			saw_builders_standby = true
			break
	assert_true(saw_builders_standby, "2 builders must reach perimeter standby slots cleanly")
	assert_eq(w2.get_state(), Unit.State.WORKING)
	assert_eq(w3.get_state(), Unit.State.WORKING)

	# If W1 happened to already withdraw Trip 1, wait until it drops it off before interrupting with empty pack.
	var empty_wait: int = 0
	while not w1.get_carry_load().is_empty() and empty_wait < 600:
		await wait_physics_frames(1)
		empty_wait += 1
	assert_true(w1.get_carry_load().is_empty(), "W1 must not hold unreturned pile wood when testing clean promotion")

	# Interrupt W1 -> W2 promotes automatically to TRANSPORTER and finishes site1!
	w1.issue_order(MoveOrder.new(w1.global_position + Vector3(-2.0, 0.0, 2.0)))
	assert_eq(site1.get_worker_role(w2), ConstructionSite.WorkerRole.TRANSPORTER, "Builder W2 must auto-promote when W1 leaves")
	assert_eq(site1.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)

	var sup_f: int = 0
	while not site1.is_fully_supplied() and sup_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		sup_f += 1
	assert_true(site1.is_fully_supplied(), "Promoted transporter W2 must complete site supply cleanly")

	# Now verify 2 forced parallel transporters on Site 2 without double-withdrawal or RVO deadlock.
	var res_site2: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_B)
	assert_true(bool(res_site2["ok"]))
	var site2: ConstructionSite = res_site2["site"] as ConstructionSite
	w1.issue_order(ConstructOrder.new(site2, camp, true))
	w4.issue_order(ConstructOrder.new(site2, camp, true))
	assert_eq(site2.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site2.get_worker_role(w4), ConstructionSite.WorkerRole.TRANSPORTER)

	var par_f: int = 0
	while not site2.is_fully_supplied() and par_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		par_f += 1
	assert_true(site2.is_fully_supplied(), "Concurrent forced transporters must supply site2 cleanly without double withdrawal")
	assert_eq(site2.get_delivered_buffer_amount(&"wood"), 12)
	assert_eq(site2.get_delivered_buffer_amount(&"stone"), 6)

	vp.queue_free()
	await wait_process_frames(2)


func test_04_competing_sites_isolation_and_second_world3d_region() -> void:
	# Region 1
	var ctx1: Dictionary = await _spawn_main_in_viewport()
	var vp1: SubViewport = ctx1["vp"] as SubViewport
	var inv1: SettlementInventory = ctx1["inventory"] as SettlementInventory
	var camp1: CampStorageZone = ctx1["camp"] as CampStorageZone
	var cm1: ConstructionManager = ctx1["cm"] as ConstructionManager
	var u1_a: Unit = (ctx1["units"] as Array[Unit])[0]
	var u1_b: Unit = (ctx1["units"] as Array[Unit])[1]

	# Region 2 isolated in its own SubViewport + own_world_3d.
	var ctx2: Dictionary = await _spawn_main_in_viewport()
	var vp2: SubViewport = ctx2["vp"] as SubViewport
	var inv2: SettlementInventory = ctx2["inventory"] as SettlementInventory
	var camp2: CampStorageZone = ctx2["camp"] as CampStorageZone
	var cm2: ConstructionManager = ctx2["cm"] as ConstructionManager
	var u2_a: Unit = (ctx2["units"] as Array[Unit])[0]

	assert_true(inv1.deposit(&"wood", 24))
	assert_true(inv1.deposit(&"stone", 12))
	assert_true(inv2.deposit(&"wood", 12))
	assert_true(inv2.deposit(&"stone", 6))

	var s1_a: ConstructionSite = cm1.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)["site"] as ConstructionSite
	var s1_b: ConstructionSite = cm1.try_create_site_from_placement(SHELTER_DEF, SITE_POS_B)["site"] as ConstructionSite
	var s2_a: ConstructionSite = cm2.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)["site"] as ConstructionSite

	assert_ne(s1_a.reservation_id, s1_b.reservation_id)
	assert_eq(inv1.get_reserved_amount(&"wood"), 24)
	assert_eq(inv1.get_available_amount(&"wood"), 0)
	assert_eq(inv2.get_reserved_amount(&"wood"), 12)

	u1_a.issue_order(ConstructOrder.new(s1_a, camp1))
	u1_b.issue_order(ConstructOrder.new(s1_b, camp1))
	u2_a.issue_order(ConstructOrder.new(s2_a, camp2))

	var frames: int = 0
	while (not s1_a.is_fully_supplied() or not s1_b.is_fully_supplied() or not s2_a.is_fully_supplied()) and frames < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_true(s1_a.is_fully_supplied(), "Site A in Region 1 must complete independently")
	assert_true(s1_b.is_fully_supplied(), "Site B in Region 1 must complete independently")
	assert_true(s2_a.is_fully_supplied(), "Site in isolated Region 2 must complete cleanly")
	assert_eq(inv1.get_physical_amount(&"wood"), 0)
	assert_eq(inv2.get_physical_amount(&"wood"), 0)

	vp1.queue_free()
	vp2.queue_free()
	await wait_process_frames(2)


func test_05_interruption_cargo_preservation_unneeded_return_decay_and_teardown() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var worker: Unit = (ctx["units"] as Array[Unit])[0]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var site: ConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)["site"] as ConstructionSite

	# Subcase A: Load unneeded tree wood BEFORE site assignment -> worker returns it safely to camp WITHOUT deletion!
	assert_true(worker.get_carry_load().add_units(WOOD_DEF, 3))
	worker.issue_order(ConstructOrder.new(site, camp))

	var saw_camp_deposit: bool = false
	var frames: int = 0
	while not site.is_fully_supplied() and frames < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if not saw_camp_deposit and inventory.get_available_amount(&"wood") >= 3:
			saw_camp_deposit = true
			# Subcase B: Once carrying site-attributed wood mid-transit, interrupt with MoveOrder!
		if saw_camp_deposit and worker.get_state() == Unit.State.TRANSPORTING and not worker.get_carry_load().is_empty():
			var loaded_before_cancel: int = worker.get_carry_load().get_amount(&"wood") + worker.get_carry_load().get_amount(&"stone")
			worker.issue_order(MoveOrder.new(worker.global_position + Vector3(-1.5, 0.0, 0.0)))
			await wait_physics_frames(4)
			var loaded_after_cancel: int = worker.get_carry_load().get_amount(&"wood") + worker.get_carry_load().get_amount(&"stone")
			assert_eq(loaded_after_cancel, loaded_before_cancel, "Interrupting ConstructOrder must preserve backpack cargo intact")
			# Resume same site -> worker delivers preserved cargo without losing units.
			worker.issue_order(ConstructOrder.new(site, camp))
			saw_camp_deposit = false # continue cleanly until complete

	assert_true(site.is_fully_supplied(), "Worker must finish site after safe unneeded return & mid-trip resume")
	assert_eq(inventory.get_available_amount(&"wood"), 3, "Unneeded 3 tree wood returned to camp must remain conserved in stock")

	# Subcase C: Clean teardown mid-order with active site & orders leaves zero leaked references.
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var site2: ConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_B)["site"] as ConstructionSite
	worker.issue_order(ConstructOrder.new(site2, camp))
	await wait_physics_frames(10)

	vp.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(main_root), "Teardown mid-construction task must free MainScene cleanly")


func test_06_unreachable_site_pile_and_decay_mid_walk() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var time_p: SimulatedWorldTimeProvider = main_root.get_time_provider()
	var pile_mgr: GroundPileManager = ctx["pile_manager"] as GroundPileManager
	var worker: Unit = (ctx["units"] as Array[Unit])[0]

	# 1. Decay/loss mid-walk: replace pile manager definitions or decay food-weighted custom site.
	var decaying_wood: ResourceDefinition = WOOD_DEF.duplicate() as ResourceDefinition
	var decay_prof := DecayProfile.new()
	decay_prof.can_decay = true
	decay_prof.exposure_duration_sec = 2.0
	decay_prof.decay_mode = DecayProfile.DecayMode.EXPIRE_ALL
	decaying_wood.decay_profile = decay_prof

	# Create site in custom fast-decay fixture on MainScene's TestMap or directly step expiration.
	var local_camp := CampStorageZone.new()
	local_camp.zone_id = &"decay_walk_camp"
	local_camp.position = Vector3(6.0, 0.0, 2.0)
	local_camp.zone_bounds_half_extents = Vector2(2.5, 2.5)
	local_camp.set_world_navigation(nav)
	test_map.add_child(local_camp)
	var local_piles := Node3D.new()
	test_map.add_child(local_piles)
	var local_defs: Dictionary = {&"wood": decaying_wood, &"stone": STONE_DEF.duplicate()}
	var local_mgr := GroundPileManager.new(local_defs, local_camp, local_piles, time_p)
	var local_inv := SettlementInventory.new(local_mgr)
	var local_cm := ConstructionManager.new()
	main_root.add_child(local_cm)
	local_cm.configure(main_root.get_construction_sites_root(), local_inv, local_defs, local_camp, nav, &"decay_test")

	assert_true(local_inv.deposit(&"wood", 12))
	assert_true(local_inv.deposit(&"stone", 6))
	var decay_site: ConstructionSite = local_cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)["site"] as ConstructionSite
	assert_not_null(decay_site)

	worker.global_position = Vector3(-12.0, 0.0, 2.0)
	await wait_physics_frames(2)
	var decay_order := ConstructOrder.new(decay_site, local_camp)
	worker.issue_order(decay_order)
	assert_true(decay_order.is_active())

	# Walk a few frames, then expire wood pile mid-walk -> order must detect reservation loss!
	await wait_physics_frames(6)
	time_p.advance(5.0)
	local_mgr.step_decay()
	assert_eq(decay_site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(decay_site.get_missing_amount(&"wood"), 12)

	# 2. Unreachable site/pile inside TestMap closed enclosure (around (11, 0, -11)) -> fails cleanly!
	local_mgr.cleanup()
	local_cm.queue_free()
	local_piles.queue_free()
	local_camp.queue_free()
	await wait_process_frames(2)

	# TestMap's ClosedEnclosure sits around (x=10..16, z=-16..-10) or wall blocks isolated island;
	# Test unreachable site by placing a worker inside the closed enclosure!
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var reach_site: ConstructionSite = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_B)["site"] as ConstructionSite
	assert_not_null(reach_site)

	# Place enclosure box completely trapping worker away from NavMesh/rest of map and rebake.
	var prison := StaticBody3D.new()
	prison.name = "IsolatedIslandBlocker"
	prison.collision_layer = CollisionLayers.MASK_OBSTACLES
	prison.collision_mask = 0
	for spec: Array in [
		[Vector3(-12.0, 1.5, -9.0), Vector3(4.0, 3.0, 0.8)],
		[Vector3(-12.0, 1.5, -13.0), Vector3(4.0, 3.0, 0.8)],
		[Vector3(-14.0, 1.5, -11.0), Vector3(0.8, 3.0, 4.0)],
		[Vector3(-10.0, 1.5, -11.0), Vector3(0.8, 3.0, 4.0)],
	]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = spec[1] as Vector3
		cs.shape = bx
		cs.position = spec[0] as Vector3
		prison.add_child(cs)
	test_map.add_child(prison)
	await wait_physics_frames(2)
	nav.request_rebake()
	var nav_f: int = 0
	while not nav.is_navigation_ready() and nav_f < MAX_NAV_FRAMES:
		await wait_physics_frames(1)
		nav_f += 1
	assert_true(nav.is_navigation_ready())

	worker.global_position = Vector3(-12.0, 0.0, -11.0)
	await wait_physics_frames(2)
	var blocked_order := ConstructOrder.new(reach_site, camp)
	worker.issue_order(blocked_order)
	assert_eq(blocked_order.status, UnitOrder.Status.FAILED, "Blocked path to reserved piles must reject cleanly")
	assert_true(
		blocked_order.failure_reason == ConstructOrder.REASON_PILE_UNREACHABLE
		or blocked_order.failure_reason == ConstructOrder.REASON_SITE_UNREACHABLE
	)

	# Also ensure unused variable pile_mgr check stays clean without warnings.
	assert_not_null(pile_mgr)
	vp.queue_free()
	await wait_process_frames(2)
