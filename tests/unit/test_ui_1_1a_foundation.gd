extends TestCase
## Unit tests for UI-1.1A D2.2 visual foundation:
## - 17 atlas manifest regions & bounds
## - Bit-for-bit SHA-256 parity of all 9 runtime assets vs docs/design/ui-0-r2-2/assets/
## - Responsive scale math for 1280x720 and 1920x1080
## - D2ResourceRocksView & D2TopPlaqueView signal-driven updates, idempotent configure,
##   safe unbind, zero polling, inert non-interactive controls, and zero invented calendar.

const DOCS_ASSETS_DIR: String = "res://docs/design/ui-0-r2-2/assets/"
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_DEF: ResourceDefinition = preload("res://data/resources/food.tres")


func test_atlas_manifest_and_17_regions_integrity() -> void:
	var lib := D2AtlasLibrary.new()
	assert_true(lib.load_all(), "D2AtlasLibrary must load atlas and manifest cleanly from res://assets/ui/d2/")
	assert_true(lib.is_valid(), "Atlas library must validate all 17 required regions")
	assert_true(lib.validate_manifest_bounds(), "All 17 regions must fit within 1024x1024 atlas bounds")
	assert_eq(lib.get_region_keys().size(), 17, "Manifest must contain exactly 17 canonical regions")
	for key: String in D2AtlasLibrary.REQUIRED_REGIONS:
		var tex: AtlasTexture = lib.get_region_texture(key)
		assert_not_null(tex, "AtlasTexture must resolve for region: %s" % key)
		assert_eq(lib.get_region_texture(key), tex, "AtlasTexture must be cached for region: %s" % key)


func test_runtime_assets_match_approved_originals_bit_for_bit() -> void:
	for res_path: String in D2AtlasLibrary.REQUIRED_ASSET_PATHS:
		var fname: String = res_path.get_file()
		var orig_path: String = DOCS_ASSETS_DIR + fname
		assert_true(FileAccess.file_exists(res_path), "Runtime asset must exist: %s" % res_path)
		assert_true(FileAccess.file_exists(orig_path), "Original asset must exist: %s" % orig_path)
		var h_runtime: String = FileAccess.get_sha256(res_path)
		var h_orig: String = FileAccess.get_sha256(orig_path)
		assert_false(h_runtime.is_empty(), "SHA-256 must be readable for %s" % fname)
		assert_eq(h_runtime, h_orig, "Runtime asset must match approved D2.2 original bit-for-bit: %s" % fname)


func test_responsive_scale_720p_and_1080p() -> void:
	var s_1080: float = D2ScaleController.compute_scale_for_sizes(Vector2i(1920, 1080), Vector2(1920.0, 1080.0))
	assert_true(absf(s_1080 - 1.0) <= 0.001, "1080p baseline must use scale 1.00")

	var s_720_stretched: float = D2ScaleController.compute_scale_for_sizes(Vector2i(1280, 720), Vector2(1920.0, 1080.0))
	assert_true(absf(s_720_stretched - 1.22) <= 0.001, "720p stretched canvas_items must use scale 1.22")

	var s_720_subvp: float = D2ScaleController.compute_scale_for_sizes(Vector2i(1280, 720), Vector2(1280.0, 720.0))
	assert_true(absf(s_720_subvp - 1.22 * (1280.0 / 1920.0)) <= 0.002, "720p unstretched SubViewport must preserve identical physical ratio")


