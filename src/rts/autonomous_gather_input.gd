class_name AutonomousGatherInput
extends RtsInputController
## Isolated RUX-1/RUX-2A/RUX-2B input adapter for automatic single-source and multi-source gathering.
## - RUX-1 (rux_1_auto_gather.tscn): supported_resource_ids=["wood"], multi_source_enabled=false.
## - RUX-2A (rux_2a_auto_resources.tscn): supported_resource_ids=["wood","stone","food"], multi_source_enabled=false.
## - RUX-2B (rux_2b_multi_source_selection.tscn): supported_resource_ids=["wood","stone","food"], multi_source_enabled=true.

const RING_SEGMENTS: int = 24
const RING_INNER_RADIUS: float = 0.72
const RING_OUTER_RADIUS: float = 0.90
const RING_COLOR_WOOD: Color = Color(0.55, 0.86, 0.42, 0.85)
const RING_COLOR_STONE: Color = Color(0.66, 0.78, 0.90, 0.85)
const RING_COLOR_FOOD: Color = Color(0.92, 0.66, 0.34, 0.85)

@export var supported_resource_ids: PackedStringArray = PackedStringArray(["wood"])
@export var multi_source_enabled: bool = false

var _board: CommunityWorkBoard = null
var _dispatcher: CommunityTaskDispatcher = null
var _feedback: AutonomousGatherFeedback = null
var _wired: bool = false
var _shared_ring_mesh: ArrayMesh = null
var _shared_ring_materials: Dictionary = {}
var _task_highlights: Dictionary = {}

var _drag_origin_source: ResourceSource = null
var _drag_origin_resource_id: StringName = &""
var _active_group_id: int = 0
var _active_group_resource_id: StringName = &""


func _ready() -> void:
	super._ready()
	call_deferred("_ensure_wired")


func _exit_tree() -> void:
	_clear_drag_origin()
	_clear_all_highlights()
	_disconnect_signals()
	super._exit_tree()


