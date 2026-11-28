class_name SelectedUnitPanel
extends PanelContainer
## Compact bottom-left HUD panel displaying the selected unit's state, carry percentage,
## weight/effective capacity, and carried materials, or a clean multi-selection summary.
## Driven strictly by selection, unit state, and carry-load signals without per-frame polling.

enum SelectionMode {
	EMPTY,
	SINGLE,
	MULTI,
}

enum BarTier {
	NONE,
	NORMAL,
	HIGH,
	OVERLOAD,
}

@onready var _unit_name_label: Label = $Margin/VBox/HeaderRow/UnitNameLabel
@onready var _unit_state_label: Label = $Margin/VBox/HeaderRow/UnitStateLabel
@onready var _multi_summary_label: Label = $Margin/VBox/MultiSummaryLabel
@onready var _single_content: VBoxContainer = $Margin/VBox/SingleUnitContent
@onready var _inspection_meta_label: Label = get_node_or_null("Margin/VBox/SingleUnitContent/InspectionMetaLabel") as Label
@onready var _carry_bar: ProgressBar = $Margin/VBox/SingleUnitContent/CarryBarRow/CarryProgressBar
@onready var _percentage_label: Label = $Margin/VBox/SingleUnitContent/CarryBarRow/PercentageLabel
@onready var _weight_label: Label = $Margin/VBox/SingleUnitContent/WeightLabel
@onready var _wood_label: Label = $Margin/VBox/SingleUnitContent/CarriedRow/WoodItem/TextLabel
@onready var _stone_label: Label = $Margin/VBox/SingleUnitContent/CarriedRow/StoneItem/TextLabel
@onready var _food_label: Label = $Margin/VBox/SingleUnitContent/CarriedRow/FoodItem/TextLabel

var _mode: SelectionMode = SelectionMode.EMPTY
var _selected_count: int = 0
var _tracked_unit: Unit = null
var _tracked_carry_load: UnitCarryLoad = null
var _community_work_board: CommunityWorkBoard = null
var _last_render_key: Dictionary = {}
var _has_rendered: bool = false
var _apply_count: int = 0
var _active_bar_tier: BarTier = BarTier.NONE

var _bar_fill_normal: StyleBoxFlat = null
var _bar_fill_high: StyleBoxFlat = null
var _bar_fill_overload: StyleBoxFlat = null


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	HudStyle.apply_mouse_filter_ignore_recursive(self)
	add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())

	_bar_fill_normal = HudStyle.create_progress_fill_style(HudStyle.BAR_FILL_NORMAL_COLOR)
	_bar_fill_high = HudStyle.create_progress_fill_style(HudStyle.BAR_FILL_HIGH_COLOR)
	_bar_fill_overload = HudStyle.create_progress_fill_style(HudStyle.BAR_FILL_OVERLOAD_COLOR)
	if _carry_bar != null:
		_carry_bar.min_value = 0.0
		_carry_bar.max_value = 100.0
		_carry_bar.step = 0.01
		_carry_bar.show_percentage = false
		_carry_bar.add_theme_stylebox_override(&"background", HudStyle.create_progress_bg_style())
		_apply_bar_tier(BarTier.NORMAL)

	_render_current()


func _exit_tree() -> void:
	unbind()


func set_selected_units(selected_units: Array[Unit]) -> void:
	var valid_units: Array[Unit] = []
	for unit: Unit in selected_units:
		if _is_unit_valid(unit) and not valid_units.has(unit):
			valid_units.append(unit)

	if valid_units.is_empty():
		_unbind_tracked_unit()
		_mode = SelectionMode.EMPTY
		_selected_count = 0
		_render_current()
		return

	if valid_units.size() == 1:
		var target: Unit = valid_units[0]
		if _tracked_unit != target:
			_bind_single_unit(target)
		_mode = SelectionMode.SINGLE
		_selected_count = 1
		_render_current()
		return

	_unbind_tracked_unit()
	_mode = SelectionMode.MULTI
	_selected_count = valid_units.size()
	_render_current()


func set_community_work_board(board: CommunityWorkBoard) -> void:
	if _community_work_board == board:
		return
	_unbind_community_work_board()
	_community_work_board = board
	if _community_work_board != null and is_instance_valid(_community_work_board):
		if not _community_work_board.task_registered.is_connected(_on_board_task_changed):
			_community_work_board.task_registered.connect(_on_board_task_changed)
		if not _community_work_board.task_updated.is_connected(_on_board_task_changed):
			_community_work_board.task_updated.connect(_on_board_task_changed)
		if not _community_work_board.task_closed.is_connected(_on_board_task_changed):
			_community_work_board.task_closed.connect(_on_board_task_changed)
	if is_node_ready():
		_render_current()


