extends SceneTree
## T34-PERF-01. Run rendered, uncapped, 1920x1080, OpenGL3 on Intel UHD 620.
## DOK_POWER_CONDITION must come from an external OS power observation, not inference.
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")
const MAX_DURATION_SEC: float = 120.0


func _init() -> void:
	call_deferred("_run")


func _summarize(samples: Array[float]) -> Dictionary:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return {"samples": 0, "p95_ms": 0.0, "frames_gt_100ms": 0}
	var over_100: int = 0
	var total: float = 0.0
	for value: float in sorted:
		total += value
		if value > 100.0:
			over_100 += 1
	return {"samples": sorted.size(), "mean_ms": total / sorted.size(),
		"p50_ms": sorted[ceili(sorted.size() * 0.5) - 1],
		"p95_ms": sorted[ceili(sorted.size() * 0.95) - 1],
		"max_ms": sorted.back(), "frames_gt_100ms": over_100}


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = false
	root.add_child(main)
	var nav: WorldNavigation = main.get_test_map().get_navigation()
	for _frame: int in range(240):
		if nav.is_navigation_ready():
			break
		await physics_frame
	if not nav.is_navigation_ready():
		push_error("T34-PERF-01: initial navigation did not become ready")
		quit(2)
		return
	(main.get_node("RtsCameraRig") as RtsCameraRig).edge_pan_enabled = false
	var inventory: SettlementInventory = main.get_settlement_inventory()
	inventory.deposit(&"wood", 40)
	inventory.deposit(&"stone", 24)
	var spawn: Dictionary = main._test_workers_controller.spawn_temporary_workers()
	if not bool(spawn.get("ok", false)):
		push_error("T34-PERF-01: four-worker setup failed: %s" % str(spawn))
		quit(2)
		return
	var workers: Array[Unit] = main.get_units()
	for _frame: int in range(60):
		await process_frame
	var cm: ConstructionManager = main.get_construction_manager()
	var first: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(-6, 0, 1.5))
	var second: Dictionary = cm.try_create_site_from_placement(DEPOT, Vector3(0.37, 0, -13.19))
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)) or workers.size() != 4:
		push_error("T34-PERF-01: parallel construction setup failed")
		quit(2)
		return
	var site_a: ConstructionSite = first["site"]
	var site_b: ConstructionSite = second["site"]
	main.get_placement_test_overlay().set_inspected_site(site_a)
	var bake_metrics: Array[Dictionary] = []
	nav.navigation_ready.connect(func() -> void:
		if nav._applied_building_revision >= 0:
			bake_metrics.append(nav.get_last_bake_metrics())
	)
	var started: int = Time.get_ticks_usec()
	var previous: int = started
	var frame_ms: Array[float] = []
	var assembly_ms: Array[float] = []
	var rebake_frame_ms: Array[float] = []
	var parallel_frames: int = 0
	var was_baking: bool = false
	var was_assembling: bool = false
	var command: CommandController = main.get_command_controller()
	var group_a: Array[Unit] = [workers[0], workers[2]]
	var group_b: Array[Unit] = [workers[1], workers[3]]
	var commands_ok: bool = command.command_units_to_site(site_a, group_a) and command.command_units_to_site(site_b, group_b)
	var finished: bool = false
	while Time.get_ticks_usec() - started < int(MAX_DURATION_SEC * 1_000_000):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed_ms: float = float(now - previous) / 1000.0
		previous = now
		frame_ms.append(elapsed_ms)
		if was_baking or nav._active_rebake_token != null:
			rebake_frame_ms.append(elapsed_ms)
		var assembling: int = 0
		var assembling_sites: Dictionary = {}
		for worker: Unit in workers:
			var order: ConstructOrder = worker.get_current_order() as ConstructOrder
			if order != null and order.get_phase() == ConstructOrder.Phase.BUILDER_ASSEMBLING:
				assembling += 1
				if is_instance_valid(order.site):
					assembling_sites[order.site.get_instance_id()] = true
		if was_assembling or assembling > 0:
			assembly_ms.append(elapsed_ms)
		if assembling_sites.size() >= 2:
			parallel_frames += 1
		was_assembling = assembling > 0
		was_baking = nav._active_rebake_token != null
		if cm.get_completed_buildings().size() == 2 and nav._pending_building_blockers.is_empty() and nav._active_rebake_token == null:
			finished = true
			break
	var summary: Dictionary = _summarize(frame_ms)
	var adapter: String = RenderingServer.get_video_adapter_name()
	var correct_hardware: bool = "Intel" in adapter and "UHD" in adapter and "620" in adapter and DisplayServer.get_name() != "headless"
	var power: String = OS.get_environment("DOK_POWER_CONDITION")
	var target_environment: bool = correct_hardware and power == "AC" and DisplayServer.window_get_size() == Vector2i(1920, 1080) and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var scenario_ok: bool = commands_ok and finished and parallel_frames > 0 and not bake_metrics.is_empty() and not rebake_frame_ms.is_empty()
	var performance_ok: bool = float(summary["p95_ms"]) <= 16.7 and int(summary["frames_gt_100ms"]) == 0
	var materials: Array[Dictionary] = []
	for building: BuildingInstance in cm.get_completed_buildings():
		materials.append(building.incorporated_materials)
	var result: Dictionary = {"adapter": RenderingServer.get_video_adapter_name(),
		"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"window": str(DisplayServer.window_get_size()), "viewport": str(root.get_visible_rect().size),
		"power_condition_external_observation": power, "duration_sec": float(Time.get_ticks_usec() - started) / 1_000_000.0,
		"workers": workers.size(), "completed_buildings": cm.get_completed_buildings().size(),
		"parallel_assembly_frames": parallel_frames, "materials_incorporated": materials,
		"all_frames": summary, "assembly_frames": _summarize(assembly_ms),
		"rebake_frames": _summarize(rebake_frame_ms), "active_bakes": bake_metrics,
		"scenario_ok": scenario_ok, "target_environment": target_environment, "performance_ok": performance_ok}
	print("T34_PERF_01_RESULT ", JSON.stringify(result))
	main.queue_free()
	await process_frame
	await physics_frame
	quit(0 if scenario_ok and target_environment and performance_ok else 1)
