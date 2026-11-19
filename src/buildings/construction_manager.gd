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

const BUSY_COMPLETION_RETRY_SEC: float = 0.05

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
var _creation_in_progress: bool = false
var _retry_timers: Dictionary = {}
var _busy_completion_timers: Dictionary = {}
var _navigation_retry_timer: Timer = null


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
		if is_instance_valid(_world_navigation):
			_world_navigation.register_additional_source_root(_buildings_root)
			if not _world_navigation.navigation_rebake_failed.is_connected(_on_navigation_rebake_failed):
				_world_navigation.navigation_rebake_failed.connect(_on_navigation_rebake_failed)


func _exit_tree() -> void:
	if is_instance_valid(_world_navigation):
		_world_navigation.unregister_additional_source_root(_buildings_root)
		if _world_navigation.navigation_rebake_failed.is_connected(_on_navigation_rebake_failed):
			_world_navigation.navigation_rebake_failed.disconnect(_on_navigation_rebake_failed)
	for timer_var: Variant in _retry_timers.values():
		var t: Timer = timer_var as Timer
		if is_instance_valid(t):
			t.queue_free()
	_retry_timers.clear()
	for busy_var: Variant in _busy_completion_timers.values():
		var bt: Timer = busy_var as Timer
		if is_instance_valid(bt):
			bt.queue_free()
	_busy_completion_timers.clear()
	if is_instance_valid(_navigation_retry_timer):
		_navigation_retry_timer.queue_free()
		_navigation_retry_timer = null


func _on_navigation_rebake_failed(_reason: String) -> void:
	if not is_instance_valid(_world_navigation) or not _world_navigation.can_retry_active_rebake() or is_instance_valid(_navigation_retry_timer):
		return
	_navigation_retry_timer = Timer.new()
	_navigation_retry_timer.one_shot = true
	_navigation_retry_timer.wait_time = WorldNavigation.NAV_REBAKE_RETRY_COOLDOWN_SEC
	add_child(_navigation_retry_timer)
	_navigation_retry_timer.timeout.connect(_retry_navigation_bake)
	_navigation_retry_timer.start()


func _retry_navigation_bake() -> void:
	_navigation_retry_timer.queue_free()
	_navigation_retry_timer = null
	if is_instance_valid(_world_navigation) and _world_navigation.can_retry_active_rebake() and _world_navigation._active_rebake_token == null:
		_world_navigation.request_async_active_rebake()


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
		_execute_site_completion(site, null, true)


func _valid_completion_site(site: ConstructionSite) -> bool:
	return is_instance_valid(site) and _sites.has(site) and site.is_inside_tree() and site.get_parent() == _sites_root and site.region_id == _region_id and not site.is_transaction_busy() and site.is_completion_ready()


func _has_conflicting_completed_building(site: ConstructionSite) -> bool:
	return _has_building_id(site.site_id) or has_building_overlapping_rect(site.get_footprint_rect())


func _world_to_buildings_local_transform(target_global: Transform3D) -> Transform3D:
	if is_instance_valid(_buildings_root) and _buildings_root.is_inside_tree():
		return _buildings_root.global_transform.affine_inverse() * target_global
	return target_global


func _validate_site_ready_for_completion_under_guard(
	site: ConstructionSite,
	expected_site_id: StringName,
	expected_generation: int,
	expected_world: World3D,
	expected_region: StringName
) -> bool:
	if not is_instance_valid(site) or not _sites.has(site) or not site.is_inside_tree() or site.get_parent() != _sites_root:
		return false
	if site.site_id != expected_site_id or site.get_generation() != expected_generation:
		return false
	if site.get_world_3d() != expected_world or site.region_id != expected_region or site.region_id != _region_id:
		return false
	if site._work_transaction_in_progress or site._is_complementing:
		return false
	if site.get_site_state() != ConstructionSite.SiteState.COMPLETING or not site.is_completion_ready():
		return false
	return not _has_conflicting_completed_building(site)


func _finish_completion_guards(scope: ReservedWithdrawalCoordinator.CompletionScope) -> void:
	ReservedWithdrawalCoordinator._release_completion_scope(scope)
	_completion_in_progress = false


