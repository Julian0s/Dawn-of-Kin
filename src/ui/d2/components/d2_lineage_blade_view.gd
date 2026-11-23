class_name D2LineageBladeView
extends Control
## D2.2 Bottom-Left contextual basalt kintsugi unit & lineage blade (UI-1.2).
##
## Design & Architecture Rules:
## - Uses canonical atlas region "lineage_blade" (474x234 with 10 px shadow_pad; 454x214 content)
##   backed by D2PolygonalSlab (_has_point + Geometry2D.is_point_in_polygon).
## - Displays strictly TRUTHFUL simulation data via SelectionManager, Unit, UnitCarryLoad, and
##   HudFormatter (build_carry_snapshot, format_unit_name, format_unit_state):
##   - EMPTY: hidden cleanly, zero stale text, zero blocking hitbox.
##   - SINGLE: unit name, real activity state badge, capacity, current weight, fill %, overload
##     callout, and real carried Wood / Stone / Food counts.
##   - MULTI: real selected count and truthful per-unit name/state list with ZERO invented
##     combined resource sums or individual stats masquerading as group totals.
## - Zero invented T5 genealogy, health/vigor/satiety stats, or unimplemented action buttons.
## - Strictly signal-driven; zero per-frame polling; process_mode = PROCESS_MODE_PAUSABLE.

enum SelectionMode {
	EMPTY,
	SINGLE,
	MULTI,
}

const RESOURCE_KEYS: Array[StringName] = [&"wood", &"stone", &"food"]
const RESOURCE_NAMES: Array[String] = ["Madeira", "Pedra", "Alimento"]
const RESOURCE_ICONS: Array[String] = ["ico_wood", "ico_stone", "ico_food"]
const MAX_MULTI_ROWS: int = 4

var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _selection_manager: SelectionManager = null

var _mode: SelectionMode = SelectionMode.EMPTY
var _selected_count: int = 0
var _tracked_unit: Unit = null
var _tracked_carry_load: UnitCarryLoad = null
var _tracked_group_units: Array[Unit] = []

var _slab: D2PolygonalSlab = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _badge_box: Panel = null
var _badge_style: StyleBoxFlat = null
var _badge_label: Label = null
var _header_divider: Panel = null

# Single-selection content nodes
var _carry_header_label: Label = null
var _carry_pct_label: Label = null
var _carry_track: Panel = null
var _carry_fill: Panel = null
var _carry_fill_style: StyleBoxFlat = null
var _weight_label: Label = null
var _capacity_or_overload_label: Label = null
var _col_divider: Panel = null
var _materials_header_label: Label = null
var _mat_icons: Array[TextureRect] = []
var _mat_name_labels: Array[Label] = []
var _mat_value_labels: Array[Label] = []

# Multi-selection content nodes
var _multi_summary_label: Label = null
var _multi_hint_label: Label = null

var _built: bool = false
var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var _scale_factor: float = D2Tokens.SCALE_1080P
var _content_rect: Rect2 = Rect2()
var _last_render_key: Dictionary = {}
var _has_rendered: bool = false
var _apply_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


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


func configure(selection_manager: SelectionManager) -> void:
	if _selection_manager != selection_manager:
		_disconnect_selection_manager()
		_selection_manager = selection_manager
		if _selection_manager != null and not _selection_manager.selection_changed.is_connected(_on_selection_changed):
			_selection_manager.selection_changed.connect(_on_selection_changed)
	var current: Array[Unit] = _selection_manager.get_selected_units() if _selection_manager != null else []
	set_selected_units(current)


