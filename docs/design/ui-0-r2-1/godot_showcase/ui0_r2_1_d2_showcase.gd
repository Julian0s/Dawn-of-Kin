extends SceneTree
## UI-0 R2.1 — Isolated Interactive Showcase & Un-Vsynced A/B Benchmark (Direction D2.1)
## Zero production gameplay edits. Loads MainScene strictly as a live 3D visual backdrop.
##
## Modes:
##   Default (automated): Captures 5 live Godot state screenshots (rest 720p/1080p, founder selected,
##   construction mode, pause modal) and runs un-vsynced A/B benchmark (BASELINE_3D vs D2_1_PROCEDURAL_REST
##   vs D2_1_ATLAS_REST vs D2_1_ATLAS_ACTIVE) with 60 warmup + 3x180 interleaved frames = 540 frames/scenario.
##
##   Interactive (--interactive): Keeps window open for live mouse/keyboard testing of:
##   - Click Alden / Brena (keys 1 / 2): Diptych elevation + sliding Inspection Tablet + Personal/Community toggle
##   - Click Construir (key B): Alabaster Maquette Plinth + Shelter/Depot pick + Valid/Invalid preview (key V)
##   - Click Menu (key M) / Esc: Deterministic Esc unwind hierarchy + Pause Monolith + Anti-click-through

const WARMUP_FRAMES := 60
const MEASURE_FRAMES := 180
const REPETITIONS := 3

const ASSETS_DIR := "res://docs/design/ui-0-r2-1/assets/"
const OUT_DIR := "res://docs/design/ui-0-r2-1/"
const BENCH_JSON := "res://docs/design/ui-0-r2-1/godot_showcase/benchmark_results_r2_1.json"

var _font_serif: Font = null
var _font_sans: Font = null
var _atlas_tex: Texture2D = null
var _manifest: Dictionary = {}
var _tex_alden: Texture2D = null
var _tex_brena: Texture2D = null
var _tex_emblem: Texture2D = null
var _tex_shelter: Texture2D = null
var _tex_depot: Texture2D = null
var _interactive_mode: bool = false


# ------------------------------------------------------------------------------
# PROCEDURAL TWIN (for honest A/B benchmark vs Pre-Baked AtlasTexture!)
# Uses unified 8-degree cleaved bevels with edge-only golden Aurora seams (ZERO lines across text).
# ------------------------------------------------------------------------------
class ProceduralCleavedCanvas extends Control:
	var scale_k: float = 1.0

	func _draw() -> void:
		var s := scale_k
		var w := size.x
		var h := size.y
		var basalt := Color(0.095, 0.106, 0.122, 0.94)
		var tray := Color(0.045, 0.052, 0.062, 0.84)
		var alab := Color(0.935, 0.916, 0.872, 0.97)
		var gold := Color(0.875, 0.737, 0.447, 0.92)
		var gold_dim := Color(0.875, 0.737, 0.447, 0.34)
		var amber := Color(0.85, 0.61, 0.31, 0.85)
		var slate := Color(0.56, 0.61, 0.65, 0.75)

		# 1. Top-Left Stockpile Monolith (292x54)
		var lx := 18.0 * s
		var ty := 14.0 * s
		_draw_slab(Vector2(lx, ty), Vector2(292.0 * s, 54.0 * s), 10.0 * s, basalt, gold_dim, 3, gold)
		for i in range(3):
			var rx := lx + (18.0 + i * 90.0) * s
			var rc := Rect2(rx, ty + 8.0 * s, 80.0 * s, 38.0 * s)
			draw_rect(rc, tray, true)
			draw_rect(rc, amber if i != 1 else slate, false, 1.2)

		# 2. Top-Right Solar Cycle Monolith (236x86)
		var rx0 := w - 254.0 * s
		_draw_slab(Vector2(rx0, ty), Vector2(236.0 * s, 86.0 * s), 12.0 * s, basalt, gold_dim, 1, gold)
		draw_rect(Rect2(rx0 + 18.0 * s, ty + 44.0 * s, 198.0 * s, 28.0 * s), tray, true)

		# 3. Bottom-Left Joined Founder Diptych (2 halves x 104x136)
		var by := h - 150.0 * s
		_draw_half_left(Vector2(lx, by), Vector2(104.0 * s, 136.0 * s), 12.0 * s, basalt, gold_dim, gold)
		draw_rect(Rect2(lx + 14.0 * s, by + 92.0 * s, 82.0 * s, 34.0 * s), tray, true)
		_draw_half_right(Vector2(lx + 106.0 * s, by), Vector2(104.0 * s, 136.0 * s), 12.0 * s, basalt, gold_dim, gold)
		draw_rect(Rect2(lx + 114.0 * s, by + 92.0 * s, 82.0 * s, 34.0 * s), tray, true)

		# 4. Bottom-Right Alabaster Construction Keystone + Basalt Utility Wedge
		var cmd_y := h - 80.0 * s
		var bx := w - 338.0 * s
		_draw_slab(Vector2(bx, cmd_y), Vector2(176.0 * s, 66.0 * s), 12.0 * s, alab, Color(0.54, 0.45, 0.30, 0.9), 3, Color(0.76, 0.60, 0.32, 0.95))
		var ux := w - 154.0 * s
		_draw_slab(Vector2(ux, cmd_y), Vector2(136.0 * s, 66.0 * s), 12.0 * s, basalt, gold_dim, 1, gold)
		draw_rect(Rect2(ux + 14.0 * s, cmd_y + 8.0 * s, 108.0 * s, 22.0 * s), tray, true)
		draw_rect(Rect2(ux + 10.0 * s, cmd_y + 36.0 * s, 108.0 * s, 22.0 * s), tray, true)

	func _draw_slab(pos: Vector2, sz: Vector2, bev: float, fill_c: Color, rim_c: Color, seam_edge: int, seam_c: Color) -> void:
		var pts := PackedVector2Array([
			pos + Vector2(bev, 0.0),
			pos + Vector2(sz.x, 0.0),
			pos + Vector2(sz.x - bev, sz.y),
			pos + Vector2(0.0, sz.y),
		])
		draw_colored_polygon(pts, fill_c)
		var ring := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(ring, rim_c, 1.4, true)
		var p1 := pts[seam_edge % 4]
		var p2 := pts[(seam_edge + 1) % 4]
		draw_line(p1, p2, seam_c, 2.6, true)

	func _draw_half_left(pos: Vector2, sz: Vector2, bev: float, fill_c: Color, rim_c: Color, seam_c: Color) -> void:
		var pts := PackedVector2Array([
			pos + Vector2(bev, 0.0),
			pos + Vector2(sz.x, 0.0),
			pos + Vector2(sz.x, sz.y),
			pos + Vector2(0.0, sz.y),
		])
		draw_colored_polygon(pts, fill_c)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), rim_c, 1.4, true)
		draw_line(pts[1], pts[2], seam_c, 2.4, true)

	func _draw_half_right(pos: Vector2, sz: Vector2, bev: float, fill_c: Color, rim_c: Color, seam_c: Color) -> void:
		var pts := PackedVector2Array([
			pos + Vector2(0.0, 0.0),
			pos + Vector2(sz.x, 0.0),
			pos + Vector2(sz.x - bev, sz.y),
			pos + Vector2(0.0, sz.y),
		])
		draw_colored_polygon(pts, fill_c)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), rim_c, 1.4, true)
		draw_line(pts[3], pts[0], seam_c, 2.4, true)


