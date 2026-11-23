class_name D2ConstructionDockView
extends Control
## D2.2 Vertical alabaster construction maquette dock (UI-1.3).
##
## Design & Architecture Rules:
## - Reuses canonical D2.2 atlas regions:
##   - "maquette_shelter" (210x238 / 190x218 content, 10 px shadow_pad) for resting maquettes.
##   - "maquette_depot_sel" (226x264 / 206x244 content, 10 px shadow_pad, raised -14 px) for
##     the maquette currently active in PlacementController.
## - Uses approved illustrations "d1_shelter_mini.png" and "d1_depot_mini.png".
## - Reads names, dimensions, build work, and material costs EXCLUSIVELY from real
##   BuildingDefinition instances (zero hardcoded cost duplication in UI).
## - Never falsely advertises unimplemented T3.7 protected storage capacity as active.
## - Clicking a maquette or pressing [1]/[2] (within construction context) delegates strictly
##   to PlacementController.start_placement(def); never creates sites or touches inventory.
## - [B] toggles dock open/closed when unpaused; Esc is handled solely by D2UiEscapeRouter.
## - process_mode = PROCESS_MODE_PAUSABLE; zero per-frame polling.

signal dock_open_changed(is_open: bool)

const MINIATURE_BY_DEFINITION_ID: Dictionary = {
	&"shelter_basic": D2AtlasLibrary.SHELTER_MINI_PATH,
	&"storage_depot": D2AtlasLibrary.DEPOT_MINI_PATH,
}


class _MaquetteHitButton:
	extends D2SlabButton

	func _init() -> void:
		super._init()

	func _draw() -> void:
		if _scaled_polygon.size() < 3:
			return
		var outline := PackedVector2Array(_scaled_polygon)
		outline.append(_scaled_polygon[0])
		if is_pressed():
			draw_colored_polygon(_scaled_polygon, Color(0.875, 0.737, 0.447, 0.18))
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_PRIMARY, 1.5, true)
		elif _is_active_state:
			draw_colored_polygon(_scaled_polygon, Color(0.220, 0.357, 0.165, 0.05))
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 2.0, true)
		elif _is_hovered_visual:
			draw_colored_polygon(_scaled_polygon, Color(0.875, 0.737, 0.447, 0.10))
			draw_polyline(outline, D2Tokens.COLOR_ACCENT_GOLD_HIGHLIGHT, 1.5, true)


class _MaquetteCard:
	extends RefCounted
	var index: int = 0
	var definition: BuildingDefinition = null
	var is_selected: bool = false
	var slab: D2PolygonalSlab = null
	var hit_button: _MaquetteHitButton = null
	var status_tag: Label = null
	var shortcut_badge: Panel = null
	var shortcut_label: Label = null
	var miniature: TextureRect = null
	var title_label: Label = null
	var subtitle_label: Label = null
	var cost_label: Label = null
	var content_rect: Rect2 = Rect2()


var _atlas: D2AtlasLibrary = null
var _theme_factory: D2ThemeFactory = null
var _placement_controller: PlacementController = null
var _definitions: Array[BuildingDefinition] = []
var _cards: Array[_MaquetteCard] = []
var _miniature_cache: Dictionary = {}

var _dock_open: bool = false
var _built: bool = false
var _viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var _scale_factor: float = D2Tokens.SCALE_1080P


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
	_built = true
	_rebuild_cards()
	apply_layout(_viewport_size, _scale_factor)
	_sync_card_states()


func configure(
	placement_controller: PlacementController,
	definitions: Array[BuildingDefinition]
) -> void:
	_disconnect_controller()
	_placement_controller = placement_controller
	_definitions.clear()
	for def: BuildingDefinition in definitions:
		if def != null and def.is_valid():
			_definitions.append(def)

	if _placement_controller != null and is_instance_valid(_placement_controller):
		if not _placement_controller.placement_started.is_connected(_on_placement_started):
			_placement_controller.placement_started.connect(_on_placement_started)
		if not _placement_controller.placement_cancelled.is_connected(_on_placement_ended):
			_placement_controller.placement_cancelled.connect(_on_placement_ended)
		if not _placement_controller.placement_confirmed.is_connected(_on_placement_confirmed):
			_placement_controller.placement_confirmed.connect(_on_placement_confirmed)

	if _built:
		_rebuild_cards()
		apply_layout(_viewport_size, _scale_factor)
		_sync_card_states()


