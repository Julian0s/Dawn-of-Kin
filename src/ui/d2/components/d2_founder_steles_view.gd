class_name D2FounderStelesView
extends Control
## D2.2 Bottom-Left twin independent staggered basalt founder steles.
##
## Design & Architecture Rules (UI-1.2):
## - Strict D2.2 geometry (1080p baseline):
##   - Normal stele: 128x156 (108x136 content + 10 px shadow_pad), x0=20, x1=142, stele 1 +6 px lower.
##   - Selected stele: 128x174 (108x154 content + 10 px shadow_pad), raised 22 px upward.
## - DT-04 respected: names come exclusively from HudFormatter.format_unit_name(unit)
##   without mutating .tres definitions; portraits map by CharacterDefinition.character_id
##   (&"leader_a" -> portrait_alden.jpg, &"leader_b" -> portrait_brena.jpg) with safe monogram
##   fallback for future inhabitants.
## - Single source of truth: SelectionManager (bidirectional via selection_changed and
##   select_single / toggle_unit on click / Shift+click).
## - Strictly signal-driven (SelectionManager.selection_changed, Unit.state_changed,
##   Unit.tree_exited, UnitCarryLoad.load_changed, UnitCarryLoad.capacity_changed); zero polling.
## - process_mode = PROCESS_MODE_PAUSABLE (matches RTS selection restrictions during pause).
## - Reuses D2PolygonalSlab and D2SlabButton with exact polygonal hitboxes.

const MAX_FOUNDER_SLOTS: int = 2
const PORTRAIT_BY_CHARACTER_ID: Dictionary = {
	&"leader_a": D2AtlasLibrary.PORTRAIT_ALDEN_PATH,
	&"leader_b": D2AtlasLibrary.PORTRAIT_BRENA_PATH,
}


class _SteleHitButton:
	extends D2SlabButton
	signal stele_clicked(shift_held: bool)
	var _pending_shift: bool = false

	func _init() -> void:
		super._init()
		pressed.connect(_on_self_pressed)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_pending_shift = mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
		super._gui_input(event)

	func _draw() -> void:
		# Transparent over D2PolygonalSlab basalt artwork; only renders subtle D2.2 gold hover/press tint.
		if _scaled_polygon.size() < 3:
			return
		if is_pressed():
			draw_colored_polygon(_scaled_polygon, Color(0.875, 0.737, 0.447, 0.14))
		elif _is_hovered_visual:
			draw_colored_polygon(_scaled_polygon, Color(0.875, 0.737, 0.447, 0.08))
			var outline := PackedVector2Array(_scaled_polygon)
			outline.append(_scaled_polygon[0])
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1.5, true)

	func _on_self_pressed() -> void:
		var shift_flag: bool = _pending_shift or Input.is_key_pressed(KEY_SHIFT)
		_pending_shift = false
		stele_clicked.emit(shift_flag)


class _SteleSlot:
	extends RefCounted
	var index: int = 0
	var unit: Unit = null
	var carry_load: UnitCarryLoad = null
	var selected: bool = false
	var slab: D2PolygonalSlab = null
	var hit_button: _SteleHitButton = null
	var selected_tag: Label = null
	var portrait_frame: Panel = null
	var portrait_rect: TextureRect = null
	var fallback_monogram: Label = null
	var name_label: Label = null
	var state_label: Label = null
	var carry_track: Panel = null
	var carry_fill: Panel = null
	var portrait_border_style: StyleBoxFlat = null
	var carry_track_style: StyleBoxFlat = null
	var carry_fill_style: StyleBoxFlat = null
	var content_rect: Rect2 = Rect2()
	var state_cb: Callable = Callable()
	var exit_cb: Callable = Callable()
	var carry_cb: Callable = Callable()


var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _selection_manager: SelectionManager = null
var _slots: Array[_SteleSlot] = []
var _portrait_cache: Dictionary = {}

var _built: bool = false
var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var _scale_factor: float = D2Tokens.SCALE_1080P
var _apply_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
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


