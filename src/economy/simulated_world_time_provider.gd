class_name SimulatedWorldTimeProvider
extends WorldTimeProvider
## Deterministic, manually controllable world clock for unit/integration tests and headless stepping.

var _world_time_sec: float = 0.0
var _time_scale: float = 1.0
var _paused: bool = false


func _init(initial_time_sec: float = 0.0) -> void:
	if is_finite(initial_time_sec) and initial_time_sec >= 0.0:
		_world_time_sec = initial_time_sec


func get_world_time_sec() -> float:
	return _world_time_sec


func get_time_scale() -> float:
	return _time_scale


func set_time_scale(new_scale: float) -> bool:
	if not is_finite(new_scale) or new_scale < 0.0:
		return false
	_time_scale = new_scale
	return true


func is_paused() -> bool:
	return _paused


func set_paused(paused: bool) -> void:
	_paused = paused


func advance(delta_sec: float) -> float:
	if _paused or not is_finite(delta_sec) or delta_sec <= 0.0:
		return _world_time_sec
	_world_time_sec += delta_sec * _time_scale
	return _world_time_sec
