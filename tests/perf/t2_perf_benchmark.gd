extends SceneTree
## Representative T2 performance benchmark on real MainScene + TestMap.
## Measures post-warmup wall-clock frame times with:
## - 2 active protagonists navigating + RVO separation
## - simultaneous wood/stone/food gathering and load-weighted return transport
## - physical GroundPileManager camp deliveries and active piles
## - signal-driven HUD updates (SettlementStockpilePanel + SelectedUnitPanel)
## - centralized EconomyClockController decay firing inside measurement window
## Do NOT run with --fixed-fps.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const FRAME_BUDGET_MS: float = 1000.0 / 60.0
const FRAME_30FPS_MS: float = 1000.0 / 30.0
const FRAME_SPIKE_MS: float = 100.0
const DECAY_TIME_SCALE: float = 35.0

var _warmup_sec: float = 5.0
var _duration_sec: float = 30.0
var _run_index: int = 1
var _output_json_path: String = ""
var _resolution_label: String = ""

var _recording: bool = false
var _delivery_events: int = 0
var _decay_steps: int = 0
var _decay_units_total: int = 0
var _prev_stock: Dictionary = {"wood": 0, "stone": 0, "food": 0}


func _init() -> void:
	_parse_args()
	call_deferred("_run_benchmark")


func _parse_args() -> void:
	var all_args: PackedStringArray = PackedStringArray()
	all_args.append_array(OS.get_cmdline_args())
	all_args.append_array(OS.get_cmdline_user_args())
	for raw_arg: String in all_args:
		if raw_arg.begins_with("--warmup-sec="):
			_warmup_sec = maxf(0.5, float(raw_arg.trim_prefix("--warmup-sec=")))
		elif raw_arg.begins_with("--duration-sec="):
			_duration_sec = maxf(1.0, float(raw_arg.trim_prefix("--duration-sec=")))
		elif raw_arg.begins_with("--run-index="):
			_run_index = maxi(1, int(raw_arg.trim_prefix("--run-index=")))
		elif raw_arg.begins_with("--output-json="):
			_output_json_path = raw_arg.trim_prefix("--output-json=").strip_edges()
		elif raw_arg.begins_with("--resolution-label="):
			_resolution_label = raw_arg.trim_prefix("--resolution-label=").strip_edges()


