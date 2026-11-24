extends RefCounted
## Visual language of the interface: warm paper, plum ink and verbena colours,
## rounded fonts and small vector icons drawn by code (no image files).

const INK := Color("2b2140")
const INK_SOFT := Color("5b4a6e")
const PAPER := Color("fff4dc")
const PAPER_DARK := Color("f3e2bf")
const CARD := Color("fffaf0")
const CORAL := Color("ff6b6b")
const SUN := Color("ffd166")
const MINT := Color("06d6a0")
const SKY := Color("4cc9f0")
const PINK := Color("f78fb3")
const LILAC := Color("b9a6ff")
const WOOD := Color("c98a55")
const NIGHT := Color("2f2a5a")
const FESTIVE = [Color("ff6b6b"), Color("ffd166"), Color("06d6a0"), Color("4cc9f0"), Color("f78fb3"), Color("c59dff")]

static var _fonts := {}

static func font(kind:String = "body", weight:int = 700) -> Font:
	## "title" is Fredoka, "body" is Nunito; both are variable fonts.
	var key := "%s%d" % [kind, weight]
	if _fonts.has(key): return _fonts[key]
	var base:FontFile = load("res://game/fonts/Fredoka.ttf" if kind == "title" else "res://game/fonts/Nunito.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	_fonts[key] = fv
	return fv

static func card(fill:Color = CARD, radius:int = 18, border:Color = INK, bw:int = 3, shadow:int = 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.shadow_color = Color(INK, 0.35)
	s.shadow_size = 0
	s.shadow_offset = Vector2(0, shadow)
	s.anti_aliasing = true
	if shadow > 0: s.shadow_size = 1
	return s

static func text(ci:CanvasItem, pos:Vector2, value:String, size:int, color:Color = INK, kind:String = "body", weight:int = 800, align:int = HORIZONTAL_ALIGNMENT_LEFT, width:float = -1, outline:int = 0, outline_color:Color = INK):
	var f := font(kind, weight)
	if outline > 0: ci.draw_string_outline(f, pos, value, align, width, size, outline, outline_color)
	ci.draw_string(f, pos, value, align, width, size, color)

static func text_width(value:String, size:int, kind:String = "body", weight:int = 800) -> float:
	return font(kind, weight).get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

static func pill(ci:CanvasItem, rect:Rect2, fill:Color, frac:float, back:Color = Color(INK, 0.18)):
	var r := rect.size.y * 0.5
	var bg := card(back, int(r), Color(0, 0, 0, 0), 0, 0)
	ci.draw_style_box(bg, rect)
	if frac <= 0.001: return
	var w := maxf(rect.size.y, rect.size.x * clampf(frac, 0.0, 1.0))
	ci.draw_style_box(card(fill, int(r), Color(0, 0, 0, 0), 0, 0), Rect2(rect.position, Vector2(w, rect.size.y)))
	ci.draw_line(rect.position + Vector2(r, rect.size.y * 0.3), rect.position + Vector2(w - r, rect.size.y * 0.3), Color(1, 1, 1, 0.35), maxf(1.0, rect.size.y * 0.18), true)

static func ring(ci:CanvasItem, c:Vector2, r:float, frac:float, color:Color, width:float, back:Color = Color(INK, 0.2)):
	ci.draw_arc(c, r, 0, TAU, 48, back, width, true)
	if frac > 0.001: ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0, 1), 48, color, width, true)

static func keycap(ci:CanvasItem, c:Vector2, key:String, size:float = 30.0, fill:Color = CARD):
	var rect := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
	ci.draw_style_box(card(fill, int(size * 0.28), INK, 2, 3), rect)
	var fs := int(size * 0.55) if key.length() == 1 else int(size * 0.34)
	text(ci, c + Vector2(-size * 0.5, fs * 0.36), key, fs, INK, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, size)

