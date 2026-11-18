extends TestCase
const Ledger = preload("res://src/economy/carry_provenance_ledger.gd")

func lot(id: String, resource: String, quantity: Variant, origin: StringName, site: String = "") -> Dictionary:
	return {"lot_id": id, "unit_id": "worker", "resource_id": resource, "quantity": quantity, "origin": origin, "site_id": site, "generation": 1 if site != "" else 0}

func test_mixed_provenance_split_and_selective_withdrawal() -> void:
	var l = Ledger.new()
	assert_true(l.register_lot("1", lot("free", "wood", 4, Ledger.FREE_GATHERED)).ok)
	assert_true(l.register_lot("2", lot("a", "wood", 5, Ledger.SITE_RESERVED, "A")).ok)
	assert_true(l.register_lot("3", lot("b", "wood", 3, Ledger.SITE_RESERVED, "B")).ok)
	assert_true(l.register_lot("4", lot("stone", "stone", 2, Ledger.FREE_GATHERED)).ok)
	assert_true(l.validate_aggregate("worker", {"wood": 12, "stone": 2}).ok)
	assert_true(l.split_lot("split", "a", "a2", 2).ok)
	assert_true(l.validate_aggregate("worker", {"wood": 12, "stone": 2}).ok)
	assert_true(l.withdraw("take", "a2", 2).ok)
	assert_eq(l.query("worker", "wood", Ledger.SITE_RESERVED, "B")[0].quantity, 3)
	assert_eq(l.query("worker", "wood", Ledger.FREE_GATHERED)[0].quantity, 4)
	assert_true(l.validate_aggregate("worker", {"wood": 10, "stone": 2}).ok)
	var before: Dictionary = l.snapshot()
	assert_true(l.withdraw("take", "a2", 2).replayed)
	assert_eq(l.snapshot(), before)
	assert_false(l.withdraw("take", "a2", 1).ok)
	assert_false(l.withdraw("new", "b", 4).ok)
	assert_eq(l.snapshot(), before)
	assert_false(l.validate_aggregate("worker", {"wood": 11, "stone": 2}).ok)
	assert_false(l.validate_aggregate("worker", {"wood": 10}).ok)
	before[&"b"].quantity = 999
	assert_eq(l.snapshot()[&"b"].quantity, 3)

func test_invalid_ids_types_overflow_and_no_mutation() -> void:
	var l = Ledger.new()
	assert_true(l.register_lot("one", lot("one", "wood", 9223372036854775807, Ledger.FREE_GATHERED)).ok)
	var before: Dictionary = l.snapshot()
	assert_eq(l.register_lot("two", lot("two", "wood", 1, Ledger.FREE_GATHERED)).reason, "overflow")
	assert_false(l.register_lot("bad", lot("", "stone", 1, Ledger.FREE_GATHERED)).ok)
	assert_false(l.register_lot("bad", lot("bad", "stone", -1, Ledger.FREE_GATHERED)).ok)
	assert_false(l.register_lot("bad", lot("bad", "stone", 1.0, Ledger.FREE_GATHERED)).ok)
	assert_false(l.register_lot("bad", lot("bad", "stone", 1, Ledger.SITE_RESERVED)).ok)
	assert_false(l.register_lot("other", lot("one", "stone", 1, Ledger.FREE_GATHERED)).ok)
	assert_false(l.split_lot("x", "one", "child", 9223372036854775807).ok)
	assert_false(l.withdraw("x", "one", -1).ok)
	assert_false(l.validate_aggregate("worker", {"wood": 1.0}).ok)
	assert_eq(l.snapshot(), before)
	assert_true(l.register_lot("one", lot("one", "wood", 9223372036854775807, Ledger.FREE_GATHERED)).replayed)
	assert_false(l.register_lot("one", lot("changed", "wood", 1, Ledger.FREE_GATHERED)).ok)
	assert_eq(l.snapshot(), before)
