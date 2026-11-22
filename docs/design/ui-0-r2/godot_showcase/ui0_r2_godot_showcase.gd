extends SceneTree
## Dawn of Kin — UI-0 R2 Reproducible Isolated Godot 4.7.2 Visual Parity & Preliminary Benchmark Showcase
## Zero gameplay integration: loads the real 3D reference scene read-only, hides legacy UiLayer,
## renders all three original artistic directions using native Godot 4.7.2 Control + custom antialiased _draw()
## + CLIP_CHILDREN_ONLY masks + real painted assets, captures screenshots, and records un-vsynced frame timings.

const RUX2B_SCENE_PATH: String = "res://tests/visual/rux_2b_multi_source_selection.tscn"
const ASSETS_RES_REL: String = "docs/design/ui-0-r2/assets"
const OUT_RES_REL: String = "docs/design/ui-0-r2"

const WARMUP_FRAMES: int = 60
const FRAMES_PER_RUN: int = 180
const REPETITIONS: int = 3

var _project_dir: String = ""
var _assets_dir: String = ""
var _out_dir: String = ""

var _font_display: Font
var _font_ui: Font
var _font_ui_bold: Font

var _tex_alden: ImageTexture
var _tex_brena: ImageTexture
var _tex_emblem: ImageTexture
var _tex_astrolabe: ImageTexture
var _tex_shelter: ImageTexture
var _tex_depot: ImageTexture
var _tex_kintsugi: ImageTexture
var _tex_linen: ImageTexture
var _tex_ceramic: ImageTexture


# ------------------------------------------------------------------------------
# Custom Antialiased Native Godot 4.7.2 Sculptural Controls (Zero 9-slice text overlap!)
# ------------------------------------------------------------------------------
class AuroraOrbitalCanvas extends Control:
	var accent: Color = Color(0.87, 0.75, 0.48, 0.88)
	var dim_line: Color = Color(0.87, 0.75, 0.48, 0.32)
	var core_bg: Color = Color(0.07, 0.09, 0.10, 0.84)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		# 1. Top-Left: Three Floating Matter Pebbles linked by a delicate dawn thread (NO BOX!)
		var py: float = 36.0
		var pebble_xs: PackedFloat32Array = PackedFloat32Array([48.0, 134.0, 220.0])
		draw_line(Vector2(48.0, py), Vector2(220.0, py), dim_line, 1.5, true)
		var pebble_cols: Array[Color] = [
			Color(0.36, 0.25, 0.16, 0.92),
			Color(0.28, 0.31, 0.34, 0.92),
			Color(0.45, 0.29, 0.14, 0.92),
		]
		var pebble_rims: Array[Color] = [
			Color(0.85, 0.67, 0.42, 0.92),
			Color(0.76, 0.81, 0.85, 0.92),
			Color(0.92, 0.70, 0.38, 0.92),
		]
		for i: int in range(3):
			var c := Vector2(pebble_xs[i], py)
			draw_circle(c, 22.0, pebble_cols[i])
			draw_arc(c, 22.0, 0.0, TAU, 36, pebble_rims[i], 1.6, true)
			# Subtle exposure wind arc on wood/food pebbles
			if i != 1:
				draw_arc(c, 26.0, -PI * 0.75, -PI * 0.25, 16, Color(0.88, 0.65, 0.30, 0.75), 1.4, true)

		# 2. Bottom-Center: Floating Origin Knot (NO RECTANGULAR BAR!)
		var cx: float = w * 0.5
		var cy: float = h - 54.0
		# Delicate open celestial orbital arcs extending outward
		draw_arc(Vector2(cx, cy + 44.0), 158.0, PI * 1.18, PI * 1.82, 48, dim_line, 1.5, true)
		draw_arc(Vector2(cx, cy + 44.0), 146.0, PI * 1.24, PI * 1.76, 48, accent, 1.8, true)
		# Two floating orbital rings for founders + central dawn halo
		draw_circle(Vector2(cx - 56.0, cy), 33.0, core_bg)
		draw_arc(Vector2(cx - 56.0, cy), 33.0, 0.0, TAU, 40, accent, 2.2, true)
		draw_circle(Vector2(cx + 56.0, cy), 33.0, core_bg)
		draw_arc(Vector2(cx + 56.0, cy), 33.0, 0.0, TAU, 40, accent, 2.2, true)
		# Golden lineage thread linking both rings
		draw_line(Vector2(cx - 24.0, cy), Vector2(cx + 24.0, cy), accent, 2.0, true)
		draw_circle(Vector2(cx, cy), 22.0, Color(0.09, 0.11, 0.13, 0.94))
		draw_arc(Vector2(cx, cy), 22.0, 0.0, TAU, 32, Color(0.95, 0.85, 0.62, 0.95), 1.8, true)

		# Orbiting minimal action nodes along outer arc (Build, Tasks, Lineage)
		for pt: Vector2 in [Vector2(cx - 126.0, cy + 12.0), Vector2(cx + 126.0, cy + 12.0), Vector2(cx + 186.0, cy + 20.0)]:
			draw_circle(pt, 20.0, core_bg)
			draw_arc(pt, 20.0, 0.0, TAU, 28, accent, 1.4, true)