# ------------------------------------------------------------------------------
# ATLAS-BACKED INTERACTIVE D2.1 HUD CONTROLLER (Zero gameplay coupling!)
# ------------------------------------------------------------------------------
class D21AtlasHud extends Control:
	var atlas_tex: Texture2D
	var manifest: Dictionary
	var font_serif: Font
	var font_sans: Font
	var tex_alden: Texture2D
	var tex_brena: Texture2D
	var tex_emblem: Texture2D
	var tex_shelter: Texture2D
	var tex_depot: Texture2D
	var scale_k: float = 1.0
	var show_demo_bar: bool = false

	# Interactive UI state (strictly isolated to showcase)
	var selected_founder: String = ""  # "", "alden", "brena"
	var alden_personal: bool = true
	var construction_open: bool = false
	var selected_building: String = "depot"  # "shelter", "depot"
	var preview_valid: bool = true
	var pause_open: bool = false
	var speed_idx: int = 1  # 0=pause, 1=1x, 2=2x, 3=4x

	# Node references for real stateful updates & short Tweens (120-160 ms)
	var _alden_root: Control
	var _alden_slab: TextureRect
	var _alden_status_lbl: Label
	var _brena_root: Control
	var _brena_slab: TextureRect
	var _inspector_root: Control
	var _insp_name: Label
	var _insp_role: Label
	var _insp_mode_badge: Label
	var _insp_carry_lbl: Label
	var _insp_carry_fill: ColorRect
	var _insp_toggle_btn: Button
	var _construction_root: Control
	var _valid_keystone: Control
	var _valid_slab: TextureRect
	var _valid_lbl: Label
	var _site_inspector: Control
	var _pause_root: Control
	var _shelter_hl: ColorRect
	var _depot_hl: ColorRect
	var _alden_base_y: float = 0.0
	var _brena_base_y: float = 0.0

	func _atlas_region(key: String) -> AtlasTexture:
		var r: Dictionary = manifest["regions"][key]
		var at := AtlasTexture.new()
		at.atlas = atlas_tex
		at.region = Rect2(float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]))
		return at

	func _make_piece(key: String, pos: Vector2) -> TextureRect:
		var r: Dictionary = manifest["regions"][key]
		var pad := float(manifest["shadow_pad"])
		var tr := TextureRect.new()
		tr.texture = _atlas_region(key)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var w := float(r["w"]) * scale_k
		var h := float(r["h"]) * scale_k
		tr.custom_minimum_size = Vector2(w, h)
		tr.size = Vector2(w, h)
		tr.position = pos - Vector2(pad * scale_k, pad * scale_k)
		tr.mouse_filter = Control.MOUSE_FILTER_STOP  # Anti-click-through on every solid stone slab!
		return tr

	func _lbl(txt: String, pos: Vector2, sz: Vector2, px: int, col: Color, serif: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
		var l := Label.new()
		l.text = txt
		l.position = pos
		l.size = sz
		l.horizontal_alignment = align
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override(&"font_size", max(9, int(round(px * scale_k))))
		l.add_theme_color_override(&"font_color", col)
		var f := font_serif if serif else font_sans
		if f != null:
			l.add_theme_font_override(&"font", f)
		return l

	func _circular_portrait(tex: Texture2D, pos: Vector2, diam: float, border_col: Color) -> Control:
		var frame := Panel.new()
		frame.position = pos
		frame.size = Vector2(diam, diam)
		frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.09, 0.11, 1.0)
		sb.set_corner_radius_all(int(diam * 0.5))
		sb.set_border_width_all(max(1, int(round(2.0 * scale_k))))
		sb.border_color = border_col
		frame.add_theme_stylebox_override(&"panel", sb)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
		return frame

	func _hitbox_btn(pos: Vector2, sz: Vector2, cb: Callable) -> Button:
		var b := Button.new()
		b.position = pos
		b.size = sz
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		b.add_theme_stylebox_override(&"normal", empty)
		b.add_theme_stylebox_override(&"pressed", empty)
		var hov := StyleBoxFlat.new()
		hov.bg_color = Color(0.875, 0.737, 0.447, 0.12)
		b.add_theme_stylebox_override(&"hover", hov)
		b.pressed.connect(cb)
		return b

	func build(vp_size: Vector2) -> void:
		size = vp_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # Empty screen passes straight to 3D!
		var s := scale_k
		var w := vp_size.x
		var h := vp_size.y
		var ivory := Color(0.957, 0.937, 0.894, 1.0)
		var muted := Color(0.74, 0.71, 0.65, 1.0)
		var gold := Color(0.875, 0.737, 0.447, 1.0)
		var moss := Color(0.66, 0.81, 0.57, 1.0)
		var ink := Color(0.114, 0.094, 0.075, 1.0)
		var ink_sub := Color(0.33, 0.28, 0.22, 1.0)

		# 1. TOP-LEFT: Unified Stepped Stockpile Monolith (3 cleanly separated recessed stone trays)
		var lx := 18.0 * s
		var ty := 14.0 * s
		add_child(_make_piece("stockpile_monolith", Vector2(lx, ty)))
		var res_items := [
			["MAD", "24", Color(0.90, 0.74, 0.44, 1.0)],
			["PED", "14", Color(0.79, 0.83, 0.86, 1.0)],
			["ALI", "18", Color(0.92, 0.69, 0.37, 1.0)],
		]
		for i in range(3):
			var tx := lx + (22.0 + i * 90.0) * s
			add_child(_lbl(res_items[i][0], Vector2(tx, ty + 11.0 * s), Vector2(36.0 * s, 16.0 * s), 10, res_items[i][2], false, HORIZONTAL_ALIGNMENT_LEFT))
			add_child(_lbl(res_items[i][1], Vector2(tx + 34.0 * s, ty + 11.0 * s), Vector2(36.0 * s, 28.0 * s), 17, ivory, true, HORIZONTAL_ALIGNMENT_RIGHT))
			add_child(_lbl("EXPOSTO" if i != 1 else "ESTÁVEL", Vector2(tx, ty + 28.0 * s), Vector2(46.0 * s, 14.0 * s), 8, muted, false, HORIZONTAL_ALIGNMENT_LEFT))

		# 2. TOP-RIGHT: Solar Cycle Monolith ("Marco de Ciclo" — ZERO Japanese ema, ZERO crossing veins!)
		var rx0 := w - 254.0 * s
		add_child(_make_piece("cycle_monolith", Vector2(rx0, ty)))
		add_child(_lbl("NÍVEL I · ACAMPAMENTO", Vector2(rx0 + 20.0 * s, ty + 7.0 * s), Vector2(194.0 * s, 14.0 * s), 9, gold, false, HORIZONTAL_ALIGNMENT_LEFT))
		add_child(_lbl("Ano I · Ciclo 1 (T4)", Vector2(rx0 + 20.0 * s, ty + 21.0 * s), Vector2(194.0 * s, 20.0 * s), 14, ivory, true, HORIZONTAL_ALIGNMENT_LEFT))
		add_child(_lbl("|| [1x] 2x 4x", Vector2(rx0 + 22.0 * s, ty + 47.0 * s), Vector2(96.0 * s, 22.0 * s), 10, ivory, false, HORIZONTAL_ALIGNMENT_LEFT))
		add_child(_lbl("● Exposto", Vector2(rx0 + 120.0 * s, ty + 47.0 * s), Vector2(64.0 * s, 22.0 * s), 9, Color(0.92, 0.70, 0.37, 1.0), false, HORIZONTAL_ALIGNMENT_LEFT))
		add_child(_lbl("☰", Vector2(rx0 + 194.0 * s, ty + 46.0 * s), Vector2(20.0 * s, 22.0 * s), 12, gold, false, HORIZONTAL_ALIGNMENT_CENTER))
		add_child(_hitbox_btn(Vector2(rx0 + 188.0 * s, ty + 42.0 * s), Vector2(32.0 * s, 32.0 * s), func() -> void: toggle_pause()))

		# 3. BOTTOM-LEFT: Joined Founder Diptych (Alden + Brena sharing ONE central golden seam + Crown Emblem!)
		var by := h - 150.0 * s
		_alden_base_y = by
		_brena_base_y = by

		_alden_root = Control.new()
		_alden_root.position = Vector2(lx, by)
		_alden_root.size = Vector2(104.0 * s, 136.0 * s)
		_alden_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_alden_root)
		_alden_slab = _make_piece("founder_half_left", Vector2.ZERO)
		_alden_root.add_child(_alden_slab)
		_alden_root.add_child(_circular_portrait(tex_alden, Vector2(25.0 * s, 16.0 * s), 58.0 * s, gold))
		_alden_root.add_child(_lbl("Alden", Vector2(16.0 * s, 94.0 * s), Vector2(78.0 * s, 17.0 * s), 13, ivory, true, HORIZONTAL_ALIGNMENT_CENTER))
		_alden_status_lbl = _lbl("Livre", Vector2(16.0 * s, 110.0 * s), Vector2(78.0 * s, 14.0 * s), 10, gold, false, HORIZONTAL_ALIGNMENT_CENTER)
		_alden_root.add_child(_alden_status_lbl)
		_alden_root.add_child(_hitbox_btn(Vector2(0, 0), Vector2(104.0 * s, 136.0 * s), func() -> void: select_founder("alden")))

		_brena_root = Control.new()
		_brena_root.position = Vector2(lx + 106.0 * s, by)
		_brena_root.size = Vector2(104.0 * s, 136.0 * s)
		_brena_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_brena_root)
		_brena_slab = _make_piece("founder_half_right", Vector2.ZERO)
		_brena_root.add_child(_brena_slab)
		_brena_root.add_child(_circular_portrait(tex_brena, Vector2(19.0 * s, 16.0 * s), 58.0 * s, gold))
		_brena_root.add_child(_lbl("Brena", Vector2(10.0 * s, 94.0 * s), Vector2(78.0 * s, 17.0 * s), 13, ivory, true, HORIZONTAL_ALIGNMENT_CENTER))
		_brena_root.add_child(_lbl("Coletando", Vector2(10.0 * s, 110.0 * s), Vector2(78.0 * s, 14.0 * s), 10, moss, false, HORIZONTAL_ALIGNMENT_CENTER))
		_brena_root.add_child(_hitbox_btn(Vector2(0, 0), Vector2(104.0 * s, 136.0 * s), func() -> void: select_founder("brena")))

		# Crown Emblem straddling the central joining Aurora Seam!
		var crown := _circular_portrait(tex_emblem, Vector2(lx + 91.0 * s, by - 14.0 * s), 28.0 * s, gold)
		add_child(crown)

		# 3B. CONTEXTUAL FOUNDER INSPECTION TABLET (Docked flush to Diptych right edge — hidden at rest!)
		_inspector_root = Control.new()
		_inspector_root.position = Vector2(lx + 210.0 * s, by)
		_inspector_root.size = Vector2(332.0 * s, 136.0 * s)
		_inspector_root.visible = false
		_inspector_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_inspector_root)
		_inspector_root.add_child(_make_piece("founder_inspector_tablet", Vector2.ZERO))
		_insp_name = _lbl("Alden · Fundador", Vector2(16.0 * s, 10.0 * s), Vector2(150.0 * s, 20.0 * s), 14, ivory, true)
		_inspector_root.add_child(_insp_name)
		_insp_mode_badge = _lbl("PESSOAL", Vector2(152.0 * s, 12.0 * s), Vector2(60.0 * s, 16.0 * s), 9, gold, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_inspector_root.add_child(_insp_mode_badge)
		_insp_role = _lbl("Adulto · Proteção dos Líderes", Vector2(16.0 * s, 29.0 * s), Vector2(196.0 * s, 16.0 * s), 10, muted)
		_inspector_root.add_child(_insp_role)
		_insp_carry_lbl = _lbl("Carga: 8 / 20 peso (40%) · 4,0 m/s", Vector2(20.0 * s, 53.0 * s), Vector2(186.0 * s, 16.0 * s), 10, ivory)
		_inspector_root.add_child(_insp_carry_lbl)
		var bar_bg := ColorRect.new()
		bar_bg.position = Vector2(20.0 * s, 74.0 * s)
		bar_bg.size = Vector2(184.0 * s, 6.0 * s)
		bar_bg.color = Color(1, 1, 1, 0.12)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inspector_root.add_child(bar_bg)
		_insp_carry_fill = ColorRect.new()
		_insp_carry_fill.position = Vector2(20.0 * s, 74.0 * s)
		_insp_carry_fill.size = Vector2(74.0 * s, 6.0 * s)
		_insp_carry_fill.color = gold
		_insp_carry_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inspector_root.add_child(_insp_carry_fill)

		_insp_toggle_btn = Button.new()
		_insp_toggle_btn.text = "Liberar · P-RUX-2"
		_insp_toggle_btn.position = Vector2(16.0 * s, 95.0 * s)
		_insp_toggle_btn.size = Vector2(188.0 * s, 28.0 * s)
		_insp_toggle_btn.focus_mode = Control.FOCUS_NONE
		_insp_toggle_btn.add_theme_font_size_override(&"font_size", max(9, int(round(10 * s))))
		_insp_toggle_btn.pressed.connect(func() -> void: toggle_alden_mode())
		_inspector_root.add_child(_insp_toggle_btn)

		# Right Lineage summary bay inside Inspection Tablet
		_inspector_root.add_child(_lbl("VÍNCULO", Vector2(226.0 * s, 24.0 * s), Vector2(84.0 * s, 14.0 * s), 9, gold, false, HORIZONTAL_ALIGNMENT_CENTER))
		_inspector_root.add_child(_lbl("A ═ B", Vector2(226.0 * s, 44.0 * s), Vector2(84.0 * s, 20.0 * s), 13, ivory, true, HORIZONTAL_ALIGNMENT_CENTER))
		_inspector_root.add_child(_lbl("Casa Principal", Vector2(226.0 * s, 68.0 * s), Vector2(84.0 * s, 15.0 * s), 9, muted, false, HORIZONTAL_ALIGNMENT_CENTER))
		_inspector_root.add_child(_lbl("Alento (T6)", Vector2(226.0 * s, 84.0 * s), Vector2(84.0 * s, 15.0 * s), 9, moss, false, HORIZONTAL_ALIGNMENT_CENTER))
		_inspector_root.add_child(_lbl("Esc: recolher", Vector2(226.0 * s, 102.0 * s), Vector2(84.0 * s, 14.0 * s), 8, gold, false, HORIZONTAL_ALIGNMENT_CENTER))

		# 4. BOTTOM-RIGHT: Alabaster Construction Keystone + Basalt Utility Wedge
		var cmd_y := h - 80.0 * s
		var bx := w - 338.0 * s
		add_child(_make_piece("build_keystone_alabaster", Vector2(bx, cmd_y)))
		var sh_ico := TextureRect.new()
		sh_ico.texture = tex_shelter
		sh_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sh_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sh_ico.position = Vector2(bx + 16.0 * s, cmd_y + 10.0 * s)
		sh_ico.size = Vector2(44.0 * s, 44.0 * s)
		sh_ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sh_ico)
		# Generous clearance from right bevel — ZERO clipping!
		add_child(_lbl("Construir", Vector2(bx + 66.0 * s, cmd_y + 13.0 * s), Vector2(96.0 * s, 22.0 * s), 15, ink, true, HORIZONTAL_ALIGNMENT_LEFT))
		add_child(_lbl("Maquetes [B]", Vector2(bx + 66.0 * s, cmd_y + 35.0 * s), Vector2(96.0 * s, 18.0 * s), 10, ink_sub, false, HORIZONTAL_ALIGNMENT_LEFT))
		add_child(_hitbox_btn(Vector2(bx, cmd_y), Vector2(176.0 * s, 66.0 * s), func() -> void: toggle_construction()))

		var ux := w - 154.0 * s
		add_child(_make_piece("utility_wedge_basalt", Vector2(ux, cmd_y)))
		add_child(_lbl("Tarefas", Vector2(ux + 20.0 * s, cmd_y + 10.0 * s), Vector2(72.0 * s, 18.0 * s), 11, ivory))
		add_child(_lbl("[T]", Vector2(ux + 90.0 * s, cmd_y + 10.0 * s), Vector2(26.0 * s, 18.0 * s), 10, gold, false, HORIZONTAL_ALIGNMENT_RIGHT))
		add_child(_lbl("Linhagem", Vector2(ux + 16.0 * s, cmd_y + 38.0 * s), Vector2(76.0 * s, 18.0 * s), 11, ivory))
		add_child(_lbl("[H]", Vector2(ux + 86.0 * s, cmd_y + 38.0 * s), Vector2(26.0 * s, 18.0 * s), 10, gold, false, HORIZONTAL_ALIGNMENT_RIGHT))

		# 5. CONSTRUCTION MODE OVERLAYS (Alabaster Maquette Plinth + Validation Keystone + Left Site Inspector)
		_construction_root = Control.new()
		_construction_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_construction_root.visible = false
		_construction_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_construction_root)

		var px := w - 454.0 * s
		var py := h - 264.0 * s
		_construction_root.add_child(_make_piece("construction_plinth_alabaster", Vector2(px, py)))
		_construction_root.add_child(_lbl("MESA DE MAQUETES · NÍVEL I (ACAMPAMENTO)", Vector2(px + 24.0 * s, py + 11.0 * s), Vector2(380.0 * s, 20.0 * s), 11, ink_sub, true))

		_shelter_hl = ColorRect.new()
		_shelter_hl.position = Vector2(px + 22.0 * s, py + 46.0 * s)
		_shelter_hl.size = Vector2(186.0 * s, 108.0 * s)
		_shelter_hl.color = Color(0.36, 0.55, 0.30, 0.16)
		_shelter_hl.visible = false
		_shelter_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_construction_root.add_child(_shelter_hl)

		_depot_hl = ColorRect.new()
		_depot_hl.position = Vector2(px + 224.0 * s, py + 46.0 * s)
		_depot_hl.size = Vector2(186.0 * s, 108.0 * s)
		_depot_hl.color = Color(0.36, 0.55, 0.30, 0.18)
		_depot_hl.visible = true
		_depot_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_construction_root.add_child(_depot_hl)

		var mini1 := TextureRect.new()
		mini1.texture = tex_shelter
		mini1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mini1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mini1.position = Vector2(px + 28.0 * s, py + 58.0 * s)
		mini1.size = Vector2(58.0 * s, 58.0 * s)
		mini1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_construction_root.add_child(mini1)
		_construction_root.add_child(_lbl("Abrigo Básico", Vector2(px + 90.0 * s, py + 58.0 * s), Vector2(114.0 * s, 20.0 * s), 13, ink, true))
		_construction_root.add_child(_lbl("4x4 m · 30 s", Vector2(px + 90.0 * s, py + 78.0 * s), Vector2(114.0 * s, 16.0 * s), 10, ink_sub))
		_construction_root.add_child(_lbl("12 Mad · 6 Ped", Vector2(px + 90.0 * s, py + 98.0 * s), Vector2(114.0 * s, 18.0 * s), 11, Color(0.18, 0.32, 0.15, 1.0)))
		_construction_root.add_child(_hitbox_btn(Vector2(px + 20.0 * s, py + 44.0 * s), Vector2(190.0 * s, 112.0 * s), func() -> void: select_building("shelter")))

		var mini2 := TextureRect.new()
		mini2.texture = tex_depot
		mini2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mini2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mini2.position = Vector2(px + 230.0 * s, py + 58.0 * s)
		mini2.size = Vector2(58.0 * s, 58.0 * s)
		mini2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_construction_root.add_child(mini2)
		_construction_root.add_child(_lbl("Depósito Rústico", Vector2(px + 292.0 * s, py + 58.0 * s), Vector2(118.0 * s, 20.0 * s), 13, ink, true))
		_construction_root.add_child(_lbl("5x4 m · 45 s", Vector2(px + 292.0 * s, py + 78.0 * s), Vector2(118.0 * s, 16.0 * s), 10, ink_sub))
		_construction_root.add_child(_lbl("18 Mad · 10 Ped", Vector2(px + 292.0 * s, py + 98.0 * s), Vector2(118.0 * s, 18.0 * s), 11, Color(0.18, 0.32, 0.15, 1.0)))
		_construction_root.add_child(_hitbox_btn(Vector2(px + 222.0 * s, py + 44.0 * s), Vector2(190.0 * s, 112.0 * s), func() -> void: select_building("depot")))

		# Top-Center Validation Keystone (Valid Alabaster vs Invalid Terracotta)
		_valid_keystone = Control.new()
		_valid_keystone.position = Vector2((w - 412.0 * s) * 0.5, ty)
		_valid_keystone.size = Vector2(412.0 * s, 44.0 * s)
		_valid_keystone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_construction_root.add_child(_valid_keystone)
		_valid_slab = _make_piece("validation_keystone_valid", Vector2.ZERO)
		_valid_keystone.add_child(_valid_slab)
		_valid_lbl = _lbl("TERRENO VÁLIDO · Depósito (5x4 m) · Esc cancelar", Vector2(24.0 * s, 9.0 * s), Vector2(364.0 * s, 24.0 * s), 10, Color(0.17, 0.30, 0.14, 1.0), false, HORIZONTAL_ALIGNMENT_CENTER)
		_valid_keystone.add_child(_valid_lbl)
		_valid_keystone.add_child(_hitbox_btn(Vector2.ZERO, Vector2(412.0 * s, 44.0 * s), func() -> void: toggle_preview_valid()))

		# Left-side Active Site Inspector (Aligned cleanly under Stockpile Monolith!)
		_site_inspector = Control.new()
		_site_inspector.position = Vector2(lx, ty + 66.0 * s)
		_site_inspector.size = Vector2(310.0 * s, 248.0 * s)
		_site_inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_construction_root.add_child(_site_inspector)
		_site_inspector.add_child(_make_piece("modal_monolith_basalt", Vector2.ZERO))
		_site_inspector.add_child(_lbl("CANTEIRO EM ERGIMENTO", Vector2(24.0 * s, 14.0 * s), Vector2(200.0 * s, 16.0 * s), 9, gold))
		_site_inspector.add_child(_lbl("Abrigo Básico", Vector2(24.0 * s, 30.0 * s), Vector2(180.0 * s, 22.0 * s), 16, ivory, true))
		_site_inspector.add_child(_lbl("42%", Vector2(214.0 * s, 30.0 * s), Vector2(64.0 * s, 22.0 * s), 16, gold, true, HORIZONTAL_ALIGNMENT_RIGHT))
		_site_inspector.add_child(_lbl("Madeira no canteiro: 12 / 12", Vector2(30.0 * s, 72.0 * s), Vector2(244.0 * s, 20.0 * s), 11, ivory))
		_site_inspector.add_child(_lbl("Pedra no canteiro: 6 / 6", Vector2(30.0 * s, 96.0 * s), Vector2(244.0 * s, 20.0 * s), 11, ivory))
		_site_inspector.add_child(_lbl("Construtores (D9): 1 / 2 · Alden", Vector2(30.0 * s, 120.0 * s), Vector2(244.0 * s, 20.0 * s), 11, moss))
		_site_inspector.add_child(_lbl("Complementar (DEC-11B) · Indisponível", Vector2(30.0 * s, 158.0 * s), Vector2(244.0 * s, 20.0 * s), 10, muted))
		_site_inspector.add_child(_lbl("Cancelar Construção (D3)", Vector2(30.0 * s, 186.0 * s), Vector2(244.0 * s, 22.0 * s), 11, Color(0.93, 0.61, 0.52, 1.0), true))

		# 6. PAUSE MONOLITH OVERLAY (Same Basalt + Aurora Seam visual language!)
		_pause_root = Control.new()
		_pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pause_root.visible = false
		_pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_pause_root)
		var dim := ColorRect.new()
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.color = Color(0.04, 0.05, 0.06, 0.54)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_pause_root.add_child(dim)
		var mx := (w - 310.0 * s) * 0.5
		var my := (h - 248.0 * s) * 0.5
		_pause_root.add_child(_make_piece("modal_monolith_basalt", Vector2(mx, my)))
		_pause_root.add_child(_lbl("PAUSA · MARCOS DE PEDRA", Vector2(mx + 26.0 * s, my + 11.0 * s), Vector2(256.0 * s, 14.0 * s), 9, gold, false, HORIZONTAL_ALIGNMENT_CENTER))
		_pause_root.add_child(_lbl("DAWN OF KIN", Vector2(mx + 26.0 * s, my + 28.0 * s), Vector2(256.0 * s, 22.0 * s), 16, ivory, true, HORIZONTAL_ALIGNMENT_CENTER))
		var p_items := ["Retomar Assentamento (Esc)", "Salvar Crônica (Proposta T3.8)", "Configurações (720p / 1080p)", "Menu Principal"]
		for j in range(p_items.size()):
			var by_i := my + (72.0 + j * 36.0) * s
			var col_j := gold if j == 0 else (muted if j == 1 else ivory)
			_pause_root.add_child(_lbl(p_items[j], Vector2(mx + 34.0 * s, by_i), Vector2(236.0 * s, 26.0 * s), 12, col_j, j == 0, HORIZONTAL_ALIGNMENT_CENTER))
		_pause_root.add_child(_hitbox_btn(Vector2(mx + 34.0 * s, my + 70.0 * s), Vector2(236.0 * s, 30.0 * s), func() -> void: toggle_pause()))

		if show_demo_bar:
			var hint := _lbl("SHOWCASE ISOLADO D2.1 · [1/2] Fundadores · [B] Construir · [V] Válida/Inválida · [Esc] Desfazer/Pausa", Vector2(0, h - 22.0), Vector2(w, 20.0), 10, gold, false, HORIZONTAL_ALIGNMENT_CENTER)
			add_child(hint)

	func select_founder(who: String, instant: bool = false) -> void:
		if selected_founder == who:
			clear_founder_selection(instant)
			return
		selected_founder = who
		var lift := 12.0 * scale_k
		var ay := _alden_base_y - (lift if who == "alden" else 0.0)
		var by := _brena_base_y - (lift if who == "brena" else 0.0)
		_alden_slab.texture = _atlas_region("founder_half_selected" if who == "alden" else "founder_half_left")
		if instant:
			_alden_root.position.y = ay
			_brena_root.position.y = by
		else:
			var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(_alden_root, "position:y", ay, 0.14)
			tw.tween_property(_brena_root, "position:y", by, 0.14)
		_inspector_root.visible = true
		if who == "alden":
			_insp_name.text = "Alden · Fundador"
			_insp_role.text = "Adulto · Proteção dos Líderes"
			_insp_mode_badge.text = "PESSOAL" if alden_personal else "COMUNITÁRIO"
			_insp_carry_lbl.text = "Carga: 8 / 20 peso (40%) · 4,0 m/s"
			_insp_carry_fill.size.x = 74.0 * scale_k
			_insp_toggle_btn.visible = true
		else:
			_insp_name.text = "Brena · Fundadora"
			_insp_role.text = "Adulta · Coletando madeira"
			_insp_mode_badge.text = "COMUNITÁRIO"
			_insp_carry_lbl.text = "Carga: 4 / 20 peso (20%) · 4,4 m/s"
			_insp_carry_fill.size.x = 37.0 * scale_k
			_insp_toggle_btn.visible = false

	func clear_founder_selection(instant: bool = false) -> void:
		selected_founder = ""
		_alden_slab.texture = _atlas_region("founder_half_left")
		_inspector_root.visible = false
		if instant:
			_alden_root.position.y = _alden_base_y
			_brena_root.position.y = _brena_base_y
		else:
			var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(_alden_root, "position:y", _alden_base_y, 0.12)
			tw.tween_property(_brena_root, "position:y", _brena_base_y, 0.12)

	func toggle_alden_mode() -> void:
		alden_personal = not alden_personal
		_alden_status_lbl.text = "Pessoal" if alden_personal else "Livre"
		if selected_founder == "alden":
			_insp_mode_badge.text = "PESSOAL" if alden_personal else "COMUNITÁRIO"
			_insp_toggle_btn.text = "Liberar p/ Comunidade (P-RUX-2)" if alden_personal else "Retomar Controle Pessoal"

	func toggle_construction() -> void:
		construction_open = not construction_open
		_construction_root.visible = construction_open

	func select_building(bid: String) -> void:
		selected_building = bid
		_shelter_hl.visible = (bid == "shelter")
		_depot_hl.visible = (bid == "depot")
		_update_validation_banner()

	func toggle_preview_valid() -> void:
		preview_valid = not preview_valid
		_update_validation_banner()

	func _update_validation_banner() -> void:
		var bname := "Abrigo (4x4 m)" if selected_building == "shelter" else "Depósito (5x4 m)"
		if preview_valid:
			_valid_slab.texture = _atlas_region("validation_keystone_valid")
			_valid_lbl.text = "TERRENO VÁLIDO · %s · Esc cancelar" % bname
			_valid_lbl.add_theme_color_override(&"font_color", Color(0.17, 0.30, 0.14, 1.0))
		else:
			_valid_slab.texture = _atlas_region("validation_keystone_invalid")
			_valid_lbl.text = "BLOQUEADO · Acampamento (D6) · Esc"
			_valid_lbl.add_theme_color_override(&"font_color", Color(0.95, 0.64, 0.55, 1.0))

	func toggle_pause() -> void:
		pause_open = not pause_open
		_pause_root.visible = pause_open

	func handle_escape() -> void:
		if pause_open:
			toggle_pause()
		elif construction_open:
			toggle_construction()
		elif selected_founder != "":
			clear_founder_selection()
		else:
			toggle_pause()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			var ke := event as InputEventKey
			if not ke.pressed or ke.echo:
				return
			match ke.keycode:
				KEY_1:
					select_founder("alden")
				KEY_2:
					select_founder("brena")
				KEY_B:
					toggle_construction()
				KEY_V:
					if construction_open:
						toggle_preview_valid()
				KEY_ESCAPE:
					handle_escape()


