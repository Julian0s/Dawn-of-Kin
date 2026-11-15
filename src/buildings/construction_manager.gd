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
	if has_site_overlapping_rect(target_rect):
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
		if get_site_by_id(candidate_site_id) != null:
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
