class_name ReservedWithdrawalCoordinator
extends RefCounted
## Opt-in transactional coordinator for withdrawing site-reserved resources from a
## physical ground pile into a provenance-enabled UnitCarryLoad and reconciling the
## site's transit claim atomically, with idempotency, fixed lock order, full pre-commit
## rollback across all participants, and coherent post-commit signal publication.

var fault_injection_hook: Callable = Callable()

const DOMAIN_META := &"_reserved_withdrawal_domains"
const RECEIPT_WITHDRAWAL := &"reserved_withdrawal"
const RECEIPT_DELIVERY := &"selective_site_delivery"
const RECEIPT_CAMP_DELIVERY := &"selective_camp_delivery"


## Capability for the one active selective delivery in this domain.
class DeliveryScope extends RefCounted:
	var site: ConstructionSite
	var unit: Unit
	var load: UnitCarryLoad
	var inventory: SettlementInventory
	var storage: GroundPileManager
	var sites: Array[ConstructionSite] = []


## Capability for the one active selective camp delivery in this domain.
class CampDeliveryScope extends RefCounted:
	var world: World3D
	var region_id: StringName
	var camp_zone: CampStorageZone
	var unit: Unit
	var load: UnitCarryLoad
	var inventory: SettlementInventory
	var storage: GroundPileManager
	var sites: Array[ConstructionSite] = []


## Capability for the one active site completion in this domain.
class CompletionScope extends RefCounted:
	var world: World3D
	var region_id: StringName
	var manager: ConstructionManager
	var site: ConstructionSite
	var inventory: SettlementInventory
	var storage: GroundPileManager
	var sites: Array[ConstructionSite] = []
	var authority: RegionalAuthority = null


## Capability for the one active site creation in this domain.
class SiteCreationScope extends RefCounted:
	var world: World3D
	var region_id: StringName
	var manager: ConstructionManager
	var inventory: SettlementInventory
	var storage_source: SettlementStorageSource
	var storage: GroundPileManager
	var camp_zone: CampStorageZone
	var sites: Array[ConstructionSite] = []
	var new_site: ConstructionSite = null
	var authority: RegionalAuthority = null
	var _expected_site_id: StringName
	var _expected_reservation_id: StringName
	var _expected_definition: BuildingDefinition
	var _expected_costs: Dictionary = {}
	var _reservation_applied: bool = false
	var _commit_authorized: bool = false
	var _rollback_authorized: bool = false
	var _published: bool = false
	var _rolled_back: bool = false
	var _bound_checkpoint: Dictionary = {}


## Capability for the one active manual complement in this domain.
class ManualComplementScope extends RefCounted:
	var world: World3D
	var region_id: StringName
	var site: ConstructionSite
	var inventory: SettlementInventory
	var storage_source: SettlementStorageSource
	var storage: GroundPileManager
	var camp_zone: CampStorageZone
	var sites: Array[ConstructionSite] = []
	var authority: RegionalAuthority = null
	var _complement_applied: bool = false
	var _commit_authorized: bool = false
	var _rollback_authorized: bool = false
	var _published: bool = false
	var _rolled_back: bool = false
	var _bound_checkpoint: Dictionary = {}


class WorkScope extends RefCounted:
	var participants: Dictionary
	var authority: RegionalAuthority
	var temporary_authority: bool
	var had_domain_metadata: bool


class RegionalAuthority extends RefCounted:
	var storage: WeakRef
	var is_executing: bool = false
	var receipts: Dictionary = {}
	var committed_lots: Dictionary = {}
	var active_delivery: DeliveryScope
	var active_camp_delivery: CampDeliveryScope
	var active_completion: CompletionScope
	var active_site_creation: SiteCreationScope
	var active_manual_complement: ManualComplementScope
	var active_work: WorkScope
	var construction_transfer_serial: int = 0

	func has_active_operation() -> bool:
		return (
			is_executing
			or active_delivery != null
			or active_camp_delivery != null
			or active_completion != null
			or active_site_creation != null
			or active_manual_complement != null
			or active_work != null
		)


static var _active_site_creation_scopes: Array[SiteCreationScope] = []
static var _active_manual_complement_scopes: Array[ManualComplementScope] = []


var _owner_thread_id: int = OS.get_thread_caller_id()
var _handle_executing: bool = false
var _last_world: WeakRef
var _last_region: StringName


func _last_authority() -> RegionalAuthority:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _last_world == null:
		return null
	var world: World3D = _last_world.get_ref() as World3D
	if world == null:
		return null
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	return domains.get(_last_region) as RegionalAuthority


func is_busy() -> bool:
	var authority := _last_authority()
	return authority != null and authority.is_executing


## Queries refer to the last domain resolved by this handle.
func has_receipt(operation_id: Variant) -> bool:
	var authority := _last_authority()
	return not get_receipt(operation_id).is_empty()


func get_receipt(operation_id: Variant) -> Dictionary:
	var authority := _last_authority()
	if authority == null or not CarryProvenanceLedger._id(operation_id):
		return {}
	var op := StringName(operation_id)
	return _read_receipt(authority.receipts.get(op), op, RECEIPT_WITHDRAWAL).duplicate(true)


func get_receipt_in_domain(world: World3D, region_id: Variant, operation_id: Variant) -> Dictionary:
	var authority := _receipt_authority_in_domain(world, region_id, operation_id)
	if authority == null:
		return {}
	var op := StringName(operation_id)
	var receipt := _read_receipt(authority.receipts.get(op), op, RECEIPT_WITHDRAWAL)
	if receipt.is_empty() or receipt.world_instance_id != world.get_instance_id() or receipt.region_id != StringName(region_id):
		return {}
	return receipt.duplicate(true)


## A receipt lookup must never resolve, bind or create an economic domain.
static func _receipt_authority_in_domain(world: World3D, region_id: Variant, operation_id: Variant) -> RegionalAuthority:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or world == null:
		return null
	if not CarryProvenanceLedger._id(region_id) or not CarryProvenanceLedger._id(operation_id):
		return null
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	return domains.get(StringName(region_id)) as RegionalAuthority


## A C2 receipt without kind is admitted only with the original C2 format.
static func _read_receipt(record: Variant, operation: StringName, kind: StringName) -> Dictionary:
	if not record is Dictionary or not record.get("receipt") is Dictionary:
		return {}
	if kind == RECEIPT_CAMP_DELIVERY:
		for field: String in ["camp_zone", "unit", "load", "inventory", "storage"]:
			if not record.get(field) is WeakRef:
				return {}
	else:
		for field: String in ["site", "unit", "load"]:
			if not record.get(field) is WeakRef:
				return {}
	var receipt: Dictionary = record.receipt
	if typeof(receipt.get("operation_id")) != TYPE_STRING_NAME or receipt.operation_id != operation:
		return {}
	if receipt.has("kind") and (typeof(receipt.kind) != TYPE_STRING_NAME or receipt.kind != kind):
		return {}
	if kind == RECEIPT_DELIVERY or kind == RECEIPT_CAMP_DELIVERY:
		return receipt if receipt.has("kind") else {}
	if kind != RECEIPT_WITHDRAWAL or receipt.size() != (18 if receipt.has("kind") else 17):
		return {}
	for field: String in ["site_id", "reservation_id", "region_id", "unit_id", "resource_id", "lot_id"]:
		if typeof(receipt.get(field)) != TYPE_STRING_NAME or not CarryProvenanceLedger._id(receipt[field]):
			return {}
	for field: String in ["generation", "pile_id", "unit_weight", "requested_amount", "committed_amount"]:
		if typeof(receipt.get(field)) != TYPE_INT or receipt[field] <= 0:
			return {}
	# RefCounted object IDs may be negative in Godot's signed GDScript int.
	for field: String in ["site_instance_id", "world_instance_id", "pile_instance_id", "unit_instance_id", "carry_load_instance_id"]:
		if typeof(receipt.get(field)) != TYPE_INT or receipt[field] == 0:
			return {}
	if receipt.requested_amount != receipt.committed_amount:
		return {}
	return receipt


static func _owns_delivery_scope(scope: DeliveryScope) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or scope == null or not is_instance_valid(scope.site) or not scope.site.is_inside_tree():
		return false
	var world := scope.site.get_world_3d()
	if world == null or scope.load == null or scope.inventory == null or scope.storage == null:
		return false
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	var authority := domains.get(scope.site.region_id) as RegionalAuthority
	return authority != null and authority.is_executing and authority.active_delivery == scope \
		and authority.active_camp_delivery == null and authority.active_completion == null \
		and authority.active_site_creation == null and authority.active_manual_complement == null \
		and authority.storage.get_ref() == scope.storage and scope.site.get_inventory() == scope.inventory \
		and scope.inventory.get_storage_source() == scope.storage and scope.inventory._is_delivering \
		and scope.storage._is_preparing_withdrawal and scope.load._coordinator_transaction_locked \
		and scope.load._provenance_busy and scope.site._is_preparing_or_transacting


static func _owns_camp_delivery_scope(scope: CampDeliveryScope) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or scope == null:
		return false
	if scope.world == null or not CarryProvenanceLedger._id(scope.region_id):
		return false
	if not is_instance_valid(scope.camp_zone) or not scope.camp_zone.is_inside_tree() or scope.camp_zone.get_world_3d() != scope.world:
		return false
	if not is_instance_valid(scope.unit) or not scope.unit.is_inside_tree() or scope.unit.get_world_3d() != scope.world:
		return false
	if scope.load == null or scope.inventory == null or scope.storage == null:
		return false
	var domains: Dictionary = scope.world.get_meta(DOMAIN_META, {})
	var authority := domains.get(scope.region_id) as RegionalAuthority
	if (
		authority == null
		or not authority.is_executing
		or authority.active_camp_delivery != scope
		or authority.active_delivery != null
		or authority.active_completion != null
		or authority.active_site_creation != null
		or authority.active_manual_complement != null
		or authority.storage.get_ref() != scope.storage
		or scope.inventory.get_storage_source() != scope.storage
		or scope.storage.get_camp_zone() != scope.camp_zone
		or not scope.inventory._is_delivering
		or not scope.storage._is_preparing_withdrawal
		or not scope.camp_zone._coordinator_transaction_locked
		or not scope.load._coordinator_transaction_locked
		or not scope.load._provenance_busy
	):
		return false
	for site: ConstructionSite in scope.sites:
		if not is_instance_valid(site) or not site.is_inside_tree() or site.get_world_3d() != scope.world or site.region_id != scope.region_id or not site._is_preparing_or_transacting:
			return false
	return true


static func _owns_completion_scope(scope: CompletionScope) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or scope == null:
		return false
	if scope.world == null or not is_instance_valid(scope.world) or not CarryProvenanceLedger._id(scope.region_id):
		return false
	if scope.manager == null or not is_instance_valid(scope.manager):
		return false
	if scope.site == null or not is_instance_valid(scope.site) or not scope.site.is_inside_tree() or scope.site.get_world_3d() != scope.world or scope.site.region_id != scope.region_id:
		return false
	if scope.inventory == null or not scope.inventory._is_delivering or not scope.site._is_preparing_or_transacting:
		return false
	for s: ConstructionSite in scope.sites:
		if not is_instance_valid(s) or not s.is_inside_tree() or s.get_world_3d() != scope.world or s.region_id != scope.region_id or not s._is_preparing_or_transacting:
			return false
	if scope.storage != null:
		var domains: Dictionary = scope.world.get_meta(DOMAIN_META, {})
		var authority := domains.get(scope.region_id) as RegionalAuthority
		if (
			authority == null
			or authority != scope.authority
			or not authority.is_executing
			or authority.active_completion != scope
			or authority.active_delivery != null
			or authority.active_camp_delivery != null
			or authority.active_site_creation != null
			or authority.active_manual_complement != null
			or authority.storage == null
			or authority.storage.get_ref() != scope.storage
			or scope.inventory.get_storage_source() != scope.storage
			or not scope.storage._is_preparing_withdrawal
		):
			return false
	return true


