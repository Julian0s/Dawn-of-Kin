extends SceneTree
## Visual capture script for T1.2: launches Main scene in windowed mode,
## waits for rendering and DebugOverlay stats, and writes a PNG screenshot to test_output/.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_REL_PATH: String = "res://test_output/t1_2_test_map.png"


func _initialize() -> void:
	call_deferred("_run_capture")


func _run_capture() -> void:
	var main_instance: Node = MAIN_SCENE.instantiate()
	root.add_child(main_instance)

	# Allow >1.5 s of rendered frames so Engine.get_frames_per_second() reflects steady-state FPS.
	for _i: int in range(90):
		await process_frame

	var output_abs_path: String = ProjectSettings.globalize_path(OUTPUT_REL_PATH)
	var output_dir: String = output_abs_path.get_base_dir()
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_err != OK:
		push_error("Failed to create screenshot output directory '%s': %s" % [output_dir, error_string(mkdir_err)])
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
		push_error("Failed to save screenshot to '%s': %s" % [output_abs_path, error_string(save_err)])
		quit(1)
		return

	print("Screenshot saved: %s (%dx%d)" % [output_abs_path, image.get_width(), image.get_height()])
	quit(0)
