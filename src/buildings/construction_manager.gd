class_name ConstructionManager
extends Node
## Per-region / settlement coordinator responsible for creating ConstructionSite nodes
## with atomic resource reservation, overlap/duplicate protection, and rollback on failure.

signal site_created(site: ConstructionSite)
signal site_creation_rejected(
	reason: String,
	message: String,
	definition: BuildingDefinition,
	world_position: Vector3
)

var _sites_root: Node3D = null
var _inventory: SettlementInventory = null
var _resource_defs: Dictionary = {}
var _camp_zone: CampStorageZone = null
var _world_navigation: WorldNavigation = null
var _region_id: StringName = &"default"
var _next_site_seq: int = 1
var _sites: Array[ConstructionSite] = []
var site_creator_override: Callable = Callable()
var building_creator_override: Callable = Callable()
var _buildings_root: Node3D = null
var _completed_buildings: Array[BuildingInstance] = []
var _queued_completions: Dictionary = {}
var _completion_in_progress: bool = false
var _retry_timers: Dictionary = {}


func configure(
	p_sites_root: Node3D,
	p_inventory: SettlementInventory,
	p_resource_defs: Dictionary = {},
	p_camp_zone: CampStorageZone = null,
	p_world_navigation: WorldNavigation = null,
	p_region_id: StringName = &"default"
) -> void:
	_sites_root = p_sites_root
	_inventory = p_inventory
	_resource_defs = p_resource_defs.duplicate()
	_camp_zone = p_camp_zone
	_world_navigation = p_world_navigation
	_region_id = p_region_id if not p_region_id.is_empty() else &"default"
	if is_instance_valid(_sites_root) and _sites_root.is_inside_tree():
		_buildings_root = Node3D.new()
		_buildings_root.name = "CompletedBuildings"
		_buildings_root.set_meta(&"region_id", _region_id)
		_sites_root.get_parent().add_child(_buildings_root)


func get_region_id() -> StringName:
	return _region_id


func get_camp_zone() -> CampStorageZone:
	return _camp_zone


func get_inventory() -> SettlementInventory:
	return _inventory


func get_world_navigation() -> WorldNavigation:
	return _world_navigation


func get_sites() -> Array[ConstructionSite]:
	_prune_invalid_sites()
	return _sites.duplicate()


func get_site_by_id(target_site_id: StringName) -> ConstructionSite:
	_prune_invalid_sites()
	for site: ConstructionSite in _sites:
		if site.site_id == target_site_id:
			return site
	return null


func has_site_overlapping_rect(rect: Rect2, tolerance: float = 0.01) -> bool:
	_prune_invalid_sites()
	var shrunk := Rect2(
		rect.position + Vector2(tolerance, tolerance),
		Vector2(maxf(0.0, rect.size.x - tolerance * 2.0), maxf(0.0, rect.size.y - tolerance * 2.0))
	)
	for site: ConstructionSite in _sites:
		if site.get_footprint_rect().intersects(shrunk, true):
			return true
	return false


func get_completed_buildings() -> Array[BuildingInstance]:
	for i: int in range(_completed_buildings.size() - 1, -1, -1):
		if not is_instance_valid(_completed_buildings[i]) or not _completed_buildings[i].is_inside_tree():
			_completed_buildings.remove_at(i)
	return _completed_buildings.duplicate()


func has_building_overlapping_rect(rect: Rect2, tolerance: float = 0.01) -> bool:
	var shrunk := Rect2(rect.position + Vector2.ONE * tolerance, (rect.size - Vector2.ONE * tolerance * 2.0).max(Vector2.ZERO))
	for building: BuildingInstance in get_completed_buildings():
		if building.get_footprint_rect().intersects(shrunk, true):
			return true
	return false


func has_footprint_overlapping_rect(rect: Rect2, tolerance: float = 0.01) -> bool:
	return has_site_overlapping_rect(rect, tolerance) or has_building_overlapping_rect(rect, tolerance)


func _on_site_state_changed(site: ConstructionSite) -> void:
	if not is_instance_valid(site) or not _sites.has(site) or site.get_site_state() != ConstructionSite.SiteState.COMPLETING:
		return
	var uid: int = site.get_instance_id()
	if _queued_completions.has(uid):
		return
	_queued_completions[uid] = true
	_complete_queued_site.call_deferred(uid)


func _complete_queued_site(uid: int) -> void:
	_queued_completions.erase(uid)
	var site: ConstructionSite = instance_from_id(uid) as ConstructionSite
	if is_instance_valid(site):
		complete_site_transaction(site)


func _valid_completion_site(site: ConstructionSite) -> bool:
	return is_instance_valid(site) and _sites.has(site) and site.is_inside_tree() and site.get_parent() == _sites_root and site.region_id == _region_id and site.is_completion_ready()


