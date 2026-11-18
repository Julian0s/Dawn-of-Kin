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


## Capability for the one active selective delivery in this domain.
class DeliveryScope extends RefCounted:
	var site: ConstructionSite
	var unit: Unit
	var load: UnitCarryLoad
	var inventory: SettlementInventory
	var storage: GroundPileManager
	var sites: Array[ConstructionSite] = []


class RegionalAuthority extends RefCounted:
	var storage: WeakRef
	var is_executing: bool = false
	var receipts: Dictionary = {}
	var committed_lots: Dictionary = {}
	var active_delivery: DeliveryScope
	var construction_transfer_serial: int = 0


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


## A C2 receipt without kind is admitted only with the original C2 format.
static func _read_receipt(record: Variant, operation: StringName, kind: StringName) -> Dictionary:
	if not record is Dictionary or not record.get("receipt") is Dictionary:
		return {}
	for field: String in ["site", "unit", "load"]:
		if not record.get(field) is WeakRef:
			return {}
	var receipt: Dictionary = record.receipt
	if typeof(receipt.get("operation_id")) != TYPE_STRING_NAME or receipt.operation_id != operation:
		return {}
	if receipt.has("kind") and (typeof(receipt.kind) != TYPE_STRING_NAME or receipt.kind != kind):
		return {}
	if kind == RECEIPT_DELIVERY:
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
		and authority.storage.get_ref() == scope.storage and scope.site.get_inventory() == scope.inventory \
		and scope.inventory.get_storage_source() == scope.storage and scope.inventory._is_delivering \
		and scope.storage._is_preparing_withdrawal and scope.load._coordinator_transaction_locked \
		and scope.load._provenance_busy and scope.site._is_preparing_or_transacting


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


static func _inspect_camp_economic_domain(
	world: World3D,
	region: StringName,
	inventory: SettlementInventory,
	storage: GroundPileManager,
	authority: RegionalAuthority,
	domains: Dictionary,
	tree: SceneTree
) -> Dictionary:
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