func unbind() -> void:
	_unbind_tracked_unit()
	_unbind_community_work_board()
	_mode = SelectionMode.EMPTY
	_selected_count = 0
	if is_node_ready():
		_render_current()


func refresh() -> void:
	_render_current()


func get_selection_mode() -> SelectionMode:
	return _mode


func get_selected_count() -> int:
	return _selected_count


func get_tracked_unit() -> Unit:
	return _tracked_unit


func get_header_text() -> String:
	return _unit_name_label.text if _unit_name_label != null else ""


func get_state_text() -> String:
	return _unit_state_label.text if _unit_state_label != null else ""


func get_inspection_meta_text() -> String:
	if _inspection_meta_label == null or not _inspection_meta_label.visible:
		return ""
	return _inspection_meta_label.text


func get_percentage_text() -> String:
	return _percentage_label.text if _percentage_label != null else ""


func get_bar_value() -> float:
	return _carry_bar.value if _carry_bar != null else 0.0


func get_weight_text() -> String:
	return _weight_label.text if _weight_label != null else ""


func get_carried_text(resource_id: StringName) -> String:
	match resource_id:
		&"wood":
			return _wood_label.text if _wood_label != null else ""
		&"stone":
			return _stone_label.text if _stone_label != null else ""
		&"food":
			return _food_label.text if _food_label != null else ""
		_:
			return ""


func get_multi_summary_text() -> String:
	return _multi_summary_label.text if _multi_summary_label != null else ""


func get_apply_count() -> int:
	return _apply_count


func is_single_details_visible() -> bool:
	return _single_content != null and _single_content.visible


func is_multi_summary_visible() -> bool:
	return _multi_summary_label != null and _multi_summary_label.visible


func is_bound_to_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit) or _tracked_unit != unit:
		return false
	return (
		unit.state_changed.is_connected(_on_unit_state_changed)
		and unit.control_mode_changed.is_connected(_on_unit_control_mode_changed)
	)


func _bind_single_unit(unit: Unit) -> void:
	_unbind_tracked_unit()
	if not _is_unit_valid(unit):
		return
	_tracked_unit = unit
	if not _tracked_unit.state_changed.is_connected(_on_unit_state_changed):
		_tracked_unit.state_changed.connect(_on_unit_state_changed)
	if not _tracked_unit.control_mode_changed.is_connected(_on_unit_control_mode_changed):
		_tracked_unit.control_mode_changed.connect(_on_unit_control_mode_changed)
	if not _tracked_unit.tree_exited.is_connected(_on_tracked_unit_tree_exited):
		_tracked_unit.tree_exited.connect(_on_tracked_unit_tree_exited)

	_tracked_carry_load = _tracked_unit.get_carry_load()
	if _tracked_carry_load != null:
		if not _tracked_carry_load.load_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.load_changed.connect(_on_carry_changed)
		if not _tracked_carry_load.capacity_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.capacity_changed.connect(_on_carry_changed)


func _unbind_tracked_unit() -> void:
	if _tracked_unit != null and is_instance_valid(_tracked_unit):
		if _tracked_unit.state_changed.is_connected(_on_unit_state_changed):
			_tracked_unit.state_changed.disconnect(_on_unit_state_changed)
		if _tracked_unit.control_mode_changed.is_connected(_on_unit_control_mode_changed):
			_tracked_unit.control_mode_changed.disconnect(_on_unit_control_mode_changed)
		if _tracked_unit.tree_exited.is_connected(_on_tracked_unit_tree_exited):
			_tracked_unit.tree_exited.disconnect(_on_tracked_unit_tree_exited)
	if _tracked_carry_load != null:
		if _tracked_carry_load.load_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.load_changed.disconnect(_on_carry_changed)
		if _tracked_carry_load.capacity_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.capacity_changed.disconnect(_on_carry_changed)
	_tracked_unit = null
	_tracked_carry_load = null