func _schedule_busy_completion_retry(site: ConstructionSite) -> void:
	if not is_instance_valid(site) or not _sites.has(site) or site.get_site_state() != ConstructionSite.SiteState.COMPLETING:
		return
	var uid: int = site.get_instance_id()
	if _busy_completion_timers.has(uid) and is_instance_valid(_busy_completion_timers[uid]):
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = BUSY_COMPLETION_RETRY_SEC
	add_child(timer)
	_busy_completion_timers[uid] = timer
	timer.timeout.connect(_on_busy_completion_retry_timeout.bind(uid))
	timer.start()


func _on_busy_completion_retry_timeout(uid: int) -> void:
	var timer: Timer = _busy_completion_timers.get(uid) as Timer
	_busy_completion_timers.erase(uid)
	if is_instance_valid(timer):
		timer.queue_free()
	var site: ConstructionSite = instance_from_id(uid) as ConstructionSite
	if is_instance_valid(site) and site.get_site_state() == ConstructionSite.SiteState.COMPLETING:
		_execute_site_completion(site, null, true)


func _clear_completion_timers_for_site(uid: int) -> void:
	var retry_timer: Timer = _retry_timers.get(uid) as Timer
	_retry_timers.erase(uid)
	if is_instance_valid(retry_timer):
		retry_timer.queue_free()
	var busy_timer: Timer = _busy_completion_timers.get(uid) as Timer
	_busy_completion_timers.erase(uid)
	if is_instance_valid(busy_timer):
		busy_timer.queue_free()


func complete_site_transaction(site: ConstructionSite, building_instance: BuildingInstance = null) -> bool:
	return _execute_site_completion(site, building_instance, false)