func configure(selection_manager: SelectionManager, units: Array[Unit]) -> void:
	if _selection_manager != selection_manager:
		_disconnect_selection_manager()
		_selection_manager = selection_manager
		if _selection_manager != null and not _selection_manager.selection_changed.is_connected(_on_selection_changed):
			_selection_manager.selection_changed.connect(_on_selection_changed)

	var ordered: Array[Unit] = _order_founder_units(units)
	for i: int in range(_slots.size()):
		var target_unit: Unit = ordered[i] if i < ordered.size() else null
		_bind_slot_unit(_slots[i], target_unit)

	_sync_selection_from_manager()
	apply_layout(_viewport_size, _scale_factor)
	refresh()


func unbind() -> void:
	_disconnect_selection_manager()
	_selection_manager = null
	for slot: _SteleSlot in _slots:
		_unbind_slot_unit(slot)
		slot.selected = false
		_set_slot_visible(slot, false)


func apply_layout(viewport_size: Vector2, scale_factor: float) -> void:
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built:
		return
	for slot: _SteleSlot in _slots:
		_layout_slot(slot)


func refresh() -> void:
	if not _built:
		return
	for slot: _SteleSlot in _slots:
		_render_slot(slot)
	_apply_count += 1


func get_slot_count() -> int:
	return _slots.size()


func get_slot_unit(index: int) -> Unit:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index].unit


func is_slot_selected(index: int) -> bool:
	if index < 0 or index >= _slots.size():
		return false
	return _slots[index].selected


func is_slot_visible(index: int) -> bool:
	if index < 0 or index >= _slots.size():
		return false
	return _slots[index].slab != null and _slots[index].slab.visible


func get_slot_name_text(index: int) -> String:
	if index < 0 or index >= _slots.size() or _slots[index].name_label == null:
		return ""
	return _slots[index].name_label.text


func get_slot_state_text(index: int) -> String:
	if index < 0 or index >= _slots.size() or _slots[index].state_label == null:
		return ""
	return _slots[index].state_label.text


func get_slot_portrait_texture(index: int) -> Texture2D:
	if index < 0 or index >= _slots.size() or _slots[index].portrait_rect == null:
		return null
	return _slots[index].portrait_rect.texture


func get_slot_slab(index: int) -> D2PolygonalSlab:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index].slab


func get_slot_button(index: int) -> D2SlabButton:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index].hit_button


func get_slot_content_rect(index: int) -> Rect2:
	if index < 0 or index >= _slots.size():
		return Rect2()
	return _slots[index].content_rect


func get_content_bounds() -> Rect2:
	var combined := Rect2()
	var has_any: bool = false
	for slot: _SteleSlot in _slots:
		if slot.slab != null and slot.slab.visible and slot.content_rect.size.x > 0.0:
			if not has_any:
				combined = slot.content_rect
				has_any = true
			else:
				combined = combined.merge(slot.content_rect)
	return combined


func get_apply_count() -> int:
	return _apply_count


func is_bound_to_selection_manager(manager: SelectionManager) -> bool:
	return (
		_selection_manager != null
		and _selection_manager == manager
		and _selection_manager.selection_changed.is_connected(_on_selection_changed)
	)


func is_bound_to_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	for slot: _SteleSlot in _slots:
		if slot.unit == unit and slot.state_cb.is_valid():
			return unit.state_changed.is_connected(slot.state_cb)
	return false


