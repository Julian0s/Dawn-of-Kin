class_name TemporaryTestWorkersController
extends RefCounted
## Test/development-only spawner and safe remover for temporary C4 workers (Worker3 and Worker4).
## Strictly decoupled from campaign/narrative population, recruitment, or reproduction systems.

const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const WORKER_3_ID: StringName = &"test_worker_3"
const WORKER_4_ID: StringName = &"test_worker_4"
const MIN_UNIT_CLEARANCE_XZ: float = 1.25
const SPAWN_OFFSETS_NEAR_CAMP: Array[Vector3] = [
	Vector3(-4.2, 0.0, 1.5),
	Vector3(4.2, 0.0, 1.5),
	Vector3(-4.2, 0.0, -0.5),
	Vector3(4.2, 0.0, -0.5),
	Vector3(-2.0, 0.0, 4.2),
	Vector3(2.0, 0.0, 4.2),
	Vector3(0.0, 0.0, 4.4),
	Vector3(-4.5, 0.0, 3.5),
	Vector3(4.5, 0.0, 3.5),
]

var _units_root: Node3D = null
var _world_navigation: WorldNavigation = null
var _camp_storage_zone: CampStorageZone = null
var _selection_manager: SelectionManager = null
var _construction_sites_root: Node3D = null
var _spawned_workers: Array[Unit] = []


func configure(
	units_root: Node3D,
	world_navigation: WorldNavigation,
	camp_storage_zone: CampStorageZone = null,
	selection_manager: SelectionManager = null,
	construction_sites_root: Node3D = null
) -> void:
	_units_root = units_root
	_world_navigation = world_navigation
	_camp_storage_zone = camp_storage_zone
	_selection_manager = selection_manager
	_construction_sites_root = construction_sites_root


func get_temporary_workers() -> Array[Unit]:
	var active: Array[Unit] = []
	for u: Unit in _spawned_workers:
		if u != null and is_instance_valid(u) and u.is_inside_tree() and not u.is_queued_for_deletion():
			active.append(u)
	_spawned_workers = active

	if _units_root != null and is_instance_valid(_units_root):
		for child: Node in _units_root.get_children():
			if not (child is Unit):
				continue
			var unit: Unit = child as Unit
			if unit.is_queued_for_deletion():
				continue
			var cid: StringName = unit.get_character_id()
			if (cid == WORKER_3_ID or cid == WORKER_4_ID or unit.name == &"Worker3" or unit.name == &"Worker4") and not active.has(unit):
				active.append(unit)
				_spawned_workers.append(unit)
	return active


func has_temporary_workers() -> bool:
	return not get_temporary_workers().is_empty()


func spawn_temporary_workers() -> Dictionary:
	if _units_root == null or not is_instance_valid(_units_root) or not _units_root.is_inside_tree():
		return {
			"ok": false,
			"reason": "missing_units_root",
			"message": "Raiz de unidades indisponível na cena.",
			"workers": [],
		}
	if has_temporary_workers():
		return {
			"ok": false,
			"reason": "already_exists",
			"message": "Worker3 e Worker4 já foram adicionados.",
			"workers": get_temporary_workers(),
		}

	var camp_center: Vector3 = _camp_storage_zone.global_position if (_camp_storage_zone != null and is_instance_valid(_camp_storage_zone)) else Vector3(0.0, 0.0, 0.5)
	var reserved_positions: Array[Vector3] = []

	var pos_3: Vector3 = _find_valid_spawn_position(camp_center, reserved_positions)
	if not pos_3.is_finite():
		return {
			"ok": false,
			"reason": "no_spawn_space",
			"message": "Não há posição navegável livre próxima ao acampamento para Worker3.",
			"workers": [],
		}
	reserved_positions.append(pos_3)

	var pos_4: Vector3 = _find_valid_spawn_position(camp_center, reserved_positions)
	if not pos_4.is_finite():
		return {
			"ok": false,
			"reason": "no_spawn_space",
			"message": "Não há posição navegável livre próxima ao acampamento para Worker4.",
			"workers": [],
		}

	var def_3 := _create_worker_definition(
		WORKER_3_ID,
		"Worker3",
		CharacterDefinition.SilhouetteKind.EXPLORER_PACK,
		Color(0.22, 0.72, 0.42, 1.0),
		Color(0.16, 0.24, 0.18, 1.0)
	)
	var def_4 := _create_worker_definition(
		WORKER_4_ID,
		"Worker4",
		CharacterDefinition.SilhouetteKind.CLOAK_SCOUT,
		Color(0.78, 0.62, 0.18, 1.0),
		Color(0.28, 0.22, 0.14, 1.0)
	)

	var w3: Unit = _instantiate_worker("Worker3", def_3, pos_3)
	var w4: Unit = _instantiate_worker("Worker4", def_4, pos_4)
	_spawned_workers = [w3, w4]

	return {
		"ok": true,
		"reason": "",
		"message": "Worker3 e Worker4 adicionados próximo ao acampamento.",
		"workers": [w3, w4],
	}


func can_remove_temporary_workers() -> Dictionary:
	var workers: Array[Unit] = get_temporary_workers()
	if workers.is_empty():
		return {
			"can_remove": false,
			"reason": "none_present",
			"message": "Nenhum trabalhador temporário ativo para remover.",
		}

	for worker: Unit in workers:
		var carry: UnitCarryLoad = worker.get_carry_load()
		if carry != null and not carry.is_empty():
			var total_units: int = 0
			for amt: Variant in carry.get_all_amounts().values():
				total_units += int(amt)
			return {
				"can_remove": false,
				"reason": "cargo_in_backpack",
				"message": "Remoção bloqueada: %s possui carga na mochila (%d un). Entregue ou descarregue antes de remover." % [
					worker.name,
					total_units,
				],
			}

		if _construction_sites_root != null and is_instance_valid(_construction_sites_root):
			for child: Node in _construction_sites_root.get_children():
				if not (child is ConstructionSite):
					continue
				var site: ConstructionSite = child as ConstructionSite
				if not is_instance_valid(site) or not site.is_valid():
					continue
				var claim: Dictionary = site.get_transit_claim_for_unit(worker)
				if not claim.is_empty():
					return {
						"can_remove": false,
						"reason": "transit_claim_active",
						"message": "Remoção bloqueada: %s possui reserva em trânsito no canteiro %s." % [
							worker.name,
							String(site.site_id),
						],
					}

	return {
		"can_remove": true,
		"reason": "",
		"message": "",
	}