func _ensure_wired() -> void:
	if _wired:
		return
	var main := get_parent() as MainScene
	if main == null:
		return
	_board = main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	_dispatcher = main.get_node_or_null("CommunityTaskDispatcher") as CommunityTaskDispatcher
	_feedback = main.get_node_or_null("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	if _board == null or _dispatcher == null:
		return

	var test_map: TestMap = main.get_test_map()
	var world_nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var units_root: Node = main.get_node_or_null("Units")
	var region_id: StringName = &"default"
	if main.get_construction_manager() != null:
		region_id = main.get_construction_manager().get_region_id()

	_board.configure(region_id)
	_dispatcher.configure(
		_board,
		main.get_command_controller(),
		world_nav,
		units_root,
		main.get_camp_storage_zone(),
		main.get_settlement_inventory(),
		region_id,
		main.use_provenance_economy
	)

	if not _board.task_registered.is_connected(_on_task_registered):
		_board.task_registered.connect(_on_task_registered)
	if not _board.task_closed.is_connected(_on_task_closed):
		_board.task_closed.connect(_on_task_closed)
	if not _dispatcher.task_feedback.is_connected(_on_dispatcher_feedback):
		_dispatcher.task_feedback.connect(_on_dispatcher_feedback)

	_wired = true


func _disconnect_signals() -> void:
	if _board != null and is_instance_valid(_board):
		if _board.task_registered.is_connected(_on_task_registered):
			_board.task_registered.disconnect(_on_task_registered)
		if _board.task_closed.is_connected(_on_task_closed):
			_board.task_closed.disconnect(_on_task_closed)
	if _dispatcher != null and is_instance_valid(_dispatcher):
		if _dispatcher.task_feedback.is_connected(_on_dispatcher_feedback):
			_dispatcher.task_feedback.disconnect(_on_dispatcher_feedback)
	_wired = false


func _on_left_press_started(press_pos: Vector2) -> void:
	_clear_drag_origin()
	if not multi_source_enabled:
		return
	_ensure_wired()
	var pick: PickResult = pick_at_screen_pos(press_pos)
	if pick.is_resource_source() and _supports_resource_id(pick.resource_source.get_resource_id()):
		_drag_origin_source = pick.resource_source
		_drag_origin_resource_id = pick.resource_source.get_resource_id()


func _on_drag_cancelled() -> void:
	_clear_drag_origin()


func _clear_drag_origin() -> void:
	_drag_origin_source = null
	_drag_origin_resource_id = &""


func _handle_left_click(screen_pos: Vector2, shift_held: bool) -> void:
	_clear_drag_origin()
	_ensure_wired()
	var pick: PickResult = pick_at_screen_pos(screen_pos)
	if pick.is_resource_source() and _supports_resource_id(pick.resource_source.get_resource_id()):
		construction_site_picked.emit(null)
		if _board == null:
			return
		var source: ResourceSource = pick.resource_source
		var res_id: StringName = source.get_resource_id()
		var target_group_id: int = 0

		if multi_source_enabled and shift_held:
			if _active_group_id > 0 and _board.has_active_tasks_in_group(_active_group_id):
				if res_id != _active_group_resource_id:
					_show_feedback("Seleção atual é de %s · clique sem Shift para iniciar outra tarefa." % _resource_noun(_active_group_resource_id))
					return
				target_group_id = _active_group_id

		var res: Dictionary = _board.register_gather_task(source, target_group_id)
		if not bool(res.get("ok", false)):
			var reason: String = String(res.get("reason", ""))
			if reason == "source_depleted":
				_show_feedback(_depleted_feedback(res_id))
			else:
				_show_feedback("Fonte indisponível.")
			return

		var task: WorkTask = res.get("task") as WorkTask
		if multi_source_enabled and task != null:
			_active_group_id = task.group_id
			_active_group_resource_id = task.resource_id

		if not bool(res.get("created", false)):
			if task != null and task.is_blocked_reauthorization():
				_show_feedback("Tarefa aguardando nova autorização.")
			elif multi_source_enabled and shift_held:
				_show_feedback("Fonte já está selecionada.")
			else:
				_show_feedback(_already_registered_feedback(res_id))
		return

	if not shift_held:
		_active_group_id = 0
		_active_group_resource_id = &""
	super._handle_left_click(screen_pos, shift_held)


func _handle_box_selection(start_pos: Vector2, end_pos: Vector2, shift_held: bool) -> void:
	if multi_source_enabled and _drag_origin_source != null and is_instance_valid(_drag_origin_source):
		var origin_source: ResourceSource = _drag_origin_source
		var origin_res_id: StringName = _drag_origin_resource_id
		_clear_drag_origin()
		_handle_source_box_selection(origin_source, origin_res_id, start_pos, end_pos, shift_held)
		return

	_clear_drag_origin()
	super._handle_box_selection(start_pos, end_pos, shift_held)


func _handle_source_box_selection(
	origin_source: ResourceSource,
	origin_res_id: StringName,
	start_pos: Vector2,
	end_pos: Vector2,
	shift_held: bool
) -> void:
	_ensure_wired()
	_resolve_dependencies()
	if _board == null or not _can_pick():
		return

	var camera: Camera3D = _camera_rig.get_camera()
	var viewport: Viewport = get_viewport()
	var viewport_rect: Rect2 = viewport.get_visible_rect() if viewport != null else Rect2()
	var tree: SceneTree = get_tree()
	var candidates: Array = tree.get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES) if tree != null else []
	var box_rect: Rect2 = SelectionBoxMath.normalize_rect(start_pos, end_pos)
	var boxed_sources: Array[ResourceSource] = SelectionBoxMath.collect_sources_in_box(
		camera,
		candidates,
		box_rect,
		viewport_rect,
		origin_res_id,
		true
	)

	if (
		is_instance_valid(origin_source)
		and origin_source.is_inside_tree()
		and not origin_source.is_depleted()
		and origin_source.is_available()
		and not boxed_sources.has(origin_source)
	):
		boxed_sources.insert(0, origin_source)

	if boxed_sources.is_empty():
		_show_feedback(_depleted_feedback(origin_res_id))
		return

	var target_group_id: int = 0
	if shift_held and _active_group_id > 0 and _board.has_active_tasks_in_group(_active_group_id):
		if _active_group_resource_id == origin_res_id:
			target_group_id = _active_group_id

	construction_site_picked.emit(null)
	var group_res: Dictionary = _board.register_gather_group(boxed_sources, target_group_id)
	if not bool(group_res.get("ok", false)):
		_show_feedback("Nenhuma fonte disponível na seleção.")
		return

	_active_group_id = int(group_res.get("group_id", 0))
	_active_group_resource_id = origin_res_id

	var created_count: int = (group_res.get("created_tasks", []) as Array).size()
	var existing_count: int = (group_res.get("existing_tasks", []) as Array).size()
	var total_count: int = created_count + existing_count
	if created_count == 0 and existing_count > 0:
		_show_feedback("Fontes já estavam selecionadas.")
	elif total_count > 1:
		_show_feedback("%d %s marcadas." % [total_count, _source_plural_noun(origin_res_id)])