func _build_nodes() -> void:
	_built = true
	_slots.clear()
	for i: int in range(MAX_FOUNDER_SLOTS):
		var slot := _SteleSlot.new()
		slot.index = i
		slot.state_cb = Callable(self, "_on_slot_unit_state_changed").bind(i)
		slot.exit_cb = Callable(self, "_on_slot_unit_tree_exited").bind(i)
		slot.carry_cb = Callable(self, "_on_slot_carry_changed").bind(i)

		var slab := D2PolygonalSlab.new()
		slab.name = "FounderSteleSlab_%d" % i
		slab.texture = _atlas.get_region_texture("founder_stele") if _atlas != null else null
		slab.configure_polygon(D2Tokens.POLYGON_FOUNDER_STELE, D2Tokens.STELE_CONTENT_SIZE, D2Tokens.ATLAS_SHADOW_PAD)
		add_child(slab)
		slot.slab = slab

		var sel_tag := Label.new()
		sel_tag.name = "FounderSelectedTag_%d" % i
		sel_tag.text = "SELECIONADO"
		sel_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sel_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sel_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sel_tag.add_theme_color_override(&"font_color", D2Tokens.COLOR_ACCENT_GOLD_PRIMARY)
		sel_tag.visible = false
		add_child(sel_tag)
		slot.selected_tag = sel_tag

		var p_frame := Panel.new()
		p_frame.name = "FounderPortraitFrame_%d" % i
		p_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		p_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p_style := StyleBoxFlat.new()
		p_style.bg_color = D2Tokens.COLOR_SURFACE_BASALT_DEEP
		p_style.border_color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
		p_style.set_border_width_all(2)
		p_style.set_corner_radius_all(31)
		p_frame.add_theme_stylebox_override(&"panel", p_style)
		add_child(p_frame)
		slot.portrait_frame = p_frame
		slot.portrait_border_style = p_style

		var p_rect := TextureRect.new()
		p_rect.name = "FounderPortraitTex_%d" % i
		p_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		p_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p_frame.add_child(p_rect)
		slot.portrait_rect = p_rect

		var mono := Label.new()
		mono.name = "FounderPortraitFallback_%d" % i
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mono.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mono.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
		mono.visible = false
		p_frame.add_child(mono)
		slot.fallback_monogram = mono

		var n_lbl := Label.new()
		n_lbl.name = "FounderName_%d" % i
		n_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n_lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_PRIMARY_IVORY)
		add_child(n_lbl)
		slot.name_label = n_lbl

		var st_lbl := Label.new()
		st_lbl.name = "FounderState_%d" % i
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		st_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st_lbl.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_SECONDARY_MUTED)
		add_child(st_lbl)
		slot.state_label = st_lbl

		var track := Panel.new()
		track.name = "FounderCarryTrack_%d" % i
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track_sb := StyleBoxFlat.new()
		track_sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
		track.add_theme_stylebox_override(&"panel", track_sb)
		add_child(track)
		slot.carry_track = track
		slot.carry_track_style = track_sb

		var fill := Panel.new()
		fill.name = "FounderCarryFill_%d" % i
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
		fill.add_theme_stylebox_override(&"panel", fill_sb)
		add_child(fill)
		slot.carry_fill = fill
		slot.carry_fill_style = fill_sb

		# Interactive polygonal hit button placed on top of slab visuals
		var btn := _SteleHitButton.new()
		btn.name = "FounderSteleButton_%d" % i
		btn.configure_polygon(D2Tokens.POLYGON_FOUNDER_STELE, D2Tokens.STELE_CONTENT_SIZE, D2Tokens.ATLAS_SHADOW_PAD)
		btn.stele_clicked.connect(_on_stele_clicked.bind(i))
		add_child(btn)
		slot.hit_button = btn

		_set_slot_visible(slot, false)
		_slots.append(slot)


