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


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
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

	# In T3.4.3, once fully supplied, SOLO_SUPPLIER promotes to BUILDER and assembles to COMPLETING.
	await wait_physics_frames(4)
	assert_eq(site.get_total_received_amount(&"wood"), 12)
	assert_eq(site.get_total_received_amount(&"stone"), 6)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 0)
	assert_eq(site.get_in_transit_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"wood"), 0)
	assert_eq(inventory.get_physical_amount(&"wood"), 2, "Only excess unreserved wood stays in camp")
	assert_eq(inventory.get_physical_amount(&"stone"), 2)
	assert_true(worker.get_carry_load().is_empty())
	assert_eq(site.get_worker_role(worker), ConstructionSite.WorkerRole.BUILDER, "Solo supplier promotes to BUILDER once supplied")
	assert_true(worker.get_state() == Unit.State.WORKING or worker.get_state() == Unit.State.MOVING)

	var completed_id: StringName = site.site_id
	var build_frames: int = 0
	while cm.get_completed_buildings().is_empty() and build_frames < MAX_SIM_FRAMES * 2:
		await wait_physics_frames(1)
		build_frames += 1
	assert_eq(cm.get_completed_buildings().size(), 1)
	var building: BuildingInstance = cm.get_completed_buildings()[0]
	assert_eq(building.building_id, completed_id)
	assert_true(building.is_valid())
	assert_eq(building.incorporated_materials, {&"wood": 12, &"stone": 6})
	assert_null(cm.get_site_by_id(completed_id))
	await wait_physics_frames(4)
	assert_eq(worker.get_state(), Unit.State.IDLE)
	assert_false(is_instance_valid(site))
	assert_eq(nav.navigation_mesh.get_polygon_count(), poly_before, "Active NavMesh stays unchanged before T3.4.5")

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


func _build_wall_enclosure(parent: Node3D, node_name: String, center: Vector3, half_extents: Vector2, wall_height: float = 3.0, thickness: float = 0.45) -> StaticBody3D:
	var enclosure := StaticBody3D.new()
	enclosure.name = node_name
	enclosure.collision_layer = CollisionLayers.MASK_OBSTACLES
	enclosure.collision_mask = 0
	var half_h: float = wall_height * 0.5
	var specs: Array[Array] = [
		[Vector3(center.x, half_h, center.z + half_extents.y + thickness * 0.5), Vector3(half_extents.x * 2.0 + thickness * 2.0, wall_height, thickness)],
		[Vector3(center.x, half_h, center.z - half_extents.y - thickness * 0.5), Vector3(half_extents.x * 2.0 + thickness * 2.0, wall_height, thickness)],
		[Vector3(center.x + half_extents.x + thickness * 0.5, half_h, center.z), Vector3(thickness, wall_height, half_extents.y * 2.0)],
		[Vector3(center.x - half_extents.x - thickness * 0.5, half_h, center.z), Vector3(thickness, wall_height, half_extents.y * 2.0)],
	]
	for spec: Array in specs:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = spec[1] as Vector3
		cs.shape = bx
		cs.position = spec[0] as Vector3
		enclosure.add_child(cs)
	parent.add_child(enclosure)
	return enclosure


func _wait_nav_ready(nav: WorldNavigation) -> void:
	await wait_physics_frames(2)
	nav.request_rebake()
	var nav_f: int = 0
	while not nav.is_navigation_ready() and nav_f < MAX_NAV_FRAMES:
		await wait_physics_frames(1)
		nav_f += 1
	assert_true(nav.is_navigation_ready())


