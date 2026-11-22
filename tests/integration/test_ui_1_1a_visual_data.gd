extends TestCase
## Integration tests for UI-1.1A D2.2 visual foundation inside MainScene:
## - Real physical gathering -> no premature credit -> updates on camp pile delivery
## - Dual-mode without duplicate stockpile HUD (Safeguard 1)
## - Legacy mode default intact in main.tscn
## - Inert controls truly non-interactive & external pause preserved (Safeguards 2 & 3)
## - Clean layout without overlap or clipping at 1280x720 and 1920x1080
## - Clean teardown on scene exit.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://tests/visual/ui_1_d2_2_sandbox.tscn")
const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 1800


func after_each() -> void:
	if get_tree() != null:
		get_tree().paused = false
	Engine.time_scale = 1.0


func _wait_nav_ready(main_root: MainScene) -> void:
	var test_map: TestMap = main_root.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var frames: int = 0
	while nav != null and not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	await wait_process_frames(2)
	await wait_physics_frames(2)


func _assert_all_controls_mouse_ignore(node: Control) -> void:
	assert_eq(node.mouse_filter, Control.MOUSE_FILTER_IGNORE, "UI-1.1A node must remain MOUSE_FILTER_IGNORE: %s" % node.name)
	for child: Node in node.get_children():
		if child is Control:
			_assert_all_controls_mouse_ignore(child as Control)


func test_legacy_mode_default_is_completely_intact() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	main_root.use_provenance_economy = false
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	assert_false(main_root.use_d2_2_hud, "main.tscn default must keep use_d2_2_hud = false")
	assert_null(main_root.get_d2_hud_root(), "Legacy mode must not instantiate D2HudRoot")
	var legacy_stockpile: SettlementStockpilePanel = main_root.get_resource_hud().get_stockpile_panel()
	assert_true(legacy_stockpile.visible, "Legacy stockpile panel must remain visible in default mode")
	assert_true(legacy_stockpile.is_bound_to_inventory(main_root.get_settlement_inventory()), "Legacy stockpile must remain bound")

	vp.queue_free()
	await wait_process_frames(2)


func test_dual_mode_hides_duplicate_stockpile_and_preserves_non_migrated_ui() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_test_child(vp)

	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	main_root.use_provenance_economy = false
	vp.add_child(main_root)
	await _wait_nav_ready(main_root)

	assert_true(main_root.use_d2_2_hud, "Sandbox scene must enable use_d2_2_hud")
	var d2: D2HudRoot = main_root.get_d2_hud_root()
	assert_not_null(d2, "D2HudRoot must be instantiated when use_d2_2_hud is true")
	assert_true(d2.visible)

	# Safeguard 1: zero duplicate stockpile HUD
	var legacy_stockpile: SettlementStockpilePanel = main_root.get_resource_hud().get_stockpile_panel()
	assert_false(legacy_stockpile.visible, "Legacy stockpile panel must be hidden in D2.2 mode to prevent duplicate HUD")
	assert_false(legacy_stockpile.is_bound_to_inventory(main_root.get_settlement_inventory()), "Hidden legacy stockpile must be unbound")

	# Non-migrated functional UIs stay operational
	var leader: Unit = main_root.get_units()[0]
	main_root.get_selection_manager().select_single(leader)
	await wait_process_frames(1)
	assert_true(main_root.get_resource_hud().get_selected_unit_panel().visible, "Non-migrated SelectedUnitPanel must still work")
	assert_not_null(main_root.get_node_or_null("UiLayer/ConstructionHud"), "ConstructionHud must remain available")
	assert_not_null(main_root.get_node_or_null("UiLayer/BuildingInspectorPanel"), "BuildingInspectorPanel must remain available")

	# Safeguard 2: all UI-1.1A controls strictly non-interactive
	_assert_all_controls_mouse_ignore(d2)
	assert_false(d2.get_top_plaque_view().has_interactive_buttons(), "Top plaque must have zero interactive buttons in UI-1.1A")

	# Safeguard 3: external pause & time_scale untouched
	assert_false(get_tree().paused)
	assert_true(absf(Engine.time_scale - 1.0) <= 0.001)
	get_tree().paused = true
	d2.refresh_all()
	assert_true(get_tree().paused, "UI-1.1A must never clear or alter an external pause")
	get_tree().paused = false

	# Layout bounds & no overlap at both 1280x720 and 1920x1080
	var debug_panel: Control = main_root.get_node("UiLayer/DebugOverlay/Panel") as Control
	var unit_panel: Control = main_root.get_resource_hud().get_selected_unit_panel()
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		vp.size = res
		await wait_process_frames(3)
		var vp_rect := Rect2(Vector2.ZERO, Vector2(res))
		var rocks_rect: Rect2 = d2.get_resource_rocks_view().get_content_bounds()
		var plaque_rect: Rect2 = d2.get_top_plaque_view().get_content_bounds()
		assert_true(vp_rect.encloses(rocks_rect), "Resource rocks must stay inside viewport %s" % str(res))
		assert_true(vp_rect.encloses(plaque_rect), "Top plaque must stay inside viewport %s" % str(res))
		assert_false(rocks_rect.intersects(plaque_rect), "Rocks and plaque must not intersect at %s" % str(res))
		assert_false(rocks_rect.intersects(unit_panel.get_global_rect()), "Rocks and unit panel must not intersect at %s" % str(res))
		assert_false(rocks_rect.intersects(debug_panel.get_global_rect()), "Rocks and DebugOverlay must not intersect at %s" % str(res))

	# Clean teardown disconnects signals
	var inv: SettlementInventory = main_root.get_settlement_inventory()
	var rocks_ref: D2ResourceRocksView = d2.get_resource_rocks_view()
	var plaque_ref: D2TopPlaqueView = d2.get_top_plaque_view()
	assert_true(rocks_ref.is_bound_to_inventory(inv), "Rocks must be bound before scene exit")
	assert_true(plaque_ref.is_bound_to_inventory(inv), "Plaque must be bound before scene exit")
	vp.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(rocks_ref), "Rocks node must be freed on viewport teardown")
	assert_false(is_instance_valid(plaque_ref), "Plaque node must be freed on viewport teardown")
	assert_eq(inv.inventory_changed.get_connections().size(), 0, "All inventory_changed listeners must disconnect on scene exit")


