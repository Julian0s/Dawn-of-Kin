extends SceneTree
## Measures real wall-clock cost and frame-time impact of T3.2 placement hover,
## synchronous cached-geometry confirmation, and non-blocking async confirmation
## across >= 30 representative confirmations inside rendered MainScene + TestMap (without --fixed-fps).

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")
const CONFIRM_RUNS: int = 32


func _init() -> void:
	call_deferred("_run")


func _percentile(sorted_vals: Array[float], q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(sorted_vals.size()))) - 1, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _summarize(label: String, raw_vals: Array[float]) -> Dictionary:
	var sorted: Array[float] = raw_vals.duplicate()
	sorted.sort()
	var sum: float = 0.0
	for v: float in sorted:
		sum += v
	return {
		"samples": sorted.size(),
		"mean": snappedf(sum / maxf(float(sorted.size()), 1.0), 0.001),
		"p50": snappedf(_percentile(sorted, 0.50), 0.001),
		"p95": snappedf(_percentile(sorted, 0.95), 0.001),
		"max": snappedf(sorted[sorted.size() - 1], 0.001) if not sorted.is_empty() else 0.0,
	}


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main)

	var test_map: TestMap = main.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var wait_frames: int = 0
	while nav != null and not nav.is_navigation_ready() and wait_frames < 240:
		await physics_frame
		wait_frames += 1

	for _f: int in range(4):
		await process_frame
		await physics_frame

	var rig: RtsCameraRig = main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var placement: PlacementController = main.get_placement_controller()
	var validator: PlacementValidator = placement.get_validator()
	var ctx: PlacementValidator.ValidationContext = placement.build_validation_context()

	var hover_positions: Array[Vector3] = [
		Vector3(-6.0, 0.0, 1.5),
		Vector3(0.37, 0.0, -13.19),
		Vector3(0.0, 0.0, 0.5),
		Vector3(-9.5, 0.0, -1.5),
		Vector3(9.05, 0.81, -14.0),
		Vector3(0.0, 0.0, 5.2),
	]
	var valid_confirm_positions: Array[Vector3] = [
		Vector3(-6.0, 0.0, 1.5),
		Vector3(0.37, 0.0, -13.19),
		Vector3(0.0, 0.0, 5.2),
		Vector3(5.8, 0.0, 2.2),
		Vector3(-5.2, 0.0, -13.5),
		Vector3(5.5, 0.0, -13.5),
	]

	# Warmup hover + sync/async confirm before measurement window
	for _w: int in range(8):
		validator.validate_hover(SHELTER_DEF, hover_positions[_w % hover_positions.size()], ctx)
		await process_frame
	for _w2: int in range(3):
		validator.validate_confirm(SHELTER_DEF, valid_confirm_positions[_w2 % valid_confirm_positions.size()], ctx)
		await process_frame

	# 1. Hover benchmark (120 frames)
	var hover_ms: Array[float] = []
	var hover_frame_ms: Array[float] = []
	var prev_frame_usec: int = Time.get_ticks_usec()
	for i: int in range(120):
		await process_frame
		var frame_now: int = Time.get_ticks_usec()
		hover_frame_ms.append(float(frame_now - prev_frame_usec) / 1000.0)
		prev_frame_usec = frame_now

		var pos: Vector3 = hover_positions[i % hover_positions.size()]
		var def: BuildingDefinition = SHELTER_DEF if (i % 2 == 0) else DEPOT_DEF
		var res: PlacementValidator.ValidationResult = validator.validate_hover(def, pos, ctx)
		hover_ms.append(float(res.evaluation_usec) / 1000.0)

	# 2. Async confirmation benchmark (32 representative confirmations via worker-thread CandidateSession)
	var async_main_ms: Array[float] = []
	var async_wall_ms: Array[float] = []
	var async_prepare_ms: Array[float] = []
	var async_bake_ms: Array[float] = []
	var async_sync_ms: Array[float] = []
	var async_query_ms: Array[float] = []
	var async_frame_ms: Array[float] = []

	for i: int in range(CONFIRM_RUNS):
		await process_frame
		var pos: Vector3 = valid_confirm_positions[i % valid_confirm_positions.size()]
		var def: BuildingDefinition = SHELTER_DEF if (i % 2 == 0) else DEPOT_DEF
		var done_res: Array[PlacementValidator.ValidationResult] = []
		var f_prev_usec: int = Time.get_ticks_usec()
		validator.validate_confirm_async(
			def,
			pos,
			ctx,
			func(res: PlacementValidator.ValidationResult) -> void:
				done_res.append(res)
		)
		while done_res.is_empty():
			await process_frame
			var f_now_usec: int = Time.get_ticks_usec()
			async_frame_ms.append(float(f_now_usec - f_prev_usec) / 1000.0)
			f_prev_usec = f_now_usec

		var res_a: PlacementValidator.ValidationResult = done_res[0]
		async_main_ms.append(float(res_a.main_thread_usec) / 1000.0)
		async_wall_ms.append(float(res_a.evaluation_usec) / 1000.0)
		async_prepare_ms.append(res_a.candidate_prepare_ms)
		async_bake_ms.append(res_a.candidate_bake_ms)
		async_sync_ms.append(res_a.candidate_sync_ms)
		async_query_ms.append(res_a.connectivity_query_ms)

	# 3. Synchronous confirm benchmark (32 confirmations using cached static geometry)
	var sync_total_ms: Array[float] = []
	var sync_prepare_ms: Array[float] = []
	var sync_bake_ms: Array[float] = []
	var sync_server_ms: Array[float] = []
	var sync_query_ms: Array[float] = []
	for i: int in range(CONFIRM_RUNS):
		await process_frame
		var pos: Vector3 = valid_confirm_positions[i % valid_confirm_positions.size()]
		var def: BuildingDefinition = SHELTER_DEF if (i % 2 == 0) else DEPOT_DEF
		var res_s: PlacementValidator.ValidationResult = validator.validate_confirm(def, pos, ctx)
		sync_total_ms.append(float(res_s.evaluation_usec) / 1000.0)
		sync_prepare_ms.append(res_s.candidate_prepare_ms)
		sync_bake_ms.append(res_s.candidate_bake_ms)
		sync_server_ms.append(res_s.candidate_sync_ms)
		sync_query_ms.append(res_s.connectivity_query_ms)

	var report: Dictionary = {
		"static_cache_active": nav.has_static_geometry_cache() if nav != null else false,
		"hover_eval_ms": _summarize("hover_eval_ms", hover_ms),
		"hover_frame_ms": _summarize("hover_frame_ms", hover_frame_ms),
		"async_confirm_main_thread_ms": _summarize("async_confirm_main_thread_ms", async_main_ms),
		"async_confirm_wall_ms": _summarize("async_confirm_wall_ms", async_wall_ms),
		"async_confirm_frame_ms": _summarize("async_confirm_frame_ms", async_frame_ms),
		"async_breakdown_ms": {
			"prepare": _summarize("async_prepare", async_prepare_ms),
			"worker_bake": _summarize("async_bake", async_bake_ms),
			"rid_sync": _summarize("async_sync", async_sync_ms),
			"connectivity_queries": _summarize("async_queries", async_query_ms),
		},
		"sync_cached_confirm_total_ms": _summarize("sync_confirm_total_ms", sync_total_ms),
		"sync_breakdown_ms": {
			"prepare": _summarize("sync_prepare", sync_prepare_ms),
			"bake": _summarize("sync_bake", sync_bake_ms),
			"rid_sync": _summarize("sync_sync", sync_server_ms),
			"connectivity_queries": _summarize("sync_queries", sync_query_ms),
		},
	}
	print("T3_2_PERF_RESULT", JSON.stringify(report))

	main.queue_free()
	await process_frame
	quit(0)
