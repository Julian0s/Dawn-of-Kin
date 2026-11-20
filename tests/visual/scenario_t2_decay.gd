extends SceneTree
## Visual manual-inspection scenario for T2 centralized decay observation without waiting
## real-time minutes (no debug UI buttons added to the game HUD).
## Run with:
##   .\tools\run_game.ps1 -Resolution "1280x720" -ExtraArgs "--script","res://tests/visual/scenario_t2_decay.gd" -FailOnWarnings

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const DECAY_TIME_SCALE: float = 60.0


func _init() -> void:
	call_deferred("_start_scenario")


func _start_scenario() -> void:
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = false
	if main == null:
		push_error("Failed to instantiate MainScene for decay scenario.")
		quit(1)
		return

	root.add_child(main)

	var test_map: TestMap = main.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var wait_frames: int = 0
		while not nav.is_navigation_ready() and wait_frames < 180:
			await physics_frame
			wait_frames += 1

	await process_frame
	await physics_frame

	var inventory: SettlementInventory = main.get_settlement_inventory()
	var pile_manager: GroundPileManager = main.get_ground_pile_manager()
	var clock: EconomyClockController = main.get_economy_clock()

	if inventory == null or clock == null:
		push_error("Missing SettlementInventory or EconomyClockController in MainScene.")
		quit(1)
		return

	inventory.deposit(&"food", 12)
	inventory.deposit(&"wood", 8)
	inventory.deposit(&"stone", 6)

	var scaled_ok: bool = clock.set_time_scale(DECAY_TIME_SCALE)
	clock.decay_stepped.connect(_on_decay_stepped.bind(inventory, pile_manager))

	print("[DECAY_SCENARIO] Initial stock seeded: food=12, wood=8, stone=6 | time_scale=%.1fx (ok=%s)" % [
		DECAY_TIME_SCALE,
		str(scaled_ok),
	])
	print("[DECAY_SCENARIO] Watch HUD top-right & CampPiles: food decays first (~3s), wood decays later (~7s), stone remains 6.")


func _on_decay_stepped(losses: Dictionary, inventory: SettlementInventory, pile_manager: GroundPileManager) -> void:
	if losses.is_empty():
		return
	var pile_count: int = pile_manager.get_piles().size() if pile_manager != null else -1
	print("[DECAY_SCENARIO] Decay losses=%s | remaining -> food=%d wood=%d stone=%d | active_piles=%d" % [
		str(losses),
		inventory.get_amount(&"food"),
		inventory.get_amount(&"wood"),
		inventory.get_amount(&"stone"),
		pile_count,
	])
