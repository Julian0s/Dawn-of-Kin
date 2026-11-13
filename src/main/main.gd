class_name MainScene
extends Node3D
## Root composition script connecting level data, world navigation, units, and the RTS camera rig.

@onready var _test_map: TestMap = $TestMap
@onready var _camera_rig: RtsCameraRig = $RtsCameraRig
@onready var _units_root: Node3D = $Units


func _ready() -> void:
	if _test_map != null and _camera_rig != null:
		_camera_rig.set_map_bounds(_test_map.get_map_bounds())

	if _test_map != null and _units_root != null:
		var world_nav: WorldNavigation = _test_map.get_navigation()
		for child: Node in _units_root.get_children():
			if child is Unit:
				(child as Unit).set_world_navigation(world_nav)


func get_units() -> Array[Unit]:
	var result: Array[Unit] = []
	if _units_root == null:
		return result
	for child: Node in _units_root.get_children():
		if child is Unit:
			result.append(child as Unit)
	return result
