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
var _settlement_inventory: SettlementInventory = null
var _region_id: StringName = &""
var _use_provenance: bool = false
var _spawned_workers: Array[Unit] = []


func configure(
	units_root: Node3D,
	world_navigation: WorldNavigation,
	camp_storage_zone: CampStorageZone = null,
	selection_manager: SelectionManager = null,
	construction_sites_root: Node3D = null,
	settlement_inventory: SettlementInventory = null,
	region_id: StringName = &"",
	use_provenance: bool = false
) -> void:
	_units_root = units_root
	_world_navigation = world_navigation
	_camp_storage_zone = camp_storage_zone
	_selection_manager = selection_manager
	_construction_sites_root = construction_sites_root
	_settlement_inventory = settlement_inventory
	_region_id = region_id
	_use_provenance = use_provenance


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

	var w3: Unit = _instantiate_worker("Worker3", def_3)
	var w4: Unit = _instantiate_worker("Worker4", def_4)
	if _use_provenance:
		var pair: Array[Unit] = [w3, w4]
		var admission := ReservedWithdrawalCoordinator.admit_empty_provenance_units(
			pair, _units_root, _camp_storage_zone, _settlement_inventory, _region_id
		)
		if not admission.ok:
			w3.free()
			w4.free()
			return {"ok": false, "reason": admission.reason, "message": "Admissão econômica bloqueada: %s" % admission.reason, "workers": []}
	w3.position = _units_root.to_local(pos_3)
	w4.position = _units_root.to_local(pos_4)
	_spawned_workers = [w3, w4]
	_units_root.add_child(w3)
	_units_root.add_child(w4)

	return {
		"ok": true,
		"reason": "",
		"message": "Worker3 e Worker4 adicionados próximo ao acampamento.",
		"workers": [w3, w4],
	}


func can_remove_temporary_workers() -> Dictionary:
	var workers: Array[Unit] = get_temporary_workers()
	return _validate_workers_for_removal(workers, false)


func remove_temporary_workers_safely() -> Dictionary:
	var workers: Array[Unit] = get_temporary_workers()
	var check: Dictionary = _validate_workers_for_removal(workers, false)
	if not bool(check.get("can_remove", false)):
		return {
			"ok": false,
			"reason": str(check.get("reason", "")),
			"message": str(check.get("message", "Não foi possível remover trabalhadores temporários.")),
		}

	# Phase 2: Cancel active orders safely before touching selection or the scene tree.
	for worker: Unit in workers:
		var active_order: UnitOrder = worker.get_current_order()
		if active_order == null:
			continue
		var pre_cancel_check: Dictionary = _validate_workers_for_removal(workers, false)
		if not bool(pre_cancel_check.get("can_remove", false)):
			return {
				"ok": false,
				"reason": str(pre_cancel_check.get("reason", "transaction_in_progress")),
				"message": str(pre_cancel_check.get("message", "Não foi possível remover trabalhadores temporários.")),
			}
		worker.cancel_current_order("temporary_worker_removed")
		if worker.get_current_order() != null or not active_order.is_finished():
			return {
				"ok": false,
				"reason": "order_cancel_failed",
				"message": "Remoção bloqueada: não foi possível encerrar com segurança a ordem ativa de %s." % worker.name,
			}

	# Phase 3: Full revalidation after order cancellations, before selection/tree mutations.
	var post_cancel_workers: Array[Unit] = get_temporary_workers()
	if not _same_worker_set(workers, post_cancel_workers):
		return {
			"ok": false,
			"reason": "worker_set_changed",
			"message": "Remoção bloqueada: conjunto de trabalhadores temporários foi alterado durante o cancelamento.",
		}
	var post_cancel_check: Dictionary = _validate_workers_for_removal(workers, true)
	if not bool(post_cancel_check.get("can_remove", false)):
		return {
			"ok": false,
			"reason": str(post_cancel_check.get("reason", "")),
			"message": str(post_cancel_check.get("message", "Não foi possível remover trabalhadores temporários.")),
		}

	# Phase 4: Unselect, then revalidate one final time before remove_child()/queue_free().
	if _selection_manager != null and is_instance_valid(_selection_manager):
		for worker: Unit in workers:
			_selection_manager.remove_unit(worker)

	var final_workers: Array[Unit] = get_temporary_workers()
	if not _same_worker_set(workers, final_workers):
		return {
			"ok": false,
			"reason": "worker_set_changed",
			"message": "Remoção bloqueada: conjunto de trabalhadores temporários foi alterado antes da remoção efetiva.",
		}
	var final_check: Dictionary = _validate_workers_for_removal(workers, true)
	if not bool(final_check.get("can_remove", false)):
		return {
			"ok": false,
			"reason": str(final_check.get("reason", "")),
			"message": str(final_check.get("message", "Não foi possível remover trabalhadores temporários.")),
		}

	for worker: Unit in workers:
		# Revalidate each removal: previous tree/selection callbacks may change obligations.
		var immediate_check := _validate_workers_for_removal([worker], true)
		if not immediate_check.can_remove:
			return {"ok": false, "reason": immediate_check.reason, "message": immediate_check.message}
		if worker.get_parent() == _units_root:
			_units_root.remove_child(worker)
		worker.queue_free()

	_spawned_workers.clear()
	return {
		"ok": true,
		"reason": "",
		"message": "Worker3 e Worker4 removidos com segurança.",
	}


