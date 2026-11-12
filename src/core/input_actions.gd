class_name InputActions
extends RefCounted
## Central registry of InputMap action names defined in project.godot.

const SELECT: StringName = &"select"
const COMMAND: StringName = &"command"
const SELECTION_MODIFIER: StringName = &"selection_modifier"
const CLEAR_SELECTION: StringName = &"clear_selection"

const CAMERA_PAN_UP: StringName = &"camera_pan_up"
const CAMERA_PAN_DOWN: StringName = &"camera_pan_down"
const CAMERA_PAN_LEFT: StringName = &"camera_pan_left"
const CAMERA_PAN_RIGHT: StringName = &"camera_pan_right"
const CAMERA_DRAG: StringName = &"camera_drag"
const CAMERA_ZOOM_IN: StringName = &"camera_zoom_in"
const CAMERA_ZOOM_OUT: StringName = &"camera_zoom_out"

const DEBUG_OVERLAY: StringName = &"debug_overlay"
const DEBUG_NAVIGATION: StringName = &"debug_navigation"


static func get_all_actions() -> Array[StringName]:
	return [
		SELECT,
		COMMAND,
		SELECTION_MODIFIER,
		CLEAR_SELECTION,
		CAMERA_PAN_UP,
		CAMERA_PAN_DOWN,
		CAMERA_PAN_LEFT,
		CAMERA_PAN_RIGHT,
		CAMERA_DRAG,
		CAMERA_ZOOM_IN,
		CAMERA_ZOOM_OUT,
		DEBUG_OVERLAY,
		DEBUG_NAVIGATION,
	]
