extends SceneTree
## T1.10 Controlled RVO Cost Breakdown Benchmark.
## Compares identical workloads on MainScene to decompose:
## - General physics baseline (IDLE_RVO_OFF vs MOVING_RVO_OFF)
## - Passive RVO overhead when idle (IDLE_RVO_ON - IDLE_RVO_OFF)
## - Native NavigationServer3D RVO solver delta (TIME_NAVIGATION_PROCESS)
## - Navmesh clamping query cost (NavigationServer3D.map_get_closest_point)
## - Remaining TIME_PHYSICS_PROCESS delta (agent sync, callbacks, GDScript overhead)

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SAMPLE_FRAMES: int = 360
const WARMUP_FRAMES: int = 60

var _out_path: String = "test_output/perf/rvo_breakdown.json"


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		while not nav.is_navigation_ready():
			await physics_frame

	await process_frame
	await physics_frame
	await physics_frame

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in main_root.get_units():
		if unit.get_character_id() == &"leader_a":
			leader_a = unit
		elif unit.get_character_id() == &"leader_b":
			leader_b = unit

	if leader_a == null or leader_b == null:
		push_error("RVO breakdown: missing protagonists")
		quit(1)
		return

	var agent_a: NavigationAgent3D = leader_a.get_node("NavigationAgent3D") as NavigationAgent3D
	var agent_b: NavigationAgent3D = leader_b.get_node("NavigationAgent3D") as NavigationAgent3D

	# Warmup
	for _i: int in range(WARMUP_FRAMES):
		await physics_frame

	# 1. IDLE RVO OFF
	agent_a.avoidance_enabled = false
	agent_b.avoidance_enabled = false
	_park_units(leader_a, leader_b)
	var idle_off: Dictionary = await _measure_idle()

	# 2. IDLE RVO ON
	agent_a.avoidance_enabled = true
	agent_b.avoidance_enabled = true
	_park_units(leader_a, leader_b)
	var idle_on: Dictionary = await _measure_idle()

	# 3. MOVING RVO OFF
	agent_a.avoidance_enabled = false
	agent_b.avoidance_enabled = false
	var moving_off: Dictionary = await _measure_crossing(leader_a, leader_b)

	# 4. MOVING RVO ON
	agent_a.avoidance_enabled = true
	agent_b.avoidance_enabled = true
	var moving_on: Dictionary = await _measure_crossing(leader_a, leader_b)

	# 5. Isolated NavigationServer3D.map_get_closest_point cost (2 calls per frame = 2 units)
	var nav_map: RID = agent_a.get_navigation_map()
	var clamp_samples_us: Array[float] = []
	for i: int in range(SAMPLE_FRAMES):
		var p1 := Vector3(sin(float(i) * 0.1) * 4.0, 0.0, 0.0)
		var p2 := Vector3(-sin(float(i) * 0.1) * 4.0, 0.0, 0.0)
		var t0: int = Time.get_ticks_usec()
		var _c1: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, p1)
		var _c2: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, p2)
		var t1: int = Time.get_ticks_usec()
		clamp_samples_us.append(float(t1 - t0))

	# 6. Isolated NavigationAgent3D.get_next_path_position cost (2 calls per frame)
	var path_query_samples_us: Array[float] = []
	for _i: int in range(SAMPLE_FRAMES):
		var t0: int = Time.get_ticks_usec()
		var _n1: Vector3 = agent_a.get_next_path_position()
		var _n2: Vector3 = agent_b.get_next_path_position()
		var t1: int = Time.get_ticks_usec()
		path_query_samples_us.append(float(t1 - t0))

	var phys_delta_us: float = float(moving_on["phys_avg_us"]) - float(moving_off["phys_avg_us"])
	var nav_delta_us: float = float(moving_on["nav_avg_us"]) - float(moving_off["nav_avg_us"])
	var clamp_avg_us: float = _avg(clamp_samples_us)
	var residual_phys_delta_us: float = phys_delta_us - clamp_avg_us

	var report: Dictionary = {
		"sample_frames": SAMPLE_FRAMES,
		"gpu_adapter": RenderingServer.get_video_adapter_name(),
		"cpu_name": OS.get_processor_name(),
		"idle_rvo_off": idle_off,
		"idle_rvo_on": idle_on,
		"moving_rvo_off": moving_off,
		"moving_rvo_on": moving_on,
		"isolated_queries": {
			"map_get_closest_point_2x_avg_us": clamp_avg_us,
			"map_get_closest_point_2x_p95_us": _percentile(clamp_samples_us, 0.95),
			"get_next_path_position_2x_avg_us": _avg(path_query_samples_us),
		},
		"decomposition": {
			"idle_rvo_phys_delta_us": float(idle_on["phys_avg_us"]) - float(idle_off["phys_avg_us"]),
			"idle_rvo_nav_delta_us": float(idle_on["nav_avg_us"]) - float(idle_off["nav_avg_us"]),
			"moving_phys_total_delta_us": phys_delta_us,
			"moving_nav_total_delta_us": nav_delta_us,
			"estimated_navmesh_clamp_2x_us": clamp_avg_us,
			"estimated_cpp_agent_callback_and_gdscript_delta_us": residual_phys_delta_us,
		},
	}

	_write_json(_out_path, report)
	print("RVO_BREAKDOWN ", JSON.stringify(report))
	quit(0)