func _same_worker_set(a: Array[Unit], b: Array[Unit]) -> bool:
	if a.size() != b.size():
		return false
	for u: Unit in a:
		if not b.has(u):
			return false
	return true


func _validate_workers_for_removal(workers: Array[Unit], require_no_active_orders: bool) -> Dictionary:
	if workers.is_empty():
		return _cannot_remove("none_present", "Nenhum trabalhador temporário ativo para remover.")

	if _units_root == null or not is_instance_valid(_units_root) or not _units_root.is_inside_tree():
		return _cannot_remove("invalid_worker_state", "Remoção bloqueada: raiz de unidades indisponível na cena.")

	var world: World3D = _units_root.get_world_3d()
	var tree: SceneTree = _units_root.get_tree()
	if world == null or tree == null:
		return _cannot_remove("invalid_worker_state", "Remoção bloqueada: contexto de mundo/cena indisponível.")

	if _camp_storage_zone != null:
		if not is_instance_valid(_camp_storage_zone) or not _camp_storage_zone.is_inside_tree() or _camp_storage_zone.get_world_3d() != world:
			return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: zona de acampamento inconsistente com o mundo atual.")
		if _camp_storage_zone.is_transaction_locked():
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: zona de acampamento está em transação ativa.")

	var candidate_storage: GroundPileManager = null
	var candidate_region: StringName = _region_id
	if _settlement_inventory != null:
		if _settlement_inventory.is_transaction_busy():
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: inventário do assentamento está em transação ativa.")
		candidate_storage = _settlement_inventory.get_storage_source() as GroundPileManager
		if candidate_storage != null:
			if candidate_storage.is_locked() or candidate_storage.is_batch_active():
				return _cannot_remove("transaction_in_progress", "Remoção bloqueada: armazenamento físico está em transação ativa.")
			if _camp_storage_zone != null and candidate_storage.get_camp_zone() != _camp_storage_zone:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: armazenamento físico diverge da zona de acampamento.")
			var bound_world: World3D = candidate_storage.get_bound_withdrawal_world()
			var bound_region: StringName = candidate_storage.get_bound_withdrawal_region()
			if bound_world != null and bound_world != world:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: armazenamento físico vinculado a outro World3D.")
			if not bound_region.is_empty():
				if not candidate_region.is_empty() and candidate_region != bound_region:
					return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: região configurada diverge da região vinculada ao armazenamento.")
				candidate_region = bound_region

	var sites_in_world: Array[ConstructionSite] = _collect_world_construction_sites(tree, world)

	# Infer domain anchor from sites inside _construction_sites_root when not explicitly configured.
	if _construction_sites_root != null and is_instance_valid(_construction_sites_root):
		for child: Node in _construction_sites_root.get_children():
			if not (child is ConstructionSite):
				continue
			var root_site: ConstructionSite = child as ConstructionSite
			if not is_instance_valid(root_site) or not root_site.is_inside_tree() or root_site.is_queued_for_deletion():
				continue
			if root_site.get_world_3d() != world:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: canteiro na raiz padrão pertence a outro World3D.")
			if not root_site.is_valid():
				continue
			if not CarryProvenanceLedger._id(root_site.region_id):
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: canteiro com region_id inválido.")
			if candidate_region.is_empty():
				candidate_region = root_site.region_id
			elif candidate_region != root_site.region_id:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: regiões conflitantes na raiz de canteiros.")
			var rs_inv: SettlementInventory = root_site.get_inventory()
			var rs_storage: GroundPileManager = rs_inv.get_storage_source() as GroundPileManager if rs_inv != null else null
			if rs_storage != null:
				if candidate_storage == null:
					candidate_storage = rs_storage
				elif candidate_storage != rs_storage:
					return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: armazenamentos conflitantes na raiz de canteiros.")

	# Read-only regional authority check (never creates a RegionalAuthority).
	var domain_probe: Dictionary = ReservedWithdrawalCoordinator.inspect_domain_for_worker_removal_readonly(
		world,
		candidate_region,
		candidate_storage,
		_camp_storage_zone
	)
	if not bool(domain_probe.get("ok", false)):
		var probe_reason: String = str(domain_probe.get("reason", "ambiguous_economic_domain"))
		var probe_msg: String = "Remoção bloqueada: transação regional ativa no domínio econômico." if probe_reason == "regional_transaction_active" else "Remoção bloqueada: identidade do domínio econômico ambígua."
		return _cannot_remove(probe_reason, probe_msg)

	var resolved_region: StringName = domain_probe.get("resolved_region", candidate_region) as StringName
	var resolved_storage: GroundPileManager = domain_probe.get("resolved_storage", candidate_storage) as GroundPileManager
	if resolved_storage != null and (resolved_storage.is_locked() or resolved_storage.is_batch_active()):
		return _cannot_remove("transaction_in_progress", "Remoção bloqueada: armazenamento regional em transação ativa.")

	for worker: Unit in workers:
		var w_check: Dictionary = _validate_single_worker(
			worker,
			world,
			tree,
			resolved_region,
			resolved_storage,
			sites_in_world,
			require_no_active_orders
		)
		if not bool(w_check.get("can_remove", false)):
			return w_check

	return {
		"can_remove": true,
		"reason": "",
		"message": "",
	}