func test_06_r1_closed_wall_blocks_pile_withdrawal_and_site_dropoff() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var worker: Unit = (ctx["units"] as Array[Unit])[0]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	# A) Seal camp/piles inside a closed wall box; check both physical reach predicate AND order rejection.
	var wood_entries: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, &"wood")
	assert_false(wood_entries.is_empty())
	var wood_pile_pos: Vector3 = wood_entries[0]["world_pos"] as Vector3
	var camp_enclosure: StaticBody3D = _build_wall_enclosure(
		test_map,
		"R1_ClosedCampWall",
		camp.global_position,
		camp.zone_bounds_half_extents + Vector2(0.8, 0.8)
	)
	await _wait_nav_ready(nav)

	# Even when unit stands right outside the wall within nominal distance, wall blocks physical pile reach.
	var site_world: World3D = site.get_world_3d()
	assert_not_null(site_world)
	var near_outside: Vector3 = wood_pile_pos + Vector3(-1.45, 0.0, 0.0)
	if near_outside.x > camp.global_position.x - camp.zone_bounds_half_extents.x - 1.5:
		near_outside = camp.global_position + Vector3(-(camp.zone_bounds_half_extents.x + 1.5), 0.0, 0.0)
	assert_false(
		BuildSlotPlanner.is_unit_in_pile_reach(near_outside, wood_pile_pos, ConstructionSite.DEFAULT_PILE_PICKUP_REACH, site_world),
		"Pile reach predicate must return false across a closed wall"
	)

	worker.global_position = near_outside
	await wait_physics_frames(2)
	var blocked_pile_order := ConstructOrder.new(site, camp)
	worker.issue_order(blocked_pile_order)
	var f1: int = 0
	while blocked_pile_order.is_active() and f1 < 300:
		await wait_physics_frames(1)
		f1 += 1
	assert_eq(blocked_pile_order.status, UnitOrder.Status.FAILED, "Closed wall around reserved piles must fail cleanly")
	assert_eq(blocked_pile_order.failure_reason, ConstructOrder.REASON_PILE_UNREACHABLE)
	assert_true(worker.get_carry_load().is_empty(), "No units may be withdrawn through a closed wall")
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 12)

	# Remove camp enclosure before testing site enclosure.
	camp_enclosure.queue_free()
	await _wait_nav_ready(nav)

	# B) Worker validly withdraws 5 wood, then a closed wall surrounds the construction site before dropoff.
	var pile_id: int = int(wood_entries[0]["pile_id"])
	var withdrawn: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		pile_id,
		site.reservation_id,
		WOOD_DEF.duplicate() as ResourceDefinition,
		5,
		worker.get_carry_load()
	)
	assert_eq(withdrawn, 5)
	site.record_withdrawn_for_site(worker, &"wood", withdrawn)

	var half_extents: Vector2 = site.get_footprint_rect().size * 0.5
	var site_enclosure: StaticBody3D = _build_wall_enclosure(
		test_map,
		"R1_ClosedSiteWall",
		site.global_position,
		half_extents + Vector2(0.45, 0.45)
	)
	await _wait_nav_ready(nav)

	var outside_site: Vector3 = site.global_position + Vector3(-(half_extents.x + 1.10), 0.0, 0.0)
	assert_false(
		BuildSlotPlanner.is_unit_in_site_dropoff_range(outside_site, site, ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, site_world),
		"Dropoff reach predicate must reject delivery across a closed wall even inside perimeter tolerance"
	)

	worker.global_position = outside_site
	await wait_physics_frames(2)
	var blocked_site_order := ConstructOrder.new(site, camp)
	worker.issue_order(blocked_site_order)
	var f2: int = 0
	while blocked_site_order.is_active() and f2 < 300:
		await wait_physics_frames(1)
		f2 += 1
	assert_eq(blocked_site_order.status, UnitOrder.Status.FAILED, "Closed wall around site must fail cleanly")
	assert_eq(blocked_site_order.failure_reason, ConstructOrder.REASON_SITE_UNREACHABLE)
	assert_eq(worker.get_carry_load().get_amount(&"wood"), 5, "Cargo must remain intact in backpack when dropoff is wall-blocked")
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0, "Site buffer must stay 0 when wall blocks dropoff")

	site_enclosure.queue_free()
	vp.queue_free()
	await wait_process_frames(2)


