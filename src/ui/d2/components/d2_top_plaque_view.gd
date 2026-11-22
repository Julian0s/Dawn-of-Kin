class_name D2TopPlaqueView
extends Control
## D2.2 Top-Right peaked dark kintsugi plaque displaying region identity and truthful
## storage exposure status.
## Safeguard 2 (UI-1.1A): time slots (||, 1x, 2x, 4x) and Menu indicator are strictly
## inert visual placeholders (MOUSE_FILTER_IGNORE, muted disabled styling, zero callbacks).
## Zero invented seasons, calendar dates, or simulated speeds.

const REGION_TITLE: String = "CLAREIRA INICIAL"
const STAGE_SUBTITLE: String = "Acampamento"
const INERT_TIME_LABELS: Array[String] = ["||", "1×", "2×", "4×"]
const INERT_TIME_WIDTHS: Array[float] = [22.0, 28.0, 26.0, 26.0]

var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _inventory: SettlementInventory = null
var _camp_zone: CampStorageZone = null
var _pile_manager: GroundPileManager = null

var _slab: TextureRect = null
var _region_label: Label = null
var _stage_label: Label = null
var _time_boxes: Array[Panel] = []
var _time_labels: Array[Label] = []
var _exposure_label: Label = null
var _menu_inert_label: Label = null

var _built: bool = false
var _scale_factor: float = D2Tokens.SCALE_1080P
var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var _last_exposure_tone: int = -1
var _last_exposure_short: String = ""
var _has_rendered: bool = false
var _apply_count: int = 0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _exit_tree() -> void:
	unbind()


func setup_visuals(
	atlas: D2AtlasLibrary,
	theme_factory: D2ThemeFactory,
	viewport_size: Vector2,
	scale_factor: float = 1.0
) -> void:
	_atlas = atlas
	_theme_factory = theme_factory
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built:
		_build_nodes()
	apply_layout(_viewport_size, _scale_factor)
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


func apply_layout(viewport_size: Vector2, scale_factor: float) -> void:
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built or _atlas == null:
		return
	var s: float = _scale_factor
	var meta: Dictionary = _atlas.get_region_metadata("top_plaque")
	var pad: float = float(meta.get("pad", 10.0))
	var rw: float = float(meta.get("w", 216.0))
	var rh: float = float(meta.get("h", 130.0))
	var pw: float = D2Tokens.PLAQUE_CONTENT_SIZE.x * s
	var px: float = _viewport_size.x - D2Tokens.PLAQUE_MARGIN_RIGHT * s - pw
	var py: float = D2Tokens.PLAQUE_MARGIN_TOP * s

	var serif_bold: Font = _theme_factory.get_serif_font(true) if _theme_factory != null else null
	var sans_reg: Font = _theme_factory.get_sans_font(false) if _theme_factory != null else null
	var sans_bold: Font = _theme_factory.get_sans_font(true) if _theme_factory != null else null

	var slab_sz := Vector2(rw * s, rh * s)
	_slab.position = Vector2(px - pad * s, py - pad * s)
	_slab.custom_minimum_size = slab_sz
	_slab.size = slab_sz

	_region_label.position = Vector2(px + 10.0 * s, py + 11.0 * s)
	_region_label.size = Vector2(pw - 20.0 * s, 14.0 * s)
	_region_label.add_theme_font_size_override(&"font_size", maxi(9, int(round(9.5 * s))))
	if sans_bold != null:
		_region_label.add_theme_font_override(&"font", sans_bold)

	_stage_label.position = Vector2(px + 10.0 * s, py + 25.0 * s)
	_stage_label.size = Vector2(pw - 20.0 * s, 24.0 * s)
	_stage_label.add_theme_font_size_override(&"font_size", maxi(11, int(round(16.0 * s))))
	if serif_bold != null:
		_stage_label.add_theme_font_override(&"font", serif_bold)

	var total_w: float = (22.0 + 28.0 + 26.0 + 26.0 + 15.0) * s
	var sx: float = px + (pw - total_w) * 0.5
	var sy: float = py + 55.0 * s
	var slot_font_px: int = maxi(9, int(round(10.5 * s)))
	for j: int in range(4):
		var bw: float = INERT_TIME_WIDTHS[j] * s
		var bh: float = 21.0 * s
		_time_boxes[j].position = Vector2(sx, sy)
		_time_boxes[j].size = Vector2(bw, bh)
		_time_labels[j].position = Vector2(sx, sy)
		_time_labels[j].size = Vector2(bw, bh)
		_time_labels[j].add_theme_font_size_override(&"font_size", slot_font_px)
		if sans_reg != null:
			_time_labels[j].add_theme_font_override(&"font", sans_reg)
		sx += bw + 5.0 * s

	var footer_y: float = py + 82.0 * s
	var footer_h: float = 18.0 * s
	var footer_font_px: int = maxi(9, int(round(9.8 * s)))
	_exposure_label.position = Vector2(px + 10.0 * s, footer_y)
	_exposure_label.size = Vector2(96.0 * s, footer_h)
	_exposure_label.add_theme_font_size_override(&"font_size", footer_font_px)
	if sans_bold != null:
		_exposure_label.add_theme_font_override(&"font", sans_bold)

	_menu_inert_label.position = Vector2(px + 108.0 * s, footer_y)
	_menu_inert_label.size = Vector2(78.0 * s, footer_h)
	_menu_inert_label.add_theme_font_size_override(&"font_size", footer_font_px)
	if sans_reg != null:
		_menu_inert_label.add_theme_font_override(&"font", sans_reg)