func set_selected_units(selected_units: Array[Unit]) -> void:
	var valid_units: Array[Unit] = []
	for u: Unit in selected_units:
		if _is_unit_valid(u) and not valid_units.has(u):
			valid_units.append(u)

	if valid_units.is_empty():
		_unbind_all_units()
		_mode = SelectionMode.EMPTY
		_selected_count = 0
		_render_current()
		return

	if valid_units.size() == 1:
		var target: Unit = valid_units[0]
		if _tracked_unit != target or not _tracked_group_units.is_empty():
			_bind_single_unit(target)
		_mode = SelectionMode.SINGLE
		_selected_count = 1
		_render_current()
		return

	_bind_group_units(valid_units)
	_mode = SelectionMode.MULTI
	_selected_count = valid_units.size()
	_render_current()


func unbind() -> void:
	_disconnect_selection_manager()
	_selection_manager = null
	_unbind_all_units()
	_mode = SelectionMode.EMPTY
	_selected_count = 0
	if _built:
		_render_current()
	else:
		visible = false


func refresh() -> void:
	_render_current()


func apply_layout(viewport_size: Vector2, scale_factor: float) -> void:
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built or _atlas == null:
		return
	var s: float = _scale_factor
	var meta: Dictionary = _atlas.get_region_metadata("lineage_blade")
	var pad: float = float(meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
	var rw: float = float(meta.get("w", 474.0))
	var rh: float = float(meta.get("h", 234.0))
	var bw: float = D2Tokens.BLADE_CONTENT_SIZE.x * s
	var bh: float = D2Tokens.BLADE_CONTENT_SIZE.y * s
	var bx: float = (
		D2Tokens.STELE_ORIGIN_X
		+ 2.0 * D2Tokens.STELE_CONTENT_SIZE.x
		+ D2Tokens.STELE_GAP_X
		+ D2Tokens.BLADE_GAP_X
	) * s
	var by: float = _viewport_size.y - D2Tokens.BLADE_MARGIN_BOTTOM * s - bh
	_content_rect = Rect2(bx, by, bw, bh)

	var serif_bold: Font = _theme_factory.get_serif_font(true) if _theme_factory != null else null
	var sans_reg: Font = _theme_factory.get_sans_font(false) if _theme_factory != null else null
	var sans_bold: Font = _theme_factory.get_sans_font(true) if _theme_factory != null else null

	var slab_sz := Vector2(rw * s, rh * s)
	_slab.position = Vector2(bx - pad * s, by - pad * s)
	_slab.configure_polygon(D2Tokens.POLYGON_LINEAGE_BLADE, D2Tokens.BLADE_CONTENT_SIZE, pad)
	_slab.set_scaled_size(slab_sz)

	_title_label.position = Vector2(bx + 22.0 * s, by + 16.0 * s)
	_title_label.size = Vector2(286.0 * s, 26.0 * s)
	_title_label.add_theme_font_size_override(&"font_size", maxi(13, int(round(19.0 * s))))
	if serif_bold != null:
		_title_label.add_theme_font_override(&"font", serif_bold)

	_subtitle_label.position = Vector2(bx + 22.0 * s, by + 43.0 * s)
	_subtitle_label.size = Vector2(292.0 * s, 16.0 * s)
	_subtitle_label.add_theme_font_size_override(&"font_size", maxi(9, int(round(10.8 * s))))
	if sans_reg != null:
		_subtitle_label.add_theme_font_override(&"font", sans_reg)

	_badge_box.position = Vector2(bx + 320.0 * s, by + 20.0 * s)
	_badge_box.size = Vector2(112.0 * s, 24.0 * s)
	_badge_label.position = _badge_box.position
	_badge_label.size = _badge_box.size
	_badge_label.add_theme_font_size_override(&"font_size", maxi(8, int(round(9.5 * s))))
	if sans_bold != null:
		_badge_label.add_theme_font_override(&"font", sans_bold)

	_header_divider.position = Vector2(bx + 22.0 * s, by + 66.0 * s)
	_header_divider.size = Vector2(410.0 * s, maxf(1.0, 1.0 * s))

	# Single-unit left column (physical carry & weight)
	_carry_header_label.position = Vector2(bx + 22.0 * s, by + 79.0 * s)
	_carry_header_label.size = Vector2(166.0 * s, 18.0 * s)
	_carry_header_label.add_theme_font_size_override(&"font_size", maxi(10, int(round(12.0 * s))))
	if sans_bold != null:
		_carry_header_label.add_theme_font_override(&"font", sans_bold)

	_carry_pct_label.position = Vector2(bx + 190.0 * s, by + 79.0 * s)
	_carry_pct_label.size = Vector2(74.0 * s, 18.0 * s)
	_carry_pct_label.add_theme_font_size_override(&"font_size", maxi(10, int(round(12.5 * s))))
	if sans_bold != null:
		_carry_pct_label.add_theme_font_override(&"font", sans_bold)

	_carry_track.position = Vector2(bx + 22.0 * s, by + 104.0 * s)
	_carry_track.size = Vector2(242.0 * s, maxf(5.0, 8.0 * s))
	_carry_fill.position = _carry_track.position
	_carry_fill.size = Vector2(_carry_fill.size.x, _carry_track.size.y)

	_weight_label.position = Vector2(bx + 22.0 * s, by + 121.0 * s)
	_weight_label.size = Vector2(246.0 * s, 20.0 * s)
	_weight_label.add_theme_font_size_override(&"font_size", maxi(10, int(round(11.5 * s))))
	if sans_reg != null:
		_weight_label.add_theme_font_override(&"font", sans_reg)

	_capacity_or_overload_label.position = Vector2(bx + 22.0 * s, by + 148.0 * s)
	_capacity_or_overload_label.size = Vector2(246.0 * s, 22.0 * s)
	_capacity_or_overload_label.add_theme_font_size_override(&"font_size", maxi(9, int(round(10.8 * s))))
	if sans_bold != null:
		_capacity_or_overload_label.add_theme_font_override(&"font", sans_bold)

	# Vertical divider
	_col_divider.position = Vector2(bx + 278.0 * s, by + 78.0 * s)
	_col_divider.size = Vector2(maxf(1.0, 1.0 * s), 116.0 * s)

	# Single-unit right column (carried materials breakdown)
	_materials_header_label.position = Vector2(bx + 290.0 * s, by + 79.0 * s)
	_materials_header_label.size = Vector2(144.0 * s, 16.0 * s)
	_materials_header_label.add_theme_font_size_override(&"font_size", maxi(8, int(round(9.4 * s))))
	if sans_bold != null:
		_materials_header_label.add_theme_font_override(&"font", sans_bold)

	var ico_sz := Vector2(16.0 * s, 16.0 * s)
	var row_font: int = maxi(10, int(round(11.5 * s)))
	for i: int in range(3):
		var ry: float = by + (104.0 + float(i) * 28.0) * s
		_mat_icons[i].position = Vector2(bx + 290.0 * s, ry + 2.0 * s)
		_mat_icons[i].custom_minimum_size = ico_sz
		_mat_icons[i].size = ico_sz

		_mat_name_labels[i].position = Vector2(bx + 312.0 * s, ry)
		_mat_name_labels[i].size = Vector2(78.0 * s, 20.0 * s)
		_mat_name_labels[i].add_theme_font_size_override(&"font_size", row_font)
		if sans_reg != null:
			_mat_name_labels[i].add_theme_font_override(&"font", sans_reg)

		_mat_value_labels[i].position = Vector2(bx + 390.0 * s, ry)
		_mat_value_labels[i].size = Vector2(42.0 * s, 20.0 * s)
		_mat_value_labels[i].add_theme_font_size_override(&"font_size", row_font)
		if sans_bold != null:
			_mat_value_labels[i].add_theme_font_override(&"font", sans_bold)

	# Multi-selection content
	_multi_summary_label.position = Vector2(bx + 22.0 * s, by + 80.0 * s)
	_multi_summary_label.size = Vector2(410.0 * s, 82.0 * s)
	_multi_summary_label.add_theme_font_size_override(&"font_size", maxi(10, int(round(12.2 * s))))
	if sans_reg != null:
		_multi_summary_label.add_theme_font_override(&"font", sans_reg)

	_multi_hint_label.position = Vector2(bx + 22.0 * s, by + 168.0 * s)
	_multi_hint_label.size = Vector2(410.0 * s, 22.0 * s)
	_multi_hint_label.add_theme_font_size_override(&"font_size", maxi(9, int(round(10.5 * s))))
	if sans_reg != null:
		_multi_hint_label.add_theme_font_override(&"font", sans_reg)

	if _has_rendered and _mode == SelectionMode.SINGLE:
		var fill_pct: float = clampf(float(_last_render_key.get("fill_pct", 0.0)), 0.0, 100.0)
		_carry_fill.size = Vector2(_carry_track.size.x * (fill_pct / 100.0), _carry_track.size.y)


func get_selection_mode() -> SelectionMode:
	return _mode


func get_selected_count() -> int:
	return _selected_count


func get_tracked_unit() -> Unit:
	return _tracked_unit


func get_slab() -> D2PolygonalSlab:
	return _slab


func get_content_bounds() -> Rect2:
	return _content_rect


func get_title_text() -> String:
	return _title_label.text if _title_label != null else ""


func get_badge_text() -> String:
	return _badge_label.text if _badge_label != null else ""


func get_percentage_text() -> String:
	return _carry_pct_label.text if _carry_pct_label != null else ""


func get_weight_text() -> String:
	return _weight_label.text if _weight_label != null else ""


func get_carried_value_text(resource_id: StringName) -> String:
	var idx: int = RESOURCE_KEYS.find(resource_id)
	if idx < 0 or idx >= _mat_value_labels.size():
		return ""
	return _mat_value_labels[idx].text


func get_multi_summary_text() -> String:
	return _multi_summary_label.text if _multi_summary_label != null else ""


func is_overload_indicated() -> bool:
	return bool(_last_render_key.get("overloaded", false))


func is_single_details_visible() -> bool:
	return visible and _carry_header_label != null and _carry_header_label.visible


func is_multi_summary_visible() -> bool:
	return visible and _multi_summary_label != null and _multi_summary_label.visible


func get_apply_count() -> int:
	return _apply_count


func is_bound_to_selection_manager(manager: SelectionManager) -> bool:
	return (
		_selection_manager != null
		and _selection_manager == manager
		and _selection_manager.selection_changed.is_connected(_on_selection_changed)
	)


func is_bound_to_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit) or _tracked_unit != unit:
		return false
	return unit.state_changed.is_connected(_on_unit_state_changed)