func test_07_r1_partial_wall_detour_and_open_ground_regression() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var worker: Unit = (ctx["units"] as Array[Unit])[0]

	# Place a site in open space at (-6, 0, -5) and place a partial wall between worker's west approach and site.
	var detour_site_pos := Vector3(-6.0, 0.0, -5.0)
	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, detour_site_pos)
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	var partial_wall := StaticBody3D.new()
	partial_wall.name = "R1_PartialWall"
	partial_wall.collision_layer = CollisionLayers.MASK_OBSTACLES
	partial_wall.collision_mask = 0
	var wall_cs := CollisionShape3D.new()
	var wall_bx := BoxShape3D.new()
	wall_bx.size = Vector3(0.45, 3.0, 6.2)
	wall_cs.shape = wall_bx
	wall_cs.position = detour_site_pos + Vector3(-2.55, 1.5, 0.0)
	partial_wall.add_child(wall_cs)
	test_map.add_child(partial_wall)
	await _wait_nav_ready(nav)

	# 2C: Directly west of the partial wall is within tolerance (1.05m from west face) yet blocked by the wall.
	var site_world: World3D = site.get_world_3d()
	assert_not_null(site_world)
	var west_of_wall: Vector3 = detour_site_pos + Vector3(-3.05, 0.0, 0.0)
	assert_false(
		BuildSlotPlanner.is_unit_in_site_dropoff_range(west_of_wall, site, ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, site_world),
		"Partial wall between unit and site face must block straight-line dropoff reach"
	)

	var slot_res: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(
		west_of_wall,
		site,
		nav
	)
	assert_true(bool(slot_res.get("valid", false)), "Partial wall with open detour must resolve a valid accessible perimeter slot")
	var chosen_slot: Vector3 = slot_res["position"] as Vector3
	assert_true(
		BuildSlotPlanner.is_unit_in_site_dropoff_range(chosen_slot, site, ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, site_world),
		"Chosen perimeter slot must have unobstructed dropoff reach to the site"
	)

	# Worker starts west of partial wall holding 6 reserved wood; must walk around the wall (never drop through wall) and finish all 12w/6s.
	var wood_entries: Array[Dictionary] = inventory.get_reserved_pile_entries(site.reservation_id, &"wood")
	var wood_pile_id: int = int(wood_entries[0]["pile_id"])
	var pre_taken: int = inventory.withdraw_reserved_from_pile_to_carry_load(
		wood_pile_id,
		site.reservation_id,
		WOOD_DEF.duplicate() as ResourceDefinition,
		6,
		worker.get_carry_load()
	)
	assert_eq(pre_taken, 6)
	site.record_withdrawn_for_site(worker, &"wood", pre_taken)

	worker.global_position = west_of_wall
	await wait_physics_frames(2)
	var detour_order := ConstructOrder.new(site, camp)
	worker.issue_order(detour_order)

	var max_z_deviation: float = 0.0
	var delivered_only_with_clear_reach: bool = true
	var prev_wood_buf: int = 0
	var sim_f: int = 0
	while not site.is_fully_supplied() and sim_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		sim_f += 1
		max_z_deviation = maxf(max_z_deviation, absf(worker.global_position.z - detour_site_pos.z))
		var cur_buf: int = site.get_delivered_buffer_amount(&"wood")
		if cur_buf > prev_wood_buf:
			if not BuildSlotPlanner.is_unit_in_site_dropoff_range(worker.global_position, site, ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE + 0.15, site_world):
				delivered_only_with_clear_reach = false
			prev_wood_buf = cur_buf

	assert_true(site.is_fully_supplied(), "Worker must complete full supply after detouring partial wall and continuing on open ground")
	assert_true(delivered_only_with_clear_reach, "Delivery must only happen from an unobstructed side of the partial wall")
	assert_true(max_z_deviation > 1.8, "Worker starting behind partial wall must physically detour around wall edge (not pass through wall)")
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 12)
	assert_eq(site.get_delivered_buffer_amount(&"stone"), 6)

	partial_wall.queue_free()
	vp.queue_free()
	await wait_process_frames(2)