func refresh() -> void:
	var snap: Dictionary = HudFormatter.build_stockpile_snapshot(_inventory, _camp_zone, _pile_manager)
	var tone: int = int(snap.get("exposure_tone", HudFormatter.ExposureTone.EXPOSED_IDLE))
	var short_text: String = "● PROTEGIDO" if tone == HudFormatter.ExposureTone.PROTECTED else "● EXPOSTO"
	if _has_rendered and _last_exposure_tone == tone and _last_exposure_short == short_text:
		return
	_last_exposure_tone = tone
	_last_exposure_short = short_text
	if not _built:
		return
	_exposure_label.text = short_text
	match tone:
		HudFormatter.ExposureTone.PROTECTED:
			_exposure_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT)
		HudFormatter.ExposureTone.EXPOSED_ACTIVE:
			_exposure_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_AMBER)
		_:
			_exposure_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
	_has_rendered = true
	_apply_count += 1


func get_exposure_text() -> String:
	return _exposure_label.text if _exposure_label != null else ""


func get_exposure_tone() -> int:
	return _last_exposure_tone


func get_stage_subtitle_text() -> String:
	return _stage_label.text if _stage_label != null else ""


func get_apply_count() -> int:
	return _apply_count


func has_interactive_buttons() -> bool:
	return _has_button_descendant(self)


func get_content_bounds() -> Rect2:
	var s: float = _scale_factor
	var pw: float = D2Tokens.PLAQUE_CONTENT_SIZE.x * s
	var ph: float = D2Tokens.PLAQUE_CONTENT_SIZE.y * s
	var px: float = _viewport_size.x - D2Tokens.PLAQUE_MARGIN_RIGHT * s - pw
	var py: float = D2Tokens.PLAQUE_MARGIN_TOP * s
	return Rect2(px, py, pw, ph)


func is_bound_to_inventory(inventory: SettlementInventory) -> bool:
	return _inventory != null and _inventory == inventory and _inventory.inventory_changed.is_connected(_on_inventory_changed)


func _build_nodes() -> void:
	_built = true
	_time_boxes.clear()
	_time_labels.clear()

	_slab = TextureRect.new()
	_slab.name = "TopPlaqueSlab"
	_slab.texture = _atlas.get_region_texture("top_plaque") if _atlas != null else null
	_slab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slab.stretch_mode = TextureRect.STRETCH_SCALE
	_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slab)

	_region_label = Label.new()
	_region_label.name = "RegionLabel"
	_region_label.text = REGION_TITLE
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_region_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_region_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
	add_child(_region_label)

	_stage_label = Label.new()
	_stage_label.name = "StageLabel"
	_stage_label.text = STAGE_SUBTITLE
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
	add_child(_stage_label)

	var disabled_box_style := StyleBoxFlat.new()
	disabled_box_style.bg_color = D2Tokens.COLOR_DISABLED_FILL
	disabled_box_style.border_color = D2Tokens.COLOR_DISABLED_BORDER
	disabled_box_style.set_border_width_all(1)

	for j: int in range(4):
		var box := Panel.new()
		box.name = "InertTimeSlot_%d" % j
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override(&"panel", disabled_box_style)
		add_child(box)
		_time_boxes.append(box)

		var lbl := Label.new()
		lbl.name = "InertTimeLabel_%d" % j
		lbl.text = INERT_TIME_LABELS[j]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_DISABLED_TEXT)
		add_child(lbl)
		_time_labels.append(lbl)

	_exposure_label = Label.new()
	_exposure_label.name = "ExposureLabel"
	_exposure_label.text = "● EXPOSTO"
	_exposure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_exposure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exposure_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exposure_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
	add_child(_exposure_label)

	_menu_inert_label = Label.new()
	_menu_inert_label.name = "InertMenuLabel"
	_menu_inert_label.text = "· ☰ MENU"
	_menu_inert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_menu_inert_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_menu_inert_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_inert_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_DISABLED_TEXT)
	add_child(_menu_inert_label)


func _on_inventory_changed() -> void:
	refresh()


func _disconnect_inventory() -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)


static func _has_button_descendant(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is BaseButton:
			return true
		if _has_button_descendant(child):
			return true
	return false