func complete_site_transaction(site: ConstructionSite, building_instance: BuildingInstance = null) -> bool:
	if _completion_in_progress or not _valid_completion_site(site) or site._work_transaction_in_progress:
		return false
	if site.get_site_state() != ConstructionSite.SiteState.COMPLETING:
		return false
	_completion_in_progress = true
	if not is_instance_valid(_buildings_root) or not _buildings_root.is_inside_tree() or _buildings_root.get_world_3d() != site.get_world_3d() or StringName(_buildings_root.get_meta(&"region_id", &"")) != site.region_id:
		site.record_completion_failure("invalid_buildings_root")
		_schedule_retry(site)
		_completion_in_progress = false
		return false
	var building: BuildingInstance = null
	var created: Variant = building_instance
	if created == null:
		created = building_creator_override.call(site) if building_creator_override.is_valid() else BuildingInstance.new()
	if created is BuildingInstance:
		building = created as BuildingInstance
	var owns_created: bool = is_instance_valid(created) and created is Node and (created as Node).get_parent() == null
	var valid: bool = is_instance_valid(building) and owns_created
	if valid and building_instance == null:
		valid = building.configure(site.site_id, site.definition, site.region_id, site.get_consumed_amounts())
	if valid:
		_buildings_root.add_child(building)
		building.global_transform = site.global_transform
		valid = building.is_valid() and building.building_id == site.site_id and building.definition == site.definition and building.region_id == site.region_id and building.get_world_3d() == site.get_world_3d() and building.get_footprint_rect() == site.get_footprint_rect() and building.incorporated_materials == site.get_consumed_amounts()
	if not valid:
		if owns_created and is_instance_valid(created) and created is Node:
			var partial: Node = created as Node
			# Overrides must return a newly owned node; never free a registered structure.
			if not _completed_buildings.has(partial):
				if partial.get_parent() != null:
					partial.get_parent().remove_child(partial)
				partial.free()
		site.record_completion_failure("building_instantiation_or_validation_failed")
		_schedule_retry(site)
		_completion_in_progress = false
		return false
	_completed_buildings.append(building)
	# Both footprints are registered before any completion callback can run.
	site.commit_completed_building(building)
	_sites.erase(site)
	_sites_root.remove_child(site)
	site.queue_free()
	if is_instance_valid(_world_navigation):
		_world_navigation.notify_building_geometry_changed()
	_completion_in_progress = false
	return true


func _schedule_retry(site: ConstructionSite) -> void:
	if site.get_site_state() != ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE:
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = ConstructionSite.RETRY_COOLDOWN_SEC
	add_child(timer)
	var uid: int = site.get_instance_id()
	_retry_timers[uid] = timer
	site._completion_retry_timer = timer
	timer.timeout.connect(_on_completion_retry_timeout.bind(uid))
	timer.start()


func _on_completion_retry_timeout(uid: int) -> void:
	var timer: Timer = _retry_timers.get(uid) as Timer
	_retry_timers.erase(uid)
	if is_instance_valid(timer):
		timer.queue_free()
	var site: ConstructionSite = instance_from_id(uid) as ConstructionSite
	if not _valid_completion_site(site) or site.get_site_state() != ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE:
		return
	site._retry_cooldown_remaining_sec = 0.0
	site._completion_retry_timer = null
	site._site_state = ConstructionSite.SiteState.COMPLETING
	site.state_changed.emit(site)


func retry_failed_site_completion(site: ConstructionSite) -> bool:
	if _completion_in_progress or not _valid_completion_site(site) or site.get_site_state() != ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR:
		return false
	site._completion_retry_count = 0
	site._retry_cooldown_remaining_sec = 0.0
	site._completion_retry_timer = null
	site._site_state = ConstructionSite.SiteState.COMPLETING
	site.state_changed.emit(site)
	return true


