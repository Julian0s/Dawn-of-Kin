extends SceneTree
## T1.10 Reproducible Windowed Performance Benchmark.
## Measures real rendered frame-to-frame wall time (us/ms), physics/navigation CPU time,
## draw calls, objects, memory, and hardware/display metadata on MainScene with active RVO,
## repeated movement orders, and continuous RTS camera motion.
## Never uses --fixed-fps and disables VSync to avoid artificial FPS capping.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")

const WAYPOINTS_A: Array[Vector3] = [
	Vector3(-8.0, 0.0, 6.0),
	Vector3(0.0, 0.0, -2.0),
	Vector3(0.0, 0.0, -10.0),
	Vector3(17.5, 2.0, -14.0),
	Vector3(2.0, 0.0, -14.0),
	Vector3(6.0, 0.0, 6.0),
]

const WAYPOINTS_B: Array[Vector3] = [
	Vector3(8.0, 0.0, 6.0),
	Vector3(0.0, 0.0, -10.0),
	Vector3(0.0, 0.0, -2.0),
	Vector3(2.0, 0.0, -14.0),
	Vector3(17.5, 2.0, -14.0),
	Vector3(-6.0, 0.0, 6.0),
]

var _warmup_sec: float = 5.0
var _duration_sec: float = 30.0
var _out_path: String = "test_output/perf/benchmark_run.json"
var _requested_res: String = "windowed"
var _use_fullscreen: bool = false


