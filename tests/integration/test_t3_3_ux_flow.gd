class_name TestT33UxFlow
extends TestCase
## Integration tests for T3.3-UX dynamic resolution switching, temporary C4 workers,
## D9 4-worker cap rejection, and safe cleanup without losing resources.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")

var _scene: MainScene = null


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		_scene = null
	await get_tree().process_frame


func _boot_main_scene() -> Dictionary:
	_scene = MAIN_SCENE.instantiate() as MainScene
	_scene.use_provenance_economy = false
	get_tree().root.add_child(_scene)
	await get_tree().process_frame
	await get_tree().physics_frame

	var test_map: TestMap = _scene.get_node("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation()
	var deadline_msec: int = Time.get_ticks_msec() + 8000
	while not nav.is_navigation_ready() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame

	var camp: CampStorageZone = test_map.get_camp_storage_zone()
	var inventory: SettlementInventory = _scene.get_node("CommandController").get_settlement_inventory()
	var units_root: Node3D = _scene.get_node("Units") as Node3D
	var overlay: PlacementTestOverlay = _scene.get_node("UiLayer/PlacementTestOverlay") as PlacementTestOverlay
	var construction_mgr: ConstructionManager = _scene.get_node("ConstructionManager") as ConstructionManager
	var selection_mgr: SelectionManager = _scene.get_node("SelectionManager") as SelectionManager
	var command_ctrl: CommandController = _scene.get_node("CommandController") as CommandController
	var camera_rig: RtsCameraRig = _scene.get_node("RtsCameraRig") as RtsCameraRig
	return {
		"nav": nav,
		"camp": camp,
		"inventory": inventory,
		"units_root": units_root,
		"overlay": overlay,
		"construction_mgr": construction_mgr,
		"selection_mgr": selection_mgr,
		"command_ctrl": command_ctrl,
		"camera_rig": camera_rig,
		"leader_a": units_root.get_node("LeaderA") as Unit,
		"leader_b": units_root.get_node("LeaderB") as Unit,
	}


func _seed_shelter_stock(ctx: Dictionary) -> void:
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var gpm: GroundPileManager = _scene._ground_pile_manager
	gpm.deposit(&"wood", 16)
	gpm.deposit(&"stone", 8)
	assert_true(inventory.get_available_amount(&"wood") >= 12, "Seeded wood >= 12")
	assert_true(inventory.get_available_amount(&"stone") >= 6, "Seeded stone >= 6")


func _spawn_founding_house_test_unit(ctx: Dictionary, node_name: String, id: StringName, pos: Vector3) -> Unit:
	var units_root: Node3D = ctx["units_root"] as Node3D
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var unit_scene: PackedScene = preload("res://src/units/unit.tscn")
	var def := CharacterDefinition.new()
	def.character_id = id
	def.display_name = node_name
	def.house_affiliation = CharacterDefinition.HouseAffiliation.FOUNDING_HOUSE
	def.founding_house_origin = CharacterDefinition.FoundingHouseOrigin.DIRECT_DESCENDANT
	def.age_stage = CharacterDefinition.AgeStage.ADULT
	var u: Unit = unit_scene.instantiate() as Unit
	u.name = node_name
	u.definition = def
	u.position = pos
	units_root.add_child(u)
	u.set_world_navigation(nav)
	return u


func test_01_resolution_toggle_preserves_scene_sites_backpacks_and_camera() -> void:
	var ctx: Dictionary = await _boot_main_scene()
	_seed_shelter_stock(ctx)
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var construction_mgr: ConstructionManager = ctx["construction_mgr"] as ConstructionManager
	var camera_rig: RtsCameraRig = ctx["camera_rig"] as RtsCameraRig
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var selection_mgr: SelectionManager = ctx["selection_mgr"] as SelectionManager

	var site_res: Dictionary = construction_mgr.try_create_site_from_placement(
		MainScene.SHELTER_BASIC_DEFINITION,
		Vector3(-6.0, 0.0, 2.0)
	)
	assert_true(bool(site_res.get("ok", false)), "Site created before resolution toggle")
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	assert_true(leader_a.get_carry_load().add_units(MainScene.WOOD_DEFINITION, 5), "Seed LeaderA backpack")
	selection_mgr.select_single(leader_a)
	camera_rig.set_focus_position(Vector2(-3.0, 1.5))
	camera_rig.zoom_by(-1.0)
	await get_tree().process_frame

	var scene_id: int = _scene.get_instance_id()
	var site_id: int = site.get_instance_id()
	var cam_focus_before: Vector2 = camera_rig.get_focus_position()
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var reserved_wood_before: int = inv.get_reserved_amount(&"wood")

	var r1: Dictionary = overlay.apply_test_resolution(DisplayResolutionService.PRESET_1920X1080)
	assert_true(bool(r1.get("ok", false)), "First resolution toggle succeeded")
	await get_tree().process_frame

	var r2: Dictionary = overlay.apply_test_resolution(DisplayResolutionService.PRESET_1280X720)
	assert_true(bool(r2.get("ok", false)), "Second resolution toggle succeeded")
	await get_tree().process_frame

	assert_eq(_scene.get_instance_id(), scene_id, "Scene must not reload on resolution change")
	assert_true(is_instance_valid(site) and site.get_instance_id() == site_id, "Site must persist across resolution changes")
	assert_eq(inv.get_reserved_amount(&"wood"), reserved_wood_before, "Reserved wood must persist")
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), 5, "LeaderA backpack must persist")
	assert_true(is_instance_valid(leader_b), "LeaderB must persist")
	assert_eq(selection_mgr.get_selected_units(), [leader_a], "Selection must persist")
	assert_true(camera_rig.get_focus_position().distance_to(cam_focus_before) < 0.05, "Camera focus must persist")
	assert_true(overlay.get_resolution_status_text().begins_with("Atual:"), "Resolution label must update")