static func _acquire_completion_scope(manager: ConstructionManager, site: ConstructionSite) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {"ok": false, "busy": false, "reason": "wrong_thread"}
	if manager == null or not is_instance_valid(manager) or site == null or not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion():
		return {"ok": false, "busy": false, "reason": "invalid_site"}
	var world: World3D = site.get_world_3d()
	var region: StringName = site.region_id
	var inventory: SettlementInventory = site.get_inventory()
	if world == null or not is_instance_valid(world) or not CarryProvenanceLedger._id(region) or region != manager.get_region_id():
		return {"ok": false, "busy": false, "reason": "invalid_domain"}
	if inventory == null or manager.get_inventory() != inventory:
		return {"ok": false, "busy": false, "reason": "invalid_inventory"}
	if inventory.is_transaction_busy():
		return {"ok": false, "busy": true, "reason": "busy"}

	var domain_sites: Array[ConstructionSite] = site._collect_known_other_sites_pure()
	domain_sites.append(site)
	domain_sites.sort_custom(func(left: ConstructionSite, right: ConstructionSite) -> bool:
		if left.site_id == right.site_id:
			return left.get_instance_id() < right.get_instance_id()
		return String(left.site_id) < String(right.site_id))
	for s: ConstructionSite in domain_sites:
		if s.is_transaction_busy():
			return {"ok": false, "busy": true, "reason": "busy"}

	var storage_source: SettlementStorageSource = inventory.get_storage_source()
	if storage_source == null:
		return {"ok": false, "busy": false, "reason": "invalid_inventory"}

	var scope := CompletionScope.new()
	scope.world = world
	scope.region_id = region
	scope.manager = manager
	scope.site = site
	scope.inventory = inventory
	scope.sites = domain_sites

	if storage_source is GroundPileManager:
		var storage: GroundPileManager = storage_source as GroundPileManager
		var domains: Dictionary = world.get_meta(DOMAIN_META, {})
		var authority: RegionalAuthority = domains.get(region) as RegionalAuthority
		if not _matches_economic_domain(site, world, storage, authority):
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		if authority != null and authority.has_active_operation():
			return {"ok": false, "busy": true, "reason": "busy"}
		if (
			_has_active_site_creation_in_domain(world, region)
			or _has_active_site_creation_for_storage(inventory, storage)
			or _has_active_manual_complement_in_domain(world, region)
			or _has_active_manual_complement_for_storage(inventory, storage)
		):
			return {"ok": false, "busy": true, "reason": "busy"}
		if storage.is_locked() or storage.is_batch_active():
			return {"ok": false, "busy": true, "reason": "busy"}
		var camp_zone: CampStorageZone = storage.get_camp_zone()
		if camp_zone != null and is_instance_valid(camp_zone) and camp_zone.is_transaction_locked():
			return {"ok": false, "busy": true, "reason": "busy"}
		if authority == null:
			authority = RegionalAuthority.new()
			authority.storage = weakref(storage)
			domains[region] = authority
			world.set_meta(DOMAIN_META, domains)
			storage._withdrawal_world = weakref(world)
			storage._withdrawal_region = region
		scope.storage = storage
		scope.authority = authority
		authority.is_executing = true
		authority.active_completion = scope
		for s: ConstructionSite in domain_sites:
			s._is_preparing_or_transacting = true
		inventory._is_delivering = true
		storage._is_preparing_withdrawal = true
		return {"ok": true, "busy": false, "scope": scope}

	if is_region_transaction_active_readonly(world, region) or _has_active_site_creation_for_storage(inventory, storage_source) or _has_active_manual_complement_for_storage(inventory, storage_source):
		return {"ok": false, "busy": true, "reason": "busy"}
	for s: ConstructionSite in domain_sites:
		s._is_preparing_or_transacting = true
	inventory._is_delivering = true
	return {"ok": true, "busy": false, "scope": scope}


static func _release_completion_scope(scope: CompletionScope) -> void:
	if scope == null:
		return
	if scope.storage != null:
		scope.storage._is_preparing_withdrawal = false
	if scope.inventory != null:
		scope.inventory._is_delivering = false
	for idx: int in range(scope.sites.size() - 1, -1, -1):
		var s: ConstructionSite = scope.sites[idx]
		if is_instance_valid(s):
			s._is_preparing_or_transacting = false
	if scope.authority != null:
		if scope.authority.active_completion == scope:
			scope.authority.active_completion = null
		scope.authority.is_executing = false


static func _has_active_site_creation_in_domain(world: World3D, region_id: StringName) -> bool:
	if world == null or not is_instance_valid(world) or not CarryProvenanceLedger._id(region_id):
		return false
	for scope: SiteCreationScope in _active_site_creation_scopes:
		if scope != null and scope.world == world and scope.region_id == region_id:
			return true
	return false


static func _has_active_manual_complement_in_domain(world: World3D, region_id: StringName) -> bool:
	if world == null or not is_instance_valid(world) or not CarryProvenanceLedger._id(region_id):
		return false
	for scope: ManualComplementScope in _active_manual_complement_scopes:
		if scope != null and scope.world == world and scope.region_id == region_id:
			return true
	return false


static func _has_active_manual_complement_for_storage(
	inventory: SettlementInventory,
	storage_source: SettlementStorageSource
) -> bool:
	for scope: ManualComplementScope in _active_manual_complement_scopes:
		if scope == null:
			continue
		if (inventory != null and scope.inventory == inventory) or (storage_source != null and scope.storage_source == storage_source):
			return true
	return false


static func _has_active_site_creation_for_storage(
	inventory: SettlementInventory,
	storage_source: SettlementStorageSource
) -> bool:
	for scope: SiteCreationScope in _active_site_creation_scopes:
		if scope == null:
			continue
		if (inventory != null and scope.inventory == inventory) or (storage_source != null and scope.storage_source == storage_source):
			return true
	return false


static func _owns_site_creation_scope(scope: SiteCreationScope) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or scope == null:
		return false
	if not _active_site_creation_scopes.has(scope):
		return false
	if scope.world == null or not is_instance_valid(scope.world) or not CarryProvenanceLedger._id(scope.region_id):
		return false
	if scope.manager == null or not is_instance_valid(scope.manager) or not scope.manager._creation_in_progress:
		return false
	if scope.inventory == null or not scope.inventory._is_delivering or scope.storage_source == null:
		return false
	if scope.inventory.get_storage_source() != scope.storage_source:
		return false
	for s: ConstructionSite in scope.sites:
		if not is_instance_valid(s) or not s._is_preparing_or_transacting:
			return false
	if scope.camp_zone != null:
		if not is_instance_valid(scope.camp_zone) or not scope.camp_zone._coordinator_transaction_locked:
			return false
	if scope.storage != null:
		if not scope.storage._is_preparing_withdrawal:
			return false
	elif scope.storage_source is InMemoryStorageSource:
		if not (scope.storage_source as InMemoryStorageSource)._is_preparing_withdrawal:
			return false
	if scope.authority != null:
		var domains: Dictionary = scope.world.get_meta(DOMAIN_META, {})
		var authority := domains.get(scope.region_id) as RegionalAuthority
		if (
			authority == null
			or authority != scope.authority
			or not authority.is_executing
			or authority.active_site_creation != scope
			or authority.active_delivery != null
			or authority.active_camp_delivery != null
			or authority.active_completion != null
			or authority.active_manual_complement != null
			or authority.storage == null
			or authority.storage.get_ref() != scope.storage
		):
			return false
	return true


static func _acquire_site_creation_scope(manager: ConstructionManager) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {"ok": false, "busy": false, "reason": "wrong_thread"}
	if manager == null or not is_instance_valid(manager) or not manager.is_inside_tree():
		return {"ok": false, "busy": false, "reason": "invalid_sites_root"}
	var sites_root: Node3D = manager._sites_root
	if sites_root == null or not is_instance_valid(sites_root) or not sites_root.is_inside_tree():
		return {"ok": false, "busy": false, "reason": "invalid_sites_root"}
	var world: World3D = sites_root.get_world_3d()
	var tree: SceneTree = sites_root.get_tree()
	var region: StringName = manager.get_region_id()
	var inventory: SettlementInventory = manager.get_inventory()
	if world == null or not is_instance_valid(world) or tree == null or not CarryProvenanceLedger._id(region):
		return {"ok": false, "busy": false, "reason": "invalid_domain"}
	if inventory == null:
		return {"ok": false, "busy": false, "reason": "invalid_inventory"}
	var storage_source: SettlementStorageSource = inventory.get_storage_source()
	if storage_source == null:
		return {"ok": false, "busy": false, "reason": "invalid_inventory"}
	if not (storage_source is GroundPileManager) and not (storage_source is InMemoryStorageSource):
		return {"ok": false, "busy": false, "reason": "unsupported_storage_source"}

	if inventory.is_transaction_busy() or storage_source.is_batch_active():
		return {"ok": false, "busy": true, "reason": "busy"}
	if is_region_transaction_active_readonly(world, region) or _has_active_site_creation_for_storage(inventory, storage_source) or _has_active_manual_complement_for_storage(inventory, storage_source):
		return {"ok": false, "busy": true, "reason": "busy"}

	var peer_sites: Array[ConstructionSite] = []
	var seen_ids: Dictionary = {}
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer := node as ConstructionSite
		if peer == null or not is_instance_valid(peer) or not peer.is_inside_tree():
			continue
		var same_domain: bool = peer.get_world_3d() == world and peer.region_id == region
		var peer_inv: SettlementInventory = peer.get_inventory()
		var shares_backing: bool = peer_inv == inventory or (peer_inv != null and peer_inv.get_storage_source() == storage_source)
		if same_domain or shares_backing:
			var pid: int = peer.get_instance_id()
			if not seen_ids.has(pid):
				seen_ids[pid] = true
				peer_sites.append(peer)
	for managed_site: ConstructionSite in manager._sites:
		if managed_site != null and is_instance_valid(managed_site):
			var mid: int = managed_site.get_instance_id()
			if not seen_ids.has(mid):
				seen_ids[mid] = true
				peer_sites.append(managed_site)
	peer_sites.sort_custom(func(left: ConstructionSite, right: ConstructionSite) -> bool:
		if left.site_id == right.site_id:
			return left.get_instance_id() < right.get_instance_id()
		return String(left.site_id) < String(right.site_id))
	for s: ConstructionSite in peer_sites:
		if s.is_transaction_busy():
			return {"ok": false, "busy": true, "reason": "busy"}

	var camp_zone: CampStorageZone = null
	var storage: GroundPileManager = null
	var authority: RegionalAuthority = null
	if storage_source is GroundPileManager:
		storage = storage_source as GroundPileManager
		if storage.is_shut_down():
			return {"ok": false, "busy": false, "reason": "invalid_domain"}
		if storage.is_locked() or storage.is_batch_active():
			return {"ok": false, "busy": true, "reason": "busy"}
		if not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree() or storage._piles_root.get_world_3d() != world:
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		var domains_raw: Variant = world.get_meta(DOMAIN_META, {})
		var domains: Dictionary = domains_raw as Dictionary if domains_raw is Dictionary else {}
		authority = domains.get(region) as RegionalAuthority
		var bound_world: World3D = storage.get_bound_withdrawal_world()
		var bound_region: StringName = storage.get_bound_withdrawal_region()
		if bound_world != null and (bound_world != world or bound_region != region):
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		if bound_world == null and not bound_region.is_empty():
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		if authority != null:
			if authority.storage == null or authority.storage.get_ref() != storage:
				return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
			for s: ConstructionSite in peer_sites:
				if not s.is_valid():
					continue
				var s_same_domain: bool = s.get_world_3d() == world and s.region_id == region
				var s_inv: SettlementInventory = s.get_inventory()
				var s_storage: SettlementStorageSource = s_inv.get_storage_source() if s_inv != null else null
				if s_same_domain != (s_storage == storage) or (s_same_domain and s_inv != inventory):
					return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
			if authority.has_active_operation():
				return {"ok": false, "busy": true, "reason": "busy"}
		else:
			for other_key: Variant in domains.keys():
				var other_auth: RegionalAuthority = domains.get(other_key) as RegionalAuthority
				if other_auth != null and other_auth.storage != null and other_auth.storage.get_ref() == storage:
					return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		camp_zone = storage.get_camp_zone()
	else:
		var mem_storage: InMemoryStorageSource = storage_source as InMemoryStorageSource
		if mem_storage == null:
			return {"ok": false, "busy": false, "reason": "unsupported_storage_source"}
		if mem_storage.is_locked() or mem_storage.is_batch_active():
			return {"ok": false, "busy": true, "reason": "busy"}
		camp_zone = manager.get_camp_zone()

	if camp_zone != null and is_instance_valid(camp_zone) and camp_zone.is_transaction_locked():
		return {"ok": false, "busy": true, "reason": "busy"}
	var mgr_camp: CampStorageZone = manager.get_camp_zone()
	if mgr_camp != null and is_instance_valid(mgr_camp) and mgr_camp != camp_zone and mgr_camp.is_transaction_locked():
		return {"ok": false, "busy": true, "reason": "busy"}

	var scope := SiteCreationScope.new()
	scope.world = world
	scope.region_id = region
	scope.manager = manager
	scope.inventory = inventory
	scope.storage_source = storage_source
	scope.storage = storage
	scope.camp_zone = camp_zone if (camp_zone != null and is_instance_valid(camp_zone)) else null
	scope.sites = peer_sites
	scope.authority = authority

	if authority != null:
		authority.is_executing = true
		authority.active_site_creation = scope
	_active_site_creation_scopes.append(scope)
	for s: ConstructionSite in peer_sites:
		s._is_preparing_or_transacting = true
	inventory._is_delivering = true
	if storage != null:
		storage._is_preparing_withdrawal = true
	elif storage_source is InMemoryStorageSource:
		(storage_source as InMemoryStorageSource)._is_preparing_withdrawal = true
	if scope.camp_zone != null:
		scope.camp_zone._coordinator_transaction_locked = true
	return {"ok": true, "busy": false, "scope": scope}


