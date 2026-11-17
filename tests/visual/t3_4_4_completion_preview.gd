extends SceneTree
## Rendered T3.4.4 smoke scenario; exports a real viewport image to TEMP.
## No performance or owner/manual acceptance is inferred from this capture.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: MainScene = preload("res://src/main/main.tscn").instantiate() as MainScene
	root.add_child(main)
	await process_frame
	await process_frame
	var nav: WorldNavigation = main.get_test_map().get_navigation()
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < 240:
		await physics_frame
		frames += 1
	if not nav.is_navigation_ready():
		push_error("Completion preview: navigation never became ready")
		quit(1)
		return
	var rig: RtsCameraRig = main.get_node("RtsCameraRig") as RtsCameraRig
	rig.edge_pan_enabled = false
	var inventory: SettlementInventory = main.get_settlement_inventory()
	inventory.deposit(&"wood", 12)
	inventory.deposit(&"stone", 6)
	var cm: ConstructionManager = main.get_construction_manager()
	var result: Dictionary = cm.try_create_site_from_placement(preload("res://data/buildings/shelter_basic.tres"), Vector3(-6, 0, 1.5))
	if not result["ok"]:
		push_error("Completion preview: site creation failed")
		quit(1)
		return
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	main.get_command_controller().command_units_to_site(result["site"], main.get_units())
	frames = 0
	while cm.get_completed_buildings().is_empty() and frames < 7200:
		await physics_frame
		frames += 1
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	if cm.get_completed_buildings().size() != 1:
		push_error("Completion preview: assembly did not produce exactly one building")
		quit(1)
		return
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var building: BuildingInstance = cm.get_completed_buildings()[0]
	var target: String = OS.get_environment("TEMP").path_join("dok344_completed.png")
	var saved: Error = root.get_texture().get_image().save_png(target)
	print("T344_GRAPHICAL ", JSON.stringify({"building_id": building.building_id, "materials": building.incorporated_materials, "remaining_sites": cm.get_sites().size(), "image": target, "save_error": saved}))
	quit(0 if saved == OK else 1)