class KintsugiSteleCanvas extends Control:
	var stone_dark: Color = Color(0.11, 0.12, 0.13, 0.92)
	var stone_mid: Color = Color(0.17, 0.18, 0.19, 0.94)
	var gold_vein: Color = Color(0.84, 0.69, 0.39, 0.92)
	var alabaster: Color = Color(0.91, 0.88, 0.81, 0.94)

	func _draw_monolith(pts: PackedVector2Array, fill: Color, rim: Color, vein_a: Vector2, vein_b: Vector2) -> void:
		draw_colored_polygon(pts, fill)
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, rim, 1.6, true)
		if not vein_a.is_equal_approx(vein_b):
			var mid: Vector2 = vein_a.lerp(vein_b, 0.48) + Vector2(4.0, -3.0)
			draw_polyline(PackedVector2Array([vein_a, mid, vein_b]), gold_vein, 1.5, true)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		# 1. Top-Left: Three Stepped River-Stone Monoliths (asymmetric cairn, NO flat bar!)
		_draw_monolith(
			PackedVector2Array([Vector2(20, 18), Vector2(96, 14), Vector2(104, 54), Vector2(24, 58)]),
			stone_dark, Color(0.68, 0.56, 0.38, 0.78), Vector2(24, 42), Vector2(98, 28)
		)
		_draw_monolith(
			PackedVector2Array([Vector2(110, 22), Vector2(186, 18), Vector2(192, 58), Vector2(114, 60)]),
			stone_mid, Color(0.65, 0.70, 0.74, 0.78), Vector2(114, 28), Vector2(188, 48)
		)
		_draw_monolith(
			PackedVector2Array([Vector2(198, 16), Vector2(276, 20), Vector2(282, 56), Vector2(202, 56)]),
			stone_dark, Color(0.82, 0.60, 0.32, 0.82), Vector2(204, 46), Vector2(276, 30)
		)

		# 2. Top-Right: Hanging Sanctuary Ema Plaque (vertical monolith for season/time)
		_draw_monolith(
			PackedVector2Array([Vector2(w - 178, 14), Vector2(w - 18, 20), Vector2(w - 24, 96), Vector2(w - 172, 102)]),
			stone_dark, gold_vein, Vector2(w - 172, 64), Vector2(w - 22, 52)
		)

		# 3. Bottom-Left: Twin Tilted Founder Steles linked by Kintsugi Gold Seam
		_draw_monolith(
			PackedVector2Array([Vector2(22, h - 126), Vector2(112, h - 134), Vector2(118, h - 18), Vector2(18, h - 16)]),
			stone_dark, gold_vein, Vector2(22, h - 42), Vector2(114, h - 54)
		)
		_draw_monolith(
			PackedVector2Array([Vector2(128, h - 114), Vector2(218, h - 120), Vector2(224, h - 16), Vector2(124, h - 18)]),
			stone_mid, Color(0.70, 0.62, 0.45, 0.72), Vector2(128, h - 38), Vector2(220, h - 48)
		)

		# 4. Bottom-Right: Alabaster Architectural Maquette Slabs (light stone contrast!)
		_draw_monolith(
			PackedVector2Array([Vector2(w - 282, h - 84), Vector2(w - 154, h - 92), Vector2(w - 148, h - 18), Vector2(w - 278, h - 16)]),
			alabaster, Color(0.55, 0.44, 0.28, 0.9), Vector2.ZERO, Vector2.ZERO
		)
		_draw_monolith(
			PackedVector2Array([Vector2(w - 140, h - 76), Vector2(w - 20, h - 82), Vector2(w - 16, h - 16), Vector2(w - 136, h - 18)]),
			stone_dark, gold_vein, Vector2(w - 136, h - 42), Vector2(w - 18, h - 34)
		)


