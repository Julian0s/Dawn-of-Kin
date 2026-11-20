extends TestCase

const Fixtures = preload("res://tests/integration/test_t3_6_3_b1_2_cancellation_commit_transaction.gd")
const SHELTER = preload("res://data/buildings/shelter_basic.tres")
var fixture: Fixtures
const R := preload("res://src/economy/cancellation_recovery_transaction.gd")
const C := preload("res://src/economy/reserved_withdrawal_coordinator.gd")


func _record(main: MainScene, cancel_id: StringName) -> ReservedWithdrawalCoordinator.CancellationCustodyRecord:
	var domains: Dictionary = main.get_world_3d().get_meta(C.DOMAIN_META)
	return domains[&"default"].cancellation_custodies[cancel_id]


func _balanced(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord) -> void:
	assert_true(C.validate_custody_accounting_pure(record).ok, str(record.to_snapshot_dict()))
	for res: StringName in record.required_amounts:
		assert_eq(record.required_amounts[res], int(record.released_on_piles.get(res, 0)) + int(record.local_buffer_remaining.get(res, 0)) + int(record.local_incorporated_remaining.get(res, 0)) + int(record.in_transit_remaining.get(res, 0)) + int(record.delivered_to_camp.get(res, 0)) + int(record.demolition_loss.get(res, 0)) + int(record.missing_deficit.get(res, 0)))


func _walk(unit: Unit, target: Vector3) -> void:
	var move := MoveOrder.new(target)
	unit.issue_order(move)
	assert_true(await fixture._until(func() -> bool: return move.is_finished(), 3600), "Movement must finish")
	assert_true(move.is_succeeded(), move.failure_reason)


func _approach(unit: Unit, record: ReservedWithdrawalCoordinator.CancellationCustodyRecord) -> void:
	await _walk(unit, record.anchor_position + Vector3(-record.footprint_size.x * 0.5 - 0.4, 0, 0))


func _requests(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, origin: StringName, prefix: String) -> Array[Dictionary]:
	var amounts := record.local_buffer_remaining if origin == CarryProvenanceLedger.CANCEL_BUFFER else record.local_incorporated_remaining
	var result: Array[Dictionary] = []
	for res: StringName in amounts:
		if amounts[res] > 0:
			result.append({"lot_id": StringName(prefix + String(res)), "resource_id": res, "amount": amounts[res], "origin": origin})
	return result


func _selected(unit: Unit) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	for lot: Dictionary in unit.get_carry_load().provenance_snapshot().ledger.lots.values():
		if R.CANCEL_ORIGINS.has(lot.origin):
			requests.append({"lot_id": lot.lot_id, "amount": lot.quantity})
	return requests


func _deliver(main: MainScene, unit: Unit, requested: Array[Dictionary] = []) -> DeliverToCampOrder:
	var selection := requested if not requested.is_empty() else _selected(unit)
	var order := DeliverToCampOrder.new(main.get_camp_storage_zone(), main.get_settlement_inventory(), true, &"default", selection)
	unit.issue_order(order)
	assert_true(await fixture._until(func() -> bool: return order.is_finished(), 3600), "Physical delivery must finish")
	assert_true(order.is_succeeded(), order.failure_reason)
	return order


func _local() -> Dictionary:
	var main := await fixture._fixture()
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := fixture._site(main, Vector3(-6, 0, 1.5))
	assert_true(main.get_command_controller().command_units_to_site(site, main.get_units()))
	assert_true(await fixture._until(func() -> bool: return site._work_progress_usec >= 15_000_000, 6500))
	var cancelled := C.execute_site_cancellation(site, &"b13_cancel")
	assert_true(cancelled.ok, str(cancelled))
	var record := _record(main, cancelled.receipt.cancel_id)
	for unit: Unit in main.get_units():
		unit.cancel_current_order()
	for unit: Unit in main.get_units():
		if not _selected(unit).is_empty():
			await _deliver(main, unit)
	return {"main": main, "site": site, "record": record, "unit": main.get_units()[0]}


