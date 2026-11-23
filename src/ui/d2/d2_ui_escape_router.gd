class_name D2UiEscapeRouter
extends Node
## Progressive priority-ordered Escape router for Dawn of Kin D2.2 UI.
##
## In UI-1.1B, this router operates strictly in pass-through mode (zero active handlers):
## - Never opens a non-existent main menu (reserved for UI-1.5).
## - Never consumes Esc when no registered handler returns can_handle() == true.
## - Never interferes with ConstructionHud._input(), PlacementController, or
##   RtsInputController._unhandled_input() when idle.
## - Never cancels selection or placement twice.

signal escape_handled(handler_id: StringName)

const PRIORITY_SETTINGS: int = 10
const PRIORITY_MAIN_MENU: int = 20
const PRIORITY_MAQUETTES: int = 30
const PRIORITY_PLACEMENT: int = 40
const PRIORITY_INSPECTOR: int = 50
const PRIORITY_FALLBACK_OPEN_MENU: int = 90

var _handlers: Array[Dictionary] = []
var _next_order: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	clear_handlers()


func register_handler(
	handler_id: StringName,
	priority: int,
	can_handle: Callable,
	handle: Callable
) -> bool:
	if handler_id.is_empty() or not can_handle.is_valid() or not handle.is_valid():
		return false
	unregister_handler(handler_id)
	_next_order += 1
	_handlers.append({
		"id": handler_id,
		"priority": priority,
		"order": _next_order,
		"can_handle": can_handle,
		"handle": handle,
	})
	_handlers.sort_custom(_sort_handlers)
	return true


func unregister_handler(handler_id: StringName) -> bool:
	for i: int in range(_handlers.size()):
		if (_handlers[i]["id"] as StringName) == handler_id:
			_handlers.remove_at(i)
			return true
	return false


func has_handler(handler_id: StringName) -> bool:
	for entry: Dictionary in _handlers:
		if (entry["id"] as StringName) == handler_id:
			return true
	return false


func get_registered_handler_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in _handlers:
		ids.append(entry["id"] as StringName)
	return ids


func get_handler_count() -> int:
	return _handlers.size()


func is_pass_through_mode() -> bool:
	return _handlers.is_empty()


func clear_handlers() -> void:
	_handlers.clear()


func try_route_escape() -> StringName:
	if _handlers.is_empty():
		return &""
	var snapshot: Array[Dictionary] = _handlers.duplicate()
	for entry: Dictionary in snapshot:
		var can_cb: Callable = entry["can_handle"] as Callable
		var handle_cb: Callable = entry["handle"] as Callable
		if not can_cb.is_valid() or not handle_cb.is_valid():
			continue
		if bool(can_cb.call()):
			handle_cb.call()
			var hid: StringName = entry["id"] as StringName
			escape_handled.emit(hid)
			return hid
	return &""


func _unhandled_input(event: InputEvent) -> void:
	if _handlers.is_empty():
		return
	if not _is_escape_press(event):
		return
	var handled_id: StringName = try_route_escape()
	if not handled_id.is_empty():
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


static func _is_escape_press(event: InputEvent) -> bool:
	if event == null:
		return false
	if event.is_action_pressed(InputActions.CLEAR_SELECTION):
		return true
	if event is InputEventKey:
		var key_ev: InputEventKey = event as InputEventKey
		return key_ev.pressed and not key_ev.echo and key_ev.keycode == KEY_ESCAPE
	return false


static func _sort_handlers(a: Dictionary, b: Dictionary) -> bool:
	var pa: int = int(a["priority"])
	var pb: int = int(b["priority"])
	if pa != pb:
		return pa < pb
	return int(a["order"]) < int(b["order"])