func _build_nodes() -> void:
	_built = true
	_mat_icons.clear()
	_mat_name_labels.clear()
	_mat_value_labels.clear()

	var meta: Dictionary = _atlas.get_region_metadata("lineage_blade") if _atlas != null else {}
	var pad: float = float(meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))

	_slab = D2PolygonalSlab.new()
	_slab.name = "LineageBladeSlab"
	_slab.texture = _atlas.get_region_texture("lineage_blade") if _atlas != null else null
	_slab.configure_polygon(D2Tokens.POLYGON_LINEAGE_BLADE, D2Tokens.BLADE_CONTENT_SIZE, pad)
	add_child(_slab)

	_title_label = Label.new()
	_title_label.name = "BladeTitleLabel"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
	add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "BladeSubtitleLabel"
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
	add_child(_subtitle_label)

	_badge_box = Panel.new()
	_badge_box.name = "BladeStateBadgeBox"
	_badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_style = StyleBoxFlat.new()
	_badge_style.bg_color = Color(0.0, 0.0, 0.0, 0.24)
	_badge_style.border_color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
	_badge_style.set_border_width_all(1)
	_badge_box.add_theme_stylebox_override(&"panel", _badge_style)
	add_child(_badge_box)

	_badge_label = Label.new()
	_badge_label.name = "BladeStateBadgeLabel"
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
	add_child(_badge_label)

	_header_divider = _make_divider("BladeHeaderDivider", Color(0.875, 0.737, 0.447, 0.35))
	add_child(_header_divider)

	_carry_header_label = Label.new()
	_carry_header_label.name = "BladeCarryHeader"
	_carry_header_label.text = "Carga física"
	_carry_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_carry_header_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
	add_child(_carry_header_label)

	_carry_pct_label = Label.new()
	_carry_pct_label.name = "BladeCarryPct"
	_carry_pct_label.text = "0%"
	_carry_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_carry_pct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_carry_pct_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry_pct_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
	add_child(_carry_pct_label)

	_carry_track = Panel.new()
	_carry_track.name = "BladeCarryTrack"
	_carry_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_sb := StyleBoxFlat.new()
	track_sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	track_sb.border_color = Color(0.875, 0.737, 0.447, 0.25)
	track_sb.set_border_width_all(1)
	_carry_track.add_theme_stylebox_override(&"panel", track_sb)
	add_child(_carry_track)

	_carry_fill = Panel.new()
	_carry_fill.name = "BladeCarryFill"
	_carry_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry_fill_style = StyleBoxFlat.new()
	_carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
	_carry_fill.add_theme_stylebox_override(&"panel", _carry_fill_style)
	add_child(_carry_fill)

	_weight_label = Label.new()
	_weight_label.name = "BladeWeightLabel"
	_weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weight_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_weight_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
	add_child(_weight_label)

	_capacity_or_overload_label = Label.new()
	_capacity_or_overload_label.name = "BladeCapacityOrOverloadLabel"
	_capacity_or_overload_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capacity_or_overload_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_capacity_or_overload_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
	add_child(_capacity_or_overload_label)

	_col_divider = _make_divider("BladeColDivider", Color(0.875, 0.737, 0.447, 0.28))
	add_child(_col_divider)

	_materials_header_label = Label.new()
	_materials_header_label.name = "BladeMaterialsHeader"
	_materials_header_label.text = "CARGA TRANSPORTADA"
	_materials_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_materials_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_materials_header_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
	add_child(_materials_header_label)

	for i: int in range(3):
		var ico := TextureRect.new()
		ico.name = "BladeMatIcon_%s" % String(RESOURCE_KEYS[i])
		ico.texture = _atlas.get_region_texture(RESOURCE_ICONS[i]) if _atlas != null else null
		ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ico)
		_mat_icons.append(ico)

		var n_lbl := Label.new()
		n_lbl.name = "BladeMatName_%s" % String(RESOURCE_KEYS[i])
		n_lbl.text = RESOURCE_NAMES[i]
		n_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n_lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
		add_child(n_lbl)
		_mat_name_labels.append(n_lbl)

		var v_lbl := Label.new()
		v_lbl.name = "BladeMatVal_%s" % String(RESOURCE_KEYS[i])
		v_lbl.text = "0"
		v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v_lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
		add_child(v_lbl)
		_mat_value_labels.append(v_lbl)

	_multi_summary_label = Label.new()
	_multi_summary_label.name = "BladeMultiSummary"
	_multi_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multi_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_multi_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_multi_summary_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
	add_child(_multi_summary_label)

	_multi_hint_label = Label.new()
	_multi_hint_label.name = "BladeMultiHint"
	_multi_hint_label.text = "Selecione uma unidade individual para inspecionar carga e transporte."
	_multi_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multi_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_multi_hint_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
	add_child(_multi_hint_label)