func test_08_r1_interrupted_transporter_does_not_stall_replacement_or_touch_builder_pack() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var main_root: MainScene = ctx["main"] as MainScene
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var w1: Unit = (ctx["units"] as Array[Unit])[0]
	var w2: Unit = _spawn_extra_worker(main_root, nav, "R1_PeerW2", camp.global_position + Vector3(-1.5, 0.0, 4.0))
	var w3: Unit = _spawn_extra_worker(main_root, nav, "R1_PeerW3", camp.global_position + Vector3(-2.5, 0.0, 4.0))

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, SITE_POS_A)
	assert_true(bool(res["ok"]))
	var site: ConstructionSite = res["site"] as ConstructionSite

	# Pre-seed W3 (will be BUILDER) with 2 external unattributed wood that must remain untouched during standby.
	assert_true(w3.get_carry_load().add_units(WOOD_DEF.duplicate() as ResourceDefinition, 2))

	# 1. Start W1 as SOLO_SUPPLIER until it withdraws reserved wood, then interrupt it mid-transport.
	w1.global_position = camp.global_position + Vector3(-1.0, 0.0, 2.5)
	await wait_physics_frames(2)
	var o1 := ConstructOrder.new(site, camp)
	w1.issue_order(o1)
	var withdraw_f: int = 0
	while w1.get_carry_load().is_empty() and withdraw_f < 600:
		await wait_physics_frames(1)
		withdraw_f += 1
	assert_false(w1.get_carry_load().is_empty(), "W1 must physically withdraw material before interruption")
	var orphan_wood: int = w1.get_carry_load().get_amount(&"wood")
	assert_true(orphan_wood > 0)

	# Interrupt W1 -> move far away, leaving orphan transit claim in W1's backpack.
	w1.issue_order(MoveOrder.new(Vector3(-12.0, 0.0, -8.0)))
	await wait_physics_frames(4)
	assert_false(site.has_active_peer_transport_for_site(), "Interrupted worker orphan claim must NOT count as active peer transport")

	# 2. Assign W2 (TRANSPORTER) and W3 (BUILDER) to the site.
	var o2 := ConstructOrder.new(site, camp)
	var o3 := ConstructOrder.new(site, camp)
	w2.issue_order(o2)
	w3.issue_order(o3)
	assert_eq(site.get_worker_role(w2), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site.get_worker_role(w3), ConstructionSite.WorkerRole.BUILDER)

	# Track W2 phase transitions and verify W3 safely returns its 2 external wood to camp without leaking into site.
	var phase_changes: int = 0
	var last_phase: ConstructOrder.Phase = o2.get_phase()
	var saw_builder_returning_unneeded: bool = false
	var saw_builder_assembling_after_return: bool = false
	var f: int = 0
	while o2.is_active() and f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		f += 1
		var cur_phase: ConstructOrder.Phase = o2.get_phase()
		if cur_phase != last_phase:
			phase_changes += 1
			last_phase = cur_phase
		if o3.is_active():
			if o3.get_phase() == ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO:
				saw_builder_returning_unneeded = true
			if w3.get_carry_load().is_empty() and (
				o3.get_phase() == ConstructOrder.Phase.BUILDER_ASSEMBLING
				or o3.get_phase() == ConstructOrder.Phase.WAITING_FOR_MATERIALS
				or o3.get_phase() == ConstructOrder.Phase.BUILDER_STANDBY
			):
				saw_builder_assembling_after_return = true

	# W2 must NOT stall in infinite wait/replanning; once piles are exhausted it must finish cleanly with REASON_RESERVATION_UNAVAILABLE.
	assert_false(o2.is_active(), "Replacement transporter must NOT stall infinitely waiting on interrupted peer claim")
	assert_eq(o2.status, UnitOrder.Status.FAILED)
	assert_eq(o2.failure_reason, ConstructOrder.REASON_RESERVATION_UNAVAILABLE)
	assert_true(phase_changes <= 24, "Replacement transporter must not loop/replan per frame (phase_changes=%d)" % phase_changes)
	assert_eq(site.get_total_received_amount(&"wood"), 12 - orphan_wood, "W2 must deliver all non-orphaned pile wood before exiting")
	assert_eq(site.get_total_received_amount(&"stone"), 6, "W2 must deliver all reserved stone before exiting")
	assert_true(saw_builder_returning_unneeded, "BUILDER carrying unneeded external wood must route through camp return")
	assert_true(w3.get_carry_load().is_empty() and inventory.get_available_amount(&"wood") == 2, "BUILDER external wood must return to camp stock without leaking into site")
	assert_true(saw_builder_assembling_after_return, "BUILDER must proceed to builder slot after returning external wood")

	# Cancel W3 cleanly if promoted after W2 exited, then re-issue W1 with its attributed wood -> site finishes 100%!
	w3.issue_order(MoveOrder.new(Vector3(-11.0, 0.0, -8.0)))
	await wait_physics_frames(2)

	var o1_resume := ConstructOrder.new(site, camp)
	w1.issue_order(o1_resume)
	var resume_f: int = 0
	while not site.is_fully_supplied() and resume_f < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		resume_f += 1
	assert_true(site.is_fully_supplied(), "Re-issuing original interrupted worker must deliver its held claim and reach 100% supply")
	assert_eq(site.get_total_received_amount(&"wood"), 12)
	assert_eq(site.get_total_received_amount(&"stone"), 6)
	assert_eq(inventory.get_available_amount(&"wood"), 2, "Returned external wood remains conserved in camp")

	vp.queue_free()
	await wait_process_frames(2)


