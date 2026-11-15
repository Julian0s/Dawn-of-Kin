extends SceneTree
## T3.3-R2 real rendered Godot diagnostic & visual reproduction runner.
## Executes Scenarios A, B, C, D, E in MainScene + TestMap without --headless,
## records structured JSONL telemetry (worker velocity/path/collisions & site ledger),
## and captures real PNG viewport screenshots at all key lifecycle moments.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")

const MAX_NAV_WAIT_FRAMES: int = 240
const MAX_SIM_FRAMES_PER_PHASE: int = 2400
const TELEMETRY_SAMPLE_INTERVAL: int = 4

const POS_SCENARIO_A := Vector3(-6.0, 0.0, 1.5)
const POS_SCENARIO_B := Vector3(18.5, 2.0, -14.0)
const POS_SCENARIO_C := Vector3(15.2, 2.0, -11.2)
const POS_SCENARIO_D_SITE := Vector3(17.5, 2.0, -14.0)
const POS_SCENARIO_D_LATERAL := Vector3(9.5, 0.0, -9.8)

var _mode: String = "pre_fix"
var _resolution_tag: String = "1280x720"
var _scenario_filter: String = "all"
var _evidence_root_rel: String = "res://docs/testing/evidence/t3_3_r2_plateau"
var _telemetry_file: FileAccess = null
var _captured_moments: Dictionary = {}


func _initialize() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.substr("--mode=".length()).strip_edges()
		elif arg.begins_with("--res="):
			_resolution_tag = arg.substr("--res=".length()).strip_edges()
		elif arg.begins_with("--scenario="):
			_scenario_filter = arg.substr("--scenario=".length()).strip_edges().to_upper()
		elif arg.begins_with("--out="):
			_evidence_root_rel = arg.substr("--out=".length()).strip_edges()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.physics_ticks_per_second = 60

	var root_abs: String = ProjectSettings.globalize_path(_evidence_root_rel)
	var dir_err: Error = DirAccess.make_dir_recursive_absolute(root_abs)
	if dir_err != OK:
		push_error("Failed to create evidence directory '%s': %s" % [root_abs, error_string(dir_err)])
		quit(1)
		return

	var gdignore_path: String = root_abs.path_join(".gdignore")
	if not FileAccess.file_exists(gdignore_path):
		var ig: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if ig != null:
			ig.close()

	var shot_dir_abs: String = root_abs.path_join("%s/%s" % [_resolution_tag, _mode])
	DirAccess.make_dir_recursive_absolute(shot_dir_abs)

	var telemetry_name: String = "%s_telemetry.jsonl" % _mode if _resolution_tag == "1280x720" else "%s_telemetry_%s.jsonl" % [_mode, _resolution_tag]
	var telemetry_abs: String = root_abs.path_join(telemetry_name)
	_telemetry_file = FileAccess.open(telemetry_abs, FileAccess.WRITE)
	if _telemetry_file == null:
		push_error("Failed to open telemetry log '%s'" % telemetry_abs)
		quit(1)
		return

	var scenarios_to_run: Array[String] = _resolve_scenarios()
	var results: Dictionary = {}

	for sc: String in scenarios_to_run:
		var sc_res: Dictionary = {}
		match sc:
			"A":
				sc_res = await _run_scenario_a(shot_dir_abs)
			"B":
				sc_res = await _run_scenario_b(shot_dir_abs)
			"C":
				sc_res = await _run_scenario_c(shot_dir_abs)
			"D":
				sc_res = await _run_scenario_d(shot_dir_abs)
			"E":
				sc_res = await _run_scenario_e(shot_dir_abs)
		results[sc] = sc_res

	if _telemetry_file != null:
		_telemetry_file.close()
		_telemetry_file = null

	var summary: Dictionary = {
		"mode": _mode,
		"resolution": _resolution_tag,
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"scenarios": results,
		"captured_moments": _captured_moments,
	}
	var summary_abs: String = root_abs.path_join("%s_summary_%s.json" % [_mode, _resolution_tag])
	var sum_file: FileAccess = FileAccess.open(summary_abs, FileAccess.WRITE)
	if sum_file != null:
		sum_file.store_string(JSON.stringify(summary, "\t"))
		sum_file.close()

	print("T3_3_R2_REPRO_SUMMARY ", JSON.stringify(summary))
	quit(0)


func _resolve_scenarios() -> Array[String]:
	if _scenario_filter == "ALL" or _scenario_filter.is_empty():
		return ["A", "B", "C", "D", "E"]
	var list: Array[String] = []
	for part: String in _scenario_filter.split(","):
		var code: String = part.strip_edges().to_upper()
		if code in ["A", "B", "C", "D", "E"] and not list.has(code):
			list.append(code)
	if list.is_empty():
		return ["A", "B", "C", "D", "E"]
	return list


func _boot_fresh_main(focus_xz: Vector2, zoom_dist: float) -> Dictionary:
	var main_inst: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_inst)

	var test_map: TestMap = main_inst.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var rig: RtsCameraRig = main_inst.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false
		rig.set_focus_position(focus_xz)
		rig.set_target_zoom_distance(zoom_dist, true)

	var wait_frames: int = 0
	while nav != null and not nav.is_navigation_ready() and wait_frames < MAX_NAV_WAIT_FRAMES:
		await physics_frame
		wait_frames += 1

	for _f: int in range(6):
		await process_frame
		await physics_frame

	var debug_mesh := ImmediateMesh.new()
	var debug_mat := StandardMaterial3D.new()
	debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mat.vertex_color_use_as_albedo = true
	debug_mat.no_depth_test = false
	var debug_node := MeshInstance3D.new()
	debug_node.name = "R2DiagnosticOverlay"
	debug_node.mesh = debug_mesh
	debug_node.material_override = debug_mat
	debug_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main_inst.add_child(debug_node)

	var units: Array[Unit] = main_inst.get_units()
	var leader_a: Unit = units[0] if units.size() > 0 else null
	var leader_b: Unit = units[1] if units.size() > 1 else null
	var dbg_overlay: Control = main_inst.get_node_or_null("UiLayer/DebugOverlay") as Control
	if dbg_overlay != null:
		dbg_overlay.visible = false

	return {
		"main": main_inst,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"placement": main_inst.get_placement_controller(),
		"overlay": main_inst.get_placement_test_overlay(),
		"selection": main_inst.get_selection_manager(),
		"command": main_inst.get_command_controller(),
		"inventory": main_inst.get_settlement_inventory(),
		"cm": main_inst.get_construction_manager(),
		"leader_a": leader_a,
		"leader_b": leader_b,
		"debug_mesh": debug_mesh,
	}


