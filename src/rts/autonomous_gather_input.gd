class_name AutonomousGatherInput
extends RtsInputController
## Unified R-03A D1 input adapter for decoupled natural resource source selection and explicit HUD authorization.
## - Left-click without Shift on unselected source: selects ONLY that source (no task created).
## - Left-click without Shift on already selected source (D1-B): deselects ONLY that source, preserving others.
## - Shift + left-click on source: toggles individual source across heterogeneous categories (wood/stone/food).
## - Shift + drag from ANY valid playable point: adds eligible sources in box (heterogeneous union, idempotent,
##   never touches SelectionManager or falls back to unit box selection).
## - Drag without Shift: ALWAYS traditional RTS unit box selection (even if started over a resource source).
## - Explicit authorization/reauthorization (D1-C): triggered exclusively via CommunitySelectionActionsHud
##   or authorize_selected_category(resource_id), never on source selection gestures.

enum DragMode {
	NONE,
	UNIT_BOX_RTS,
	SOURCE_BOX_ADD,
}

const RING_SEGMENTS: int = 24
const RING_INNER_RADIUS: float = 0.72
const RING_OUTER_RADIUS: float = 0.90
const SELECTION_RING_INNER_RADIUS: float = 0.98
const SELECTION_RING_OUTER_RADIUS: float = 1.12
const RING_COLOR_WOOD: Color = Color(0.55, 0.86, 0.42, 0.85)
const RING_COLOR_STONE: Color = Color(0.66, 0.78, 0.90, 0.85)
const RING_COLOR_FOOD: Color = Color(0.92, 0.66, 0.34, 0.85)
const SELECTION_RING_COLOR: Color = Color(0.95, 0.85, 0.56, 0.90)

@export var supported_resource_ids: PackedStringArray = PackedStringArray(["wood"])
@export var multi_source_enabled: bool = false

var _selection_model: SourceSelectionModel = SourceSelectionModel.new()
var _board: CommunityWorkBoard = null
var _dispatcher: CommunityTaskDispatcher = null
var _feedback: AutonomousGatherFeedback = null
var _actions_hud: CommunitySelectionActionsHud = null
var _wired: bool = false
var _torn_down: bool = false
var _use_provenance_economy: bool = true
var _economy_admission_reason: String = ""

var _shared_ring_mesh: ArrayMesh = null
var _shared_selection_ring_mesh: ArrayMesh = null
var _shared_ring_materials: Dictionary = {}
var _shared_selection_ring_material: StandardMaterial3D = null
var _task_highlights: Dictionary = {}
var _selection_highlights: Dictionary = {}

var _drag_mode: DragMode = DragMode.NONE


func _ready() -> void:
	super._ready()
	call_deferred("_ensure_wired")


func _exit_tree() -> void:
	teardown_community_work()
	super._exit_tree()


func get_source_selection_model() -> SourceSelectionModel:
	return _selection_model


func get_active_drag_mode() -> DragMode:
	return _drag_mode


func configure_community_work(
	p_board: CommunityWorkBoard,
	p_dispatcher: CommunityTaskDispatcher,
	p_feedback: AutonomousGatherFeedback = null,
	p_use_provenance: bool = true,
	p_economy_admission_reason: String = "",
	p_actions_hud: CommunitySelectionActionsHud = null
) -> void:
	_disconnect_signals()
	_clear_drag_state()
	_clear_all_selection_highlights()
	_clear_all_task_highlights()
	_torn_down = false
	_board = p_board
	_dispatcher = p_dispatcher
	_feedback = p_feedback
	_actions_hud = p_actions_hud
	_use_provenance_economy = p_use_provenance
	_economy_admission_reason = p_economy_admission_reason
	if _board == null or not is_instance_valid(_board) or _dispatcher == null or not is_instance_valid(_dispatcher):
		_selection_model.teardown()
		_wired = false
		return

	_selection_model.configure(Callable(_board, "is_source_in_region_domain"), supported_resource_ids)
	if not _selection_model.selection_changed.is_connected(_on_source_selection_changed):
		_selection_model.selection_changed.connect(_on_source_selection_changed)

	if not _board.task_registered.is_connected(_on_task_registered):
		_board.task_registered.connect(_on_task_registered)
	if not _board.task_closed.is_connected(_on_task_closed):
		_board.task_closed.connect(_on_task_closed)
	if not _dispatcher.task_feedback.is_connected(_on_dispatcher_feedback):
		_dispatcher.task_feedback.connect(_on_dispatcher_feedback)
	if _actions_hud != null and is_instance_valid(_actions_hud):
		if not _actions_hud.category_authorize_requested.is_connected(_on_hud_category_authorize_requested):
			_actions_hud.category_authorize_requested.connect(_on_hud_category_authorize_requested)

	for existing_task: WorkTask in _board.get_active_tasks():
		if existing_task != null and existing_task.is_source_valid():
			_attach_task_highlight(existing_task)
	_sync_selection_highlights()
	_wired = true