func remove_temporary_workers_safely() -> Dictionary:
	var check: Dictionary = can_remove_temporary_workers()
	if not bool(check.get("can_remove", false)):
		return {
			"ok": false,
			"reason": str(check.get("reason", "")),
			"message": str(check.get("message", "Não foi possível remover trabalhadores temporários.")),
		}

	var workers: Array[Unit] = get_temporary_workers()
	for worker: Unit in workers:
		if _selection_manager != null and is_instance_valid(_selection_manager):
			_selection_manager.remove_unit(worker)
		worker.cancel_current_order("temporary_worker_removed")
		if worker.get_parent() == _units_root:
			_units_root.remove_child(worker)
		worker.queue_free()

	_spawned_workers.clear()
	return {
		"ok": true,
		"reason": "",
		"message": "Worker3 e Worker4 removidos com segurança.",
	}


func _instantiate_worker(node_name: String, def: CharacterDefinition, world_pos: Vector3) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.name = node_name
	unit.definition = def
	if _world_navigation != null:
		unit.set_world_navigation(_world_navigation)
	_units_root.add_child(unit)
	unit.global_position = world_pos
	unit.apply_definition(def)
	return unit


func _create_worker_definition(
	id: StringName,
	display_name_text: String,
	silhouette: CharacterDefinition.SilhouetteKind,
	primary: Color,
	secondary: Color
) -> CharacterDefinition:
	var def := CharacterDefinition.new()
	def.character_id = id
	def.display_name = display_name_text
	def.move_speed = 4.8
	def.work_approach_speed = 2.5
	def.max_load_speed_multiplier = 0.60
	def.turn_rate = 10.0
	def.silhouette_kind = silhouette
	def.primary_color = primary
	def.secondary_color = secondary
	def.base_carry_capacity = 20
	return def


func _find_valid_spawn_position(camp_center: Vector3, reserved_positions: Array[Vector3]) -> Vector3:
	for offset: Vector3 in SPAWN_OFFSETS_NEAR_CAMP:
		var candidate := Vector3(camp_center.x + offset.x, camp_center.y, camp_center.z + offset.z)
		var validated: Vector3 = _validate_spawn_candidate(candidate, camp_center, reserved_positions)
		if validated.is_finite():
			return validated
	return Vector3(INF, INF, INF)


func _validate_spawn_candidate(
	candidate: Vector3,
	camp_center: Vector3,
	reserved_positions: Array[Vector3]
) -> Vector3:
	var pos: Vector3 = candidate
	if _world_navigation != null and is_instance_valid(_world_navigation) and _world_navigation.is_navigation_ready():
		var snapped: Vector3 = _world_navigation.snap_to_navmesh(candidate)
		if not snapped.is_finite():
			return Vector3(INF, INF, INF)
		var path_res: WorldNavigation.PathResult = _world_navigation.find_path(snapped, camp_center)
		if not path_res.reachable:
			return Vector3(INF, INF, INF)
		pos = Vector3(snapped.x, camp_center.y, snapped.z)

	var ground_y: float = _sample_terrain_y(pos)
	if is_finite(ground_y):
		if absf(ground_y - camp_center.y) > 0.85:
			return Vector3(INF, INF, INF)
		pos.y = ground_y

	if _units_root != null and is_instance_valid(_units_root):
		for child: Node in _units_root.get_children():
			if not (child is Unit):
				continue
			var existing: Unit = child as Unit
			if existing.is_queued_for_deletion():
				continue
			var d_xz: float = Vector2(existing.global_position.x - pos.x, existing.global_position.z - pos.z).length()
			if d_xz < MIN_UNIT_CLEARANCE_XZ:
				return Vector3(INF, INF, INF)

	for used: Vector3 in reserved_positions:
		var d_used: float = Vector2(used.x - pos.x, used.z - pos.z).length()
		if d_used < MIN_UNIT_CLEARANCE_XZ:
			return Vector3(INF, INF, INF)

	if _construction_sites_root != null and is_instance_valid(_construction_sites_root):
		for child: Node in _construction_sites_root.get_children():
			if not (child is ConstructionSite):
				continue
			var site: ConstructionSite = child as ConstructionSite
			if not is_instance_valid(site) or not site.is_valid():
				continue
			if site.definition != null:
				var half_ext: Vector2 = site.definition.footprint_size * 0.5 + Vector2(0.8, 0.8)
				if absf(pos.x - site.global_position.x) <= half_ext.x and absf(pos.z - site.global_position.z) <= half_ext.y:
					return Vector3(INF, INF, INF)

	return pos


func _sample_terrain_y(world_pos: Vector3) -> float:
	if _units_root == null or not _units_root.is_inside_tree():
		return INF
	var world_3d: World3D = _units_root.get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return INF
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(world_pos.x, world_pos.y + 4.0, world_pos.z),
		Vector3(world_pos.x, world_pos.y - 4.0, world_pos.z),
		CollisionLayers.MASK_TERRAIN
	)
	var hit: Dictionary = world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	return (hit["position"] as Vector3).y