func _bind_single_unit(unit: Unit) -> void:
	_unbind_all_units()
	if not _is_unit_valid(unit):
		return
	_tracked_unit = unit
	if not _tracked_unit.state_changed.is_connected(_on_unit_state_changed):
		_tracked_unit.state_changed.connect(_on_unit_state_changed)
	if not _tracked_unit.tree_exited.is_connected(_on_tracked_unit_tree_exited):
		_tracked_unit.tree_exited.connect(_on_tracked_unit_tree_exited)
	_tracked_carry_load = _tracked_unit.get_carry_load()
	if _tracked_carry_load != null:
		if not _tracked_carry_load.load_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.load_changed.connect(_on_carry_changed)
		if not _tracked_carry_load.capacity_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.capacity_changed.connect(_on_carry_changed)


func _bind_group_units(units: Array[Unit]) -> void:
	_unbind_all_units()
	for u: Unit in units:
		if not _is_unit_valid(u):
			continue
		_tracked_group_units.append(u)
		if not u.state_changed.is_connected(_on_group_unit_state_changed):
			u.state_changed.connect(_on_group_unit_state_changed)
		if not u.tree_exited.is_connected(_on_group_unit_tree_exited):
			u.tree_exited.connect(_on_group_unit_tree_exited)


func _unbind_all_units() -> void:
	if _tracked_unit != null and is_instance_valid(_tracked_unit):
		if _tracked_unit.state_changed.is_connected(_on_unit_state_changed):
			_tracked_unit.state_changed.disconnect(_on_unit_state_changed)
		if _tracked_unit.tree_exited.is_connected(_on_tracked_unit_tree_exited):
			_tracked_unit.tree_exited.disconnect(_on_tracked_unit_tree_exited)
	if _tracked_carry_load != null:
		if _tracked_carry_load.load_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.load_changed.disconnect(_on_carry_changed)
		if _tracked_carry_load.capacity_changed.is_connected(_on_carry_changed):
			_tracked_carry_load.capacity_changed.disconnect(_on_carry_changed)
	_tracked_unit = null
	_tracked_carry_load = null

	for u: Unit in _tracked_group_units:
		if u != null and is_instance_valid(u):
			if u.state_changed.is_connected(_on_group_unit_state_changed):
				u.state_changed.disconnect(_on_group_unit_state_changed)
			if u.tree_exited.is_connected(_on_group_unit_tree_exited):
				u.tree_exited.disconnect(_on_group_unit_tree_exited)
	_tracked_group_units.clear()