static func _release_site_creation_scope(scope: SiteCreationScope) -> void:
	if scope == null:
		return
	if scope.camp_zone != null and is_instance_valid(scope.camp_zone):
		scope.camp_zone._coordinator_transaction_locked = false
	if scope.storage != null:
		scope.storage._is_preparing_withdrawal = false
	elif scope.storage_source is InMemoryStorageSource:
		(scope.storage_source as InMemoryStorageSource)._is_preparing_withdrawal = false
	if scope.inventory != null:
		scope.inventory._is_delivering = false
	if scope.new_site != null and is_instance_valid(scope.new_site):
		scope.new_site._is_preparing_or_transacting = false
	for idx: int in range(scope.sites.size() - 1, -1, -1):
		var s: ConstructionSite = scope.sites[idx]
		if is_instance_valid(s):
			s._is_preparing_or_transacting = false
	_active_site_creation_scopes.erase(scope)
	if scope.authority != null:
		if scope.authority.active_site_creation == scope:
			scope.authority.active_site_creation = null
		scope.authority.is_executing = false


static func _authorize_site_creation_commit(scope: SiteCreationScope) -> bool:
	if not _owns_site_creation_scope(scope):
		return false
	if not scope._reservation_applied or scope._bound_checkpoint.is_empty() \
		or scope._commit_authorized or scope._published or scope._rolled_back or scope._rollback_authorized:
		return false
	var site := scope.new_site
	var manager := scope.manager
	var sites_root := manager._sites_root
	if not is_instance_valid(site) or site.is_queued_for_deletion() or not site.is_inside_tree() \
		or not is_instance_valid(sites_root) or site.get_parent() != sites_root \
		or site.get_world_3d() != scope.world or not manager._sites.has(site):
		return false
	if not site.is_valid() or site.get_site_state() != ConstructionSite.SiteState.ACTIVE \
		or site.site_id != scope._expected_site_id or site.reservation_id != scope._expected_reservation_id \
		or site.region_id != scope.region_id or manager.get_region_id() != scope.region_id \
		or site.get_inventory() != scope.inventory or manager.get_inventory() != scope.inventory \
		or site.definition != scope._expected_definition or scope._expected_costs.is_empty() \
		or site.get_required_amounts() != scope._expected_costs \
		or scope.inventory.get_reservation_amounts(site.reservation_id) != scope._expected_costs:
		return false
	scope._commit_authorized = true
	return true


static func _authorize_site_creation_rollback(scope: SiteCreationScope) -> bool:
	if not _owns_site_creation_scope(scope):
		return false
	if not scope._reservation_applied or scope._published or scope._rolled_back or scope._commit_authorized:
		return false
	scope._rollback_authorized = true
	return true


static func _authorize_manual_complement_commit(scope: ManualComplementScope) -> bool:
	if not _owns_manual_complement_scope(scope):
		return false
	if not scope._complement_applied or scope._published or scope._rolled_back or scope._rollback_authorized:
		return false
	scope._commit_authorized = true
	scope._bound_checkpoint = {}
	return true


static func _authorize_manual_complement_rollback(scope: ManualComplementScope) -> bool:
	if not _owns_manual_complement_scope(scope):
		return false
	if not scope._complement_applied or scope._published or scope._rolled_back or scope._commit_authorized:
		return false
	scope._rollback_authorized = true
	return true


static func _inspect_manual_complement_preconditions_readonly(site: ConstructionSite) -> Dictionary:
	return _inspect_site_mutation_preconditions_readonly(site, true)


static func _inspect_site_mutation_preconditions_readonly(site: ConstructionSite, sort_peers: bool) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {"ok": false, "busy": false, "reason": "wrong_thread"}
	if (
		site == null
		or not is_instance_valid(site)
		or not site.is_valid()
		or site.get_site_state() != ConstructionSite.SiteState.ACTIVE
		or site.get_inventory() == null
		or not site.is_inside_tree()
		or site.is_queued_for_deletion()
	):
		return {"ok": false, "busy": false, "reason": "site_not_active"}
	var world: World3D = site.get_world_3d()
	var tree: SceneTree = site.get_tree()
	var region: StringName = site.region_id
	if world == null or not is_instance_valid(world) or tree == null or not CarryProvenanceLedger._id(region):
		return {"ok": false, "busy": false, "reason": "invalid_domain"}
	if _has_active_work_in_domain(world, region):
		return {"ok": false, "busy": true, "reason": "busy"}
	var inventory: SettlementInventory = site.get_inventory()
	var storage_source: SettlementStorageSource = inventory.get_storage_source()
	if storage_source == null:
		return {"ok": false, "busy": false, "reason": "invalid_inventory"}
	if not (storage_source is GroundPileManager) and not (storage_source is InMemoryStorageSource):
		return {"ok": false, "busy": false, "reason": "unsupported_storage_source"}

	var peer_sites: Array[ConstructionSite] = []
	var seen_ids: Dictionary = {}
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer := node as ConstructionSite
		if peer == null or not is_instance_valid(peer) or not peer.is_inside_tree():
			continue
		var same_domain: bool = peer.get_world_3d() == world and peer.region_id == region
		var peer_inv: SettlementInventory = peer.get_inventory()
		var shares_backing: bool = peer_inv == inventory or (peer_inv != null and peer_inv.get_storage_source() == storage_source)
		if same_domain or shares_backing:
			var pid: int = peer.get_instance_id()
			if not seen_ids.has(pid):
				seen_ids[pid] = true
				peer_sites.append(peer)
	if not seen_ids.has(site.get_instance_id()):
		peer_sites.append(site)
	if sort_peers:
		peer_sites.sort_custom(func(left: ConstructionSite, right: ConstructionSite) -> bool:
			if left.site_id == right.site_id:
				return left.get_instance_id() < right.get_instance_id()
			return String(left.site_id) < String(right.site_id))

	var domains_raw: Variant = world.get_meta(DOMAIN_META, {}) if world.has_meta(DOMAIN_META) else {}
	var domains: Dictionary = domains_raw as Dictionary if domains_raw is Dictionary else {}
	var authority: RegionalAuthority = domains.get(region) as RegionalAuthority
	var storage: GroundPileManager = null
	var camp_zone: CampStorageZone = null

	for s: ConstructionSite in peer_sites:
		if not s.is_valid():
			continue
		if s.get_world_3d() != world:
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		var s_same_domain: bool = s.get_world_3d() == world and s.region_id == region
		var s_inv: SettlementInventory = s.get_inventory()
		var s_storage: SettlementStorageSource = s_inv.get_storage_source() if s_inv != null else null
		if s_same_domain and (s_inv != inventory or s_storage != storage_source):
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		if authority != null and s_same_domain != (s_storage == storage_source):
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}

	if storage_source is GroundPileManager:
		storage = storage_source as GroundPileManager
		if storage.is_shut_down():
			return {"ok": false, "busy": false, "reason": "invalid_domain"}
		if not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree() or storage._piles_root.get_world_3d() != world:
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		var bound_world: World3D = storage.get_bound_withdrawal_world()
		var bound_region: StringName = storage.get_bound_withdrawal_region()
		if bound_world != null and (bound_world != world or bound_region != region):
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		if bound_world == null and not bound_region.is_empty():
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		if authority != null:
			if authority.storage == null or authority.storage.get_ref() != storage:
				return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
			if not _matches_economic_domain(site, world, storage, authority):
				return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		else:
			for other_key: Variant in domains.keys():
				var other_auth: RegionalAuthority = domains.get(other_key) as RegionalAuthority
				if other_auth != null and other_auth.storage != null and other_auth.storage.get_ref() == storage:
					return {"ok": false, "busy": false, "reason": "ambiguous_domain"}
		camp_zone = storage.get_camp_zone()
	else:
		if authority != null:
			return {"ok": false, "busy": false, "reason": "ambiguous_domain"}

	if (
		site.is_transaction_busy()
		or inventory.is_transaction_busy()
		or storage_source.is_batch_active()
		or is_region_transaction_active_readonly(world, region)
		or _has_active_site_creation_for_storage(inventory, storage_source)
		or _has_active_manual_complement_for_storage(inventory, storage_source)
	):
		return {"ok": false, "busy": true, "reason": "busy"}
	if storage != null and (storage.is_locked() or storage.is_batch_active()):
		return {"ok": false, "busy": true, "reason": "busy"}
	if storage_source is InMemoryStorageSource and ((storage_source as InMemoryStorageSource).is_locked() or storage_source.is_batch_active()):
		return {"ok": false, "busy": true, "reason": "busy"}
	if camp_zone != null and is_instance_valid(camp_zone) and camp_zone.is_transaction_locked():
		return {"ok": false, "busy": true, "reason": "busy"}
	for s: ConstructionSite in peer_sites:
		if s.is_transaction_busy():
			return {"ok": false, "busy": true, "reason": "busy"}
	if authority != null and authority.has_active_operation():
		return {"ok": false, "busy": true, "reason": "busy"}

	return {
		"ok": true,
		"busy": false,
		"world": world,
		"region": region,
		"inventory": inventory,
		"storage_source": storage_source,
		"storage": storage,
		"camp_zone": camp_zone if (camp_zone != null and is_instance_valid(camp_zone)) else null,
		"sites": peer_sites,
		"authority": authority,
	}


static func _has_active_work_in_domain(world: World3D, region: StringName) -> bool:
	if world == null:
		return false
	var domains: Variant = world.get_meta(DOMAIN_META, {})
	if not domains is Dictionary:
		return false
	var authority := (domains as Dictionary).get(region) as RegionalAuthority
	return authority != null and authority.active_work != null


static func _acquire_work_scope(site: ConstructionSite) -> Dictionary:
	var pre := _inspect_site_mutation_preconditions_readonly(site, false)
	if not pre.ok:
		return pre
	var world: World3D = pre.world
	var region: StringName = pre.region
	var domains_raw: Variant = world.get_meta(DOMAIN_META, {})
	if not domains_raw is Dictionary:
		return {"ok": false, "reason": "ambiguous_domain"}
	var domains: Dictionary = domains_raw
	var scope := WorkScope.new()
	scope.participants = pre
	scope.had_domain_metadata = world.has_meta(DOMAIN_META)
	scope.authority = pre.authority
	if scope.authority == null:
		# Legacy and in-memory sites only need an authority for this synchronous step.
		scope.temporary_authority = true
		scope.authority = RegionalAuthority.new()
		scope.authority.storage = weakref(pre.storage_source)
		domains[region] = scope.authority
		world.set_meta(DOMAIN_META, domains)
	scope.authority.is_executing = true
	scope.authority.active_work = scope
	_set_work_participant_guards(pre, site, true)
	return {"ok": true, "scope": scope}


static func _set_work_participant_guards(pre: Dictionary, site: ConstructionSite, locked: bool) -> void:
	var peers: Array[ConstructionSite] = pre.sites
	for peer: ConstructionSite in peers:
		if is_instance_valid(peer) and peer != site:
			peer._is_preparing_or_transacting = locked
	var inventory: SettlementInventory = pre.inventory
	inventory._is_delivering = locked
	var storage_source: SettlementStorageSource = pre.storage_source
	if storage_source is GroundPileManager:
		(storage_source as GroundPileManager)._is_preparing_withdrawal = locked
	else:
		(storage_source as InMemoryStorageSource)._is_preparing_withdrawal = locked
	var camp_zone: CampStorageZone = pre.camp_zone
	if is_instance_valid(camp_zone):
		camp_zone._coordinator_transaction_locked = locked


static func _release_work_scope(scope: WorkScope, site: ConstructionSite) -> void:
	if scope.authority.active_work != scope:
		return
	_set_work_participant_guards(scope.participants, site, false)
	scope.authority.active_work = null
	scope.authority.is_executing = false
	if scope.temporary_authority:
		var world: World3D = scope.participants.world
		var region: StringName = scope.participants.region
		var domains: Dictionary = world.get_meta(DOMAIN_META, {})
		if domains.get(region) == scope.authority:
			domains.erase(region)
			if domains.is_empty() and not scope.had_domain_metadata:
				world.remove_meta(DOMAIN_META)


static func _acquire_manual_complement_scope(site: ConstructionSite) -> Dictionary:
	var pre: Dictionary = _inspect_manual_complement_preconditions_readonly(site)
	if not bool(pre.get("ok", false)):
		return pre
	var scope := ManualComplementScope.new()
	scope.world = pre["world"] as World3D
	scope.region_id = pre["region"] as StringName
	scope.site = site
	scope.inventory = pre["inventory"] as SettlementInventory
	scope.storage_source = pre["storage_source"] as SettlementStorageSource
	scope.storage = pre["storage"] as GroundPileManager
	scope.camp_zone = pre["camp_zone"] as CampStorageZone
	scope.sites = pre["sites"] as Array[ConstructionSite]
	scope.authority = pre["authority"] as RegionalAuthority

	if scope.authority != null:
		scope.authority.is_executing = true
		scope.authority.active_manual_complement = scope
	_active_manual_complement_scopes.append(scope)
	for s: ConstructionSite in scope.sites:
		s._is_preparing_or_transacting = true
	scope.inventory._is_delivering = true
	if scope.storage != null:
		scope.storage._is_preparing_withdrawal = true
	elif scope.storage_source is InMemoryStorageSource:
		(scope.storage_source as InMemoryStorageSource)._is_preparing_withdrawal = true
	if scope.camp_zone != null:
		scope.camp_zone._coordinator_transaction_locked = true
	return {"ok": true, "busy": false, "scope": scope}