func _validate_single_worker(
	worker: Unit,
	world: World3D,
	tree: SceneTree,
	resolved_region: StringName,
	resolved_storage: GroundPileManager,
	sites_in_world: Array[ConstructionSite],
	require_no_active_orders: bool
) -> Dictionary:
	if worker == null or not is_instance_valid(worker) or not worker.is_inside_tree() or worker.is_queued_for_deletion():
		return _cannot_remove("invalid_worker_state", "Remoção bloqueada: estado de trabalhador inválido.")
	if worker.get_world_3d() != world:
		return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: %s está em outro World3D." % worker.name)

	var carry: UnitCarryLoad = worker.get_carry_load()
	if carry == null:
		return _cannot_remove("invalid_worker_state", "Remoção bloqueada: %s sem estrutura de mochila válida." % worker.name)

	# Transactional locks on unit and carry load (including post-commit signal windows).
	if worker._is_reserved_withdrawal_locked():
		return _cannot_remove("transaction_in_progress", "Remoção bloqueada: %s está sob trava de transação econômica." % worker.name)
	if carry.is_transaction_busy() or carry._coordinator_transaction_locked:
		return _cannot_remove("transaction_in_progress", "Remoção bloqueada: mochila de %s está sob transação ativa." % worker.name)
	var custody_check := CancellationLifecycleGuard.inspect_worker(worker, resolved_region)
	if not custody_check.ok:
		return _cannot_remove(custody_check.reason, "Remoção bloqueada: recuperação ou custódia pendente de %s." % worker.name)

	# Active order transactional / cancellability inspection.
	var order: UnitOrder = worker.get_current_order()
	if require_no_active_orders and order != null:
		return _cannot_remove("order_cancel_failed", "Remoção bloqueada: ordem ativa de %s não foi encerrada." % worker.name)
	if order != null and order.is_active():
		var order_check: Dictionary = _validate_active_order_for_removal(worker, order, world)
		if not bool(order_check.get("can_remove", false)):
			return order_check

	# Provenance unit identity and ledger reconciliation check.
	if carry.is_provenance_enabled():
		var prov_uid: StringName = carry.get_provenance_unit_id()
		if not CarryProvenanceLedger._id(prov_uid):
			return _cannot_remove("ambiguous_unit_identity", "Remoção bloqueada: %s possui identidade de proveniência inválida." % worker.name)
		if not carry.validate_provenance():
			return _cannot_remove("unreconciled_carry_load", "Remoção bloqueada: mochila de %s possui ledger não reconciliado." % worker.name)
		if not resolved_region.is_empty():
			var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
				world, resolved_region, worker, carry, tree
			)
			if not bool(id_check.get("ok", false)):
				return _cannot_remove("ambiguous_unit_identity", "Remoção bloqueada: identidade econômica ambígua ou conflitante (%s)." % String(prov_uid))
		else:
			for node: Node in tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
				var other_unit: Unit = node as Unit
				if other_unit == null or other_unit == worker or not is_instance_valid(other_unit) or not other_unit.is_inside_tree() or other_unit.is_queued_for_deletion():
					continue
				var other_carry: UnitCarryLoad = other_unit.get_carry_load()
				if other_carry == carry:
					return _cannot_remove("ambiguous_unit_identity", "Remoção bloqueada: mochila compartilhada entre unidades distintas.")
				if other_unit.get_world_3d() != world:
					continue
				if other_carry != null and other_carry.is_provenance_enabled() and other_carry.get_provenance_unit_id() == prov_uid:
					return _cannot_remove("ambiguous_unit_identity", "Remoção bloqueada: identidade econômica duplicada (%s) no World3D." % String(prov_uid))

	# Domain-wide ConstructionSite scan via GROUP_CONSTRUCTION_SITES (read-only).
	var uid: int = worker.get_instance_id()
	for site: ConstructionSite in sites_in_world:
		var site_inv: SettlementInventory = site.get_inventory()
		var site_storage: GroundPileManager = site_inv.get_storage_source() as GroundPileManager if site_inv != null else null
		var site_has_valid_region: bool = CarryProvenanceLedger._id(site.region_id)
		var same_region: bool = not resolved_region.is_empty() and site_has_valid_region and site.region_id == resolved_region
		var same_storage: bool = resolved_storage != null and site_storage == resolved_storage
		var same_camp: bool = _camp_storage_zone != null and site_storage != null and site_storage.get_camp_zone() == _camp_storage_zone
		var in_our_root: bool = _construction_sites_root != null and is_instance_valid(_construction_sites_root) and site.get_parent() == _construction_sites_root
		var belongs_to_our_domain: bool = same_region or same_storage or same_camp or in_our_root

		var claim: Dictionary = site._read_transit_claim_for_unit_pure(uid)
		var has_claim: bool = not claim.is_empty()
		if has_claim:
			var raw_entry: Dictionary = site._transit_claims.get(uid, {}) as Dictionary
			if raw_entry.get("unit") != worker:
				return _cannot_remove("ambiguous_unit_identity", "Remoção bloqueada: identidade ambígua de claim no canteiro %s." % String(site.site_id))

		if belongs_to_our_domain:
			if not site_has_valid_region:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: canteiro %s possui region_id inválido." % String(site.site_id))
			if not resolved_region.is_empty() and site.region_id != resolved_region:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: conflito de região no canteiro %s." % String(site.site_id))
			if resolved_storage != null and site_storage != null and site_storage != resolved_storage:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: armazenamento conflitante no canteiro %s." % String(site.site_id))
			if site.is_transaction_busy():
				return _cannot_remove("transaction_in_progress", "Remoção bloqueada: canteiro %s está em transação ativa." % String(site.site_id))
			if has_claim:
				return _cannot_remove(
					"transit_claim_active",
					"Remoção bloqueada: %s possui reserva em trânsito no canteiro %s." % [
						worker.name,
						String(site.site_id),
					]
				)
			if require_no_active_orders and site._pending_pickups.has(uid):
				return _cannot_remove(
					"transit_claim_active",
					"Remoção bloqueada: %s ainda possui coleta pendente no canteiro %s." % [
						worker.name,
						String(site.site_id),
					]
				)
		else:
			if has_claim:
				if resolved_region.is_empty():
					return _cannot_remove(
						"transit_claim_active",
						"Remoção bloqueada: %s possui reserva em trânsito no canteiro %s." % [
							worker.name,
							String(site.site_id),
						]
					)
				return _cannot_remove(
					"ambiguous_economic_domain",
					"Remoção bloqueada: %s possui claim em canteiro (%s) de outra região." % [
						worker.name,
						String(site.site_id),
					]
				)
			if (site._pending_pickups.has(uid) or site._assigned_workers.has(uid)) and site.is_transaction_busy():
				return _cannot_remove("transaction_in_progress", "Remoção bloqueada: canteiro %s referenciando %s está em transação ativa." % [String(site.site_id), worker.name])

	# Physical cargo in backpack (aggregate amounts, weight, or provenance lots).
	var has_provenance_lots: bool = carry.is_provenance_enabled() and not carry._provenance.snapshot().is_empty()
	if not carry.is_empty() or carry.get_current_weight() > 0 or has_provenance_lots:
		var total_units: int = 0
		for amt: Variant in carry.get_all_amounts().values():
			total_units += int(amt)
		return _cannot_remove(
			"cargo_in_backpack",
			"Remoção bloqueada: %s possui carga na mochila (%d un). Entregue ou descarregue antes de remover." % [
				worker.name,
				total_units,
			]
		)

	return {
		"can_remove": true,
		"reason": "",
		"message": "",
	}