func _execute_site_completion(
	site: ConstructionSite,
	building_instance: BuildingInstance,
	from_queued_dispatch: bool
) -> bool:
	if _completion_in_progress or _creation_in_progress or not _valid_completion_site(site):
		if from_queued_dispatch and is_instance_valid(site) and _sites.has(site) and site.get_site_state() == ConstructionSite.SiteState.COMPLETING and (_completion_in_progress or _creation_in_progress or site.is_transaction_busy()):
			_schedule_busy_completion_retry(site)
		return false
	if site.get_site_state() != ConstructionSite.SiteState.COMPLETING:
		return false
	if _has_conflicting_completed_building(site):
		return false

	var expected_site_id: StringName = site.site_id
	var expected_generation: int = site.get_generation()
	var expected_world: World3D = site.get_world_3d()
	var expected_region: StringName = site.region_id

	var acq: Dictionary = ReservedWithdrawalCoordinator._acquire_completion_scope(self, site)
	if not bool(acq.get("ok", false)):
		if bool(acq.get("busy", false)):
			if from_queued_dispatch:
				_schedule_busy_completion_retry(site)
			return false
		site.record_completion_failure(String(acq.get("reason", "invalid_domain")))
		_schedule_retry(site)
		return false

	var scope: ReservedWithdrawalCoordinator.CompletionScope = acq["scope"] as ReservedWithdrawalCoordinator.CompletionScope
	_completion_in_progress = true

	if not is_instance_valid(_buildings_root) or not _buildings_root.is_inside_tree() or _buildings_root.get_world_3d() != expected_world or StringName(_buildings_root.get_meta(&"region_id", &"")) != expected_region:
		site._record_completion_failure_under_guard("invalid_buildings_root", scope)
		_schedule_retry(site)
		_finish_completion_guards(scope)
		return false

	var building: BuildingInstance = null
	var created: Variant = building_instance
	if created == null:
		created = building_creator_override.call(site) if building_creator_override.is_valid() else BuildingInstance.new()
	if created is BuildingInstance:
		building = created as BuildingInstance
	var owns_created: bool = is_instance_valid(created) and created is Node and (created as Node).get_parent() == null
	var valid: bool = (
		is_instance_valid(building)
		and owns_created
		and _validate_site_ready_for_completion_under_guard(site, expected_site_id, expected_generation, expected_world, expected_region)
	)
	if valid and building_instance == null:
		valid = building.configure(expected_site_id, site.definition, expected_region, site.get_consumed_amounts())
	if valid:
		# Configure transform before tree entry so child_entered_tree never observes unpositioned geometry.
		building.transform = _world_to_buildings_local_transform(site.global_transform)
		valid = (
			building.is_valid()
			and building.building_id == expected_site_id
			and building.definition == site.definition
			and building.region_id == expected_region
			and building.incorporated_materials == site.get_consumed_amounts()
			and _validate_site_ready_for_completion_under_guard(site, expected_site_id, expected_generation, expected_world, expected_region)
		)
	if valid:
		_buildings_root.add_child(building)
		building.global_transform = site.global_transform
		valid = (
			_validate_site_ready_for_completion_under_guard(site, expected_site_id, expected_generation, expected_world, expected_region)
			and building.is_valid()
			and building.building_id == expected_site_id
			and building.definition == site.definition
			and building.region_id == expected_region
			and building.get_world_3d() == expected_world
			and building.get_footprint_rect() == site.get_footprint_rect()
			and building.incorporated_materials == site.get_consumed_amounts()
		)
	if not valid:
		if owns_created and is_instance_valid(created) and created is Node:
			var partial: Node = created as Node
			# Overrides must return a newly owned node; never free a registered structure.
			if not _completed_buildings.has(partial):
				if partial.get_parent() != null:
					partial.get_parent().remove_child(partial)
				partial.free()
		if is_instance_valid(site):
			site._record_completion_failure_under_guard("building_instantiation_or_validation_failed", scope)
			_schedule_retry(site)
		_finish_completion_guards(scope)
		return false

	_clear_completion_timers_for_site(site.get_instance_id())
	_completed_buildings.append(building)
	# Both footprints are registered before any completion callback can run.
	if is_instance_valid(_world_navigation):
		_world_navigation.notify_building_geometry_changed(building)
	site._commit_completed_building_under_guard(building, scope)
	_sites.erase(site)
	_finish_completion_guards(scope)
	if is_instance_valid(site) and site.get_parent() == _sites_root:
		_sites_root.remove_child(site)
	if is_instance_valid(site):
		site.queue_free()
	if is_instance_valid(_world_navigation):
		_world_navigation.request_async_active_rebake()
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
	if not is_instance_valid(site) or not _sites.has(site) or not site.is_inside_tree() or site.get_parent() != _sites_root or site.region_id != _region_id or site.get_site_state() != ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE:
		return
	if site.is_transaction_busy() or ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(site.get_world_3d(), site.region_id):
		_schedule_retry(site)
		return
	if not site.is_completion_ready():
		return
	site._retry_cooldown_remaining_sec = 0.0
	site._completion_retry_timer = null
	site._site_state = ConstructionSite.SiteState.COMPLETING
	site.state_changed.emit(site)


func retry_failed_site_completion(site: ConstructionSite) -> bool:
	if _completion_in_progress or not _valid_completion_site(site) or site.get_site_state() != ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR:
		return false
	if ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(site.get_world_3d(), site.region_id):
		return false
	site._completion_retry_count = 0
	site._retry_cooldown_remaining_sec = 0.0
	site._completion_retry_timer = null
	site._site_state = ConstructionSite.SiteState.COMPLETING
	site.state_changed.emit(site)
	return true


func _finish_site_creation_guards(scope: ReservedWithdrawalCoordinator.SiteCreationScope) -> void:
	ReservedWithdrawalCoordinator._release_site_creation_scope(scope)
	_creation_in_progress = false


func _has_live_domain_site_id(candidate_site_id: StringName) -> bool:
	if not is_instance_valid(_sites_root) or not _sites_root.is_inside_tree():
		return false
	var tree: SceneTree = _sites_root.get_tree()
	var world: World3D = _sites_root.get_world_3d()
	if tree == null or world == null:
		return false
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer := node as ConstructionSite
		if peer != null and is_instance_valid(peer) and peer.is_inside_tree() and peer.get_world_3d() == world and peer.region_id == _region_id and peer.site_id == candidate_site_id:
			return true
	return false