func test_rocks_and_plaque_signal_sync_idempotence_and_no_polling() -> void:
	var source := InMemoryStorageSource.new()
	var inventory := SettlementInventory.new(source)
	var lib := D2AtlasLibrary.new()
	lib.load_all()
	var theme_factory := D2ThemeFactory.new()

	var rocks := D2ResourceRocksView.new()
	add_test_child(rocks)
	rocks.setup_visuals(lib, theme_factory, 1.0)
	rocks.configure(inventory)
	rocks.configure(inventory) # idempotent

	var plaque := D2TopPlaqueView.new()
	add_test_child(plaque)
	plaque.setup_visuals(lib, theme_factory, Vector2(1920.0, 1080.0), 1.0)
	plaque.configure(inventory)
	plaque.configure(inventory) # idempotent

	assert_false(rocks.is_processing(), "D2ResourceRocksView must not poll _process")
	assert_false(rocks.is_physics_processing(), "D2ResourceRocksView must not poll _physics_process")
	assert_false(plaque.is_processing(), "D2TopPlaqueView must not poll _process")
	assert_false(plaque.is_physics_processing(), "D2TopPlaqueView must not poll _physics_process")

	assert_true(rocks.is_bound_to_inventory(inventory), "Rocks must bind to inventory_changed")
	assert_true(plaque.is_bound_to_inventory(inventory), "Plaque must bind to inventory_changed")

	assert_eq(rocks.get_displayed_text(&"wood"), "0")
	assert_eq(rocks.get_displayed_text(&"stone"), "0")
	assert_eq(rocks.get_displayed_text(&"food"), "0")
	var initial_rock_applies: int = rocks.get_apply_count()
	rocks.refresh()
	assert_eq(rocks.get_apply_count(), initial_rock_applies, "Redundant refresh must not re-apply unchanged values")

	assert_true(inventory.deposit(&"wood", 12))
	assert_true(inventory.deposit(&"stone", 6))
	assert_true(inventory.deposit(&"food", 9))
	assert_eq(rocks.get_displayed_text(&"wood"), "12")
	assert_eq(rocks.get_displayed_text(&"stone"), "6")
	assert_eq(rocks.get_displayed_text(&"food"), "9")
	assert_eq(plaque.get_exposure_tone(), HudFormatter.ExposureTone.EXPOSED_ACTIVE, "Plaque exposure must reflect active decaying resources")
	assert_eq(plaque.get_exposure_text(), "● EXPOSTO")

	# Safeguard 2: zero interactive buttons and zero invented seasons/calendar
	assert_false(plaque.has_interactive_buttons(), "UI-1.1A plaque must not instantiate interactive buttons")
	assert_eq(plaque.get_stage_subtitle_text(), "Acampamento")
	assert_false(plaque.get_stage_subtitle_text().contains("Primavera"), "Plaque must not display unimplemented seasons")
	assert_false(plaque.get_stage_subtitle_text().contains("Ano"), "Plaque must not display unimplemented calendar years")

	# Stepped vertical layout check: wood(0) < food(+2) < stone(+7)
	var rects: Array[Rect2] = rocks.get_rock_rects()
	assert_eq(rects.size(), 3)
	assert_lt(rects[0].position.y, rects[2].position.y, "Food rock must be staggered below wood rock")
	assert_lt(rects[2].position.y, rects[1].position.y, "Stone rock must be staggered below food rock")

	# Scale down regression check (1.22 -> 1.00 must not stay clamped to previous custom_minimum_size)
	rocks.apply_scale(1.22)
	plaque.apply_layout(Vector2(1920.0, 1080.0), 1.22)
	rocks.apply_scale(1.0)
	plaque.apply_layout(Vector2(1920.0, 1080.0), 1.0)
	var wood_slab: Control = rocks.get_node("RockSlab_wood") as Control
	var plaque_slab: Control = plaque.get_node("TopPlaqueSlab") as Control
	assert_true(absf(wood_slab.size.x - 104.0) <= 0.5, "Rock slab must shrink cleanly from 1.22 to 1.00")
	assert_true(absf(plaque_slab.size.x - 216.0) <= 0.5, "Plaque slab must shrink cleanly from 1.22 to 1.00")

	# Unbind disconnects cleanly
	rocks.unbind()
	plaque.unbind()
	assert_false(rocks.is_bound_to_inventory(inventory), "Rocks must disconnect on unbind")
	assert_false(plaque.is_bound_to_inventory(inventory), "Plaque must disconnect on unbind")
	var before_unbound_deposit: String = rocks.get_displayed_text(&"wood")
	assert_true(inventory.deposit(&"wood", 5))
	assert_eq(rocks.get_displayed_text(&"wood"), before_unbound_deposit, "Unbound rocks must not react to signals")

	rocks.queue_free()
	plaque.queue_free()
	await wait_process_frames(1)