func _supports_resource_id(resource_id: StringName) -> bool:
	return supported_resource_ids.has(String(resource_id))


func _on_task_registered(task: WorkTask) -> void:
	if task == null or not task.is_source_valid():
		return
	_attach_highlight(task)


func _on_task_closed(task: WorkTask) -> void:
	if task == null:
		return
	_remove_highlight(task.task_id)
	if _active_group_id > 0 and task.group_id == _active_group_id and _board != null and not _board.has_active_tasks_in_group(_active_group_id):
		_active_group_id = 0
		_active_group_resource_id = &""


func _on_dispatcher_feedback(message: String) -> void:
	_show_feedback(message)


func _show_feedback(message: String) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.show_message(message)


func _attach_highlight(task: WorkTask) -> void:
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


func _remove_highlight(task_id: int) -> void:
	if not _task_highlights.has(task_id):
		return
	var ref: WeakRef = _task_highlights[task_id] as WeakRef
	_task_highlights.erase(task_id)
	var obj: Object = ref.get_ref() if ref != null else null
	if obj != null and is_instance_valid(obj) and obj is MeshInstance3D:
		(obj as MeshInstance3D).queue_free()


func _clear_all_highlights() -> void:
	for key: Variant in _task_highlights.keys():
		var ref: WeakRef = _task_highlights[key] as WeakRef
		var obj: Object = ref.get_ref() if ref != null else null
		if obj != null and is_instance_valid(obj) and obj is MeshInstance3D:
			(obj as MeshInstance3D).queue_free()
	_task_highlights.clear()


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
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for step: int in range(RING_SEGMENTS + 1):
		var angle: float = (float(step) / float(RING_SEGMENTS)) * TAU
		var c: float = cos(angle)
		var s: float = sin(angle)
		vertices.append(Vector3(c * RING_INNER_RADIUS, 0.0, s * RING_INNER_RADIUS))
		vertices.append(Vector3(c * RING_OUTER_RADIUS, 0.0, s * RING_OUTER_RADIUS))
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
	_shared_ring_mesh = ArrayMesh.new()
	_shared_ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _depleted_feedback(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "Rocha esgotada."
		&"food":
			return "Arbusto esgotado."
		_:
			return "Árvore esgotada."


static func _already_registered_feedback(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "Tarefa já registrada para esta rocha."
		&"food":
			return "Tarefa já registrada para este arbusto."
		_:
			return "Tarefa já registrada para esta árvore."


static func _resource_noun(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "pedra"
		&"food":
			return "alimentos"
		_:
			return "madeira"


static func _source_plural_noun(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "rochas"
		&"food":
			return "arbustos"
		_:
			return "árvores"
