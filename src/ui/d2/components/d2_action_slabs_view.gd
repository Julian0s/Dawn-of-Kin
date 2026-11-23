class_name D2ActionSlabsView
extends Control
## D2.2 Bottom-Right action slabs: Alabaster Maquetes ("Construir [B]") +
## Basalt Commands ("Tarefas [T]" / "Linhagem [H]").
##
## Design & Architecture Rules (UI-1.3):
## - Preserves exact D2.2 atlas regions ("slab_maquetes_alab" 196x92 / 176x72 content,
##   "slab_cmd_basalt" 166x92 / 146x72 content, 10 px shadow_pad) and polygonal silhouettes.
## - Maquetes [B] is interactive and toggles D2ConstructionDockView.
## - Tarefas [T] and Linhagem [H] preserve canonical D2.2 visual composition while staying
##   honestly disabled/inert until their authorized target features exist (zero fake panels).
## - Solid stone surfaces block clicks, RMB, MMB, scroll, and Edge Pan; transparent shadow
##   margins and chamfered corners pass events cleanly through to the 3D RTS world.
## - process_mode = PROCESS_MODE_PAUSABLE; zero per-frame polling.

signal maquettes_toggle_requested()


class _MaquettesHitButton:
	extends D2SlabButton

	func _init() -> void:
		super._init()

	func _draw() -> void:
		if _scaled_polygon.size() < 3:
			return
		var outline := PackedVector2Array(_scaled_polygon)
		outline.append(_scaled_polygon[0])
		if disabled:
			draw_colored_polygon(_scaled_polygon, Color(0.08, 0.09, 0.10, 0.34))
			return
		if is_pressed():
			draw_colored_polygon(_scaled_polygon, Color(0.875, 0.737, 0.447, 0.22))
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY, 1.5, true)
		elif _is_active_state:
			draw_colored_polygon(_scaled_polygon, Color(0.961, 0.851, 0.588, 0.10))
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 2.0, true)
		elif _is_hovered_visual:
			draw_colored_polygon(_scaled_polygon, Color(0.961, 0.851, 0.588, 0.12))
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1.5, true)


var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _shelter_mini_tex: Texture2D = null

var _maquettes_slab: D2PolygonalSlab = null
var _maquettes_button: _MaquettesHitButton = null
var _maquettes_icon: TextureRect = null
var _maquettes_title_label: Label = null
var _maquettes_sub_label: Label = null

var _cmd_slab: D2PolygonalSlab = null
var _tasks_icon: TextureRect = null
var _tasks_label: Label = null
var _cmd_divider: Panel = null
var _lineage_icon: TextureRect = null
var _lineage_label: Label = null

var _maquettes_open: bool = false
var _maquettes_enabled: bool = true
var _built: bool = false
var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var _scale_factor: float = D2Tokens.SCALE_1080P
var _maquettes_rect: Rect2 = Rect2()
var _cmd_rect: Rect2 = Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	_sync_visual_states()


func set_maquettes_open(open: bool) -> void:
	if _maquettes_open == open:
		return
	_maquettes_open = open
	apply_layout(_viewport_size, _scale_factor)
	_sync_visual_states()


func is_maquettes_open() -> bool:
	return _maquettes_open


func set_maquettes_enabled(enabled: bool) -> void:
	_maquettes_enabled = enabled
	_sync_visual_states()


func is_maquettes_enabled() -> bool:
	return _maquettes_enabled


func has_inert_unimplemented_controls() -> bool:
	return (
		_cmd_slab != null
		and _tasks_label != null
		and _lineage_label != null
		and _tasks_label.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and _lineage_label.mouse_filter == Control.MOUSE_FILTER_IGNORE
	)


