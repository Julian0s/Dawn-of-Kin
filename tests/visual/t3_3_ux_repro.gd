extends SceneTree
## Visual rendered reproduction & verification runner for T3.3-UX:
## - Dynamic resolution switching (1280x720 -> 1920x1080 -> 1280x720) during active transport
## - Temporary C4 workers (Worker3, Worker4) spawn/no-dup/safe-removal
## - Full D9 C4-A..C4-E sequence with real viewport PNGs and JSON/JSONL logs.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const EVIDENCE_DIR_RES: String = "res://docs/testing/evidence/t3_3_ux"

var _log_lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var res_label: String = _parse_resolution_tag()
	var out_dir_abs: String = ProjectSettings.globalize_path(EVIDENCE_DIR_RES)
	var shots_dir_abs: String = out_dir_abs.path_join(res_label)
	DirAccess.make_dir_recursive_absolute(shots_dir_abs)

	var main_scene: MainScene = MAIN_SCENE.instantiate() as MainScene
	main_scene.use_provenance_economy = false
	root.add_child(main_scene)
	await process_frame
	await physics_frame

	var test_map: TestMap = main_scene.get_node("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation()
	var deadline_msec: int = Time.get_ticks_msec() + 10000
	while not nav.is_navigation_ready() and Time.get_ticks_msec() < deadline_msec:
		await physics_frame

	var gpm: GroundPileManager = main_scene._ground_pile_manager
	gpm.deposit(&"wood", 16)
	gpm.deposit(&"stone", 8)

	var units_root: Node3D = main_scene.get_node("Units") as Node3D
	var overlay: PlacementTestOverlay = main_scene.get_node("UiLayer/PlacementTestOverlay") as PlacementTestOverlay
	var construction_mgr: ConstructionManager = main_scene.get_node("ConstructionManager") as ConstructionManager
	var selection_mgr: SelectionManager = main_scene.get_node("SelectionManager") as SelectionManager
	var command_ctrl: CommandController = main_scene.get_node("CommandController") as CommandController
	var camera_rig: RtsCameraRig = main_scene.get_node("RtsCameraRig") as RtsCameraRig
	var leader_a: Unit = units_root.get_node("LeaderA") as Unit
	var leader_b: Unit = units_root.get_node("LeaderB") as Unit

	# 1. Spawn Worker3 & Worker4 via overlay button + duplicate guard check
	overlay.get_add_c4_workers_button().pressed.emit()
	await process_frame
	await physics_frame
	var w3: Unit = units_root.get_node_or_null("Worker3") as Unit
	var w4: Unit = units_root.get_node_or_null("Worker4") as Unit
	var spawn_count_after_first: int = units_root.get_child_count()
	var dup_res: Dictionary = overlay.get_temporary_workers_controller().spawn_temporary_workers()
	var spawn_count_after_dup: int = units_root.get_child_count()

	var site_res: Dictionary = construction_mgr.try_create_site_from_placement(
		MainScene.SHELTER_BASIC_DEFINITION,
		Vector3(-6.0, 0.0, 2.0)
	)
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	overlay.set_inspected_site(site)
	camera_rig.set_focus_position(Vector2(-2.5, 1.5))
	await _wait_render_frames(4)

	_log_event("c4_setup", {
		"resolution_tag": res_label,
		"units_count": spawn_count_after_first,
		"dup_rejected": not bool(dup_res.get("ok", true)),
		"units_count_after_dup": spawn_count_after_dup,
		"site_id": String(site.site_id),
		"window_size": [root.size.x, root.size.y],
	})
	await _capture_png(shots_dir_abs.path_join("01_four_workers_and_site.png"))

	# 2. C4-A: 1 worker
	command_ctrl.command_units_to_site(site, [leader_a])
	await _wait_render_frames(6)
	_log_event("c4_a", _snapshot_site_and_units(site, [leader_a, leader_b, w3, w4]))
	await _capture_png(shots_dir_abs.path_join("02_c4_a_one_worker.png"))

	# 3. C4-B: 2 workers
	command_ctrl.command_units_to_site(site, [leader_b])
	await _wait_render_frames(6)
	_log_event("c4_b", _snapshot_site_and_units(site, [leader_a, leader_b, w3, w4]))
	await _capture_png(shots_dir_abs.path_join("03_c4_b_two_workers.png"))

	# 4. C4-C: 3 workers
	command_ctrl.command_units_to_site(site, [w3])
	await _wait_render_frames(8)
	_log_event("c4_c", _snapshot_site_and_units(site, [leader_a, leader_b, w3, w4]))
	await _capture_png(shots_dir_abs.path_join("04_c4_c_three_workers.png"))

	# 5. Live resolution switches while active transport + site panel open + 4 workers visible
	selection_mgr.select_single(w4)
	var scene_id_before: int = main_scene.get_instance_id()
	var site_id_before: int = site.get_instance_id()
	var res_1080: Dictionary = overlay.apply_test_resolution(DisplayResolutionService.PRESET_1920X1080)
	await _wait_render_frames(6)
	_log_event("resolution_switch_1080", {
		"ok": bool(res_1080.get("ok", false)),
		"effective_size": [root.size.x, root.size.y],
		"was_clamped": bool(res_1080.get("was_clamped", false)),
		"status_text": overlay.get_resolution_status_text(),
		"scene_id_preserved": main_scene.get_instance_id() == scene_id_before,
		"site_id_preserved": site.get_instance_id() == site_id_before,
	})
	await _capture_png(shots_dir_abs.path_join("05_mid_transport_1920x1080_target.png"))

	var res_720: Dictionary = overlay.apply_test_resolution(DisplayResolutionService.PRESET_1280X720)
	await _wait_render_frames(6)
	_log_event("resolution_switch_720", {
		"ok": bool(res_720.get("ok", false)),
		"effective_size": [root.size.x, root.size.y],
		"was_clamped": bool(res_720.get("was_clamped", false)),
		"status_text": overlay.get_resolution_status_text(),
		"scene_id_preserved": main_scene.get_instance_id() == scene_id_before,
		"site_id_preserved": site.get_instance_id() == site_id_before,
		"selection_preserved": selection_mgr.get_selected_units() == [w4],
	})

	# 6. C4-D: attempt to assign 4th worker (Worker4) -> rejected with banner
	var c4_d_ok: bool = command_ctrl.command_units_to_site(site, [w4])
	var c4_d_reason: String = command_ctrl.get_last_command_reason()
	await _wait_render_frames(4)
	_log_event("c4_d", {
		"accepted": c4_d_ok,
		"reason": command_ctrl.get_last_command_reason(),
		"status_title": overlay.get_status_title_text(),
		"status_detail": overlay.get_status_detail_text(),
		"snapshot": _snapshot_site_and_units(site, [leader_a, leader_b, w3, w4]),
	})
	await _capture_png(shots_dir_abs.path_join("06_c4_d_fourth_rejected.png"))

	# 7. C4-E: interrupt active transporter -> builder promotes -> full supply
	var active_transporter: Unit = null
	for entry: Dictionary in site.get_assigned_worker_entries():
		if int(entry["role"]) == int(ConstructionSite.WorkerRole.TRANSPORTER):
			active_transporter = entry["unit"] as Unit
			break
	if active_transporter != null:
		selection_mgr.select_single(active_transporter)
		command_ctrl.command_at(PickResult.from_ground(Vector3(-14.0, 0.0, 8.0), Vector3.UP))

	await _wait_render_frames(6)
	_log_event("c4_e_promoted", _snapshot_site_and_units(site, [leader_a, leader_b, w3, w4]))

	Engine.time_scale = 3.0
	var supply_deadline: int = Time.get_ticks_msec() + 18000
	while not site.is_fully_supplied() and Time.get_ticks_msec() < supply_deadline:
		if active_transporter != null and active_transporter.get_state() == Unit.State.IDLE and not active_transporter.get_carry_load().is_empty():
			# If the interrupted transporter already withdrew cargo before interruption, resume delivery so 100% of reserved materials reach the site without loss.
			command_ctrl.command_units_to_site(site, [active_transporter])
		await physics_frame
	Engine.time_scale = 1.0
	await _wait_render_frames(4)

	_log_event("c4_e_final", _snapshot_site_and_units(site, [leader_a, leader_b, w3, w4]))
	await _capture_png(shots_dir_abs.path_join("07_c4_e_promoted_and_supplied.png"))

	# 8. Safe removal of Worker3 & Worker4 after completion
	var remove_res: Dictionary = overlay.get_temporary_workers_controller().remove_temporary_workers_safely()
	await process_frame
	_log_event("c4_cleanup", {
		"remove_ok": bool(remove_res.get("ok", false)),
		"units_count_after_remove": units_root.get_child_count(),
	})

	var summary := {
		"resolution_tag": res_label,
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"passed": (
			spawn_count_after_first == 4
			and spawn_count_after_dup == 4
			and not bool(dup_res.get("ok", true))
			and not c4_d_ok
			and c4_d_reason == ConstructOrder.REASON_NO_WORKER_SLOT
			and site.is_fully_supplied()
			and site.get_delivered_buffer_amount(&"wood") == 12
			and site.get_delivered_buffer_amount(&"stone") == 6
			and bool(remove_res.get("ok", false))
			and units_root.get_child_count() == 2
		),
		"delivered": site.get_delivered_buffer_amounts(),
		"c4_d_reason": c4_d_reason,
		"units_count_after_remove": units_root.get_child_count(),
		"resolution_1080_switch": res_1080,
		"resolution_720_switch": res_720,
	}

	var summary_file := FileAccess.open(out_dir_abs.path_join("summary_%s.json" % res_label), FileAccess.WRITE)
	if summary_file != null:
		summary_file.store_string(JSON.stringify(summary, "\t"))
		summary_file.close()

	var log_file := FileAccess.open(out_dir_abs.path_join("telemetry_%s.jsonl" % res_label), FileAccess.WRITE)
	if log_file != null:
		log_file.store_string("\n".join(_log_lines) + "\n")
		log_file.close()

	print("T3_3_UX_REPRO_RESULT " + JSON.stringify(summary))
	main_scene.queue_free()
	await process_frame
	quit(0 if bool(summary["passed"]) else 1)


func _snapshot_site_and_units(site: ConstructionSite, units: Array[Unit]) -> Dictionary:
	var snap: Dictionary = site.get_status_snapshot()
	var unit_rows: Array[Dictionary] = []
	for u: Unit in units:
		if u == null or not is_instance_valid(u):
			continue
		var carry: UnitCarryLoad = u.get_carry_load()
		unit_rows.append({
			"name": String(u.name),
			"state": u.get_state_name(),
			"pos": [snappedf(u.global_position.x, 0.01), snappedf(u.global_position.y, 0.01), snappedf(u.global_position.z, 0.01)],
			"carry": carry.get_all_amounts() if carry != null else {},
		})
	var worker_roles: Array[Dictionary] = []
	for entry: Dictionary in site.get_assigned_worker_entries():
		worker_roles.append({
			"name": str(entry.get("name", "")),
			"role": str(entry.get("role_label", "")),
		})
	return {
		"is_fully_supplied": bool(snap.get("is_fully_supplied", false)),
		"delivered": snap.get("delivered_buffer", {}),
		"reserved": snap.get("reserved_in_piles", {}),
		"in_transit": snap.get("in_transit", {}),
		"worker_roles": worker_roles,
		"units": unit_rows,
	}


func _log_event(event_name: String, data: Dictionary) -> void:
	_log_lines.append(JSON.stringify({"event": event_name, "msec": Time.get_ticks_msec(), "data": data}))


func _capture_png(abs_path: String) -> void:
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(abs_path)


func _wait_render_frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _parse_resolution_tag() -> String:
	var sz: Vector2i = root.size
	return "%dx%d" % [sz.x, sz.y]
