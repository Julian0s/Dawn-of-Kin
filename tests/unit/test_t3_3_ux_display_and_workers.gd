class_name TestT33UxDisplayAndWorkers
extends TestCase
## Unit tests for T3.3-UX modular DisplayResolutionService geometry & monitor clamping.


func test_01_compute_safe_window_geometry_presets_on_large_monitor() -> void:
	var usable := Rect2i(0, 0, 2560, 1400)
	var dec := Vector2i(16, 39)

	var r720: Dictionary = DisplayResolutionService.compute_safe_window_geometry(
		DisplayResolutionService.PRESET_1280X720,
		Vector2i(100, 100),
		usable,
		dec
	)
	assert_eq(r720["effective_size"], Vector2i(1280, 720), "1280x720 fits large monitor without clamping")
	assert_false(bool(r720["was_clamped"]), "1280x720 should not report clamped")

	var r1080: Dictionary = DisplayResolutionService.compute_safe_window_geometry(
		DisplayResolutionService.PRESET_1920X1080,
		Vector2i(100, 100),
		usable,
		dec
	)
	assert_eq(r1080["effective_size"], Vector2i(1920, 1080), "1920x1080 fits large monitor without clamping")
	assert_false(bool(r1080["was_clamped"]), "1920x1080 should not report clamped")


func test_02_compute_safe_window_geometry_clamps_to_smaller_monitor_and_keeps_accessible() -> void:
	var usable := Rect2i(0, 0, 1620, 1032)
	var dec := Vector2i(16, 39)

	var res: Dictionary = DisplayResolutionService.compute_safe_window_geometry(
		DisplayResolutionService.PRESET_1920X1080,
		Vector2i(-400, -120),
		usable,
		dec
	)
	var eff: Vector2i = res["effective_size"] as Vector2i
	var pos: Vector2i = res["position"] as Vector2i
	assert_true(bool(res["was_clamped"]), "1920x1080 must clamp on 1620x1032 usable screen")
	assert_true(eff.x + dec.x <= usable.size.x, "Clamped width + decorations must fit monitor width")
	assert_true(eff.y + dec.y <= usable.size.y, "Clamped height + decorations must fit usable height")
	assert_true(pos.x >= usable.position.x, "Window X must stay inside usable screen")
	assert_true(pos.y >= usable.position.y, "Window titlebar Y must stay inside usable screen")