func test_local_buffer_incorporated_multitrip_and_settlement() -> void:
	var ctx := await _local()
	var main: MainScene = ctx.main
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	var unit: Unit = ctx.unit
	var load := unit.get_carry_load()
	var fixed := [record.released_on_piles.duplicate(), record.demolition_loss.duplicate(), record.missing_deficit.duplicate()]
	assert_true(record.get_local_custody_total() > 0)
	print("B13_ACCOUNTING_BEFORE ", record.to_snapshot_dict())
	assert_true(main.get_construction_manager().has_footprint_overlapping_rect(ctx.site.get_footprint_rect()))
	assert_true(is_instance_valid(record.custody_body.get_ref()))
	assert_true(load.set_base_capacity(6))
	var trips := 0
	for origin: StringName in [CarryProvenanceLedger.CANCEL_BUFFER, CarryProvenanceLedger.CANCEL_INCORPORATED]:
		while not _requests(record, origin, "pending").is_empty() and trips < 25:
			await _approach(unit, record)
			var requests := _requests(record, origin, "b13_trip%d_" % trips)
			var before_e := record.delivered_to_camp.duplicate()
			var before_physical := main.get_settlement_inventory().get_all_physical_amounts()
			var before_a := record.get_local_custody_total()
			var taken := C.recover_cancellation_materials(record.cancel_id, unit, requests, StringName("pickup%d" % trips))
			assert_true(taken.ok, str(taken))
			if not taken.ok:
				return
			assert_true(load.get_current_weight() <= 6)
			assert_eq(record.delivered_to_camp, before_e, "No early camp credit")
			assert_eq(main.get_settlement_inventory().get_all_physical_amounts(), before_physical)
			assert_true(record.get_local_custody_total() < before_a)
			_balanced(record)
			var replay := C.recover_cancellation_materials(record.cancel_id, unit, requests, StringName("pickup%d" % trips))
			assert_true(replay.ok and replay.replayed)
			assert_eq(replay.receipt, taken.receipt)
			if record.get_local_custody_total() == 0:
				assert_true(record.get_in_transit_custody_total() > 0)
				assert_false(main.get_construction_manager().has_footprint_overlapping_rect(ctx.site.get_footprint_rect()))
				assert_eq((record.custody_body.get_ref() as StaticBody3D).collision_layer, 0)
				var context := PlacementValidator.ValidationContext.from_region(main.get_test_map(), main.get_test_map().get_navigation())
				assert_true(PlacementValidator.new().validate_hover(SHELTER, record.anchor_position, context).reason_code != PlacementValidator.REASON_OBSTACLE_OVERLAP, "No invisible custody collider may block placement after A=0")
			var order := await _deliver(main, unit)
			assert_false(order.last_receipt.is_empty())
			assert_true(load.is_empty())
			_balanced(record)
			trips += 1
	assert_true(trips > 1 and trips < 25)
	assert_eq(record.get_local_custody_total(), 0)
	assert_eq(record.get_in_transit_custody_total(), 0)
	assert_eq(record.state, ConstructionCancellationMath.State.SETTLED)
	print("B13_ACCOUNTING_SETTLED ", record.to_snapshot_dict())
	assert_eq(fixed, [record.released_on_piles, record.demolition_loss, record.missing_deficit])
	await wait_physics_frames(2)
	assert_false(is_instance_valid(record.custody_body.get_ref()))