func _teardown_main(ctx: Dictionary) -> void:
	var main_inst: MainScene = ctx.get("main") as MainScene
	if main_inst != null and is_instance_valid(main_inst):
		main_inst.queue_free()
	for _i: int in range(4):
		await process_frame
		await physics_frame


func _seed_camp_stock(ctx: Dictionary) -> void:
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	inventory.deposit(&"wood", 16)
	inventory.deposit(&"stone", 8)


func _place_site_via_controller(
	ctx: Dictionary,
	world_pos: Vector3,
	capture_preview_name: String = "",
	shot_dir_abs: String = ""
) -> Dictionary:
	var placement: PlacementController = ctx["placement"] as PlacementController
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var camera: Camera3D = ctx["camera"] as Camera3D
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var overlay: PlacementTestOverlay = ctx["overlay"] as PlacementTestOverlay

	rig.set_focus_position(Vector2(world_pos.x, world_pos.z))
	rig.set_target_zoom_distance(28.0, true)
	await process_frame
	await process_frame

	placement.start_placement(SHELTER_DEF)
	var vp_pt: Vector2 = camera.unproject_position(world_pos)
	var win_pt: Vector2 = _vp_to_window_pos(vp_pt)
	_push_mouse_motion(win_pt)
	await process_frame
	await process_frame

	var hover_res: PlacementValidator.ValidationResult = placement.get_last_hover_result()
	if hover_res == null:
		hover_res = placement.update_preview_at_world_pos(world_pos)
	if not capture_preview_name.is_empty():
		await _capture_png(shot_dir_abs, capture_preview_name)

	await _push_mouse_click(MOUSE_BUTTON_LEFT, win_pt)
	var frames: int = 0
	while placement.is_confirm_pending() and frames < 120:
		await process_frame
		frames += 1

	var confirm_res: PlacementValidator.ValidationResult = placement.get_last_confirm_result()
	if confirm_res == null and placement.is_placement_active():
		confirm_res = placement.confirm_at_world_pos(world_pos)
		frames = 0
		while placement.is_confirm_pending() and frames < 120:
			await process_frame
			frames += 1
		confirm_res = placement.get_last_confirm_result()
	var sites: Array[ConstructionSite] = cm.get_sites()
	var site: ConstructionSite = sites[sites.size() - 1] if not sites.is_empty() else null
	if site != null and overlay != null:
		overlay.set_inspected_site(site)

	await process_frame
	return {
		"hover_valid": hover_res != null and hover_res.valid,
		"hover_reason": str(hover_res.reason_code) if hover_res != null else "null",
		"confirm_valid": confirm_res != null and confirm_res.valid,
		"confirm_reason": str(confirm_res.reason_code) if confirm_res != null else "null",
		"site": site,
	}


func _assign_workers_via_rmb(ctx: Dictionary, site: ConstructionSite, workers: Array[Unit]) -> bool:
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var camera: Camera3D = ctx["camera"] as Camera3D
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cmd: CommandController = ctx["command"] as CommandController
	var site_pos: Vector3 = site.global_position

	rig.set_focus_position(Vector2(site_pos.x, site_pos.z))
	rig.set_target_zoom_distance(28.0, true)
	await process_frame
	await process_frame

	selection.set_selection(workers)
	var vp_pt: Vector2 = camera.unproject_position(site_pos + Vector3(0.0, 0.2, 0.0))
	await _push_mouse_click(MOUSE_BUTTON_RIGHT, _vp_to_window_pos(vp_pt))
	await physics_frame

	var all_assigned: bool = true
	for u: Unit in workers:
		var order: UnitOrder = u.get_current_order()
		if not (order is ConstructOrder):
			all_assigned = false
	if not all_assigned and cmd != null:
		cmd.command_units_to_site(site, workers)
		await physics_frame
		all_assigned = true
		for u: Unit in workers:
			if not (u.get_current_order() is ConstructOrder):
				all_assigned = false
	return all_assigned


func _vp_to_window_pos(vp_pos: Vector2) -> Vector2:
	var vp_size: Vector2 = root.get_visible_rect().size
	var win_size: Vector2 = Vector2(DisplayServer.window_get_size())
	if vp_size.x <= 1.0 or vp_size.y <= 1.0 or win_size.x <= 1.0 or win_size.y <= 1.0:
		return vp_pos
	return Vector2(vp_pos.x * (win_size.x / vp_size.x), vp_pos.y * (win_size.y / vp_size.y))


