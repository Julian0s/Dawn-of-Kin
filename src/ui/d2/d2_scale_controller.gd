class_name D2ScaleController
extends RefCounted
## Computes the responsive D2.2 UI scale factor for 1280x720 and 1920x1080 viewports.
## Produces scale=1.00 at 1080p and scale=1.22 on a 1920x1080 canvas_items 720p window
## (matching physical proportions of G_godot_D2_2_hud_1280x720.png and 1920x1080.png).


static func compute_scale_for_sizes(physical_size: Vector2i, logical_size: Vector2) -> float:
	if physical_size.x <= 0 or logical_size.x <= 0.0:
		return D2Tokens.SCALE_1080P
	var stretch_ratio: float = float(physical_size.x) / logical_size.x
	if stretch_ratio <= 0.01:
		return D2Tokens.SCALE_1080P
	var target_physical_scale: float = D2Tokens.SCALE_1080P
	if physical_size.x <= D2Tokens.PHYSICAL_WIDTH_720P_THRESHOLD:
		target_physical_scale = D2Tokens.SCALE_720P_STRETCHED * (
			D2Tokens.PHYSICAL_720P_WIDTH / D2Tokens.LOGICAL_BASELINE_WIDTH
		)
	return clampf(target_physical_scale / stretch_ratio, 0.5, 2.0)


static func compute_scale_for_viewport(viewport: Viewport) -> float:
	if viewport == null:
		return D2Tokens.SCALE_1080P
	var logical_size: Vector2 = viewport.get_visible_rect().size
	var physical_size: Vector2i = Vector2i(int(round(logical_size.x)), int(round(logical_size.y)))
	if viewport is Window:
		var win: Window = viewport as Window
		if win.size.x > 0 and win.size.y > 0:
			physical_size = win.size
	elif viewport is SubViewport:
		var sv: SubViewport = viewport as SubViewport
		if sv.size.x > 0 and sv.size.y > 0:
			physical_size = sv.size
	return compute_scale_for_sizes(physical_size, logical_size)