func _validate_active_order_for_removal(worker: Unit, order: UnitOrder, world: World3D) -> Dictionary:
	if order.has_method("is_provenance_transfer_executing") and bool(order.call("is_provenance_transfer_executing")):
		return _cannot_remove("transaction_in_progress", "Remoção bloqueada: %s executa transferência de coleta." % worker.name)
	if order.has_method("is_selective_transfer_executing") and bool(order.call("is_selective_transfer_executing")):
		return _cannot_remove("transaction_in_progress", "Remoção bloqueada: %s executa entrega seletiva." % worker.name)
	if order.has_method("_defer_transfer_replan") and bool(order.call("_defer_transfer_replan")):
		return _cannot_remove("transaction_in_progress", "Remoção bloqueada: %s executa transferência de obra." % worker.name)

	if order is ConstructOrder:
		var c_order: ConstructOrder = order as ConstructOrder
		if c_order.site != null and is_instance_valid(c_order.site):
			if c_order.site.is_inside_tree() and c_order.site.get_world_3d() != world:
				return _cannot_remove("ambiguous_economic_domain", "Remoção bloqueada: ordem de construção de %s aponta para outro World3D." % worker.name)
			if c_order.site.is_transaction_busy():
				return _cannot_remove("transaction_in_progress", "Remoção bloqueada: canteiro da ordem de %s está em transação ativa." % worker.name)
			if CarryProvenanceLedger._id(c_order.site.region_id) and ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, c_order.site.region_id):
				return _cannot_remove("regional_transaction_active", "Remoção bloqueada: transação regional ativa na região da ordem de %s." % worker.name)
	elif order is GatherResourceOrder:
		var g_order: GatherResourceOrder = order as GatherResourceOrder
		if g_order.source != null and is_instance_valid(g_order.source) and g_order.source._is_transferring:
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: fonte da ordem de coleta de %s está transferindo." % worker.name)
		if g_order.inventory != null and g_order.inventory.is_transaction_busy():
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: inventário da ordem de coleta de %s está em transação ativa." % worker.name)
		if g_order.camp_zone != null and is_instance_valid(g_order.camp_zone) and g_order.camp_zone.is_transaction_locked():
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: acampamento da ordem de coleta de %s está em transação ativa." % worker.name)
		if g_order.use_provenance_transactions and CarryProvenanceLedger._id(g_order.region_id) and ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, g_order.region_id):
			return _cannot_remove("regional_transaction_active", "Remoção bloqueada: transação regional ativa na ordem de coleta de %s." % worker.name)
	elif order is DeliverToCampOrder:
		var d_order: DeliverToCampOrder = order as DeliverToCampOrder
		if d_order.inventory != null and d_order.inventory.is_transaction_busy():
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: inventário da ordem de entrega de %s está em transação ativa." % worker.name)
		if d_order.camp_zone != null and is_instance_valid(d_order.camp_zone) and d_order.camp_zone.is_transaction_locked():
			return _cannot_remove("transaction_in_progress", "Remoção bloqueada: acampamento da ordem de entrega de %s está em transação ativa." % worker.name)
		if d_order.use_selective_provenance and CarryProvenanceLedger._id(d_order.region_id) and ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, d_order.region_id):
			return _cannot_remove("regional_transaction_active", "Remoção bloqueada: transação regional ativa na ordem de entrega de %s." % worker.name)

	return {"can_remove": true, "reason": "", "message": ""}


