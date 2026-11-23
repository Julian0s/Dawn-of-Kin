class_name D2HudRoot
extends Control
## Lightweight root compositor for Dawn of Kin D2.2 HUD (UI-1.1A + UI-1.1B + UI-1.2).
## Owns D2AtlasLibrary, D2ThemeFactory, responsive scaling, D2ResourceRocksView,
## D2TopPlaqueView, D2FounderStelesView, D2LineageBladeView,
## D2SimulationPauseController (PROCESS_MODE_ALWAYS), and D2UiEscapeRouter (pass-through).
## Never holds economic or selection authority and never polls per frame.

signal layout_updated(scale_factor: float)

var _atlas: D2AtlasLibrary = D2AtlasLibrary.new()
var _theme_factory: D2ThemeFactory = D2ThemeFactory.new()
var _rocks_view: D2ResourceRocksView = null
var _plaque_view: D2TopPlaqueView = null
var _founder_steles_view: D2FounderStelesView = null
var _lineage_blade_view: D2LineageBladeView = null
var _pause_controller: D2SimulationPauseController = null
var _escape_router: D2UiEscapeRouter = null

var _bound_viewport: Viewport = null
var _current_scale: float = D2Tokens.SCALE_1080P
var _built: bool = false


func _init() -> void:
	# Must be ALWAYS so Godot's Viewport::_gui_find_control_at_pos() traverses down to
	# D2TopPlaqueView (PROCESS_MODE_ALWAYS) during SceneTree pause.
	# D2HudRoot itself does zero processing (set_process(false), MOUSE_FILTER_IGNORE),
	# while D2ResourceRocksView, D2FounderStelesView, and D2LineageBladeView stay PROCESS_MODE_PAUSABLE.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_built()
	_bind_viewport_resize()
	_update_responsive_layout()


func _exit_tree() -> void:
	unbind()


func configure(
	settlement_inventory: SettlementInventory,
	camp_storage_zone: CampStorageZone = null,
	ground_pile_manager: GroundPileManager = null,
	camera_rig: RtsCameraRig = null,
	economy_clock: EconomyClockController = null,
	selection_manager: SelectionManager = null,
	units: Array[Unit] = []
) -> void:
	_ensure_built()
	if _pause_controller != null:
		_pause_controller.configure(camera_rig, economy_clock)
	if _rocks_view != null:
		_rocks_view.configure(settlement_inventory, camp_storage_zone, ground_pile_manager)
	if _plaque_view != null:
		_plaque_view.configure(settlement_inventory, camp_storage_zone, ground_pile_manager)
		_plaque_view.bind_pause_controller(_pause_controller)
	if _founder_steles_view != null:
		_founder_steles_view.configure(selection_manager, units)
	if _lineage_blade_view != null:
		_lineage_blade_view.configure(selection_manager)
	_update_responsive_layout()


func unbind() -> void:
	_unbind_viewport_resize()
	if _rocks_view != null and is_instance_valid(_rocks_view):
		_rocks_view.unbind()
	if _plaque_view != null and is_instance_valid(_plaque_view):
		_plaque_view.unbind()
	if _founder_steles_view != null and is_instance_valid(_founder_steles_view):
		_founder_steles_view.unbind()
	if _lineage_blade_view != null and is_instance_valid(_lineage_blade_view):
		_lineage_blade_view.unbind()
	if _pause_controller != null and is_instance_valid(_pause_controller):
		_pause_controller.unbind()
	if _escape_router != null and is_instance_valid(_escape_router):
		_escape_router.clear_handlers()


func refresh_all() -> void:
	if _rocks_view != null:
		_rocks_view.refresh()
	if _plaque_view != null:
		_plaque_view.refresh()
	if _founder_steles_view != null:
		_founder_steles_view.refresh()
	if _lineage_blade_view != null:
		_lineage_blade_view.refresh()
	if _pause_controller != null:
		_pause_controller.sync_external_state()