func unbind() -> void:
	_disconnect_controller()
	_placement_controller = null
	_definitions.clear()
	if _dock_open:
		_dock_open = false
		visible = false
		dock_open_changed.emit(false)
	else:
		visible = false
	_clear_cards()


func is_bound_to_controller(controller: PlacementController) -> bool:
	if controller == null or _placement_controller != controller:
		return false
	return controller.placement_started.is_connected(_on_placement_started)


func set_dock_open(open: bool) -> void:
	var target: bool = open and _placement_controller != null and is_instance_valid(_placement_controller) and not _definitions.is_empty()
	if _dock_open == target:
		visible = _dock_open
		return
	_dock_open = target
	visible = _dock_open
	if _dock_open:
		_sync_card_states()
		apply_layout(_viewport_size, _scale_factor)
	dock_open_changed.emit(_dock_open)


func toggle_dock() -> void:
	set_dock_open(not _dock_open)


func is_dock_open() -> bool:
	return _dock_open


func select_building_index(index: int) -> bool:
	if _placement_controller == null or not is_instance_valid(_placement_controller):
		return false
	if index < 0 or index >= _definitions.size():
		return false
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return false
	var def: BuildingDefinition = _definitions[index]
	if def == null or not def.is_valid():
		return false
	var started: bool = _placement_controller.start_placement(def)
	if started:
		set_dock_open(false)
	return started


func select_building_by_id(definition_id: StringName) -> bool:
	for i: int in range(_definitions.size()):
		if _definitions[i].definition_id == definition_id:
			return select_building_index(i)
	return false


func refresh() -> void:
	_sync_card_states()
	apply_layout(_viewport_size, _scale_factor)