func _render_current() -> void:
	var next_key: Dictionary = _build_render_key()
	if _has_rendered and _render_keys_match(_last_render_key, next_key):
		return
	_apply_render_key(next_key)


func _build_render_key() -> Dictionary:
	if _mode == SelectionMode.SINGLE and not _is_unit_valid(_tracked_unit):
		_unbind_all_units()
		_mode = SelectionMode.EMPTY
		_selected_count = 0

	if _mode == SelectionMode.MULTI:
		var live: Array[Unit] = []
		for u: Unit in _tracked_group_units:
			if _is_unit_valid(u):
				live.append(u)
		if live.is_empty():
			_unbind_all_units()
			_mode = SelectionMode.EMPTY
			_selected_count = 0
		elif live.size() == 1:
			_bind_single_unit(live[0])
			_mode = SelectionMode.SINGLE
			_selected_count = 1
		else:
			_selected_count = live.size()

	if _mode == SelectionMode.EMPTY:
		return {
			"mode": SelectionMode.EMPTY,
			"count": 0,
			"title": "",
			"subtitle": "",
			"badge": "",
			"state_enum": -1,
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
			"multi_text": "",
		}

	if _mode == SelectionMode.MULTI:
		var lines: PackedStringArray = PackedStringArray()
		var listed: int = mini(_tracked_group_units.size(), MAX_MULTI_ROWS)
		for i: int in range(listed):
			var u: Unit = _tracked_group_units[i]
			if _is_unit_valid(u):
				lines.append("• %s — %s" % [HudFormatter.format_unit_name(u), HudFormatter.format_unit_state(u.get_state())])
		if _tracked_group_units.size() > MAX_MULTI_ROWS:
			lines.append("• +%d unidades" % (_tracked_group_units.size() - MAX_MULTI_ROWS))
		return {
			"mode": SelectionMode.MULTI,
			"count": _selected_count,
			"title": "%d unidades selecionadas" % _selected_count,
			"subtitle": "Seleção múltipla ativa · Ordens aplicadas ao grupo",
			"badge": "GRUPO",
			"state_enum": -1,
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
			"multi_text": "\n".join(lines),
		}

	var carry_load: UnitCarryLoad = _tracked_carry_load if _tracked_carry_load != null else _tracked_unit.get_carry_load()
	var carry: Dictionary = HudFormatter.build_carry_snapshot(carry_load)
	var u_state: Unit.State = _tracked_unit.get_state()
	var state_text: String = HudFormatter.format_unit_state(u_state)
	var overloaded: bool = bool(carry.get("is_overloaded", false))
	var cap: int = int(carry.get("effective_capacity", 0))
	var subtitle: String = (
		"SOBRECARGA · Peso acima da capacidade efetiva (%d)" % cap
		if overloaded
		else "Unidade ativa · Capacidade efetiva: %d peso" % cap
	)
	return {
		"mode": SelectionMode.SINGLE,
		"count": 1,
		"title": HudFormatter.format_unit_name(_tracked_unit),
		"subtitle": subtitle,
		"badge": state_text.to_upper(),
		"state_enum": int(u_state),
		"display_pct": int(carry.get("display_percentage", 0)),
		"fill_pct": float(carry.get("fill_percentage", 0.0)),
		"weight": int(carry.get("current_weight", 0)),
		"capacity": cap,
		"overloaded": overloaded,
		"wood": int(carry.get("wood", 0)),
		"stone": int(carry.get("stone", 0)),
		"food": int(carry.get("food", 0)),
		"pct_text": String(carry.get("percentage_text", "0%")),
		"weight_text": String(carry.get("weight_text", "Peso transportado: 0 / 0")),
		"multi_text": "",
	}


