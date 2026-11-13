extends SceneTree
## Visual capture script for T1.3: launches Main scene in windowed mode and saves
## screenshots at minimum, intermediate, and maximum zoom plus near map bounds.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_DIR: String = "res://test_output"


func _initialize() -> void:
	call_deferred("_run_captures")


func _run_captures() -> void:
	var main_instance: Node = MAIN_SCENE.instantiate()
	root.add_child(main_instance)

	var rig: RtsCameraRig = main_instance.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig == null:
		push_error("Main scene is missing RtsCameraRig.")
		quit(1)
		return
	rig.edge_pan_enabled = false

	var output_abs_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(output_abs_dir)
	if mkdir_err != OK:
		push_error("Failed to create output directory '%s': %s" % [output_abs_dir, error_string(mkdir_err)])
		quit(1)
		return

	var gdignore_path: String = output_abs_dir.path_join(".gdignore")
	if not FileAccess.file_exists(gdignore_path):
		var gdignore_file: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if gdignore_file != null:
			gdignore_file.close()

	# Allow steady-state FPS sampling before the first capture.
	for _i: int in range(85):
		await process_frame

	if not await _capture_state(rig, Vector2.ZERO, rig.min_distance, output_abs_dir.path_join("t1_3_zoom_min.png")):
		quit(1)
		return

	if not await _capture_state(rig, Vector2.ZERO, rig.default_distance, output_abs_dir.path_join("t1_3_zoom_mid.png")):
		quit(1)
		return

	if not await _capture_state(rig, Vector2.ZERO, rig.max_distance, output_abs_dir.path_join("t1_3_zoom_max.png")):
		quit(1)
		return

	if not await _capture_state(rig, Vector2(26.0, -22.0), rig.default_distance, output_abs_dir.path_join("t1_3_bounds_edge.png")):
		quit(1)
		return

	quit(0)


func _capture_state(rig: RtsCameraRig, focus_xz: Vector2, distance: float, abs_path: String) -> bool:
	rig.set_focus_position(focus_xz)
	rig.set_target_zoom_distance(distance, true)

	for _i: int in range(5):
		await process_frame

	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Captured viewport image is empty for %s" % abs_path)
		return false

	var err: Error = image.save_png(abs_path)
	if err != OK:
		push_error("Failed to save screenshot '%s': %s" % [abs_path, error_string(err)])
		return false

	print("Screenshot saved: %s (%dx%d, focus=%s, dist=%.1f)" % [
		abs_path,
		image.get_width(),
		image.get_height(),
		str(rig.get_focus_position()),
		rig.get_current_zoom_distance(),
	])
	return true
