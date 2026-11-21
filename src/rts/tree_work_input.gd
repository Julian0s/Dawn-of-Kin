extends RtsInputController
## Only the UX-1 evaluation scene installs this input adapter.

@onready var menu: TreeWorkMenu = $"../UiLayer/TreeWorkMenu"


func _handle_left_click(screen_pos: Vector2, shift_held: bool) -> void:
	var pick := pick_at_screen_pos(screen_pos)
	if pick.is_resource_source() and pick.resource_source.get_resource_id() == &"wood":
		construction_site_picked.emit(null)
		menu.choose_tree(pick.resource_source)
		return
	if menu.visible and not pick.is_unit():
		menu.close_menu()
		return
	super._handle_left_click(screen_pos, shift_held)
	if pick.is_unit():
		menu.choose_people(_selection_manager.get_selected_units())
	else:
		menu.close_menu()


func _handle_box_selection(start_pos: Vector2, end_pos: Vector2, shift_held: bool) -> void:
	super._handle_box_selection(start_pos, end_pos, shift_held)
	menu.choose_people(_selection_manager.get_selected_units())


func _handle_right_click(screen_pos: Vector2) -> void:
	if menu.visible:
		menu.close_menu()
		return
	super._handle_right_click(screen_pos)


func _unhandled_input(event: InputEvent) -> void:
	if menu.visible and event.is_action_pressed(InputActions.CLEAR_SELECTION):
		menu.close_menu()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
