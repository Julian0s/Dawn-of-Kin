extends SceneTree
## Visual capture script for T1.7: launches MainScene in windowed mode and captures
## active box-selection drag overlay and resulting multi-unit selection rings.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_DIR: String = "res://test_output"


func _initialize() -> void:
	call_deferred("_run_captures")


func _run_captures() -> void:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_root)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	var manager: SelectionManager = main_root.get_selection_manager()
	var overlay: SelectionBoxOverlay = main_root.get_selection_box_overlay()
	if rig == null or manager == null or overlay == null:
		push_error("MainScene missing RtsCameraRig, SelectionManager, or SelectionBoxOverlay.")
		quit(1)
		return

	rig.edge_pan_enabled = false
	rig.set_focus_position(Vector2(0.0, 2.5))
	rig.set_target_zoom_distance(28.0, true)

	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in main_root.get_units():
		if unit.get_character_id() == &"leader_a":
			leader_a = unit
		elif unit.get_character_id() == &"leader_b":
			leader_b = unit

	if leader_a == null or leader_b == null:
		push_error("MainScene missing LeaderA or LeaderB.")
		quit(1)
		return

	var output_abs_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(output_abs_dir)
	if mkdir_err != OK:
		push_error("Failed to create output directory '%s': %s" % [output_abs_dir, error_string(mkdir_err)])
		quit(1)
		return

	for _i: int in range(30):
		await process_frame
		await physics_frame

	var cam: Camera3D = rig.get_camera()
	var a_pos: Vector2 = cam.unproject_position(SelectionBoxMath.get_unit_world_anchor(leader_a))
	var b_pos: Vector2 = cam.unproject_position(SelectionBoxMath.get_unit_world_anchor(leader_b))
	var start_pt := Vector2(minf(a_pos.x, b_pos.x) - 70.0, minf(a_pos.y, b_pos.y) - 65.0)
	var end_pt := Vector2(maxf(a_pos.x, b_pos.x) + 70.0, maxf(a_pos.y, b_pos.y) + 65.0)

	# 1. Start drag and capture while SelectionBoxOverlay is active over both units.
	await _move_mouse(start_pt)
	_push_left_button(start_pt, true)
	await process_frame
	await _move_mouse(end_pt)
	if not overlay.is_box_active() or not overlay.visible:
		push_error("Expected SelectionBoxOverlay active during box drag.")
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_7_01_box_dragging.png")):
		quit(1)
		return

	# 2. Release left button and capture both units selected with overlay cleared.
	_push_left_button(end_pt, false)
	for _i: int in range(4):
		await process_frame
	if overlay.is_box_active() or overlay.visible:
		push_error("Expected SelectionBoxOverlay cleared after box release.")
		quit(1)
		return
	if manager.get_selection_count() != 2 or not manager.is_selected(leader_a) or not manager.is_selected(leader_b):
		push_error("Expected both protagonists selected after box release.")
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_7_02_box_selected_both.png")):
		quit(1)
		return

	print("T1.7 visual box selection scenario completed successfully (2 captures).")
	quit(0)


func _move_mouse(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	root.push_input(motion, true)
	for _i: int in range(3):
		await process_frame


func _push_left_button(screen_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = screen_pos
	ev.global_position = screen_pos
	ev.pressed = pressed
	root.push_input(ev, true)


func _save_shot(abs_path: String) -> bool:
	for _i: int in range(4):
		await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("Failed to capture viewport image for '%s'." % abs_path)
		return false
	var err: Error = img.save_png(abs_path)
	if err != OK:
		push_error("Failed to save PNG '%s': %s" % [abs_path, error_string(err)])
		return false
	print("Saved visual capture: %s" % abs_path)
	return true