func try_create_site_from_placement(
	definition: BuildingDefinition,
	world_position: Vector3
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _reject("wrong_thread", "Operação de criação deve executar na thread principal.", definition, world_position)
	if _sites_root == null or not is_instance_valid(_sites_root) or not _sites_root.is_inside_tree() or _sites_root.get_world_3d() == null:
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

	if _creation_in_progress or _completion_in_progress:
		return _reject("busy", "Região econômica ocupada por outra transação.", definition, world_position)

	var acq: Dictionary = ReservedWithdrawalCoordinator._acquire_site_creation_scope(self)
	if not bool(acq.get("ok", false)):
		var acq_reason: String = String(acq.get("reason", "busy" if bool(acq.get("busy", false)) else "invalid_domain"))
		var acq_msg: String = "Região econômica ocupada por outra transação." if bool(acq.get("busy", false)) else "Domínio econômico inválido ou ambíguo para criar canteiro."
		return _reject(acq_reason, acq_msg, definition, world_position)

	var scope: ReservedWithdrawalCoordinator.SiteCreationScope = acq["scope"] as ReservedWithdrawalCoordinator.SiteCreationScope
	_creation_in_progress = true
	var expected_world: World3D = scope.world
	var storage_source: SettlementStorageSource = scope.storage_source
	var saved_next_site_seq: int = _next_site_seq

	var ids: Dictionary = _allocate_unique_ids()
	var new_site_id: StringName = ids["site_id"] as StringName
	var new_res_id: StringName = ids["reservation_id"] as StringName

	var reservation_checkpoint: Dictionary = {}
	var reserved_via_silent_pile: bool = false
	var reserved_via_silent_memory: bool = false
	var reserved_via_fallback: bool = false

	if storage_source is GroundPileManager:
		var gpm: GroundPileManager = storage_source as GroundPileManager
		var prep: Dictionary = gpm._prepare_site_reservation_under_guard(new_res_id, costs, scope)
		if not bool(prep.get("ok", false)):
			_next_site_seq = saved_next_site_seq
			_finish_site_creation_guards(scope)
			var prep_reason: String = String(prep.get("reason", "insufficient_resources"))
			if prep_reason == "insufficient_resources":
				return _reject("insufficient_resources", _format_insufficient_message(definition, costs), definition, world_position)
			return _reject(prep_reason, "Não foi possível reservar os recursos da obra.", definition, world_position)
		var applied: Dictionary = gpm._apply_prepared_site_reservation_silent(
			new_res_id,
			prep["entries"] as Array[Dictionary],
			scope
		)
		if not bool(applied.get("ok", false)):
			_next_site_seq = saved_next_site_seq
			_finish_site_creation_guards(scope)
			return _reject("reservation_failed", _format_insufficient_message(definition, costs), definition, world_position)
		reservation_checkpoint = applied["checkpoint"] as Dictionary
		reserved_via_silent_pile = true
	elif storage_source is InMemoryStorageSource:
		var mem_src: InMemoryStorageSource = storage_source as InMemoryStorageSource
		var applied_mem: Dictionary = mem_src._apply_site_reservation_silent(new_res_id, costs, scope)
		if not bool(applied_mem.get("ok", false)):
			_next_site_seq = saved_next_site_seq
			_finish_site_creation_guards(scope)
			var mem_reason: String = String(applied_mem.get("reason", "insufficient_resources"))
			if mem_reason == "insufficient_resources":
				return _reject("insufficient_resources", _format_insufficient_message(definition, costs), definition, world_position)
			return _reject("reservation_failed", _format_insufficient_message(definition, costs), definition, world_position)
		reservation_checkpoint = applied_mem["checkpoint"] as Dictionary
		reserved_via_silent_memory = true
	else:
		if not storage_source.can_reserve_batch(new_res_id, costs):
			_next_site_seq = saved_next_site_seq
			_finish_site_creation_guards(scope)
			return _reject("insufficient_resources", _format_insufficient_message(definition, costs), definition, world_position)
		storage_source.begin_batch()
		if not storage_source.reserve_batch(new_res_id, costs):
			storage_source.end_batch(true)
			_next_site_seq = saved_next_site_seq
			_finish_site_creation_guards(scope)
			return _reject("reservation_failed", _format_insufficient_message(definition, costs), definition, world_position)
		reserved_via_fallback = true

	var site: ConstructionSite = null
	if site_creator_override.is_valid():
		var override_result: Variant = site_creator_override.call(new_site_id, new_res_id, definition, world_position)
		if override_result is ConstructionSite:
			site = override_result as ConstructionSite
	else:
		site = ConstructionSite.new()

	var owns_site: bool = (
		site != null
		and is_instance_valid(site)
		and site.get_parent() == null
		and not _sites.has(site)
		and not site.is_valid()
	)
	var valid: bool = owns_site
	if valid:
		# Configure and position before tree entry so child_entered_tree never observes an invalid site.
		site.position = _world_to_sites_local(world_position)
		valid = site.configure(
			new_site_id,
			new_res_id,
			definition,
			_inventory,
			_resource_defs,
			_region_id
		)
		if valid and is_instance_valid(site):
			site._is_preparing_or_transacting = true
			scope.new_site = site
		valid = (
			valid
			and is_instance_valid(site)
			and site.is_valid()
			and site.site_id == new_site_id
			and site.reservation_id == new_res_id
			and site.region_id == _region_id
			and site.definition == definition
			and site.get_inventory() == _inventory
			and site.get_site_state() == ConstructionSite.SiteState.ACTIVE
		)
	if valid:
		_sites_root.add_child(site)
		valid = (
			is_instance_valid(site)
			and site.is_inside_tree()
			and site.get_parent() == _sites_root
			and site.get_world_3d() == expected_world
			and site.is_valid()
			and site.site_id == new_site_id
			and site.reservation_id == new_res_id
			and site.region_id == _region_id
			and site.definition == definition
			and site.get_inventory() == _inventory
			and site.get_site_state() == ConstructionSite.SiteState.ACTIVE
			and not has_footprint_overlapping_rect(site.get_footprint_rect())
			and _inventory.get_reservation_amounts(new_res_id) == costs
		)

	if not valid:
		if reserved_via_silent_pile:
			(storage_source as GroundPileManager)._restore_site_reservation_checkpoint_silent(reservation_checkpoint, scope)
		elif reserved_via_silent_memory:
			(storage_source as InMemoryStorageSource)._restore_site_reservation_checkpoint_silent(reservation_checkpoint, scope)
		elif reserved_via_fallback:
			storage_source.release_batch(new_res_id)
			storage_source.end_batch(true)
		_next_site_seq = saved_next_site_seq
		if owns_site and is_instance_valid(site):
			site._unbind_inventory()
			if site.get_parent() != null:
				site.get_parent().remove_child(site)
			site.free()
		scope.new_site = null
		_finish_site_creation_guards(scope)
		return _reject(
			"site_instantiation_failed",
			"Falha ao criar o canteiro de obra; reserva liberada.",
			definition,
			world_position
		)

	# Irreversible commit point: site and reservation are both valid and registered before any signal fires.
	_sites.append(site)
	site.state_changed.connect(_on_site_state_changed)
	if reserved_via_silent_pile:
		_inventory._transaction_revision += 1

	site._suppress_coordinator_signal_echo = true
	if reserved_via_silent_pile:
		(storage_source as GroundPileManager)._publish_site_reservation_committed(scope)
	elif reserved_via_silent_memory:
		(storage_source as InMemoryStorageSource)._publish_site_reservation_committed(scope)
	elif reserved_via_fallback:
		storage_source.end_batch(false)
	if is_instance_valid(site):
		site._suppress_coordinator_signal_echo = false

	site_created.emit(site)
	_finish_site_creation_guards(scope)
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
		if get_site_by_id(candidate_site_id) != null or _has_building_id(candidate_site_id) or _has_live_domain_site_id(candidate_site_id):
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