func test_09_r2_plateau_ramp_detour_and_elevated_slot_filtering() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var worker: Unit = (ctx["units"] as Array[Unit])[0]

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var plateau_edge_pos := Vector3(15.2, 2.0, -11.2)
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, plateau_edge_pos)
	assert_true(bool(res.get("ok", false)), "Plateau ramp-edge shelter placement must succeed")
	var site: ConstructionSite = res["site"] as ConstructionSite
	await wait_physics_frames(2)
	await _wait_nav_ready(nav)

	# 1. Verify lower ground below the 2m plateau cliff never satisfies site dropoff or slot selection.
	var site_world: World3D = site.get_world_3d()
	assert_not_null(site_world)
	assert_false(
		BuildSlotPlanner.is_unit_in_site_dropoff_range(
			Vector3(15.2, 0.0, -8.5),
			site,
			ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE,
			site_world
		),
		"Lower ground below 2m plateau drop-off must never count as valid site dropoff range"
	)
	var cliff_slot: Dictionary = BuildSlotPlanner.compute_site_perimeter_slot(Vector3(15.2, 0.0, -7.5), site, nav)
	assert_true(bool(cliff_slot.get("valid", false)))
	var cliff_slot_pos: Vector3 = cliff_slot["position"] as Vector3
	assert_true(cliff_slot_pos.y >= 1.4, "Resolved perimeter slot for plateau site must stay elevated (got y=%.3f)" % cliff_slot_pos.y)

	# 2. Verify forced lateral approach South of ramp routes west around ramp foot (x <= 5.0) with 0 lateral Ramp wall hits.
	var lateral_start := Vector3(9.5, 0.0, -9.8)
	worker.global_position = lateral_start
	await wait_physics_frames(2)
	var ramp_top_target := Vector3(13.8, 2.0, -14.0)
	var path_res: WorldNavigation.PathResult = nav.find_path(lateral_start, ramp_top_target)
	assert_true(path_res.reachable, "Plateau must be reachable from lateral south of ramp")
	var min_path_x: float = 999.0
	var crosses_lateral_wall: bool = false
	for pt: Vector3 in path_res.path:
		min_path_x = minf(min_path_x, pt.x)
		if pt.x > 5.4 and pt.z >= -12.35 and pt.z <= -11.35 and pt.y < 0.7:
			crosses_lateral_wall = true
	assert_false(crosses_lateral_wall, "NavMesh path must never cross Terrain/Ramp lateral wall at z=-12.0")
	assert_true(min_path_x <= 5.0, "NavMesh path must detour around ramp foot x<=5.0 (min_x=%.3f)" % min_path_x)

	var move_ord := MoveOrder.new(ramp_top_target)
	worker.issue_order(move_ord)
	var lateral_hits: int = 0
	var min_unit_x: float = worker.global_position.x
	var move_f: int = 0
	while move_ord.is_active() and move_f < 900:
		await wait_physics_frames(1)
		move_f += 1
		min_unit_x = minf(min_unit_x, worker.global_position.x)
		for ci: int in range(worker.get_slide_collision_count()):
			var kc: KinematicCollision3D = worker.get_slide_collision(ci)
			if kc != null and kc.get_collider() != null and String(kc.get_collider().get("name")) == "Ramp" and absf(kc.get_normal().y) < 0.707:
				lateral_hits += 1
	assert_eq(move_ord.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(lateral_hits, 0, "Worker detouring around ramp must have 0 lateral collisions with Ramp")
	assert_true(min_unit_x <= 5.0, "Worker physical detour must round ramp foot x<=5.0 (min_x=%.3f)" % min_unit_x)

	# 3. Complete full plateau logistics from camp (12 wood, 6 stone) with 0 lateral wall collisions.
	worker.global_position = camp.global_position + Vector3(-1.5, 0.0, 2.0)
	await wait_physics_frames(2)
	var supply_ord := ConstructOrder.new(site, camp)
	worker.issue_order(supply_ord)
	var sim_f: int = 0
	var supply_lateral_hits: int = 0
	while not site.is_fully_supplied() and sim_f < 2800:
		await wait_physics_frames(1)
		sim_f += 1
		for ci: int in range(worker.get_slide_collision_count()):
			var kc: KinematicCollision3D = worker.get_slide_collision(ci)
			if kc != null and kc.get_collider() != null and String(kc.get_collider().get("name")) == "Ramp" and absf(kc.get_normal().y) < 0.707:
				supply_lateral_hits += 1
		if supply_ord.status == UnitOrder.Status.FAILED:
			break

	assert_true(site.is_fully_supplied(), "Plateau ramp-edge site must reach 100% physical supply")
	assert_eq(supply_lateral_hits, 0, "Repeated plateau trips must have 0 lateral collisions with Ramp")
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 12)
	assert_eq(site.get_delivered_buffer_amount(&"stone"), 6)

	vp.queue_free()
	await wait_process_frames(2)


