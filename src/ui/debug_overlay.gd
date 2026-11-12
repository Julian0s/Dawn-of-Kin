class_name DebugOverlay
extends Control
## Lightweight non-blocking HUD overlay displaying FPS, frame times, and scene node counts.
## Toggled via InputActions.DEBUG_OVERLAY (F3).

@onready var _stats_label: Label = $Panel/Margin/StatsLabel

var _last_tick_usec: int = 0
var _frame_time_ms: float = 0.0


func _ready() -> void:
	_last_tick_usec = Time.get_ticks_usec()
	_refresh_stats()


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	if _last_tick_usec > 0:
		_frame_time_ms = float(now_usec - _last_tick_usec) / 1000.0
	_last_tick_usec = now_usec

	if visible:
		_refresh_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.DEBUG_OVERLAY):
		toggle_visibility()
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func toggle_visibility() -> void:
	visible = not visible
	if visible:
		_refresh_stats()


func get_stats_text() -> String:
	return _stats_label.text if _stats_label != null else ""


func _refresh_stats() -> void:
	if _stats_label == null:
		return

	var fps: float = Engine.get_frames_per_second()
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

	_stats_label.text = (
		"Dawn of Kin — Debug [F3]\n"
		+ "FPS: %.0f | Frame: %.2f ms\n"
		+ "Process: %.2f ms | Physics: %.2f ms\n"
		+ "Nodes: %d | Draw calls: %d"
	) % [fps, _frame_time_ms, process_ms, physics_ms, node_count, draw_calls]