func apply_layout(viewport_size: Vector2, scale_factor: float) -> void:
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built or _atlas == null:
		return

	var s: float = _scale_factor
	var w: float = _viewport_size.x
	var h: float = _viewport_size.y

	var mw: float = D2Tokens.ACTION_SLAB_MAQUETES_SIZE.x * s
	var cw: float = D2Tokens.ACTION_SLAB_CMD_SIZE.x * s
	var sh: float = D2Tokens.ACTION_SLAB_MAQUETES_SIZE.y * s
	var base_y: float = h - D2Tokens.ACTION_SLAB_MARGIN_BOTTOM * s - sh
	var cx: float = w - D2Tokens.ACTION_SLAB_MARGIN_RIGHT * s - cw
	var mx: float = cx - D2Tokens.ACTION_SLAB_GAP_X * s - mw
	var my: float = base_y - (D2Tokens.ACTION_SLAB_ACTIVE_LIFT_Y * s if _maquettes_open else 0.0)

	_maquettes_rect = Rect2(Vector2(mx, my), Vector2(mw, sh))
	_cmd_rect = Rect2(Vector2(cx, base_y), Vector2(cw, sh))

	var m_meta: Dictionary = _atlas.get_region_metadata("slab_maquetes_alab")
	var m_pad: float = float(m_meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
	var m_pos: Vector2 = Vector2(mx - m_pad * s, my - m_pad * s)
	var m_sz: Vector2 = Vector2(float(m_meta.get("w", 196.0)) * s, float(m_meta.get("h", 92.0)) * s)
	_maquettes_slab.position = m_pos
	_maquettes_slab.set_scaled_size(m_sz)
	_maquettes_button.position = m_pos
	_maquettes_button.set_scaled_size(m_sz)

	_maquettes_icon.position = Vector2(mx + 16.0 * s, my + 13.0 * s)
	_maquettes_icon.size = Vector2(46.0 * s, 46.0 * s)

	_maquettes_title_label.position = Vector2(mx + 70.0 * s, my + 14.0 * s)
	_maquettes_title_label.size = Vector2(98.0 * s, 23.0 * s)
	_apply_font(_maquettes_title_label, true, true, maxi(11, int(round(15.5 * s))))

	_maquettes_sub_label.position = Vector2(mx + 70.0 * s, my + 38.0 * s)
	_maquettes_sub_label.size = Vector2(98.0 * s, 17.0 * s)
	_apply_font(_maquettes_sub_label, false, false, maxi(9, int(round(10.8 * s))))

	var c_meta: Dictionary = _atlas.get_region_metadata("slab_cmd_basalt")
	var c_pad: float = float(c_meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
	var c_pos: Vector2 = Vector2(cx - c_pad * s, base_y - c_pad * s)
	var c_sz: Vector2 = Vector2(float(c_meta.get("w", 166.0)) * s, float(c_meta.get("h", 92.0)) * s)
	_cmd_slab.position = c_pos
	_cmd_slab.set_scaled_size(c_sz)

	_tasks_icon.position = Vector2(cx + 18.0 * s, base_y + 16.0 * s)
	_tasks_icon.size = Vector2(15.0 * s, 15.0 * s)

	_tasks_label.position = Vector2(cx + 39.0 * s, base_y + 14.0 * s)
	_tasks_label.size = Vector2(96.0 * s, 19.0 * s)
	_apply_font(_tasks_label, false, false, maxi(9, int(round(11.6 * s))))

	_cmd_divider.position = Vector2(cx + 18.0 * s, base_y + 36.0 * s)
	_cmd_divider.size = Vector2(cw - 34.0 * s, maxf(1.0, 1.0 * s))

	_lineage_icon.position = Vector2(cx + 18.0 * s, base_y + 42.0 * s)
	_lineage_icon.size = Vector2(15.0 * s, 15.0 * s)

	_lineage_label.position = Vector2(cx + 39.0 * s, base_y + 40.0 * s)
	_lineage_label.size = Vector2(96.0 * s, 19.0 * s)
	_apply_font(_lineage_label, false, false, maxi(9, int(round(11.6 * s))))


func get_maquettes_slab() -> D2PolygonalSlab:
	return _maquettes_slab


func get_maquettes_button() -> D2SlabButton:
	return _maquettes_button


func get_commands_slab() -> D2PolygonalSlab:
	return _cmd_slab


func get_maquettes_content_rect() -> Rect2:
	return _maquettes_rect


func get_commands_content_rect() -> Rect2:
	return _cmd_rect


func get_content_bounds() -> Rect2:
	if _maquettes_rect.size == Vector2.ZERO:
		return _cmd_rect
	if _cmd_rect.size == Vector2.ZERO:
		return _maquettes_rect
	return _maquettes_rect.merge(_cmd_rect)


func _build_nodes() -> void:
	_built = true
	_shelter_mini_tex = D2AtlasLibrary._load_texture(D2AtlasLibrary.SHELTER_MINI_PATH)

	_maquettes_slab = D2PolygonalSlab.new()
	_maquettes_slab.name = "MaquettesAlabasterSlab"
	_maquettes_slab.texture = _atlas.get_region_texture("slab_maquetes_alab")
	_maquettes_slab.configure_polygon(
		D2Tokens.POLYGON_SLAB_MAQUETES,
		D2Tokens.ACTION_SLAB_MAQUETES_SIZE,
		D2Tokens.ATLAS_SHADOW_PAD
	)
	add_child(_maquettes_slab)

	_maquettes_button = _MaquettesHitButton.new()
	_maquettes_button.name = "MaquettesButton"
	_maquettes_button.configure_polygon(
		D2Tokens.POLYGON_SLAB_MAQUETES,
		D2Tokens.ACTION_SLAB_MAQUETES_SIZE,
		D2Tokens.ATLAS_SHADOW_PAD
	)
	_maquettes_button.pressed.connect(_on_maquettes_pressed)
	add_child(_maquettes_button)

	_maquettes_icon = TextureRect.new()
	_maquettes_icon.name = "MaquettesIcon"
	_maquettes_icon.texture = _shelter_mini_tex
	_maquettes_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_maquettes_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_maquettes_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_maquettes_icon)

	_maquettes_title_label = Label.new()
	_maquettes_title_label.name = "MaquettesTitleLabel"
	_maquettes_title_label.text = "Maquetes"
	_maquettes_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_maquettes_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_maquettes_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maquettes_title_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_ON_ALABASTER_INK)
	add_child(_maquettes_title_label)

	_maquettes_sub_label = Label.new()
	_maquettes_sub_label.name = "MaquettesSubLabel"
	_maquettes_sub_label.text = "Construir [B]"
	_maquettes_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_maquettes_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_maquettes_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maquettes_sub_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_ON_ALABASTER_SUB)
	add_child(_maquettes_sub_label)

	_cmd_slab = D2PolygonalSlab.new()
	_cmd_slab.name = "CommandsBasaltSlab"
	_cmd_slab.texture = _atlas.get_region_texture("slab_cmd_basalt")
	_cmd_slab.configure_polygon(
		D2Tokens.POLYGON_SLAB_CMD_BASALT,
		D2Tokens.ACTION_SLAB_CMD_SIZE,
		D2Tokens.ATLAS_SHADOW_PAD
	)
	add_child(_cmd_slab)

	_tasks_icon = TextureRect.new()
	_tasks_icon.name = "TasksInertIcon"
	_tasks_icon.texture = _atlas.get_region_texture("ico_tasks")
	_tasks_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tasks_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tasks_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tasks_icon.modulate = Color(1.0, 1.0, 1.0, 0.48)
	add_child(_tasks_icon)

	_tasks_label = Label.new()
	_tasks_label.name = "TasksInertLabel"
	_tasks_label.text = "Tarefas [T]"
	_tasks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tasks_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tasks_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tasks_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_DISABLED_TEXT)
	add_child(_tasks_label)

	_cmd_divider = Panel.new()
	_cmd_divider.name = "CommandsDivider"
	_cmd_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var div_style := StyleBoxFlat.new()
	div_style.bg_color = D2Tokens.COLOR_ACCENT_GOLD_DIM
	_cmd_divider.add_theme_stylebox_override(&"panel", div_style)
	add_child(_cmd_divider)

	_lineage_icon = TextureRect.new()
	_lineage_icon.name = "LineageInertIcon"
	_lineage_icon.texture = _atlas.get_region_texture("ico_lineage")
	_lineage_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lineage_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lineage_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lineage_icon.modulate = Color(1.0, 1.0, 1.0, 0.48)
	add_child(_lineage_icon)

	_lineage_label = Label.new()
	_lineage_label.name = "LineageInertLabel"
	_lineage_label.text = "Linhagem [H]"
	_lineage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lineage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lineage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lineage_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_DISABLED_TEXT)
	add_child(_lineage_label)


func _sync_visual_states() -> void:
	if not _built:
		return
	_maquettes_button.set_interactive_enabled(_maquettes_enabled)
	_maquettes_button.set_active_state(_maquettes_open and _maquettes_enabled)
	_maquettes_icon.modulate = Color.WHITE if _maquettes_enabled else Color(0.75, 0.75, 0.75, 0.55)
	_maquettes_title_label.add_theme_color_override(
		&"font_color",
		D2Tokens.COLOR_TEXT_ON_ALABASTER_INK if _maquettes_enabled else D2Tokens.COLOR_TEXT_ON_ALABASTER_SUB
	)


func _on_maquettes_pressed() -> void:
	if not _maquettes_enabled:
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return
	maquettes_toggle_requested.emit()


func _apply_font(lbl: Label, serif: bool, bold: bool, font_px: int) -> void:
	lbl.add_theme_font_size_override(&"font_size", font_px)
	if _theme_factory == null:
		return
	var f: Font = _theme_factory.get_serif_font(bold) if serif else _theme_factory.get_sans_font(bold)
	if f != null:
		lbl.add_theme_font_override(&"font", f)