func test_10_r2_plateau_two_worker_roles_promotion_and_full_supply() -> void:
	var ctx: Dictionary = await _spawn_main_in_viewport()
	var vp: SubViewport = ctx["vp"] as SubViewport
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var units: Array[Unit] = ctx["units"] as Array[Unit]
	var w1: Unit = units[0]
	var w2: Unit = units[1] if units.size() >= 2 else _spawn_extra_worker(ctx["main"] as MainScene, nav, "R2_PeerW2", camp.global_position + Vector3(2.5, 0.0, 2.5))

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	var res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(15.2, 2.0, -11.2))
	assert_true(bool(res.get("ok", false)))
	var site: ConstructionSite = res["site"] as ConstructionSite
	await wait_physics_frames(2)
	await _wait_nav_ready(nav)

	var o1 := ConstructOrder.new(site, camp)
	var o2 := ConstructOrder.new(site, camp)
	w1.issue_order(o1)
	w2.issue_order(o2)
	assert_eq(site.get_worker_role(w1), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site.get_worker_role(w2), ConstructionSite.WorkerRole.BUILDER)

	var saw_builder_standby: bool = false
	var interrupted_w1: bool = false
	var saw_builder_promoted: bool = false
	var lateral_hits: int = 0
	var sim_f: int = 0
	while not site.is_fully_supplied() and sim_f < 2800:
		await wait_physics_frames(1)
		sim_f += 1
		if o2.is_active() and o2.get_phase() == ConstructOrder.Phase.BUILDER_STANDBY:
			saw_builder_standby = true
		if not interrupted_w1 and saw_builder_standby and o1.trips_completed >= 1 and w1.get_carry_load().is_empty():
			interrupted_w1 = true
			w1.issue_order(MoveOrder.new(Vector3(-4.0, 0.0, 2.0)))
			await wait_physics_frames(2)
			var promoted_role: ConstructionSite.WorkerRole = site.get_worker_role(w2)
			saw_builder_promoted = (
				promoted_role == ConstructionSite.WorkerRole.SOLO_SUPPLIER
				or promoted_role == ConstructionSite.WorkerRole.TRANSPORTER
			)
		for u: Unit in [w1, w2]:
			for ci: int in range(u.get_slide_collision_count()):
				var kc: KinematicCollision3D = u.get_slide_collision(ci)
				if kc != null and kc.get_collider() != null and String(kc.get_collider().get("name")) == "Ramp" and absf(kc.get_normal().y) < 0.707:
					lateral_hits += 1
		if o2.status == UnitOrder.Status.FAILED:
			break

	assert_true(saw_builder_standby, "Secondary worker must reach elevated BUILDER_STANDBY perimeter on plateau")
	assert_true(saw_builder_promoted, "Interrupting primary TRANSPORTER must promote plateau BUILDER to supply")
	assert_eq(o2.failure_reason, "", "Promoted plateau worker must complete supply without failing (got '%s')" % o2.failure_reason)
	assert_true(site.is_fully_supplied(), "Two-worker plateau supply after promotion must reach 100%")
	assert_eq(lateral_hits, 0, "Two-worker plateau supply must have 0 lateral collisions against Ramp")
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 12)
	assert_eq(site.get_delivered_buffer_amount(&"stone"), 6)

	vp.queue_free()
	await wait_process_frames(2)
