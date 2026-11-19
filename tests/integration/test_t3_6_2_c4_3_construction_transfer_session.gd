extends "res://tests/framework/selective_site_delivery_fixture.gd"

const WITHDRAW := ConstructionTransferSession.Kind.WITHDRAWAL
const DELIVERY := ConstructionTransferSession.Kind.DELIVERY
const NONE := ConstructionTransferSession.Kind.NONE


class UncertainSession extends ConstructionTransferSession:
	var commit_before_losing_response := false
	var invocations := 0
	var actual: Dictionary = {}

	func _invoke_coordinator(site: ConstructionSite, unit: Unit, kind: Kind) -> Dictionary:
		invocations += 1
		if invocations > 1:
			return super._invoke_coordinator(site, unit, kind)
		if commit_before_losing_response:
			# A different handle commits the same intent. No handle-local hint is shared.
			if kind == Kind.WITHDRAWAL:
				actual = ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(
					site, unit, _pile_id, _resource_id, _amount, _operation_id, _lot_id)
			else:
				actual = SelectiveSiteDeliveryCoordinator.new().execute_selective_site_delivery(
					site, unit, _operation_id)
		return {}


func _prepare_pickup(fx: Dictionary, site: ConstructionSite, unit: Unit, session: ConstructionTransferSession) -> ConstructOrder:
	var order := _arm_order(site, unit)
	order._provenance_transfer = session
	var pile: GroundResourcePile = fx.wood
	unit.global_position = pile.global_position + Vector3(0.4, 0, 0)
	assert_eq(site.claim_pickup(unit, pile.pile_id, pile.resource_id, 2), 2)
	return order


func _attempt_pickup(fx: Dictionary, site: ConstructionSite, unit: Unit, order: ConstructOrder) -> Dictionary:
	var pile: GroundResourcePile = fx.wood
	return order._provenance_transfer.withdraw(site, unit, order.get_instance_id(), pile.pile_id, &"wood", 2)


func _authority(site: ConstructionSite) -> ReservedWithdrawalCoordinator.RegionalAuthority:
	var domains: Dictionary = site.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	return domains.get(site.region_id) as ReservedWithdrawalCoordinator.RegionalAuthority


func _at_dropoff(site: ConstructionSite, unit: Unit) -> void:
	unit.global_position = site.global_position + Vector3(1.7, 0, 0)
	assert_true(BuildSlotPlanner.is_unit_in_site_dropoff_range(unit.global_position, site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, site.get_world_3d()))


func test_busy_withdrawal_rejects_conflicts_without_replacing_intent() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site_a", {&"wood": 4, &"stone": 2})
	var peer := _create_site(fx, &"site_b", {&"wood": 3}, 13.0)
	var carrier := _unit(fx, &"carrier")
	var load := carrier.get_carry_load()
	var session := ConstructionTransferSession.new()
	var order := _prepare_pickup(fx, site, carrier, session)
	load.begin_batch()
	assert_eq(_attempt_pickup(fx, site, carrier, order).get("reason"), "busy")
	var original_id := session._operation_id
	var original_lot := session._lot_id
	assert_ne(original_id, &"")
	var serial := _authority(site).construction_transfer_serial
	var before := _snapshot(fx, [site, peer], carrier)
	for payload: Array in [[fx.wood.pile_id, &"wood", 1], [fx.wood.pile_id, &"stone", 2],
		[fx.stone.pile_id, &"wood", 2]]:
		var res := session.withdraw(site, carrier, order.get_instance_id(), payload[0], payload[1], payload[2])
		assert_eq(res.get("reason"), "transaction_identity_changed")
	assert_eq(session.deliver(site, carrier, order.get_instance_id()).get("reason"), "transaction_identity_changed")
	assert_eq(session._operation_id, original_id)
	assert_eq(session._lot_id, original_lot)
	assert_eq(session._pile_id, fx.wood.pile_id)
	assert_eq(session._resource_id, &"wood")
	assert_eq(session._amount, 2)
	assert_eq(session._busy_retries, 1)
	assert_eq(_authority(site).construction_transfer_serial, serial)
	assert_eq(_snapshot(fx, [site, peer], carrier), before)
	load.end_batch()
	assert_true(session.retry_is_due(ConstructionTransferSession.RETRY_INTERVAL_SEC))
	var result := session.retry(site, carrier, order.get_instance_id())
	assert_eq(result.get("withdrawn"), 2, str(result))
	assert_eq(result.get("receipt", {}).get("operation_id"), original_id)
	assert_eq(fx.inventory.get_physical_amount(&"wood") + load.get_amount(&"wood"), 20)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 2)
	assert_eq(peer.get_reserved_in_piles_amount(&"wood"), 3)
	assert_eq(site._read_transit_claim_for_unit_pure(carrier.get_instance_id()), {&"wood": 2})