func _park_units(unit_a: Unit, unit_b: Unit) -> void:
	unit_a.cancel_current_order()
	unit_b.cancel_current_order()
	unit_a.velocity = Vector3.ZERO
	unit_b.velocity = Vector3.ZERO
	unit_a.global_position = Vector3(-4.0, 0.0, 0.0)
	unit_b.global_position = Vector3(4.0, 0.0, 0.0)


func _measure_idle() -> Dictionary:
	await physics_frame
	await physics_frame
	var phys_us: Array[float] = []
	var nav_us: Array[float] = []
	for _i: int in range(SAMPLE_FRAMES):
		await physics_frame
		phys_us.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0)
		nav_us.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1_000_000.0)
	return {
		"phys_avg_us": _avg(phys_us),
		"phys_p95_us": _percentile(phys_us, 0.95),
		"nav_avg_us": _avg(nav_us),
		"nav_p95_us": _percentile(nav_us, 0.95),
	}


func _measure_crossing(unit_a: Unit, unit_b: Unit) -> Dictionary:
	var phys_us: Array[float] = []
	var nav_us: Array[float] = []

	var cycle: int = 0
	for frame_idx: int in range(SAMPLE_FRAMES):
		if frame_idx % 120 == 0:
			unit_a.cancel_current_order()
			unit_b.cancel_current_order()
			unit_a.velocity = Vector3.ZERO
			unit_b.velocity = Vector3.ZERO
			if cycle % 2 == 0:
				unit_a.global_position = Vector3(-5.0, 0.0, 0.0)
				unit_b.global_position = Vector3(5.0, 0.0, 0.0)
				await physics_frame
				unit_a.issue_order(MoveOrder.new(Vector3(5.0, 0.0, 0.0)))
				unit_b.issue_order(MoveOrder.new(Vector3(-5.0, 0.0, 0.0)))
			else:
				unit_a.global_position = Vector3(-4.5, 0.0, -4.5)
				unit_b.global_position = Vector3(4.5, 0.0, -4.5)
				await physics_frame
				unit_a.issue_order(MoveOrder.new(Vector3(4.5, 0.0, 4.5)))
				unit_b.issue_order(MoveOrder.new(Vector3(-4.5, 0.0, 4.5)))
			cycle += 1
		await physics_frame
		phys_us.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0)
		nav_us.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1_000_000.0)

	return {
		"phys_avg_us": _avg(phys_us),
		"phys_p95_us": _percentile(phys_us, 0.95),
		"nav_avg_us": _avg(nav_us),
		"nav_p95_us": _percentile(nav_us, 0.95),
	}


func _avg(vals: Array[float]) -> float:
	if vals.is_empty():
		return 0.0
	var s: float = 0.0
	for v: float in vals:
		s += v
	return s / float(vals.size())


func _percentile(vals: Array[float], q: float) -> float:
	if vals.is_empty():
		return 0.0
	var sorted: Array[float] = vals.duplicate()
	sorted.sort()
	var idx: int = clampi(int(ceil(q * float(sorted.size()))) - 1, 0, sorted.size() - 1)
	return sorted[idx]


func _write_json(rel_or_abs_path: String, data: Dictionary) -> void:
	var abs_path: String = rel_or_abs_path
	if not abs_path.is_absolute_path():
		abs_path = ProjectSettings.globalize_path("res://" + rel_or_abs_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