func test_02_temporary_workers_spawn_no_duplicates_and_safe_removal() -> void:
	var ctx: Dictionary = await _boot_main_scene()
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var units_root: Node3D = ctx["units_root"] as Node3D
	var selection_mgr: SelectionManager = ctx["selection_mgr"] as SelectionManager
	var ctrl: TemporaryTestWorkersController = overlay.get_temporary_workers_controller()
	assert_not_null(ctrl, "TemporaryTestWorkersController must be wired in MainScene")

	assert_eq(units_root.get_child_count(), 2, "Starts with LeaderA and LeaderB only")
	overlay.get_add_c4_workers_button().pressed.emit()
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 4, "Adds Worker3 and Worker4")

	var dup_res: Dictionary = ctrl.spawn_temporary_workers()
	assert_false(bool(dup_res.get("ok", false)), "Repeated spawn must be rejected")
	assert_eq(str(dup_res.get("reason", "")), "already_exists", "Reason must be already_exists")
	assert_eq(units_root.get_child_count(), 4, "No duplicate workers created")

	var w3: Unit = units_root.get_node("Worker3") as Unit
	var w4: Unit = units_root.get_node("Worker4") as Unit
	assert_not_null(w3, "Worker3 exists")
	assert_not_null(w4, "Worker4 exists")

	selection_mgr.select_single(w3)
	selection_mgr.add_unit(w4)
	assert_eq(selection_mgr.get_selection_count(), 2, "Temporary workers can be selected")

	assert_true(w3.get_carry_load().add_units(MainScene.WOOD_DEFINITION, 3), "Add cargo to Worker3 backpack")
	var blocked_res: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_false(bool(blocked_res.get("ok", false)), "Removal must be blocked while Worker3 carries cargo")
	assert_eq(str(blocked_res.get("reason", "")), "cargo_in_backpack", "Block reason must report backpack cargo")
	assert_eq(units_root.get_child_count(), 4, "Workers preserved when removal is blocked")
	assert_eq(w3.get_carry_load().get_amount(&"wood"), 3, "Backpack cargo preserved")

	assert_eq(w3.get_carry_load().remove_units(&"wood", 3), 3, "Unload Worker3 backpack cleanly")
	overlay.get_remove_c4_workers_button().pressed.emit()
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 2, "Only LeaderA and LeaderB remain after safe removal")


