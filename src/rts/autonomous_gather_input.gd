class_name AutonomousGatherInput
extends RtsInputController
## Isolated RUX-1 input adapter for automatic single-tree wood gathering.
## Installed only in tests/visual/rux_1_auto_gather.tscn; keeps MainScene and UX-1 untouched.

const RING_SEGMENTS: int = 24
const RING_INNER_RADIUS: float = 0.72
const RING_OUTER_RADIUS: float = 0.90
const RING_COLOR: Color = Color(0.55, 0.86, 0.42, 0.85)

var _board: CommunityWorkBoard = null
var _dispatcher: CommunityTaskDispatcher = null
var _feedback: AutonomousGatherFeedback = null
var _wired: bool = false
var _shared_ring_mesh: ArrayMesh = null
var _shared_ring_material: StandardMaterial3D = null
var _task_highlights: Dictionary = {}


func _ready() -> void:
	super._ready()
	call_deferred("_ensure_wired")


func _exit_tree() -> void:
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


func _handle_left_click(screen_pos: Vector2, shift_held: bool) -> void:
	_ensure_wired()
	var pick: PickResult = pick_at_screen_pos(screen_pos)
	if pick.is_resource_source() and pick.resource_source.get_resource_id() == &"wood":
		construction_site_picked.emit(null)
		if _board == null:
			return
		var res: Dictionary = _board.register_wood_gather_task(pick.resource_source)
		if not bool(res.get("ok", false)):
			var reason: String = String(res.get("reason", ""))
			if reason == "source_depleted":
				_show_feedback("Árvore esgotada.")
			else:
				_show_feedback("Fonte indisponível.")
		elif not bool(res.get("created", false)):
			_show_feedback("Tarefa já registrada para esta árvore.")
		return
	super._handle_left_click(screen_pos, shift_held)


func _on_task_registered(task: WorkTask) -> void:
	if task == null or not task.is_source_valid():
		return
	_attach_highlight(task)


func _on_task_closed(task: WorkTask) -> void:
	if task == null:
		return
	_remove_highlight(task.task_id)


func _on_dispatcher_feedback(message: String) -> void:
	_show_feedback(message)


func _show_feedback(message: String) -> void:
	if _feedback != null and is_instance_valid(_feedback):
		_feedback.show_message(message)


func _attach_highlight(task: WorkTask) -> void:
	if _task_highlights.has(task.task_id):
		return
	_ensure_shared_ring_resources()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Rux1TaskRing_%d" % task.task_id
	mesh_inst.mesh = _shared_ring_mesh
	mesh_inst.material_override = _shared_ring_material
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = Vector3(0.0, 0.05, 0.0)
	var radius_scale: float = maxf(task.source.get_solid_radius() + 0.65, 1.15)
	mesh_inst.scale = Vector3(radius_scale, 1.0, radius_scale)
	task.source.add_child(mesh_inst)
	_task_highlights[task.task_id] = mesh_inst


func _remove_highlight(task_id: int) -> void:
	if not _task_highlights.has(task_id):
		return
	var mesh_inst: MeshInstance3D = _task_highlights[task_id] as MeshInstance3D
	_task_highlights.erase(task_id)
	if mesh_inst != null and is_instance_valid(mesh_inst):
		mesh_inst.queue_free()


func _clear_all_highlights() -> void:
	for key: Variant in _task_highlights.keys():
		var mesh_inst: MeshInstance3D = _task_highlights[key] as MeshInstance3D
		if mesh_inst != null and is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	_task_highlights.clear()


func _ensure_shared_ring_resources() -> void:
	if _shared_ring_material == null:
		_shared_ring_material = StandardMaterial3D.new()
		_shared_ring_material.albedo_color = RING_COLOR
		_shared_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shared_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	if _shared_ring_mesh == null:
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