func test_pickup_preparation_rollback_replay_and_signal_guards() -> void:
	var ctx := await _local()
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	var unit: Unit = ctx.unit
	await _approach(unit, record)
	var requests := _requests(record, CarryProvenanceLedger.CANCEL_BUFFER, "atomic_")
	assert_false(requests.is_empty())
	var before := unit.get_carry_load().provenance_snapshot()
	var custody := record.to_snapshot_dict()
	var events: Array = []
	var committed_ids := R._authority(unit.get_world_3d(), &"default").committed_lots.duplicate()
	var cb := func() -> void: events.append(unit.get_carry_load().validate_provenance())
	unit.get_carry_load().load_changed.connect(cb)
	var plan := R.prepare(record.cancel_id, unit, requests, &"atomic", &"default")
	assert_true(plan.ok, str(plan))
	assert_eq(unit.get_carry_load().provenance_snapshot(), before)
	assert_eq(record.to_snapshot_dict(), custody)
	assert_eq(events, [])
	for stage: String in ["before_apply", "after_carry", "after_custody", "before_commit"]:
		var revision := unit.get_carry_load().get_transaction_revision()
		var result := R.recover(record.cancel_id, unit, requests, &"atomic", &"default", {}, stage)
		assert_false(result.ok, str(result))
		assert_eq(unit.get_carry_load().provenance_snapshot(), before)
		var restored := record.to_snapshot_dict()
		restored.revision = custody.revision
		assert_eq(restored, custody)
		assert_true(unit.get_carry_load().get_transaction_revision() >= revision)
		assert_eq(events, [])
		assert_eq(R._authority(unit.get_world_3d(), &"default").committed_lots, committed_ids)
		assert_false(unit.get_carry_load().is_transaction_busy())
	assert_false(R.recover(record.cancel_id, unit, requests, &"atomic", &"default", plan).ok, "Old plan must be stale after rollback")
	unit.get_carry_load().load_changed.disconnect(cb)
	var observed: Array = []
	var reenter := func() -> void:
		observed.append(C.recover_cancellation_materials(record.cancel_id, unit, requests, &"nested").ok)
		observed.append(unit.get_carry_load().add_resource(&"wood", 1, 1))
		observed.append(unit.get_carry_load().validate_provenance())
		observed.append(R._rollback_delivery(R._authority(unit.get_world_3d(), &"default").active_camp_delivery, {record.cancel_id: {"record": record, "before": custody}}))
	unit.get_carry_load().load_changed.connect(reenter)
	var result := C.recover_cancellation_materials(record.cancel_id, unit, requests, &"atomic")
	unit.get_carry_load().load_changed.disconnect(reenter)
	assert_true(result.ok, str(result))
	assert_eq(observed, [false, false, true, false])
	assert_false(C.recover_cancellation_materials(record.cancel_id, unit, [], &"atomic").ok)
	assert_false(C.recover_cancellation_materials(record.cancel_id, unit, requests, &"another_op").ok, "Lot IDs cannot be reused")
	var other := (ctx.main as MainScene).get_units()[1]
	other.global_position = unit.global_position
	var conflicting := requests.duplicate(true)
	conflicting[0].amount = 1
	assert_eq(R.prepare(record.cancel_id, other, conflicting, &"other_worker", &"default").get("reason"), "lot_operation_conflict", "Lot identity cannot move to a different backpack")
	_balanced(record)


