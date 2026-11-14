class_name SettlementStockpilePanel
extends PanelContainer
## Compact top-right HUD panel displaying settlement collective stockpile from
## SettlementInventory and truthful camp storage exposure status.
## Driven strictly by inventory signals; never runs per-frame polling.

@onready var _wood_value_label: Label = $Margin/VBox/ResourcesRow/WoodItem/ValueLabel
@onready var _stone_value_label: Label = $Margin/VBox/ResourcesRow/StoneItem/ValueLabel
@onready var _food_value_label: Label = $Margin/VBox/ResourcesRow/FoodItem/ValueLabel
@onready var _exposure_label: Label = $Margin/VBox/ExposureLabel

var _inventory: SettlementInventory = null
var _camp_zone: CampStorageZone = null
var _pile_manager: GroundPileManager = null
var _last_snapshot: Dictionary = {}
var _has_rendered: bool = false
var _apply_count: int = 0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	HudStyle.apply_mouse_filter_ignore_recursive(self)
	add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	refresh()


func _exit_tree() -> void:
	unbind()


func configure(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone = null,
	pile_manager: GroundPileManager = null
) -> void:
	if _inventory != inventory:
		_disconnect_inventory()
		_inventory = inventory
		if _inventory != null and not _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.connect(_on_inventory_changed)

	_camp_zone = camp_zone
	_pile_manager = pile_manager
	refresh()


func unbind() -> void:
	_disconnect_inventory()
	_inventory = null
	_camp_zone = null
	_pile_manager = null


func refresh() -> void:
	var next_snapshot: Dictionary = HudFormatter.build_stockpile_snapshot(_inventory, _camp_zone, _pile_manager)
	if _has_rendered and _snapshots_match(_last_snapshot, next_snapshot):
		return
	_apply_snapshot(next_snapshot)


func get_displayed_amount(resource_id: StringName) -> int:
	match resource_id:
		&"wood":
			return int(_last_snapshot.get("wood", 0))
		&"stone":
			return int(_last_snapshot.get("stone", 0))
		&"food":
			return int(_last_snapshot.get("food", 0))
		_:
			return 0


func get_wood_value_text() -> String:
	return _wood_value_label.text if _wood_value_label != null else ""


func get_stone_value_text() -> String:
	return _stone_value_label.text if _stone_value_label != null else ""


func get_food_value_text() -> String:
	return _food_value_label.text if _food_value_label != null else ""


func get_exposure_text() -> String:
	return _exposure_label.text if _exposure_label != null else ""


func get_apply_count() -> int:
	return _apply_count


func is_bound_to_inventory(inventory: SettlementInventory) -> bool:
	return _inventory != null and _inventory == inventory and _inventory.inventory_changed.is_connected(_on_inventory_changed)


func _on_inventory_changed() -> void:
	refresh()


func _disconnect_inventory() -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)


func _apply_snapshot(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate()
	if not is_node_ready():
		return

	var wood: int = int(snapshot.get("wood", 0))
	var stone: int = int(snapshot.get("stone", 0))
	var food: int = int(snapshot.get("food", 0))
	var exposure_text: String = str(snapshot.get("exposure_text", "Armazenamento: exposto"))
	var exposure_tone: int = int(snapshot.get("exposure_tone", HudFormatter.ExposureTone.EXPOSED_IDLE))

	if _wood_value_label != null:
		_wood_value_label.text = "%d" % wood
	if _stone_value_label != null:
		_stone_value_label.text = "%d" % stone
	if _food_value_label != null:
		_food_value_label.text = "%d" % food
	if _exposure_label != null:
		_exposure_label.text = exposure_text
		match exposure_tone:
			HudFormatter.ExposureTone.PROTECTED:
				_exposure_label.add_theme_color_override(&"font_color", HudStyle.EXPOSURE_PROTECTED_COLOR)
			HudFormatter.ExposureTone.EXPOSED_ACTIVE:
				_exposure_label.add_theme_color_override(&"font_color", HudStyle.EXPOSURE_ACTIVE_COLOR)
			_:
				_exposure_label.add_theme_color_override(&"font_color", HudStyle.EXPOSURE_IDLE_COLOR)

	_has_rendered = true
	_apply_count += 1


static func _snapshots_match(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("wood", -1)) == int(b.get("wood", -2))
		and int(a.get("stone", -1)) == int(b.get("stone", -2))
		and int(a.get("food", -1)) == int(b.get("food", -2))
		and int(a.get("exposure_tone", -1)) == int(b.get("exposure_tone", -2))
		and str(a.get("exposure_text", "")) == str(b.get("exposure_text", ""))
	)