func test_real_physical_gathering_updates_rocks_only_after_delivery() -> void:
	var main_root: MainScene = SANDBOX_SCENE.instantiate() as MainScene
	main_root.use_provenance_economy = false
	add_test_child(main_root)
	await _wait_nav_ready(main_root)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	# Accelerate source & unit for deterministic test speed
	var test_map: TestMap = main_root.get_test_map()
	var target_src: ResourceSource = null
	for src: ResourceSource in test_map.get_resource_sources():
		src.set_gather_cycle_timings(0.08, 0.0)
		src.felling_duration_sec = minf(src.felling_duration_sec, 0.06)
		if src.get_resource_id() == &"wood" and target_src == null:
			target_src = src
	assert_not_null(target_src, "TestMap must contain a wood ResourceSource")

	var leader: Unit = main_root.get_units()[0]
	var fast_def: CharacterDefinition = leader.get_definition().duplicate() as CharacterDefinition
	fast_def.move_speed = 8.0
	fast_def.work_approach_speed = 8.0
	fast_def.max_load_speed_multiplier = 1.0
	leader.apply_definition(fast_def)

	var d2: D2HudRoot = main_root.get_d2_hud_root()
	var rocks: D2ResourceRocksView = d2.get_resource_rocks_view()
	var plaque: D2TopPlaqueView = d2.get_top_plaque_view()
	assert_eq(rocks.get_displayed_amount(&"wood"), 0, "Wood rock must start at 0")
	assert_eq(plaque.get_exposure_tone(), HudFormatter.ExposureTone.EXPOSED_IDLE)

	# Issue real gather command
	main_root.get_selection_manager().select_single(leader)
	main_root.get_command_controller().command_at(PickResult.from_resource_source(target_src, target_src.global_position, Vector3.UP))

	# Wait until unit has extracted wood into carry load BEFORE physical delivery
	var saw_carrying_zero_stockpile: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if leader.get_carry_load().get_amount(&"wood") > 0 and main_root.get_settlement_inventory().get_amount(&"wood") == 0:
			assert_eq(rocks.get_displayed_amount(&"wood"), 0, "Wood rock must NOT credit before physical delivery")
			saw_carrying_zero_stockpile = true
			break
	assert_true(saw_carrying_zero_stockpile, "Unit must carry extracted wood before physical delivery")

	# Wait until physical delivery completes
	var delivered: bool = false
	while frames < MAX_CYCLE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		if main_root.get_settlement_inventory().get_amount(&"wood") > 0:
			delivered = true
			break
	await wait_process_frames(2)
	assert_true(delivered, "Unit must physically deliver wood to CampStorageZone")
	var real_wood: int = main_root.get_settlement_inventory().get_amount(&"wood")
	assert_eq(rocks.get_displayed_amount(&"wood"), real_wood, "Wood rock must match SettlementInventory exactly after delivery")
	assert_eq(rocks.get_displayed_text(&"wood"), "%d" % real_wood)
	assert_eq(plaque.get_exposure_tone(), HudFormatter.ExposureTone.EXPOSED_ACTIVE, "Plaque exposure must switch to active decay after wood delivery")

	main_root.queue_free()
	await wait_process_frames(2)
