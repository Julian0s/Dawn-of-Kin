extends SceneTree
## Dawn of Kin — UI-0 R2.2 Faithful Direction D2 ("Marcos de Pedra e Eclipse") Isolated Godot 4.7.2 Showcase
## Faithfully reproduces the owner-chosen UI-0 R2 D2 visual reference (D2_B, D2_C, D2_D, D2_E) inside Godot 4.7.2
## over the EXACT same 3D reference scene (rux_2b_multi_source_selection.tscn), using pre-baked 2x-supersampled
## AtlasTexture pieces + exact original D2 icons, with ZERO text overlaps and ZERO gameplay edits.
##
## Modes:
##   Default: Captures all 4 faithful D2 views at 1920x1080 AND 1280x720 (8 screenshots) + un-vsynced benchmark.
##   Interactive (--interactive): Live interactive preview switching HUD Normal / Seleção-Linhagem / Construção / Menu.

const REFERENCE_3D_SCENE := "res://tests/visual/rux_2b_multi_source_selection.tscn"
const ASSETS_DIR := "res://docs/design/ui-0-r2-2/assets/"
const OUT_DIR := "res://docs/design/ui-0-r2-2/"
const BENCH_JSON := "res://docs/design/ui-0-r2-2/godot_showcase/benchmark_results_r2_2.json"

const WARMUP_FRAMES := 60
const MEASURE_FRAMES := 180
const REPETITIONS := 3

var _font_serif: Font = null
var _font_serif_bold: Font = null
var _font_sans: Font = null
var _font_sans_bold: Font = null

var _atlas_tex: Texture2D = null
var _menu_monolith_tex: Texture2D = null
var _manifest: Dictionary = {}
var _tex_alden: Texture2D = null
var _tex_brena: Texture2D = null
var _tex_emblem: Texture2D = null
var _tex_shelter: Texture2D = null
var _tex_depot: Texture2D = null
var _interactive_mode: bool = false