func _run_benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = false
	if main == null:
		push_error("Failed to instantiate MainScene for T2 benchmark.")
		quit(1)
		return

	root.add_child(main)

	var test_map: TestMap = main.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var nav_wait: int = 0
		while not nav.is_navigation_ready() and nav_wait < 240:
			await physics_frame
			nav_wait += 1

	await process_frame
	await physics_frame

	var rig: RtsCameraRig = main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var units: Array[Unit] = main.get_units()
	var leader_a: Unit = null
	var leader_b: Unit = null
	for u: Unit in units:
		if u.get_character_id() == &"leader_a":
			leader_a = u
		elif u.get_character_id() == &"leader_b":
			leader_b = u

	var selection_mgr: SelectionManager = main.get_selection_manager()
	var cmd_ctrl: CommandController = main.get_command_controller()
	var inventory: SettlementInventory = main.get_settlement_inventory()
	var pile_mgr: GroundPileManager = main.get_ground_pile_manager()
	var clock: EconomyClockController = main.get_economy_clock()
	var hud: ResourceHud = main.get_resource_hud()

	if leader_a == null or leader_b == null or selection_mgr == null or cmd_ctrl == null or inventory == null or clock == null:
		push_error("MainScene missing required T2 nodes for benchmark.")
		quit(1)
		return

	var sources: Array[ResourceSource] = test_map.get_resource_sources() if test_map != null else []
	if sources.is_empty():
		push_error("TestMap has zero ResourceSource nodes.")
		quit(1)
		return

	# Seed small initial piles so physical camp geometry + active decay are already present,
	# while keeping workers gathering real resources throughout warmup + measurement.
	inventory.deposit(&"food", 8)
	inventory.deposit(&"wood", 6)
	inventory.deposit(&"stone", 3)

	_prev_stock = _snapshot_stock(inventory)
	inventory.inventory_changed.connect(_on_inventory_changed.bind(inventory))
	clock.set_time_scale(DECAY_TIME_SCALE)
	clock.decay_stepped.connect(_on_decay_stepped)

	var a_source_cursor: int = 0
	var b_source_cursor: int = 2 % sources.size()
	_assign_worker_to_next_source(leader_a, selection_mgr, cmd_ctrl, sources, a_source_cursor)
	_assign_worker_to_next_source(leader_b, selection_mgr, cmd_ctrl, sources, b_source_cursor)
	selection_mgr.select_single(leader_a)

	# Warmup phase (excluded from stats)
	var warmup_start_usec: int = Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - warmup_start_usec) / 1000000.0 < _warmup_sec:
		await process_frame
		if leader_a.get_state() == Unit.State.IDLE:
			a_source_cursor = (a_source_cursor + 1) % sources.size()
			_assign_worker_to_next_source(leader_a, selection_mgr, cmd_ctrl, sources, a_source_cursor)
		if leader_b.get_state() == Unit.State.IDLE:
			b_source_cursor = (b_source_cursor + 1) % sources.size()
			_assign_worker_to_next_source(leader_b, selection_mgr, cmd_ctrl, sources, b_source_cursor)

	# Reset counters after warmup before recording window
	_delivery_events = 0
	_decay_steps = 0
	_decay_units_total = 0
	_prev_stock = _snapshot_stock(inventory)
	_recording = true

	var stockpile_panel: SettlementStockpilePanel = hud.get_stockpile_panel() if hud != null else null
	var unit_panel: SelectedUnitPanel = hud.get_selected_unit_panel() if hud != null else null
	var stockpile_applies_start: int = stockpile_panel.get_apply_count() if stockpile_panel != null else 0
	var unit_applies_start: int = unit_panel.get_apply_count() if unit_panel != null else 0

	var frame_times_ms: Array[float] = []
	var gt_16_7: int = 0
	var gt_33_3: int = 0
	var gt_100: int = 0

	var measure_start_usec: int = Time.get_ticks_usec()
	var prev_usec: int = measure_start_usec
	var last_hud_cycle_sec: float = 0.0
	var hud_cycle_idx: int = 0

	while true:
		await process_frame
		var now_usec: int = Time.get_ticks_usec()
		var dt_ms: float = float(now_usec - prev_usec) / 1000.0
		prev_usec = now_usec
		var elapsed_sec: float = float(now_usec - measure_start_usec) / 1000000.0

		frame_times_ms.append(dt_ms)
		if dt_ms > FRAME_BUDGET_MS:
			gt_16_7 += 1
		if dt_ms > FRAME_30FPS_MS:
			gt_33_3 += 1
		if dt_ms > FRAME_SPIKE_MS:
			gt_100 += 1

		var reselected: bool = false
		if leader_a.get_state() == Unit.State.IDLE:
			a_source_cursor = (a_source_cursor + 1) % sources.size()
			_assign_worker_to_next_source(leader_a, selection_mgr, cmd_ctrl, sources, a_source_cursor)
			reselected = true
		if leader_b.get_state() == Unit.State.IDLE:
			b_source_cursor = (b_source_cursor + 1) % sources.size()
			_assign_worker_to_next_source(leader_b, selection_mgr, cmd_ctrl, sources, b_source_cursor)
			reselected = true

		# Periodically rotate selection (leader_a -> leader_b -> multi -> leader_a)
		# and exercise smooth camera zoom so HUD and camera pipelines remain active.
		if reselected or (elapsed_sec - last_hud_cycle_sec) >= 4.0:
			if (elapsed_sec - last_hud_cycle_sec) >= 4.0:
				last_hud_cycle_sec = elapsed_sec
				hud_cycle_idx = (hud_cycle_idx + 1) % 3
				if rig != null:
					rig.zoom_by(-0.25 if (hud_cycle_idx % 2 == 0) else 0.25)
			match hud_cycle_idx:
				0:
					selection_mgr.select_single(leader_a)
				1:
					selection_mgr.select_single(leader_b)
				_:
					selection_mgr.select_single(leader_a)
					selection_mgr.add_unit(leader_b)

		if elapsed_sec >= _duration_sec:
			break

	_recording = false
	var actual_duration_sec: float = float(Time.get_ticks_usec() - measure_start_usec) / 1000000.0

	var stockpile_applies_delta: int = (stockpile_panel.get_apply_count() - stockpile_applies_start) if stockpile_panel != null else 0
	var unit_applies_delta: int = (unit_panel.get_apply_count() - unit_applies_start) if unit_panel != null else 0

	var sorted_ms: Array[float] = frame_times_ms.duplicate()
	sorted_ms.sort()

	var sum_ms: float = 0.0
	for ms: float in sorted_ms:
		sum_ms += ms

	var count: int = sorted_ms.size()
	var avg_ms: float = sum_ms / float(maxi(1, count))
	var avg_fps: float = (1000.0 / avg_ms) if avg_ms > 0.0 else 0.0
	var min_ms: float = sorted_ms[0] if count > 0 else 0.0
	var max_ms: float = sorted_ms[count - 1] if count > 0 else 0.0
	var p50_ms: float = _percentile(sorted_ms, 0.50)
	var p95_ms: float = _percentile(sorted_ms, 0.95)
	var p99_ms: float = _percentile(sorted_ms, 0.99)

	var win_size: Vector2i = DisplayServer.window_get_size()
	var vsync_mode: DisplayServer.VSyncMode = DisplayServer.window_get_vsync_mode()
	var ver: Dictionary = Engine.get_version_info()
	var result: Dictionary = {
		"benchmark": "t2_representative",
		"run_index": _run_index,
		"resolution_label": _resolution_label if not _resolution_label.is_empty() else ("%dx%d" % [win_size.x, win_size.y]),
		"window_size": [win_size.x, win_size.y],
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"gpu_adapter": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"os": OS.get_name(),
		"godot_version": "%s.%s.%s" % [str(ver.get("major", 0)), str(ver.get("minor", 0)), str(ver.get("patch", 0))],
		"vsync_mode": int(vsync_mode),
		"vsync_disabled": vsync_mode == DisplayServer.VSYNC_DISABLED,
		"warmup_sec": _warmup_sec,
		"duration_sec": snappedf(actual_duration_sec, 0.001),
		"decay_time_scale": DECAY_TIME_SCALE,
		"frame_count": count,
		"avg_frame_ms": snappedf(avg_ms, 0.001),
		"avg_fps": snappedf(avg_fps, 0.01),
		"min_frame_ms": snappedf(min_ms, 0.001),
		"p50_ms": snappedf(p50_ms, 0.001),
		"p95_ms": snappedf(p95_ms, 0.001),
		"p99_ms": snappedf(p99_ms, 0.001),
		"max_frame_ms": snappedf(max_ms, 0.001),
		"frames_gt_16_7ms": gt_16_7,
		"frames_gt_33_3ms": gt_33_3,
		"frames_gt_100ms": gt_100,
		"passed_p95": p95_ms <= 16.7 and gt_100 == 0,
		"economy_metrics": {
			"delivery_events": _delivery_events,
			"decay_steps": _decay_steps,
			"decay_units_total": _decay_units_total,
			"final_stock": _snapshot_stock(inventory),
			"active_pile_count": pile_mgr.get_piles().size() if pile_mgr != null else 0,
			"hud_stockpile_applies": stockpile_applies_delta,
			"hud_selected_unit_applies": unit_applies_delta,
		},
	}

	var json_str: String = JSON.stringify(result)
	print("[T2_PERF_RESULT] %s" % json_str)

	if not _output_json_path.is_empty():
		var abs_path: String = ProjectSettings.globalize_path(_output_json_path) if _output_json_path.begins_with("res://") else _output_json_path
		var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(result, "  "))
			f.close()

	main.queue_free()
	await process_frame
	quit(0)


