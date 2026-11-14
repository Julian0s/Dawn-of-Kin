class_name EconomyClockController
extends Node
## Centralized, pausable economy clock driving camp pile decay without per-pile timers.
## Owns a single Timer node synced with a SimulatedWorldTimeProvider so gameplay respects
## SceneTree pause/time scale and tests can deterministically fast-forward time.

signal decay_stepped(losses: Dictionary)

@export var tick_interval_sec: float = 1.0
@export var autostart_timer: bool = true

var _time_provider: SimulatedWorldTimeProvider = null
var _pile_manager: GroundPileManager = null
var _timer: Timer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_timer()
	if autostart_timer and _timer.is_stopped():
		_timer.start()


func configure(
	pile_manager: GroundPileManager,
	time_provider: SimulatedWorldTimeProvider = null
) -> void:
	_pile_manager = pile_manager
	if time_provider != null:
		_time_provider = time_provider
	elif _time_provider == null:
		_time_provider = SimulatedWorldTimeProvider.new(0.0)
	_ensure_timer()
	if autostart_timer and is_inside_tree() and _timer.is_stopped():
		_timer.start()


func get_time_provider() -> SimulatedWorldTimeProvider:
	return _time_provider


func get_timer() -> Timer:
	_ensure_timer()
	return _timer


func get_world_time_sec() -> float:
	if _time_provider == null:
		return 0.0
	return _time_provider.get_world_time_sec()


func set_paused(paused: bool) -> void:
	if _time_provider != null:
		_time_provider.set_paused(paused)


func is_paused() -> bool:
	var tree_paused: bool = get_tree() != null and get_tree().paused
	var clock_paused: bool = _time_provider != null and _time_provider.is_paused()
	return tree_paused or clock_paused


func set_time_scale(new_scale: float) -> bool:
	if _time_provider == null:
		return false
	return _time_provider.set_time_scale(new_scale)


func get_time_scale() -> float:
	if _time_provider == null:
		return 1.0
	return _time_provider.get_time_scale()


func step_decay() -> Dictionary:
	if _pile_manager == null or is_paused():
		return {}
	var losses: Dictionary = _pile_manager.step_decay()
	decay_stepped.emit(losses)
	return losses


func advance_simulated_time(delta_sec: float) -> Dictionary:
	if _time_provider == null or _pile_manager == null:
		return {}
	if is_paused() or not is_finite(delta_sec) or delta_sec <= 0.0:
		return {}
	_time_provider.advance(delta_sec)
	return step_decay()


func _ensure_timer() -> void:
	if _timer != null and is_instance_valid(_timer):
		return
	_timer = get_node_or_null("DecayTickTimer") as Timer
	if _timer == null:
		_timer = Timer.new()
		_timer.name = "DecayTickTimer"
		add_child(_timer)
	_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_timer.ignore_time_scale = false
	_timer.one_shot = false
	_timer.wait_time = maxf(0.05, tick_interval_sec)
	if not _timer.timeout.is_connected(_on_tick_timeout):
		_timer.timeout.connect(_on_tick_timeout)


func _on_tick_timeout() -> void:
	if _time_provider == null or _pile_manager == null or is_paused():
		return
	var prev_time: float = _time_provider.get_world_time_sec()
	var next_time: float = _time_provider.advance(_timer.wait_time)
	if next_time > prev_time:
		step_decay()