func test_anchor_survives_visual_removal_and_wrong_position_or_domain_is_rejected() -> void:
	var ctx := await _local()
	var main: MainScene = ctx.main
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	var unit: Unit = ctx.unit
	var requests := _requests(record, CarryProvenanceLedger.CANCEL_BUFFER, "survive_")
	var before := unit.get_carry_load().provenance_snapshot()
	await _walk(unit, record.anchor_position + Vector3(-record.footprint_size.x * 0.5 - 2.0, 0, 0))
	assert_false(R.prepare(record.cancel_id, unit, requests, &"wrong_position", &"default").ok, "Distant worker must be refused")
	assert_false(R.prepare(record.cancel_id, unit, requests, &"wrong_region", &"foreign").ok)
	var other_main := await fixture._fixture()
	assert_false(R.prepare(record.cancel_id, other_main.get_units()[0], requests, &"wrong_world", &"default").ok)
	var site: ConstructionSite = ctx.site
	var rect := site.get_footprint_rect()
	site.queue_free()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(site))
	assert_true(main.get_construction_manager().has_footprint_overlapping_rect(rect))
	assert_true(R.overlaps(main.get_world_3d(), &"default", rect))
	assert_false(R.overlaps(main.get_world_3d(), &"foreign", rect))
	var validator := PlacementValidator.new()
	var context := PlacementValidator.ValidationContext.from_region(main.get_test_map(), main.get_test_map().get_navigation())
	assert_eq(validator.validate_hover(SHELTER, record.anchor_position, context).reason_code, PlacementValidator.REASON_OBSTACLE_OVERLAP)
	assert_true((record.custody_body.get_ref() as StaticBody3D).is_inside_tree())
	var body := record.custody_body.get_ref() as StaticBody3D
	var query := PhysicsRayQueryParameters3D.create(record.anchor_position + Vector3.UP * 8, record.anchor_position - Vector3.UP, CollisionLayers.MASK_BUILDINGS)
	assert_eq(main.get_world_3d().direct_space_state.intersect_ray(query).get("collider"), body)
	await _approach(unit, record)
	var nav := main.get_test_map().get_navigation()
	var original_nav := unit.get_movement().get_world_navigation()
	unit.get_movement().set_world_navigation(null)
	assert_false(R.prepare(record.cancel_id, unit, requests, &"bad_nav", &"default").ok)
	unit.get_movement().set_world_navigation(original_nav)
	assert_true(nav.is_navigation_ready())
	assert_eq(unit.get_carry_load().provenance_snapshot(), before)
	assert_true(C.transition_custody_record(record, ConstructionCancellationMath.State.RETURN_BLOCKED, "physical path blocked").ok)
	var taken := C.recover_cancellation_materials(record.cancel_id, unit, requests, &"after_visual_free")
	assert_true(taken.ok, str(taken))
	assert_eq(record.state, ConstructionCancellationMath.State.RETURNING)
	await _deliver(main, unit)
	_balanced(record)


func test_invalid_pickup_capacity_generation_and_readonly_failures() -> void:
	var ctx := await _local()
	var unit: Unit = ctx.unit
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	await _approach(unit, record)
	var requests := _requests(record, CarryProvenanceLedger.CANCEL_BUFFER, "validation_")
	var before := unit.get_carry_load().provenance_snapshot()
	var custody := record.to_snapshot_dict()
	var invalid := requests.duplicate(true)
	invalid[0].amount += 100
	assert_false(R.prepare(record.cancel_id, unit, invalid, &"too_much", &"default").ok)
	invalid = requests.duplicate(true)
	invalid[0].origin = CarryProvenanceLedger.CANCEL_TRANSIT
	assert_false(R.prepare(record.cancel_id, unit, invalid, &"bad_origin", &"default").ok)
	var capacity := unit.get_carry_load().get_base_capacity()
	assert_true(unit.get_carry_load().set_base_capacity(0))
	assert_false(R.prepare(record.cancel_id, unit, requests, &"capacity", &"default").ok)
	assert_true(unit.get_carry_load().set_base_capacity(capacity))
	record.generation += 1
	assert_false(R.prepare(record.cancel_id, unit, requests, &"generation", &"default").ok)
	record.generation -= 1
	assert_eq(unit.get_carry_load().provenance_snapshot(), before)
	assert_eq(record.to_snapshot_dict(), custody)
	_balanced(record)


func test_delivery_refuses_missing_slot_capacity_and_unrequested_cancel_lots() -> void:
	var ctx := await _local()
	var main: MainScene = ctx.main
	var unit: Unit = ctx.unit
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	await _approach(unit, record)
	assert_true(C.recover_cancellation_materials(record.cancel_id, unit, _requests(record, CarryProvenanceLedger.CANCEL_BUFFER, "blocked_"), &"blocked_pickup").ok)
	var inv := main.get_settlement_inventory()
	var camp := main.get_camp_storage_zone()
	var coordinator := SelectiveCampDeliveryCoordinator.new()
	var selected := _selected(unit)
	var before := unit.get_carry_load().provenance_snapshot()
	var custody := record.to_snapshot_dict()
	var stock := inv.get_all_physical_amounts()
	assert_false(coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"not_at_camp", selected).ok)
	assert_false(coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"generic", []).ok, "Generic delivery cannot consume CANCEL lots")
	var extent := camp.zone_bounds_half_extents
	var max_amount := camp.max_pile_amount
	camp.zone_bounds_half_extents = Vector2(0.05, 0.05)
	camp.max_pile_amount = 1
	var prepared := SelectiveCampDeliveryPlanner.prepare_selective_camp_delivery(inv, camp, unit, &"default", &"no_capacity", selected)
	assert_false(prepared.ok, str(prepared))
	camp.zone_bounds_half_extents = extent
	camp.max_pile_amount = max_amount
	assert_false(coordinator.execute_selective_camp_delivery(inv, null, unit, &"default", &"invalid_camp", selected).ok)
	assert_eq(unit.get_carry_load().provenance_snapshot(), before)
	assert_eq(record.to_snapshot_dict(), custody)
	assert_eq(inv.get_all_physical_amounts(), stock)
	_balanced(record)


