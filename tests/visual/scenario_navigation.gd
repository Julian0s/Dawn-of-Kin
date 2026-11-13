extends SceneTree
## Visual capture script for T1.4: launches Main scene with --debug-navigation,
## waits for WorldNavigation readiness, and saves a PNG screenshot of the baked navmesh.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_REL_PATH: String = "res://test_output/t1_4_navmesh.png"
const MAX_WAIT_FRAMES: int = 120


func _initialize() -> void:
	call_deferred("_run_capture")


func _run_capture() -> void:
	var main_instance: Node = MAIN_SCENE.instantiate()
	root.add_child(main_instance)

	var test_map: TestMap = main_instance.get_node_or_null("TestMap") as TestMap
	var rig: RtsCameraRig = main_instance.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if test_map == null or rig == null:
		push_error("Main scene is missing TestMap or RtsCameraRig.")
		quit(1)
		return

	rig.edge_pan_enabled = false
	rig.set_focus_position(Vector2.ZERO)
	rig.set_target_zoom_distance(54.0, true)

	var nav: WorldNavigation = test_map.get_navigation()
	if nav == null:
		push_error("TestMap is missing WorldNavigation.")
		quit(1)
		return

	var waited: int = 0
	while not nav.is_navigation_ready() and waited < MAX_WAIT_FRAMES:
		await physics_frame
		waited += 1

	if not nav.is_navigation_ready():
		push_error("WorldNavigation did not become ready within %d physics frames." % MAX_WAIT_FRAMES)
		quit(1)
		return

	for _i: int in range(15):
		await process_frame

	var output_abs_path: String = ProjectSettings.globalize_path(OUTPUT_REL_PATH)
	var output_dir: String = output_abs_path.get_base_dir()
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_err != OK:
		push_error("Failed to create output directory '%s': %s" % [output_dir, error_string(mkdir_err)])
		quit(1)
		return

	var gdignore_path: String = output_dir.path_join(".gdignore")
	if not FileAccess.file_exists(gdignore_path):
		var gdignore_file: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if gdignore_file != null:
			gdignore_file.close()

	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Captured viewport image is empty.")
		quit(1)
		return

	var save_err: Error = image.save_png(output_abs_path)
	if save_err != OK:
		push_error("Failed to save screenshot '%s': %s" % [output_abs_path, error_string(save_err)])
		quit(1)
		return

	print("Screenshot saved: %s (%dx%d) | metrics=%s" % [
		output_abs_path,
		image.get_width(),
		image.get_height(),
		str(nav.get_last_bake_metrics()),
	])
	quit(0)
