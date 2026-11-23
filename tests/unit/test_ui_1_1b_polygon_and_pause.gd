extends TestCase
## Unit tests for UI-1.1B:
## - D2PolygonalSlab & D2SlabButton polygonal _has_point(), shadow_pad transparency,
##   scroll/focus properties, and dynamic resize scaling (1.00 -> 1.22 -> 1.00).
## - D2SimulationPauseController ownership & cooperative authority policy covering all 6
##   mandatory scenarios (HUD pause/resume, external unmanaged & cooperative pause preservation,
##   multi-reason UI coexistence, HUD removal while paused, scene exit while externally paused,
##   repeated/out-of-order idempotency, zero EconomyClockController.set_paused() / Engine.time_scale mutation).
## - D2TopPlaqueView active ||/1x states, external pause honesty (1x disabled), and inert 2x/4x/Menu.
## - D2UiEscapeRouter pass-through mode and priority-ordered single-dispatch contract.

const EXT_LEASE_A: StringName = &"test_external_authority_a"
const EXT_LEASE_B: StringName = &"test_external_authority_b"


func after_each() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		D2SimulationPauseController.release_tree_pause_lease(tree, EXT_LEASE_A)
		D2SimulationPauseController.release_tree_pause_lease(tree, EXT_LEASE_B)
		if tree.has_meta(D2SimulationPauseController.TREE_META_PAUSE_AUTHORITIES):
			tree.remove_meta(D2SimulationPauseController.TREE_META_PAUSE_AUTHORITIES)
		tree.paused = false
	Engine.time_scale = 1.0