func test_delivery_rollback_all_stages_and_selective_partial_custody() -> void:
	var ctx := await _local()
	var main: MainScene = ctx.main
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	var unit: Unit = ctx.unit
	await _approach(unit, record)
	assert_true(C.recover_cancellation_materials(record.cancel_id, unit, _requests(record, CarryProvenanceLedger.CANCEL_BUFFER, "deposit_"), &"deposit_pickup").ok)
	var camp := main.get_camp_storage_zone()
	var nav := main.get_test_map().get_navigation()
	var slot := GatherSlotPlanner.compute_camp_dropoff_slot(unit.global_position, camp, nav, [])
	assert_true(slot.valid)
	# This fault-injection fixture starts at a real authorized slot. End-to-end
	# walking is asserted separately by the multitrip and mixed-cargo tests.
	unit.cancel_current_order()
	unit.global_position = slot.position
	await wait_physics_frames(1)
	var selected := _selected(unit)
	selected[0].amount = 1
	var inv := main.get_settlement_inventory()
	var coordinator := SelectiveCampDeliveryCoordinator.new()
	var load_before := unit.get_carry_load().provenance_snapshot()
	var amounts := inv.get_all_physical_amounts()
	var reservations := main.get_ground_pile_manager()._ledger.snapshot_state()
	var custody := record.to_snapshot_dict()
	var events: Array = []
	var signal_cb := func() -> void: events.append(true)
	inv.inventory_changed.connect(signal_cb)
	for stage: String in ["before_carry_debit", "after_ledger_debit", "after_carry_debit", "before_pile_merge", "after_pile_merge", "before_pile_create", "after_pile_create", "before_reservation_restore", "after_reservation_restore", "before_claim_update", "after_claim_update", "during_final_invariants", "before_receipt_commit", "after_custody_update"]:
		coordinator._fault_at = func(probe: String) -> bool: return probe == stage
		var result := coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"delivery_atomic", selected)
		assert_false(result.ok, stage)
		assert_eq(unit.get_carry_load().provenance_snapshot(), load_before, stage)
		assert_eq(inv.get_all_physical_amounts(), amounts, stage)
		assert_eq(main.get_ground_pile_manager()._ledger.snapshot_state(), reservations, stage)
		var restored := record.to_snapshot_dict()
		restored.revision = custody.revision
		assert_eq(restored, custody, stage)
		assert_eq(events, [], stage)
		assert_false(inv.is_transaction_busy())
	inv.inventory_changed.disconnect(signal_cb)
	coordinator._fault_at = Callable()
	var reentries: Array = []
	var signal_reentry := func() -> void:
		reentries.append(coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"delivery_nested", selected).ok)
		reentries.append(unit.get_carry_load().validate_provenance())
		reentries.append(C.validate_custody_accounting_pure(record).ok)
		var scope := R._authority(unit.get_world_3d(), &"default").active_camp_delivery
		reentries.append(R._rollback_delivery(scope, {record.cancel_id: {"record": record, "before": custody}}))
	inv.inventory_changed.connect(signal_reentry)
	var committed := coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"delivery_atomic", selected)
	inv.inventory_changed.disconnect(signal_reentry)
	assert_true(committed.ok, str(committed))
	assert_eq(reentries, [false, true, true, false])
	assert_true(coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"delivery_atomic", selected).replayed)
	assert_false(coordinator.execute_selective_camp_delivery(inv, camp, unit, &"default", &"delivery_atomic", []).ok)
	_balanced(record)