func try_create_site_from_placement(
	definition: BuildingDefinition,
	world_position: Vector3
) -> Dictionary:
	if _sites_root == null or not is_instance_valid(_sites_root):
		return _reject("invalid_sites_root", "Canteiro inválido: raiz de construções indisponível.", definition, world_position)
	if _inventory == null or _inventory.get_storage_source() == null:
		return _reject("invalid_inventory", "Estoque do assentamento indisponível para reservar obra.", definition, world_position)
	if definition == null or not definition.is_valid():
		return _reject("invalid_definition", "Definição de edificação inválida.", definition, world_position)
	if not world_position.is_finite():
		return _reject("invalid_position", "Posição do canteiro inválida.", definition, world_position)

	var costs: Dictionary = _extract_positive_costs(definition.costs)
	if costs.is_empty():
		return _reject("invalid_costs", "Custo da edificação inválido ou vazio.", definition, world_position)

	var target_rect: Rect2 = definition.get_footprint_rect_at(Vector2(world_position.x, world_position.z))
	if has_footprint_overlapping_rect(target_rect):
		if has_building_overlapping_rect(target_rect):
			return _reject("building_overlap", "Completed building occupies this area.", definition, world_position)
		return _reject(
			"site_overlap",
			"Posição inválida: já existe um canteiro de obra nessa área.",
			definition,
			world_position
		)

	if _camp_zone != null and is_instance_valid(_camp_zone) and _camp_zone.is_valid():
		var camp_anchor: Vector3 = _camp_zone.get_anchor_position()
		var half: Vector2 = _camp_zone.zone_bounds_half_extents
		var camp_rect := Rect2(Vector2(camp_anchor.x, camp_anchor.z) - half, half * 2.0)
		if camp_rect.intersects(target_rect, true):
			return _reject(
				"camp_overlap",
				"Posição inválida: não é permitido construir sobre a área do acampamento.",
				definition,
				world_position
			)

	var ids: Dictionary = _allocate_unique_ids()
	var new_site_id: StringName = ids["site_id"] as StringName
	var new_res_id: StringName = ids["reservation_id"] as StringName

	if not _inventory.can_reserve_batch(new_res_id, costs):
		var msg: String = _format_insufficient_message(definition, costs)
		return _reject("insufficient_resources", msg, definition, world_position)

	if not _inventory.reserve_batch(new_res_id, costs):
		var msg_fail: String = _format_insufficient_message(definition, costs)
		return _reject("reservation_failed", msg_fail, definition, world_position)

	var site: ConstructionSite = null
	if site_creator_override.is_valid():
		var override_result: Variant = site_creator_override.call(new_site_id, new_res_id, definition, world_position)
		if override_result is ConstructionSite:
			site = override_result as ConstructionSite
	else:
		site = ConstructionSite.new()

	var configured: bool = false
	if site != null and is_instance_valid(site):
		site.position = _world_to_sites_local(world_position)
		if site.get_parent() == null:
			_sites_root.add_child(site)
		configured = site.configure(
			new_site_id,
			new_res_id,
			definition,
			_inventory,
			_resource_defs,
			_region_id
		)
	if not configured or site == null or not is_instance_valid(site) or not site.is_valid():
		_inventory.release_batch(new_res_id)
		if site != null and is_instance_valid(site):
			if site.get_parent() != null:
				site.get_parent().remove_child(site)
			site.free()
		return _reject(
			"site_instantiation_failed",
			"Falha ao criar o canteiro de obra; reserva liberada.",
			definition,
			world_position
		)

	_sites.append(site)
	site.state_changed.connect(_on_site_state_changed)
	site_created.emit(site)
	var display_name: String = definition.display_name if not definition.display_name.is_empty() else String(definition.definition_id)
	return {
		"ok": true,
		"site": site,
		"reason": "",
		"message": "Canteiro criado: %s (recursos reservados)." % display_name,
	}


func _allocate_unique_ids() -> Dictionary:
	while true:
		var suffix: String = "%s_%04d" % [String(_region_id), _next_site_seq]
		_next_site_seq += 1
		var candidate_site_id := StringName("site_" + suffix)
		var candidate_res_id := StringName("res_site_" + suffix)
		if _inventory != null and _inventory.has_reservation(candidate_res_id):
			continue
		if get_site_by_id(candidate_site_id) != null or _has_building_id(candidate_site_id):
			continue
		return {
			"site_id": candidate_site_id,
			"reservation_id": candidate_res_id,
		}
	return {}


func _world_to_sites_local(world_pos: Vector3) -> Vector3:
	if _sites_root != null and is_instance_valid(_sites_root) and _sites_root.is_inside_tree():
		return _sites_root.to_local(world_pos)
	return world_pos


func _reject(
	reason: String,
	message: String,
	definition: BuildingDefinition,
	world_position: Vector3
) -> Dictionary:
	site_creation_rejected.emit(reason, message, definition, world_position)
	return {
		"ok": false,
		"site": null,
		"reason": reason,
		"message": message,
	}


func _format_insufficient_message(definition: BuildingDefinition, costs: Dictionary) -> String:
	var label: String = definition.display_name if not definition.display_name.is_empty() else String(definition.definition_id)
	var parts: Array[String] = []
	var keys: Array[StringName] = []
	for k: Variant in costs.keys():
		keys.append(k as StringName)
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for res_id: StringName in keys:
		var req: int = int(costs[res_id])
		var free_amt: int = _inventory.get_available_amount(res_id) if _inventory != null else 0
		if free_amt < req:
			parts.append("%s %d/%d" % [_display_resource_name(res_id), free_amt, req])
	if parts.is_empty():
		return "Recursos insuficientes no estoque livre para construir %s." % label
	return "Estoque livre insuficiente para %s (%s)." % [label, ", ".join(parts)]


func _display_resource_name(res_id: StringName) -> String:
	if _resource_defs.has(res_id):
		var def: ResourceDefinition = _resource_defs[res_id] as ResourceDefinition
		if def != null and not def.display_name.is_empty():
			return def.display_name
	return String(res_id)


func _prune_invalid_sites() -> void:
	for i: int in range(_sites.size() - 1, -1, -1):
		var site: ConstructionSite = _sites[i]
		if site == null or not is_instance_valid(site) or not site.is_inside_tree():
			_sites.remove_at(i)


static func _extract_positive_costs(costs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in costs.keys():
		var amt: int = int(costs[key])
		if amt <= 0:
			continue
		var res_id: StringName = StringName(String(key))
		if res_id.is_empty():
			return {}
		result[res_id] = amt
	return result


func _has_building_id(id: StringName) -> bool:
	for building: BuildingInstance in get_completed_buildings():
		if building.building_id == id:
			return true
	return false