func test_uncertain_committed_withdrawal_and_delivery_reconcile_across_handles() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 4})
	var carrier := _unit(fx, &"carrier")
	var load := carrier.get_carry_load()
	var pickup := UncertainSession.new()
	pickup.commit_before_losing_response = true
	var order := _prepare_pickup(fx, site, carrier, pickup)
	var result := _attempt_pickup(fx, site, carrier, order)
	assert_eq(pickup.actual.get("withdrawn"), 2, str(pickup.actual))
	assert_eq(result.get("replayed"), true)
	assert_eq(result.get("withdrawn"), 0)
	assert_eq(result.get("receipt"), pickup.actual.get("receipt"))
	assert_eq(load.get_amount(&"wood"), 2)
	assert_eq(_authority(site).construction_transfer_serial, 1)

	var dropoff := UncertainSession.new()
	dropoff.commit_before_losing_response = true
	order._provenance_transfer = dropoff
	_at_dropoff(site, carrier)
	var delivered := dropoff.deliver(site, carrier, order.get_instance_id())
	assert_eq(dropoff.actual.get("delivered_now"), 2, str(dropoff.actual))
	assert_eq(delivered.get("replayed"), true)
	assert_eq(delivered.get("delivered_now"), 0)
	assert_eq(delivered.get("receipt"), dropoff.actual.get("receipt"))
	assert_eq(_authority(site).construction_transfer_serial, 2)
	assert_eq(_authority(site).receipts.size(), 2)
	assert_eq(_authority(site).committed_lots.size(), 1)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 2)
	assert_true(load.is_empty())
	assert_eq(fx.inventory.get_physical_amount(&"wood") + site.get_delivered_buffer_amount(&"wood"), 20)


func test_uncertain_without_receipt_cannot_allocate_or_commit_on_repeat() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 4})
	var carrier := _unit(fx, &"carrier")
	var session := UncertainSession.new()
	var order := _prepare_pickup(fx, site, carrier, session)
	var result := _attempt_pickup(fx, site, carrier, order)
	assert_eq(result.get("reason"), "unknown_transaction_outcome")
	var frozen_op := session._operation_id
	assert_ne(frozen_op, &"")
	var serial := _authority(site).construction_transfer_serial
	var before := _snapshot(fx, [site], carrier)
	assert_eq(_attempt_pickup(fx, site, carrier, order).get("reason"), "unknown_transaction_outcome")
	assert_eq(session._operation_id, frozen_op)
	assert_eq(session.invocations, 1)
	assert_eq(_authority(site).construction_transfer_serial, serial)
	assert_eq(_snapshot(fx, [site], carrier), before)
	assert_eq(fx.inventory.get_physical_amount(&"wood"), 20)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 4)