func _push_mouse_motion(screen_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen_pos
	ev.global_position = screen_pos
	root.push_input(ev, false)


func _push_mouse_click(button: MouseButton, screen_pos: Vector2) -> void:
	_push_mouse_motion(screen_pos)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = screen_pos
	press.global_position = screen_pos
	root.push_input(press, false)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = screen_pos
	release.global_position = screen_pos
	root.push_input(release, false)
	await process_frame
	await process_frame


func _capture_png(shot_dir_abs: String, filename: String) -> String:
	for _i: int in range(3):
		await process_frame
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("T3_3_R2: Empty viewport image for '%s'" % filename)
		return ""
	var out_abs: String = shot_dir_abs.path_join(filename)
	var err: Error = image.save_png(out_abs)
	if err != OK:
		push_error("T3_3_R2: Failed saving '%s': %s" % [out_abs, error_string(err)])
		return ""
	_captured_moments[filename] = out_abs
	return out_abs


func _draw_debug_overlay(ctx: Dictionary, site: ConstructionSite, workers: Array[Unit]) -> void:
	var mesh: ImmediateMesh = ctx.get("debug_mesh") as ImmediateMesh
	if mesh == null:
		return
	mesh.clear_surfaces()

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Highlight lateral edges of Terrain/Ramp (z = -12 South wall, z = -16 North wall) in orange-red.
	var ramp_col := Color(1.0, 0.35, 0.1, 1.0)
	mesh.surface_set_color(ramp_col)
	mesh.surface_add_vertex(Vector3(5.0, 0.08, -12.0))
	mesh.surface_add_vertex(Vector3(13.0, 2.08, -12.0))
	mesh.surface_set_color(ramp_col)
	mesh.surface_add_vertex(Vector3(5.0, 0.08, -16.0))
	mesh.surface_add_vertex(Vector3(13.0, 2.08, -16.0))

	# Draw active nav path & steer target for each worker in bright cyan/yellow.
	for u: Unit in workers:
		if u == null or not is_instance_valid(u):
			continue
		var mov: UnitMovement = u.get_movement()
		var path_var: Variant = mov.get("_active_path")
		if path_var is PackedVector3Array:
			var path: PackedVector3Array = path_var as PackedVector3Array
			for i: int in range(path.size() - 1):
				mesh.surface_set_color(Color(0.1, 0.95, 1.0, 1.0))
				mesh.surface_add_vertex(path[i] + Vector3(0.0, 0.15, 0.0))
				mesh.surface_set_color(Color(0.1, 0.95, 1.0, 1.0))
				mesh.surface_add_vertex(path[i + 1] + Vector3(0.0, 0.15, 0.0))
		var target_pt: Vector3 = mov.get_target_position()
		if target_pt.is_finite() and mov.get_move_state() == UnitMovement.MoveState.MOVING:
			mesh.surface_set_color(Color(1.0, 0.15, 0.9, 1.0))
			mesh.surface_add_vertex(target_pt + Vector3(-0.3, 0.25, -0.3))
			mesh.surface_add_vertex(target_pt + Vector3(0.3, 0.25, 0.3))
			mesh.surface_set_color(Color(1.0, 0.15, 0.9, 1.0))
			mesh.surface_add_vertex(target_pt + Vector3(-0.3, 0.25, 0.3))
			mesh.surface_add_vertex(target_pt + Vector3(0.3, 0.25, -0.3))

	if site != null and is_instance_valid(site):
		var r: Rect2 = site.get_footprint_rect()
		var sy: float = site.global_position.y + 0.12
		var c0 := Vector3(r.position.x, sy, r.position.y)
		var c1 := Vector3(r.end.x, sy, r.position.y)
		var c2 := Vector3(r.end.x, sy, r.end.y)
		var c3 := Vector3(r.position.x, sy, r.end.y)
		for seg: Array in [[c0, c1], [c1, c2], [c2, c3], [c3, c0]]:
			mesh.surface_set_color(Color(0.2, 1.0, 0.35, 1.0))
			mesh.surface_add_vertex(seg[0] as Vector3)
			mesh.surface_set_color(Color(0.2, 1.0, 0.35, 1.0))
			mesh.surface_add_vertex(seg[1] as Vector3)

	mesh.surface_end()


func _move_state_name(state: int) -> String:
	match state:
		UnitMovement.MoveState.IDLE:
			return "IDLE"
		UnitMovement.MoveState.MOVING:
			return "MOVING"
		UnitMovement.MoveState.ARRIVED:
			return "ARRIVED"
		UnitMovement.MoveState.FAILED_STUCK:
			return "FAILED_STUCK"
		UnitMovement.MoveState.FAILED_INVALID:
			return "FAILED_INVALID"
		_:
			return "UNKNOWN(%d)" % state


func _order_phase_name(order: UnitOrder) -> String:
	if not (order is ConstructOrder):
		return order.get_order_name() if order != null else "NONE"
	match (order as ConstructOrder).get_phase():
		ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO:
			return "RETURNING_UNNEEDED_CARGO"
		ConstructOrder.Phase.MOVING_TO_PILE:
			return "MOVING_TO_PILE"
		ConstructOrder.Phase.MOVING_TO_SITE_DROPOFF:
			return "MOVING_TO_SITE_DROPOFF"
		ConstructOrder.Phase.MOVING_TO_BUILDER_SLOT:
			return "MOVING_TO_BUILDER_SLOT"
		ConstructOrder.Phase.BUILDER_STANDBY:
			return "BUILDER_STANDBY"
		ConstructOrder.Phase.WAITING_FOR_PEER_SUPPLY:
			return "WAITING_FOR_PEER_SUPPLY"
		_:
			return "UNKNOWN"


func _order_status_name(order: UnitOrder) -> String:
	if order == null:
		return "NONE"
	match order.status:
		UnitOrder.Status.PENDING:
			return "PENDING"
		UnitOrder.Status.RUNNING:
			return "RUNNING"
		UnitOrder.Status.SUCCEEDED:
			return "SUCCEEDED"
		UnitOrder.Status.FAILED:
			return "FAILED"
		UnitOrder.Status.CANCELLED:
			return "CANCELLED"
		_:
			return "UNKNOWN"


func _vec3_arr(v: Vector3) -> Array[float]:
	if not v.is_finite():
		return [999999.0, 999999.0, 999999.0]
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func _dict_str_int(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d.keys():
		out[String(k)] = int(d[k])
	return out


func _record_telemetry(
	scenario_id: String,
	frame_idx: int,
	event_tag: String,
	ctx: Dictionary,
	site: ConstructionSite,
	workers: Array[Unit],
	tracked_orders: Dictionary,
	stats: Dictionary
) -> void:
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var nav_rev: int = nav.get_navigation_revision() if nav != null else -1

	var worker_records: Array[Dictionary] = []
	for u: Unit in workers:
		if u == null or not is_instance_valid(u):
			continue
		var uid: int = u.get_instance_id()
		var mov: UnitMovement = u.get_movement()
		var active_order: UnitOrder = u.get_current_order()
		if active_order == null and tracked_orders.has(uid):
			active_order = tracked_orders[uid] as UnitOrder

		var path_points: Array = []
		var path_len: float = 0.0
		var next_wp := Vector3(INF, INF, INF)
		var path_var: Variant = mov.get("_active_path")
		var path_idx: int = int(mov.get("_active_path_index"))
		if path_var is PackedVector3Array:
			var pv: PackedVector3Array = path_var as PackedVector3Array
			for i: int in range(pv.size()):
				path_points.append(_vec3_arr(pv[i]))
				if i > 0:
					path_len += pv[i - 1].distance_to(pv[i])
			if not pv.is_empty():
				next_wp = pv[clampi(path_idx, 0, pv.size() - 1)]

		var target_pos: Vector3 = mov.get_target_position()
		var steer_pt: Vector3 = next_wp if next_wp.is_finite() else target_pos
		var delta_xz := Vector2(steer_pt.x - u.global_position.x, steer_pt.z - u.global_position.z)
		var desired_vel := Vector3.ZERO
		var effective_vel := Vector3.ZERO
		if mov.get_move_state() == UnitMovement.MoveState.MOVING and delta_xz.length_squared() > 0.0001:
			var dir_xz: Vector2 = delta_xz.normalized()
			var t_spd: float = mov.get_target_move_speed()
			var e_spd: float = mov.get_effective_move_speed()
			desired_vel = Vector3(dir_xz.x * t_spd, 0.0, dir_xz.y * t_spd)
			effective_vel = Vector3(dir_xz.x * e_spd, 0.0, dir_xz.y * e_spd)

		var collisions: Array[Dictionary] = []
		var slide_count: int = u.get_slide_collision_count()
		for c_idx: int in range(slide_count):
			var kc: KinematicCollision3D = u.get_slide_collision(c_idx)
			if kc == null:
				continue
			var col_obj: Object = kc.get_collider()
			var col_name: String = str(col_obj.get("name")) if col_obj != null else "?"
			var col_layer: int = int(col_obj.get("collision_layer")) if (col_obj is CollisionObject3D) else 0
			var norm: Vector3 = kc.get_normal()
			collisions.append({
				"position": _vec3_arr(kc.get_position()),
				"normal": _vec3_arr(norm),
				"collider": col_name,
				"collider_layer": col_layer,
			})
			if (col_name == "Ramp" or col_name == "Plateau") and absf(norm.y) < 0.707:
				stats["lateral_wall_collisions"] = int(stats.get("lateral_wall_collisions", 0)) + 1
				var lateral_samples: Array = stats.get("lateral_samples", []) as Array
				if lateral_samples.size() < 25:
					lateral_samples.append({
						"frame": frame_idx,
						"unit": u.name,
						"unit_pos": _vec3_arr(u.global_position),
						"col_pos": _vec3_arr(kc.get_position()),
						"normal": _vec3_arr(norm),
						"collider": col_name,
						"target": _vec3_arr(target_pos),
					})
					stats["lateral_samples"] = lateral_samples

		worker_records.append({
			"unit_id": uid,
			"unit_name": u.name,
			"global_position": _vec3_arr(u.global_position),
			"desired_velocity": _vec3_arr(desired_vel),
			"effective_velocity": _vec3_arr(effective_vel),
			"applied_velocity": _vec3_arr(u.velocity),
			"is_on_floor": u.is_on_floor(),
			"move_state": _move_state_name(mov.get_move_state()),
			"order_phase": _order_phase_name(active_order),
			"order_status": _order_status_name(active_order),
			"failure_reason": active_order.failure_reason if active_order != null else "",
			"target_position": _vec3_arr(target_pos),
			"next_waypoint": _vec3_arr(next_wp),
			"nav_path": path_points,
			"nav_path_length": snappedf(path_len, 0.001),
			"nav_revision": nav_rev,
			"repath_attempts": mov.get_repath_attempts(),
			"no_progress_elapsed": snappedf(mov.get_no_progress_timer(), 0.001),
			"slide_collision_count": slide_count,
			"slide_collisions": collisions,
			"carry": _dict_str_int(u.get_carry_load().get_all_amounts()),
		})

	var site_record: Dictionary = {}
	if site != null and is_instance_valid(site):
		var roles: Dictionary = {}
		for entry: Dictionary in site.get_assigned_worker_entries():
			roles[str(entry.get("name", "?"))] = str(entry.get("role_label", "?"))
		var trips_total: int = 0
		for u_key: Variant in tracked_orders.keys():
			var o: UnitOrder = tracked_orders[u_key] as UnitOrder
			if o is ConstructOrder:
				trips_total += (o as ConstructOrder).trips_completed
		site_record = {
			"site_id": String(site.site_id),
			"site_position": _vec3_arr(site.global_position),
			"worker_roles": roles,
			"required_materials": _dict_str_int(site.get_required_amounts()),
			"reserved_materials": _dict_str_int(site.get_reserved_in_piles_amounts()),
			"in_transit_materials": _dict_str_int(site.get_in_transit_amounts()),
			"delivered_materials": _dict_str_int(site.get_delivered_buffer_amounts()),
			"missing_materials": _dict_str_int(site.get_missing_amounts()),
			"trips_completed": trips_total,
			"is_fully_supplied": site.is_fully_supplied(),
		}

	var rec: Dictionary = {
		"mode": _mode,
		"resolution": _resolution_tag,
		"scenario": scenario_id,
		"frame": frame_idx,
		"event": event_tag,
		"workers": worker_records,
		"site": site_record,
	}
	if _telemetry_file != null:
		_telemetry_file.store_line(JSON.stringify(rec))


func _run_scenario_a(shot_dir_abs: String) -> Dictionary:
	var ctx: Dictionary = await _boot_fresh_main(Vector2(-3.0, 1.0), 30.0)
	_seed_camp_stock(ctx)
	var place_res: Dictionary = await _place_site_via_controller(ctx, POS_SCENARIO_A)
	var site: ConstructionSite = place_res["site"] as ConstructionSite
	var leader_a: Unit = ctx["leader_a"] as Unit
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	rig.set_focus_position(Vector2(-3.0, 1.0))
	rig.set_target_zoom_distance(28.0, true)

	var stats: Dictionary = {"lateral_wall_collisions": 0, "lateral_samples": []}
	var tracked: Dictionary = {}
	if site == null or leader_a == null:
		await _teardown_main(ctx)
		return {
			"passed": false,
			"reason": "placement_failed",
			"hover_reason": place_res["hover_reason"],
			"confirm_reason": place_res["confirm_reason"],
		}

	await _assign_workers_via_rmb(ctx, site, [leader_a])
	tracked[leader_a.get_instance_id()] = leader_a.get_current_order()

	var frames: int = 0
	var failure_reason: String = ""
	while frames < MAX_SIM_FRAMES_PER_PHASE:
		await physics_frame
		frames += 1
		_draw_debug_overlay(ctx, site, [leader_a])
		if frames % TELEMETRY_SAMPLE_INTERVAL == 0:
			_record_telemetry("A", frames, "tick", ctx, site, [leader_a], tracked, stats)
		var ord: UnitOrder = tracked.get(leader_a.get_instance_id()) as UnitOrder
		if ord != null and ord.status == UnitOrder.Status.FAILED:
			failure_reason = ord.failure_reason
			_record_telemetry("A", frames, "order_failed", ctx, site, [leader_a], tracked, stats)
			break
		if site.is_fully_supplied() and (ord == null or ord.is_finished()):
			_record_telemetry("A", frames, "completed", ctx, site, [leader_a], tracked, stats)
			break

	await _capture_png(shot_dir_abs, "scenario_A_final.png")
	var ord_a_final: ConstructOrder = tracked.get(leader_a.get_instance_id()) as ConstructOrder
	var out: Dictionary = {
		"passed": site.is_fully_supplied() and failure_reason.is_empty(),
		"frames": frames,
		"delivered": _dict_str_int(site.get_delivered_buffer_amounts()),
		"trips_completed": ord_a_final.trips_completed if ord_a_final != null else 0,
		"failure_reason": failure_reason,
		"lateral_wall_collisions": int(stats["lateral_wall_collisions"]),
	}
	await _teardown_main(ctx)
	return out


func _run_scenario_b(shot_dir_abs: String) -> Dictionary:
	var ctx: Dictionary = await _boot_fresh_main(Vector2(10.0, -9.0), 34.0)
	_seed_camp_stock(ctx)
	var place_res: Dictionary = await _place_site_via_controller(ctx, POS_SCENARIO_B)
	var site: ConstructionSite = place_res["site"] as ConstructionSite
	var leader_a: Unit = ctx["leader_a"] as Unit
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	rig.set_focus_position(Vector2(10.5, -10.5))
	rig.set_target_zoom_distance(32.0, true)

	var stats: Dictionary = {"lateral_wall_collisions": 0, "lateral_samples": []}
	var tracked: Dictionary = {}
	if site == null or leader_a == null:
		await _teardown_main(ctx)
		return {
			"passed": false,
			"reason": "placement_failed",
			"hover_reason": place_res["hover_reason"],
			"confirm_reason": place_res["confirm_reason"],
		}

	await _assign_workers_via_rmb(ctx, site, [leader_a])
	tracked[leader_a.get_instance_id()] = leader_a.get_current_order()

	var frames: int = 0
	var failure_reason: String = ""
	var max_y_reached: float = 0.0
	var selected_slots: Array[Array] = []
	var prev_target := Vector3(INF, INF, INF)

	while frames < MAX_SIM_FRAMES_PER_PHASE:
		await physics_frame
		frames += 1
		max_y_reached = maxf(max_y_reached, leader_a.global_position.y)
		var mov: UnitMovement = leader_a.get_movement()
		var t_pos: Vector3 = mov.get_target_position()
		if t_pos.is_finite() and t_pos.distance_squared_to(prev_target) > 0.01:
			prev_target = t_pos
			selected_slots.append(_vec3_arr(t_pos))
		_draw_debug_overlay(ctx, site, [leader_a])
		if frames % TELEMETRY_SAMPLE_INTERVAL == 0:
			_record_telemetry("B", frames, "tick", ctx, site, [leader_a], tracked, stats)
		var ord: UnitOrder = tracked.get(leader_a.get_instance_id()) as UnitOrder
		if ord != null and ord.status == UnitOrder.Status.FAILED:
			failure_reason = ord.failure_reason
			_record_telemetry("B", frames, "order_failed", ctx, site, [leader_a], tracked, stats)
			break
		if site.is_fully_supplied() and (ord == null or ord.is_finished()):
			_record_telemetry("B", frames, "completed", ctx, site, [leader_a], tracked, stats)
			break

	rig.set_focus_position(Vector2(11.5, -13.0))
	rig.set_target_zoom_distance(28.0, true)
	await _capture_png(shot_dir_abs, "scenario_B_final.png")
	var ord_b_final: ConstructOrder = tracked.get(leader_a.get_instance_id()) as ConstructOrder
	var out: Dictionary = {
		"passed": site.is_fully_supplied() and failure_reason.is_empty(),
		"frames": frames,
		"delivered": _dict_str_int(site.get_delivered_buffer_amounts()),
		"trips_completed": ord_b_final.trips_completed if ord_b_final != null else 0,
		"failure_reason": failure_reason,
		"max_y_reached": snappedf(max_y_reached, 0.001),
		"selected_targets": selected_slots,
		"lateral_wall_collisions": int(stats["lateral_wall_collisions"]),
		"lateral_samples": stats["lateral_samples"],
	}
	await _teardown_main(ctx)
	return out


func _run_scenario_c(shot_dir_abs: String) -> Dictionary:
	# Plateau near ramp transition and South-West cliff edge: captures primary lifecycle PNGs 01..09.
	var ctx: Dictionary = await _boot_fresh_main(Vector2(11.5, -12.0), 28.0)
	_seed_camp_stock(ctx)
	var place_res: Dictionary = await _place_site_via_controller(
		ctx,
		POS_SCENARIO_C,
		"01_plateau_preview_valid.png",
		shot_dir_abs
	)
	var site: ConstructionSite = place_res["site"] as ConstructionSite
	var leader_a: Unit = ctx["leader_a"] as Unit
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig

	var stats: Dictionary = {"lateral_wall_collisions": 0, "lateral_samples": []}
	var tracked: Dictionary = {}
	if site == null or leader_a == null:
		await _capture_png(shot_dir_abs, "09_pre_fix_failure_state.png" if _mode == "pre_fix" else "scenario_C_final.png")
		await _teardown_main(ctx)
		return {
			"passed": false,
			"reason": "placement_failed",
			"hover_reason": place_res["hover_reason"],
			"confirm_reason": place_res["confirm_reason"],
		}

	await _capture_png(shot_dir_abs, "02_site_created.png")
	await _assign_workers_via_rmb(ctx, site, [leader_a])
	tracked[leader_a.get_instance_id()] = leader_a.get_current_order()

	var captured_03: bool = false
	var captured_04: bool = false
	var captured_05: bool = false
	var captured_06: bool = false
	var captured_07: bool = false
	var captured_08: bool = false

	var frames: int = 0
	var failure_reason: String = ""
	var max_y_reached: float = 0.0
	var selected_targets: Array[Array] = []
	var prev_target := Vector3(INF, INF, INF)
	var prev_trips: int = 0

	while frames < MAX_SIM_FRAMES_PER_PHASE:
		await physics_frame
		frames += 1
		var upos: Vector3 = leader_a.global_position
		max_y_reached = maxf(max_y_reached, upos.y)
		var mov: UnitMovement = leader_a.get_movement()
		var t_pos: Vector3 = mov.get_target_position()
		if t_pos.is_finite() and t_pos.distance_squared_to(prev_target) > 0.01:
			prev_target = t_pos
			selected_targets.append(_vec3_arr(t_pos))

		_draw_debug_overlay(ctx, site, [leader_a])
		var ord: ConstructOrder = tracked.get(leader_a.get_instance_id()) as ConstructOrder

		if not captured_03 and not leader_a.get_carry_load().is_empty():
			captured_03 = true
			_record_telemetry("C", frames, "03_pickup_start", ctx, site, [leader_a], tracked, stats)
			rig.set_focus_position(Vector2(2.0, -3.5))
			rig.set_target_zoom_distance(26.0, true)
			await _capture_png(shot_dir_abs, "03_pickup_start.png")

		if not captured_04 and not leader_a.get_carry_load().is_empty() and upos.z <= -8.0 and upos.x <= 8.5:
			captured_04 = true
			_record_telemetry("C", frames, "04_ramp_foot_approach", ctx, site, [leader_a], tracked, stats)
			rig.set_focus_position(Vector2(9.5, -13.0))
			rig.set_target_zoom_distance(24.0, true)
			await _capture_png(shot_dir_abs, "04_ramp_foot_approach.png")

		if not captured_05 and not leader_a.get_carry_load().is_empty() and (
			(upos.x >= 5.2 and upos.x <= 12.6 and upos.z <= -10.5 and upos.z >= -16.8 and upos.y >= 0.12)
			or int(stats["lateral_wall_collisions"]) >= 1
		):
			captured_05 = true
			_record_telemetry("C", frames, "05_ramp_climb", ctx, site, [leader_a], tracked, stats)
			rig.set_focus_position(Vector2(10.5, -13.2))
			rig.set_target_zoom_distance(24.0, true)
			await _capture_png(shot_dir_abs, "05_ramp_climb.png")

		if not captured_06 and upos.x >= 12.6 and upos.y >= 1.7:
			captured_06 = true
			_record_telemetry("C", frames, "06_plateau_top_entry", ctx, site, [leader_a], tracked, stats)
			rig.set_focus_position(Vector2(13.5, -12.8))
			rig.set_target_zoom_distance(24.0, true)
			await _capture_png(shot_dir_abs, "06_plateau_top_entry.png")

		if ord != null and ord.trips_completed >= 1 and prev_trips == 0:
			prev_trips = ord.trips_completed
			if not captured_07:
				captured_07 = true
				_record_telemetry("C", frames, "07_first_trip_delivery", ctx, site, [leader_a], tracked, stats)
				rig.set_focus_position(Vector2(14.0, -12.0))
				rig.set_target_zoom_distance(25.0, true)
				await _capture_png(shot_dir_abs, "07_first_trip_delivery.png")

		if ord != null and ord.trips_completed >= 1 and not captured_08 and not leader_a.get_carry_load().is_empty() and upos.z <= -7.0:
			captured_08 = true
			_record_telemetry("C", frames, "08_subsequent_trips", ctx, site, [leader_a], tracked, stats)
			rig.set_focus_position(Vector2(10.5, -12.5))
			rig.set_target_zoom_distance(27.0, true)
			await _capture_png(shot_dir_abs, "08_subsequent_trips.png")

		if frames % TELEMETRY_SAMPLE_INTERVAL == 0:
			_record_telemetry("C", frames, "tick", ctx, site, [leader_a], tracked, stats)

		if ord != null and ord.status == UnitOrder.Status.FAILED:
			failure_reason = ord.failure_reason
			_record_telemetry("C", frames, "order_failed", ctx, site, [leader_a], tracked, stats)
			break
		if site.is_fully_supplied() and (ord == null or ord.is_finished()):
			_record_telemetry("C", frames, "completed", ctx, site, [leader_a], tracked, stats)
			break

	rig.set_focus_position(Vector2(12.0, -12.5))
	rig.set_target_zoom_distance(26.0, true)
	if _mode == "pre_fix" and (not site.is_fully_supplied() or not failure_reason.is_empty()):
		await _capture_png(shot_dir_abs, "09_pre_fix_failure_state.png")
	await _capture_png(shot_dir_abs, "scenario_C_final.png")
	var ord_c_final: ConstructOrder = tracked.get(leader_a.get_instance_id()) as ConstructOrder

	var out: Dictionary = {
		"passed": site.is_fully_supplied() and failure_reason.is_empty(),
		"frames": frames,
		"delivered": _dict_str_int(site.get_delivered_buffer_amounts()),
		"trips_completed": ord_c_final.trips_completed if ord_c_final != null else 0,
		"failure_reason": failure_reason,
		"final_unit_pos": _vec3_arr(leader_a.global_position),
		"max_y_reached": snappedf(max_y_reached, 0.001),
		"selected_targets": selected_targets,
		"lateral_wall_collisions": int(stats["lateral_wall_collisions"]),
		"lateral_samples": stats["lateral_samples"],
	}
	await _teardown_main(ctx)
	return out


func _run_scenario_d(shot_dir_abs: String) -> Dictionary:
	# Forced lateral approach South of ramp (9.5, 0.0, -9.8) heading to plateau site (15.8, 2.0, -14.0).
	var ctx: Dictionary = await _boot_fresh_main(Vector2(10.0, -11.5), 26.0)
	_seed_camp_stock(ctx)
	var place_res: Dictionary = await _place_site_via_controller(ctx, POS_SCENARIO_D_SITE)
	var site: ConstructionSite = place_res["site"] as ConstructionSite
	var leader_a: Unit = ctx["leader_a"] as Unit
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cmd: CommandController = ctx["command"] as CommandController
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation

	var stats: Dictionary = {"lateral_wall_collisions": 0, "lateral_samples": []}
	var tracked: Dictionary = {}
	if site == null or leader_a == null:
		await _teardown_main(ctx)
		return {
			"passed": false,
			"reason": "placement_failed",
			"hover_reason": place_res["hover_reason"],
			"confirm_reason": place_res["confirm_reason"],
		}

	# First verify direct path from (9.5, 0.0, -9.8) -> (15.8, 2.0, -14.0) and MoveOrder climb.
	leader_a.global_position = POS_SCENARIO_D_LATERAL
	await physics_frame
	var path_check: WorldNavigation.PathResult = nav.find_path(POS_SCENARIO_D_LATERAL, Vector3(13.8, 2.0, -14.0))
	var path_crosses_lateral_wall: bool = false
	var min_x_along_path: float = 999.0
	var path_pts_d: Array = []
	for pt: Vector3 in path_check.path:
		path_pts_d.append(_vec3_arr(pt))
		min_x_along_path = minf(min_x_along_path, pt.x)
		if pt.x > 5.4 and pt.z >= -12.35 and pt.z <= -11.35 and pt.y < 0.7:
			path_crosses_lateral_wall = true

	var move_ord := MoveOrder.new(Vector3(13.8, 2.0, -14.0))
	leader_a.issue_order(move_ord)
	tracked[leader_a.get_instance_id()] = move_ord

	rig.set_focus_position(Vector2(9.5, -12.5))
	rig.set_target_zoom_distance(25.0, true)

	var frames: int = 0
	var move_failed_reason: String = ""
	var unit_min_x_detour: float = leader_a.global_position.x
	var captured_d_moment: bool = false
	while frames < 900:
		await physics_frame
		frames += 1
		unit_min_x_detour = minf(unit_min_x_detour, leader_a.global_position.x)
		_draw_debug_overlay(ctx, site, [leader_a])
		if frames % TELEMETRY_SAMPLE_INTERVAL == 0:
			_record_telemetry("D", frames, "lateral_move_tick", ctx, site, [leader_a], tracked, stats)
		if not captured_d_moment:
			if _mode == "pre_fix" and int(stats["lateral_wall_collisions"]) >= 1:
				captured_d_moment = true
				_record_telemetry("D", frames, "09_pre_fix_lateral_wall_impact", ctx, site, [leader_a], tracked, stats)
				rig.set_focus_position(Vector2(7.5, -12.2))
				rig.set_target_zoom_distance(18.0, true)
				await _capture_png(shot_dir_abs, "09_pre_fix_failure_state.png")
			elif _mode == "post_fix" and leader_a.global_position.x <= 5.5 and leader_a.global_position.z <= -11.0:
				captured_d_moment = true
				_record_telemetry("D", frames, "post_fix_detour_ramp_foot", ctx, site, [leader_a], tracked, stats)
				rig.set_focus_position(Vector2(7.2, -13.0))
				rig.set_target_zoom_distance(22.0, true)
				await _capture_png(shot_dir_abs, "scenario_D_detour.png")
		if move_ord.status == UnitOrder.Status.FAILED:
			move_failed_reason = move_ord.failure_reason
			_record_telemetry("D", frames, "lateral_move_failed", ctx, site, [leader_a], tracked, stats)
			break
		if move_ord.is_finished() and move_ord.is_succeeded():
			_record_telemetry("D", frames, "lateral_move_succeeded", ctx, site, [leader_a], tracked, stats)
			break

	# Then reset position back to lateral South side with withdrawn cargo from camp and assign ConstructOrder.
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var withdraw_entries: Array[Dictionary] = inv.get_reserved_pile_entries(site.reservation_id, &"stone")
	var carry_seeded: bool = false
	if not withdraw_entries.is_empty():
		var pile_id: int = int(withdraw_entries[0]["pile_id"])
		var got: int = inv.withdraw_reserved_from_pile_to_carry_load(pile_id, site.reservation_id, main_stone_def(), 6, leader_a.get_carry_load())
		if got > 0:
			site.record_withdrawn_for_site(leader_a, &"stone", got)
			carry_seeded = true

	leader_a.cancel_current_order("reset_for_construct_d")
	leader_a.global_position = POS_SCENARIO_D_LATERAL
	await physics_frame
	cmd.command_units_to_site(site, [leader_a])
	tracked[leader_a.get_instance_id()] = leader_a.get_current_order()

	var construct_failed_reason: String = ""
	var construct_frames: int = 0
	while construct_frames < MAX_SIM_FRAMES_PER_PHASE:
		await physics_frame
		construct_frames += 1
		frames += 1
		_draw_debug_overlay(ctx, site, [leader_a])
		if construct_frames % TELEMETRY_SAMPLE_INTERVAL == 0:
			_record_telemetry("D", frames, "construct_tick", ctx, site, [leader_a], tracked, stats)
		var ord: UnitOrder = tracked.get(leader_a.get_instance_id()) as UnitOrder
		if ord != null and ord.status == UnitOrder.Status.FAILED:
			construct_failed_reason = ord.failure_reason
			_record_telemetry("D", frames, "construct_failed", ctx, site, [leader_a], tracked, stats)
			break
		if site.is_fully_supplied() and (ord == null or ord.is_finished()):
			_record_telemetry("D", frames, "completed", ctx, site, [leader_a], tracked, stats)
			break

	if _mode == "pre_fix" and not captured_d_moment and (not move_failed_reason.is_empty() or not construct_failed_reason.is_empty() or not site.is_fully_supplied() or int(stats["lateral_wall_collisions"]) > 0):
		await _capture_png(shot_dir_abs, "09_pre_fix_failure_state.png")
	await _capture_png(shot_dir_abs, "scenario_D_final.png")
	var c_ord: ConstructOrder = tracked.get(leader_a.get_instance_id()) as ConstructOrder
	var out: Dictionary = {
		"passed": move_failed_reason.is_empty() and not path_crosses_lateral_wall and site.is_fully_supplied() and construct_failed_reason.is_empty(),
		"carry_seeded": carry_seeded,
		"path_crosses_lateral_wall": path_crosses_lateral_wall,
		"path_min_x": snappedf(min_x_along_path, 0.001),
		"unit_min_x_detour": snappedf(unit_min_x_detour, 0.001),
		"direct_nav_path": path_pts_d,
		"move_failed_reason": move_failed_reason,
		"construct_failed_reason": construct_failed_reason,
		"delivered": _dict_str_int(site.get_delivered_buffer_amounts()),
		"trips_completed": c_ord.trips_completed if c_ord != null else 0,
		"lateral_wall_collisions": int(stats["lateral_wall_collisions"]),
		"lateral_samples": stats["lateral_samples"],
	}
	await _teardown_main(ctx)
	return out


func main_stone_def() -> ResourceDefinition:
	return MainScene.STONE_DEFINITION


func _run_scenario_e(shot_dir_abs: String) -> Dictionary:
	# 2 simultaneous workers (LeaderA + LeaderB) on plateau edge Scenario C:
	# verifies D9 role assignment, BUILDER standby on plateau, transporter interruption -> BUILDER promotion, and full completion.
	var ctx: Dictionary = await _boot_fresh_main(Vector2(11.5, -12.0), 30.0)
	_seed_camp_stock(ctx)
	var place_res: Dictionary = await _place_site_via_controller(ctx, POS_SCENARIO_C)
	var site: ConstructionSite = place_res["site"] as ConstructionSite
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig

	var stats: Dictionary = {"lateral_wall_collisions": 0, "lateral_samples": []}
	var tracked: Dictionary = {}
	if site == null or leader_a == null or leader_b == null:
		await _teardown_main(ctx)
		return {"passed": false, "reason": "placement_failed"}

	await _assign_workers_via_rmb(ctx, site, [leader_a, leader_b])
	tracked[leader_a.get_instance_id()] = leader_a.get_current_order()
	tracked[leader_b.get_instance_id()] = leader_b.get_current_order()

	var saw_d9_roles: bool = (
		site.get_worker_role(leader_a) == ConstructionSite.WorkerRole.TRANSPORTER
		and site.get_worker_role(leader_b) == ConstructionSite.WorkerRole.BUILDER
	)
	var saw_builder_standby: bool = false
	var saw_builder_promoted: bool = false
	var interrupted_transporter: bool = false
	var readded_leader_a: bool = false
	var captured_standby_full: bool = false
	var failure_reasons: Array[String] = []

	rig.set_focus_position(Vector2(11.5, -12.5))
	rig.set_target_zoom_distance(30.0, true)

	var frames: int = 0
	while frames < MAX_SIM_FRAMES_PER_PHASE:
		await physics_frame
		frames += 1
		_draw_debug_overlay(ctx, site, [leader_a, leader_b])

		var ord_a: ConstructOrder = tracked.get(leader_a.get_instance_id()) as ConstructOrder
		var ord_b: ConstructOrder = tracked.get(leader_b.get_instance_id()) as ConstructOrder
		if ord_b != null and ord_b.is_active() and ord_b.get_phase() == ConstructOrder.Phase.BUILDER_STANDBY:
			saw_builder_standby = true

		# After LeaderA completes trip 1 and LeaderB has reached BUILDER_STANDBY on the plateau,
		# interrupt LeaderA once to test BUILDER -> SOLO_SUPPLIER/TRANSPORTER promotion.
		if not interrupted_transporter and saw_builder_standby and ord_a != null and ord_a.trips_completed >= 1:
			interrupted_transporter = true
			leader_a.issue_order(MoveOrder.new(Vector3(-4.0, 0.0, 2.0)))
			await physics_frame
			var new_role_b: ConstructionSite.WorkerRole = site.get_worker_role(leader_b)
			if new_role_b == ConstructionSite.WorkerRole.SOLO_SUPPLIER or new_role_b == ConstructionSite.WorkerRole.TRANSPORTER:
				saw_builder_promoted = true
			_record_telemetry("E", frames, "transporter_interrupted_promotion", ctx, site, [leader_a, leader_b], tracked, stats)

		# Re-assign LeaderA back once LeaderA reached MoveOrder end (or after trip 2 starts) so final state has standby builder too.
		if interrupted_transporter and not readded_leader_a and site.get_delivered_buffer_amount(&"stone") + site.get_delivered_buffer_amount(&"wood") >= 10:
			if leader_a.get_current_order() == null:
				readded_leader_a = true
				await _assign_workers_via_rmb(ctx, site, [leader_a])
				tracked[leader_a.get_instance_id()] = leader_a.get_current_order()
				_record_telemetry("E", frames, "leader_a_reassigned", ctx, site, [leader_a, leader_b], tracked, stats)

		if site.is_fully_supplied() and not captured_standby_full:
			captured_standby_full = true
			_record_telemetry("E", frames, "09_completed_standby", ctx, site, [leader_a, leader_b], tracked, stats)
			if _mode == "post_fix":
				rig.set_focus_position(Vector2(14.5, -11.5))
				rig.set_target_zoom_distance(25.0, true)
				await _capture_png(shot_dir_abs, "09_post_fix_completed_standby.png")

		if frames % TELEMETRY_SAMPLE_INTERVAL == 0:
			_record_telemetry("E", frames, "tick", ctx, site, [leader_a, leader_b], tracked, stats)

		for uid_key: Variant in tracked.keys():
			var o: UnitOrder = tracked[uid_key] as UnitOrder
			if o != null and o.status == UnitOrder.Status.FAILED:
				var tag: String = "%s:%s" % [str(uid_key), o.failure_reason]
				if not failure_reasons.has(tag):
					failure_reasons.append(tag)

		if not failure_reasons.is_empty():
			_record_telemetry("E", frames, "order_failed", ctx, site, [leader_a, leader_b], tracked, stats)
			break

		if site.is_fully_supplied() and (ord_b == null or ord_b.is_finished()) and (not readded_leader_a or leader_a.get_current_order() == null):
			break

	await _capture_png(shot_dir_abs, "scenario_E_final.png")
	var out: Dictionary = {
		"passed": site.is_fully_supplied() and failure_reasons.is_empty() and saw_d9_roles and saw_builder_standby and saw_builder_promoted,
		"frames": frames,
		"saw_d9_roles": saw_d9_roles,
		"saw_builder_standby": saw_builder_standby,
		"saw_builder_promoted": saw_builder_promoted,
		"delivered": _dict_str_int(site.get_delivered_buffer_amounts()),
		"failure_reasons": failure_reasons,
		"lateral_wall_collisions": int(stats["lateral_wall_collisions"]),
		"lateral_samples": stats["lateral_samples"],
	}
	await _teardown_main(ctx)
	return out