func teardown_community_work() -> void:
	_torn_down = true
	_clear_drag_state()
	_clear_all_selection_highlights()
	_clear_all_task_highlights()
	_disconnect_signals()
	_selection_model.teardown()
	_board = null
	_dispatcher = null
	_feedback = null
	_actions_hud = null


func authorize_selected_category(resource_id: StringName) -> Dictionary:
	_ensure_wired()
	if _board == null or not is_instance_valid(_board):
		return {
			"ok": false,
			"reason": "missing_board",
			"resource_id": resource_id,
			"created_tasks": [],
			"reauthorized_tasks": [],
			"existing_tasks": [],
		}
	if _is_community_economy_blocked():
		_show_feedback("Economia regional bloqueada: trabalho comunitário indisponível.")
		return {
			"ok": false,
			"reason": "economy_blocked",
			"resource_id": resource_id,
			"created_tasks": [],
			"reauthorized_tasks": [],
			"existing_tasks": [],
		}
	if not _supports_resource_id(resource_id):
		return {
			"ok": false,
			"reason": "unsupported_resource",
			"resource_id": resource_id,
			"created_tasks": [],
			"reauthorized_tasks": [],
			"existing_tasks": [],
		}

	var selected_sources: Array[ResourceSource] = _selection_model.get_selected_by_resource(resource_id)
	if selected_sources.is_empty():
		return {
			"ok": false,
			"reason": "no_selected_sources",
			"resource_id": resource_id,
			"created_tasks": [],
			"reauthorized_tasks": [],
			"existing_tasks": [],
		}

	var new_sources: Array[ResourceSource] = []
	var blocked_tasks: Array[WorkTask] = []
	var existing_tasks: Array[WorkTask] = []
	for src: ResourceSource in selected_sources:
		var active_task: WorkTask = _board.get_active_task_for_source(src)
		if active_task == null:
			new_sources.append(src)
		elif active_task.is_blocked_reauthorization():
			blocked_tasks.append(active_task)
		else:
			existing_tasks.append(active_task)

	var created_tasks: Array[WorkTask] = []
	var group_id: int = 0
	if not new_sources.is_empty():
		var group_res: Dictionary = _board.register_gather_group(new_sources, 0)
		if bool(group_res.get("ok", false)):
			group_id = int(group_res.get("group_id", 0))
			for task_val: Variant in (group_res.get("created_tasks", []) as Array):
				if task_val is WorkTask:
					created_tasks.append(task_val as WorkTask)

	var reauthorized_tasks: Array[WorkTask] = []
	for blocked: WorkTask in blocked_tasks:
		var reauth_res: Dictionary = _board.reauthorize_gather_task(blocked)
		if bool(reauth_res.get("ok", false)):
			reauthorized_tasks.append(blocked)

	var changed_total: int = created_tasks.size() + reauthorized_tasks.size()
	if changed_total == 0 and not existing_tasks.is_empty():
		_show_feedback(_already_authorized_feedback(resource_id, existing_tasks.size()))
	elif reauthorized_tasks.size() > 0 and created_tasks.is_empty():
		_show_feedback("Trabalho reautorizado para %d %s." % [
			reauthorized_tasks.size(),
			_source_noun_for_count(resource_id, reauthorized_tasks.size()),
		])
	elif changed_total > 1:
		_show_feedback("%d %s autorizadas para coleta." % [
			changed_total,
			_source_plural_noun(resource_id),
		])

	return {
		"ok": changed_total > 0 or not existing_tasks.is_empty(),
		"reason": "" if (changed_total > 0 or not existing_tasks.is_empty()) else "no_valid_sources",
		"resource_id": resource_id,
		"group_id": group_id,
		"created_tasks": created_tasks,
		"reauthorized_tasks": reauthorized_tasks,
		"existing_tasks": existing_tasks,
	}


func _is_community_economy_blocked() -> bool:
	return _use_provenance_economy and not _economy_admission_reason.is_empty()


