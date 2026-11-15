extends SceneTree
## Measures real wall-clock cost of T3.2 placement hover validation vs isolated candidate
## NavMesh confirmation inside rendered MainScene + TestMap (without --fixed-fps).

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")


func _init() -> void:
	call_deferred("_run")


func _percentile(sorted_vals: Array[float], q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(sorted_vals.size()))) - 1, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


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

	await process_frame
	await physics_frame

	var rig: RtsCameraRig = main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var placement: PlacementController = main.get_placement_controller()
	var validator: PlacementValidator = placement.get_validator()
	var ctx: PlacementValidator.ValidationContext = placement.build_validation_context()

	# Warmup
	var sample_positions: Array[Vector3] = [
		Vector3(-6.0, 0.0, 1.5),
		Vector3(0.37, 0.0, -13.19),
		Vector3(0.0, 0.0, 0.5),
		Vector3(-9.5, 0.0, -1.5),
		Vector3(9.05, 0.81, -14.0),
		Vector3(-6.4, 0.0, 2.1),
	]
	for _w: int in range(6):
		validator.validate_hover(SHELTER_DEF, sample_positions[0], ctx)
		await process_frame

	# 1. Measure 120 continuous hover validations across valid & invalid spots + per-frame frametime
	var hover_us: Array[float] = []
	var hover_frame_ms: Array[float] = []
	var prev_frame_usec: int = Time.get_ticks_usec()
	for i: int in range(120):
		await process_frame
		var frame_now: int = Time.get_ticks_usec()
		hover_frame_ms.append(float(frame_now - prev_frame_usec) / 1000.0)
		prev_frame_usec = frame_now

		var pos: Vector3 = sample_positions[i % sample_positions.size()]
		var def: BuildingDefinition = SHELTER_DEF if (i % 2 == 0) else DEPOT_DEF
		var res: PlacementValidator.ValidationResult = validator.validate_hover(def, pos, ctx)
		hover_us.append(float(res.evaluation_usec))

	# 2. Measure 15 confirmation validations on valid gridless spots (exercises full CandidateSession bake + connectivity)
	var confirm_ms: Array[float] = []
	var bake_ms: Array[float] = []
	var valid_confirm_positions: Array[Vector3] = [
		Vector3(-6.0, 0.0, 1.5),
		Vector3(0.37, 0.0, -13.19),
		Vector3(0.0, 0.0, 5.2),
		Vector3(5.8, 0.0, 2.2),
		Vector3(-5.2, 0.0, -13.5),
	]
	for i: int in range(15):
		await process_frame
		var pos: Vector3 = valid_confirm_positions[i % valid_confirm_positions.size()]
		var def: BuildingDefinition = SHELTER_DEF if (i % 2 == 0) else DEPOT_DEF
		var res: PlacementValidator.ValidationResult = validator.validate_confirm(def, pos, ctx)
		confirm_ms.append(float(res.evaluation_usec) / 1000.0)
		bake_ms.append(res.candidate_bake_ms)

	hover_us.sort()
	hover_frame_ms.sort()
	confirm_ms.sort()
	bake_ms.sort()

	var hover_mean_us: float = 0.0
	for v: float in hover_us:
		hover_mean_us += v
	hover_mean_us /= float(hover_us.size())

	var confirm_mean_ms: float = 0.0
	for v: float in confirm_ms:
		confirm_mean_ms += v
	confirm_mean_ms /= float(confirm_ms.size())

	var bake_mean_ms: float = 0.0
	for v: float in bake_ms:
		bake_mean_ms += v
	bake_mean_ms /= float(bake_ms.size())

	print("T3_2_PERF_RESULT", JSON.stringify({
		"hover_samples": hover_us.size(),
		"hover_mean_ms": snappedf(hover_mean_us / 1000.0, 0.001),
		"hover_p50_ms": snappedf(_percentile(hover_us, 0.50) / 1000.0, 0.001),
		"hover_p95_ms": snappedf(_percentile(hover_us, 0.95) / 1000.0, 0.001),
		"hover_max_ms": snappedf(hover_us[hover_us.size() - 1] / 1000.0, 0.001),
		"hover_frame_p50_ms": snappedf(_percentile(hover_frame_ms, 0.50), 0.001),
		"hover_frame_p95_ms": snappedf(_percentile(hover_frame_ms, 0.95), 0.001),
		"confirm_samples": confirm_ms.size(),
		"confirm_mean_ms": snappedf(confirm_mean_ms, 0.001),
		"confirm_p50_ms": snappedf(_percentile(confirm_ms, 0.50), 0.001),
		"confirm_p95_ms": snappedf(_percentile(confirm_ms, 0.95), 0.001),
		"confirm_max_ms": snappedf(confirm_ms[confirm_ms.size() - 1], 0.001),
		"candidate_bake_mean_ms": snappedf(bake_mean_ms, 0.001),
		"candidate_bake_p50_ms": snappedf(_percentile(bake_ms, 0.50), 0.001),
		"candidate_bake_p95_ms": snappedf(_percentile(bake_ms, 0.95), 0.001),
	}))

	main.queue_free()
	await process_frame
	quit(0)
