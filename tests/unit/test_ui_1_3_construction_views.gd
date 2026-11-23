extends TestCase
## Unit tests for UI-1.3 D2.2 construction views:
## - Atlas regions & polygonal hitboxes for D2ActionSlabsView, D2ConstructionDockView, D2PlacementStatusBar
## - Truthful BuildingDefinition cost/metadata binding (zero hardcoded numbers, zero premature T3.7 claims)
## - Honest inertness of Tarefas [T] and Linhagem [H]
## - D2PlacementStatusBar state machine: HIDDEN / UNEVALUATED / VALID / INVALID / CONFIRMING (never fake LOCAL VÁLIDO)
## - Idempotent configure(), unbind(), zero polling, and responsive layout bounds at 1280x720 and 1920x1080.

const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")


func test_01_action_slabs_and_maquette_dock_polygons_costs_and_honesty() -> void:
	var atlas := D2AtlasLibrary.new()
	assert_true(atlas.load_all(), "D2AtlasLibrary must load cleanly")
	assert_true(atlas.validate_manifest_bounds(), "All 17 regions must lie inside 1024x1024 atlas")
	for key: String in ["slab_maquetes_alab", "slab_cmd_basalt", "maquette_shelter", "maquette_depot_sel", "build_valid_bar", "ico_tasks", "ico_lineage"]:
		assert_not_null(atlas.get_region_texture(key), "Atlas region must exist: %s" % key)

	var theme_factory := D2ThemeFactory.new()
	var root := Control.new()
	root.size = Vector2(1920.0, 1080.0)
	add_test_child(root)

	var slabs := D2ActionSlabsView.new()
	root.add_child(slabs)
	slabs.setup_visuals(atlas, theme_factory, Vector2(1920.0, 1080.0), 1.0)

	# Process mode & zero polling
	assert_eq(slabs.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_false(slabs.is_processing())
	assert_false(slabs.is_physics_processing())
	assert_true(slabs.has_inert_unimplemented_controls(), "Tarefas [T] and Linhagem [H] must remain honestly inert")

	# Polygonal hitboxes on alabaster & basalt slabs (interior true, shadow pad corner false)
	var m_slab: D2PolygonalSlab = slabs.get_maquettes_slab()
	var c_slab: D2PolygonalSlab = slabs.get_commands_slab()
	assert_true(m_slab.contains_local_point(m_slab.size * 0.5), "Maquetes slab center must hit")
	assert_false(m_slab.contains_local_point(Vector2(2.0, 2.0)), "Maquetes 10 px shadow pad must pass through")
	assert_true(c_slab.contains_local_point(c_slab.size * 0.5), "Commands slab center must hit")
	assert_false(c_slab.contains_local_point(Vector2(2.0, 2.0)), "Commands 10 px shadow pad must pass through")

	# Active state lifts Maquetes slab upward without colliding with basalt slab
	var y_closed: float = slabs.get_maquettes_content_rect().position.y
	slabs.set_maquettes_open(true)
	var y_open: float = slabs.get_maquettes_content_rect().position.y
	assert_lt(y_open, y_closed - 4.0, "Active Maquetes slab must lift upward when dock is open")
	assert_false(slabs.get_maquettes_content_rect().intersects(slabs.get_commands_content_rect()), "Action slabs must never overlap")
	slabs.set_maquettes_open(false)

	# D2ConstructionDockView with real BuildingDefinitions
	var controller := PlacementController.new()
	add_test_child(controller)
	var dock := D2ConstructionDockView.new()
	root.add_child(dock)
	dock.setup_visuals(atlas, theme_factory, Vector2(1920.0, 1080.0), 1.0)
	dock.configure(controller, [SHELTER_DEF, DEPOT_DEF])

	assert_eq(dock.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_false(dock.is_processing())
	assert_false(dock.is_dock_open(), "Dock must start closed")
	assert_false(dock.visible)
	assert_eq(dock.get_card_count(), 2)
	assert_eq(dock.get_card_title_text(0), "Abrigo Básico")
	assert_eq(dock.get_card_title_text(1), "Depósito Rústico")
	assert_eq(dock.get_card_cost_text(0), "12 Mad · 6 Ped")
	assert_eq(dock.get_card_cost_text(1), "18 Mad · 10 Ped")

	# Honesty check: Depot card must NOT prematurely advertise unimplemented T3.7 protected storage
	var depot_sub: String = dock.get_card_subtitle_text(1)
	assert_false(depot_sub.contains("Protege"), "Depot card must NOT falsely advertise T3.7 protected storage")
	assert_false(depot_sub.contains("50/50/30"), "Depot card must NOT falsely advertise T3.7 protected storage capacities")
	assert_true(depot_sub.contains("5×4 m"), "Depot subtitle must reflect real BuildingDefinition footprint")

	# Dynamic BuildingDefinition cost proof (zero hardcoded costs!)
	var custom_def: BuildingDefinition = SHELTER_DEF.duplicate() as BuildingDefinition
	custom_def.definition_id = &"custom_hut"
	custom_def.display_name = "Cabana Teste"
	custom_def.costs = {&"wood": 7, &"stone": 3}
	custom_def.footprint_size = Vector2(3.0, 3.0)
	custom_def.build_work_required_sec = 18.0
	dock.configure(controller, [custom_def, DEPOT_DEF])
	assert_eq(dock.get_card_title_text(0), "Cabana Teste")
	assert_eq(dock.get_card_cost_text(0), "7 Mad · 3 Ped", "Costs MUST come dynamically from BuildingDefinition.costs")
	assert_true(dock.get_card_subtitle_text(0).contains("3×3 m"))

	# Restore canonical definitions & test card polygonal hitboxes + layout at 1280x720 and 1920x1080
	dock.configure(controller, [SHELTER_DEF, DEPOT_DEF])
	dock.set_dock_open(true)
	assert_true(dock.visible)
	for res: Vector2 in [Vector2(1920.0, 1080.0), Vector2(1280.0, 720.0)]:
		var scale_f: float = 1.0 if res.x >= 1900.0 else (res.x / 1920.0) * 1.22
		slabs.apply_layout(res, scale_f)
		dock.apply_layout(res, scale_f)
		var vp_rect := Rect2(Vector2.ZERO, res)
		assert_true(vp_rect.encloses(slabs.get_content_bounds()), "Action slabs must fit inside %s" % str(res))
		assert_true(vp_rect.encloses(dock.get_content_bounds()), "Maquette dock must fit inside %s" % str(res))
		assert_false(dock.get_card_content_rect(0).intersects(dock.get_card_content_rect(1)), "Maquettes must not overlap at %s" % str(res))
		assert_false(dock.get_content_bounds().intersects(slabs.get_content_bounds()), "Maquette dock must not overlap action slabs at %s" % str(res))
		var c0_slab: D2PolygonalSlab = dock.get_card_slab(0)
		assert_true(c0_slab.contains_local_point(c0_slab.size * 0.5))
		assert_false(c0_slab.contains_local_point(Vector2(2.0, 2.0)))

	# Selected maquette elevates and switches to maquette_depot_sel geometry without overlapping sibling
	assert_true(dock.select_building_index(1))
	assert_false(dock.is_dock_open(), "Selecting a maquette must deterministically close the dock")
	assert_true(controller.is_placement_active())
	assert_eq(controller.get_active_definition().definition_id, &"storage_depot")
	dock.set_dock_open(true)
	assert_true(dock.is_card_selected(1), "Active Depot card must be marked selected when dock reopens")
	assert_false(dock.is_card_selected(0))
	assert_false(dock.get_card_content_rect(0).intersects(dock.get_card_content_rect(1)), "Raised selected maquette must not overlap sibling")

	# Clean idempotent unbind disconnects all controller signals
	dock.unbind()
	dock.unbind()
	assert_false(dock.is_dock_open())
	assert_false(dock.is_bound_to_controller(controller))
	assert_eq(controller.placement_started.get_connections().size(), 0)
	assert_eq(controller.placement_cancelled.get_connections().size(), 0)
	assert_eq(controller.placement_confirmed.get_connections().size(), 0)

	controller.cancel_placement()
	controller.queue_free()
	root.queue_free()


func test_02_placement_status_bar_truthful_states_and_zero_fake_valid() -> void:
	var atlas := D2AtlasLibrary.new()
	assert_true(atlas.load_all())
	var theme_factory := D2ThemeFactory.new()

	var root := Control.new()
	root.size = Vector2(1920.0, 1080.0)
	add_test_child(root)

	var controller := PlacementController.new()
	add_test_child(controller)

	var bar := D2PlacementStatusBar.new()
	root.add_child(bar)
	bar.setup_visuals(atlas, theme_factory, Vector2(1920.0, 1080.0), 1.0)
	bar.configure(controller)

	assert_eq(bar.process_mode, Node.PROCESS_MODE_PAUSABLE)
	assert_false(bar.is_processing())
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.HIDDEN)
	assert_false(bar.visible)

	# 1. Start placement without camera/pointer -> MUST be UNEVALUATED, NEVER LOCAL VÁLIDO!
	assert_true(controller.start_placement(SHELTER_DEF))
	assert_true(bar.visible)
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.UNEVALUATED, "Fresh placement without hover result must be UNEVALUATED")
	assert_false(bar.get_displayed_text().contains("LOCAL VÁLIDO"), "Must NEVER fabricate LOCAL VÁLIDO before real validation")
	assert_true(bar.get_displayed_text().contains("Abrigo Básico"))

	# 2. Valid hover signal -> VALID
	controller.hover_state_changed.emit(true, "", Vector3(5.0, 0.0, 5.0))
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.VALID)
	assert_true(bar.get_displayed_text().contains("LOCAL VÁLIDO"))
	assert_true(bar.get_displayed_text().contains("4×4 m"))

	# 3. Invalid hover signal -> INVALID with concrete reason text
	var camp_reason: String = "Posição inválida: área reservada para pilhas do acampamento."
	controller.hover_state_changed.emit(false, camp_reason, Vector3.ZERO)
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.INVALID)
	assert_eq(bar.get_badge_text(), "INVÁLIDO")
	assert_true(bar.get_displayed_text().contains(camp_reason))
	assert_false(bar.get_displayed_text().contains("LOCAL VÁLIDO"))

	# 4. Async confirmation pending -> CONFIRMING (must override VALID/INVALID while in flight!)
	controller._confirm_in_flight = true
	controller.confirm_pending_changed.emit(true)
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.CONFIRMING)
	assert_eq(bar.get_badge_text(), "VALIDANDO")
	assert_false(bar.get_displayed_text().contains("LOCAL VÁLIDO"))

	# 5. Placement rejected with ValidationResult reason_code fallback when reason_text is empty
	controller._confirm_in_flight = false
	var rej_res := PlacementValidator.ValidationResult.new()
	rej_res.valid = false
	rej_res.reason_code = PlacementValidator.REASON_CORRIDOR_BLOCKED
	rej_res.reason_text = ""
	controller.placement_rejected.emit(SHELTER_DEF, Vector3.ZERO, rej_res)
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.INVALID)
	assert_eq(bar.get_last_reason_code(), PlacementValidator.REASON_CORRIDOR_BLOCKED)
	assert_true(bar.get_displayed_text().contains("corredor"), "Empty reason_text must map cleanly from real reason_code")

	# 6. Placement cancelled -> HIDDEN cleanly
	controller.cancel_placement()
	assert_eq(bar.get_status_mode(), D2PlacementStatusBar.StatusMode.HIDDEN)
	assert_false(bar.visible)
	assert_eq(bar.get_displayed_text(), "")

	# 7. Polygonal hitbox on status bar & top-center clearance at 1280x720 and 1920x1080
	for res: Vector2 in [Vector2(1920.0, 1080.0), Vector2(1280.0, 720.0)]:
		var s: float = 1.0 if res.x >= 1900.0 else (res.x / 1920.0) * 1.22
		bar.apply_layout(res, s)
		var bar_rect: Rect2 = bar.get_content_bounds()
		assert_true(Rect2(Vector2.ZERO, res).encloses(bar_rect), "Status bar must stay inside %s" % str(res))
		var rocks_end_x: float = (D2Tokens.ROCK_ORIGIN.x + 3.0 * D2Tokens.ROCK_CONTENT_SIZE.x + 2.0 * D2Tokens.ROCK_GAP_X) * s
		var plaque_start_x: float = res.x - (D2Tokens.PLAQUE_MARGIN_RIGHT + D2Tokens.PLAQUE_CONTENT_SIZE.x) * s
		assert_gt(bar_rect.position.x, rocks_end_x, "Status bar must clear resource rocks at %s" % str(res))
		assert_lt(bar_rect.end.x, plaque_start_x, "Status bar must clear top plaque at %s" % str(res))
		var sb_slab: D2PolygonalSlab = bar.get_slab()
		assert_true(sb_slab.contains_local_point(sb_slab.size * 0.5))
		assert_false(sb_slab.contains_local_point(Vector2(2.0, 2.0)))

	# 8. Idempotent unbind disconnects all controller signals
	bar.unbind()
	bar.unbind()
	assert_false(bar.is_bound_to_controller(controller))
	assert_eq(controller.placement_started.get_connections().size(), 0)
	assert_eq(controller.hover_state_changed.get_connections().size(), 0)
	assert_eq(controller.confirm_pending_changed.get_connections().size(), 0)

	controller.queue_free()
	root.queue_free()
