extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")

func test_public_add_cannot_create_material_without_transfer() -> void:
	for scenario: String in ["free", "reserved", "batch", "coordinator_guard"]:
		var load := UnitCarryLoad.new(20)
		assert_true(load.enable_provenance(&"worker"))
		var events: Array = []
		var observer := func() -> void: events.append(load.provenance_snapshot())
		load.load_changed.connect(observer)
		var before := load.provenance_snapshot()
		var revision := load.get_transaction_revision()
		if scenario == "batch":
			load.begin_batch()
		if scenario == "coordinator_guard":
			load._coordinator_transaction_locked = true
		var reserved := scenario == "reserved"
		var origin := CarryProvenanceLedger.SITE_RESERVED if reserved else CarryProvenanceLedger.FREE_GATHERED
		var result := load.add_with_provenance("op", "lot", &"wood", 1, 2, origin, &"site" if reserved else &"", 1 if reserved else 0)
		assert_false(result.ok, scenario)
		assert_eq(load.get_amount(&"wood"), 0, scenario)
		assert_eq(load.get_current_weight(), 0, scenario)
		assert_eq(load.provenance_snapshot(), before, scenario)
		assert_eq(load.get_transaction_revision(), revision, scenario)
		assert_true(load.validate_provenance(), scenario)
		assert_eq(events.size(), 0, scenario)
		assert_eq(load._coordinator_transaction_locked, scenario == "coordinator_guard", scenario)
		assert_eq(load._batch_depth, 1 if scenario == "batch" else 0, scenario)
		if scenario == "batch":
			load.end_batch()
		assert_eq(events.size(), 0, scenario)
		load.load_changed.disconnect(observer)

func test_binding_atomic_add_and_bypass() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.enable_provenance(&"unit"))
	var empty: Dictionary = load.provenance_snapshot()
	assert_true(load.validate_provenance())
	assert_false(load.add_resource(&"wood", 1, 1))
	assert_false(load.add_units(WOOD, 1))
	assert_eq(load.remove_units(&"wood", 1), 0)
	assert_eq(load.take_all(), {})
	load.restore_load_snapshot({&"wood": 9}, {&"wood": 1})
	assert_eq(load.provenance_snapshot(), empty)
	var a: Dictionary = CarryFixture.add_lot(load, "op1", "a", &"wood", 1, 4, CarryProvenanceLedger.SITE_RESERVED, &"A", 1)
	assert_true(a.ok)
	assert_true(CarryFixture.add_lot(load, "op2", "b", &"wood", 1, 3, CarryProvenanceLedger.SITE_RESERVED, &"B", 1).ok)
	assert_true(CarryFixture.add_lot(load, "op3", "c", &"stone", 2, 2, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_eq(load.get_amount(&"wood"), 7)
	assert_eq(load.get_current_weight(), 11)
	assert_true(load.validate_provenance())
	var before: Dictionary = load.provenance_snapshot()
	assert_true(CarryFixture.add_lot(load, "op1", "a", &"wood", 1, 4, CarryProvenanceLedger.SITE_RESERVED, &"A", 1).replayed)
	assert_false(CarryFixture.add_lot(load, "op1", "a", &"wood", 1, 5, CarryProvenanceLedger.SITE_RESERVED, &"A", 1).ok)
	assert_false(CarryFixture.add_lot(load, "op4", "d", &"wood", 2, 1, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_false(CarryFixture.add_lot(load, "op4", "d", &"wood", 1, 10, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_false(CarryFixture.add_lot(load, "op4", "b", &"wood", 1, 1, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_eq(load.provenance_snapshot(), before)

func test_legacy_and_independence() -> void:
	var legacy := UnitCarryLoad.new(20)
	assert_true(legacy.add_resource(&"wood", 1, 2))
	assert_false(legacy.enable_provenance(&"legacy"))
	assert_eq(legacy.remove_units(&"wood", 1), 1)
	assert_eq(legacy.take_all(), {&"wood": 1})
	var a := UnitCarryLoad.new(20)
	var b := UnitCarryLoad.new(20)
	assert_true(a.enable_provenance(&"a"))
	assert_true(b.enable_provenance(&"b"))
	assert_true(CarryFixture.add_lot(a, "same", "same", &"wood", 1, 2, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_true(CarryFixture.add_lot(b, "same", "same", &"wood", 1, 3, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_eq(a.get_amount(&"wood"), 2)
	assert_eq(b.get_amount(&"wood"), 3)
	assert_true(a.validate_provenance())
	assert_true(b.validate_provenance())

func test_signal_reentrancy_observes_consistent_state() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.enable_provenance(&"worker"))
	var observed: Array = []
	var observer := func() -> void:
		observed.append(load.validate_provenance())
		observed.append(CarryFixture.add_lot(load, "recursive", "r", &"wood", 1, 1, CarryProvenanceLedger.FREE_GATHERED).ok)
	load.load_changed.connect(observer)
	assert_true(CarryFixture.add_lot(load, "outer", "a", &"wood", 1, 2, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_eq(observed, [true, false])
	assert_eq(load.get_amount(&"wood"), 2)
	load.load_changed.disconnect(observer)

func test_preparation_is_detached_guarded_and_stale_safe() -> void:
	var load := UnitCarryLoad.new(20)
	assert_true(load.enable_provenance(&"worker"))
	var events: Array = []
	var observer := func() -> void: events.append(load.provenance_snapshot())
	load.load_changed.connect(observer)
	var before: Dictionary = load.provenance_snapshot()
	var plan: Dictionary = load._prepare_provenance_add("op", "lot", &"wood", 1, 3, CarryProvenanceLedger.FREE_GATHERED)
	assert_true(plan.ok)
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(events.size(), 0)
	assert_false(load._apply_prepared_provenance_add(plan))
	assert_eq(load.provenance_snapshot(), before)
	var invalid: Dictionary = load._prepare_provenance_add("bad", "bad", &"wood", 1, 50, CarryProvenanceLedger.FREE_GATHERED)
	assert_false(invalid.ok)
	assert_eq(load.provenance_snapshot(), before)
	# Simulate the guarded internal coordinator in a unit-only fixture.
	load._provenance_busy = true
	load._provenance_applying = true
	assert_true(load._apply_prepared_provenance_add(plan))
	load._provenance_applying = false
	load._provenance_busy = false
	assert_eq(events.size(), 0)
	assert_true(load.validate_provenance())
	assert_eq(load.get_amount(&"wood"), 3)
	var after: Dictionary = load.provenance_snapshot()
	load._provenance_busy = true
	load._provenance_applying = true
	assert_false(load._apply_prepared_provenance_add(plan))
	load._provenance_applying = false
	load._provenance_busy = false
	assert_eq(load.provenance_snapshot(), after)
	assert_true(CarryFixture.add_lot(load, "op2", "lot2", &"wood", 1, 1, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_eq(events.size(), 1)
	assert_true(CarryFixture.add_lot(load, "op2", "lot2", &"wood", 1, 1, CarryProvenanceLedger.FREE_GATHERED).replayed)
	assert_false(CarryFixture.add_lot(load, "op2", "lot2", &"wood", 1, 2, CarryProvenanceLedger.FREE_GATHERED).ok)
	load.load_changed.disconnect(observer)
