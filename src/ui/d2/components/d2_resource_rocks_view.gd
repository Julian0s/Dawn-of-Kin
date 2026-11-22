class_name D2ResourceRocksView
extends Control
## D2.2 Top-Left 3 stepped independent river-stone resource monoliths (Wood, Stone, Food).
## Strictly signal-driven via SettlementInventory.inventory_changed and HudFormatter; zero polling.
## In UI-1.1A all controls remain MOUSE_FILTER_IGNORE (polygonal hitboxes arrive in UI-1.1B).

const RESOURCE_ORDER: Array[StringName] = [&"wood", &"stone", &"food"]
const ICON_KEYS: Array[String] = ["ico_wood", "ico_stone", "ico_food"]

var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _inventory: SettlementInventory = null
var _camp_zone: CampStorageZone = null
var _pile_manager: GroundPileManager = null

var _slabs: Array[TextureRect] = []
var _icons: Array[TextureRect] = []
var _value_labels: Array[Label] = []
var _built: bool = false
var _scale_factor: float = D2Tokens.SCALE_1080P

var _last_amounts: Dictionary = {}
var _has_rendered: bool = false
var _apply_count: int = 0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _exit_tree() -> void:
	unbind()


func setup_visuals(atlas: D2AtlasLibrary, theme_factory: D2ThemeFactory, scale_factor: float = 1.0) -> void:
	_atlas = atlas
	_theme_factory = theme_factory
	_scale_factor = scale_factor
	if not _built:
		_build_nodes()
	apply_scale(_scale_factor)
	refresh()


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


func apply_scale(scale_factor: float) -> void:
	_scale_factor = scale_factor
	if not _built or _atlas == null:
		return
	var meta: Dictionary = _atlas.get_region_metadata("resource_rock")
	var pad: float = float(meta.get("pad", 10.0))
	var rw: float = float(meta.get("w", 104.0))
	var rh: float = float(meta.get("h", 62.0))
	var s: float = _scale_factor
	var x0: float = D2Tokens.ROCK_ORIGIN.x * s
	var y0: float = D2Tokens.ROCK_ORIGIN.y * s
	var font_px: int = maxi(10, int(round(D2Tokens.ROCK_FONT_SIZE * s)))
	var serif_bold: Font = _theme_factory.get_serif_font(true) if _theme_factory != null else null

	for i: int in range(3):
		var rx: float = x0 + float(i) * (D2Tokens.ROCK_CONTENT_SIZE.x + D2Tokens.ROCK_GAP_X) * s
		var ry: float = y0 + D2Tokens.ROCK_OFFSETS_Y[i] * s

		var slab: TextureRect = _slabs[i]
		var slab_sz := Vector2(rw * s, rh * s)
		slab.position = Vector2(rx - pad * s, ry - pad * s)
		slab.custom_minimum_size = slab_sz
		slab.size = slab_sz

		var icon: TextureRect = _icons[i]
		icon.position = Vector2(rx + D2Tokens.ROCK_ICON_OFFSET.x * s, ry + D2Tokens.ROCK_ICON_OFFSET.y * s)
		var icon_sz := Vector2(D2Tokens.ROCK_ICON_SIZE * s, D2Tokens.ROCK_ICON_SIZE * s)
		icon.custom_minimum_size = icon_sz
		icon.size = icon_sz

		var lbl: Label = _value_labels[i]
		lbl.position = Vector2(rx + D2Tokens.ROCK_LABEL_OFFSET.x * s, ry + D2Tokens.ROCK_LABEL_OFFSET.y * s)
		lbl.size = Vector2(D2Tokens.ROCK_LABEL_SIZE.x * s, D2Tokens.ROCK_LABEL_SIZE.y * s)
		lbl.add_theme_font_size_override(&"font_size", font_px)
		if serif_bold != null:
			lbl.add_theme_font_override(&"font", serif_bold)


func refresh() -> void:
	var snap: Dictionary = HudFormatter.build_stockpile_snapshot(_inventory, _camp_zone, _pile_manager)
	var wood: int = int(snap.get("wood", 0))
	var stone: int = int(snap.get("stone", 0))
	var food: int = int(snap.get("food", 0))
	if _has_rendered:
		if int(_last_amounts.get(&"wood", -1)) == wood \
			and int(_last_amounts.get(&"stone", -1)) == stone \
			and int(_last_amounts.get(&"food", -1)) == food:
			return
	_last_amounts = {&"wood": wood, &"stone": stone, &"food": food}
	if not _built:
		return
	_value_labels[0].text = "%d" % wood
	_value_labels[1].text = "%d" % stone
	_value_labels[2].text = "%d" % food
	_has_rendered = true
	_apply_count += 1


func get_displayed_amount(resource_id: StringName) -> int:
	return int(_last_amounts.get(resource_id, 0))


func get_displayed_text(resource_id: StringName) -> String:
	var idx: int = RESOURCE_ORDER.find(resource_id)
	if idx < 0 or idx >= _value_labels.size():
		return ""
	return _value_labels[idx].text


func get_apply_count() -> int:
	return _apply_count


func is_bound_to_inventory(inventory: SettlementInventory) -> bool:
	return _inventory != null and _inventory == inventory and _inventory.inventory_changed.is_connected(_on_inventory_changed)


func get_content_bounds() -> Rect2:
	var s: float = _scale_factor
	var x0: float = D2Tokens.ROCK_ORIGIN.x * s
	var y0: float = D2Tokens.ROCK_ORIGIN.y * s
	var total_w: float = (3.0 * D2Tokens.ROCK_CONTENT_SIZE.x + 2.0 * D2Tokens.ROCK_GAP_X) * s
	var max_y_off: float = 7.0 * s
	var total_h: float = max_y_off + D2Tokens.ROCK_CONTENT_SIZE.y * s
	return Rect2(x0, y0, total_w, total_h)


func get_rock_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var s: float = _scale_factor
	var x0: float = D2Tokens.ROCK_ORIGIN.x * s
	var y0: float = D2Tokens.ROCK_ORIGIN.y * s
	for i: int in range(3):
		var rx: float = x0 + float(i) * (D2Tokens.ROCK_CONTENT_SIZE.x + D2Tokens.ROCK_GAP_X) * s
		var ry: float = y0 + D2Tokens.ROCK_OFFSETS_Y[i] * s
		rects.append(Rect2(rx, ry, D2Tokens.ROCK_CONTENT_SIZE.x * s, D2Tokens.ROCK_CONTENT_SIZE.y * s))
	return rects


func _build_nodes() -> void:
	_built = true
	_slabs.clear()
	_icons.clear()
	_value_labels.clear()
	var rock_tex: AtlasTexture = _atlas.get_region_texture("resource_rock") if _atlas != null else null
	for i: int in range(3):
		var res_name: String = String(RESOURCE_ORDER[i])
		var slab := TextureRect.new()
		slab.name = "RockSlab_%s" % res_name
		slab.texture = rock_tex
		slab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slab.stretch_mode = TextureRect.STRETCH_SCALE
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slab)
		_slabs.append(slab)

		var icon := TextureRect.new()
		icon.name = "RockIcon_%s" % res_name
		icon.texture = _atlas.get_region_texture(ICON_KEYS[i]) if _atlas != null else null
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		_icons.append(icon)

		var lbl := Label.new()
		lbl.name = "RockValue_%s" % res_name
		lbl.text = "0"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
		add_child(lbl)
		_value_labels.append(lbl)


func _on_inventory_changed() -> void:
	refresh()


func _disconnect_inventory() -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