func _apply_render_key(key: Dictionary) -> void:
	_last_render_key = key.duplicate()
	if not _built:
		visible = false
		return

	var mode_val: int = int(key.get("mode", SelectionMode.EMPTY))
	if mode_val == SelectionMode.EMPTY:
		visible = false
		_title_label.text = ""
		_subtitle_label.text = ""
		_badge_label.text = ""
		_carry_pct_label.text = ""
		_weight_label.text = ""
		_capacity_or_overload_label.text = ""
		_multi_summary_label.text = ""
		for v_lbl: Label in _mat_value_labels:
			v_lbl.text = "0"
		_set_single_nodes_visible(false)
		_set_multi_nodes_visible(false)
		_has_rendered = true
		_apply_count += 1
		return

	visible = true
	_title_label.text = String(key.get("title", ""))
	_subtitle_label.text = String(key.get("subtitle", ""))
	_badge_label.text = String(key.get("badge", ""))

	if mode_val == SelectionMode.MULTI:
		_set_single_nodes_visible(false)
		_set_multi_nodes_visible(true)
		_subtitle_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
		_badge_style.border_color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
		_badge_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
		_multi_summary_label.text = String(key.get("multi_text", ""))
		_has_rendered = true
		_apply_count += 1
		return

	# Single unit mode
	_set_single_nodes_visible(true)
	_set_multi_nodes_visible(false)

	var overloaded: bool = bool(key.get("overloaded", false))
	var fill_pct: float = clampf(float(key.get("fill_pct", 0.0)), 0.0, 100.0)
	var state_enum: int = int(key.get("state_enum", int(Unit.State.IDLE)))
	var badge_color: Color = _color_for_badge(state_enum)
	_badge_style.border_color = badge_color
	_badge_label.add_theme_color_override(&"font_color", badge_color)
	_subtitle_label.add_theme_color_override(
		&"font_color",
		D2Tokens.COLOR_FEEDBACK_ERROR_ROSE if overloaded else D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
	)

	_carry_pct_label.text = String(key.get("pct_text", "0%"))
	_weight_label.text = String(key.get("weight_text", "Peso transportado: 0 / 0"))
	_weight_label.add_theme_color_override(
		&"font_color",
		D2Tokens.COLOR_FEEDBACK_ERROR_ROSE if overloaded else D2Tokens.COLOR_TEXT_SECONDARY_MUTED
	)

	if overloaded:
		_carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_ERROR_DARK
		_carry_pct_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_ERROR_ROSE)
		_capacity_or_overload_label.text = "● SOBRECARGA ATIVA"
		_capacity_or_overload_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_ERROR_ROSE)
	elif fill_pct >= 80.0:
		_carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_AMBER
		_carry_pct_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_AMBER)
		_capacity_or_overload_label.text = "Capacidade: %d peso" % int(key.get("capacity", 0))
		_capacity_or_overload_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
	else:
		_carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
		_carry_pct_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
		_capacity_or_overload_label.text = "Capacidade: %d peso" % int(key.get("capacity", 0))
		_capacity_or_overload_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)

	var fill_w: float = _carry_track.size.x * (fill_pct / 100.0)
	_carry_fill.size = Vector2(fill_w, _carry_track.size.y)
	_carry_fill.visible = fill_w > 0.5

	_mat_value_labels[0].text = "%d" % int(key.get("wood", 0))
	_mat_value_labels[1].text = "%d" % int(key.get("stone", 0))
	_mat_value_labels[2].text = "%d" % int(key.get("food", 0))

	_has_rendered = true
	_apply_count += 1