class LoomSeedCanvas extends Control:
	var linen: Color = Color(0.92, 0.88, 0.79, 0.95)
	var moss: Color = Color(0.19, 0.25, 0.20, 0.93)
	var clay: Color = Color(0.68, 0.35, 0.22, 0.94)
	var thread: Color = Color(0.84, 0.76, 0.60, 0.88)

	func _draw_seed_medallion(center: Vector2, rx: float, ry: float, fill: Color, rim: Color) -> void:
		var pts := PackedVector2Array()
		for i: int in range(32):
			var a: float = (float(i) / 32.0) * TAU
			var pinch: float = 1.0 - 0.16 * absf(sin(a))
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry * pinch))
		draw_colored_polygon(pts, fill)
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, rim, 1.8, true)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		# 1. Top-Left: Harvest Linen Thread with 3 Ceramic Seed Medallions (NO BOX!)
		draw_line(Vector2(24, 42), Vector2(284, 42), thread, 2.0, true)
		_draw_seed_medallion(Vector2(62, 42), 34, 22, Color(0.35, 0.24, 0.16, 0.94), thread)
		_draw_seed_medallion(Vector2(146, 42), 34, 22, Color(0.29, 0.33, 0.35, 0.94), thread)
		_draw_seed_medallion(Vector2(230, 42), 34, 22, clay, thread)

		# 2. Top-Right: Four-Petal Botanical Season Rosette + Ceramic Time Capsule
		var rx: float = w - 180.0
		var ry: float = 44.0
		draw_circle(Vector2(rx, ry), 26.0, moss)
		draw_arc(Vector2(rx, ry), 26.0, 0.0, TAU, 32, thread, 1.6, true)
		# Four glazed seasonal petals (Spring highlighted in warm moss-gold!)
		var petal_cols: Array[Color] = [
			Color(0.56, 0.75, 0.44, 0.95),
			Color(0.84, 0.68, 0.34, 0.55),
			Color(0.75, 0.42, 0.26, 0.50),
			Color(0.78, 0.83, 0.85, 0.48),
		]
		var dirs: Array[Vector2] = [Vector2(0, -11), Vector2(11, 0), Vector2(0, 11), Vector2(-11, 0)]
		for i: int in range(4):
			draw_circle(Vector2(rx, ry) + dirs[i], 7.0, petal_cols[i])
		draw_circle(Vector2(rx, ry), 4.5, linen)

		# Time capsule stitched beside petals
		_draw_seed_medallion(Vector2(w - 86.0, 44.0), 62, 22, linen, Color(0.46, 0.38, 0.28, 0.9))

		# 3. Bottom-Left: Overlapping Ceramic Family Nest (Pod silhouette!)
		draw_circle(Vector2(64, h - 56), 38.0, moss)
		draw_arc(Vector2(64, h - 56), 38.0, 0.0, TAU, 40, thread, 2.2, true)
		draw_circle(Vector2(122, h - 56), 38.0, moss)
		draw_arc(Vector2(122, h - 56), 38.0, 0.0, TAU, 40, thread, 2.2, true)
		# Sprout bud for future children (Proposal T5)
		draw_circle(Vector2(93, h - 22), 12.0, Color(0.52, 0.69, 0.41, 0.92))
		draw_arc(Vector2(93, h - 22), 12.0, 0.0, TAU, 24, linen, 1.5, true)

		# 4. Bottom-Right: Stitched Ceramic Action Petals
		_draw_seed_medallion(Vector2(w - 230, h - 44), 48, 24, linen, Color(0.46, 0.38, 0.28, 0.9))
		_draw_seed_medallion(Vector2(w - 130, h - 44), 48, 24, linen, Color(0.46, 0.38, 0.28, 0.9))
		_draw_seed_medallion(Vector2(w - 50, h - 50), 34, 34, clay, linen)