func _layout_slot(slot: _SteleSlot) -> void:
	if not _built or _atlas == null:
		return
	var s: float = _scale_factor
	var is_sel: bool = slot.selected
	var region_key: String = "founder_stele_raised" if is_sel else "founder_stele"
	var meta: Dictionary = _atlas.get_region_metadata(region_key)
	var pad: float = float(meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
	var base_content: Vector2 = D2Tokens.STELE_RAISED_CONTENT_SIZE if is_sel else D2Tokens.STELE_CONTENT_SIZE
	var base_poly: Array[Vector2] = D2Tokens.POLYGON_FOUNDER_STELE_RAISED if is_sel else D2Tokens.POLYGON_FOUNDER_STELE
	var rw: float = float(meta.get("w", base_content.x + 2.0 * pad))
	var rh: float = float(meta.get("h", base_content.y + 2.0 * pad))

	var sw: float = base_content.x * s
	var sh: float = base_content.y * s
	var x: float = (D2Tokens.STELE_ORIGIN_X + float(slot.index) * (D2Tokens.STELE_CONTENT_SIZE.x + D2Tokens.STELE_GAP_X)) * s
	var normal_y: float = _viewport_size.y - D2Tokens.STELE_MARGIN_BOTTOM * s - D2Tokens.STELE_CONTENT_SIZE.y * s
	if slot.index == 1:
		normal_y += D2Tokens.STELE_SECOND_OFFSET_Y * s
	var y: float = normal_y - (D2Tokens.STELE_RAISED_LIFT_Y * s if is_sel else 0.0)
	slot.content_rect = Rect2(x, y, sw, sh)

	var slab_sz := Vector2(rw * s, rh * s)
	var slab_pos := Vector2(x - pad * s, y - pad * s)
	slot.slab.texture = _atlas.get_region_texture(region_key)
	slot.slab.position = slab_pos
	slot.slab.configure_polygon(base_poly, base_content, pad)
	slot.slab.set_scaled_size(slab_sz)

	slot.hit_button.position = slab_pos
	slot.hit_button.configure_polygon(base_poly, base_content, pad)
	slot.hit_button.set_scaled_size(slab_sz)

	var serif_bold: Font = _theme_factory.get_serif_font(true) if _theme_factory != null else null
	var sans_reg: Font = _theme_factory.get_sans_font(false) if _theme_factory != null else null
	var sans_bold: Font = _theme_factory.get_sans_font(true) if _theme_factory != null else null

	slot.selected_tag.position = Vector2(x + 6.0 * s, y + 11.0 * s)
	slot.selected_tag.size = Vector2(sw - 12.0 * s, 14.0 * s)
	slot.selected_tag.add_theme_font_size_override(&"font_size", maxi(8, int(round(9.0 * s))))
	if sans_bold != null:
		slot.selected_tag.add_theme_font_override(&"font", sans_bold)

	var diam: float = D2Tokens.STELE_PORTRAIT_DIAMETER * s
	var p_y: float = y + (30.0 if is_sel else 14.0) * s
	slot.portrait_frame.position = Vector2(x + (sw - diam) * 0.5, p_y)
	slot.portrait_frame.size = Vector2(diam, diam)
	slot.portrait_border_style.set_corner_radius_all(int(round(diam * 0.5)))
	slot.portrait_border_style.set_border_width_all(maxi(1, int(round(2.0 * s))))
	slot.portrait_border_style.border_color = D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT if is_sel else D2Tokens.COLOR_ACCENT_GOLD_PRIMARY

	slot.fallback_monogram.add_theme_font_size_override(&"font_size", maxi(14, int(round(22.0 * s))))
	if serif_bold != null:
		slot.fallback_monogram.add_theme_font_override(&"font", serif_bold)

	var name_y: float = y + (98.0 if is_sel else 82.0) * s
	slot.name_label.position = Vector2(x + 6.0 * s, name_y)
	slot.name_label.size = Vector2(sw - 12.0 * s, 21.0 * s)
	slot.name_label.add_theme_font_size_override(&"font_size", maxi(11, int(round((15.0 if is_sel else 14.5) * s))))
	if serif_bold != null:
		slot.name_label.add_theme_font_override(&"font", serif_bold)

	var state_y: float = y + (119.0 if is_sel else 102.0) * s
	slot.state_label.position = Vector2(x + 6.0 * s, state_y)
	slot.state_label.size = Vector2(sw - 12.0 * s, 16.0 * s)
	slot.state_label.add_theme_font_size_override(&"font_size", maxi(9, int(round(10.5 * s))))
	if sans_reg != null:
		slot.state_label.add_theme_font_override(&"font", sans_reg)

	var bar_x: float = x + 14.0 * s
	var bar_w: float = sw - 28.0 * s
	var bar_h: float = maxf(2.0, 3.0 * s)
	var bar_y: float = y + (139.0 if is_sel else 122.0) * s
	slot.carry_track.position = Vector2(bar_x, bar_y)
	slot.carry_track.size = Vector2(bar_w, bar_h)
	slot.carry_fill.position = Vector2(bar_x, bar_y)
	slot.carry_fill.size = Vector2(slot.carry_fill.size.x, bar_h)


func _render_slot(slot: _SteleSlot) -> void:
	var has_unit: bool = _is_unit_valid(slot.unit)
	_set_slot_visible(slot, has_unit)
	if not has_unit:
		return

	var unit: Unit = slot.unit
	var def: CharacterDefinition = unit.get_definition()
	var unit_name: String = HudFormatter.format_unit_name(unit)
	var unit_state: Unit.State = unit.get_state()
	var state_text: String = HudFormatter.format_unit_state(unit_state)

	slot.selected_tag.visible = slot.selected
	slot.name_label.text = unit_name
	slot.state_label.text = state_text
	slot.state_label.add_theme_color_override(&"font_color", _color_for_unit_state(unit_state, slot.selected))

	# Portrait mapping by character_id with safe monogram fallback
	var char_id: StringName = def.character_id if def != null else &""
	var portrait_tex: Texture2D = _resolve_portrait_texture(char_id)
	if portrait_tex != null:
		slot.portrait_rect.texture = portrait_tex
		slot.portrait_rect.visible = true
		slot.fallback_monogram.visible = false
		slot.portrait_border_style.bg_color = D2Tokens.COLOR_SURFACE_BASALT_DEEP
	else:
		slot.portrait_rect.texture = null
		slot.portrait_rect.visible = false
		slot.fallback_monogram.text = unit_name.left(1).to_upper() if not unit_name.is_empty() else "?"
		slot.fallback_monogram.visible = true
		var tint: Color = def.primary_color if def != null else D2Tokens.COLOR_ACCENT_GOLD_DIM
		slot.portrait_border_style.bg_color = tint.darkened(0.65)

	# Real carry fill indicator from UnitCarryLoad (zero invented health/vigor)
	var carry_load: UnitCarryLoad = slot.carry_load if slot.carry_load != null else unit.get_carry_load()
	var snap: Dictionary = HudFormatter.build_carry_snapshot(carry_load)
	var fill_pct: float = clampf(float(snap.get("fill_percentage", 0.0)), 0.0, 100.0)
	var overloaded: bool = bool(snap.get("is_overloaded", false))
	var track_w: float = slot.carry_track.size.x
	var fill_w: float = track_w * (fill_pct / 100.0)
	slot.carry_fill.size = Vector2(fill_w, slot.carry_track.size.y)
	slot.carry_fill.visible = fill_w > 0.5
	if overloaded:
		slot.carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_ERROR_ROSE
	elif fill_pct >= 80.0:
		slot.carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_AMBER
	else:
		slot.carry_fill_style.bg_color = D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT


func _set_slot_visible(slot: _SteleSlot, vis: bool) -> void:
	if slot.slab != null:
		slot.slab.visible = vis
	if slot.hit_button != null:
		slot.hit_button.visible = vis
	if slot.selected_tag != null:
		slot.selected_tag.visible = vis and slot.selected
	if slot.portrait_frame != null:
		slot.portrait_frame.visible = vis
	if slot.name_label != null:
		slot.name_label.visible = vis
	if slot.state_label != null:
		slot.state_label.visible = vis
	if slot.carry_track != null:
		slot.carry_track.visible = vis
	if slot.carry_fill != null:
		slot.carry_fill.visible = vis and slot.carry_fill.size.x > 0.5


func _bind_slot_unit(slot: _SteleSlot, unit: Unit) -> void:
	if slot.unit == unit:
		return
	_unbind_slot_unit(slot)
	if not _is_unit_valid(unit):
		return
	slot.unit = unit
	if not unit.state_changed.is_connected(slot.state_cb):
		unit.state_changed.connect(slot.state_cb)
	if not unit.tree_exited.is_connected(slot.exit_cb):
		unit.tree_exited.connect(slot.exit_cb)
	slot.carry_load = unit.get_carry_load()
	if slot.carry_load != null:
		if not slot.carry_load.load_changed.is_connected(slot.carry_cb):
			slot.carry_load.load_changed.connect(slot.carry_cb)
		if not slot.carry_load.capacity_changed.is_connected(slot.carry_cb):
			slot.carry_load.capacity_changed.connect(slot.carry_cb)


func _unbind_slot_unit(slot: _SteleSlot) -> void:
	if slot.unit != null and is_instance_valid(slot.unit):
		if slot.state_cb.is_valid() and slot.unit.state_changed.is_connected(slot.state_cb):
			slot.unit.state_changed.disconnect(slot.state_cb)
		if slot.exit_cb.is_valid() and slot.unit.tree_exited.is_connected(slot.exit_cb):
			slot.unit.tree_exited.disconnect(slot.exit_cb)
	if slot.carry_load != null:
		if slot.carry_cb.is_valid() and slot.carry_load.load_changed.is_connected(slot.carry_cb):
			slot.carry_load.load_changed.disconnect(slot.carry_cb)
		if slot.carry_cb.is_valid() and slot.carry_load.capacity_changed.is_connected(slot.carry_cb):
			slot.carry_load.capacity_changed.disconnect(slot.carry_cb)
	slot.unit = null
	slot.carry_load = null


func _sync_selection_from_manager() -> void:
	var any_sel_changed: bool = false
	for slot: _SteleSlot in _slots:
		var now_sel: bool = (
			_selection_manager != null
			and is_instance_valid(_selection_manager)
			and _is_unit_valid(slot.unit)
			and _selection_manager.is_selected(slot.unit)
		)
		if slot.selected != now_sel:
			slot.selected = now_sel
			any_sel_changed = true
	if any_sel_changed and _built:
		for slot: _SteleSlot in _slots:
			_layout_slot(slot)


func _on_selection_changed(_selected_units: Array[Unit]) -> void:
	_sync_selection_from_manager()
	refresh()


func _on_slot_unit_state_changed(_new_state: Unit.State, _prev_state: Unit.State, slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _slots.size():
		_render_slot(_slots[slot_index])
		_apply_count += 1


func _on_slot_carry_changed(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _slots.size():
		_render_slot(_slots[slot_index])
		_apply_count += 1


func _on_slot_unit_tree_exited(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot: _SteleSlot = _slots[slot_index]
	_unbind_slot_unit(slot)
	slot.selected = false
	_set_slot_visible(slot, false)
	_apply_count += 1


func _on_stele_clicked(shift_held: bool, slot_index: int) -> void:
	if _selection_manager == null or not is_instance_valid(_selection_manager):
		return
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var unit: Unit = _slots[slot_index].unit
	if not _is_unit_valid(unit):
		return
	if shift_held:
		_selection_manager.toggle_unit(unit)
	else:
		_selection_manager.select_single(unit)


func _disconnect_selection_manager() -> void:
	if _selection_manager != null and is_instance_valid(_selection_manager):
		if _selection_manager.selection_changed.is_connected(_on_selection_changed):
			_selection_manager.selection_changed.disconnect(_on_selection_changed)


func _resolve_portrait_texture(character_id: StringName) -> Texture2D:
	if character_id.is_empty() or not PORTRAIT_BY_CHARACTER_ID.has(character_id):
		return null
	if _portrait_cache.has(character_id):
		return _portrait_cache[character_id] as Texture2D
	var path: String = String(PORTRAIT_BY_CHARACTER_ID[character_id])
	var tex: Texture2D = _load_texture_res(path)
	if tex != null:
		_portrait_cache[character_id] = tex
	return tex


static func _load_texture_res(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded: Resource = ResourceLoader.load(path)
		if loaded is Texture2D:
			return loaded as Texture2D
	if FileAccess.file_exists(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var img := Image.new()
			var err: Error = ERR_FILE_UNRECOGNIZED
			if path.ends_with(".jpg") or path.ends_with(".jpeg"):
				err = img.load_jpg_from_buffer(bytes)
			elif path.ends_with(".png"):
				err = img.load_png_from_buffer(bytes)
			if err == OK:
				return ImageTexture.create_from_image(img)
	return null


static func _order_founder_units(units: Array[Unit]) -> Array[Unit]:
	var leader_a: Unit = null
	var leader_b: Unit = null
	var others: Array[Unit] = []
	for u: Unit in units:
		if not _is_unit_valid(u):
			continue
		var def: CharacterDefinition = u.get_definition()
		var cid: StringName = def.character_id if def != null else &""
		if cid == &"leader_a" and leader_a == null:
			leader_a = u
		elif cid == &"leader_b" and leader_b == null:
			leader_b = u
		elif not others.has(u):
			others.append(u)
	var ordered: Array[Unit] = []
	if leader_a != null:
		ordered.append(leader_a)
	if leader_b != null:
		ordered.append(leader_b)
	for extra: Unit in others:
		if ordered.size() >= MAX_FOUNDER_SLOTS:
			break
		ordered.append(extra)
	return ordered


static func _color_for_unit_state(state: Unit.State, is_selected: bool) -> Color:
	match state:
		Unit.State.WORKING:
			return D2Tokens.COLOR_FEEDBACK_VALID_BRIGHT
		Unit.State.TRANSPORTING:
			return D2Tokens.COLOR_FEEDBACK_AMBER
		Unit.State.MOVING:
			return D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT if is_selected else D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
		_:
			return D2Tokens.COLOR_ACCENT_GOLD_PRIMARY if is_selected else D2Tokens.COLOR_TEXT_SECONDARY_MUTED


static func _is_unit_valid(unit: Unit) -> bool:
	return unit != null and is_instance_valid(unit) and unit.is_inside_tree()