func apply_layout(viewport_size: Vector2, scale_factor: float) -> void:
	_viewport_size = viewport_size
	_scale_factor = scale_factor
	if not _built or _atlas == null or _cards.is_empty():
		return

	var s: float = _scale_factor
	var w: float = _viewport_size.x
	var h: float = _viewport_size.y
	var base_bottom: float = h - D2Tokens.MAQUETTE_BASE_MARGIN_BOTTOM * s
	var gap_x: float = D2Tokens.MAQUETTE_GAP_X * s
	var right_cursor: float = w - D2Tokens.MAQUETTE_MARGIN_RIGHT * s

	# Lay out cards right-to-left so the rightmost card anchors cleanly to the right margin
	# regardless of which maquette is currently elevated/widened.
	for rev_idx: int in range(_cards.size() - 1, -1, -1):
		var card: _MaquetteCard = _cards[rev_idx]
		var is_sel: bool = card.is_selected
		var base_sz: Vector2 = D2Tokens.MAQUETTE_SELECTED_SIZE if is_sel else D2Tokens.MAQUETTE_NORMAL_SIZE
		var region_key: String = "maquette_depot_sel" if is_sel else "maquette_shelter"
		var poly: Array[Vector2] = D2Tokens.POLYGON_MAQUETTE_DEPOT_SEL if is_sel else D2Tokens.POLYGON_MAQUETTE_SHELTER
		var cw: float = base_sz.x * s
		var ch: float = base_sz.y * s
		var lift_y: float = D2Tokens.MAQUETTE_SELECTED_LIFT_Y * s if is_sel else 0.0
		var cx: float = right_cursor - cw
		var cy: float = base_bottom - ch - lift_y
		right_cursor = cx - gap_x

		card.content_rect = Rect2(Vector2(cx, cy), Vector2(cw, ch))

		var meta: Dictionary = _atlas.get_region_metadata(region_key)
		var pad: float = float(meta.get("pad", D2Tokens.ATLAS_SHADOW_PAD))
		var slab_pos := Vector2(cx - pad * s, cy - pad * s)
		var slab_sz := Vector2(float(meta.get("w", base_sz.x + 20.0)) * s, float(meta.get("h", base_sz.y + 20.0)) * s)

		card.slab.texture = _atlas.get_region_texture(region_key)
		card.slab.configure_polygon(poly, base_sz, pad)
		card.slab.position = slab_pos
		card.slab.set_scaled_size(slab_sz)

		card.hit_button.configure_polygon(poly, base_sz, pad)
		card.hit_button.position = slab_pos
		card.hit_button.set_scaled_size(slab_sz)
		card.hit_button.set_active_state(is_sel)

		# Top-right key shortcut badge ([1] / [2])
		var badge_w: float = 24.0 * s
		var badge_h: float = 18.0 * s
		card.shortcut_badge.position = Vector2(cx + cw - badge_w - 10.0 * s, cy + 10.0 * s)
		card.shortcut_badge.size = Vector2(badge_w, badge_h)
		card.shortcut_label.position = Vector2.ZERO
		card.shortcut_label.size = Vector2(badge_w, badge_h)
		_apply_font(card.shortcut_label, false, true, maxi(9, int(round(10.0 * s))))

		if is_sel:
			card.status_tag.visible = true
			card.status_tag.position = Vector2(cx + 12.0 * s, cy + 12.0 * s)
			card.status_tag.size = Vector2(cw - 44.0 * s, 16.0 * s)
			_apply_font(card.status_tag, false, true, maxi(9, int(round(9.8 * s))))

			card.miniature.position = Vector2(cx + (cw - 128.0 * s) * 0.5, cy + 32.0 * s)
			card.miniature.size = Vector2(128.0 * s, 128.0 * s)

			card.title_label.position = Vector2(cx + 10.0 * s, cy + 166.0 * s)
			card.title_label.size = Vector2(cw - 20.0 * s, 23.0 * s)
			_apply_font(card.title_label, true, true, maxi(11, int(round(16.0 * s))))

			card.subtitle_label.position = Vector2(cx + 10.0 * s, cy + 190.0 * s)
			card.subtitle_label.size = Vector2(cw - 20.0 * s, 17.0 * s)
			_apply_font(card.subtitle_label, false, false, maxi(9, int(round(10.6 * s))))

			card.cost_label.position = Vector2(cx + 10.0 * s, cy + 213.0 * s)
			card.cost_label.size = Vector2(cw - 20.0 * s, 19.0 * s)
			_apply_font(card.cost_label, false, true, maxi(10, int(round(11.8 * s))))
		else:
			card.status_tag.visible = false

			card.miniature.position = Vector2(cx + (cw - 116.0 * s) * 0.5, cy + 16.0 * s)
			card.miniature.size = Vector2(116.0 * s, 116.0 * s)

			card.title_label.position = Vector2(cx + 10.0 * s, cy + 136.0 * s)
			card.title_label.size = Vector2(cw - 20.0 * s, 22.0 * s)
			_apply_font(card.title_label, true, true, maxi(11, int(round(15.2 * s))))

			card.subtitle_label.position = Vector2(cx + 10.0 * s, cy + 160.0 * s)
			card.subtitle_label.size = Vector2(cw - 20.0 * s, 17.0 * s)
			_apply_font(card.subtitle_label, false, false, maxi(9, int(round(10.5 * s))))

			card.cost_label.position = Vector2(cx + 10.0 * s, cy + 183.0 * s)
			card.cost_label.size = Vector2(cw - 20.0 * s, 19.0 * s)
			_apply_font(card.cost_label, false, true, maxi(10, int(round(11.6 * s))))


func _unhandled_input(event: InputEvent) -> void:
	if _placement_controller == null or not is_instance_valid(_placement_controller):
		return
	if _definitions.is_empty():
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return
	if not (event is InputEventKey):
		return
	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev.pressed or key_ev.echo:
		return
	if key_ev.ctrl_pressed or key_ev.alt_pressed or key_ev.meta_pressed:
		return

	var code: Key = key_ev.keycode if key_ev.keycode != KEY_NONE else key_ev.physical_keycode
	if code == KEY_B:
		toggle_dock()
		_consume_viewport_input()
		return

	var in_construction_context: bool = _dock_open or _placement_controller.is_placement_active()
	if not in_construction_context:
		return

	if code == KEY_1 or code == KEY_KP_1:
		if select_building_index(0):
			_consume_viewport_input()
	elif code == KEY_2 or code == KEY_KP_2:
		if select_building_index(1):
			_consume_viewport_input()


func get_card_count() -> int:
	return _cards.size()


func get_card_slab(index: int) -> D2PolygonalSlab:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index].slab


func get_card_button(index: int) -> D2SlabButton:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index].hit_button


func get_card_definition(index: int) -> BuildingDefinition:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index].definition


func get_card_title_text(index: int) -> String:
	if index < 0 or index >= _cards.size():
		return ""
	return _cards[index].title_label.text


func get_card_subtitle_text(index: int) -> String:
	if index < 0 or index >= _cards.size():
		return ""
	return _cards[index].subtitle_label.text


