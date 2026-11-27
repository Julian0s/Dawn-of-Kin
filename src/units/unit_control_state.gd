class_name UnitControlState
extends RefCounted
## Lightweight authority state component owned exclusively by Unit (R-03B B2).
## Distinguishes control authority (ControlMode) from physical operational state (Unit.State).
## Mutated solely by Unit through its F03 order lifecycle; external consumers are read-only.

enum ControlMode {
	COMMUNITY_FREE = 0,
	COMMUNITY_WORKING = 1,
	PERSONAL_ACTIVE = 2,
}

var _mode: ControlMode = ControlMode.COMMUNITY_FREE
var _active_origin: UnitOrder.OrderOrigin = UnitOrder.OrderOrigin.NONE
var _last_published_mode: ControlMode = ControlMode.COMMUNITY_FREE


func get_mode() -> ControlMode:
	return _mode


func get_mode_name() -> String:
	match _mode:
		ControlMode.COMMUNITY_FREE:
			return "COMMUNITY_FREE"
		ControlMode.COMMUNITY_WORKING:
			return "COMMUNITY_WORKING"
		ControlMode.PERSONAL_ACTIVE:
			return "PERSONAL_ACTIVE"
		_:
			return "COMMUNITY_FREE"


func get_active_origin() -> UnitOrder.OrderOrigin:
	return _active_origin


func get_last_published_mode() -> ControlMode:
	return _last_published_mode


func is_community_free() -> bool:
	return _mode == ControlMode.COMMUNITY_FREE


func is_personal_active() -> bool:
	return _mode == ControlMode.PERSONAL_ACTIVE


func _apply_internal(new_mode: ControlMode, new_origin: UnitOrder.OrderOrigin) -> void:
	_mode = new_mode
	_active_origin = new_origin


func _commit_published_mode() -> Dictionary:
	if _mode == _last_published_mode:
		return {
			"changed": false,
			"new_mode": _mode,
			"previous_mode": _last_published_mode,
		}
	var previous_mode: ControlMode = _last_published_mode
	_last_published_mode = _mode
	return {
		"changed": true,
		"new_mode": _mode,
		"previous_mode": previous_mode,
	}


static func mode_for_origin(origin: UnitOrder.OrderOrigin) -> ControlMode:
	match origin:
		UnitOrder.OrderOrigin.PERSONAL:
			return ControlMode.PERSONAL_ACTIVE
		UnitOrder.OrderOrigin.COMMUNITY, UnitOrder.OrderOrigin.SYSTEM_RECOVERY:
			return ControlMode.COMMUNITY_WORKING
		_:
			return ControlMode.COMMUNITY_FREE