func test_03_c4_three_workers_fourth_rejected_and_promotion_on_interrupt() -> void:
	var ctx: Dictionary = await _boot_main_scene()
	_seed_shelter_stock(ctx)
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay
	var units_root: Node3D = ctx["units_root"] as Node3D
	var construction_mgr: ConstructionManager = ctx["construction_mgr"] as ConstructionManager
	var command_ctrl: CommandController = ctx["command_ctrl"] as CommandController
	var selection_mgr: SelectionManager = ctx["selection_mgr"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	overlay.get_add_c4_workers_button().pressed.emit()
	await get_tree().process_frame
	var w3: Unit = units_root.get_node("Worker3") as Unit
	var w4: Unit = units_root.get_node("Worker4") as Unit

	var site_res: Dictionary = construction_mgr.try_create_site_from_placement(
		MainScene.SHELTER_BASIC_DEFINITION,
		Vector3(-6.0, 0.0, 2.0)
	)
	assert_true(bool(site_res.get("ok", false)), "Site created for C4 test")
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	overlay.set_inspected_site(site)

	# R-03B B1 (B0-Q03 B): Worker3/Worker4 are COMMUNITY and do not receive personal site commands.
	assert_eq(w3.get_definition().house_affiliation, CharacterDefinition.HouseAffiliation.COMMUNITY)
	assert_eq(w4.get_definition().house_affiliation, CharacterDefinition.HouseAffiliation.COMMUNITY)
	assert_false(command_ctrl.command_units_to_site(site, [w3]), "COMMUNITY Worker3 must reject personal site command")
	assert_eq(command_ctrl.get_last_command_reason(), UnitControlPermissions.REASON_PERSONAL_CONTROL_DENIED)

	# Local Founding House adult units to exercise D9 3-worker cap, 4th no_worker_slot rejection, and promotion.
	var founder_c: Unit = _spawn_founding_house_test_unit(ctx, "FounderC", &"founder_c_c4", Vector3(-3.0, 0.0, 1.5))
	var founder_d: Unit = _spawn_founding_house_test_unit(ctx, "FounderD", &"founder_d_c4", Vector3(-2.0, 0.0, 3.0))
	await get_tree().process_frame

	# C4-A: 1 worker
	assert_true(command_ctrl.command_units_to_site(site, [leader_a]), "C4-A LeaderA assigned")
	await get_tree().physics_frame
	var entries_1: Array[Dictionary] = site.get_assigned_worker_entries()
	assert_eq(entries_1.size(), 1, "C4-A has 1 worker")

	# C4-B: 2 workers
	assert_true(command_ctrl.command_units_to_site(site, [leader_b]), "C4-B LeaderB assigned")
	await get_tree().physics_frame
	var entries_2: Array[Dictionary] = site.get_assigned_worker_entries()
	assert_eq(entries_2.size(), 2, "C4-B has 2 workers")

	# C4-C: 3 workers (1 transporter + 2 builders)
	assert_true(command_ctrl.command_units_to_site(site, [founder_c]), "C4-C 3rd Founding House worker assigned")
	await get_tree().physics_frame
	var entries_3: Array[Dictionary] = site.get_assigned_worker_entries()
	assert_eq(entries_3.size(), 3, "C4-C has 3 workers")
	var t_count: int = 0
	var b_count: int = 0
	for entry: Dictionary in entries_3:
		if int(entry["role"]) == int(ConstructionSite.WorkerRole.TRANSPORTER):
			t_count += 1
		elif int(entry["role"]) == int(ConstructionSite.WorkerRole.BUILDER):
			b_count += 1
	assert_eq(t_count, 1, "C4-C has 1 transporter")
	assert_eq(b_count, 2, "C4-C has 2 builders")

	# C4-D: 4th worker rejected + panel displays clear reason
	var reject_ok: bool = command_ctrl.command_units_to_site(site, [founder_d])
	assert_false(reject_ok, "C4-D 4th worker must be rejected")
	assert_eq(command_ctrl.get_last_command_reason(), ConstructOrder.REASON_NO_WORKER_SLOT, "Reason is no_worker_slot")
	assert_eq(site.get_assigned_worker_entries().size(), 3, "Previous 3 workers remain assigned")
	assert_true(overlay.get_status_detail_text().contains("no_worker_slot"), "Overlay status explains no_worker_slot rejection")

	# C4-E: interrupt current transporter -> one builder promotes -> full supply completes without T3.4
	var active_transporter: Unit = null
	for entry: Dictionary in site.get_assigned_worker_entries():
		if int(entry["role"]) == int(ConstructionSite.WorkerRole.TRANSPORTER):
			active_transporter = entry["unit"] as Unit
			break
	assert_not_null(active_transporter, "Active transporter identified before interrupt")

	selection_mgr.select_single(active_transporter)
	var move_pick := PickResult.from_ground(Vector3(-14.0, 0.0, 8.0), Vector3.UP)
	assert_true(command_ctrl.command_at(move_pick), "Interrupt transporter with move order")

	for _i: int in range(6):
		await get_tree().physics_frame

	var promoted_entries: Array[Dictionary] = site.get_assigned_worker_entries()
	assert_eq(promoted_entries.size(), 2, "Remaining 2 workers stay assigned after promotion")
	var promoted_t: int = 0
	var promoted_b: int = 0
	for entry: Dictionary in promoted_entries:
		if int(entry["role"]) == int(ConstructionSite.WorkerRole.TRANSPORTER):
			promoted_t += 1
		elif int(entry["role"]) == int(ConstructionSite.WorkerRole.BUILDER):
			promoted_b += 1
	assert_eq(promoted_t, 1, "One builder promoted to transporter")
	assert_eq(promoted_b, 1, "Other builder stays builder")

	var deadline_msec: int = Time.get_ticks_msec() + 18000
	while not site.is_fully_supplied() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().physics_frame

	assert_true(site.is_fully_supplied(), "C4-E promoted builder completes full supply")
	assert_eq(site.get_total_received_amount(&"wood"), 12, "Exact 12 wood received (buffer + consumed)")
	assert_eq(site.get_delivered_buffer_amount(&"wood") + site.get_consumed_amount(&"wood"), 12)
	assert_eq(site.get_total_received_amount(&"stone"), 6, "Exact 6 stone received (buffer + consumed)")
	assert_eq(site.get_delivered_buffer_amount(&"stone") + site.get_consumed_amount(&"stone"), 6)
	var snap: Dictionary = site.get_status_snapshot()
	assert_true(bool(snap.get("is_fully_supplied", false)), "Snapshot confirms 100% material supply received")
	assert_eq(_scene.get_node("ConstructionSites").get_child_count(), 1, "Site remains ConstructionSite without T3.4.4 transmutation")