func _ensure_wired() -> void:
	if _wired or _torn_down or not is_inside_tree():
		return
	var main := get_parent() as MainScene
	if main == null:
		return
	var board: CommunityWorkBoard = main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher: CommunityTaskDispatcher = main.get_node_or_null("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var feedback: AutonomousGatherFeedback = main.get_node_or_null("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var actions_hud: CommunitySelectionActionsHud = main.get_node_or_null("UiLayer/CommunitySelectionActionsHud") as CommunitySelectionActionsHud
	if board == null or dispatcher == null:
		return

	var test_map: TestMap = main.get_test_map()
	var world_nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var units_root: Node = main.get_node_or_null("Units")
	var region_id: StringName = &"default"
	if main.get_construction_manager() != null:
		region_id = main.get_construction_manager().get_region_id()
	var admission_reason: String = main.get_economy_admission_reason()

	board.configure(region_id, main.get_world_3d())
	dispatcher.configure(
		board,
		main.get_command_controller(),
		world_nav,
		units_root,
		main.get_camp_storage_zone(),
		main.get_settlement_inventory(),
		region_id,
		main.use_provenance_economy,
		admission_reason
	)
	configure_community_work(board, dispatcher, feedback, main.use_provenance_economy, admission_reason, actions_hud)
	if actions_hud != null and is_instance_valid(actions_hud):
		actions_hud.configure(_selection_model, board, main.use_provenance_economy, admission_reason)


func _disconnect_signals() -> void:
	if _selection_model != null:
		if _selection_model.selection_changed.is_connected(_on_source_selection_changed):
			_selection_model.selection_changed.disconnect(_on_source_selection_changed)
	if _board != null and is_instance_valid(_board):
		if _board.task_registered.is_connected(_on_task_registered):
			_board.task_registered.disconnect(_on_task_registered)
		if _board.task_closed.is_connected(_on_task_closed):
			_board.task_closed.disconnect(_on_task_closed)
	if _dispatcher != null and is_instance_valid(_dispatcher):
		if _dispatcher.task_feedback.is_connected(_on_dispatcher_feedback):
			_dispatcher.task_feedback.disconnect(_on_dispatcher_feedback)
	if _actions_hud != null and is_instance_valid(_actions_hud):
		if _actions_hud.category_authorize_requested.is_connected(_on_hud_category_authorize_requested):
			_actions_hud.category_authorize_requested.disconnect(_on_hud_category_authorize_requested)
	_wired = false


func _on_left_press_started_with_shift(_press_pos: Vector2, _shift_held: bool) -> void:
	_drag_mode = DragMode.NONE


func _on_drag_threshold_crossed(_start_pos: Vector2, _current_pos: Vector2, shift_held: bool) -> void:
	# Lock drag mode once at threshold using the Shift state of the event that crosses the threshold (D0 / F01).
	if multi_source_enabled and shift_held:
		_drag_mode = DragMode.SOURCE_BOX_ADD
	else:
		_drag_mode = DragMode.UNIT_BOX_RTS
	_resolve_dependencies()
	if _selection_box_overlay != null:
		_selection_box_overlay.set_box_style(_drag_mode == DragMode.SOURCE_BOX_ADD)


func _on_drag_cancelled() -> void:
	_clear_drag_state()


func _on_clear_selection_requested() -> void:
	_clear_drag_state()
	_selection_model.clear()


func _clear_drag_state() -> void:
	_drag_mode = DragMode.NONE


func _handle_left_click(screen_pos: Vector2, shift_held: bool) -> void:
	_clear_drag_state()
	_ensure_wired()
	var pick: PickResult = pick_at_screen_pos(screen_pos)
	if pick.is_resource_source() and _supports_resource_id(pick.resource_source.get_resource_id()):
		construction_site_picked.emit(null)
		var source: ResourceSource = pick.resource_source
		var res_id: StringName = source.get_resource_id()
		if source.is_depleted():
			_show_feedback(_depleted_feedback(res_id))
			return
		if not _selection_model.is_source_eligible(source):
			_show_feedback("Fonte indisponível.")
			return

		if multi_source_enabled and shift_held:
			_selection_model.toggle_source(source)
		else:
			# D1-B: clicking an already selected source without Shift deselects ONLY that source.
			if _selection_model.is_selected(source):
				_selection_model.deselect_source(source)
			else:
				_selection_model.select_single(source)
		return

	if (pick.is_ground() or pick.is_none()) and not shift_held:
		_selection_model.clear()
	super._handle_left_click(screen_pos, shift_held)


func _handle_box_selection(start_pos: Vector2, end_pos: Vector2, shift_held: bool) -> void:
	var active_mode: DragMode = _drag_mode
	if active_mode == DragMode.NONE:
		active_mode = DragMode.SOURCE_BOX_ADD if (multi_source_enabled and shift_held) else DragMode.UNIT_BOX_RTS
	_clear_drag_state()

	if active_mode == DragMode.SOURCE_BOX_ADD:
		_handle_source_box_selection(start_pos, end_pos)
		return

	# Traditional RTS unit box selection (never starts source selection without Shift).
	var unit_shift: bool = shift_held if not multi_source_enabled else false
	super._handle_box_selection(start_pos, end_pos, unit_shift)


func _handle_source_box_selection(start_pos: Vector2, end_pos: Vector2) -> void:
	_ensure_wired()
	_resolve_dependencies()
	if _board == null or not is_instance_valid(_board) or not _can_pick():
		return

	var camera: Camera3D = _camera_rig.get_camera()
	var viewport: Viewport = get_viewport()
	var viewport_rect: Rect2 = viewport.get_visible_rect() if viewport != null else Rect2()
	var tree: SceneTree = get_tree()
	var candidates: Array = tree.get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES) if tree != null else []
	var box_rect: Rect2 = SelectionBoxMath.normalize_rect(start_pos, end_pos)
	var raw_boxed: Array[ResourceSource] = SelectionBoxMath.collect_sources_in_box(
		camera,
		candidates,
		box_rect,
		viewport_rect,
		&"",
		true
	)

	var eligible_boxed: Array[ResourceSource] = []
	for candidate_src: ResourceSource in raw_boxed:
		if _supports_resource_id(candidate_src.get_resource_id()) and _selection_model.is_source_eligible(candidate_src):
			eligible_boxed.append(candidate_src)

	if eligible_boxed.is_empty():
		return

	construction_site_picked.emit(null)
	_selection_model.add_sources(eligible_boxed)