func test_cancel_transit_mixed_free_and_other_site_remain_untouched() -> void:
	var main := await fixture._fixture()
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 24))
	assert_true(inv.deposit(&"stone", 12))
	var a := fixture._site(main, Vector3(-6, 0, 1.5))
	var b := fixture._site(main, Vector3(0.37, 0, -13.19))
	var unit := main.get_units()[0]
	for source: ResourceSource in main.get_test_map().get_resource_sources():
		if source.definition.resource_id == &"food":
			assert_true(source.transfer_to_carry_load_with_provenance(unit.get_carry_load(), &"free", &"free_lot", 1).ok)
			break
	fixture._withdraw(main, a, unit, &"take_a", &"lot_a")
	fixture._withdraw(main, b, unit, &"take_b", &"lot_b")
	unit.issue_order(MoveOrder.new(unit.global_position + Vector3(1, 0, 0)))
	var cancelled := C.execute_site_cancellation(a, &"mixed_cancel")
	assert_true(cancelled.ok)
	var record := _record(main, cancelled.receipt.cancel_id)
	var cargo_before := unit.get_carry_load().provenance_snapshot()
	var b_reserved := inv.get_reservation_amounts(b.reservation_id)
	var b_claim := b._transit_claims.duplicate(true)
	var order := await _deliver(main, unit, [{"lot_id": &"lot_a", "amount": 2}])
	assert_eq(order.last_delivered[&"wood"], 2)
	var after := unit.get_carry_load().provenance_snapshot()
	assert_eq(after.ledger.lots[&"free_lot"], cargo_before.ledger.lots[&"free_lot"])
	assert_eq(after.ledger.lots[&"lot_b"], cargo_before.ledger.lots[&"lot_b"])
	assert_eq(inv.get_reservation_amounts(b.reservation_id), b_reserved)
	assert_eq(b._transit_claims, b_claim)
	assert_eq(record.delivered_to_camp[&"wood"], 2)
	assert_eq(record.state, ConstructionCancellationMath.State.SETTLED)
	_balanced(record)


func before_each() -> void:
	fixture = Fixtures.new()
	add_test_child(fixture)
	fixture.before_each()


func after_each() -> void:
	fixture.after_each()
	fixture.cleanup_tracked_nodes()


func test_foreign_region_lot_cannot_be_hidden_from_cancellation() -> void:
	var main := await fixture._fixture()
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := fixture._site(main, Vector3(-6, 0, 1.5))
	var worker := main.get_units()[0]
	fixture._withdraw(main, site, worker, &"b13_foreign", &"b13_foreign_lot")
	worker.cancel_current_order()
	site._clear_all_transit_listeners()
	worker.set_meta(&"region_id", &"foreign")
	var before := worker.get_carry_load().provenance_snapshot()
	var result := ReservedWithdrawalCoordinator.prepare_site_cancellation(site, &"b13_foreign_cancel")
	assert_false(result.ok, "Target-site cargo in another region must be diagnosed")
	assert_eq(worker.get_carry_load().provenance_snapshot(), before)
	assert_true(site.is_active())


func test_recovery_requires_a_physical_debit() -> void:
	var main := await fixture._fixture()
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := fixture._site(main, Vector3(-6, 0, 1.5))
	assert_true(main.get_command_controller().command_units_to_site(site, main.get_units()))
	assert_true(await fixture._until(func() -> bool: return site._work_progress_usec >= 15_000_000, 6500))
	var cancelled := ReservedWithdrawalCoordinator.execute_site_cancellation(site, &"b13_cancel")
	assert_true(cancelled.ok, str(cancelled))
	if not cancelled.ok:
		return
	var coord := ReservedWithdrawalCoordinator.new()
	assert_true(coord.has_method("recover_cancellation_materials"), "B1.3 physical recovery entry is required")