# ------------------------------------------------------------------ icons (centre c, size s)
static func icon(ci:CanvasItem, name:String, c:Vector2, s:float, tint:Color = Color.WHITE):
	match name:
		"house":
			var body := PackedVector2Array([c + Vector2(-0.38, -0.05) * s, c + Vector2(0.38, -0.05) * s, c + Vector2(0.38, 0.42) * s, c + Vector2(-0.38, 0.42) * s])
			ci.draw_colored_polygon(body, Color("ffd99a") * tint)
			var roof := PackedVector2Array([c + Vector2(-0.5, 0.0) * s, c + Vector2(0, -0.45) * s, c + Vector2(0.5, 0.0) * s])
			ci.draw_colored_polygon(roof, Color("4c7fc0") * tint)
			ci.draw_rect(Rect2(c + Vector2(-0.1, 0.12) * s, Vector2(0.2, 0.3) * s), Color("3f6f9f") * tint)
			ci.draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], c + Vector2(0.38, 0.0) * s, body[2], body[3], c + Vector2(-0.38, 0.0) * s, roof[0]]), INK, maxf(1.5, s * 0.06), true)
		"plank":
			var r := Rect2(c - Vector2(0.48, 0.22) * s, Vector2(0.96, 0.44) * s)
			ci.draw_style_box(card(WOOD, int(s * 0.1), INK, maxi(1, int(s * 0.05)), 0), r)
			for i in 2: ci.draw_line(c + Vector2(-0.35, -0.06 + i * 0.12) * s, c + Vector2(0.3, -0.06 + i * 0.12) * s, Color("9a6a48"), maxf(1.0, s * 0.04), true)
			ci.draw_circle(c + Vector2(0.38, 0), s * 0.05, Color("9a6a48"))
		"hammer":
			# claw hammer: wooden handle and a steel head
			var hx := Transform2D(-0.7, c)
			var handle := PackedVector2Array([Vector2(-0.07, -0.05), Vector2(0.07, -0.05), Vector2(0.06, 0.45), Vector2(-0.06, 0.45)])
			var head := PackedVector2Array([Vector2(-0.34, -0.22), Vector2(0.2, -0.22), Vector2(0.24, -0.05), Vector2(-0.34, -0.05)])
			var claw := PackedVector2Array([Vector2(0.2, -0.22), Vector2(0.42, -0.36), Vector2(0.36, -0.12), Vector2(0.24, -0.05)])
			for shape in [[handle, WOOD], [head, Color("8f9fb5")], [claw, Color("8f9fb5")]]:
				var pts := PackedVector2Array()
				for v in shape[0]: pts.append(hx * (v * s))
				ci.draw_colored_polygon(pts, shape[1])
				pts.append(pts[0])
				ci.draw_polyline(pts, INK, maxf(1.0, s * 0.06), true)
		"coin":
			ci.draw_circle(c, s * 0.42, INK)
			ci.draw_circle(c, s * 0.36, SUN)
			ci.draw_arc(c, s * 0.24, 0, TAU, 20, Color("e0a63a"), maxf(1.0, s * 0.06), true)
			ci.draw_line(c + Vector2(-0.12, -0.2) * s, c + Vector2(0.05, -0.27) * s, Color(1, 1, 1, 0.7), maxf(1.0, s * 0.06), true)
		"medkit":
			ci.draw_style_box(card(Color.WHITE, int(s * 0.14), INK, maxi(1, int(s * 0.06)), 0), Rect2(c - Vector2(0.4, 0.34) * s, Vector2(0.8, 0.68) * s))
			ci.draw_rect(Rect2(c - Vector2(0.24, 0.07) * s, Vector2(0.48, 0.14) * s), CORAL)
			ci.draw_rect(Rect2(c - Vector2(0.07, 0.24) * s, Vector2(0.14, 0.48) * s), CORAL)
		"traca":
			var r := Rect2(c - Vector2(0.14, 0.3) * s, Vector2(0.28, 0.62) * s)
			ci.draw_style_box(card(CORAL, int(s * 0.08), INK, maxi(1, int(s * 0.05)), 0), r)
			ci.draw_rect(Rect2(c + Vector2(-0.14, -0.05) * s, Vector2(0.28, 0.1) * s), SUN)
			ci.draw_line(c + Vector2(0, -0.3) * s, c + Vector2(0.12, -0.45) * s, INK, maxf(1.0, s * 0.05), true)
			ci.draw_circle(c + Vector2(0.14, -0.47) * s, s * 0.08, SUN)
		"bulb":
			# paper lantern; tint alpha < 0.5 draws it unlit
			var lit := tint.a > 0.5
			var col := Color(tint.r, tint.g, tint.b) if lit else Color("d9cfc0")
			if lit: ci.draw_circle(c, s * 0.62, Color(col, 0.28))
			ci.draw_rect(Rect2(c + Vector2(-0.14, -0.5) * s, Vector2(0.28, 0.12) * s), INK)
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				pts.append(c + Vector2(cos(a) * 0.34, sin(a) * 0.4) * s)
			ci.draw_colored_polygon(pts, col)
			pts.append(pts[0])
			ci.draw_polyline(pts, INK, maxf(1.0, s * 0.06), true)
			for x in [-0.12, 0.12]: ci.draw_line(c + Vector2(x, -0.36) * s, c + Vector2(x * 1.2, 0.36) * s, Color(INK, 0.35), maxf(1.0, s * 0.03), true)
		"sun":
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.36, c + Vector2(cos(a), sin(a)) * s * 0.5, Color("ffb35c"), maxf(2.0, s * 0.08), true)
			ci.draw_circle(c, s * 0.3, SUN)
			ci.draw_arc(c, s * 0.3, 0, TAU, 24, Color("e0a63a"), maxf(1.0, s * 0.05), true)
		"moon":
			ci.draw_circle(c, s * 0.36, Color("fff2c0"))
			ci.draw_circle(c + Vector2(0.16, -0.1) * s, s * 0.3, NIGHT)
		"sprout":
			ci.draw_circle(c + Vector2(0, 0.08) * s, s * 0.32, Color("a6d69c"))
			ci.draw_arc(c + Vector2(0, 0.08) * s, s * 0.32, 0, TAU, 20, INK, maxf(1.0, s * 0.06), true)
			ci.draw_line(c + Vector2(0, -0.22) * s, c + Vector2(0, -0.4) * s, Color("4f9a4a"), maxf(1.0, s * 0.06), true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.4) * s, c + Vector2(0.24, -0.5) * s, c + Vector2(0.1, -0.32) * s]), Color("7cd06a"))
			ci.draw_circle(c + Vector2(-0.1, 0.04) * s, s * 0.05, INK)
			ci.draw_circle(c + Vector2(0.12, 0.06) * s, s * 0.035, INK)
		"crown":
			var pts := PackedVector2Array([c + Vector2(-0.4, 0.25) * s, c + Vector2(-0.4, -0.2) * s, c + Vector2(-0.2, 0.02) * s, c + Vector2(0, -0.3) * s, c + Vector2(0.2, 0.02) * s, c + Vector2(0.4, -0.2) * s, c + Vector2(0.4, 0.25) * s])
			ci.draw_colored_polygon(pts, SUN)
			pts.append(pts[0])
			ci.draw_polyline(pts, INK, maxf(1.0, s * 0.06), true)
		"bell":
			var pts := PackedVector2Array([c + Vector2(-0.34, 0.25) * s, c + Vector2(-0.24, -0.15) * s, c + Vector2(0, -0.32) * s, c + Vector2(0.24, -0.15) * s, c + Vector2(0.34, 0.25) * s])
			ci.draw_colored_polygon(pts, SUN * tint)
			pts.append(pts[0])
			ci.draw_polyline(pts, INK, maxf(1.0, s * 0.06), true)
			ci.draw_circle(c + Vector2(0, 0.33) * s, s * 0.08, INK)
		"heart":
			var pts := PackedVector2Array()
			for i in 24:
				var t := TAU * i / 24.0
				pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * s / 36.0)
			ci.draw_colored_polygon(pts, CORAL * tint)
			pts.append(pts[0])
			ci.draw_polyline(pts, INK, maxf(1.0, s * 0.06), true)

static func bunting(ci:CanvasItem, from:Vector2, to:Vector2, count:int, sag:float, size:float, seed:int = 0):
	## A string of paper pennants: the festival motif used on panel edges.
	var pts := PackedVector2Array()
	for i in count + 1:
		var t := float(i) / count
		pts.append(from.lerp(to, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
	ci.draw_polyline(pts, Color(INK, 0.7), 2.0, true)
	for i in count:
		var a := pts[i]
		var b := pts[i + 1]
		var m := (a + b) * 0.5
		ci.draw_colored_polygon(PackedVector2Array([a + (b - a) * 0.12, a + (b - a) * 0.88, m + Vector2(0, size)]), FESTIVE[(i + seed) % FESTIVE.size()])