func _supports_resource_id(resource_id: StringName) -> bool:
	return supported_resource_ids.has(String(resource_id))


func _on_hud_category_authorize_requested(resource_id: StringName) -> void:
	authorize_selected_category(resource_id)


func _on_source_selection_changed() -> void:
	_sync_selection_highlights()


func _on_task_registered(task: WorkTask) -> void:
	if task == null or not task.is_source_valid():
		return
	_attach_task_highlight(task)


func _on_task_closed(task: WorkTask) -> void:
	if task == null:
		return
	_remove_task_highlight(task.task_id)


func _on_dispatcher_feedback(message: String) -> void:
	_show_feedback(message)


func _show_feedback(message: String) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.show_message(message)


func _sync_selection_highlights() -> void:
	var active_ids: Dictionary = {}
	for src: ResourceSource in _selection_model.get_selected_sources():
		var sid: int = src.get_instance_id()
		active_ids[sid] = true
		if not _selection_highlights.has(sid):
			_attach_selection_highlight(src, sid)

	var stale_ids: Array[int] = []
	for sid_key: Variant in _selection_highlights.keys():
		var sid: int = int(sid_key)
		if not active_ids.has(sid):
			stale_ids.append(sid)
	for sid: int in stale_ids:
		_remove_selection_highlight(sid)


func _attach_selection_highlight(source: ResourceSource, sid: int) -> void:
	if source == null or not is_instance_valid(source) or not source.is_inside_tree():
		return
	_ensure_shared_selection_ring_mesh()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "SourceSelectionRing_%d" % sid
	mesh_inst.mesh = _shared_selection_ring_mesh
	mesh_inst.material_override = _get_shared_selection_ring_material()
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = Vector3(0.0, 0.06, 0.0)
	var radius_scale: float = maxf(source.get_solid_radius() + 0.65, 1.15)
	mesh_inst.scale = Vector3(radius_scale, 1.0, radius_scale)
	source.add_child(mesh_inst)
	_selection_highlights[sid] = weakref(mesh_inst)


func _remove_selection_highlight(sid: int) -> void:
	if not _selection_highlights.has(sid):
		return
	var ref: WeakRef = _selection_highlights[sid] as WeakRef
	_selection_highlights.erase(sid)
	var obj: Object = ref.get_ref() if ref != null else null
	if obj != null and is_instance_valid(obj) and obj is MeshInstance3D:
		(obj as MeshInstance3D).queue_free()