func get_card_cost_text(index: int) -> String:
	if index < 0 or index >= _cards.size():
		return ""
	return _cards[index].cost_label.text


func is_card_selected(index: int) -> bool:
	if index < 0 or index >= _cards.size():
		return false
	return _cards[index].is_selected


func get_card_content_rect(index: int) -> Rect2:
	if index < 0 or index >= _cards.size():
		return Rect2()
	return _cards[index].content_rect


func get_content_bounds() -> Rect2:
	var combined := Rect2()
	var has_any: bool = false
	for card: _MaquetteCard in _cards:
		if card.content_rect.size == Vector2.ZERO:
			continue
		if not has_any:
			combined = card.content_rect
			has_any = true
		else:
			combined = combined.merge(card.content_rect)
	return combined


static func format_costs(definition: BuildingDefinition) -> String:
	if definition == null:
		return ""
	var parts: Array[String] = []
	var ordered_keys: Array[StringName] = [&"wood", &"stone", &"food"]
	var short_names: Dictionary = {
		&"wood": "Mad",
		&"stone": "Ped",
		&"food": "Ali",
	}
	var seen: Dictionary = {}
	for key: StringName in ordered_keys:
		var amount: int = int(definition.costs.get(key, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, String(short_names[key])])
			seen[key] = true
	for raw_key: Variant in definition.costs.keys():
		var k := StringName(raw_key)
		if seen.has(k):
			continue
		var amount: int = int(definition.costs.get(raw_key, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, String(k).capitalize()])
	if parts.is_empty():
		return "Sem custo"
	return " · ".join(parts)


static func format_factual_subtitle(definition: BuildingDefinition) -> String:
	if definition == null:
		return ""
	var w_str: String = _format_dim(definition.footprint_size.x)
	var d_str: String = _format_dim(definition.footprint_size.y)
	var work_sec: int = int(round(definition.build_work_required_sec))
	return "%s×%s m · %d s · máx. %d" % [w_str, d_str, work_sec, definition.max_builders]


static func _format_dim(val: float) -> String:
	if is_equal_approx(val, round(val)):
		return "%d" % int(round(val))
	return "%.1f" % val


func _rebuild_cards() -> void:
	_clear_cards()
	if _atlas == null:
		return

	for i: int in range(_definitions.size()):
		var def: BuildingDefinition = _definitions[i]
		var card := _MaquetteCard.new()
		card.index = i
		card.definition = def

		card.slab = D2PolygonalSlab.new()
		card.slab.name = "MaquetteSlab_%s" % String(def.definition_id)
		card.slab.texture = _atlas.get_region_texture("maquette_shelter")
		card.slab.configure_polygon(
			D2Tokens.POLYGON_MAQUETTE_SHELTER,
			D2Tokens.MAQUETTE_NORMAL_SIZE,
			D2Tokens.ATLAS_SHADOW_PAD
		)
		add_child(card.slab)

		card.hit_button = _MaquetteHitButton.new()
		card.hit_button.name = "MaquetteButton_%s" % String(def.definition_id)
		card.hit_button.configure_polygon(
			D2Tokens.POLYGON_MAQUETTE_SHELTER,
			D2Tokens.MAQUETTE_NORMAL_SIZE,
			D2Tokens.ATLAS_SHADOW_PAD
		)
		card.hit_button.pressed.connect(_on_card_pressed.bind(i))
		add_child(card.hit_button)

		card.status_tag = Label.new()
		card.status_tag.name = "MaquetteStatus_%d" % i
		card.status_tag.text = "● EM POSIÇÃO"
		card.status_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.status_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.status_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.status_tag.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_VALID_GREEN)
		card.status_tag.visible = false
		add_child(card.status_tag)

		card.shortcut_badge = Panel.new()
		card.shortcut_badge.name = "MaquetteShortcut_%d" % i
		card.shortcut_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge_sb := StyleBoxFlat.new()
		badge_sb.bg_color = Color(0.114, 0.094, 0.075, 0.08)
		badge_sb.set_border_width_all(1)
		badge_sb.border_color = D2Tokens.COLOR_ACCENT_GOLD_PRIMARY
		card.shortcut_badge.add_theme_stylebox_override(&"panel", badge_sb)
		add_child(card.shortcut_badge)

		card.shortcut_label = Label.new()
		card.shortcut_label.name = "MaquetteShortcutLabel_%d" % i
		card.shortcut_label.text = "[%d]" % (i + 1)
		card.shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.shortcut_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.shortcut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.shortcut_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_ON_ALABASTER_SUB)
		card.shortcut_badge.add_child(card.shortcut_label)

		card.miniature = TextureRect.new()
		card.miniature.name = "MaquetteMini_%d" % i
		card.miniature.texture = _get_miniature_texture(def.definition_id)
		card.miniature.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.miniature.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.miniature.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card.miniature)

		card.title_label = Label.new()
		card.title_label.name = "MaquetteTitle_%d" % i
		card.title_label.text = def.display_name
		card.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.title_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_ON_ALABASTER_INK)
		add_child(card.title_label)

		card.subtitle_label = Label.new()
		card.subtitle_label.name = "MaquetteSub_%d" % i
		card.subtitle_label.text = format_factual_subtitle(def)
		card.subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.subtitle_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_TEXT_ON_ALABASTER_SUB)
		add_child(card.subtitle_label)

		card.cost_label = Label.new()
		card.cost_label.name = "MaquetteCost_%d" % i
		card.cost_label.text = format_costs(def)
		card.cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.cost_label.add_theme_color_override(&"font_color", D2Tokens.COLOR_FEEDBACK_VALID_GREEN)
		add_child(card.cost_label)

		_cards.append(card)