class FaithfulD2Showcase extends Control:
	var atlas_tex: Texture2D
	var menu_monolith_tex: Texture2D
	var manifest: Dictionary
	var f_serif: Font
	var f_serif_b: Font
	var f_sans: Font
	var f_sans_b: Font
	var tex_alden: Texture2D
	var tex_brena: Texture2D
	var tex_emblem: Texture2D
	var tex_shelter: Texture2D
	var tex_depot: Texture2D
	var s: float = 1.0  # 1.0 at 1080p, 1.22 at 720p (matches D2_B_hud_1280x720 physical proportions!)

	# View roots: "hud", "construction", "lineage", "menu"
	var _view_hud: Control
	var _view_construction: Control
	var _view_lineage: Control
	var _view_menu: Control
	var _current_view: String = "hud"

	# Palette matching exact CSS variables of D2_B/C/D/E
	const C_IVORY := Color(0.957, 0.937, 0.894, 1.0)    # #F4EFE4
	const C_GOLD := Color(0.875, 0.737, 0.447, 1.0)     # #DFBC72
	const C_GOLD_HI := Color(0.961, 0.851, 0.588, 1.0)  # #F5D996
	const C_INK := Color(0.114, 0.094, 0.075, 1.0)      # #1D1813
	const C_INK_SUB := Color(0.357, 0.294, 0.227, 1.0)  # #5B4B3A
	const C_GREEN := Color(0.220, 0.357, 0.165, 1.0)    # #385B2A
	const C_SAGE := Color(0.647, 0.788, 0.545, 1.0)     # #A5C98B
	const C_AMBER := Color(0.918, 0.706, 0.392, 1.0)    # #EAB464
	const C_MUTED := Color(0.75, 0.73, 0.68, 1.0)
	const C_ROSE := Color(0.949, 0.722, 0.675, 1.0)     # #F2B8AC

	func _region(key: String) -> AtlasTexture:
		var r: Dictionary = manifest["regions"][key]
		var at := AtlasTexture.new()
		at.atlas = atlas_tex
		at.region = Rect2(float(r["x"]), float(r["y"]), float(r["w"]), float(r["h"]))
		return at

	func _slab(parent: Node, key: String, pos: Vector2, sz: Vector2 = Vector2.ZERO, stop_mouse: bool = true) -> TextureRect:
		var r: Dictionary = manifest["regions"][key]
		var pad := float(r["pad"])
		var cw := float(r["content_w"])
		var ch := float(r["content_h"])
		var sx := (sz.x / cw) if sz.x > 0.0 else s
		var sy := (sz.y / ch) if sz.y > 0.0 else s
		var tr := TextureRect.new()
		tr.texture = _region(key)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = pos - Vector2(pad * sx, pad * sy)
		tr.size = Vector2(float(r["w"]) * sx, float(r["h"]) * sy)
		tr.custom_minimum_size = tr.size
		tr.mouse_filter = Control.MOUSE_FILTER_STOP if stop_mouse else Control.MOUSE_FILTER_IGNORE
		parent.add_child(tr)
		return tr

	func _icon(parent: Node, key: String, pos: Vector2, px: float) -> TextureRect:
		var tr := TextureRect.new()
		tr.texture = _region(key)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = pos
		tr.size = Vector2(px, px)
		tr.custom_minimum_size = tr.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tr)
		return tr

	func _img(parent: Node, tex: Texture2D, pos: Vector2, sz: Vector2) -> TextureRect:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = pos
		tr.size = sz
		tr.custom_minimum_size = sz
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tr)
		return tr

	func _lbl(parent: Node, txt: String, pos: Vector2, sz: Vector2, px: float, col: Color,
			serif: bool = false, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
		var l := Label.new()
		l.text = txt
		l.position = pos
		l.size = sz
		l.horizontal_alignment = align
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override(&"font_size", max(9, int(round(px * s))))
		l.add_theme_color_override(&"font_color", col)
		var f: Font = null
		if serif:
			f = f_serif_b if bold and f_serif_b != null else f_serif
		else:
			f = f_sans_b if bold and f_sans_b != null else f_sans
		if f != null:
			l.add_theme_font_override(&"font", f)
		parent.add_child(l)
		return l

	func _portrait(parent: Node, tex: Texture2D, pos: Vector2, diam: float, rim: Color) -> Panel:
		var p := Panel.new()
		p.position = pos
		p.size = Vector2(diam, diam)
		p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.09, 0.10, 1.0)
		sb.set_corner_radius_all(int(round(diam * 0.5)))
		sb.set_border_width_all(max(1, int(round(2.0 * s))))
		sb.border_color = rim
		p.add_theme_stylebox_override(&"panel", sb)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
		parent.add_child(p)
		return p

	func _box(parent: Node, pos: Vector2, sz: Vector2, fill: Color, rim: Color = Color(0, 0, 0, 0), rim_w: int = 1) -> Panel:
		var p := Panel.new()
		p.position = pos
		p.size = sz
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		if rim.a > 0.0:
			sb.set_border_width_all(rim_w)
			sb.border_color = rim
		p.add_theme_stylebox_override(&"panel", sb)
		parent.add_child(p)
		return p

	func _hitbox(parent: Node, pos: Vector2, sz: Vector2, cb: Callable) -> Button:
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
		hov.bg_color = Color(0.875, 0.737, 0.447, 0.10)
		b.add_theme_stylebox_override(&"hover", hov)
		b.pressed.connect(cb)
		parent.add_child(b)
		return b

	# Shared Top-Left: Exact 3 Stepped River-Stone Resource Monoliths
	func _add_resource_cairn(parent: Node) -> void:
		var x0 := 24.0 * s
		var y0 := 20.0 * s
		var items := [
			["ico_wood", "24", 0.0],
			["ico_stone", "14", 7.0],
			["ico_food", "18", 2.0],
		]
		for i in range(3):
			var rx := x0 + float(i) * (84.0 + 10.0) * s
			var ry := y0 + float(items[i][2]) * s
			_slab(parent, "resource_rock", Vector2(rx, ry))
			_icon(parent, items[i][0], Vector2(rx + 18.0 * s, ry + 11.0 * s), 20.0 * s)
			_lbl(parent, items[i][1], Vector2(rx + 42.0 * s, ry + 7.0 * s), Vector2(32.0 * s, 26.0 * s), 18.0, C_IVORY, true, true, HORIZONTAL_ALIGNMENT_LEFT)

	# Shared Top-Right: Exact Peaked Dark Kintsugi Plaque
	func _add_top_plaque(parent: Node, compact: bool = false) -> void:
		var w := size.x
		var pw := 196.0 * s
		var ph := (64.0 if compact else 110.0) * s
		var px := w - 24.0 * s - pw
		var py := 16.0 * s
		_slab(parent, "top_plaque", Vector2(px, py), Vector2(pw, ph))
		_lbl(parent, "CLAREIRA INICIAL", Vector2(px + 10.0 * s, py + 11.0 * s), Vector2(pw - 20.0 * s, 14.0 * s), 9.5, C_GOLD, false, true, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(parent, "Primavera · Ano I", Vector2(px + 10.0 * s, py + 25.0 * s), Vector2(pw - 20.0 * s, 24.0 * s), 16.5, C_IVORY, true, true, HORIZONTAL_ALIGNMENT_CENTER)
		if compact:
			return
		# Speed controls row (4 clean bordered boxes centered inside the plaque)
		var sp_labels := ["||", "1×", "2×", "4×"]
		var sp_ws := [22.0, 28.0, 26.0, 26.0]
		var total_w := (22.0 + 28.0 + 26.0 + 26.0 + 15.0) * s
		var sx := px + (pw - total_w) * 0.5
		var sy := py + 55.0 * s
		for j in range(4):
			var bw := float(sp_ws[j]) * s
			var is_on := (j == 1)
			var fill := Color(0.875, 0.737, 0.447, 0.28) if is_on else Color(0, 0, 0, 0.18)
			var rim := C_GOLD if is_on else Color(0.875, 0.737, 0.447, 0.35)
			_box(parent, Vector2(sx, sy), Vector2(bw, 21.0 * s), fill, rim, 1)
			_lbl(parent, sp_labels[j], Vector2(sx, sy), Vector2(bw, 21.0 * s), 10.5, C_IVORY, false, is_on, HORIZONTAL_ALIGNMENT_CENTER)
			sx += bw + 5.0 * s
		_lbl(parent, "● EXPOSTO · ☰ MENU", Vector2(px + 10.0 * s, py + 82.0 * s), Vector2(pw - 20.0 * s, 18.0 * s), 10.0, C_AMBER, false, true, HORIZONTAL_ALIGNMENT_CENTER)
		_hitbox(parent, Vector2(px, py + 78.0 * s), Vector2(pw, 28.0 * s), func() -> void: set_view("menu"))

	# Shared Bottom-Left: Twin Staggered Tilted Basalt Founder Steles
	func _add_founder_steles(parent: Node) -> void:
		var h := size.y
		var sw := 108.0 * s
		var sh := 136.0 * s
		var x1 := 24.0 * s
		var y1 := h - 22.0 * s - sh
		# Alden stele
		_slab(parent, "founder_stele", Vector2(x1, y1))
		_portrait(parent, tex_alden, Vector2(x1 + 23.0 * s, y1 + 14.0 * s), 62.0 * s, C_GOLD)
		_lbl(parent, "Alden", Vector2(x1 + 8.0 * s, y1 + 83.0 * s), Vector2(sw - 16.0 * s, 21.0 * s), 15.0, C_IVORY, true, true, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(parent, "Livre", Vector2(x1 + 8.0 * s, y1 + 104.0 * s), Vector2(sw - 16.0 * s, 16.0 * s), 10.5, C_GOLD, false, false, HORIZONTAL_ALIGNMENT_CENTER)
		_hitbox(parent, Vector2(x1, y1), Vector2(sw, sh), func() -> void: set_view("lineage"))

		# Brena stele (14px gap, staggered 6px lower — exact CSS `margin-bottom: -6px`!)
		var x2 := x1 + sw + 14.0 * s
		var y2 := y1 + 6.0 * s
		_slab(parent, "founder_stele", Vector2(x2, y2))
		_portrait(parent, tex_brena, Vector2(x2 + 23.0 * s, y2 + 14.0 * s), 62.0 * s, C_GOLD)
		_lbl(parent, "Brena", Vector2(x2 + 8.0 * s, y2 + 83.0 * s), Vector2(sw - 16.0 * s, 21.0 * s), 15.0, C_IVORY, true, true, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(parent, "Coletando", Vector2(x2 + 8.0 * s, y2 + 104.0 * s), Vector2(sw - 16.0 * s, 16.0 * s), 10.5, C_SAGE, false, false, HORIZONTAL_ALIGNMENT_CENTER)
		_hitbox(parent, Vector2(x2, y2), Vector2(sw, sh), func() -> void: set_view("lineage"))

	# Shared Bottom-Right: Alabaster Maquetes Slab + Basalt Command Slab
	func _add_bottom_right_slabs(parent: Node) -> void:
		var w := size.x
		var h := size.y
		var mw := 176.0 * s
		var cw := 146.0 * s
		var sh := 72.0 * s
		var y0 := h - 22.0 * s - sh
		var cx := w - 24.0 * s - cw
		var mx := cx - 12.0 * s - mw

		# Alabaster Maquetes / Construir [B]
		_slab(parent, "slab_maquetes_alab", Vector2(mx, y0))
		_img(parent, tex_shelter, Vector2(mx + 16.0 * s, y0 + 13.0 * s), Vector2(46.0 * s, 46.0 * s))
		_lbl(parent, "Maquetes", Vector2(mx + 72.0 * s, y0 + 15.0 * s), Vector2(96.0 * s, 22.0 * s), 15.5, C_INK, true, true)
		_lbl(parent, "Construir [B]", Vector2(mx + 72.0 * s, y0 + 38.0 * s), Vector2(96.0 * s, 16.0 * s), 10.8, C_INK_SUB, false, false)
		_hitbox(parent, Vector2(mx, y0), Vector2(mw, sh), func() -> void: set_view("hud" if _current_view == "construction" else "construction"))

		# Dark Basalt Tarefas [T] / Linhagem [H]
		_slab(parent, "slab_cmd_basalt", Vector2(cx, y0))
		_icon(parent, "ico_tasks", Vector2(cx + 18.0 * s, y0 + 16.0 * s), 15.0 * s)
		_lbl(parent, "Tarefas [T]", Vector2(cx + 39.0 * s, y0 + 14.0 * s), Vector2(94.0 * s, 19.0 * s), 11.8, C_IVORY)
		_icon(parent, "ico_lineage", Vector2(cx + 18.0 * s, y0 + 41.0 * s), 15.0 * s)
		_lbl(parent, "Linhagem [H]", Vector2(cx + 39.0 * s, y0 + 39.0 * s), Vector2(94.0 * s, 19.0 * s), 11.8, C_IVORY)
		_hitbox(parent, Vector2(cx, y0 + 36.0 * s), Vector2(cw, 36.0 * s), func() -> void: set_view("lineage"))

	func build(vp_size: Vector2, scale_override: float = 1.0) -> void:
		size = vp_size
		s = scale_override
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := vp_size.x
		var h := vp_size.y

		# ------------------------------------------------------------------
		# VIEW 1: HUD NORMAL (Exact reproduction of D2_B_hud_1920x1080/720!)
		# ------------------------------------------------------------------
		_view_hud = Control.new()
		_view_hud.size = vp_size
		_view_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view_hud)
		_add_resource_cairn(_view_hud)
		_add_top_plaque(_view_hud, false)
		_add_founder_steles(_view_hud)
		_add_bottom_right_slabs(_view_hud)

		# ------------------------------------------------------------------
		# VIEW 2: CONSTRUÇÃO (Exact reproduction of D2_C_construction!)
		# ------------------------------------------------------------------
		_view_construction = Control.new()
		_view_construction.size = vp_size
		_view_construction.visible = false
		_view_construction.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view_construction)
		_add_resource_cairn(_view_construction)
		_add_top_plaque(_view_construction, false)
		_add_founder_steles(_view_construction)
		_add_bottom_right_slabs(_view_construction)

		# Top-Center Alabaster Validation Bar (wide enough for full text with generous margins!)
		var vbw := 760.0 * s
		var vbh := 38.0 * s
		var vbx := (w - vbw) * 0.5
		var vby := 24.0 * s
		_slab(_view_construction, "build_valid_bar", Vector2(vbx, vby), Vector2(vbw, vbh))
		_lbl(_view_construction, "TERRENO NIVELADO E LIVRE · Maquete: Depósito Rústico (5×4 m) · Clique esq. assentar · Esc soltar",
			Vector2(vbx + 20.0 * s, vby + 6.0 * s), Vector2(vbw - 40.0 * s, vbh - 12.0 * s), 11.8, C_GREEN, false, true, HORIZONTAL_ALIGNMENT_CENTER)

		# Top-Left Dark Basalt Active Site Monolith (x=24, y=106, w=308, h=224)
		var sx := 24.0 * s
		var sy := 106.0 * s
		_slab(_view_construction, "build_site_monolith", Vector2(sx, sy))
		_lbl(_view_construction, "MARCO EM ERGIMENTO", Vector2(sx + 20.0 * s, sy + 18.0 * s), Vector2(268.0 * s, 14.0 * s), 9.8, C_GOLD, false, true)
		_lbl(_view_construction, "Abrigo Básico", Vector2(sx + 20.0 * s, sy + 36.0 * s), Vector2(200.0 * s, 28.0 * s), 21.0, C_IVORY, true, true)
		_lbl(_view_construction, "42%", Vector2(sx + 218.0 * s, sy + 36.0 * s), Vector2(70.0 * s, 28.0 * s), 21.0, C_GOLD, true, true, HORIZONTAL_ALIGNMENT_RIGHT)
		_box(_view_construction, Vector2(sx + 20.0 * s, sy + 72.0 * s), Vector2(268.0 * s, 6.0 * s), Color(0, 0, 0, 0.55))
		_box(_view_construction, Vector2(sx + 20.0 * s, sy + 72.0 * s), Vector2(113.0 * s, 6.0 * s), C_GOLD)
		var site_rows := [
			["Madeira entregue", "12 / 12"],
			["Pedra entregue", "6 / 6"],
			["Construtores", "1 / 2 · Alden"],
		]
		for r_i in range(3):
			var ry := sy + (90.0 + float(r_i) * 24.0) * s
			_lbl(_view_construction, site_rows[r_i][0], Vector2(sx + 20.0 * s, ry), Vector2(160.0 * s, 20.0 * s), 12.2, Color(0.84, 0.82, 0.77, 1.0))
			_lbl(_view_construction, site_rows[r_i][1], Vector2(sx + 178.0 * s, ry), Vector2(110.0 * s, 20.0 * s), 12.2, C_IVORY, false, true, HORIZONTAL_ALIGNMENT_RIGHT)
		_box(_view_construction, Vector2(sx + 20.0 * s, sy + 172.0 * s), Vector2(268.0 * s, 32.0 * s), Color(0.18, 0.08, 0.07, 0.28), Color(0.839, 0.416, 0.345, 0.65), 1)
		_lbl(_view_construction, "Desmontar Marco", Vector2(sx + 20.0 * s, sy + 172.0 * s), Vector2(268.0 * s, 32.0 * s), 13.0, C_ROSE, true, false, HORIZONTAL_ALIGNMENT_CENTER)

		# Bottom-Right Two Tall Stepped Alabaster Maquette Slabs (Exact D2_C_construction layout!)
		var m2w := 206.0 * s
		var m2h := 244.0 * s
		var m1w := 190.0 * s
		var m1h := 218.0 * s
		var base_bottom := h - 118.0 * s
		var m2x := w - 24.0 * s - m2w
		var m2y := base_bottom - m2h - 14.0 * s  # translateY(-14px) elevated selected maquette!
		var m1x := m2x - 14.0 * s - m1w
		var m1y := base_bottom - m1h

		# Shelter Maquette
		_slab(_view_construction, "maquette_shelter", Vector2(m1x, m1y))
		_img(_view_construction, tex_shelter, Vector2(m1x + 37.0 * s, m1y + 14.0 * s), Vector2(116.0 * s, 116.0 * s))
		_lbl(_view_construction, "Abrigo Básico", Vector2(m1x + 10.0 * s, m1y + 136.0 * s), Vector2(m1w - 20.0 * s, 22.0 * s), 15.8, C_INK, true, true, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(_view_construction, "Moradia · 4×4 m", Vector2(m1x + 10.0 * s, m1y + 160.0 * s), Vector2(m1w - 20.0 * s, 17.0 * s), 10.8, C_INK_SUB, false, false, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(_view_construction, "12 Mad · 6 Ped", Vector2(m1x + 10.0 * s, m1y + 183.0 * s), Vector2(m1w - 20.0 * s, 19.0 * s), 11.8, C_GREEN, false, true, HORIZONTAL_ALIGNMENT_CENTER)

		# Depot Maquette (Selected / Elevated)
		_slab(_view_construction, "maquette_depot_sel", Vector2(m2x, m2y))
		_lbl(_view_construction, "● EM POSIÇÃO", Vector2(m2x + 12.0 * s, m2y + 13.0 * s), Vector2(m2w - 24.0 * s, 16.0 * s), 9.8, C_GREEN, false, true, HORIZONTAL_ALIGNMENT_CENTER)
		_img(_view_construction, tex_depot, Vector2(m2x + 39.0 * s, m2y + 32.0 * s), Vector2(128.0 * s, 128.0 * s))
		_lbl(_view_construction, "Depósito Rústico", Vector2(m2x + 10.0 * s, m2y + 166.0 * s), Vector2(m2w - 20.0 * s, 23.0 * s), 16.5, C_INK, true, true, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(_view_construction, "Protege 50/50/30 · 5×4 m", Vector2(m2x + 10.0 * s, m2y + 190.0 * s), Vector2(m2w - 20.0 * s, 17.0 * s), 10.8, C_INK_SUB, false, false, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(_view_construction, "18 Mad · 10 Ped · 45 s", Vector2(m2x + 10.0 * s, m2y + 213.0 * s), Vector2(m2w - 20.0 * s, 19.0 * s), 12.0, C_GREEN, false, true, HORIZONTAL_ALIGNMENT_CENTER)

		# ------------------------------------------------------------------
		# VIEW 3: SELEÇÃO & LINHAGEM (Exact reproduction of D2_D_lineage!)
		# ------------------------------------------------------------------
		_view_lineage = Control.new()
		_view_lineage.size = vp_size
		_view_lineage.visible = false
		_view_lineage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view_lineage)
		_add_resource_cairn(_view_lineage)
		_add_top_plaque(_view_lineage, true)

		var l_x1 := 24.0 * s
		var rsw := 108.0 * s
		var rsh := 154.0 * s
		var l_y1 := h - 24.0 * s - rsh - 22.0 * s  # translateY(-22px) raised selected stele!
		_slab(_view_lineage, "founder_stele_raised", Vector2(l_x1, l_y1))
		_lbl(_view_lineage, "SELECIONADO", Vector2(l_x1 + 6.0 * s, l_y1 + 12.0 * s), Vector2(rsw - 12.0 * s, 14.0 * s), 9.0, C_GOLD, false, true, HORIZONTAL_ALIGNMENT_CENTER)
		_portrait(_view_lineage, tex_alden, Vector2(l_x1 + 23.0 * s, l_y1 + 30.0 * s), 62.0 * s, C_GOLD_HI)
		_lbl(_view_lineage, "Alden", Vector2(l_x1 + 8.0 * s, l_y1 + 99.0 * s), Vector2(rsw - 16.0 * s, 21.0 * s), 15.5, C_IVORY, true, true, HORIZONTAL_ALIGNMENT_CENTER)
		_lbl(_view_lineage, "Pessoal", Vector2(l_x1 + 8.0 * s, l_y1 + 121.0 * s), Vector2(rsw - 16.0 * s, 16.0 * s), 10.5, C_GOLD_HI, false, false, HORIZONTAL_ALIGNMENT_CENTER)
		_hitbox(_view_lineage, Vector2(l_x1, l_y1), Vector2(rsw, rsh), func() -> void: set_view("hud"))

		# Extended Stone Blade right next to raised stele (gap=14, w=454, h=214)
		var bx := l_x1 + rsw + 14.0 * s
		var bw := 454.0 * s
		var bh := 214.0 * s
		var by := h - 24.0 * s - bh
		_slab(_view_lineage, "lineage_blade", Vector2(bx, by))
		_lbl(_view_lineage, "Alden · Casa Fundadora", Vector2(bx + 22.0 * s, by + 18.0 * s), Vector2(310.0 * s, 26.0 * s), 20.0, C_IVORY, true, true)
		_lbl(_view_lineage, "Adulto · Proteção dos Líderes · Ordem pessoal ativa", Vector2(bx + 22.0 * s, by + 44.0 * s), Vector2(318.0 * s, 16.0 * s), 10.8, C_GOLD)
		_box(_view_lineage, Vector2(bx + 356.0 * s, by + 22.0 * s), Vector2(76.0 * s, 24.0 * s), Color(0, 0, 0, 0.2), C_GOLD, 1)
		_lbl(_view_lineage, "PESSOAL", Vector2(bx + 356.0 * s, by + 22.0 * s), Vector2(76.0 * s, 24.0 * s), 10.0, C_GOLD, false, true, HORIZONTAL_ALIGNMENT_CENTER)
		# Horizontal subtle divider under header
		_box(_view_lineage, Vector2(bx + 22.0 * s, by + 68.0 * s), Vector2(410.0 * s, 1.0 * s), Color(0.875, 0.737, 0.447, 0.35))

		# Left column inside blade: Physical Carry & Release Button
		_lbl(_view_lineage, "Carga física: 8 / 20 peso (40%)", Vector2(bx + 22.0 * s, by + 82.0 * s), Vector2(246.0 * s, 18.0 * s), 11.8, C_IVORY, false, true)
		_box(_view_lineage, Vector2(bx + 22.0 * s, by + 104.0 * s), Vector2(240.0 * s, 6.0 * s), Color(0, 0, 0, 0.55))
		_box(_view_lineage, Vector2(bx + 22.0 * s, by + 104.0 * s), Vector2(96.0 * s, 6.0 * s), C_SAGE)
		_lbl(_view_lineage, "4 madeiras · Velocidade 4,0 m/s", Vector2(bx + 22.0 * s, by + 116.0 * s), Vector2(246.0 * s, 18.0 * s), 11.2, C_MUTED)
		_box(_view_lineage, Vector2(bx + 22.0 * s, by + 146.0 * s), Vector2(240.0 * s, 40.0 * s), Color(0.875, 0.737, 0.447, 0.18), C_GOLD, 1)
		_lbl(_view_lineage, "Liberar para Comunidade (P-RUX-2)", Vector2(bx + 26.0 * s, by + 148.0 * s), Vector2(232.0 * s, 36.0 * s), 11.2, C_IVORY, true, true, HORIZONTAL_ALIGNMENT_CENTER)

		# Right column inside blade: Cairn Stacked Stones Genealogy ("PILHA DA LINHAGEM")
		_box(_view_lineage, Vector2(bx + 278.0 * s, by + 80.0 * s), Vector2(1.0 * s, 112.0 * s), Color(0.875, 0.737, 0.447, 0.28))
		_lbl(_view_lineage, "PILHA DA LINHAGEM", Vector2(bx + 286.0 * s, by + 82.0 * s), Vector2(150.0 * s, 16.0 * s), 9.2, C_GOLD, false, true, HORIZONTAL_ALIGNMENT_CENTER)
		_box(_view_lineage, Vector2(bx + 306.0 * s, by + 105.0 * s), Vector2(110.0 * s, 26.0 * s), Color(0, 0, 0, 0.25), Color(0.875, 0.737, 0.447, 0.52), 1)
		_lbl(_view_lineage, "1ª Geração (T5)", Vector2(bx + 306.0 * s, by + 105.0 * s), Vector2(110.0 * s, 26.0 * s), 10.2, C_MUTED, false, false, HORIZONTAL_ALIGNMENT_CENTER)
		_box(_view_lineage, Vector2(bx + 360.0 * s, by + 135.0 * s), Vector2(2.0 * s, 12.0 * s), C_GOLD)
		_box(_view_lineage, Vector2(bx + 298.0 * s, by + 151.0 * s), Vector2(58.0 * s, 28.0 * s), Color(0.875, 0.737, 0.447, 0.24), C_GOLD, 1)
		_lbl(_view_lineage, "Alden", Vector2(bx + 298.0 * s, by + 151.0 * s), Vector2(58.0 * s, 28.0 * s), 11.5, C_IVORY, true, false, HORIZONTAL_ALIGNMENT_CENTER)
		_box(_view_lineage, Vector2(bx + 364.0 * s, by + 151.0 * s), Vector2(58.0 * s, 28.0 * s), Color(1, 1, 1, 0.08), Color(0.875, 0.737, 0.447, 0.45), 1)
		_lbl(_view_lineage, "Brena", Vector2(bx + 364.0 * s, by + 151.0 * s), Vector2(58.0 * s, 28.0 * s), 11.5, C_IVORY, true, false, HORIZONTAL_ALIGNMENT_CENTER)

		# ------------------------------------------------------------------
		# VIEW 4: MENU PRINCIPAL (Exact reproduction of D2_E_menu!)
		# ------------------------------------------------------------------
		_view_menu = Control.new()
		_view_menu.size = vp_size
		_view_menu.visible = false
		_view_menu.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_view_menu)

		# Subtle atmospheric darkening scrim over live 3D clearing
		var scrim := ColorRect.new()
		scrim.size = vp_size
		scrim.color = Color(0.043, 0.047, 0.055, 0.42)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view_menu.add_child(scrim)

		# Exact Diagonal Basalt Kintsugi Monolith + Double Golden Seam (uses 1080p logical scale cleanly!)
		var prev_s := s
		s = h / 1080.0
		var mh_scale := s
		var mono := TextureRect.new()
		mono.texture = menu_monolith_tex
		mono.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mono.stretch_mode = TextureRect.STRETCH_SCALE
		mono.position = Vector2.ZERO
		mono.size = Vector2(632.0 * mh_scale, h)
		mono.mouse_filter = Control.MOUSE_FILTER_STOP
		_view_menu.add_child(mono)

		# Top Crest + Title (Exact D2_E_menu typography & positions)
		var mx0 := 56.0 * mh_scale
		_img(_view_menu, tex_emblem, Vector2(mx0, 64.0 * mh_scale), Vector2(68.0 * mh_scale, 68.0 * mh_scale))
		_lbl(_view_menu, "DIREÇÃO 2 · MARCOS DE PEDRA E ECLIPSE", Vector2(mx0 + 82.0 * mh_scale, 76.0 * mh_scale), Vector2(420.0 * mh_scale, 18.0 * mh_scale), 10.5, C_GOLD, false, true)
		_lbl(_view_menu, "Luz da Travessia · Mistério da Sombra", Vector2(mx0 + 82.0 * mh_scale, 98.0 * mh_scale), Vector2(420.0 * mh_scale, 18.0 * mh_scale), 11.8, C_MUTED)
		_lbl(_view_menu, "DAWN", Vector2(mx0, 150.0 * mh_scale), Vector2(440.0 * mh_scale, 62.0 * mh_scale), 54.0, C_IVORY, true, true)
		_lbl(_view_menu, "OF KIN", Vector2(mx0, 208.0 * mh_scale), Vector2(440.0 * mh_scale, 62.0 * mh_scale), 54.0, C_IVORY, true, true)
		_box(_view_menu, Vector2(mx0, 282.0 * mh_scale), Vector2(220.0 * mh_scale, 2.0 * mh_scale), C_GOLD)
		var sub_l := _lbl(_view_menu, "Cada marco erguido na terra desconhecida\npreserva a memória dos fundadores.", Vector2(mx0, 296.0 * mh_scale), Vector2(360.0 * mh_scale, 46.0 * mh_scale), 13.5, Color(0.80, 0.78, 0.72, 1.0))
		sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		# Primary Alabaster Slanted Button ("Iniciar Assentamento / CAP. I")
		var b_y0 := 544.0 * mh_scale
		var btn_w := 360.0 * mh_scale
		_slab(_view_menu, "menu_primary_alab", Vector2(mx0, b_y0), Vector2(btn_w, 52.0 * mh_scale))
		_lbl(_view_menu, "Iniciar Assentamento", Vector2(mx0 + 20.0 * mh_scale, b_y0 + 10.0 * mh_scale), Vector2(250.0 * mh_scale, 32.0 * mh_scale), 17.5, C_INK, true, true)
		_lbl(_view_menu, "CAP. I", Vector2(mx0 + 272.0 * mh_scale, b_y0 + 14.0 * mh_scale), Vector2(68.0 * mh_scale, 24.0 * mh_scale), 11.0, Color(0.43, 0.33, 0.16, 1.0), false, true, HORIZONTAL_ALIGNMENT_RIGHT)
		_hitbox(_view_menu, Vector2(mx0, b_y0), Vector2(btn_w, 52.0 * mh_scale), func() -> void: set_view("hud"))

		# Exact 4 secondary monolith menu entries
		var m_items := [
			["Continuar", "PROPOSTA T3.8", Color(0, 0, 0, 0.34), Color(0.875, 0.737, 0.447, 0.55), Color(0.78, 0.75, 0.69, 1.0)],
			["Carregar Marco", "PROPOSTA T3.8", Color(0, 0, 0, 0.34), Color(0.875, 0.737, 0.447, 0.55), Color(0.78, 0.75, 0.69, 1.0)],
			["Configurações", "", Color(0, 0, 0, 0.42), C_GOLD, C_IVORY],
			["Sair", "", Color(0.173, 0.063, 0.055, 0.44), Color(0.776, 0.416, 0.345, 1.0), C_ROSE],
		]
		for k in range(m_items.size()):
			var iy := b_y0 + (64.0 + float(k) * 56.0) * mh_scale
			_box(_view_menu, Vector2(mx0, iy), Vector2(btn_w, 45.0 * mh_scale), m_items[k][2])
			_box(_view_menu, Vector2(mx0, iy), Vector2(3.0 * mh_scale, 45.0 * mh_scale), m_items[k][3])
			_lbl(_view_menu, m_items[k][0], Vector2(mx0 + 18.0 * mh_scale, iy + 8.0 * mh_scale), Vector2(210.0 * mh_scale, 28.0 * mh_scale), 15.0, m_items[k][4], true)
			if m_items[k][1] != "":
				_lbl(_view_menu, m_items[k][1], Vector2(mx0 + 228.0 * mh_scale, iy + 10.0 * mh_scale), Vector2(118.0 * mh_scale, 24.0 * mh_scale), 9.5, C_GOLD, false, true, HORIZONTAL_ALIGNMENT_RIGHT)

		_lbl(_view_menu, "UI-0 R2.2 · Basalto Kintsugi & Alabastro · Godot 4.7.2", Vector2(mx0, h - 54.0 * mh_scale), Vector2(380.0 * mh_scale, 20.0 * mh_scale), 10.8, Color(0.55, 0.54, 0.51, 1.0))
		s = prev_s

	func set_view(v: String) -> void:
		_current_view = v
		_view_hud.visible = (v == "hud")
		_view_construction.visible = (v == "construction")
		_view_lineage.visible = (v == "lineage")
		_view_menu.visible = (v == "menu")

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			var ke := event as InputEventKey
			if not ke.pressed or ke.echo:
				return
			match ke.keycode:
				KEY_1:
					set_view("hud")
				KEY_2, KEY_B:
					set_view("construction")
				KEY_3, KEY_H:
					set_view("lineage")
				KEY_4, KEY_M:
					set_view("menu")
				KEY_ESCAPE:
					set_view("menu" if _current_view == "hud" else "hud")


func _load_tex(fname: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ASSETS_DIR + fname))
	return ImageTexture.create_from_image(img)


func _load_fonts() -> void:
	for p in ["C:/Windows/Fonts/pala.ttf", "C:/Windows/Fonts/georgia.ttf"]:
		if FileAccess.file_exists(p):
			var ff := FontFile.new()
			if ff.load_dynamic_font(p) == OK:
				_font_serif = ff
				break
	for p in ["C:/Windows/Fonts/palab.ttf", "C:/Windows/Fonts/georgiab.ttf"]:
		if FileAccess.file_exists(p):
			var ffb := FontFile.new()
			if ffb.load_dynamic_font(p) == OK:
				_font_serif_bold = ffb
				break
	if _font_serif == null:
		_font_serif = _font_serif_bold
	for p in ["C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"]:
		if FileAccess.file_exists(p):
			var fs := FontFile.new()
			if fs.load_dynamic_font(p) == OK:
				_font_sans = fs
				break
	for p in ["C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"]:
		if FileAccess.file_exists(p):
			var fsb := FontFile.new()
			if fsb.load_dynamic_font(p) == OK:
				_font_sans_bold = fsb
				break
	if _font_sans_bold == null:
		_font_sans_bold = _font_sans


func _hide_legacy_hud(scene_root: Node) -> void:
	for n in scene_root.find_children("*", "CanvasLayer", true, false):
		n.visible = false
	for n in scene_root.find_children("*", "Control", true, false):
		if n.get_parent() == scene_root:
			n.visible = false


func _make_showcase(vp_size: Vector2, scale_k: float) -> FaithfulD2Showcase:
	var sc := FaithfulD2Showcase.new()
	sc.atlas_tex = _atlas_tex
	sc.menu_monolith_tex = _menu_monolith_tex
	sc.manifest = _manifest
	sc.f_serif = _font_serif
	sc.f_serif_b = _font_serif_bold
	sc.f_sans = _font_sans
	sc.f_sans_b = _font_sans_bold
	sc.tex_alden = _tex_alden
	sc.tex_brena = _tex_brena
	sc.tex_emblem = _tex_emblem
	sc.tex_shelter = _tex_shelter
	sc.tex_depot = _tex_depot
	sc.build(vp_size, scale_k)
	return sc


func _capture(path_res: String) -> void:
	for _i in range(6):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path_res))
	print("Captured %s (%dx%d)" % [path_res.get_file(), img.get_width(), img.get_height()])


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
	_interactive_mode = OS.get_cmdline_user_args().has("--interactive")
	_load_fonts()
	_atlas_tex = _load_tex("d2_2_faithful_atlas.png")
	_menu_monolith_tex = _load_tex("d2_2_menu_monolith.png")
	_manifest = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(ASSETS_DIR + "atlas_manifest.json")))
	_tex_alden = _load_tex("portrait_alden.jpg")
	_tex_brena = _load_tex("portrait_brena.jpg")
	_tex_emblem = _load_tex("emblem_dawn_of_kin.png")
	_tex_shelter = _load_tex("d1_shelter_mini.png")
	_tex_depot = _load_tex("d1_depot_mini.png")

	# Load the EXACT same 3D reference scene used for D2 original mockups (base_m1_clean)!
	var scene := (load(REFERENCE_3D_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_hide_legacy_hud(scene)

	if _interactive_mode:
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_title("Dawn of Kin — UI-0 R2.2 Faithful D2 Showcase ([1] HUD · [2/B] Construção · [3/H] Linhagem · [4/M] Menu)")
		await process_frame
		var layer := CanvasLayer.new()
		layer.layer = 50
		root.add_child(layer)
		layer.add_child(_make_showcase(root.get_visible_rect().size, 1.22))
		print("=== UI-0 R2.2 Interactive Mode Active (1=HUD, 2/B=Construção, 3/H=Linhagem, 4/M=Menu) ===")
		return

	call_deferred("_run_automated_suite")


func _run_automated_suite() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results := {
		"engine": Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_video_adapter_name(),
		"scene": REFERENCE_3D_SCENE,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
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
		var vp := root.get_visible_rect().size
		# Match exact D2_B_hud_1280x720 physical pixel scale (88/108 / 0.6667 = 1.22) at 720p, 1.0 at 1080p!
		var scale_k := 1.22 if res.x <= 1366 else 1.0
		print("=== GODOT R2.2 FAITHFUL D2 SHOWCASE & BENCHMARK: %s (logical=%dx%d, scale=%.2f) ===" % [rkey, int(vp.x), int(vp.y), scale_k])

		var sc := _make_showcase(vp, scale_k)
		layer.add_child(sc)
		sc.set_view("hud")
		await _capture(OUT_DIR + "G_godot_D2_2_hud_%s.png" % rkey)
		sc.set_view("construction")
		await _capture(OUT_DIR + "G_godot_D2_2_construction_%s.png" % rkey)
		sc.set_view("lineage")
		await _capture(OUT_DIR + "G_godot_D2_2_lineage_%s.png" % rkey)
		sc.set_view("menu")
		await _capture(OUT_DIR + "G_godot_D2_2_menu_%s.png" % rkey)
		sc.queue_free()
		await process_frame

		# Reproducible un-vsynced benchmark across equivalent baseline + D2.2 faithful states
		var sc_names := ["BASELINE_3D", "D2_2_FAITHFUL_HUD", "D2_2_FAITHFUL_CONSTRUCTION", "D2_2_FAITHFUL_LINEAGE"]
		var raw := {}
		for nm in sc_names:
			raw[nm] = []

		for _rep in range(REPETITIONS):
			for nm in sc_names:
				var node: FaithfulD2Showcase = null
				if nm != "BASELINE_3D":
					node = _make_showcase(vp, scale_k)
					layer.add_child(node)
					if nm == "D2_2_FAITHFUL_HUD":
						node.set_view("hud")
					elif nm == "D2_2_FAITHFUL_CONSTRUCTION":
						node.set_view("construction")
					elif nm == "D2_2_FAITHFUL_LINEAGE":
						node.set_view("lineage")
				var m := await _measure_block()
				raw[nm].append(m)
				if node != null:
					node.queue_free()
					await process_frame

		var res_out := {}
		for nm in sc_names:
			var avgs: Array[float] = []
			var p95s: Array[float] = []
			var p99s: Array[float] = []
			var over := 0
			for m in raw[nm]:
				avgs.append(float(m["avg_ms"]))
				p95s.append(float(m["p95_ms"]))
				p99s.append(float(m["p99_ms"]))
				over += int(m["frames_over_100ms"])
			var sp95 := p95s.duplicate(); sp95.sort()
			var sp99 := p99s.duplicate(); sp99.sort()
			res_out[nm] = {
				"median_avg_ms": _median(avgs),
				"median_p95_ms": _median(p95s),
				"median_p99_ms": _median(p99s),
				"min_p95_ms": sp95[0],
				"max_p95_ms": sp95[sp95.size() - 1],
				"min_p99_ms": sp99[0],
				"max_p99_ms": sp99[sp99.size() - 1],
				"total_frames_over_100ms": over,
				"draw_calls": raw[nm][0]["draw_calls"],
				"nodes": raw[nm][0]["nodes"],
				"runs": raw[nm],
			}
			print("%s [%s] | med_avg=%.3f ms | med_p95=%.3f ms (%.3f..%.3f) | med_p99=%.3f ms (%.3f..%.3f) | >100ms=%d | dc=%d | nodes=%d" % [
				nm, rkey, res_out[nm]["median_avg_ms"], res_out[nm]["median_p95_ms"],
				res_out[nm]["min_p95_ms"], res_out[nm]["max_p95_ms"],
				res_out[nm]["median_p99_ms"], res_out[nm]["min_p99_ms"], res_out[nm]["max_p99_ms"],
				over, res_out[nm]["draw_calls"], res_out[nm]["nodes"]
			])
		results["resolutions"][rkey] = res_out

	var f := FileAccess.open(ProjectSettings.globalize_path(BENCH_JSON), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print("Saved benchmark_results_r2_2.json -> %s" % ProjectSettings.globalize_path(BENCH_JSON))
	quit(0)