func _initialize() -> void:
	_project_dir = ProjectSettings.globalize_path("res://")
	_assets_dir = _project_dir.path_join(ASSETS_RES_REL)
	_out_dir = _project_dir.path_join(OUT_RES_REL)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run_all")


func _load_font(paths: Array[String], fallback_family: String) -> Font:
	for p: String in paths:
		if FileAccess.file_exists(p):
			var ff := FontFile.new()
			if ff.load_dynamic_font(p) == OK:
				return ff
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([fallback_family])
	return sf


func _load_tex(filename: String) -> ImageTexture:
	var img := Image.new()
	var err: Error = img.load(_assets_dir.path_join(filename))
	if err != OK:
		push_error("Missing asset: " + filename)
		return null
	return ImageTexture.create_from_image(img)


func _lbl(text: String, font: Font, sz: int, col: Color, pos: Vector2, min_sz: Vector2 = Vector2.ZERO, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if min_sz != Vector2.ZERO:
		l.size = min_sz
	l.horizontal_alignment = align
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", sz)
	l.add_theme_color_override(&"font_color", col)
	return l


func _circular_portrait(tex: Texture2D, pos: Vector2, diameter: float, border_col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = Vector2(diameter, diameter)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	sb.border_color = border_col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(diameter * 0.5))
	p.add_theme_stylebox_override(&"panel", sb)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(tr)
	return p


func _tex_rect(tex: Texture2D, pos: Vector2, sz: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = tex
	tr.position = pos
	tr.custom_minimum_size = sz
	tr.size = sz
	return tr


func _run_all() -> void:
	# CRITICAL: Disable V-Sync explicitly so measurements reflect real GPU/CPU render cost (not 60Hz clamp!)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()

	_font_display = _load_font(["C:/Windows/Fonts/palab.ttf", "C:/Windows/Fonts/georgiab.ttf"], "Palatino Linotype")
	_font_ui = _load_font(["C:/Windows/Fonts/segoeui.ttf"], "Segoe UI")
	_font_ui_bold = _load_font(["C:/Windows/Fonts/segoeuib.ttf"], "Segoe UI")

	_tex_alden = _load_tex("portrait_alden.jpg")
	_tex_brena = _load_tex("portrait_brena.jpg")
	_tex_emblem = _load_tex("emblem_dawn_of_kin.png")
	_tex_astrolabe = _load_tex("d1_astrolabe.png")
	_tex_shelter = _load_tex("d1_shelter_mini.png")
	_tex_depot = _load_tex("d1_depot_mini.png")
	_tex_kintsugi = _load_tex("d2_kintsugi_basalt.png")
	_tex_linen = _load_tex("d3_linen_weave.png")
	_tex_ceramic = _load_tex("d3_ceramic_moss.png")

	var report: Dictionary = {
		"engine": Engine.get_version_info().get("string", ""),
		"renderer": RenderingServer.get_video_adapter_name(),
		"vsync_mode": vsync_mode,
		"warmup_frames": WARMUP_FRAMES,
		"frames_per_run": FRAMES_PER_RUN,
		"repetitions": REPETITIONS,
		"total_frames_per_scenario": FRAMES_PER_RUN * REPETITIONS,
		"resolutions": {},
	}

	for sz: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var tag: String = "%dx%d" % [sz.x, sz.y]
		print("=== GODOT R2 SHOWCASE & UN-VSYNCED BENCHMARK: ", tag, " ===")
		report["resolutions"][tag] = await _run_resolution_suite(sz, tag)

	var json_path: String = _out_dir.path_join("godot_showcase/benchmark_results.json")
	DirAccess.make_dir_recursive_absolute(json_path.get_base_dir())
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("Saved benchmark_results.json -> ", json_path)
	quit(0)


func _run_resolution_suite(sz: Vector2i, tag: String) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = sz
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	root.add_child(vp)

	var main: MainScene = (load(RUX2B_SCENE_PATH) as PackedScene).instantiate() as MainScene
	vp.add_child(main)
	for _i: int in range(12):
		await process_frame

	var old_ui: CanvasLayer = main.get_node_or_null("UiLayer") as CanvasLayer
	if old_ui != null:
		old_ui.visible = false

	var inv: SettlementInventory = main.get_settlement_inventory()
	if inv != null:
		inv.deposit(&"wood", 24)
		inv.deposit(&"stone", 14)
		inv.deposit(&"food", 18)

	var cam_rig: RtsCameraRig = main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if cam_rig != null:
		cam_rig.set_focus_position(Vector2(2.5, 2.0))
		cam_rig.set_target_zoom_distance(35.0, true)

	var layer := CanvasLayer.new()
	layer.layer = 10
	vp.add_child(layer)

	var scenarios: Dictionary = {
		"BASELINE_3D": [],
		"GODOT_D1_FIO_DA_AURORA": [],
		"GODOT_D2_MARCOS_KINTSUGI": [],
		"GODOT_D3_TEAR_SEMENTE": [],
	}
	var captured: Dictionary = {}

	# Interleaved repetitions to reduce thermal drift bias between scenarios!
	for rep: int in range(REPETITIONS):
		for key: String in ["BASELINE_3D", "GODOT_D1_FIO_DA_AURORA", "GODOT_D2_MARCOS_KINTSUGI", "GODOT_D3_TEAR_SEMENTE"]:
			var ui_node: Control = null
			if key == "GODOT_D1_FIO_DA_AURORA":
				ui_node = _build_d1(sz)
			elif key == "GODOT_D2_MARCOS_KINTSUGI":
				ui_node = _build_d2(sz)
			elif key == "GODOT_D3_TEAR_SEMENTE":
				ui_node = _build_d3(sz)
			if ui_node != null:
				layer.add_child(ui_node)

			var stats: Dictionary = await _measure_block(WARMUP_FRAMES, FRAMES_PER_RUN)
			(scenarios[key] as Array).append(stats)

			if rep == 0 and ui_node != null and not captured.has(key):
				captured[key] = true
				var img: Image = vp.get_texture().get_image()
				var out_name: String = ""
				if key == "GODOT_D1_FIO_DA_AURORA":
					out_name = "G_godot_D1_fio_da_aurora_%s.png" % tag
				elif key == "GODOT_D2_MARCOS_KINTSUGI":
					out_name = "G_godot_D2_marcos_kintsugi_%s.png" % tag
				else:
					out_name = "G_godot_D3_tear_semente_%s.png" % tag
				img.save_png(_out_dir.path_join(out_name))
				print("Captured ", out_name)

			if ui_node != null:
				ui_node.queue_free()
				await process_frame
				await process_frame

	var summary: Dictionary = {}
	for key: String in scenarios.keys():
		var runs: Array = scenarios[key] as Array
		var p95s: Array[float] = []
		var avgs: Array[float] = []
		var p99s: Array[float] = []
		var over100: int = 0
		var dc: int = 0
		var nd: int = 0
		for r: Dictionary in runs:
			p95s.append(float(r.p95_ms))
			avgs.append(float(r.avg_ms))
			p99s.append(float(r.p99_ms))
			over100 += int(r.frames_over_100ms)
			dc = int(r.draw_calls)
			nd = int(r.nodes)
		p95s.sort()
		avgs.sort()
		p99s.sort()
		var mid: int = p95s.size() / 2
		summary[key] = {
			"median_avg_ms": avgs[mid],
			"median_p95_ms": p95s[mid],
			"median_p99_ms": p99s[mid],
			"total_frames_over_100ms": over100,
			"draw_calls": dc,
			"nodes": nd,
			"runs": runs,
		}
		print("%s [%s] | med_avg=%.3f ms | med_p95=%.3f ms | med_p99=%.3f ms | >100ms=%d | dc=%d | nodes=%d" % [
			key, tag, avgs[mid], p95s[mid], p99s[mid], over100, dc, nd
		])

	vp.queue_free()
	await process_frame
	return summary


func _measure_block(warmup: int, sample_count: int) -> Dictionary:
	for _w: int in range(warmup):
		await process_frame
	var times: Array[float] = []
	times.resize(sample_count)
	var over100: int = 0
	var prev: int = Time.get_ticks_usec()
	for i: int in range(sample_count):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - prev) / 1000.0
		times[i] = ms
		if ms > 100.0:
			over100 += 1
		prev = now
	times.sort()
	var total: float = 0.0
	for t: float in times:
		total += t
	var idx95: int = clampi(int(ceil(float(sample_count) * 0.95)) - 1, 0, sample_count - 1)
	var idx99: int = clampi(int(ceil(float(sample_count) * 0.99)) - 1, 0, sample_count - 1)
	return {
		"avg_ms": total / float(sample_count),
		"p95_ms": times[idx95],
		"p99_ms": times[idx99],
		"frames_over_100ms": over100,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}


func _build_d1(sz: Vector2i) -> Control:
	var c := Control.new()
	c.size = Vector2(sz)
	var canvas := AuroraOrbitalCanvas.new()
	canvas.size = Vector2(sz)
	c.add_child(canvas)

	var ivory := Color(0.96, 0.93, 0.85, 1.0)
	var gold := Color(0.89, 0.77, 0.50, 1.0)
	# Floating Pebble numbers (zero box!)
	c.add_child(_lbl("24", _font_display, 15, ivory, Vector2(26, 26), Vector2(44, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("MAD", _font_ui_bold, 9, gold, Vector2(26, 61), Vector2(44, 14), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("14", _font_display, 15, ivory, Vector2(112, 26), Vector2(44, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("PED", _font_ui_bold, 9, Color(0.80, 0.85, 0.88), Vector2(112, 61), Vector2(44, 14), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("18", _font_display, 15, ivory, Vector2(198, 26), Vector2(44, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("ALI", _font_ui_bold, 9, Color(0.92, 0.72, 0.42), Vector2(198, 61), Vector2(44, 14), HORIZONTAL_ALIGNMENT_CENTER))

	# Top-Right Astrolabe Dial (floating sculpture)
	c.add_child(_tex_rect(_tex_astrolabe, Vector2(sz.x - 94, 14), Vector2(76, 76)))
	c.add_child(_lbl("PRIMAVERA · ANO I", _font_display, 13, ivory, Vector2(sz.x - 270, 28), Vector2(166, 20), HORIZONTAL_ALIGNMENT_RIGHT))
	c.add_child(_lbl("Clareira Inicial · 1×  2×  4×", _font_ui, 11, gold, Vector2(sz.x - 270, 50), Vector2(166, 18), HORIZONTAL_ALIGNMENT_RIGHT))

	# Bottom-Center Origin Knot Portraits + Emblem (NO BAR!)
	var cx: float = float(sz.x) * 0.5
	var cy: float = float(sz.y) - 54.0
	c.add_child(_circular_portrait(_tex_alden, Vector2(cx - 84, cy - 28), 56, gold))
	c.add_child(_circular_portrait(_tex_brena, Vector2(cx + 28, cy - 28), 56, gold))
	c.add_child(_tex_rect(_tex_emblem, Vector2(cx - 16, cy - 16), Vector2(32, 32)))
	c.add_child(_lbl("T", _font_display, 13, gold, Vector2(cx - 146, cy + 2), Vector2(40, 20), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("B", _font_display, 13, ivory, Vector2(cx + 106, cy + 2), Vector2(40, 20), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("H", _font_display, 13, gold, Vector2(cx + 166, cy + 10), Vector2(40, 20), HORIZONTAL_ALIGNMENT_CENTER))

	return c


func _build_d2(sz: Vector2i) -> Control:
	var c := Control.new()
	c.size = Vector2(sz)
	var canvas := KintsugiSteleCanvas.new()
	canvas.size = Vector2(sz)
	c.add_child(canvas)

	var ivory := Color(0.95, 0.92, 0.85, 1.0)
	var gold := Color(0.87, 0.72, 0.43, 1.0)
	var dark := Color(0.14, 0.12, 0.10, 1.0)

	# Stepped Stone Counts
	c.add_child(_lbl("MAD 24", _font_display, 13, ivory, Vector2(26, 26), Vector2(72, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("PED 14", _font_display, 13, ivory, Vector2(114, 28), Vector2(74, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("ALI 18", _font_display, 13, ivory, Vector2(204, 26), Vector2(72, 22), HORIZONTAL_ALIGNMENT_CENTER))

	# Hanging Ema Plaque
	c.add_child(_lbl("PRIMAVERA", _font_display, 14, gold, Vector2(sz.x - 168, 28), Vector2(140, 20), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("Ano I · 1×  2×  4×", _font_ui, 11, ivory, Vector2(sz.x - 168, 56), Vector2(140, 18), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("Exposto", _font_ui_bold, 10, Color(0.92, 0.67, 0.36), Vector2(sz.x - 168, 76), Vector2(140, 16), HORIZONTAL_ALIGNMENT_CENTER))

	# Twin Founder Steles
	c.add_child(_circular_portrait(_tex_alden, Vector2(42, sz.y - 122), 52, gold))
	c.add_child(_lbl("Alden", _font_display, 13, ivory, Vector2(24, sz.y - 62), Vector2(88, 18), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("Pessoal", _font_ui, 10, gold, Vector2(24, sz.y - 42), Vector2(88, 16), HORIZONTAL_ALIGNMENT_CENTER))

	c.add_child(_circular_portrait(_tex_brena, Vector2(148, sz.y - 110), 52, Color(0.75, 0.68, 0.52)))
	c.add_child(_lbl("Brena", _font_display, 13, ivory, Vector2(130, sz.y - 52), Vector2(88, 18), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("Coletando", _font_ui, 10, Color(0.66, 0.80, 0.56), Vector2(130, sz.y - 34), Vector2(88, 16), HORIZONTAL_ALIGNMENT_CENTER))

	# Alabaster Construction Maquette Slab
	c.add_child(_tex_rect(_tex_shelter, Vector2(sz.x - 270, sz.y - 82), Vector2(54, 54)))
	c.add_child(_lbl("Construir", _font_display, 14, dark, Vector2(sz.x - 214, sz.y - 68), Vector2(72, 20)))
	c.add_child(_lbl("Maquetes [B]", _font_ui, 10, Color(0.36, 0.29, 0.22), Vector2(sz.x - 214, sz.y - 48), Vector2(72, 16)))
	c.add_child(_lbl("Tarefas [T]\nLinhagem [H]", _font_ui_bold, 11, ivory, Vector2(sz.x - 128, sz.y - 66), Vector2(104, 38), HORIZONTAL_ALIGNMENT_CENTER))

	return c


func _build_d3(sz: Vector2i) -> Control:
	var c := Control.new()
	c.size = Vector2(sz)
	var canvas := LoomSeedCanvas.new()
	canvas.size = Vector2(sz)
	c.add_child(canvas)

	var ivory := Color(0.96, 0.93, 0.86, 1.0)
	var dark := Color(0.18, 0.15, 0.11, 1.0)

	# Seed Medallion Counters
	c.add_child(_lbl("24", _font_display, 15, ivory, Vector2(36, 31), Vector2(52, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("14", _font_display, 15, ivory, Vector2(120, 31), Vector2(52, 22), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("18", _font_display, 15, ivory, Vector2(204, 31), Vector2(52, 22), HORIZONTAL_ALIGNMENT_CENTER))

	# Time Capsule beside Four-Petal Rosette
	c.add_child(_lbl("Ano 1 · 1×", _font_display, 13, dark, Vector2(sz.x - 138, 34), Vector2(104, 20), HORIZONTAL_ALIGNMENT_CENTER))

	# Ceramic Family Nest
	c.add_child(_circular_portrait(_tex_alden, Vector2(36, sz.y - 84), 56, Color(0.86, 0.78, 0.62)))
	c.add_child(_circular_portrait(_tex_brena, Vector2(94, sz.y - 84), 56, Color(0.86, 0.78, 0.62)))
	c.add_child(_lbl("+", _font_ui_bold, 12, ivory, Vector2(83, sz.y - 31), Vector2(20, 18), HORIZONTAL_ALIGNMENT_CENTER))

	# Stitched Action Petals
	c.add_child(_lbl("Linhagem", _font_display, 12, dark, Vector2(sz.x - 270, sz.y - 53), Vector2(80, 18), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("Tarefas", _font_display, 12, dark, Vector2(sz.x - 170, sz.y - 53), Vector2(80, 18), HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(_lbl("Obras", _font_display, 12, ivory, Vector2(sz.x - 80, sz.y - 59), Vector2(60, 18), HORIZONTAL_ALIGNMENT_CENTER))

	return c
