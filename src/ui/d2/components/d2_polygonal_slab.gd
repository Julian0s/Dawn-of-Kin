class_name D2PolygonalSlab
extends TextureRect
## Polygonal D2.2 stone slab surface extending TextureRect.
## Overrides Control._has_point() using Geometry2D.is_point_in_polygon() so only
## the solid beveled stone silhouette intercepts clicks, hover, scroll, and Edge Pan,
## while the 10 px transparent shadow_pad and chamfered corners pass events through
## cleanly to the 3D RTS world.

var _base_polygon: PackedVector2Array = PackedVector2Array()
var _base_content_size: Vector2 = Vector2.ZERO
var _shadow_pad: float = D2Tokens.ATLAS_SHADOW_PAD
var _scaled_polygon: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	focus_mode = Control.FOCUS_NONE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild_scaled_polygon()


func configure_polygon(
	content_polygon: Array[Vector2],
	content_size: Vector2,
	shadow_pad: float = D2Tokens.ATLAS_SHADOW_PAD
) -> void:
	_base_polygon = PackedVector2Array(content_polygon)
	_base_content_size = content_size
	_shadow_pad = maxf(0.0, shadow_pad)
	_rebuild_scaled_polygon()


func set_scaled_size(target_size: Vector2) -> void:
	custom_minimum_size = target_size
	size = target_size
	_rebuild_scaled_polygon()


func _has_point(point: Vector2) -> bool:
	if _scaled_polygon.size() < 3:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return Geometry2D.is_point_in_polygon(point, _scaled_polygon)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Explicitly consume left, right, middle, and scroll wheel events on solid stone
		# so zero RTS orders, selection changes, or camera zoom leak to _unhandled_input().
		accept_event()


func contains_local_point(local_point: Vector2) -> bool:
	return _has_point(local_point)


func contains_global_point(global_point: Vector2) -> bool:
	var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * global_point
	return _has_point(local_point)


func get_base_polygon() -> PackedVector2Array:
	return _base_polygon.duplicate()


func get_scaled_polygon() -> PackedVector2Array:
	return _scaled_polygon.duplicate()


func get_global_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	var xform: Transform2D = get_global_transform_with_canvas()
	result.resize(_scaled_polygon.size())
	for i: int in range(_scaled_polygon.size()):
		result[i] = xform * _scaled_polygon[i]
	return result


func get_shadow_pad() -> float:
	return _shadow_pad


func _rebuild_scaled_polygon() -> void:
	if _base_polygon.size() < 3:
		_scaled_polygon = PackedVector2Array()
		return
	var base_total_w: float = _base_content_size.x + 2.0 * _shadow_pad
	var base_total_h: float = _base_content_size.y + 2.0 * _shadow_pad
	if base_total_w <= 0.0 or base_total_h <= 0.0:
		_scaled_polygon = PackedVector2Array()
		return
	var target_w: float = size.x if size.x > 0.0 else base_total_w
	var target_h: float = size.y if size.y > 0.0 else base_total_h
	var sx: float = target_w / base_total_w
	var sy: float = target_h / base_total_h
	var rebuilt := PackedVector2Array()
	rebuilt.resize(_base_polygon.size())
	for i: int in range(_base_polygon.size()):
		var pt: Vector2 = _base_polygon[i]
		rebuilt[i] = Vector2((pt.x + _shadow_pad) * sx, (pt.y + _shadow_pad) * sy)
	_scaled_polygon = rebuilt