func get_atlas_library() -> D2AtlasLibrary:
	return _atlas


func get_theme_factory() -> D2ThemeFactory:
	return _theme_factory


func get_resource_rocks_view() -> D2ResourceRocksView:
	return _rocks_view


func get_top_plaque_view() -> D2TopPlaqueView:
	return _plaque_view


func get_founder_steles_view() -> D2FounderStelesView:
	return _founder_steles_view


func get_lineage_blade_view() -> D2LineageBladeView:
	return _lineage_blade_view


func get_pause_controller() -> D2SimulationPauseController:
	return _pause_controller


func get_escape_router() -> D2UiEscapeRouter:
	return _escape_router


func get_current_scale() -> float:
	return _current_scale


func get_debug_overlay_top_offset() -> float:
	if _rocks_view == null:
		return 12.0
	var bounds: Rect2 = _rocks_view.get_content_bounds()
	return bounds.end.y + 12.0 * _current_scale


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_atlas.load_all()
	theme = _theme_factory.build_theme()

	_pause_controller = D2SimulationPauseController.new()
	_pause_controller.name = "D2SimulationPauseController"
	add_child(_pause_controller)

	_escape_router = D2UiEscapeRouter.new()
	_escape_router.name = "D2UiEscapeRouter"
	add_child(_escape_router)

	_rocks_view = D2ResourceRocksView.new()
	_rocks_view.name = "D2ResourceRocksView"
	add_child(_rocks_view)

	_plaque_view = D2TopPlaqueView.new()
	_plaque_view.name = "D2TopPlaqueView"
	add_child(_plaque_view)

	_founder_steles_view = D2FounderStelesView.new()
	_founder_steles_view.name = "D2FounderStelesView"
	add_child(_founder_steles_view)

	_lineage_blade_view = D2LineageBladeView.new()
	_lineage_blade_view.name = "D2LineageBladeView"
	add_child(_lineage_blade_view)

	var vp: Viewport = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1920.0, 1080.0)
	_current_scale = D2ScaleController.compute_scale_for_viewport(vp)
	_rocks_view.setup_visuals(_atlas, _theme_factory, _current_scale)
	_plaque_view.setup_visuals(_atlas, _theme_factory, vp_size, _current_scale)
	_plaque_view.bind_pause_controller(_pause_controller)
	_founder_steles_view.setup_visuals(_atlas, _theme_factory, vp_size, _current_scale)
	_lineage_blade_view.setup_visuals(_atlas, _theme_factory, vp_size, _current_scale)


func _bind_viewport_resize() -> void:
	var vp: Viewport = get_viewport()
	if vp == _bound_viewport:
		return
	_unbind_viewport_resize()
	_bound_viewport = vp
	if _bound_viewport != null and not _bound_viewport.size_changed.is_connected(_on_viewport_size_changed):
		_bound_viewport.size_changed.connect(_on_viewport_size_changed)


func _unbind_viewport_resize() -> void:
	if _bound_viewport != null and is_instance_valid(_bound_viewport):
		if _bound_viewport.size_changed.is_connected(_on_viewport_size_changed):
			_bound_viewport.size_changed.disconnect(_on_viewport_size_changed)
	_bound_viewport = null


func _on_viewport_size_changed() -> void:
	_update_responsive_layout()


func _update_responsive_layout() -> void:
	if not _built:
		return
	var vp: Viewport = get_viewport()
	var vp_size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1920.0, 1080.0)
	_current_scale = D2ScaleController.compute_scale_for_viewport(vp)
	if _rocks_view != null:
		_rocks_view.apply_scale(_current_scale)
	if _plaque_view != null:
		_plaque_view.apply_layout(vp_size, _current_scale)
	if _founder_steles_view != null:
		_founder_steles_view.apply_layout(vp_size, _current_scale)
	if _lineage_blade_view != null:
		_lineage_blade_view.apply_layout(vp_size, _current_scale)
	layout_updated.emit(_current_scale)