func _init() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--warmup="):
			_warmup_sec = maxf(0.0, float(arg.trim_prefix("--warmup=")))
		elif arg.begins_with("--duration="):
			_duration_sec = maxf(1.0, float(arg.trim_prefix("--duration=")))
		elif arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--resolution="):
			_requested_res = arg.trim_prefix("--resolution=")
		elif arg == "--fullscreen":
			_use_fullscreen = true
			_requested_res = "native_fullscreen"


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _use_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

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

	var selection: SelectionManager = main_root.get_selection_manager()
	var cmd: CommandController = main_root.get_command_controller()
	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in main_root.get_units():
		if unit.get_character_id() == &"leader_a":
			leader_a = unit
		elif unit.get_character_id() == &"leader_b":
			leader_b = unit

	if leader_a == null or leader_b == null or selection == null or cmd == null:
		push_error("T1.10 Perf: Missing required MainScene protagonists or RTS controllers")
		quit(1)
		return

	var wp_idx_a: int = 0
	var wp_idx_b: int = 0
	var order_timer_sec: float = 0.0
	var order_interval_sec: float = 2.0

	# Issue initial crossing orders
	_issue_move(selection, cmd, leader_a, WAYPOINTS_A[wp_idx_a])
	_issue_move(selection, cmd, leader_b, WAYPOINTS_B[wp_idx_b])

	var frametimes_ms: Array[float] = []
	var phys_ms_samples: Array[float] = []
	var nav_ms_samples: Array[float] = []
	var draw_calls_samples: Array[float] = []
	var object_count_samples: Array[float] = []
	var mem_mb_samples: Array[float] = []

	var start_usec: int = Time.get_ticks_usec()
	var prev_usec: int = start_usec
	var record_start_usec: int = 0
	var recording: bool = false
	var total_target_sec: float = _warmup_sec + _duration_sec

	while true:
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var dt_sec: float = float(now_usec - prev_usec) / 1_000_000.0
		prev_usec = now_usec

		var elapsed_sec: float = float(now_usec - start_usec) / 1_000_000.0
		if elapsed_sec >= total_target_sec:
			break

		# Drive camera sweep across map bounds
		if rig != null:
			var angle: float = elapsed_sec * 0.45
			var cam_x: float = sin(angle) * 14.0
			var cam_z: float = cos(angle * 0.7) * 12.0 - 2.0
			rig.set_focus_position(Vector2(cam_x, cam_z))

		# Repeated movement orders (active RVO + navigation + physics)
		order_timer_sec += dt_sec
		if order_timer_sec >= order_interval_sec or leader_a.get_state() == Unit.State.IDLE or leader_b.get_state() == Unit.State.IDLE:
			if leader_a.get_state() == Unit.State.IDLE or order_timer_sec >= order_interval_sec:
				wp_idx_a = (wp_idx_a + 1) % WAYPOINTS_A.size()
				_issue_move(selection, cmd, leader_a, WAYPOINTS_A[wp_idx_a])
			if leader_b.get_state() == Unit.State.IDLE or order_timer_sec >= order_interval_sec:
				wp_idx_b = (wp_idx_b + 1) % WAYPOINTS_B.size()
				_issue_move(selection, cmd, leader_b, WAYPOINTS_B[wp_idx_b])
			order_timer_sec = 0.0

		if not recording:
			if elapsed_sec >= _warmup_sec:
				recording = true
				record_start_usec = now_usec
		else:
			var frame_ms: float = dt_sec * 1000.0
			frametimes_ms.append(frame_ms)
			phys_ms_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			nav_ms_samples.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
			draw_calls_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			object_count_samples.append(Performance.get_monitor(Performance.OBJECT_COUNT))
			mem_mb_samples.append(Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0))

	var recorded_sec: float = float(Time.get_ticks_usec() - record_start_usec) / 1_000_000.0
	var sorted_ft: Array[float] = frametimes_ms.duplicate()
	sorted_ft.sort()

	var frame_count: int = sorted_ft.size()
	var avg_fps: float = float(frame_count) / maxf(recorded_sec, 0.001)
	var p50_ms: float = _percentile(sorted_ft, 0.50)
	var p95_ms: float = _percentile(sorted_ft, 0.95)
	var p99_ms: float = _percentile(sorted_ft, 0.99)
	var max_ms: float = sorted_ft[frame_count - 1] if frame_count > 0 else 0.0
	var min_ms: float = sorted_ft[0] if frame_count > 0 else 0.0

	var over_100ms: int = 0
	var over_16_7ms: int = 0
	for ft: float in sorted_ft:
		if ft > 100.0:
			over_100ms += 1
		if ft > 16.7:
			over_16_7ms += 1

	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var win_size: Vector2i = DisplayServer.window_get_size()
	var render_size_3d: Vector2i = root.size
	var vp_size: Vector2 = root.get_visible_rect().size
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()

	var summary: Dictionary = {
		"requested_resolution": _requested_res,
		"fullscreen": _use_fullscreen,
		"screen_size": "%dx%d" % [screen_size.x, screen_size.y],
		"window_size": "%dx%d" % [win_size.x, win_size.y],
		"viewport_size": "%dx%d" % [render_size_3d.x, render_size_3d.y],
		"canvas_visible_rect_2d": "%dx%d" % [int(vp_size.x), int(vp_size.y)],
		"screen_dpi": DisplayServer.screen_get_dpi(),
		"screen_scale": DisplayServer.screen_get_scale(),
		"vsync_mode": vsync_mode,
		"gpu_adapter": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"cpu_name": OS.get_processor_name(),
		"cpu_count": OS.get_processor_count(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		"warmup_sec": _warmup_sec,
		"duration_sec": recorded_sec,
		"frames_recorded": frame_count,
		"avg_fps": avg_fps,
		"frametime_min_ms": min_ms,
		"frametime_p50_ms": p50_ms,
		"frametime_p95_ms": p95_ms,
		"frametime_p99_ms": p99_ms,
		"frametime_max_ms": max_ms,
		"frames_over_16_7ms": over_16_7ms,
		"frames_over_100ms": over_100ms,
		"phys_avg_ms": _avg(phys_ms_samples),
		"nav_avg_ms": _avg(nav_ms_samples),
		"draw_calls_avg": _avg(draw_calls_samples),
		"objects_avg": _avg(object_count_samples),
		"memory_static_avg_mb": _avg(mem_mb_samples),
		"memory_static_max_mb": OS.get_static_memory_peak_usage() / (1024.0 * 1024.0),
	}

	_write_json(_out_path, summary)
	print("PERF_RESULT ", JSON.stringify(summary))
	quit(0)


func _issue_move(selection: SelectionManager, cmd: CommandController, unit: Unit, target: Vector3) -> void:
	selection.select_single(unit)
	cmd.command_at(PickResult.from_ground(target, Vector3.UP))


func _percentile(sorted_vals: Array[float], q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(q * float(sorted_vals.size()))) - 1, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _avg(vals: Array[float]) -> float:
	if vals.is_empty():
		return 0.0
	var total: float = 0.0
	for v: float in vals:
		total += v
	return total / float(vals.size())


func _write_json(rel_or_abs_path: String, data: Dictionary) -> void:
	var abs_path: String = rel_or_abs_path
	if not abs_path.is_absolute_path():
		abs_path = ProjectSettings.globalize_path("res://" + rel_or_abs_path)
	var parent_dir: String = abs_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent_dir)
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	else:
		push_error("Failed to write perf output JSON: %s" % abs_path)