func test_order_cancel_before_and_after_commit_disarms_old_session() -> void:
	for committed: bool in [false, true]:
		var fx := _fixture()
		var site := _create_site(fx, &"site", {&"wood": 4})
		var carrier := _unit(fx, &"carrier")
		var load := carrier.get_carry_load()
		var session := ConstructionTransferSession.new()
		var order := _prepare_pickup(fx, site, carrier, session)
		load.begin_batch()
		assert_eq(_attempt_pickup(fx, site, carrier, order).get("reason"), "busy")
		var op := session._operation_id
		var lot := session._lot_id
		var serial := _authority(site).construction_transfer_serial
		var committed_receipt: Dictionary = {}
		load.end_batch()
		if committed:
			var res := ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(
				site, carrier, fx.wood.pile_id, &"wood", 2, op, lot)
			assert_eq(res.get("withdrawn"), 2, str(res))
			committed_receipt = res.get("receipt", {})
		carrier.cancel_current_order()
		assert_eq(order.status, UnitOrder.Status.CANCELLED)
		assert_eq(session.retry_kind, NONE)
		assert_eq(session._operation_id, op)
		assert_eq(session.cancel_intent(), committed_receipt)
		var before := _snapshot(fx, [site], carrier)
		var old_result := session.retry(site, carrier, order.get_instance_id())
		assert_eq(old_result.get("reason"), "order_cancelled")
		assert_eq(_attempt_pickup(fx, site, carrier, order).get("reason"), "order_cancelled")
		assert_eq(_authority(site).construction_transfer_serial, serial)
		assert_eq(_authority(site).receipts.size(), 1 if committed else 0)
		assert_eq(load.get_amount(&"wood"), 2 if committed else 0)
		assert_eq(fx.inventory.get_physical_amount(&"wood") + load.get_amount(&"wood"), 20)
		assert_eq(_snapshot(fx, [site], carrier), before)


func test_late_receipt_reconciles_original_intent_without_invoking_coordinator() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 4})
	var carrier := _unit(fx, &"carrier")
	var session := UncertainSession.new()
	var order := _prepare_pickup(fx, site, carrier, session)
	assert_eq(_attempt_pickup(fx, site, carrier, order).get("reason"), "unknown_transaction_outcome")
	var op := session._operation_id
	var lot := session._lot_id
	var authority := _authority(site)
	var serial := authority.construction_transfer_serial
	var coordinator := ReservedWithdrawalCoordinator.new()
	var commit := coordinator.execute_reserved_withdrawal(site, carrier, fx.wood.pile_id, &"wood", 2, op, lot)
	assert_eq(commit.get("withdrawn"), 2, str(commit))
	var before := _snapshot(fx, [site], carrier)
	var reconciled := _attempt_pickup(fx, site, carrier, order)
	assert_eq(reconciled.get("receipt"), commit.get("receipt"))
	assert_eq(reconciled.get("withdrawn"), 0)
	assert_eq(reconciled.get("replayed"), true)
	assert_eq(session.invocations, 1)
	assert_eq(authority.construction_transfer_serial, serial)
	assert_eq(authority.committed_lots.size(), 1)
	assert_eq(_snapshot(fx, [site], carrier), before)


func test_late_retry_refuses_changed_generation_and_removed_site() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 4})
	var carrier := _unit(fx, &"carrier")
	var load := carrier.get_carry_load()
	var session := ConstructionTransferSession.new()
	var order := _prepare_pickup(fx, site, carrier, session)
	load.begin_batch()
	assert_eq(_attempt_pickup(fx, site, carrier, order).get("reason"), "busy")
	load.end_batch()
	var op := session._operation_id
	var authority := _authority(site)
	var serial := authority.construction_transfer_serial
	site._generation += 1
	var before := _snapshot(fx, [site], carrier)
	assert_true(session.retry_is_due(ConstructionTransferSession.RETRY_INTERVAL_SEC))
	assert_eq(session.retry(site, carrier, order.get_instance_id()).get("reason"), "transaction_identity_changed")
	assert_eq(session._operation_id, op)
	assert_eq(_snapshot(fx, [site], carrier), before)
	site.get_parent().remove_child(site)
	assert_eq(session.retry(site, carrier, order.get_instance_id()).get("reason"), "invalid_domain")
	assert_eq(session._operation_id, op)
	assert_true(load.is_empty())
	assert_eq(fx.inventory.get_physical_amount(&"wood"), 20)
	assert_eq(authority.construction_transfer_serial, serial)
	assert_true(authority.receipts.is_empty())
	carrier.cancel_current_order()
	site.free()


