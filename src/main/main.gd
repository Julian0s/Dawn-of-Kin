class_name MainScene
extends Node3D
## Root composition script connecting level data, world navigation, units, selection, and camera rig.

@onready var _test_map: TestMap = $TestMap
@onready var _camera_rig: RtsCameraRig = $RtsCameraRig
@onready var _units_root: Node3D = $Units
@onready var _selection_manager: SelectionManager = $SelectionManager
@onready var _input_controller: RtsInputController = $RtsInputController
@onready var _selection_box_overlay: SelectionBoxOverlay = $UiLayer/SelectionBoxOverlay


func _ready() -> void:
	if _test_map != null and _camera_rig != null:
		_camera_rig.set_map_bounds(_test_map.get_map_bounds())

	if _test_map != null and _units_root != null:
		var world_nav: WorldNavigation = _test_map.get_navigation()
		for child: Node in _units_root.get_children():
			if child is Unit:
				(child as Unit).set_world_navigation(world_nav)

	if _input_controller != null:
		_input_controller.configure(_selection_manager, _camera_rig, _selection_box_overlay)


func get_units() -> Array[Unit]:
	var result: Array[Unit] = []
	if _units_root == null:
		return result
	for child: Node in _units_root.get_children():
		if child is Unit:
			result.append(child as Unit)
	return result


func get_selection_manager() -> SelectionManager:
	return _selection_manager


func get_input_controller() -> RtsInputController:
	return _input_controller


func get_selection_box_overlay() -> SelectionBoxOverlay:
	return _selection_box_overlay