func _unbind_community_work_board() -> void:
	if _community_work_board != null and is_instance_valid(_community_work_board):
		if _community_work_board.task_registered.is_connected(_on_board_task_changed):
			_community_work_board.task_registered.disconnect(_on_board_task_changed)
		if _community_work_board.task_updated.is_connected(_on_board_task_changed):
			_community_work_board.task_updated.disconnect(_on_board_task_changed)
		if _community_work_board.task_closed.is_connected(_on_board_task_changed):
			_community_work_board.task_closed.disconnect(_on_board_task_changed)
	_community_work_board = null


func _on_board_task_changed(_task: WorkTask) -> void:
	if _mode == SelectionMode.SINGLE:
		_render_current()


func _on_unit_state_changed(_new_state: Unit.State, _previous_state: Unit.State) -> void:
	_render_current()


func _on_unit_control_mode_changed(
	_new_mode: UnitControlState.ControlMode,
	_previous_mode: UnitControlState.ControlMode
) -> void:
	_render_current()


func _on_carry_changed() -> void:
	_render_current()


func _on_tracked_unit_tree_exited() -> void:
	_unbind_tracked_unit()
	_mode = SelectionMode.EMPTY
	_selected_count = 0
	_render_current()


func _render_current() -> void:
	var next_key: Dictionary = _build_render_key()
	if _has_rendered and _render_keys_match(_last_render_key, next_key):
		return
	_apply_render_key(next_key)


func _build_render_key() -> Dictionary:
	if _mode == SelectionMode.SINGLE and not _is_unit_valid(_tracked_unit):
		_unbind_tracked_unit()
		_mode = SelectionMode.EMPTY
		_selected_count = 0

	if _mode == SelectionMode.EMPTY:
		return {
			"mode": SelectionMode.EMPTY,
			"count": 0,
			"name": "",
			"state": "",
			"inspection_meta": "",
			"display_pct": 0,
			"fill_pct": 0.0,
			"weight": 0,
			"capacity": 0,
			"overloaded": false,
			"wood": 0,
			"stone": 0,
			"food": 0,
			"percentage_text": "0%",
			"weight_text": "Peso transportado: 0 / 0",
		}

	if _mode == SelectionMode.MULTI:
		return {
			"mode": SelectionMode.MULTI,
			"count": _selected_count,
			"name": "%d selecionados" % _selected_count,
			"state": "",
			"inspection_meta": "",
			"display_pct": 0,
			"fill_pct": 0.0,
			"weight": 0,
			"capacity": 0,
			"overloaded": false,
			"wood": 0,
			"stone": 0,
			"food": 0,
			"pct_text": "",
			"weight_text": "",
		}

	var carry_load: UnitCarryLoad = _tracked_carry_load if _tracked_carry_load != null else _tracked_unit.get_carry_load()
	var carry: Dictionary = HudFormatter.build_carry_snapshot(carry_load)
	return {
		"mode": SelectionMode.SINGLE,
		"count": 1,
		"name": HudFormatter.format_unit_name(_tracked_unit),
		"state": HudFormatter.format_unit_state(_tracked_unit.get_state()),
		"inspection_meta": HudFormatter.format_unit_inspection_meta(_tracked_unit, _community_work_board),
		"display_pct": int(carry.get("display_percentage", 0)),
		"fill_pct": float(carry.get("fill_percentage", 0.0)),
		"weight": int(carry.get("current_weight", 0)),
		"capacity": int(carry.get("effective_capacity", 0)),
		"overloaded": bool(carry.get("is_overloaded", false)),
		"wood": int(carry.get("wood", 0)),
		"stone": int(carry.get("stone", 0)),
		"food": int(carry.get("food", 0)),
		"pct_text": str(carry.get("percentage_text", "0%")),
		"weight_text": str(carry.get("weight_text", "Peso transportado: 0 / 0")),
	}


