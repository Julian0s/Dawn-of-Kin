extends SceneTree
## Measures real wall-clock frame times and site creation latency for T3.3
## construction logistics (reservation, targeted pile withdrawal, multi-worker
## transport, perimeter drop-off, and temporary site inspector HUD) inside
## rendered MainScene + TestMap without --fixed-fps.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DEPOT_DEF: BuildingDefinition = preload("res://data/buildings/storage_depot.tres")

const MEASURE_FRAMES: int = 360


func _init() -> void:
	call_deferred("_run")


func _percentile(sorted_vals: Array[float], q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(sorted_vals.size()))) - 1, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _summarize(raw_vals: Array[float]) -> Dictionary:
	var sorted: Array[float] = raw_vals.duplicate()
	sorted.sort()
	var sum: float = 0.0
	var spikes_100ms: int = 0
	for v: float in sorted:
		sum += v
		if v > 100.0:
			spikes_100ms += 1
	var mean_ms: float = sum / maxf(float(sorted.size()), 1.0)
	return {
		"samples": sorted.size(),
		"mean_ms": snappedf(mean_ms, 0.001),
		"avg_fps": snappedf(1000.0 / maxf(mean_ms, 0.001), 0.01),
		"p50_ms": snappedf(_percentile(sorted, 0.50), 0.001),
		"p95_ms": snappedf(_percentile(sorted, 0.95), 0.001),
		"max_ms": snappedf(sorted[sorted.size() - 1], 0.001) if not sorted.is_empty() else 0.0,
		"frames_gt_100ms": spikes_100ms,
	}


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = false
	root.add_child(main)

	var test_map: TestMap = main.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var wait_frames: int = 0
	while nav != null and not nav.is_navigation_ready() and wait_frames < 240:
		await physics_frame
		wait_frames += 1

	for _f: int in range(6):
		await process_frame
		await physics_frame

	var rig: RtsCameraRig = main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var inventory: SettlementInventory = main.get_settlement_inventory()
	var cm: ConstructionManager = main.get_construction_manager()
	var cmd: CommandController = main.get_command_controller()
	var overlay: PlacementTestOverlay = main.get_placement_test_overlay()
	var units_root: Node = main.get_node("Units")

	inventory.deposit(&"wood", 60)
	inventory.deposit(&"stone", 40)

	var workers: Array[Unit] = main.get_units().duplicate()
	for idx: int in range(2):
		var extra: Unit = UNIT_SCENE.instantiate() as Unit
		extra.name = "BenchWorker_%d" % idx
		extra.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
		units_root.add_child(extra)
		extra.global_position = Vector3(-4.0 + float(idx) * 1.5, 0.0, 3.0)
		extra.set_world_navigation(nav)
		workers.append(extra)

	await process_frame
	await physics_frame

	# 1. Measure site creation + atomic reservation latency across 2 sites.
	var create_ms: Array[float] = []
	var t0: int = Time.get_ticks_usec()
	var res_a: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, 1.5))
	create_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var site_a: ConstructionSite = res_a.get("site") as ConstructionSite

	var t1: int = Time.get_ticks_usec()
	var res_b: Dictionary = cm.try_create_site_from_placement(DEPOT_DEF, Vector3(0.37, 0.0, -13.19))
	create_ms.append(float(Time.get_ticks_usec() - t1) / 1000.0)
	var site_b: ConstructionSite = res_b.get("site") as ConstructionSite

	if site_a != null and overlay != null:
		overlay.set_inspected_site(site_a)

	# Assign 2 workers to site_a and 2 workers to site_b so both sites have active logistics.
	var group_a: Array[Unit] = []
	var group_b: Array[Unit] = []
	for i: int in range(workers.size()):
		if i < 2:
			group_a.append(workers[i])
		else:
			group_b.append(workers[i])
	if site_a != null and cmd != null:
		cmd.command_units_to_site(site_a, group_a)
	if site_b != null and cmd != null:
		cmd.command_units_to_site(site_b, group_b)

	# Warmup frames before sampling active transport + HUD update cost.
	for _w: int in range(12):
		await process_frame

	# 2. Sample rendered frame times during active multi-worker logistics + site HUD inspection.
	var active_frame_ms: Array[float] = []
	var prev_usec: int = Time.get_ticks_usec()
	for _i: int in range(MEASURE_FRAMES):
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		active_frame_ms.append(float(now_usec - prev_usec) / 1000.0)
		prev_usec = now_usec

	var delivered_a: Dictionary = site_a.get_delivered_buffer_amounts() if site_a != null else {}
	var delivered_b: Dictionary = site_b.get_delivered_buffer_amounts() if site_b != null else {}
	var report: Dictionary = {
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"site_a_created": site_a != null,
		"site_b_created": site_b != null,
		"site_creation_ms": _summarize(create_ms),
		"active_logistics_frame_ms": _summarize(active_frame_ms),
		"site_a_delivered_after_window": delivered_a,
		"site_b_delivered_after_window": delivered_b,
		"site_a_fully_supplied": site_a.is_fully_supplied() if site_a != null else false,
		"site_b_fully_supplied": site_b.is_fully_supplied() if site_b != null else false,
	}
	print("T3_3_PERF_RESULT ", JSON.stringify(report))

	main.queue_free()
	await process_frame
	quit(0)