func test_polygonal_slab_and_button_geometry_padding_and_resize() -> void:
	var rock := D2PolygonalSlab.new()
	add_test_child(rock)
	rock.configure_polygon(D2Tokens.POLYGON_RESOURCE_ROCK, D2Tokens.ROCK_CONTENT_SIZE, D2Tokens.ATLAS_SHADOW_PAD)
	rock.set_scaled_size(Vector2(104.0, 62.0))

	assert_eq(rock.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(rock.mouse_force_pass_scroll_events, "Polygonal slab must block scroll pass-through")
	assert_eq(rock.focus_mode, Control.FOCUS_NONE, "Polygonal slab must not capture keyboard focus")

	# Solid interior points hit
	assert_true(rock.contains_local_point(Vector2(52.0, 31.0)), "Rock center must be inside polygon")
	assert_true(rock.contains_local_point(Vector2(22.0, 16.0)), "Rock solid interior near chamfer must hit")
	assert_true(rock.contains_local_point(Vector2(86.0, 48.0)), "Rock lower-right solid interior must hit")

	# Transparent shadow pad (10px) and chamfer corners miss
	assert_false(rock.contains_local_point(Vector2(0.0, 0.0)), "Outer top-left shadow corner must pass through")
	assert_false(rock.contains_local_point(Vector2(5.0, 5.0)), "Mid shadow pad must pass through")
	assert_false(rock.contains_local_point(Vector2(11.0, 11.0)), "Chamfer cut corner outside top-left slope must pass through")
	assert_false(rock.contains_local_point(Vector2(100.0, 31.0)), "Right shadow pad must pass through")
	assert_false(rock.contains_local_point(Vector2(98.0, 58.0)), "Bottom-right shadow corner must pass through")

	# Top plaque peaked silhouette
	var plaque_slab := D2PolygonalSlab.new()
	add_test_child(plaque_slab)
	plaque_slab.configure_polygon(D2Tokens.POLYGON_TOP_PLAQUE, D2Tokens.PLAQUE_CONTENT_SIZE, D2Tokens.ATLAS_SHADOW_PAD)
	plaque_slab.set_scaled_size(Vector2(216.0, 130.0))
	assert_true(plaque_slab.contains_local_point(Vector2(108.0, 65.0)), "Plaque center must hit")
	assert_true(plaque_slab.contains_local_point(Vector2(108.0, 12.0)), "Plaque top peak must hit")
	assert_false(plaque_slab.contains_local_point(Vector2(12.0, 11.0)), "Area above plaque roof slope must pass through")
	assert_false(plaque_slab.contains_local_point(Vector2(4.0, 60.0)), "Plaque left shadow pad must pass through")

	# Resize 1.00 -> 1.22 -> 1.00 must scale polygon accurately and shrink back cleanly
	rock.set_scaled_size(Vector2(104.0 * 1.22, 62.0 * 1.22))
	var poly_122: PackedVector2Array = rock.get_scaled_polygon()
	assert_eq(poly_122.size(), 4)
	assert_near(poly_122[0].x, 16.0 * 1.22, 0.05, "Vertex 0 X must scale by 1.22")
	assert_true(rock.contains_local_point(Vector2(52.0 * 1.22, 31.0 * 1.22)), "Scaled center must hit at 1.22")
	assert_false(rock.contains_local_point(Vector2(5.0 * 1.22, 5.0 * 1.22)), "Scaled shadow pad must miss at 1.22")

	rock.set_scaled_size(Vector2(104.0, 62.0))
	var poly_100: PackedVector2Array = rock.get_scaled_polygon()
	assert_near(poly_100[0].x, 16.0, 0.05, "Vertex 0 X must shrink back cleanly to 1.00")
	assert_false(rock.contains_local_point(Vector2(100.0, 31.0)), "Shrunk right shadow pad must miss again")

	# D2SlabButton supports both polygonal mode and rectangular plaque-slot mode
	var btn := D2SlabButton.new()
	add_test_child(btn)
	btn.configure_polygon(D2Tokens.POLYGON_RESOURCE_ROCK, D2Tokens.ROCK_CONTENT_SIZE, D2Tokens.ATLAS_SHADOW_PAD)
	btn.set_scaled_size(Vector2(104.0, 62.0))
	assert_eq(btn.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_false(btn.mouse_force_pass_scroll_events)
	assert_eq(btn.focus_mode, Control.FOCUS_NONE)
	assert_true(btn.contains_local_point(Vector2(52.0, 31.0)))
	assert_false(btn.contains_local_point(Vector2(5.0, 5.0)))
	btn.clear_polygon()
	btn.set_scaled_size(Vector2(28.0, 21.0))
	assert_true(btn.contains_local_point(Vector2(14.0, 10.0)))
	assert_false(btn.contains_local_point(Vector2(30.0, 10.0)))


func test_pause_controller_all_six_ownership_scenarios() -> void:
	var tree: SceneTree = get_tree()
	assert_false(tree.paused)

	var clock := EconomyClockController.new()
	clock.autostart_timer = false
	add_test_child(clock)
	var tp := SimulatedWorldTimeProvider.new(0.0)
	clock.configure(null, tp)

	var ctrl := D2SimulationPauseController.new()
	add_test_child(ctrl)
	ctrl.configure(null, clock)
	await wait_process_frames(1)

	assert_eq(ctrl.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(ctrl.is_processing(), "Pause controller must not poll _process")
	assert_false(ctrl.is_physics_processing(), "Pause controller must not poll _physics_process")

	# Scenario 1: Initially unpaused -> HUD requests and releases pause
	assert_true(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_true(tree.paused, "HUD request_pause must pause SceneTree")
	assert_true(clock.is_paused(), "EconomyClockController must observe SceneTree.paused")
	assert_false(tp.is_paused(), "Pause controller must NEVER call EconomyClockController.set_paused()")
	assert_near(Engine.time_scale, 1.0, 0.001, "Pause controller must NEVER modify Engine.time_scale")
	assert_true(ctrl.owns_tree_pause())
	assert_true(ctrl.is_hud_paused())
	assert_false(ctrl.is_externally_paused())
	assert_true(ctrl.can_hud_resume_simulation())

	assert_true(ctrl.release_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_false(tree.paused, "Releasing sole HUD pause must unpause SceneTree")
	assert_false(clock.is_paused())
	assert_false(ctrl.is_paused())
	assert_false(ctrl.owns_tree_pause())

	# Scenario 2A: Pre-existing unmanaged external pause -> HUD requests & releases -> external preserved!
	tree.paused = true
	await wait_process_frames(1)
	assert_true(ctrl.is_paused(), "Observer must detect external SceneTree.paused synchronously")
	assert_true(ctrl.is_externally_paused())
	assert_false(ctrl.is_hud_paused())
	assert_false(ctrl.can_hud_resume_simulation())

	assert_true(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_false(ctrl.owns_tree_pause(), "HUD must NOT claim ownership over pre-existing unmanaged external pause")
	assert_true(ctrl.is_hud_paused())
	assert_true(ctrl.is_externally_paused())

	assert_true(ctrl.release_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_true(tree.paused, "CRITICAL: Releasing HUD pause must NEVER clear an unmanaged external pause")
	assert_true(ctrl.is_externally_paused())
	assert_false(ctrl.is_hud_paused())

	tree.paused = false
	await wait_process_frames(1)
	assert_false(ctrl.is_paused())
	assert_false(ctrl.is_externally_paused())

	# Scenario 2B: Cooperative external pause lease (both release orders)
	assert_true(D2SimulationPauseController.acquire_tree_pause_lease(tree, EXT_LEASE_A))
	assert_true(tree.paused)
	assert_true(ctrl.is_externally_paused())
	assert_true(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	# Order 1: HUD releases first -> tree remains paused because EXT_LEASE_A is active
	assert_true(ctrl.release_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_true(tree.paused, "Tree must remain paused while cooperative external lease is held")
	assert_true(D2SimulationPauseController.release_tree_pause_lease(tree, EXT_LEASE_A))
	assert_false(tree.paused, "Tree must unpause once last cooperative lease is released")

	# Order 2: External acquires, HUD acquires, External releases first -> tree stays paused until HUD releases
	assert_true(D2SimulationPauseController.acquire_tree_pause_lease(tree, EXT_LEASE_B))
	assert_true(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_true(D2SimulationPauseController.release_tree_pause_lease(tree, EXT_LEASE_B))
	assert_true(tree.paused, "Tree must stay paused while HUD still holds its own pause reason")
	assert_true(ctrl.release_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_false(tree.paused, "Tree must unpause when final HUD pause is released")

	# Scenario 3: Two UI-owned pause reasons coexisting
	assert_true(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_true(ctrl.request_pause(&"ui_secondary_test_reason"))
	assert_eq(ctrl.get_active_reasons().size(), 2)
	assert_true(ctrl.release_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_true(tree.paused, "Second UI pause reason must keep simulation paused")
	assert_true(ctrl.release_pause(&"ui_secondary_test_reason"))
	assert_false(tree.paused, "Releasing final UI reason must unpause")

	# Scenario 6: Repeated & out-of-order requests are strictly idempotent
	assert_false(ctrl.request_pause(&""), "Empty pause reason must be rejected")
	assert_false(ctrl.release_pause(&"nonexistent_reason"), "Releasing unknown reason must be no-op")
	assert_false(ctrl.release_pause(D2SimulationPauseController.REASON_HUD_PAUSE), "Releasing inactive reason must be no-op")
	assert_true(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	assert_false(ctrl.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE), "Duplicate request must be idempotent")
	assert_eq(ctrl.get_active_reasons().size(), 1)

	# Scenario 4: HUD controller removed while owning pause -> cleanly unpauses
	ctrl.queue_free()
	await wait_process_frames(2)
	assert_false(tree.paused, "Removing HUD pause controller that owns pause must restore SceneTree.paused = false")

	# Scenario 5: Scene/HUD removed while external pause is active -> external pause preserved!
	var ctrl2 := D2SimulationPauseController.new()
	add_test_child(ctrl2)
	await wait_process_frames(1)
	tree.paused = true
	await wait_process_frames(1)
	assert_true(ctrl2.request_pause(D2SimulationPauseController.REASON_HUD_PAUSE))
	ctrl2.queue_free()
	await wait_process_frames(2)
	assert_true(tree.paused, "CRITICAL: Removing HUD while external pause is active must NEVER unpause SceneTree")
	tree.paused = false


func test_top_plaque_pause_states_and_external_pause_honesty() -> void:
	var tree: SceneTree = get_tree()
	var lib := D2AtlasLibrary.new()
	lib.load_all()
	var tf := D2ThemeFactory.new()

	var ctrl := D2SimulationPauseController.new()
	add_test_child(ctrl)

	var plaque := D2TopPlaqueView.new()
	add_test_child(plaque)
	plaque.setup_visuals(lib, tf, Vector2(1920.0, 1080.0), 1.0)
	plaque.bind_pause_controller(ctrl)
	await wait_process_frames(1)

	assert_eq(plaque.process_mode, Node.PROCESS_MODE_ALWAYS, "Top plaque must stay responsive during pause")
	assert_eq(plaque.get_interactive_button_count(), 2, "Only || and 1x buttons may be interactive in UI-1.1B")
	assert_true(plaque.has_inert_unimplemented_controls(), "2x, 4x, and Menu must remain strictly inert")

	var btn_pause: D2SlabButton = plaque.get_pause_button()
	var btn_resume: D2SlabButton = plaque.get_resume_button()
	assert_not_null(btn_pause)
	assert_not_null(btn_resume)

	# Normal running state: 1x active, || enabled inactive
	assert_false(btn_pause.disabled)
	assert_false(btn_pause.is_active_state())
	assert_false(btn_resume.disabled)
	assert_true(btn_resume.is_active_state())

	# HUD pause state: || active, 1x enabled inactive
	btn_pause.pressed.emit()
	assert_true(tree.paused)
	assert_true(btn_pause.is_active_state())
	assert_false(btn_resume.disabled)
	assert_false(btn_resume.is_active_state())

	# Resume via 1x
	btn_resume.pressed.emit()
	assert_false(tree.paused)
	assert_false(btn_pause.is_active_state())
	assert_true(btn_resume.is_active_state())

	# External pause: 1x MUST be disabled and never pretend to clear external pause
	tree.paused = true
	await wait_process_frames(1)
	assert_true(ctrl.is_externally_paused())
	assert_true(btn_resume.disabled, "1x MUST be disabled during external pause")
	assert_false(btn_resume.is_active_state())
	assert_true(btn_pause.is_external_pause_indicator(), "|| must reflect external paused state honestly")

	tree.paused = false
	await wait_process_frames(1)
	assert_false(btn_resume.disabled, "1x must re-enable after external pause clears")
	assert_true(btn_resume.is_active_state())


func test_escape_router_passthrough_and_priority_contract() -> void:
	var router := D2UiEscapeRouter.new()
	add_test_child(router)
	await wait_process_frames(1)

	assert_eq(router.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(router.is_pass_through_mode(), "UI-1.1B router must start in pass-through mode")
	assert_eq(router.get_handler_count(), 0)
	assert_eq(router.try_route_escape(), &"", "Pass-through router must not consume Esc")

	var calls: Array[StringName] = []
	var active_flags: Dictionary = {&"inspector": true, &"maquettes": true, &"menu": false}

	assert_true(router.register_handler(
		&"inspector",
		D2UiEscapeRouter.PRIORITY_INSPECTOR,
		func() -> bool: return bool(active_flags[&"inspector"]),
		func() -> void: calls.append(&"inspector")
	))
	assert_true(router.register_handler(
		&"menu",
		D2UiEscapeRouter.PRIORITY_MAIN_MENU,
		func() -> bool: return bool(active_flags[&"menu"]),
		func() -> void: calls.append(&"menu")
	))
	assert_true(router.register_handler(
		&"maquettes",
		D2UiEscapeRouter.PRIORITY_MAQUETTES,
		func() -> bool: return bool(active_flags[&"maquettes"]),
		func() -> void: calls.append(&"maquettes")
	))

	assert_false(router.is_pass_through_mode())
	assert_eq(router.get_registered_handler_ids(), [&"menu", &"maquettes", &"inspector"])

	# Menu inactive -> Maquettes (priority 30) wins over Inspector (priority 50), fires ONCE
	assert_eq(router.try_route_escape(), &"maquettes")
	assert_eq(calls, [&"maquettes"], "Only highest-priority active handler may fire")

	# Disable maquettes -> Inspector fires
	active_flags[&"maquettes"] = false
	assert_eq(router.try_route_escape(), &"inspector")
	assert_eq(calls, [&"maquettes", &"inspector"])

	# Disable all -> nothing consumed (pass-through)
	active_flags[&"inspector"] = false
	assert_eq(router.try_route_escape(), &"", "When no handler is active, router must pass through")
	assert_eq(calls.size(), 2)

	# Unregister & clear returns cleanly to pass-through
	assert_true(router.unregister_handler(&"menu"))
	assert_false(router.has_handler(&"menu"))
	router.clear_handlers()
	assert_true(router.is_pass_through_mode())
	assert_eq(router.get_handler_count(), 0)