func _collect_world_construction_sites(tree: SceneTree, world: World3D) -> Array[ConstructionSite]:
	var sites: Array[ConstructionSite] = []
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		if not (node is ConstructionSite):
			continue
		var site: ConstructionSite = node as ConstructionSite
		if not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion():
			continue
		if not site.is_valid():
			continue
		if site.get_world_3d() != world:
			continue
		if not sites.has(site):
			sites.append(site)

	if _construction_sites_root != null and is_instance_valid(_construction_sites_root):
		for child: Node in _construction_sites_root.get_children():
			if not (child is ConstructionSite):
				continue
			var root_site: ConstructionSite = child as ConstructionSite
			if not is_instance_valid(root_site) or not root_site.is_inside_tree() or root_site.is_queued_for_deletion():
				continue
			if not root_site.is_valid():
				continue
			if root_site.get_world_3d() != world:
				continue
			if not sites.has(root_site):
				sites.append(root_site)

	return sites


func _cannot_remove(reason: String, message: String) -> Dictionary:
	return {
		"can_remove": false,
		"reason": reason,
		"message": message,
	}


func _instantiate_worker(node_name: String, def: CharacterDefinition) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.name = node_name
	unit.definition = def
	if _world_navigation != null:
		unit.set_world_navigation(_world_navigation)
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