static func _owns_manual_complement_scope(scope: ManualComplementScope) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or scope == null:
		return false
	if not _active_manual_complement_scopes.has(scope):
		return false
	if scope.world == null or not is_instance_valid(scope.world) or not CarryProvenanceLedger._id(scope.region_id):
		return false
	if (
		scope.site == null
		or not is_instance_valid(scope.site)
		or not scope.site.is_inside_tree()
		or scope.site.get_world_3d() != scope.world
		or scope.site.region_id != scope.region_id
		or not scope.site._is_complementing
		or not scope.site._is_preparing_or_transacting
	):
		return false
	if scope.inventory == null or not scope.inventory._is_delivering or scope.storage_source == null:
		return false
	if scope.site.get_inventory() != scope.inventory or scope.inventory.get_storage_source() != scope.storage_source:
		return false
	for s: ConstructionSite in scope.sites:
		if not is_instance_valid(s) or not s._is_preparing_or_transacting:
			return false
	if scope.camp_zone != null:
		if not is_instance_valid(scope.camp_zone) or not scope.camp_zone._coordinator_transaction_locked:
			return false
	if scope.storage != null:
		if not scope.storage._is_preparing_withdrawal:
			return false
	elif scope.storage_source is InMemoryStorageSource:
		if not (scope.storage_source as InMemoryStorageSource)._is_preparing_withdrawal:
			return false
	else:
		return false
	if scope.authority != null:
		var domains_raw: Variant = scope.world.get_meta(DOMAIN_META, {}) if scope.world.has_meta(DOMAIN_META) else {}
		var domains: Dictionary = domains_raw as Dictionary if domains_raw is Dictionary else {}
		var authority := domains.get(scope.region_id) as RegionalAuthority
		if (
			authority == null
			or authority != scope.authority
			or not authority.is_executing
			or authority.active_manual_complement != scope
			or authority.active_delivery != null
			or authority.active_camp_delivery != null
			or authority.active_completion != null
			or authority.active_site_creation != null
			or authority.storage == null
			or authority.storage.get_ref() != scope.storage
		):
			return false
	return true


static func _release_manual_complement_scope(scope: ManualComplementScope) -> void:
	if scope == null:
		return
	if scope.camp_zone != null and is_instance_valid(scope.camp_zone):
		scope.camp_zone._coordinator_transaction_locked = false
	if scope.storage != null:
		scope.storage._is_preparing_withdrawal = false
	elif scope.storage_source is InMemoryStorageSource:
		(scope.storage_source as InMemoryStorageSource)._is_preparing_withdrawal = false
	if scope.inventory != null:
		scope.inventory._is_delivering = false
	for idx: int in range(scope.sites.size() - 1, -1, -1):
		var s: ConstructionSite = scope.sites[idx]
		if is_instance_valid(s):
			s._is_preparing_or_transacting = false
	_active_manual_complement_scopes.erase(scope)
	if scope.authority != null:
		if scope.authority.active_manual_complement == scope:
			scope.authority.active_manual_complement = null
		scope.authority.is_executing = false


func _resolve_camp_authority(
	world: World3D,
	region_id: StringName,
	inventory: SettlementInventory,
	storage: GroundPileManager,
	tree: SceneTree
) -> Dictionary:
	if world == null or not CarryProvenanceLedger._id(region_id) or inventory == null or storage == null or tree == null:
		return _failure("invalid_domain", "coordinator")
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	var authority: RegionalAuthority = domains.get(region_id) as RegionalAuthority
	var domain_check := _inspect_camp_economic_domain(world, region_id, inventory, storage, authority, domains, tree)
	if not bool(domain_check.get("ok", false)):
		return domain_check
	if authority == null:
		authority = RegionalAuthority.new()
		authority.storage = weakref(storage)
		domains[region_id] = authority
		world.set_meta(DOMAIN_META, domains)
		storage._withdrawal_world = weakref(world)
		storage._withdrawal_region = region_id
	_last_world = weakref(world)
	_last_region = region_id
	return {"ok": true, "authority": authority}


func _resolve_authority(site: ConstructionSite, world: World3D, storage: GroundPileManager) -> RegionalAuthority:
	var region: StringName = site.region_id
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	var authority: RegionalAuthority = domains.get(region) as RegionalAuthority
	if not _matches_economic_domain(site, world, storage, authority):
		return null

	if authority == null:
		authority = RegionalAuthority.new()
		authority.storage = weakref(storage)
		domains[region] = authority
		world.set_meta(DOMAIN_META, domains)
		storage._withdrawal_world = weakref(world)
		storage._withdrawal_region = region
	_last_world = weakref(world)
	_last_region = region
	return authority


## Allocate an intent in the same domain as the two economic coordinators.
## The counter belongs to the world/region, not to the lifetime of an order.
func _allocate_construction_transfer_ids(
	site: ConstructionSite, unit: Unit, order_identity: int, kind: String, pile_id: int, resource_id: StringName
) -> Dictionary:
	if OS.get_thread_caller_id() != _owner_thread_id or _owner_thread_id != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if not is_instance_valid(site) or not site.is_inside_tree() or not site.is_active() \
		or not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _failure("invalid_participant", "coordinator")
	var world := site.get_world_3d()
	var inventory := site.get_inventory()
	var storage := (inventory.get_storage_source() as GroundPileManager) if inventory != null else null
	var load := unit.get_carry_load()
	if world == null or unit.get_world_3d() != world or storage == null or load == null \
		or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(site.region_id):
		return _failure("invalid_domain", "coordinator")
	if is_region_transaction_active_readonly(world, site.region_id):
		return _failure("busy", "coordinator")
	var id_check := validate_unit_identity_in_domain_readonly(world, site.region_id, unit, load, site.get_tree())
	if not bool(id_check.get("ok", false)):
		return _failure(String(id_check.get("reason", "ambiguous_unit_identity")), String(id_check.get("dependency", "unit")))
	var authority := _resolve_authority(site, world, storage)
	if authority == null:
		return _failure("ambiguous_domain", "coordinator")
	if authority.is_executing:
		return _failure("busy", "coordinator")
	if authority.construction_transfer_serial == CarryProvenanceLedger.MAX_INT:
		return _failure("operation_serial_exhausted", "coordinator")
	authority.construction_transfer_serial += 1
	var op := StringName("construct:%d:%d:%s:%d:%d:%d:%d:%s:%d:%s" % [
		world.get_instance_id(), authority.construction_transfer_serial, site.region_id, site.get_instance_id(),
		site.get_generation(), unit.get_instance_id(), order_identity, kind, pile_id, resource_id])
	var lot := StringName("lot:" + String(op)) if kind == "withdrawal" else &""
	var ledger := load._provenance
	if authority.receipts.has(op) or ledger._operations.has(op) \
		or (not lot.is_empty() and (authority.committed_lots.has(lot) or ledger._used_lots.has(lot))):
		return _failure("operation_conflict", "receipt")
	return {"ok": true, "operation_id": op, "lot_id": lot}


## Allocate a unique regional operation_id for an order-initiated selective camp delivery
## using the shared RegionalAuthority serial counter without requiring any ConstructionSite.
func _allocate_camp_delivery_operation_id(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	order_identity: int
) -> Dictionary:
	if OS.get_thread_caller_id() != _owner_thread_id or _owner_thread_id != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "coordinator")
	if order_identity == 0:
		return _failure("invalid_order", "coordinator")
	var region := StringName(region_id)
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _failure("invalid_unit", "coordinator")
	var world := unit.get_world_3d()
	var tree := unit.get_tree()
	if world == null or tree == null:
		return _failure("invalid_domain", "coordinator")
	if inventory == null:
		return _failure("invalid_inventory", "coordinator")
	var storage := inventory.get_storage_source() as GroundPileManager
	if storage == null:
		return _failure("unsupported_storage_source", "storage")
	if (
		camp_zone == null
		or not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
		or camp_zone.max_pile_amount < 0
	):
		return _failure("invalid_camp_zone", "camp_zone")
	if camp_zone.get_world_3d() != world:
		return _failure("world_mismatch", "camp_zone")
	if storage.get_camp_zone() != camp_zone:
		return _failure("invalid_camp_zone", "camp_zone")
	if camp_zone._custom_position_validator.is_valid() or not camp_zone._custom_position_validator.is_null():
		return _failure("unsafe_custom_position_validator", "camp_zone")
	if storage.pile_creator_override.is_valid() or not storage.pile_creator_override.is_null():
		return _failure("unsafe_pile_creator_override", "storage")
	var load := unit.get_carry_load()
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _failure("provenance_disabled", "carry_load")
	if is_region_transaction_active_readonly(world, region):
		return _failure("busy", "coordinator")
	var camp_id_check := validate_unit_identity_in_domain_readonly(world, region, unit, load, tree)
	if not bool(camp_id_check.get("ok", false)):
		return _failure(String(camp_id_check.get("reason", "ambiguous_unit_identity")), String(camp_id_check.get("dependency", "unit")))
	var auth_res := _resolve_camp_authority(world, region, inventory, storage, tree)
	if not bool(auth_res.get("ok", false)):
		return auth_res
	var authority: RegionalAuthority = auth_res["authority"] as RegionalAuthority
	if authority.is_executing:
		return _failure("busy", "coordinator")
	if authority.construction_transfer_serial == CarryProvenanceLedger.MAX_INT:
		return _failure("operation_serial_exhausted", "coordinator")
	authority.construction_transfer_serial += 1
	var op := StringName("camp_delivery:%d:%d:%s:%d:%s:%d:%d:%d" % [
		world.get_instance_id(),
		authority.construction_transfer_serial,
		region,
		camp_zone.get_instance_id(),
		camp_zone.zone_id,
		unit.get_instance_id(),
		load.get_instance_id(),
		order_identity,
	])
	var ledger := load._provenance
	if authority.receipts.has(op) or (ledger != null and ledger._operations.has(op)):
		return _failure("operation_conflict", "receipt")
	return {"ok": true, "operation_id": op}


## Allocate unique regional operation_id and lot_id for one opt-in gather extraction cycle
## using the shared RegionalAuthority serial counter without creating a parallel authority
## or mixing gather receipts into construction receipts.
func _allocate_gather_operation_ids(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	source: ResourceSource,
	unit: Unit,
	region_id: Variant,
	order_identity: int,
	cycle_index: int
) -> Dictionary:
	if OS.get_thread_caller_id() != _owner_thread_id or _owner_thread_id != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "coordinator")
	if order_identity == 0:
		return _failure("invalid_order", "coordinator")
	if cycle_index <= 0:
		return _failure("invalid_cycle", "coordinator")
	var region := StringName(region_id)
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _failure("invalid_unit", "coordinator")
	var world := unit.get_world_3d()
	var tree := unit.get_tree()
	if world == null or tree == null:
		return _failure("invalid_domain", "coordinator")
	if (
		source == null
		or not is_instance_valid(source)
		or not source.is_inside_tree()
		or source.is_queued_for_deletion()
	):
		return _failure("invalid_source", "source")
	if source.get_world_3d() != world:
		return _failure("world_mismatch", "source")
	var source_def: ResourceDefinition = source.get_definition()
	if source_def == null or not source_def.is_valid() or not CarryProvenanceLedger._id(source.source_id):
		return _failure("invalid_source", "source")
	if inventory == null:
		return _failure("invalid_inventory", "coordinator")
	var storage := inventory.get_storage_source() as GroundPileManager
	if storage == null:
		return _failure("unsupported_storage_source", "storage")
	if (
		camp_zone == null
		or not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
	):
		return _failure("invalid_camp_zone", "camp_zone")
	if camp_zone.get_world_3d() != world:
		return _failure("world_mismatch", "camp_zone")
	if storage.get_camp_zone() != camp_zone:
		return _failure("invalid_camp_zone", "camp_zone")
	var load := unit.get_carry_load()
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _failure("provenance_disabled", "carry_load")
	if is_region_transaction_active_readonly(world, region):
		return _failure("busy", "coordinator")
	var camp_id_check := validate_unit_identity_in_domain_readonly(world, region, unit, load, tree)
	if not bool(camp_id_check.get("ok", false)):
		return _failure(String(camp_id_check.get("reason", "ambiguous_unit_identity")), String(camp_id_check.get("dependency", "unit")))
	var auth_res := _resolve_camp_authority(world, region, inventory, storage, tree)
	if not bool(auth_res.get("ok", false)):
		return auth_res
	var authority: RegionalAuthority = auth_res["authority"] as RegionalAuthority
	if authority.is_executing:
		return _failure("busy", "coordinator")
	if authority.construction_transfer_serial == CarryProvenanceLedger.MAX_INT:
		return _failure("operation_serial_exhausted", "coordinator")
	authority.construction_transfer_serial += 1
	var op := StringName("gather:%d:%d:%s:%d:%s:%d:%d:%d:%d" % [
		world.get_instance_id(),
		authority.construction_transfer_serial,
		region,
		source.get_instance_id(),
		source.source_id,
		unit.get_instance_id(),
		load.get_instance_id(),
		order_identity,
		cycle_index,
	])
	var lot := StringName("lot:" + String(op))
	var ledger := load._provenance
	if (
		authority.receipts.has(op)
		or authority.committed_lots.has(lot)
		or (ledger != null and (ledger._operations.has(op) or ledger._used_lots.has(lot)))
		or source._provenance_receipts.has(op)
	):
		return _failure("operation_conflict", "receipt")
	return {"ok": true, "operation_id": op, "lot_id": lot}


