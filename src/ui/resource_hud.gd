class_name ResourceHud
extends Control
## Non-blocking T2.5 HUD coordinator composing SettlementStockpilePanel and SelectedUnitPanel.
## Connects to SelectionManager and SettlementInventory signals without per-frame polling.

@onready var _stockpile_panel: SettlementStockpilePanel = $SettlementStockpilePanel
@onready var _selected_unit_panel: SelectedUnitPanel = $SelectedUnitPanel

var _selection_manager: SelectionManager = null


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	HudStyle.apply_mouse_filter_ignore_recursive(self)


func _exit_tree() -> void:
	unbind()


func configure(
	settlement_inventory: SettlementInventory,
	selection_manager: SelectionManager,
	camp_storage_zone: CampStorageZone = null,
	ground_pile_manager: GroundPileManager = null
) -> void:
	if _selection_manager != selection_manager:
		_disconnect_selection_manager()
		_selection_manager = selection_manager
		if _selection_manager != null and not _selection_manager.selection_changed.is_connected(_on_selection_changed):
			_selection_manager.selection_changed.connect(_on_selection_changed)

	if _stockpile_panel != null:
		_stockpile_panel.configure(settlement_inventory, camp_storage_zone, ground_pile_manager)

	if _selected_unit_panel != null:
		var initial_units: Array[Unit] = _selection_manager.get_selected_units() if _selection_manager != null else []
		_selected_unit_panel.set_selected_units(initial_units)


func unbind() -> void:
	_disconnect_selection_manager()
	_selection_manager = null
	if _stockpile_panel != null:
		_stockpile_panel.unbind()
	if _selected_unit_panel != null:
		_selected_unit_panel.unbind()


func refresh_all() -> void:
	if _stockpile_panel != null:
		_stockpile_panel.refresh()
	if _selected_unit_panel != null:
		_selected_unit_panel.refresh()


func get_stockpile_panel() -> SettlementStockpilePanel:
	return _stockpile_panel


func get_selected_unit_panel() -> SelectedUnitPanel:
	return _selected_unit_panel


func is_bound_to_selection_manager(manager: SelectionManager) -> bool:
	return _selection_manager != null and _selection_manager == manager and _selection_manager.selection_changed.is_connected(_on_selection_changed)


func _on_selection_changed(selected_units: Array[Unit]) -> void:
	if _selected_unit_panel != null:
		_selected_unit_panel.set_selected_units(selected_units)


func _disconnect_selection_manager() -> void:
	if _selection_manager != null and is_instance_valid(_selection_manager):
		if _selection_manager.selection_changed.is_connected(_on_selection_changed):
			_selection_manager.selection_changed.disconnect(_on_selection_changed)