func _apply_render_key(key: Dictionary) -> void:
	_last_render_key = key.duplicate()
	if not is_node_ready():
		return

	var mode_val: int = int(key.get("mode", SelectionMode.EMPTY))
	if mode_val == SelectionMode.EMPTY:
		visible = false
		if _unit_name_label != null:
			_unit_name_label.text = ""
		if _unit_state_label != null:
			_unit_state_label.text = ""
			_unit_state_label.visible = false
		if _single_content != null:
			_single_content.visible = false
		if _multi_summary_label != null:
			_multi_summary_label.visible = false
		_has_rendered = true
		_apply_count += 1
		return

	visible = true
	if _unit_name_label != null:
		_unit_name_label.text = str(key.get("name", ""))

	if mode_val == SelectionMode.MULTI:
		if _unit_state_label != null:
			_unit_state_label.text = ""
			_unit_state_label.visible = false
		if _single_content != null:
			_single_content.visible = false
		if _multi_summary_label != null:
			_multi_summary_label.visible = true
		_has_rendered = true
		_apply_count += 1
		return

	# SelectionMode.SINGLE
	if _unit_state_label != null:
		_unit_state_label.text = str(key.get("state", "Ocioso"))
		_unit_state_label.visible = true
	if _multi_summary_label != null:
		_multi_summary_label.visible = false
	if _single_content != null:
		_single_content.visible = true
	if _inspection_meta_label != null:
		var meta_text: String = str(key.get("inspection_meta", ""))
		_inspection_meta_label.text = meta_text
		_inspection_meta_label.visible = not meta_text.is_empty()

	var fill_pct: float = clampf(float(key.get("fill_pct", 0.0)), 0.0, 100.0)
	var display_pct: int = int(key.get("display_pct", 0))
	var overloaded: bool = bool(key.get("overloaded", false))
	var wood: int = int(key.get("wood", 0))
	var stone: int = int(key.get("stone", 0))
	var food: int = int(key.get("food", 0))

	if _carry_bar != null:
		_carry_bar.value = fill_pct
		if overloaded:
			_apply_bar_tier(BarTier.OVERLOAD)
		elif display_pct >= 90:
			_apply_bar_tier(BarTier.HIGH)
		else:
			_apply_bar_tier(BarTier.NORMAL)

	if _percentage_label != null:
		_percentage_label.text = str(key.get("pct_text", "0%"))
		_percentage_label.add_theme_color_override(
			&"font_color",
			HudStyle.BAR_FILL_OVERLOAD_COLOR if overloaded else HudStyle.TEXT_PRIMARY_COLOR
		)

	if _weight_label != null:
		_weight_label.text = str(key.get("weight_text", "Peso transportado: 0 / 0"))
		_weight_label.add_theme_color_override(
			&"font_color",
			HudStyle.EXPOSURE_ACTIVE_COLOR if overloaded else HudStyle.TEXT_SECONDARY_COLOR
		)

	_apply_carried_label(_wood_label, "Madeira", wood)
	_apply_carried_label(_stone_label, "Pedra", stone)
	_apply_carried_label(_food_label, "Alimentos", food)

	_has_rendered = true
	_apply_count += 1


func _apply_carried_label(label: Label, label_name: String, amount: int) -> void:
	if label == null:
		return
	label.text = "%s: %d un" % [label_name, amount]
	label.add_theme_color_override(
		&"font_color",
		HudStyle.TEXT_PRIMARY_COLOR if amount > 0 else HudStyle.TEXT_MUTED_COLOR
	)


func _apply_bar_tier(tier: BarTier) -> void:
	if _carry_bar == null or _active_bar_tier == tier:
		return
	_active_bar_tier = tier
	match tier:
		BarTier.OVERLOAD:
			if _bar_fill_overload != null:
				_carry_bar.add_theme_stylebox_override(&"fill", _bar_fill_overload)
		BarTier.HIGH:
			if _bar_fill_high != null:
				_carry_bar.add_theme_stylebox_override(&"fill", _bar_fill_high)
		_:
			if _bar_fill_normal != null:
				_carry_bar.add_theme_stylebox_override(&"fill", _bar_fill_normal)


static func _is_unit_valid(unit: Unit) -> bool:
	return unit != null and is_instance_valid(unit) and not unit.is_queued_for_deletion()


static func _render_keys_match(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("mode", -1)) == int(b.get("mode", -2))
		and int(a.get("count", -1)) == int(b.get("count", -2))
		and str(a.get("name", "")) == str(b.get("name", ""))
		and str(a.get("state", "")) == str(b.get("state", ""))
		and str(a.get("inspection_meta", "")) == str(b.get("inspection_meta", ""))
		and int(a.get("display_pct", -1)) == int(b.get("display_pct", -2))
		and is_equal_approx(float(a.get("fill_pct", -1.0)), float(b.get("fill_pct", -2.0)))
		and int(a.get("weight", -1)) == int(b.get("weight", -2))
		and int(a.get("capacity", -1)) == int(b.get("capacity", -2))
		and bool(a.get("overloaded", false)) == bool(b.get("overloaded", true))
		and int(a.get("wood", -1)) == int(b.get("wood", -2))
		and int(a.get("stone", -1)) == int(b.get("stone", -2))
		and int(a.get("food", -1)) == int(b.get("food", -2))
	)
