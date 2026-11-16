class_name DisplayResolutionService
extends RefCounted
## Modular window resolution switcher designed for reuse in a future Settings menu.
## Changes only the game Window size/position in windowed mode without reloading scenes,
## restarting match state, or altering OS display settings.

const PRESET_1280X720: Vector2i = Vector2i(1280, 720)
const PRESET_1920X1080: Vector2i = Vector2i(1920, 1080)
const MIN_SAFE_WIDTH: int = 640
const MIN_SAFE_HEIGHT: int = 360


static func compute_safe_window_geometry(
	requested_size: Vector2i,
	current_pos: Vector2i,
	usable_rect: Rect2i,
	decoration_overhead: Vector2i = Vector2i.ZERO
) -> Dictionary:
	var req_w: int = maxi(requested_size.x, MIN_SAFE_WIDTH)
	var req_h: int = maxi(requested_size.y, MIN_SAFE_HEIGHT)
	var req := Vector2i(req_w, req_h)

	var overhead_x: int = maxi(decoration_overhead.x, 0)
	var overhead_y: int = maxi(decoration_overhead.y, 0)
	var effective_size: Vector2i = req
	var safe_pos: Vector2i = current_pos
	var was_clamped: bool = false

	if usable_rect.size.x > 0 and usable_rect.size.y > 0:
		var max_client_w: int = maxi(usable_rect.size.x - overhead_x, mini(MIN_SAFE_WIDTH, usable_rect.size.x))
		var max_client_h: int = maxi(usable_rect.size.y - overhead_y, mini(MIN_SAFE_HEIGHT, usable_rect.size.y))
		var eff_w: int = mini(req.x, max_client_w)
		var eff_h: int = mini(req.y, max_client_h)
		effective_size = Vector2i(eff_w, eff_h)
		was_clamped = (effective_size != req)

		var total_w: int = eff_w + overhead_x
		var total_h: int = eff_h + overhead_y
		var min_x: int = usable_rect.position.x
		var min_y: int = usable_rect.position.y
		var max_x: int = maxi(min_x, usable_rect.position.x + usable_rect.size.x - total_w)
		var max_y: int = maxi(min_y, usable_rect.position.y + usable_rect.size.y - total_h)

		var target_x: int = current_pos.x
		var target_y: int = current_pos.y
		if target_x < min_x or target_x > max_x:
			target_x = min_x + int((usable_rect.size.x - total_w) / 2.0)
		if target_y < min_y or target_y > max_y:
			target_y = min_y + int((usable_rect.size.y - total_h) / 2.0)

		safe_pos = Vector2i(
			clampi(target_x, min_x, max_x),
			clampi(target_y, min_y, max_y)
		)

	return {
		"requested_size": req,
		"effective_size": effective_size,
		"was_clamped": was_clamped,
		"position": safe_pos,
		"usable_rect": usable_rect,
	}


func apply_resolution(window: Window, requested_size: Vector2i) -> Dictionary:
	if window == null or not is_instance_valid(window):
		return {
			"ok": false,
			"reason": "missing_window",
			"requested_size": requested_size,
			"effective_size": Vector2i.ZERO,
			"was_clamped": false,
		}

	var screen_idx: int = window.current_screen
	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_idx)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		var screen_size: Vector2i = DisplayServer.screen_get_size(screen_idx)
		if screen_size.x > 0 and screen_size.y > 0:
			usable_rect = Rect2i(Vector2i.ZERO, screen_size)

	var decoration_overhead := Vector2i.ZERO
	if window.mode == Window.MODE_WINDOWED and window.size.x > 0 and window.size.y > 0:
		var with_dec: Vector2i = window.get_size_with_decorations()
		if with_dec.x >= window.size.x and with_dec.y >= window.size.y:
			decoration_overhead = with_dec - window.size

	var geom: Dictionary = compute_safe_window_geometry(
		requested_size,
		window.position,
		usable_rect,
		decoration_overhead
	)
	var effective_size: Vector2i = geom["effective_size"] as Vector2i
	var safe_pos: Vector2i = geom["position"] as Vector2i

	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	window.size = effective_size
	if usable_rect.size.x > 0 and usable_rect.size.y > 0:
		window.position = safe_pos

	var actual_size: Vector2i = window.size
	return {
		"ok": true,
		"reason": "",
		"requested_size": geom["requested_size"],
		"effective_size": actual_size,
		"target_effective_size": effective_size,
		"was_clamped": bool(geom["was_clamped"]) or actual_size != requested_size,
		"position": window.position,
		"usable_rect": usable_rect,
	}


static func format_resolution_status(window: Window, requested_size: Vector2i = Vector2i.ZERO) -> String:
	if window == null or not is_instance_valid(window):
		return "Atual: indisponível"
	var actual: Vector2i = window.size
	var text: String = "Atual: %d×%d" % [actual.x, actual.y]
	if requested_size.x > 0 and requested_size.y > 0 and actual != requested_size:
		text += " (limitado pelo monitor; alvo %d×%d)" % [requested_size.x, requested_size.y]
	return text