## Preconditions: a live site with a world and a physical storage source.
## Reading the domain neither establishes an authority nor reserves an ID.
static func inspect_domain_for_preparation(site: ConstructionSite, storage: GroundPileManager, operation_id: StringName) -> Dictionary:
	var world := site.get_world_3d()
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	var authority: RegionalAuthority = domains.get(site.region_id) as RegionalAuthority
	if not _matches_economic_domain(site, world, storage, authority):
		return _failure("ambiguous_domain", "coordinator")
	if authority != null:
		if authority.is_executing:
			return _failure("busy", "coordinator")
		if authority.receipts.has(operation_id):
			return _failure("operation_conflict", "receipt")
	return {"ok": true}


## Pure read-only domain inspection for camp-level preparation when no specific
## ConstructionSite is required as the entry point. Never creates a RegionalAuthority,
## never writes world metadata, and never consumes a serial or receipt.
static func inspect_camp_domain_for_preparation(
	world: World3D,
	region_id: StringName,
	inventory: SettlementInventory,
	storage: GroundPileManager,
	operation_id: StringName,
	tree: SceneTree
) -> Dictionary:
	if world == null or not CarryProvenanceLedger._id(region_id) or inventory == null or storage == null or tree == null:
		return _failure("invalid_domain", "coordinator")
	var domains: Dictionary = world.get_meta(DOMAIN_META, {})
	var authority: RegionalAuthority = domains.get(region_id) as RegionalAuthority
	var domain_check := _inspect_camp_economic_domain(world, region_id, inventory, storage, authority, domains, tree)
	if not bool(domain_check.get("ok", false)):
		return domain_check
	if authority != null:
		if authority.is_executing:
			return _failure("busy", "coordinator")
		if authority.receipts.has(operation_id):
			return _failure("operation_conflict", "receipt")
	return {"ok": true}


## Pure read-only validation of a unit's economic provenance identity in (world, region_id).
## Checks all live relevant units (not only ConstructionSite participants), detects shared
## UnitCarryLoad instances across live units/receipts, preserves legitimate isolation of
## distinct regions in the same World3D when regional association is proven, and fails closed
## on empty/invalid IDs or ambiguous regional association. Never mutates state or creates authorities.
static func admit_empty_provenance_units(
	units: Array[Unit], units_root: Node3D, camp: CampStorageZone,
	inventory: SettlementInventory, region: StringName
) -> Dictionary:
	if units.is_empty() or not is_instance_valid(units_root) or not units_root.is_inside_tree() or not is_instance_valid(camp) or not camp.is_inside_tree() or not camp.is_valid():
		return _failure("invalid_domain", "admission")
	var world := units_root.get_world_3d()
	var tree := units_root.get_tree()
	var storage := inventory.get_storage_source() as GroundPileManager if inventory != null else null
	if storage == null or camp.get_world_3d() != world or storage.get_camp_zone() != camp:
		return _failure("invalid_domain", "admission")
	if inventory.is_transaction_busy() or storage.is_locked() or storage.is_batch_active() or camp.is_transaction_locked() or is_region_transaction_active_readonly(world, region):
		return _failure("busy", "admission")
	var domain := inspect_camp_domain_for_preparation(world, region, inventory, storage, &"", tree)
	if not domain.ok:
		return domain
	var ids: Dictionary = {}
	var loads: Dictionary = {}
	for unit: Unit in units:
		if not is_instance_valid(unit) or unit.is_queued_for_deletion() or (unit.get_parent() != null and unit.get_parent() != units_root):
			return _failure("invalid_unit", "admission")
		var id := unit.get_character_id()
		var load := unit.get_carry_load()
		if not CarryProvenanceLedger._id(id) or ids.has(id) or loads.has(load):
			return _failure("ambiguous_unit_identity", "admission")
		if load == null or not load._can_enable_provenance(id) or unit.get_current_order() != null:
			return _failure("load_unavailable_for_admission", "admission")
		var identity := _validate_unit_identity_in_domain(world, region, unit, load, tree, id)
		if not identity.ok:
			return identity
		ids[id] = true
		loads[load] = id
	# The apply pass consists of assignments without signals or callbacks.
	for unit: Unit in units:
		unit.get_carry_load()._enable_provenance_unchecked(unit.get_character_id())
		unit.set_meta(&"region_id", region)
	return {"ok": true}


static func validate_unit_identity_in_domain_readonly(
	world: World3D,
	region_id: StringName,
	unit: Unit,
	load: UnitCarryLoad,
	tree: SceneTree
) -> Dictionary:
	return _validate_unit_identity_in_domain(world, region_id, unit, load, tree)