func _assign_worker_to_next_source(
	worker: Unit,
	selection_mgr: SelectionManager,
	cmd_ctrl: CommandController,
	sources: Array[ResourceSource],
	start_idx: int
) -> bool:
	if worker == null or sources.is_empty():
		return false
	for offset: int in range(sources.size()):
		var src: ResourceSource = sources[(start_idx + offset) % sources.size()]
		if is_instance_valid(src) and src.get_remaining_amount() > 0:
			selection_mgr.select_single(worker)
			var pick: PickResult = PickResult.from_resource_source(src, src.global_position, Vector3.UP)
			if cmd_ctrl.command_at(pick):
				return true
	return false


func _on_inventory_changed(inventory: SettlementInventory) -> void:
	if not _recording:
		_prev_stock = _snapshot_stock(inventory)
		return
	var current: Dictionary = _snapshot_stock(inventory)
	var increased: bool = false
	for key: String in ["wood", "stone", "food"]:
		if int(current.get(key, 0)) > int(_prev_stock.get(key, 0)):
			increased = true
	if increased:
		_delivery_events += 1
	_prev_stock = current


func _on_decay_stepped(losses: Dictionary) -> void:
	if not _recording or losses.is_empty():
		return
	_decay_steps += 1
	for k: Variant in losses.keys():
		_decay_units_total += maxi(0, int(losses[k]))


func _snapshot_stock(inventory: SettlementInventory) -> Dictionary:
	return {
		"wood": inventory.get_amount(&"wood"),
		"stone": inventory.get_amount(&"stone"),
		"food": inventory.get_amount(&"food"),
	}


func _percentile(sorted_values: Array[float], q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	if sorted_values.size() == 1:
		return sorted_values[0]
	var pos: float = clampf(q, 0.0, 1.0) * float(sorted_values.size() - 1)
	var lo: int = int(floor(pos))
	var hi: int = int(ceil(pos))
	var frac: float = pos - float(lo)
	return lerpf(sorted_values[lo], sorted_values[hi], frac)
