extends SceneTree
## T1.10 Informative Isolated RVO Stress Test (2, 10, 25, 50 units).
## Uses TestMap + Unit + RtsCameraRig with real physics, navigation, and RVO enabled.
## Informative only: does not add T5 population systems or extrapolate to hundreds of units.

const TEST_MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")
const CAMERA_RIG_SCENE: PackedScene = preload("res://src/camera/rts_camera_rig.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")

const UNIT_COUNTS: Array[int] = [2, 10, 25, 50]
const WARMUP_SEC: float = 2.0
const MEASURE_SEC: float = 8.0
const CONTACT_DIAMETER_M: float = 0.80

var _out_path: String = "test_output/perf/stress_results.json"


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var tiers: Array[Dictionary] = []
	for count: int in UNIT_COUNTS:
		var tier_res: Dictionary = await _run_tier(count)
		tiers.append(tier_res)
		print("STRESS_TIER_%d %s" % [count, JSON.stringify(tier_res)])

	var report: Dictionary = {
		"gpu_adapter": RenderingServer.get_video_adapter_name(),
		"cpu_name": OS.get_processor_name(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		"warmup_sec": WARMUP_SEC,
		"measure_sec": MEASURE_SEC,
		"tiers": tiers,
	}
	_write_json(_out_path, report)
	quit(0)


func _run_tier(unit_count: int) -> Dictionary:
	var container := Node3D.new()
	root.add_child(container)

	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	container.add_child(test_map)

	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	rig.edge_pan_enabled = false
	container.add_child(rig)
	rig.set_focus_position(Vector2(0.0, 2.0))

	var nav: WorldNavigation = test_map.get_navigation()
	while not nav.is_navigation_ready():
		await physics_frame
	var nav_map: RID = nav.get_navigation_map()

	var units: Array[Unit] = []
	var failed_orders: Array[int] = [0]
	var ring_radius: float = maxf(4.0, float(unit_count) * 0.35)
	ring_radius = minf(ring_radius, 18.0)

	for i: int in range(unit_count):
		var unit: Unit = UNIT_SCENE.instantiate() as Unit
		unit.definition = LEADER_A_DEF if (i % 2 == 0) else LEADER_B_DEF
		container.add_child(unit)
		var angle: float = (TAU * float(i)) / float(unit_count)
		var spawn_pos := Vector3(cos(angle) * ring_radius, 0.0, 4.0 + sin(angle) * ring_radius * 0.65)
		unit.global_position = NavigationServer3D.map_get_closest_point(nav_map, spawn_pos)
		unit.set_world_navigation(nav)
		unit.order_finished.connect(func(order: UnitOrder) -> void:
			if order.status == UnitOrder.Status.FAILED:
				failed_orders[0] += 1
		)
		units.append(unit)

	await process_frame
	await physics_frame
	await physics_frame

	# Issue opposing cross-circle targets so units actively cross and avoid each other
	for i: int in range(unit_count):
		var angle: float = (TAU * float(i)) / float(unit_count)
		var opposite := Vector3(-cos(angle) * ring_radius, 0.0, 4.0 - sin(angle) * ring_radius * 0.65)
		units[i].issue_order(MoveOrder.new(NavigationServer3D.map_get_closest_point(nav_map, opposite)))

	var frametimes_ms: Array[float] = []
	var phys_ms: Array[float] = []
	var nav_ms: Array[float] = []
	var mem_mb: Array[float] = []
	var overlap_pair_samples: int = 0
	var min_pair_dist_m: float = INF
	var over_100ms: int = 0

	var start_usec: int = Time.get_ticks_usec()
	var prev_usec: int = start_usec
	var record_start_usec: int = 0
	var recording: bool = false
	var reorder_timer: float = 0.0
	var flip_dir: float = 1.0

	while true:
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var dt_sec: float = float(now_usec - prev_usec) / 1_000_000.0
		prev_usec = now_usec
		var elapsed_sec: float = float(now_usec - start_usec) / 1_000_000.0
		if elapsed_sec >= WARMUP_SEC + MEASURE_SEC:
			break

		reorder_timer += dt_sec
		if reorder_timer >= 3.0:
			flip_dir *= -1.0
			for i: int in range(unit_count):
				var angle: float = (TAU * float(i)) / float(unit_count)
				var dest := Vector3(
					flip_dir * -cos(angle) * ring_radius,
					0.0,
					4.0 + flip_dir * -sin(angle) * ring_radius * 0.65
				)
				units[i].issue_order(MoveOrder.new(NavigationServer3D.map_get_closest_point(nav_map, dest)))
			reorder_timer = 0.0

		if not recording:
			if elapsed_sec >= WARMUP_SEC:
				recording = true
				record_start_usec = now_usec
		else:
			var ft_ms: float = dt_sec * 1000.0
			frametimes_ms.append(ft_ms)
			if ft_ms > 100.0:
				over_100ms += 1
			phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			nav_ms.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
			mem_mb.append(Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0))

			# Sample pairwise XZ distances
			for a_idx: int in range(unit_count):
				var pa: Vector3 = units[a_idx].global_position
				for b_idx: int in range(a_idx + 1, unit_count):
					var pb: Vector3 = units[b_idx].global_position
					var dx: float = pa.x - pb.x
					var dz: float = pa.z - pb.z
					var d: float = sqrt(dx * dx + dz * dz)
					if d < min_pair_dist_m:
						min_pair_dist_m = d
					if d < CONTACT_DIAMETER_M:
						overlap_pair_samples += 1

	var recorded_sec: float = float(Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
	var sorted_ft: Array[float] = frametimes_ms.duplicate()
	sorted_ft.sort()

	root.remove_child(container)
	container.queue_free()
	await process_frame
	await physics_frame
	await process_frame

	return {
		"units": unit_count,
		"frames_recorded": sorted_ft.size(),
		"avg_fps": float(sorted_ft.size()) / maxf(recorded_sec, 0.001),
		"frametime_p50_ms": _percentile(sorted_ft, 0.50),
		"frametime_p95_ms": _percentile(sorted_ft, 0.95),
		"frametime_max_ms": sorted_ft[sorted_ft.size() - 1] if not sorted_ft.is_empty() else 0.0,
		"frames_over_100ms": over_100ms,
		"phys_avg_ms": _avg(phys_ms),
		"nav_avg_ms": _avg(nav_ms),
		"memory_static_avg_mb": _avg(mem_mb),
		"min_pair_dist_m": min_pair_dist_m if min_pair_dist_m < INF else 0.0,
		"overlap_pair_samples_lt_0_8m": overlap_pair_samples,
		"failed_orders": int(failed_orders[0]),
	}


func _percentile(sorted_vals: Array[float], q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(sorted_vals.size()))) - 1, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _avg(vals: Array[float]) -> float:
	if vals.is_empty():
		return 0.0
	var s: float = 0.0
	for v: float in vals:
		s += v
	return s / float(vals.size())


func _write_json(rel_or_abs_path: String, data: Dictionary) -> void:
	var abs_path: String = rel_or_abs_path
	if not abs_path.is_absolute_path():
		abs_path = ProjectSettings.globalize_path("res://" + rel_or_abs_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
