class_name WorldTimeProvider
extends RefCounted
## Minimal world-time abstraction for deterministic decay and future T4 calendar integration.
## Decouples economy simulation from SceneTree or wall-clock timers.


func get_world_time_sec() -> float:
	return 0.0


func get_time_scale() -> float:
	return 1.0


func is_paused() -> bool:
	return false