func test_receipt_queries_are_typed_readonly_and_region_specific() -> void:
	var left := _fixture(&"left")
	var right := _fixture(&"right", left.viewport)
	var other := _fixture(&"left")
	var world: World3D = left.host.get_world_3d()
	var other_world: World3D = other.host.get_world_3d()
	var coordinator := SelectiveSiteDeliveryCoordinator.new()
	var withdrawals := ReservedWithdrawalCoordinator.new()
	assert_true(coordinator.get_receipt_in_domain(world, &"left", &"op").is_empty())
	assert_true(withdrawals.get_receipt_in_domain(world, &"left", &"op").is_empty())
	assert_false(world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	var committed: Dictionary = {}
	for fx: Dictionary in [left, right]:
		var site := _create_site(fx, &"site", {&"wood": 4})
		var carrier := _unit(fx, &"carrier")
		_withdraw(fx, site, carrier, fx.wood, 2, &"reserved_lot")
		_at_dropoff(site, carrier)
		var delivered := coordinator.execute_selective_site_delivery(site, carrier, &"op")
		assert_eq(delivered.get("delivered_now"), 2, str(delivered))
		committed[site.region_id] = delivered.get("receipt")
	assert_eq(coordinator.get_receipt(&"op"), committed[&"right"])
	var detached := coordinator.get_receipt_in_domain(world, &"left", &"op")
	assert_eq(detached, committed[&"left"])
	detached["delivered_amounts"][&"wood"] = 777
	assert_eq(coordinator.get_receipt_in_domain(world, &"left", &"op"), committed[&"left"])
	assert_eq(coordinator.get_receipt_in_domain(world, &"right", &"op"), committed[&"right"])
	assert_eq(coordinator.get_receipt(&"op"), committed[&"right"])
	assert_true(coordinator.get_receipt_in_domain(other_world, &"left", &"op").is_empty())
	assert_true(coordinator.get_receipt_in_domain(world, &"missing", &"op").is_empty())
	assert_true(withdrawals.get_receipt_in_domain(world, &"left", &"op").is_empty())
	assert_true(coordinator.get_receipt_in_domain(world, &"left", &"pickup_reserved_lot").is_empty())
	assert_eq(withdrawals.get_receipt_in_domain(world, &"left", &"pickup_reserved_lot").get("region_id"), &"left")
	assert_true(withdrawals.get_receipt(&"pickup_reserved_lot").is_empty())
	assert_false(other_world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META)
	assert_eq(domains.size(), 2)
	for auth: ReservedWithdrawalCoordinator.RegionalAuthority in domains.values():
		assert_eq(auth.construction_transfer_serial, 0)
		assert_eq(auth.receipts.size(), 2)
		assert_eq(auth.committed_lots.size(), 1)


func test_post_commit_observer_cannot_change_or_cancel_active_transfer() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 4})
	var carrier := _unit(fx, &"carrier")
	var load := carrier.get_carry_load()
	var session := ConstructionTransferSession.new()
	var order := _prepare_pickup(fx, site, carrier, session)
	var calls: Array = []
	_watch(load.load_changed, func() -> void:
		var reentry := session.withdraw(site, carrier, order.get_instance_id(), fx.stone.pile_id, &"stone", 6)
		var closed := session.cancel_intent()
		carrier.cancel_current_order()
		calls.append([reentry.get("reason"), closed, session._pile_id,
			session._resource_id, session._amount, carrier.get_current_order() == order]))
	var result := _attempt_pickup(fx, site, carrier, order)
	assert_eq(result.get("withdrawn"), 2, str(result))
	assert_eq(calls, [["busy", {}, fx.wood.pile_id, &"wood", 2, true]])
	assert_eq(_authority(site).receipts.size(), 1)
	assert_eq(_authority(site).construction_transfer_serial, 1)
	assert_eq(load.get_amount(&"wood"), 2)
	assert_eq(fx.inventory.get_physical_amount(&"wood") + load.get_amount(&"wood"), 20)