func _set_single_nodes_visible(vis: bool) -> void:
	_carry_header_label.visible = vis
	_carry_pct_label.visible = vis
	_carry_track.visible = vis
	_carry_fill.visible = vis and _carry_fill.size.x > 0.5
	_weight_label.visible = vis
	_capacity_or_overload_label.visible = vis
	_col_divider.visible = vis
	_materials_header_label.visible = vis
	for ico: TextureRect in _mat_icons:
		ico.visible = vis
	for n_lbl: Label in _mat_name_labels:
		n_lbl.visible = vis
	for v_lbl: Label in _mat_value_labels:
		v_lbl.visible = vis


func _set_multi_nodes_visible(vis: bool) -> void:
	_multi_summary_label.visible = vis
	_multi_hint_label.visible = vis


func _on_selection_changed(selected_units: Array[Unit]) -> void:
	set_selected_units(selected_units)


func _on_unit_state_changed(_new_state: Unit.State, _prev_state: Unit.State) -> void:
	_render_current()


func _on_carry_changed() -> void:
	_render_current()


func _on_tracked_unit_tree_exited() -> void:
	_unbind_all_units()
	_mode = SelectionMode.EMPTY
	_selected_count = 0
	_render_current()


func _on_group_unit_state_changed(_new_state: Unit.State, _prev_state: Unit.State) -> void:
	_render_current()


func _on_group_unit_tree_exited() -> void:
	_render_current()


func _disconnect_selection_manager() -> void:
	if _selection_manager != null and is_instance_valid(_selection_manager):
		if _selection_manager.selection_changed.is_connected(_on_selection_changed):
			_selection_manager.selection_changed.disconnect(_on_selection_changed)


static func _make_divider(node_name: String, color: Color) -> Panel:
	var p := Panel.new()
	p.name = node_name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	p.add_theme_stylebox_override(&"panel", sb)
	return p


static func _color_for_badge(state_enum: int) -> Color:
	match state_enum:
		int(Unit.State.WORKING):
			return D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
		int(Unit.State.TRANSPORTING):
			return D2Tokens.COLOR_FEEDBACK_AMBER
		int(Unit.State.MOVING):
			return D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT
		_:
			return D2Tokens.COLOR_ACCENT_GOLD_PRIMARY


static func _render_keys_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in a.keys():
		if not b.has(k):
			return false
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if va is float and vb is float:
			if absf(float(va) - float(vb)) > 0.001:
				return false
		elif va != vb:
			return false
	return true


static func _is_unit_valid(unit: Unit) -> bool:
	return unit != null and is_instance_valid(unit) and unit.is_inside_tree()