static func _validate_unit_identity_in_domain(
	world: World3D, region_id: StringName, unit: Unit, load: UnitCarryLoad,
	tree: SceneTree, proposed_id: StringName = &""
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {"ok": false, "reason": "wrong_thread", "dependency": "thread"}
	if world == null or not is_instance_valid(world) or not CarryProvenanceLedger._id(region_id) or tree == null or not is_instance_valid(tree):
		return {"ok": false, "reason": "invalid_domain", "dependency": "unit"}
	if not is_instance_valid(unit) or (proposed_id.is_empty() and not unit.is_inside_tree()) or unit.is_queued_for_deletion():
		return {"ok": false, "reason": "invalid_unit", "dependency": "unit"}
	if unit.is_inside_tree() and unit.get_world_3d() != world:
		return {"ok": false, "reason": "unit_world_mismatch", "dependency": "unit"}
	if load == null or unit.get_carry_load() != load:
		return {"ok": false, "reason": "carry_load_mismatch", "dependency": "carry_load"}
	var target_prov_id: StringName = proposed_id if not proposed_id.is_empty() else load.get_provenance_unit_id()
	if not CarryProvenanceLedger._id(target_prov_id) or (proposed_id.is_empty() and not load.is_provenance_enabled()):
		return {"ok": false, "reason": "provenance_disabled", "dependency": "carry_load"}

	var domains: Dictionary = {}
	if world.has_meta(DOMAIN_META):
		var raw_domains: Variant = world.get_meta(DOMAIN_META)
		if raw_domains is Dictionary:
			domains = raw_domains as Dictionary

	# Collect live ConstructionSites in this World3D (read-only).
	var world_sites: Array[ConstructionSite] = []
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		if not (node is ConstructionSite):
			continue
		var s: ConstructionSite = node as ConstructionSite
		if not is_instance_valid(s) or not s.is_inside_tree() or s.is_queued_for_deletion():
			continue
		if s.get_world_3d() == world:
			world_sites.append(s)

	# If target unit carries explicit region_id metadata, it must be valid and match region_id.
	if unit.has_meta(&"region_id"):
		var raw_target_region: Variant = unit.get_meta(&"region_id")
		if not CarryProvenanceLedger._id(raw_target_region) or StringName(raw_target_region) != region_id:
			return {"ok": false, "reason": "ambiguous_unit_identity", "dependency": "unit"}

	# Check committed receipts in this domain for a carry_load previously committed under a different unit.
	var own_auth: RegionalAuthority = domains.get(region_id) as RegionalAuthority
	if own_auth != null:
		for rec_var: Variant in own_auth.receipts.values():
			if not (rec_var is Dictionary):
				continue
			var rec_dict: Dictionary = rec_var as Dictionary
			var rec_load_ref: WeakRef = rec_dict.get("load") as WeakRef
			var rec_unit_ref: WeakRef = rec_dict.get("unit") as WeakRef
			if rec_load_ref != null and rec_load_ref.get_ref() == load:
				if rec_unit_ref != null and rec_unit_ref.get_ref() != null and rec_unit_ref.get_ref() != unit:
					return {"ok": false, "reason": "ambiguous_unit_identity", "dependency": "unit"}

	# Collect all live candidate units in the tree (shared-load check spans all worlds;
	# duplicate provenance_unit_id check spans all live units in this World3D).
	var world_other_units: Array[Unit] = []
	var seen_world_unit_ids: Dictionary = {unit.get_instance_id(): true}
	for node: Node in tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		if not (node is Unit):
			continue
		var other_u: Unit = node as Unit
		if other_u == unit or not is_instance_valid(other_u) or not other_u.is_inside_tree() or other_u.is_queued_for_deletion():
			continue
		var other_load: UnitCarryLoad = other_u.get_carry_load()
		if other_load == load:
			return {"ok": false, "reason": "ambiguous_unit_identity", "dependency": "unit"}
		if other_u.get_world_3d() == world:
			var oid: int = other_u.get_instance_id()
			if not seen_world_unit_ids.has(oid):
				seen_world_unit_ids[oid] = true
				world_other_units.append(other_u)

	# Also include any units referenced in world ConstructionSites even if not yet in GROUP_SELECTABLE_UNITS.
	for s: ConstructionSite in world_sites:
		for bucket: Dictionary in [s._assigned_workers, s._transit_claims, s._pending_pickups]:
			for uid_key: Variant in bucket.keys():
				var entry: Dictionary = bucket[uid_key] as Dictionary
				var site_u: Unit = entry.get("unit") as Unit
				if site_u == null or site_u == unit or not is_instance_valid(site_u):
					continue
				if site_u.get_carry_load() == load:
					return {"ok": false, "reason": "ambiguous_unit_identity", "dependency": "unit"}
				var suid: int = site_u.get_instance_id()
				if not seen_world_unit_ids.has(suid):
					seen_world_unit_ids[suid] = true
					world_other_units.append(site_u)

	# Evaluate duplicate provenance_unit_id among live units in this World3D.
	for other_u: Unit in world_other_units:
		var other_load: UnitCarryLoad = other_u.get_carry_load()
		if other_load == null or not other_load.is_provenance_enabled():
			continue
		if other_load.get_provenance_unit_id() != target_prov_id:
			continue
		# Same provenance_unit_id in the same World3D: allowed ONLY when other_u is provably
		# associated exclusively with a single distinct region (!= region_id).
		var other_proven: Dictionary = _collect_unit_proven_regions_readonly(other_u, other_load, world, world_sites, domains)
		var other_regions: Dictionary = other_proven["regions"] as Dictionary
		if bool(other_proven["has_invalid"]) or other_regions.size() != 1 or other_regions.has(region_id):
			return {"ok": false, "reason": "ambiguous_unit_identity", "dependency": "unit"}

	return {"ok": true, "reason": "", "dependency": ""}


static func _collect_unit_proven_regions_readonly(
	u: Unit,
	u_load: UnitCarryLoad,
	world: World3D,
	world_sites: Array[ConstructionSite],
	domains: Dictionary
) -> Dictionary:
	var regions: Dictionary = {}
	var has_invalid: bool = false

	# 1. Explicit economic region metadata on the unit itself (never guessed from proximity or name).
	if u.has_meta(&"region_id"):
		var raw_meta: Variant = u.get_meta(&"region_id")
		if CarryProvenanceLedger._id(raw_meta):
			regions[StringName(raw_meta)] = true
		else:
			has_invalid = true

	# 2. Active ConstructionSite participation in this World3D.
	var uid: int = u.get_instance_id()
	for s: ConstructionSite in world_sites:
		var participates: bool = false
		if s._assigned_workers.has(uid) and (s._assigned_workers[uid] as Dictionary).get("unit") == u:
			participates = true
		elif s._transit_claims.has(uid) and (s._transit_claims[uid] as Dictionary).get("unit") == u:
			participates = true
		elif s._pending_pickups.has(uid) and (s._pending_pickups[uid] as Dictionary).get("unit") == u:
			participates = true
		if participates:
			if CarryProvenanceLedger._id(s.region_id):
				regions[s.region_id] = true
			else:
				has_invalid = true

	# 3. Active economic order pointing to an explicit region.
	var order: UnitOrder = u.get_current_order()
	if order != null and order.is_active():
		if order is ConstructOrder:
			var c_site: ConstructionSite = (order as ConstructOrder).site
			if c_site != null and is_instance_valid(c_site) and c_site.is_inside_tree() and c_site.get_world_3d() == world:
				if CarryProvenanceLedger._id(c_site.region_id):
					regions[c_site.region_id] = true
				else:
					has_invalid = true
		elif order is DeliverToCampOrder:
			var d_order: DeliverToCampOrder = order as DeliverToCampOrder
			if d_order.use_selective_provenance and CarryProvenanceLedger._id(d_order.region_id):
				regions[d_order.region_id] = true
		elif order is GatherResourceOrder:
			var g_order: GatherResourceOrder = order as GatherResourceOrder
			if g_order.use_provenance_transactions and CarryProvenanceLedger._id(g_order.region_id):
				regions[g_order.region_id] = true

	# 4. Committed receipts recorded under RegionalAuthorities in this World3D.
	for r_key: Variant in domains.keys():
		var auth: RegionalAuthority = domains.get(r_key) as RegionalAuthority
		if auth == null:
			continue
		for rec_var: Variant in auth.receipts.values():
			if not (rec_var is Dictionary):
				continue
			var rec_dict: Dictionary = rec_var as Dictionary
			var rec_u_ref: WeakRef = rec_dict.get("unit") as WeakRef
			var rec_l_ref: WeakRef = rec_dict.get("load") as WeakRef
			if (rec_u_ref != null and rec_u_ref.get_ref() == u) or (u_load != null and rec_l_ref != null and rec_l_ref.get_ref() == u_load):
				regions[StringName(r_key)] = true
				break

	return {"regions": regions, "has_invalid": has_invalid}


## Pure read-only check: returns true if an already-registered RegionalAuthority for
## (world, region_id) is currently executing a transaction or holds an active delivery scope.
## Never creates a RegionalAuthority or writes world metadata.
static func is_region_transaction_active_readonly(world: World3D, region_id: StringName) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return true
	if world == null or not is_instance_valid(world) or not CarryProvenanceLedger._id(region_id):
		return false
	if _has_active_site_creation_in_domain(world, region_id) or _has_active_manual_complement_in_domain(world, region_id):
		return true
	if not world.has_meta(DOMAIN_META):
		return false
	var domains_raw: Variant = world.get_meta(DOMAIN_META)
	if not (domains_raw is Dictionary):
		return false
	var authority: RegionalAuthority = (domains_raw as Dictionary).get(region_id) as RegionalAuthority
	if authority == null:
		return false
	return authority.has_active_operation()


## Pure read-only domain inspection for safe temporary-worker removal.
## Resolves the responsible regional domain without ever creating a RegionalAuthority
## or mutating world metadata, and fails closed on active transactions or domain ambiguity.
static func inspect_domain_for_worker_removal_readonly(
	world: World3D,
	region_id: StringName,
	storage: GroundPileManager,
	camp_zone: CampStorageZone
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return {"ok": false, "reason": "wrong_thread", "resolved_region": &"", "resolved_storage": null}
	if world == null or not is_instance_valid(world):
		return {"ok": false, "reason": "invalid_domain", "resolved_region": &"", "resolved_storage": null}
	if CarryProvenanceLedger._id(region_id) and (_has_active_site_creation_in_domain(world, region_id) or _has_active_manual_complement_in_domain(world, region_id)):
		return {"ok": false, "reason": "regional_transaction_active", "resolved_region": region_id, "resolved_storage": storage}
	for active_sc: SiteCreationScope in _active_site_creation_scopes:
		if active_sc == null or active_sc.world != world:
			continue
		if (
			(storage != null and active_sc.storage == storage)
			or (camp_zone != null and active_sc.camp_zone == camp_zone)
			or (storage == null and camp_zone == null and not CarryProvenanceLedger._id(region_id))
		):
			return {"ok": false, "reason": "regional_transaction_active", "resolved_region": active_sc.region_id, "resolved_storage": active_sc.storage}
	for active_mc: ManualComplementScope in _active_manual_complement_scopes:
		if active_mc == null or active_mc.world != world:
			continue
		if (
			(storage != null and active_mc.storage == storage)
			or (camp_zone != null and active_mc.camp_zone == camp_zone)
			or (storage == null and camp_zone == null and not CarryProvenanceLedger._id(region_id))
		):
			return {"ok": false, "reason": "regional_transaction_active", "resolved_region": active_mc.region_id, "resolved_storage": active_mc.storage}
	if not world.has_meta(DOMAIN_META):
		return {"ok": true, "reason": "", "resolved_region": region_id, "resolved_storage": storage}
	var domains_raw: Variant = world.get_meta(DOMAIN_META)
	if not (domains_raw is Dictionary):
		return {"ok": true, "reason": "", "resolved_region": region_id, "resolved_storage": storage}
	var domains: Dictionary = domains_raw as Dictionary

	if CarryProvenanceLedger._id(region_id):
		var auth: RegionalAuthority = domains.get(region_id) as RegionalAuthority
		var resolved_storage: GroundPileManager = storage
		if auth != null:
			var auth_storage: GroundPileManager = auth.storage.get_ref() as GroundPileManager if auth.storage != null else null
			if storage != null and auth_storage != storage:
				return {"ok": false, "reason": "ambiguous_economic_domain", "resolved_region": region_id, "resolved_storage": null}
			if camp_zone != null and (auth_storage == null or auth_storage.get_camp_zone() != camp_zone):
				return {"ok": false, "reason": "ambiguous_economic_domain", "resolved_region": region_id, "resolved_storage": null}
			if auth.has_active_operation():
				return {"ok": false, "reason": "regional_transaction_active", "resolved_region": region_id, "resolved_storage": auth_storage}
			if resolved_storage == null:
				resolved_storage = auth_storage
		for other_key: Variant in domains.keys():
			var other_region: StringName = StringName(other_key)
			if other_region == region_id:
				continue
			var other_auth: RegionalAuthority = domains.get(other_key) as RegionalAuthority
			if other_auth == null or other_auth.storage == null:
				continue
			var other_storage: GroundPileManager = other_auth.storage.get_ref() as GroundPileManager
			if other_storage == null:
				continue
			if (resolved_storage != null and other_storage == resolved_storage) or (camp_zone != null and other_storage.get_camp_zone() == camp_zone):
				return {"ok": false, "reason": "ambiguous_economic_domain", "resolved_region": region_id, "resolved_storage": null}
		return {"ok": true, "reason": "", "resolved_region": region_id, "resolved_storage": resolved_storage}

	var matched_regions: Array[StringName] = []
	var matched_authorities: Array[RegionalAuthority] = []
	var matched_storages: Array[GroundPileManager] = []
	var any_executing: bool = false
	for key: Variant in domains.keys():
		var cand_region: StringName = StringName(key)
		var cand_auth: RegionalAuthority = domains.get(key) as RegionalAuthority
		if cand_auth == null:
			continue
		if cand_auth.has_active_operation():
			any_executing = true
		var cand_storage: GroundPileManager = cand_auth.storage.get_ref() as GroundPileManager if cand_auth.storage != null else null
		if cand_storage == null:
			continue
		var matches: bool = false
		if storage != null:
			matches = cand_storage == storage
		elif camp_zone != null:
			matches = cand_storage.get_camp_zone() == camp_zone
		if matches:
			matched_regions.append(cand_region)
			matched_authorities.append(cand_auth)
			matched_storages.append(cand_storage)

	if matched_regions.size() > 1:
		return {"ok": false, "reason": "ambiguous_economic_domain", "resolved_region": &"", "resolved_storage": null}
	if matched_regions.size() == 1:
		var only_auth: RegionalAuthority = matched_authorities[0]
		if only_auth.has_active_operation():
			return {"ok": false, "reason": "regional_transaction_active", "resolved_region": matched_regions[0], "resolved_storage": matched_storages[0]}
		return {"ok": true, "reason": "", "resolved_region": matched_regions[0], "resolved_storage": matched_storages[0]}
	if storage == null and camp_zone == null and any_executing:
		return {"ok": false, "reason": "regional_transaction_active", "resolved_region": &"", "resolved_storage": null}
	return {"ok": true, "reason": "", "resolved_region": &"", "resolved_storage": storage}


## Controlled release of a RegionalAuthority binding when its owning economic session ends.
## Requires the legitimate storage owner capability token, exact (World3D, region_id, storage)
## correspondence, no active transaction/scope, and verified session shutdown.
## Never creates a RegionalAuthority or modifies unrelated regions or storages.
static func release_regional_domain(
	world: World3D,
	region_id: Variant,
	storage: GroundPileManager,
	owner_token: RefCounted,
	tree: SceneTree,
	inventory: SettlementInventory = null
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _release_result(false, false, "wrong_thread", &"")
	if world == null or not is_instance_valid(world):
		return _release_result(false, false, "invalid_world", &"")
	if not CarryProvenanceLedger._id(region_id):
		return _release_result(false, false, "invalid_region", &"")
	var region: StringName = StringName(region_id)
	if storage == null:
		return _release_result(false, false, "invalid_storage", region)
	if tree == null or not is_instance_valid(tree):
		return _release_result(false, false, "invalid_tree", region)
	if owner_token == null or not storage.verify_domain_owner(owner_token):
		return _release_result(false, false, "unauthorized_owner", region)
	if (
		storage.is_locked()
		or storage.is_batch_active()
		or (inventory != null and inventory.is_transaction_busy())
		or _has_active_site_creation_in_domain(world, region)
		or _has_active_site_creation_for_storage(inventory, storage)
		or _has_active_manual_complement_in_domain(world, region)
		or _has_active_manual_complement_for_storage(inventory, storage)
	):
		return _release_result(false, false, "busy", region)

	var bound_world: World3D = storage.get_bound_withdrawal_world()
	var bound_region: StringName = storage.get_bound_withdrawal_region()
	if bound_world != null and bound_world != world:
		return _release_result(false, false, "world_mismatch", region)
	if bound_world == null and not bound_region.is_empty():
		return _release_result(false, false, "world_mismatch", region)
	if not bound_region.is_empty() and bound_region != region:
		return _release_result(false, false, "region_mismatch", region)

	var domains_raw: Variant = world.get_meta(DOMAIN_META) if world.has_meta(DOMAIN_META) else null
	if not (domains_raw is Dictionary):
		if bound_world == world and bound_region == region:
			var partial_err: String = _validate_storage_shutdown_for_release(world, region, storage, tree)
			if not partial_err.is_empty():
				return _release_result(false, false, partial_err, region)
			storage._withdrawal_world = null
			storage._withdrawal_region = &""
			storage._is_shut_down = true
		return _release_result(true, false, "not_bound", region)

	var domains: Dictionary = domains_raw as Dictionary
	var authority: RegionalAuthority = domains.get(region) as RegionalAuthority
	if authority == null:
		for other_key: Variant in domains.keys():
			var other_auth: RegionalAuthority = domains.get(other_key) as RegionalAuthority
			if other_auth != null and other_auth.storage != null and other_auth.storage.get_ref() == storage:
				return _release_result(false, false, "region_mismatch", region)
		if bound_world == world and bound_region == region:
			var partial_err: String = _validate_storage_shutdown_for_release(world, region, storage, tree)
			if not partial_err.is_empty():
				return _release_result(false, false, partial_err, region)
			storage._withdrawal_world = null
			storage._withdrawal_region = &""
			storage._is_shut_down = true
		return _release_result(true, false, "not_bound", region)

	if authority.storage == null or authority.storage.get_ref() != storage:
		return _release_result(false, false, "storage_mismatch", region)
	if bound_world != world or bound_region != region:
		return _release_result(false, false, "domain_binding_mismatch", region)
	if authority.has_active_operation():
		return _release_result(false, false, "busy", region)

	var shutdown_err: String = _validate_storage_shutdown_for_release(world, region, storage, tree)
	if not shutdown_err.is_empty():
		return _release_result(false, false, shutdown_err, region)

	domains.erase(region)
	if domains.is_empty():
		world.remove_meta(DOMAIN_META)
	else:
		world.set_meta(DOMAIN_META, domains)
	storage._withdrawal_world = null
	storage._withdrawal_region = &""
	storage._is_shut_down = true
	return _release_result(true, true, "", region)


static func _validate_storage_shutdown_for_release(
	world: World3D,
	region: StringName,
	storage: GroundPileManager,
	tree: SceneTree
) -> String:
	if is_instance_valid(storage._piles_root) and storage._piles_root.is_inside_tree():
		return "session_still_active"
	var camp_zone: CampStorageZone = storage.get_camp_zone()
	if camp_zone != null and is_instance_valid(camp_zone) and camp_zone.is_inside_tree():
		return "session_still_active"
	if not storage.get_piles().is_empty() or not storage.get_all_reservation_ids().is_empty():
		return "storage_not_cleaned_up"
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer: ConstructionSite = node as ConstructionSite
		if peer == null or not is_instance_valid(peer) or not peer.is_inside_tree():
			continue
		var peer_inv: SettlementInventory = peer.get_inventory()
		var peer_storage: SettlementStorageSource = peer_inv.get_storage_source() if peer_inv != null else null
		var same_domain: bool = peer.get_world_3d() == world and peer.region_id == region
		if peer_storage == storage or (same_domain and peer.is_valid()):
			return "active_sites_present"
	return ""


static func _release_result(ok: bool, released: bool, reason: String, region: StringName) -> Dictionary:
	return {
		"ok": ok,
		"released": released,
		"reason": reason,
		"region_id": region,
	}


static func _inspect_camp_economic_domain(
	world: World3D,
	region: StringName,
	inventory: SettlementInventory,
	storage: GroundPileManager,
	authority: RegionalAuthority,
	domains: Dictionary,
	tree: SceneTree
) -> Dictionary:
	if storage.is_shut_down():
		return _failure("storage_shut_down", "storage")
	if authority != null and authority.storage.get_ref() != storage:
		return _failure("ambiguous_domain", "coordinator")
	var bound_world: World3D = storage._withdrawal_world.get_ref() as World3D if storage._withdrawal_world != null else null
	if bound_world != null:
		if bound_world != world:
			return _failure("world_mismatch", "storage")
		if storage._withdrawal_region != region:
			return _failure("region_mismatch", "storage")
	if not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree():
		return _failure("invalid_piles_root", "storage")
	if storage._piles_root.get_world_3d() != world:
		return _failure("world_mismatch", "storage")

	for other_region: Variant in domains.keys():
		if StringName(other_region) == region:
			continue
		var other_auth: RegionalAuthority = domains.get(other_region) as RegionalAuthority
		if other_auth != null and other_auth.storage.get_ref() == storage:
			return _failure("region_mismatch", "coordinator")

	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer := node as ConstructionSite
		if peer == null or not peer.is_valid():
			continue
		var peer_inventory := peer.get_inventory()
		var peer_storage := peer_inventory.get_storage_source() if peer_inventory != null else null
		var same_domain: bool = peer.region_id == region and peer.get_world_3d() == world
		if same_domain != (peer_storage == storage) or (same_domain and peer_inventory != inventory):
			if peer_storage == storage and peer.get_world_3d() != world:
				return _failure("world_mismatch", "coordinator")
			if peer_storage == storage and peer.region_id != region:
				return _failure("region_mismatch", "coordinator")
			return _failure("ambiguous_domain", "coordinator")

	return {"ok": true}


static func _matches_economic_domain(site: ConstructionSite, world: World3D, storage: GroundPileManager, authority: RegionalAuthority) -> bool:
	if storage.is_shut_down():
		return false
	var region := site.region_id
	if authority != null and authority.storage.get_ref() != storage:
		return false
	var bound_world: World3D = storage._withdrawal_world.get_ref() as World3D if storage._withdrawal_world != null else null
	if bound_world != null and (bound_world != world or storage._withdrawal_region != region):
		return false
	if not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree() or storage._piles_root.get_world_3d() != world:
		return false

	# Refuse conflicting live site bindings before assigning an authority.
	for node: Node in site.get_tree().get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer := node as ConstructionSite
		if peer == null or not peer.is_valid():
			continue
		var peer_inventory := peer.get_inventory()
		var peer_storage := peer_inventory.get_storage_source()
		var same_domain: bool = peer.region_id == region and peer.get_world_3d() == world
		if same_domain != (peer_storage == storage) or (same_domain and peer_inventory != site.get_inventory()):
			return false

	return true


func execute_reserved_withdrawal(
	site: Variant,
	unit: Variant,
	pile_id: Variant,
	resource_id: Variant,
	requested_amount: Variant,
	operation_id: Variant,
	lot_id: Variant,
	options: Dictionary = {}
) -> Dictionary:
	return _execute_core(
		site,
		unit,
		pile_id,
		resource_id,
		requested_amount,
		operation_id,
		lot_id,
		options
	)


func commit_prepared_withdrawal(
	site: Variant,
	unit: Variant,
	prepared_plan: Variant,
	options: Dictionary = {}
) -> Dictionary:
	if OS.get_thread_caller_id() != _owner_thread_id or _owner_thread_id != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if _handle_executing:
		return _failure("busy", "coordinator")
	if not (site is ConstructionSite) or not is_instance_valid(site):
		return _failure("invalid_site", "site")
	var typed_site: ConstructionSite = site as ConstructionSite
	var shape: Dictionary = ConstructionSite._validate_plan_shape_pure(prepared_plan, typed_site.get_instance_id())
	if not bool(shape.get("ok", false)):
		return _prep_to_failure(shape)
	var p: Dictionary = prepared_plan as Dictionary
	var opts: Dictionary = options.duplicate()
	opts["prepared_plan"] = p
	return _execute_core(
		site,
		unit,
		p["pile_id"],
		p["resource_id"],
		p["requested_amount"],
		p["operation_id"],
		p["lot_id"],
		opts
	)


func _execute_core(
	site: Variant,
	unit: Variant,
	pile_id: Variant,
	resource_id: Variant,
	requested_amount: Variant,
	operation_id: Variant,
	lot_id: Variant,
	options: Dictionary
) -> Dictionary:
	if OS.get_thread_caller_id() != _owner_thread_id or _owner_thread_id != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if _handle_executing:
		return _failure("busy", "coordinator")

	if not CarryProvenanceLedger._id(operation_id):
		return _failure("invalid_operation", "input")
	if not CarryProvenanceLedger._id(lot_id):
		return _failure("invalid_lot", "input")
	if not (site is ConstructionSite) or not is_instance_valid(site):
		return _failure("invalid_site", "site")
	if not (unit is Unit) or not is_instance_valid(unit):
		return _failure("invalid_unit", "unit")
	if not CarryProvenanceLedger._id(resource_id):
		return _failure("invalid_resource", "input")
	if typeof(pile_id) != TYPE_INT or int(pile_id) <= 0:
		return _failure("invalid_pile", "input")
	if typeof(requested_amount) != TYPE_INT or int(requested_amount) <= 0:
		return _failure("invalid_amount", "input")
	if options.has("require_assigned_worker"):
		if typeof(options["require_assigned_worker"]) != TYPE_BOOL:
			return _failure("invalid_worker_requirement", "input")
		if not bool(options["require_assigned_worker"]):
			return _failure("physical_authorization_required", "policy")

	var typed_site: ConstructionSite = site as ConstructionSite
	var typed_unit: Unit = unit as Unit
	var op_id_sn := StringName(operation_id)
	var lot_id_sn := StringName(lot_id)
	var res_id_sn := StringName(resource_id)
	var pile_id_int: int = int(pile_id)
	var req_amount: int = int(requested_amount)

	if not typed_site.is_inside_tree() or not CarryProvenanceLedger._id(typed_site.region_id):
		return _failure("invalid_domain", "coordinator")
	var world := typed_site.get_world_3d()
	if world == null:
		return _failure("invalid_domain", "coordinator")
	var inventory := typed_site.get_inventory()
	var storage_source := inventory.get_storage_source() if inventory != null else null
	var storage := storage_source as GroundPileManager
	if storage == null:
		return _failure("unsupported_storage_source", "storage")
	if (
		_has_active_site_creation_in_domain(world, typed_site.region_id)
		or _has_active_site_creation_for_storage(inventory, storage)
		or _has_active_manual_complement_in_domain(world, typed_site.region_id)
		or _has_active_manual_complement_for_storage(inventory, storage)
	):
		return _failure("busy", "coordinator")
	var authority := _resolve_authority(typed_site, world, storage)
	if authority == null:
		return _failure("ambiguous_domain", "coordinator")
	if authority.is_executing:
		return _failure("busy", "coordinator")

	# 1. Idempotent replay & conflict detection by committed operation_id / lot_id.
	if authority.receipts.has(op_id_sn):
		var record: Variant = authority.receipts[op_id_sn]
		var receipt := _read_receipt(record, op_id_sn, RECEIPT_WITHDRAWAL)
		if receipt.is_empty() or record.site.get_ref() != typed_site or record.unit.get_ref() != typed_unit or record.load.get_ref() != typed_unit.get_carry_load():
			return _failure("operation_conflict", "receipt")
		return _evaluate_receipt_replay(
			receipt,
			typed_site,
			typed_unit,
			pile_id_int,
			res_id_sn,
			req_amount,
			lot_id_sn,
			options
		)
	if authority.committed_lots.has(lot_id_sn):
		return _failure("duplicate_lot", "receipt")

	# 2. Check busy participants before locking.
	if typed_site.is_transaction_busy():
		return _failure("busy", "site")
	if inventory != null and inventory.is_transaction_busy():
		return _failure("busy", "inventory")
	if storage_source != null and storage_source.is_batch_active():
		return _failure("busy", "storage")
	if storage_source is GroundPileManager and (storage_source as GroundPileManager).is_locked():
		return _failure("busy", "storage")
	var pre_cl: UnitCarryLoad = typed_unit.get_carry_load()
	if pre_cl != null and pre_cl.is_transaction_busy():
		return _failure("busy", "carry_load")
	if options.has("carry_load") and options["carry_load"] is UnitCarryLoad:
		if (options["carry_load"] as UnitCarryLoad).is_transaction_busy():
			return _failure("busy", "carry_load")

	var peer_sites: Array[ConstructionSite] = typed_site._collect_known_other_sites_pure()
	for peer: ConstructionSite in peer_sites:
		if peer.is_transaction_busy():
			return _failure("busy", "peer_site")

	# 3. Validate participant structural readiness before acquiring cooperative locks.
	var pre_parsed: Dictionary = typed_site._validate_prepare_preconditions_and_parse(
		typed_unit,
		pile_id_int,
		res_id_sn,
		req_amount,
		op_id_sn,
		lot_id_sn,
		options
	)
	if not bool(pre_parsed.get("ok", false)):
		return _prep_to_failure(pre_parsed)

	var pile_manager: GroundPileManager = pre_parsed["pile_manager"] as GroundPileManager
	var carry_load: UnitCarryLoad = pre_parsed["carry_load"] as UnitCarryLoad

	# 4. Acquire cooperative guards in strict R2 order:
	#    (1) coordinator -> site (+ region/world peer sites) -> (2) inventory -> storage -> (3) carry_load
	authority.is_executing = true
	_handle_executing = true
	typed_site._is_preparing_or_transacting = true
	var locked_peers: Array[ConstructionSite] = []
	for peer: ConstructionSite in peer_sites:
		peer._is_preparing_or_transacting = true
		locked_peers.append(peer)
	inventory._is_delivering = true
	pile_manager._is_preparing_withdrawal = true
	carry_load._provenance_busy = true
	carry_load._coordinator_transaction_locked = true

	var reval_opts: Dictionary = options.duplicate()
	reval_opts["require_assigned_worker"] = true
	reval_opts.erase("prepared_plan")
	reval_opts.erase("prior_plan")

	if options.has("prior_plan"):
		var prior_check: Dictionary = typed_site._validate_plan_under_coordinator_guards(
			typed_unit,
			options["prior_plan"],
			reval_opts
		)
		if not bool(prior_check.get("ok", false)):
			_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
			return _prep_to_failure(prior_check)

	if options.has("prepared_plan"):
		var plan_check: Dictionary = typed_site._validate_plan_under_coordinator_guards(
			typed_unit,
			options["prepared_plan"],
			reval_opts
		)
		if not bool(plan_check.get("ok", false)):
			_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
			return _prep_to_failure(plan_check)

	var fresh_plan: Dictionary = typed_site._prepare_reserved_withdrawal_under_coordinator_guards(
		typed_unit,
		pile_id_int,
		res_id_sn,
		req_amount,
		op_id_sn,
		lot_id_sn,
		reval_opts
	)
	if not bool(fresh_plan.get("ok", false)):
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _prep_to_failure(fresh_plan)

	# 5. Enforce mandatory C2 physical authorization under guards:
	#    registered transporter/solo worker + matching active pending pickup + physical pile reach.
	var uid: int = typed_unit.get_instance_id()
	if not typed_site._pending_pickups.has(uid):
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("claim_not_eligible", "claims")
	var pending_entry: Dictionary = typed_site._pending_pickups[uid] as Dictionary
	if (
		pending_entry.get("unit") != typed_unit
		or int(pending_entry.get("pile_id", 0)) != pile_id_int
		or (pending_entry.get("resource_id") as StringName) != res_id_sn
		or int(pending_entry.get("amount", 0)) < req_amount
	):
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("claim_not_eligible", "claims")

	var pile: GroundResourcePile = pile_manager.get_pile_by_id(pile_id_int)
	if pile == null or not is_instance_valid(pile) or not pile.is_inside_tree():
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("invalid_or_missing_pile", "pile")
	if pile.get_world_3d() != typed_site.get_world_3d():
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("pile_world_mismatch", "pile")
	var live_pile_pos: Vector3 = pile_manager.get_pile_world_position(pile)
	if not BuildSlotPlanner.is_unit_in_pile_reach(
		typed_unit.global_position,
		live_pile_pos,
		ConstructionSite.DEFAULT_PILE_PICKUP_REACH,
		typed_site.get_world_3d()
	):
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("out_of_pile_reach", "reach")

	# 6. Capture full pre-mutation checkpoints and accounting baselines.
	var pile_ckpt: Dictionary = pile_manager._capture_pile_withdrawal_checkpoint(pile_id_int)
	var carry_ckpt: Dictionary = carry_load._capture_provenance_checkpoint()
	var claim_ckpt: Dictionary = typed_site._capture_claim_checkpoint(uid)

	var reserved_before: int = typed_site.get_reserved_in_piles_amount(res_id_sn)
	var in_transit_before: int = typed_site._read_in_transit_amount_pure(res_id_sn)
	var buffer_before: Dictionary = typed_site.get_delivered_buffer_amounts()
	var consumed_before: Dictionary = typed_site.get_consumed_amounts()
	var missing_before: Dictionary = typed_site.get_missing_amounts()

	var hook_ctx: Dictionary = {
		"operation_id": op_id_sn,
		"lot_id": lot_id_sn,
		"site": typed_site,
		"unit": typed_unit,
		"pile_id": pile_id_int,
		"pile": pile,
		"resource_id": res_id_sn,
		"requested_amount": req_amount,
		"pile_manager": pile_manager,
		"inventory": inventory,
		"carry_load": carry_load,
		"plan": fresh_plan,
	}

	# Fault injection point 1: before physical deduction.
	if _should_abort_at_stage("before_pile_deduction", hook_ctx):
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("aborted_before_pile_deduction", "fault_injection")

	# Stage A: Silent pile & reservation deduction (node removal deferred if amount reaches 0).
	var pile_apply: Dictionary = pile_manager._apply_prepared_pile_withdrawal_silent(
		fresh_plan["pile_plan"] as Dictionary,
		pile_ckpt
	)
	if not bool(pile_apply.get("ok", false)):
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure(String(pile_apply.get("reason", "pile_apply_failed")), "pile")

	# Fault injection point 2: after physical deduction, before carry load / provenance.
	if _should_abort_at_stage("after_pile_deduction", hook_ctx):
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("aborted_after_pile_deduction", "fault_injection")

	# Stage B: Silent carry load & provenance ledger mutation.
	carry_load._provenance_applying = true
	var carry_ok: bool = carry_load._apply_prepared_provenance_add(
		(fresh_plan["carry_plan"] as Dictionary)["raw_add_plan"] as Dictionary
	)
	carry_load._provenance_applying = false
	if not carry_ok:
		carry_load._restore_provenance_checkpoint_silent(carry_ckpt)
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("carry_apply_failed", "carry_load")

	# Fault injection point 3: after carry load / provenance, before claim update.
	if _should_abort_at_stage("after_carry_add", hook_ctx):
		carry_load._restore_provenance_checkpoint_silent(carry_ckpt)
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("aborted_after_carry_add", "fault_injection")

	# Stage C: Silent construction site transit claim & pending pickup update.
	var claim_ok: bool = typed_site._apply_prepared_claim_silent(
		typed_unit,
		carry_load,
		res_id_sn,
		req_amount,
		fresh_plan["claim_plan"] as Dictionary,
		claim_ckpt
	)
	if not claim_ok:
		typed_site._restore_claim_checkpoint_silent(claim_ckpt)
		carry_load._restore_provenance_checkpoint_silent(carry_ckpt)
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("claim_apply_failed", "claims")

	# Fault injection point 4: after claim update, before final invariant check.
	if _should_abort_at_stage("after_claim_update", hook_ctx):
		typed_site._restore_claim_checkpoint_silent(claim_ckpt)
		carry_load._restore_provenance_checkpoint_silent(carry_ckpt)
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("aborted_after_claim_update", "fault_injection")

	# Fault injection point 5 & full post-mutation invariant verification.
	if _should_abort_at_stage("during_final_invariants", hook_ctx):
		typed_site._restore_claim_checkpoint_silent(claim_ckpt)
		carry_load._restore_provenance_checkpoint_silent(carry_ckpt)
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("aborted_during_final_invariants", "fault_injection")

	var invariants_ok: bool = _verify_post_mutation_invariants(
		typed_site,
		typed_unit,
		pile,
		pile_manager,
		carry_load,
		pile_id_int,
		res_id_sn,
		req_amount,
		fresh_plan,
		reserved_before,
		in_transit_before,
		buffer_before,
		consumed_before,
		missing_before
	)
	if not invariants_ok:
		typed_site._restore_claim_checkpoint_silent(claim_ckpt)
		carry_load._restore_provenance_checkpoint_silent(carry_ckpt)
		pile_manager._restore_pile_withdrawal_checkpoint_silent(pile_ckpt)
		_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)
		return _failure("invariant_violation_aborted", "invariants")

	# 7. Record the receipt before any visual or scene-tree callbacks.
	inventory._transaction_revision += 1
	var receipt: Dictionary = {
		"kind": RECEIPT_WITHDRAWAL,
		"operation_id": op_id_sn,
		"lot_id": lot_id_sn,
		"site_instance_id": typed_site.get_instance_id(),
		"site_id": typed_site.site_id,
		"generation": typed_site.get_generation(),
		"reservation_id": typed_site.reservation_id,
		"region_id": typed_site.region_id,
		"world_instance_id": typed_site.get_world_3d().get_instance_id() if typed_site.is_inside_tree() and typed_site.get_world_3d() != null else 0,
		"pile_id": pile_id_int,
		"pile_instance_id": int(fresh_plan["pile_instance_id"]),
		"resource_id": res_id_sn,
		"unit_weight": int(fresh_plan["unit_weight"]),
		"requested_amount": req_amount,
		"committed_amount": req_amount,
		"unit_instance_id": typed_unit.get_instance_id(),
		"carry_load_instance_id": carry_load.get_instance_id(),
		"unit_id": fresh_plan["unit_id"],
	}
	authority.receipts[op_id_sn] = {
		"receipt": receipt,
		"site": weakref(typed_site),
		"unit": weakref(typed_unit),
		"load": weakref(carry_load),
	}
	authority.committed_lots[lot_id_sn] = op_id_sn

	# 8. Publish consistent signals with reentrancy guards still active so all
	#    observers inspect identical final values and cannot re-enter mutators.
	typed_site._suppress_coordinator_signal_echo = true
	for peer: ConstructionSite in locked_peers:
		peer._suppress_coordinator_signal_echo = true

	if pile.amount <= 0:
		pile_manager._finalize_exhausted_pile_after_commit_silent(pile)
	else:
		pile._sync_visual_committed_state()

	# Revisions were advanced by the commit before publishing any callback.
	pile_manager._dispatch_reservations_changed()
	pile_manager._dispatch_storage_changed()
	carry_load.load_changed.emit()

	typed_site.state_changed.emit(typed_site)
	for peer: ConstructionSite in locked_peers:
		if is_instance_valid(peer):
			peer._suppress_coordinator_signal_echo = false
	if is_instance_valid(typed_site):
		typed_site._suppress_coordinator_signal_echo = false

	# 9. Release guards in strict reverse order.
	_release_guards(authority, typed_site, locked_peers, inventory, pile_manager, carry_load)

	return {
		"ok": true,
		"reason": "",
		"dependency": "",
		"replayed": false,
		"withdrawn": req_amount,
		"committed_amount": req_amount,
		"receipt": receipt.duplicate(true),
	}


func _evaluate_receipt_replay(
	rec: Dictionary,
	typed_site: ConstructionSite,
	typed_unit: Unit,
	pile_id_int: int,
	res_id_sn: StringName,
	req_amount: int,
	lot_id_sn: StringName,
	options: Dictionary
) -> Dictionary:
	var unit_load: UnitCarryLoad = typed_unit.get_carry_load()
	var world_id: int = typed_site.get_world_3d().get_instance_id() if typed_site.is_inside_tree() and typed_site.get_world_3d() != null else 0
	if (
		typed_site.get_instance_id() != int(rec["site_instance_id"])
		or typed_site.site_id != (rec["site_id"] as StringName)
		or typed_site.get_generation() != int(rec["generation"])
		or typed_site.reservation_id != (rec["reservation_id"] as StringName)
		or typed_site.region_id != (rec["region_id"] as StringName)
		or world_id != int(rec["world_instance_id"])
		or pile_id_int != int(rec["pile_id"])
		or res_id_sn != (rec["resource_id"] as StringName)
		or req_amount != int(rec["requested_amount"])
		or lot_id_sn != (rec["lot_id"] as StringName)
		or typed_unit.get_instance_id() != int(rec["unit_instance_id"])
		or unit_load == null
		or unit_load.get_instance_id() != int(rec["carry_load_instance_id"])
		or unit_load.get_provenance_unit_id() != (rec["unit_id"] as StringName)
	):
		return _failure("operation_conflict", "receipt")

	if options.has("site_id") and (not CarryProvenanceLedger._id(options["site_id"]) or StringName(options["site_id"]) != (rec["site_id"] as StringName)):
		return _failure("operation_conflict", "receipt")
	if options.has("generation") and (typeof(options["generation"]) != TYPE_INT or int(options["generation"]) != int(rec["generation"])):
		return _failure("operation_conflict", "receipt")
	if options.has("reservation_id") and (not CarryProvenanceLedger._id(options["reservation_id"]) or StringName(options["reservation_id"]) != (rec["reservation_id"] as StringName)):
		return _failure("operation_conflict", "receipt")
	if options.has("unit_id") and (not CarryProvenanceLedger._id(options["unit_id"]) or StringName(options["unit_id"]) != (rec["unit_id"] as StringName)):
		return _failure("operation_conflict", "receipt")
	if options.has("unit_weight") and (typeof(options["unit_weight"]) != TYPE_INT or int(options["unit_weight"]) != int(rec["unit_weight"])):
		return _failure("operation_conflict", "receipt")
	if options.has("carry_load") and options["carry_load"] != unit_load:
		return _failure("operation_conflict", "receipt")

	if options.has("prepared_plan"):
		var pp: Variant = options["prepared_plan"]
		if not (pp is Dictionary):
			return _failure("operation_conflict", "receipt")
		var pd: Dictionary = pp as Dictionary
		if (
			StringName(pd.get("operation_id", &"")) != (rec["operation_id"] as StringName)
			or StringName(pd.get("lot_id", &"")) != (rec["lot_id"] as StringName)
			or int(pd.get("site_instance_id", -1)) != int(rec["site_instance_id"])
			or StringName(pd.get("site_id", &"")) != (rec["site_id"] as StringName)
			or int(pd.get("generation", -1)) != int(rec["generation"])
			or StringName(pd.get("reservation_id", &"")) != (rec["reservation_id"] as StringName)
			or StringName(pd.get("region_id", &"")) != (rec["region_id"] as StringName)
			or int(pd.get("pile_id", -1)) != int(rec["pile_id"])
			or int(pd.get("pile_instance_id", -1)) != int(rec["pile_instance_id"])
			or StringName(pd.get("resource_id", &"")) != (rec["resource_id"] as StringName)
			or int(pd.get("unit_weight", -1)) != int(rec["unit_weight"])
			or int(pd.get("requested_amount", -1)) != int(rec["requested_amount"])
			or int(pd.get("unit_instance_id", -1)) != int(rec["unit_instance_id"])
			or StringName(pd.get("unit_id", &"")) != (rec["unit_id"] as StringName)
		):
			return _failure("operation_conflict", "receipt")

	return {
		"ok": true,
		"reason": "",
		"dependency": "",
		"replayed": true,
		"withdrawn": 0,
		"committed_amount": int(rec["committed_amount"]),
		"receipt": rec.duplicate(true),
	}


func _verify_post_mutation_invariants(
	typed_site: ConstructionSite,
	typed_unit: Unit,
	pile: GroundResourcePile,
	pile_manager: GroundPileManager,
	carry_load: UnitCarryLoad,
	pile_id_int: int,
	res_id_sn: StringName,
	req_amount: int,
	fresh_plan: Dictionary,
	reserved_before: int,
	in_transit_before: int,
	buffer_before: Dictionary,
	consumed_before: Dictionary,
	missing_before: Dictionary
) -> bool:
	var reserved_after: int = typed_site.get_reserved_in_piles_amount(res_id_sn)
	var in_transit_after: int = typed_site._read_in_transit_amount_pure(res_id_sn)
	if reserved_before + in_transit_before != reserved_after + in_transit_after:
		return false
	if reserved_after != reserved_before - req_amount or in_transit_after != in_transit_before + req_amount:
		return false
	if typed_site.get_delivered_buffer_amounts() != buffer_before:
		return false
	if typed_site.get_consumed_amounts() != consumed_before:
		return false
	if typed_site.get_missing_amounts() != missing_before:
		return false
	if not typed_site._verify_accounting_invariant_pure():
		return false
	if not carry_load.validate_provenance():
		return false
	var carry_plan: Dictionary = fresh_plan["carry_plan"] as Dictionary
	if carry_load.get_current_weight() != int(carry_plan["after_weight"]):
		return false
	if carry_load.get_all_amounts() != (carry_plan["after_amounts"] as Dictionary):
		return false
	var claim_reconcile: Dictionary = typed_site._verify_unit_claims_reconciled_with_provenance_pure(typed_unit, carry_load)
	if not bool(claim_reconcile.get("ok", false)):
		return false
	var pile_after: Dictionary = (fresh_plan["pile_plan"] as Dictionary)["after"] as Dictionary
	if not is_instance_valid(pile) or pile.amount != int(pile_after["pile_amount"]):
		return false
	if pile_manager.get_pile_reservations(pile_id_int) != (pile_after["pile_reservations"] as Dictionary):
		return false
	return true


func _should_abort_at_stage(stage: String, ctx: Dictionary) -> bool:
	if not fault_injection_hook.is_valid():
		return false
	var call_ctx: Dictionary = ctx.duplicate()
	call_ctx["stage"] = stage
	var outcome: Variant = fault_injection_hook.call(stage, call_ctx)
	if typeof(outcome) == TYPE_BOOL:
		return not bool(outcome)
	if outcome is Dictionary:
		return not bool((outcome as Dictionary).get("ok", true))
	return false


func _release_guards(
	authority: RegionalAuthority,
	typed_site: ConstructionSite,
	locked_peers: Array[ConstructionSite],
	inventory: SettlementInventory,
	pile_manager: GroundPileManager,
	carry_load: UnitCarryLoad
) -> void:
	carry_load._coordinator_transaction_locked = false
	carry_load._provenance_busy = false
	pile_manager._is_preparing_withdrawal = false
	inventory._is_delivering = false
	for i: int in range(locked_peers.size() - 1, -1, -1):
		var peer: ConstructionSite = locked_peers[i]
		if is_instance_valid(peer):
			peer._is_preparing_or_transacting = false
	if is_instance_valid(typed_site):
		typed_site._is_preparing_or_transacting = false
	_handle_executing = false
	authority.is_executing = false


static func _failure(reason: String, dependency: String = "") -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
		"replayed": false,
		"withdrawn": 0,
	}


static func _prep_to_failure(prep: Dictionary) -> Dictionary:
	return _failure(String(prep.get("reason", "rejected")), String(prep.get("dependency", "")))