func _clear_cards() -> void:
	for card: _MaquetteCard in _cards:
		for node: Node in [
			card.slab,
			card.hit_button,
			card.status_tag,
			card.shortcut_badge,
			card.miniature,
			card.title_label,
			card.subtitle_label,
			card.cost_label,
		]:
			if node != null and is_instance_valid(node):
				node.queue_free()
	_cards.clear()


func _sync_card_states() -> void:
	var active_def: BuildingDefinition = null
	if _placement_controller != null and is_instance_valid(_placement_controller) and _placement_controller.is_placement_active():
		active_def = _placement_controller.get_active_definition()

	for card: _MaquetteCard in _cards:
		card.is_selected = (
			active_def != null
			and card.definition != null
			and (card.definition == active_def or card.definition.definition_id == active_def.definition_id)
		)
		if card.hit_button != null:
			card.hit_button.set_active_state(card.is_selected)
		if card.status_tag != null:
			card.status_tag.visible = card.is_selected


func _on_card_pressed(index: int) -> void:
	select_building_index(index)


func _on_placement_started(_definition: BuildingDefinition) -> void:
	_sync_card_states()
	if _dock_open:
		set_dock_open(false)


func _on_placement_ended(_definition: BuildingDefinition) -> void:
	_sync_card_states()
	if _dock_open:
		apply_layout(_viewport_size, _scale_factor)


func _on_placement_confirmed(
	_definition: BuildingDefinition,
	_world_position: Vector3,
	_result: PlacementValidator.ValidationResult
) -> void:
	_sync_card_states()
	if _dock_open:
		apply_layout(_viewport_size, _scale_factor)


func _disconnect_controller() -> void:
	if _placement_controller != null and is_instance_valid(_placement_controller):
		if _placement_controller.placement_started.is_connected(_on_placement_started):
			_placement_controller.placement_started.disconnect(_on_placement_started)
		if _placement_controller.placement_cancelled.is_connected(_on_placement_ended):
			_placement_controller.placement_cancelled.disconnect(_on_placement_ended)
		if _placement_controller.placement_confirmed.is_connected(_on_placement_confirmed):
			_placement_controller.placement_confirmed.disconnect(_on_placement_confirmed)


func _get_miniature_texture(definition_id: StringName) -> Texture2D:
	if _miniature_cache.has(definition_id):
		return _miniature_cache[definition_id] as Texture2D
	var path: String = String(MINIATURE_BY_DEFINITION_ID.get(definition_id, ""))
	if path.is_empty():
		return null
	var tex: Texture2D = D2AtlasLibrary._load_texture(path)
	if tex != null:
		_miniature_cache[definition_id] = tex
	return tex


func _consume_viewport_input() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _apply_font(lbl: Label, serif: bool, bold: bool, font_px: int) -> void:
	lbl.add_theme_font_size_override(&"font_size", font_px)
	if _theme_factory == null:
		return
	var f: Font = _theme_factory.get_serif_font(bold) if serif else _theme_factory.get_sans_font(bold)
	if f != null:
		lbl.add_theme_font_override(&"font", f)