func _clear_all_selection_highlights() -> void:
	for key: Variant in _selection_highlights.keys():
		var ref: WeakRef = _selection_highlights[key] as WeakRef
		var obj: Object = ref.get_ref() if ref != null else null
		if obj != null and is_instance_valid(obj) and obj is MeshInstance3D:
			(obj as MeshInstance3D).queue_free()
	_selection_highlights.clear()


func _attach_task_highlight(task: WorkTask) -> void:
	if _task_highlights.has(task.task_id):
		return
	_ensure_shared_ring_mesh()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "AutoGatherTaskRing_%d" % task.task_id
	mesh_inst.mesh = _shared_ring_mesh
	mesh_inst.material_override = _get_shared_ring_material(task.resource_id)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = Vector3(0.0, 0.05, 0.0)
	var radius_scale: float = maxf(task.source.get_solid_radius() + 0.65, 1.15)
	mesh_inst.scale = Vector3(radius_scale, 1.0, radius_scale)
	task.source.add_child(mesh_inst)
	_task_highlights[task.task_id] = weakref(mesh_inst)


func _remove_task_highlight(task_id: int) -> void:
	if not _task_highlights.has(task_id):
		return
	var ref: WeakRef = _task_highlights[task_id] as WeakRef
	_task_highlights.erase(task_id)
	var obj: Object = ref.get_ref() if ref != null else null
	if obj != null and is_instance_valid(obj) and obj is MeshInstance3D:
		(obj as MeshInstance3D).queue_free()


func _clear_all_task_highlights() -> void:
	for key: Variant in _task_highlights.keys():
		var ref: WeakRef = _task_highlights[key] as WeakRef
		var obj: Object = ref.get_ref() if ref != null else null
		if obj != null and is_instance_valid(obj) and obj is MeshInstance3D:
			(obj as MeshInstance3D).queue_free()
	_task_highlights.clear()


func _get_shared_selection_ring_material() -> StandardMaterial3D:
	if _shared_selection_ring_material != null:
		return _shared_selection_ring_material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SELECTION_RING_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shared_selection_ring_material = mat
	return mat


func _get_shared_ring_material(resource_id: StringName) -> StandardMaterial3D:
	if _shared_ring_materials.has(resource_id):
		return _shared_ring_materials[resource_id] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	match resource_id:
		&"stone":
			mat.albedo_color = RING_COLOR_STONE
		&"food":
			mat.albedo_color = RING_COLOR_FOOD
		_:
			mat.albedo_color = RING_COLOR_WOOD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shared_ring_materials[resource_id] = mat
	return mat


func _ensure_shared_ring_mesh() -> void:
	if _shared_ring_mesh != null:
		return
	_shared_ring_mesh = _build_ring_mesh(RING_INNER_RADIUS, RING_OUTER_RADIUS)


func _ensure_shared_selection_ring_mesh() -> void:
	if _shared_selection_ring_mesh != null:
		return
	_shared_selection_ring_mesh = _build_ring_mesh(SELECTION_RING_INNER_RADIUS, SELECTION_RING_OUTER_RADIUS)


static func _build_ring_mesh(inner_radius: float, outer_radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for step: int in range(RING_SEGMENTS + 1):
		var angle: float = (float(step) / float(RING_SEGMENTS)) * TAU
		var c: float = cos(angle)
		var s: float = sin(angle)
		vertices.append(Vector3(c * inner_radius, 0.0, s * inner_radius))
		vertices.append(Vector3(c * outer_radius, 0.0, s * outer_radius))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for step: int in range(RING_SEGMENTS):
		var i0: int = step * 2
		var i1: int = i0 + 1
		var i2: int = i0 + 2
		var i3: int = i0 + 3
		indices.append_array([i0, i2, i1, i1, i2, i3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _depleted_feedback(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "Rocha esgotada."
		&"food":
			return "Arbusto esgotado."
		_:
			return "Árvore esgotada."


static func _already_authorized_feedback(resource_id: StringName, count: int) -> String:
	if count > 1:
		return "%d %s já estavam autorizadas." % [count, _source_plural_noun(resource_id)]
	match resource_id:
		&"stone":
			return "Tarefa já autorizada para esta rocha."
		&"food":
			return "Tarefa já autorizada para este arbusto."
		_:
			return "Tarefa já autorizada para esta árvore."


static func _source_noun_for_count(resource_id: StringName, count: int) -> String:
	if count != 1:
		return _source_plural_noun(resource_id)
	match resource_id:
		&"stone":
			return "rocha"
		&"food":
			return "arbusto"
		_:
			return "árvore"


static func _source_plural_noun(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "rochas"
		&"food":
			return "arbustos"
		_:
			return "árvores"