# ------------------------------------------------------------------------------
# PROCEDURAL TEXT LAYER (Paired with ProceduralCleavedCanvas for exact A/B parity)
# ------------------------------------------------------------------------------
func _build_procedural_rest(vp_size: Vector2) -> Control:
	var root := Control.new()
	root.size = vp_size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := 1.0 if vp_size.x >= 1600.0 else 0.88
	var canvas := ProceduralCleavedCanvas.new()
	canvas.size = vp_size
	canvas.scale_k = s
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(canvas)

	# Add identical text & portrait nodes so Procedural vs Atlas compares ONLY rendering method!
	var helper := _make_atlas_hud(vp_size, false)
	# Reuse labels/portraits placement directly via lightweight builder:
	var lx := 18.0 * s
	var ty := 14.0 * s
	var w := vp_size.x
	var h := vp_size.y
	var ivory := Color(0.957, 0.937, 0.894, 1.0)
	var muted := Color(0.74, 0.71, 0.65, 1.0)
	var gold := Color(0.875, 0.737, 0.447, 1.0)
	var moss := Color(0.66, 0.81, 0.57, 1.0)
	var ink := Color(0.114, 0.094, 0.075, 1.0)
	var ink_sub := Color(0.33, 0.28, 0.22, 1.0)

	var res_items := [["MAD", "24", Color(0.90, 0.74, 0.44, 1.0)], ["PED", "14", Color(0.79, 0.83, 0.86, 1.0)], ["ALI", "18", Color(0.92, 0.69, 0.37, 1.0)]]
	for i in range(3):
		var tx := lx + (22.0 + i * 90.0) * s
		root.add_child(helper._lbl(res_items[i][0], Vector2(tx, ty + 11.0 * s), Vector2(36.0 * s, 16.0 * s), 10, res_items[i][2]))
		root.add_child(helper._lbl(res_items[i][1], Vector2(tx + 34.0 * s, ty + 11.0 * s), Vector2(36.0 * s, 28.0 * s), 17, ivory, true, HORIZONTAL_ALIGNMENT_RIGHT))
		root.add_child(helper._lbl("EXPOSTO" if i != 1 else "ESTÁVEL", Vector2(tx, ty + 28.0 * s), Vector2(46.0 * s, 14.0 * s), 8, muted))

	var rx0 := w - 254.0 * s
	root.add_child(helper._lbl("NÍVEL I · ACAMPAMENTO", Vector2(rx0 + 20.0 * s, ty + 7.0 * s), Vector2(194.0 * s, 14.0 * s), 9, gold))
	root.add_child(helper._lbl("Ano I · Ciclo 1 (T4)", Vector2(rx0 + 20.0 * s, ty + 21.0 * s), Vector2(194.0 * s, 20.0 * s), 14, ivory, true))
	root.add_child(helper._lbl("|| [1x] 2x 4x", Vector2(rx0 + 22.0 * s, ty + 47.0 * s), Vector2(96.0 * s, 22.0 * s), 10, ivory))
	root.add_child(helper._lbl("● Exposto", Vector2(rx0 + 120.0 * s, ty + 47.0 * s), Vector2(64.0 * s, 22.0 * s), 9, Color(0.92, 0.70, 0.37, 1.0)))
	root.add_child(helper._lbl("☰", Vector2(rx0 + 194.0 * s, ty + 46.0 * s), Vector2(20.0 * s, 22.0 * s), 12, gold, false, HORIZONTAL_ALIGNMENT_CENTER))

	var by := h - 150.0 * s
	root.add_child(helper._circular_portrait(_tex_alden, Vector2(lx + 25.0 * s, by + 16.0 * s), 58.0 * s, gold))
	root.add_child(helper._lbl("Alden", Vector2(lx + 16.0 * s, by + 94.0 * s), Vector2(78.0 * s, 17.0 * s), 13, ivory, true, HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(helper._lbl("Livre", Vector2(lx + 16.0 * s, by + 110.0 * s), Vector2(78.0 * s, 14.0 * s), 10, gold, false, HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(helper._circular_portrait(_tex_brena, Vector2(lx + 125.0 * s, by + 16.0 * s), 58.0 * s, gold))
	root.add_child(helper._lbl("Brena", Vector2(lx + 116.0 * s, by + 94.0 * s), Vector2(78.0 * s, 17.0 * s), 13, ivory, true, HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(helper._lbl("Coletando", Vector2(lx + 116.0 * s, by + 110.0 * s), Vector2(78.0 * s, 14.0 * s), 10, moss, false, HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(helper._circular_portrait(_tex_emblem, Vector2(lx + 91.0 * s, by - 14.0 * s), 28.0 * s, gold))

	var cmd_y := h - 80.0 * s
	var bx := w - 338.0 * s
	var sh_ico := TextureRect.new()
	sh_ico.texture = _tex_shelter
	sh_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh_ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sh_ico.position = Vector2(bx + 16.0 * s, cmd_y + 10.0 * s)
	sh_ico.size = Vector2(44.0 * s, 44.0 * s)
	root.add_child(sh_ico)
	root.add_child(helper._lbl("Construir", Vector2(bx + 66.0 * s, cmd_y + 13.0 * s), Vector2(96.0 * s, 22.0 * s), 15, ink, true))
	root.add_child(helper._lbl("Maquetes [B]", Vector2(bx + 66.0 * s, cmd_y + 35.0 * s), Vector2(96.0 * s, 18.0 * s), 10, ink_sub))
	var ux := w - 154.0 * s
	root.add_child(helper._lbl("Tarefas", Vector2(ux + 20.0 * s, cmd_y + 10.0 * s), Vector2(72.0 * s, 18.0 * s), 11, ivory))
	root.add_child(helper._lbl("[T]", Vector2(ux + 90.0 * s, cmd_y + 10.0 * s), Vector2(26.0 * s, 18.0 * s), 10, gold, false, HORIZONTAL_ALIGNMENT_RIGHT))
	root.add_child(helper._lbl("Linhagem", Vector2(ux + 16.0 * s, cmd_y + 38.0 * s), Vector2(76.0 * s, 18.0 * s), 11, ivory))
	root.add_child(helper._lbl("[H]", Vector2(ux + 86.0 * s, cmd_y + 38.0 * s), Vector2(26.0 * s, 18.0 * s), 10, gold, false, HORIZONTAL_ALIGNMENT_RIGHT))
	helper.free()
	return root


func _make_atlas_hud(vp_size: Vector2, build_now: bool = true) -> D21AtlasHud:
	var hud := D21AtlasHud.new()
	hud.atlas_tex = _atlas_tex
	hud.manifest = _manifest
	hud.font_serif = _font_serif
	hud.font_sans = _font_sans
	hud.tex_alden = _tex_alden
	hud.tex_brena = _tex_brena
	hud.tex_emblem = _tex_emblem
	hud.tex_shelter = _tex_shelter
	hud.tex_depot = _tex_depot
	hud.scale_k = 1.0 if vp_size.x >= 1600.0 else 0.88
	hud.show_demo_bar = _interactive_mode
	if build_now:
		hud.build(vp_size)
	return hud


func _load_tex(fname: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ASSETS_DIR + fname))
	return ImageTexture.create_from_image(img)


func _load_fonts() -> void:
	for p in ["C:/Windows/Fonts/palab.ttf", "C:/Windows/Fonts/pala.ttf", "C:/Windows/Fonts/georgia.ttf"]:
		if FileAccess.file_exists(p):
			var ff := FontFile.new()
			if ff.load_dynamic_font(p) == OK:
				_font_serif = ff
				break
	if _font_serif == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Palatino Linotype", "Georgia", "serif"])
		_font_serif = sf
	for p in ["C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"]:
		if FileAccess.file_exists(p):
			var ff2 := FontFile.new()
			if ff2.load_dynamic_font(p) == OK:
				_font_sans = ff2
				break
	if _font_sans == null:
		var sf2 := SystemFont.new()
		sf2.font_names = PackedStringArray(["Segoe UI", "sans-serif"])
		_font_sans = sf2


func _hide_legacy_hud(main_node: Node) -> void:
	for n in main_node.find_children("*", "CanvasLayer", true, false):
		n.visible = false
	for n in main_node.find_children("*", "Control", true, false):
		if n.get_parent() == main_node:
			n.visible = false


func _capture(path_res: String) -> void:
	for _i in range(6):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path_res))
	print("Captured %s" % path_res.get_file())


func _measure_block() -> Dictionary:
	for _w in range(WARMUP_FRAMES):
		await process_frame
	var times: Array[float] = []
	times.resize(MEASURE_FRAMES)
	var over_100 := 0
	var prev_us := Time.get_ticks_usec()
	for i in range(MEASURE_FRAMES):
		await process_frame
		var now_us := Time.get_ticks_usec()
		var dt_ms := float(now_us - prev_us) / 1000.0
		prev_us = now_us
		times[i] = dt_ms
		if dt_ms > 100.0:
			over_100 += 1
	var total := 0.0
	for t in times:
		total += t
	times.sort()
	return {
		"avg_ms": total / float(MEASURE_FRAMES),
		"p95_ms": times[int(floor(MEASURE_FRAMES * 0.95))],
		"p99_ms": times[int(floor(MEASURE_FRAMES * 0.99))],
		"frames_over_100ms": over_100,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}


func _median(vals: Array[float]) -> float:
	var c := vals.duplicate()
	c.sort()
	return c[c.size() / 2]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_interactive_mode = args.has("--interactive")
	_load_fonts()
	_atlas_tex = _load_tex("d2_1_ui_atlas.png")
	_manifest = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(ASSETS_DIR + "atlas_manifest.json")))
	_tex_alden = _load_tex("portrait_alden.jpg")
	_tex_brena = _load_tex("portrait_brena.jpg")
	_tex_emblem = _load_tex("emblem_dawn_of_kin.png")
	_tex_shelter = _load_tex("d1_shelter_mini.png")
	_tex_depot = _load_tex("d1_depot_mini.png")

	var main_scene := (load("res://src/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	_hide_legacy_hud(main_scene)

	if _interactive_mode:
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_title("Dawn of Kin — UI-0 R2.1 Interactive D2.1 Showcase (Isolated)")
		await process_frame
		var layer := CanvasLayer.new()
		layer.layer = 50
		root.add_child(layer)
		layer.add_child(_make_atlas_hud(root.get_visible_rect().size))
		print("=== UI-0 R2.1 Interactive Mode Active (close window to exit) ===")
		return

	call_deferred("_run_automated_suite")


func _run_automated_suite() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vsync_mode := DisplayServer.window_get_vsync_mode()
	var results := {
		"engine": Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_video_adapter_name(),
		"vsync_mode": vsync_mode,
		"warmup_frames": WARMUP_FRAMES,
		"frames_per_run": MEASURE_FRAMES,
		"repetitions": REPETITIONS,
		"total_frames_per_scenario": MEASURE_FRAMES * REPETITIONS,
		"resolutions": {},
	}

	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)

	var resolutions := [Vector2i(1280, 720), Vector2i(1920, 1080)]
	for res in resolutions:
		var rkey := "%dx%d" % [res.x, res.y]
		DisplayServer.window_set_size(res)
		for _f in range(12):
			await process_frame
		# Respect project's canvas_items stretch logical viewport size (1920x1080) so corners align cleanly at every resolution!
		var vp := root.get_visible_rect().size
		print("=== GODOT R2.1 SHOWCASE & UN-VSYNCED A/B BENCHMARK: %s (logical=%dx%d) ===" % [rkey, int(vp.x), int(vp.y)])

		# Capture live visual proofs first (zero overlaps + real interactive state proofs!)
		var cap_hud := _make_atlas_hud(vp)
		layer.add_child(cap_hud)
		await _capture(OUT_DIR + "G_godot_D2_1_rest_%s.png" % rkey)
		if res.x == 1280:
			cap_hud.select_founder("alden", true)
			await _capture(OUT_DIR + "G_godot_D2_1_founder_selected_1280x720.png")
			cap_hud.clear_founder_selection(true)
			cap_hud.toggle_construction()
			cap_hud.select_building("depot")
			await _capture(OUT_DIR + "G_godot_D2_1_construction_1280x720.png")
			cap_hud.toggle_construction()
			cap_hud.toggle_pause()
			await _capture(OUT_DIR + "G_godot_D2_1_pause_1280x720.png")
			cap_hud.toggle_pause()
		cap_hud.queue_free()
		await process_frame

		# Interleaved un-vsynced A/B benchmark across 4 scenarios
		var sc_names := ["BASELINE_3D", "D2_1_PROCEDURAL_REST", "D2_1_ATLAS_REST", "D2_1_ATLAS_ACTIVE"]
		var raw := {}
		for sc in sc_names:
			raw[sc] = []

		for _rep in range(REPETITIONS):
			for sc in sc_names:
				var node: Control = null
				if sc == "D2_1_PROCEDURAL_REST":
					node = _build_procedural_rest(vp)
				elif sc == "D2_1_ATLAS_REST":
					node = _make_atlas_hud(vp)
				elif sc == "D2_1_ATLAS_ACTIVE":
					var ah := _make_atlas_hud(vp)
					ah.select_founder("alden", true)
					ah.toggle_construction()
					node = ah
				if node != null:
					layer.add_child(node)
				var m := await _measure_block()
				raw[sc].append(m)
				if node != null:
					node.queue_free()
					await process_frame

		var res_out := {}
		for sc in sc_names:
			var avgs: Array[float] = []
			var p95s: Array[float] = []
			var p99s: Array[float] = []
			var over := 0
			for m in raw[sc]:
				avgs.append(float(m["avg_ms"]))
				p95s.append(float(m["p95_ms"]))
				p99s.append(float(m["p99_ms"]))
				over += int(m["frames_over_100ms"])
			var s_avgs := avgs.duplicate(); s_avgs.sort()
			var s_p95s := p95s.duplicate(); s_p95s.sort()
			var s_p99s := p99s.duplicate(); s_p99s.sort()
			res_out[sc] = {
				"median_avg_ms": _median(avgs),
				"median_p95_ms": _median(p95s),
				"median_p99_ms": _median(p99s),
				"min_p95_ms": s_p95s[0],
				"max_p95_ms": s_p95s[s_p95s.size() - 1],
				"min_p99_ms": s_p99s[0],
				"max_p99_ms": s_p99s[s_p99s.size() - 1],
				"total_frames_over_100ms": over,
				"draw_calls": raw[sc][0]["draw_calls"],
				"nodes": raw[sc][0]["nodes"],
				"runs": raw[sc],
			}
			print("%s [%s] | med_avg=%.3f ms | med_p95=%.3f ms (%.3f..%.3f) | med_p99=%.3f ms (%.3f..%.3f) | >100ms=%d | dc=%d | nodes=%d" % [
				sc, rkey, res_out[sc]["median_avg_ms"], res_out[sc]["median_p95_ms"],
				res_out[sc]["min_p95_ms"], res_out[sc]["max_p95_ms"],
				res_out[sc]["median_p99_ms"], res_out[sc]["min_p99_ms"], res_out[sc]["max_p99_ms"],
				over, res_out[sc]["draw_calls"], res_out[sc]["nodes"]
			])
		results["resolutions"][rkey] = res_out

	var f := FileAccess.open(ProjectSettings.globalize_path(BENCH_JSON), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print("Saved benchmark_results_r2_1.json -> %s" % ProjectSettings.globalize_path(BENCH_JSON))
	quit(0)
