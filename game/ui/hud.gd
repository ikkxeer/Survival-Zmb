extends Control
## In-game HUD drawn as paper, ink and lanterns. It shows only what matters now:
## the house, the time of day, you, your weapon and what you can do next.
## Everything else (territory, community, details) lives in the map and the board.

const S = preload("res://game/ui/style.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const P := Data.Phase
const SLOT_COLORS = ["ffd166", "4cc9f0", "f78fb3", "06d6a0"]

var s := {}
var p := {}
var local := {}
var me := 0
var t := 0.0
var toasts := []           # [text, colour, life]
var ann := {}              # title, sub, colour, t, life
var report_lines := []
var report_t := 0.0
var last_gun := -1
var slots_t := 0.0
var last_core := -1.0
var house_shake := 0.0
var bloom := 0.0           # crosshair spread after shooting
var hit_t := 0.0
var hit_crit := false
var kill_t := 0.0
var over_t := 0.0          # seconds since the match ended (cinematic bars)
var forecast_t := 8.0
var last_phase := -1
var last_wave := -1
var indicators := []
var keys := {}             # action -> key label, from the player's bindings
var minimap_rect := Rect2()
var house_tex:Texture2D     # 3D portraits rendered by game/ui/portrait.gd
var mat_tex:Texture2D

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func feed(state:Dictionary, id:int, loc:Dictionary, dt:float):
	s = state
	me = id
	local = loc
	p = state.pl.get(id, {})
	t += dt
	over_t = over_t + dt if s.get("ph", -1) == P.OVER else 0.0
	bloom = move_toward(bloom, 0.0, dt * (1.2 + bloom * 4.0))
	hit_t = maxf(0.0, hit_t - dt)
	kill_t = maxf(0.0, kill_t - dt)
	if p.is_empty(): return
	if p.gun != last_gun:
		if last_gun >= 0: slots_t = 2.2
		last_gun = p.gun
	slots_t = maxf(0.0, slots_t - dt)
	if last_core >= 0 and s.core < last_core - 0.5: house_shake = 0.35
	last_core = s.core
	house_shake = maxf(0.0, house_shake - dt)
	if s.ph != last_phase or s.w != last_wave:
		forecast_t = 9.0
		last_phase = s.ph
		last_wave = s.w
	forecast_t = maxf(0.0, forecast_t - dt)
	for i in range(toasts.size() - 1, -1, -1):
		toasts[i][2] -= dt
		if toasts[i][2] <= 0: toasts.remove_at(i)
	if not ann.is_empty():
		ann.t += dt
		if ann.t > ann.life: ann = {}
	report_t = maxf(0.0, report_t - dt)
	queue_redraw()

func toast(msg:String, col:Color = S.SUN):
	for x in toasts:
		if x[0] == msg:
			x[2] = 5.0
			return
	toasts.append([msg, col, 5.0])
	while toasts.size() > 3: toasts.pop_front()

func announce(title:String, sub:String, col:Color, life:float):
	ann = {"title":title, "sub":sub, "col":col, "t":0.0, "life":life}

func report(lines:Array):
	report_lines = lines
	report_t = 8.0

func key(action:String, fallback:String) -> String:
	return keys.get(action, fallback)

# ================================================================== drawing
func _draw():
	if s.is_empty() or p.is_empty(): return
	if s.ph == P.OVER:
		# the ending plays like a cut-scene: no HUD, cinema bars, just the banner
		var k := smoothstep(0.0, 0.8, over_t)
		var bar := size.y * 0.1 * k
		draw_rect(Rect2(0, 0, size.x, bar), S.INK)
		draw_rect(Rect2(0, size.y - bar, size.x, bar), S.INK)
		draw_announce()
		return
	draw_world_marks()
	draw_house()
	draw_clock()
	draw_team()
	draw_notes()
	draw_badge()
	draw_weapon()
	draw_prompt()
	draw_toasts()
	draw_report()
	draw_announce()
	draw_crosshair()

# ------------------------------------------------------------------ crosshair
func shot(amount:float):
	bloom = minf(1.6, bloom + amount)

func hitmark(crit:bool):
	hit_t = 0.16
	hit_crit = crit

func killmark():
	kill_t = 0.32

func draw_crosshair():
	## A live crosshair: opens with each shot and while moving, shows hits, kills and reloads.
	if not local.get("cross_on", false): return
	var c:Vector2 = local.get("cross", size * 0.5)
	var moving:float = local.get("moving", 0.0)
	var gap := 7.0 + bloom * 13.0 + moving * 5.0
	var len := 8.0
	var col := Color.WHITE if not local.get("empty", false) else S.CORAL
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a:Vector2 = c + d * gap
		var b:Vector2 = c + d * (gap + len)
		draw_line(a, b, Color(S.INK, 0.85), 5.0, true)
		draw_line(a, b, col, 2.5, true)
	draw_circle(c, 2.6, Color(S.INK, 0.85))
	draw_circle(c, 1.5, col)
	var rl:float = local.get("reload", 0.0)
	if rl > 0.0:
		draw_arc(c, gap + len + 6.0, 0, TAU, 40, Color(S.INK, 0.5), 5.0, true)
		draw_arc(c, gap + len + 6.0, -PI * 0.5, -PI * 0.5 + TAU * rl, 40, S.SUN, 3.0, true)
	if hit_t > 0.0 or kill_t > 0.0:
		var killing := kill_t > 0.0
		var k := (kill_t / 0.32) if killing else (hit_t / 0.16)
		var r0 := 5.0 + (1.0 - k) * (6.0 if killing else 3.0)
		var r1 := r0 + (10.0 if killing else 7.0)
		var mc := S.CORAL if killing else (S.SUN if hit_crit else Color.WHITE)
		for i in 4:
			var dir := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
			draw_line(c + dir * r0, c + dir * r1, Color(S.INK, k), 5.5, true)
			draw_line(c + dir * r0, c + dir * r1, Color(mc, k), 3.0, true)
		if killing: draw_arc(c, r1 + 4.0, 0, TAU, 32, Color(S.CORAL, k * 0.7), 2.5, true)

# ------------------------------------------------------------------ house, materials, lanterns
func draw_house():
	## A round "photo" of the real house (rendered from its 3D model) framed like the
	## day medallion: the ring is its strength, the ribbon says how it is doing.
	var o := Vector2(24, 16) + Vector2(sin(t * 60.0), cos(t * 47.0)) * 4.0 * house_shake
	var frac:float = s.core / maxf(1.0, s.cmax)
	var col := S.MINT if frac > 0.5 else (S.SUN if frac > 0.25 else S.CORAL)
	var c := o + Vector2(54, 56)
	var r := 44.0
	var night:bool = s.ph == P.NIGHT
	# ribbon behind the medallion: name and state of the house
	var state_txt := "En pie" if frac > 0.66 else ("Tocada" if frac > 0.33 else "¡Se cae!")
	if house_shake > 0 and frac <= 0.66: state_txt = "¡La atacan!"
	var rib := Rect2(c + Vector2(r - 14, -36), Vector2(176, 40))
	draw_style_box(S.card(S.PAPER, 12, S.INK, 3, 4), rib)
	S.text(self, rib.position + Vector2(26, 18), "LA VERBENA", 13, S.INK_SOFT, "title", 600)
	S.text(self, rib.position + Vector2(26, 35), state_txt, 16, col.darkened(0.25) if col != S.SUN else Color("c98a1a"), "body", 900)
	S.text(self, rib.position + Vector2(rib.size.x - 52, 30), "%d%%" % roundi(frac * 100.0), 17, S.INK, "title", 600)
	# materials: a pallet of planks on a little tag under the ribbon
	var tag := Rect2(c + Vector2(r - 2, 10), Vector2(112, 40))
	draw_style_box(S.card(S.CARD, 14, S.INK, 3, 4), tag)
	if mat_tex: draw_texture_rect(mat_tex, Rect2(tag.position + Vector2(2, -14), Vector2(52, 52)), false)
	else: S.icon(self, "plank", tag.position + Vector2(28, 20), 30)
	S.text(self, tag.position + Vector2(56, 29), str(s.mat), 22, S.INK, "title", 600)
	# the medallion
	draw_circle(c + Vector2(0, 5), r + 6, Color(S.INK, 0.35))
	draw_circle(c, r + 6, S.INK)
	draw_circle(c, r + 3, S.CARD)
	var sky := Color("3b3470") if night else Color("bfe3ff")
	draw_circle(c, r - 5, sky)
	# a strip of grass at the bottom of the frame
	var ground := PackedVector2Array()
	for i in 17:
		var a := lerpf(0.2, PI - 0.2, i / 16.0)
		ground.append(c + Vector2(cos(a), sin(a)) * (r - 5))
	ground.append(c + Vector2(-(r - 5) * cos(0.2), (r - 5) * sin(0.2)))
	draw_colored_polygon(ground, Color("4f8a4c") if night else Color("8fd06a"))
	if night:
		for i in 5: draw_circle(c + Vector2(-30 + i * 14, -22 + (i % 2) * 8), 1.4, Color(1, 1, 1, 0.8))
	if house_tex:
		var hs := 108.0
		draw_texture_rect(house_tex, Rect2(c - Vector2(hs * 0.5, hs * 0.6), Vector2(hs, hs)), false)
	else:
		S.icon(self, "house", c, 52)
	S.ring(self, c, r + 1, frac, col, 6.0, Color(S.INK, 0.12))
	if house_shake > 0:
		draw_arc(c, r + 10, 0, TAU, 40, Color(S.CORAL, house_shake * 2.0), 4.0, true)
	# four paper lanterns hanging under it: the pieces of the verbena
	var pcs:Array = s.get("pc", [])
	if pcs.is_empty(): return
	var la := c + Vector2(-r - 4, r + 16)
	var lb := c + Vector2(r + 150, r + 16)
	var pts := PackedVector2Array()
	for i in 9: pts.append(la.lerp(lb, i / 8.0) + Vector2(0, 8.0 * sin(PI * i / 8.0)))
	draw_polyline(pts, Color(S.INK, 0.6), 2.0, true)
	for i in pcs.size():
		var lc := la.lerp(lb, (i + 0.5) / pcs.size()) + Vector2(0, 8.0 * sin(PI * (i + 0.5) / pcs.size()) + 15)
		var st:int = pcs[i][0]
		var tint := Color(Data.PIECES[i].color)
		if st == 4: tint.a = 1.0
		elif st == 2: tint.a = 1.0 if fmod(t, 0.8) < 0.4 else 0.2
		else: tint.a = 0.2
		draw_line(lc + Vector2(0, -21), lc + Vector2(0, -11), Color(S.INK, 0.6), 1.5, true)
		S.icon(self, "bulb", lc, 24, tint)

# ------------------------------------------------------------------ clock medallion
func draw_clock():
	var c := Vector2(size.x * 0.5, 64)
	var r := 40.0
	var night:bool = s.ph == P.NIGHT
	var fin:float = s.get("fin", -1.0)
	var rs:float = s.get("rs", 0.0)
	var frac := 0.0
	var ring_col := S.SUN
	match s.ph:
		P.PREP: frac = s.c / maxf(1.0, s.cl)
		P.DAWN:
			frac = s.c / maxf(1.0, s.cl)
			ring_col = S.PINK
		P.NIGHT:
			frac = float(s.rem) / maxf(1.0, s.tot)
			ring_col = S.LILAC
			if rs > 0:
				frac = rs / 15.0
				ring_col = S.MINT
			if fin > 0:
				frac = fin / Data.FINALE_TIME
				ring_col = S.PINK
		P.OVER: frac = 1.0
	draw_circle(c + Vector2(0, 5), r + 13, Color(S.INK, 0.3))
	draw_circle(c, r + 13, S.INK)
	S.ring(self, c, r + 6.5, frac, ring_col, 7.0, Color(1, 1, 1, 0.18))
	draw_circle(c, r, S.NIGHT if night else Color("bfe6ff"))
	if night and rs > 0:
		S.text(self, c + Vector2(-r, 14), str(ceili(rs)), 38, S.MINT, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, r * 2)
	elif fin > 0:
		S.text(self, c + Vector2(-r, 14), str(ceili(fin)), 34, S.PINK, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, r * 2)
	else:
		S.icon(self, "moon" if night else "sun", c + Vector2(0, -2), 56 + 4 * sin(t * 2.0))
	# ribbon with the day or night number
	var label := "NOCHE %d" % s.w if night else ("AMANECER" if s.ph == P.DAWN else ("DÍA %d" % s.w if s.ph == P.PREP else ("¡VICTORIA!" if s.get("vic", false) else "FIN")))
	if fin > 0: label = "¡LA GRAN VERBENA!"
	ribbon(c + Vector2(0, r + 20), label, S.LILAC if night else S.SUN, 20)
	# small bubbles beside the medallion
	if night and rs <= 0:
		bubble(c + Vector2(r + 46, -6), "sprout", str(s.rem))
		var asl:Array = s.get("as", [1, 1])
		if asl[1] > 1:
			for i in asl[1]:
				var dc := c + Vector2(-(asl[1] - 1) * 8.0 + i * 16.0, r + 44)
				draw_circle(dc, 5.5, S.INK)
				draw_circle(dc, 4.0, S.LILAC if i < asl[0] else Color(1, 1, 1, 0.3))
	elif s.ph == P.PREP:
		if s.c < 20.0: bubble(c + Vector2(r + 46, -6), "", "%d s" % ceili(s.c))
		var readies := 0
		var alive := 0
		for q in s.pl.values():
			if q.st == 0:
				alive += 1
				if q.ready: readies += 1
		if readies > 0: bubble(c + Vector2(-r - 46, -6), "bell", "%d/%d" % [readies, alive])
	# boss bar, or the night forecast when it is useful
	var y := c.y + r + 52
	if s.boss.size() > 0:
		var rect := Rect2(Vector2(c.x - 140, y), Vector2(280, 30))
		draw_style_box(S.card(S.CARD, 15, S.INK, 3), rect)
		S.icon(self, "crown", rect.position + Vector2(20, 15), 22)
		S.pill(self, Rect2(rect.position + Vector2(38, 9), Vector2(228, 12)), Color("c45ad8"), s.boss[1])
	elif s.ph == P.PREP and (forecast_t > 0 or s.c < 15.0):
		var ev:Dictionary = Data.NIGHT_EVENTS[s.ev]
		var fronts := []
		for f in s.fr: fronts.append(Map.FRONT_NAMES[f])
		var where:String = " y ".join(fronts) if fronts.size() <= 2 else ", ".join(fronts.slice(0, fronts.size() - 1)) + " y " + fronts[-1]
		tag(Vector2(c.x, y + 14), "Esta noche: %s · por el %s" % [ev.name.to_lower() if s.ev != 0 else "tranquila", where])

func ribbon(c:Vector2, label:String, col:Color, fs:int):
	var w := S.text_width(label, fs, "title", 600) + 44
	var h := fs + 14.0
	var x0 := c.x - w * 0.5
	var y0 := c.y - h * 0.5
	var notch := 10.0
	var body := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + w, y0), Vector2(x0 + w - notch, c.y), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h), Vector2(x0 + notch, c.y)])
	var shadow := PackedVector2Array()
	for v in body: shadow.append(v + Vector2(0, 4))
	draw_colored_polygon(shadow, Color(S.INK, 0.35))
	draw_colored_polygon(body, col)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, S.INK, 3.0, true)
	S.text(self, Vector2(x0, c.y + fs * 0.36), label, fs, S.INK, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, w)

func bubble(c:Vector2, icon_name:String, value:String):
	var w := S.text_width(value, 18, "title", 600) + (40.0 if icon_name != "" else 22.0)
	var rect := Rect2(c - Vector2(w * 0.5, 17), Vector2(w, 34))
	draw_style_box(S.card(S.CARD, 17, S.INK, 3), rect)
	var x := rect.position.x + 11
	if icon_name != "":
		S.icon(self, icon_name, Vector2(x + 9, c.y), 22)
		x += 22
	S.text(self, Vector2(x, c.y + 7), value, 18, S.INK, "title", 600)

func tag(c:Vector2, value:String):
	var w := S.text_width(value, 16) + 30
	var rect := Rect2(c - Vector2(w * 0.5, 15), Vector2(w, 30))
	draw_style_box(S.card(S.PAPER, 8, S.INK, 2, 3), rect)
	draw_circle(rect.position + Vector2(11, 15), 3.5, S.INK_SOFT)
	S.text(self, rect.position + Vector2(20, 21), value, 16, S.INK, "body", 800)

# ------------------------------------------------------------------ team
func draw_team():
	var ids:Array = s.pl.keys()
	ids.sort()
	var y := 190.0
	for id in ids:
		if id == me: continue
		var q:Dictionary = s.pl[id]
		var c := Vector2(48, y)
		var col := Color(Data.ROLES[q.role].color)
		var frac:float = q.hp / maxf(1.0, q.hpmax)
		var down:bool = q.st != 0
		S.ring(self, c, 23, frac, S.MINT if frac > 0.35 else S.CORAL, 5.0, Color(S.INK, 0.25))
		draw_circle(c, 19, S.INK)
		draw_circle(c, 16.5, col if not down else Color("8a7f8f"))
		S.text(self, c + Vector2(-20, 8), q.name.left(1).to_upper(), 22, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, 40, 4, S.INK)
		var name_col := Color(SLOT_COLORS[q.slot % 4]).darkened(0.35)
		S.text(self, c + Vector2(32, -1), q.name, 17, Color.WHITE, "body", 900, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, S.INK)
		if q.st == 1:
			var pulse := 0.6 + 0.4 * sin(t * 8.0)
			draw_arc(c, 27, 0, TAU, 32, Color(S.CORAL, pulse), 3.0, true)
			S.text(self, c + Vector2(32, 18), "¡Levántame! %d s" % ceili(q.bleed), 14, S.CORAL, "body", 900, HORIZONTAL_ALIGNMENT_LEFT, -1, 4, S.INK)
		elif q.st == 2:
			S.text(self, c + Vector2(32, 18), "vuelve al amanecer", 14, Color("d9cfc0"), "body", 800, HORIZONTAL_ALIGNMENT_LEFT, -1, 4, S.INK)
		y += 56

# ------------------------------------------------------------------ paper note: first day and jobs
func draw_notes():
	var lines:Array = local.get("notes", [])
	if lines.is_empty(): return
	var count := 0
	for id in s.pl: if id != me: count += 1
	var o := Vector2(24, 172 + count * 56)
	var w := 300.0
	var h := 40.0 + 26.0 * (lines.size() - 1)
	draw_set_transform(o + Vector2(w * 0.5, h * 0.5), -0.02, Vector2.ONE)
	var rect := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	draw_style_box(S.card(S.PAPER, 6, S.INK, 2, 4), rect)
	draw_rect(Rect2(Vector2(-28, -h * 0.5 - 8), Vector2(56, 16)), Color(S.PINK, 0.75))
	var y := -h * 0.5 + 26
	S.text(self, Vector2(-w * 0.5 + 14, y), lines[0], 18, S.INK, "title", 600)
	for i in range(1, lines.size()):
		y += 26
		var done:bool = lines[i].begins_with("✔")
		var body:String = lines[i].substr(2)
		var bx := Vector2(-w * 0.5 + 22, y - 6)
		draw_arc(bx, 7, 0, TAU, 16, S.INK, 2.0, true)
		if done: draw_polyline(PackedVector2Array([bx + Vector2(-4, 0), bx + Vector2(-1, 4), bx + Vector2(6, -6)]), S.MINT.darkened(0.2), 3.0, true)
		S.text(self, Vector2(-w * 0.5 + 36, y), body, 15, Color(S.INK, 0.45) if done else S.INK, "body", 800, HORIZONTAL_ALIGNMENT_LEFT, w - 48)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# ------------------------------------------------------------------ you
func draw_badge():
	var c := Vector2(78, size.y - 78)
	var col := Color(Data.ROLES[p.role].color)
	var frac:float = p.hp / maxf(1.0, p.hpmax)
	var low:bool = frac < 0.3 and p.st == 0
	draw_circle(c + Vector2(0, 5), 58, Color(S.INK, 0.3))
	draw_circle(c, 58, S.INK)
	S.ring(self, c, 51, frac, S.MINT if frac > 0.5 else (S.SUN if frac > 0.3 else S.CORAL), 10.0, Color(1, 1, 1, 0.15))
	draw_circle(c, 44, col.lightened(0.1))
	draw_circle(c + Vector2(-12, -14), 16, Color(1, 1, 1, 0.25))
	S.text(self, c + Vector2(-44, 16), p.name.left(1).to_upper(), 46, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, 88, 8, S.INK)
	if low: draw_arc(c, 62, 0, TAU, 40, Color(S.CORAL, 0.5 + 0.5 * sin(t * 9.0)), 4.0, true)
	# level star
	var lc := c + Vector2(40, -40)
	draw_circle(lc, 15, S.INK)
	draw_circle(lc, 12.5, S.SUN)
	S.text(self, lc + Vector2(-15, 7), str(p.lvl), 18, S.INK, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, 30)
	# ability
	var ac := c + Vector2(90, -24)
	var cd:float = Data.ROLES[p.role].cd * (1.0 - 0.06 * (p.lvl - 1))
	var ready:bool = p.ab <= 0
	draw_circle(ac, 25, S.INK)
	draw_circle(ac, 22, S.SKY if ready else Color("b8b0c4"))
	if not ready:
		var f:float = 1.0 - p.ab / cd
		var pts := PackedVector2Array([ac])
		for i in 33: pts.append(ac + Vector2.from_angle(-PI * 0.5 + TAU * f * i / 32.0) * 22.0)
		if f > 0.02: draw_colored_polygon(pts, Color(S.SKY, 0.65))
	else:
		draw_arc(ac, 28 + 2 * sin(t * 4.0), 0, TAU, 32, Color(S.SKY, 0.6), 2.5, true)
	S.text(self, ac + Vector2(-25, 9), key("ability", "Q"), 24, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, 50, 5, S.INK)
	# build: always reachable from here, with its key
	var bc := ac + Vector2(62, 0)
	var building:bool = local.get("build", -1) >= 0
	draw_circle(bc, 25, S.INK)
	draw_circle(bc, 22, S.SUN if building else S.CARD)
	if building: draw_arc(bc, 28 + 2 * sin(t * 4.0), 0, TAU, 32, Color(S.SUN, 0.7), 2.5, true)
	S.icon(self, "hammer", bc + Vector2(-1, -2), 30)
	S.keycap(self, bc + Vector2(18, 16), key("build", "B"), 22, S.SUN if not building else S.CARD)
	var lbl := "Salir (%s)" % key("build", "B") if building else "Construir"
	var lw := S.text_width(lbl, 15) + 20
	var lr := Rect2(bc + Vector2(34, -16), Vector2(lw, 28))
	draw_style_box(S.card(S.PAPER, 10, S.INK, 2, 3), lr)
	S.text(self, lr.position + Vector2(10, 20), lbl, 15, S.INK, "body", 900)
	# items
	var x := c.x + 70
	var y := c.y + 34
	for item in [["coin", p.coins], ["medkit", p.med], ["traca", p.tr]]:
		S.icon(self, item[0], Vector2(x + 12, y - 6), 26)
		S.text(self, Vector2(x + 28, y + 2), str(item[1]), 20, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, S.INK)
		x += 40 + S.text_width(str(item[1]), 20, "title", 600)
	if p.st == 1:
		var msg := "Has caído · %d s" % ceili(p.bleed)
		if p.med > 0: msg += " · %s: botiquín" % key("medkit", "H")
		tag(Vector2(size.x * 0.5, size.y * 0.5 + 90), msg)

func draw_weapon():
	var g:int = p.gun
	var w:Dictionary = Data.WEAPONS[g]
	var rect := Rect2(Vector2(size.x - 250, size.y - 104), Vector2(226, 80))
	draw_style_box(S.card(S.CARD, 22, S.INK, 3), rect)
	draw_circle(rect.position + Vector2(24, 24), 9, S.INK)
	draw_circle(rect.position + Vector2(24, 24), 7, Color(w.color))
	S.text(self, rect.position + Vector2(40, 30), w.name, 16, S.INK, "body", 900, HORIZONTAL_ALIGNMENT_LEFT, 176)
	var mag:int = p.mag.get(g, 0)
	var res:int = p.res.get(g, -1)
	var empty := mag == 0
	S.text(self, rect.position + Vector2(18, 70), str(mag), 34, S.CORAL if empty else S.INK, "title", 600)
	var mw := S.text_width(str(mag), 34, "title", 600)
	S.text(self, rect.position + Vector2(24 + mw, 70), "/ " + ("∞" if res < 0 else str(res)), 18, S.INK_SOFT, "title", 500)
	var lvl:int = p.guns.get(g, 1)
	for i in lvl: draw_circle(rect.position + Vector2(rect.size.x - 22 - i * 14, 58), 5, S.SUN)
	if p.rl > 0:
		S.pill(self, Rect2(rect.position + Vector2(110, 52), Vector2(70, 10)), S.SUN, 1.0 - p.rl / maxf(0.01, p.rlmax))
	elif empty:
		S.text(self, rect.position + Vector2(100, 64), key("reload", "R") + ": recargar", 14, S.CORAL, "body", 900)
	# weapon list only right after switching
	if slots_t > 0:
		var owned:Array = p.guns.keys()
		owned.sort()
		var x := rect.end.x - owned.size() * 40
		for i in owned:
			var kc := Vector2(x + 18, rect.position.y - 26)
			S.keycap(self, kc, str(i + 1), 32, Color(Data.WEAPONS[i].color) if i == g else S.CARD)
			x += 40

# ------------------------------------------------------------------ what you can do now
func draw_prompt():
	var head:Vector2 = local.get("head", Vector2(size.x * 0.5, size.y * 0.55))
	var y := head.y
	if p.notice != "":
		var w := S.text_width(p.notice, 17) + 28
		var rect := Rect2(Vector2(head.x - w * 0.5, y - 34), Vector2(w, 32))
		draw_style_box(S.card(S.SUN, 16, S.INK, 2, 3), rect)
		S.text(self, rect.position + Vector2(14, 22), p.notice, 17, S.INK, "body", 900)
		y -= 42
	var pr:String = p.prompt if p.st == 0 else ""
	if pr == "" or local.get("build", -1) >= 0: return
	var k := ""
	var body := pr
	var rx := RegEx.create_from_string("^(?:Mantén )?([A-ZÑ0-9]{1,6}): (.*)$")
	var m := rx.search(pr)
	if m:
		k = m.get_string(1)
		body = m.get_string(2)
		body = body.left(1).to_upper() + body.substr(1)
	var tw := S.text_width(body, 17) + (54.0 if k != "" else 26.0)
	var rect := Rect2(Vector2(head.x - tw * 0.5, y - 40), Vector2(tw, 38))
	draw_style_box(S.card(S.CARD, 19, S.INK, 3), rect)
	draw_colored_polygon(PackedVector2Array([Vector2(head.x - 7, rect.end.y - 1), Vector2(head.x + 7, rect.end.y - 1), Vector2(head.x, rect.end.y + 8)]), S.INK)
	var x := rect.position.x + 13
	if k != "":
		var kc := Vector2(x + 12, rect.get_center().y)
		S.keycap(self, kc, k, 26)
		if p.hold != "" and p.hm > 0: S.ring(self, kc, 18, p.ht / p.hm, S.MINT, 4.0, Color(0, 0, 0, 0))
		x += 32
	S.text(self, Vector2(x, rect.get_center().y + 6), body, 17, S.INK, "body", 800)

func draw_world_marks():
	# attacked sides of the house, pinned in the world (or at the screen edge)
	var marks:Array = local.get("sectors", [])
	var br:Array = s.get("br", [])
	for i in mini(marks.size(), br.size() / 3):
		var hit:bool = br[i * 3] > 0 or br[i * 3 + 2] > 0
		var breach:bool = br[i * 3 + 1] > 0
		if not hit and not breach: continue
		var pos:Vector2 = marks[i]
		var on := Rect2(Vector2(40, 40), size - Vector2(80, 80)).has_point(pos)
		pos = pos.clamp(Vector2(40, 40), size - Vector2(40, 40))
		var pulse := 0.5 + 0.5 * sin(t * 10.0)
		var col := S.CORAL if breach or br[i * 3 + 2] > 0 else S.SUN
		draw_circle(pos, 26 + 6 * pulse, Color(col, 0.25))
		draw_circle(pos, 20, S.INK)
		draw_circle(pos, 17, col)
		S.text(self, pos + Vector2(-20, 10), "!", 28, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_CENTER, 40, 4, S.INK)
		if not on:
			var dir := (pos - size * 0.5).normalized()
			draw_colored_polygon(PackedVector2Array([pos + dir * 34, pos + dir * 22 + Vector2(-dir.y, dir.x) * 9, pos + dir * 22 - Vector2(-dir.y, dir.x) * 9]), S.INK)
	# pins: team signals, neighbours, supplies, pieces and jobs
	for m in indicators:
		var sp:Vector2 = m[0]
		var col:Color = m[1]
		var label:String = m[2]
		var on:bool = m[3]
		if on:
			pin(sp, col, label, false)
		else:
			var center := size * 0.5
			var dir := (sp - center).normalized()
			var edge := center + dir * minf(absf((size.x * 0.5 - 56) / maxf(0.001, absf(dir.x))), absf((size.y * 0.5 - 56) / maxf(0.001, absf(dir.y))))
			pin(edge, col, label, true, dir)

func pin(at:Vector2, col:Color, label:String, edge:bool, dir:Vector2 = Vector2.ZERO):
	if edge:
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([at + dir * 26, at + dir * 12 + perp * 10, at + dir * 12 - perp * 10]), S.INK)
	var top := at + Vector2(0, -22) if not edge else at
	draw_circle(top, 13, S.INK)
	draw_circle(top, 10.5, col)
	if not edge: draw_colored_polygon(PackedVector2Array([top + Vector2(-8, 7), top + Vector2(8, 7), at]), S.INK)
	if label == "": return
	var w := S.text_width(label, 14) + 18
	var rect := Rect2(top + Vector2(-w * 0.5, 16), Vector2(w, 24))
	draw_style_box(S.card(S.CARD, 12, S.INK, 2, 2), rect)
	S.text(self, rect.position + Vector2(9, 17), label, 14, S.INK, "body", 800)

# ------------------------------------------------------------------ messages
func draw_toasts():
	var y := size.y - 170.0
	for i in range(toasts.size() - 1, -1, -1):
		var item:Array = toasts[i]
		var a := clampf(item[2], 0.0, 1.0)
		var msg:String = item[0]
		var w := minf(S.text_width(msg, 16) + 34, 560.0)
		var rect := Rect2(Vector2(24, y - 34), Vector2(w, 32))
		draw_style_box(S.card(Color(S.CARD, a), 16, Color(S.INK, a), 2, 3), rect)
		draw_circle(rect.position + Vector2(15, 16), 5, Color(item[1], a))
		S.text(self, rect.position + Vector2(27, 22), msg, 16, Color(S.INK, a), "body", 800, HORIZONTAL_ALIGNMENT_LEFT, 520)
		y -= 40

func draw_announce():
	if ann.is_empty(): return
	var k:float = ann.t
	var life:float = ann.life
	var a := clampf(minf(k * 5.0, (life - k) * 2.0), 0.0, 1.0)
	var pop := 1.0 + 0.25 * maxf(0.0, 1.0 - k * 6.0)
	var c := Vector2(size.x * 0.5, size.y * 0.235)
	draw_set_transform(c, sin(k * 2.0) * 0.01, Vector2(pop, pop))
	var fs := 40
	var w := S.text_width(ann.title, fs, "title", 600) + 90
	var h := 64.0
	var col:Color = ann.col
	for side in [-1, 1]:
		var tail := PackedVector2Array([Vector2(side * w * 0.5, -h * 0.3), Vector2(side * (w * 0.5 + 46), -h * 0.3), Vector2(side * (w * 0.5 + 30), h * 0.15), Vector2(side * (w * 0.5 + 46), h * 0.6), Vector2(side * w * 0.5, h * 0.6)])
		draw_colored_polygon(tail, Color(col.darkened(0.25), a))
	var body := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	draw_style_box(S.card(Color(col, a), 14, Color(S.INK, a), 4, 6), body)
	S.text(self, Vector2(-w * 0.5, 16), ann.title, fs, Color(1, 1, 1, a), "title", 600, HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(S.INK, a))
	S.bunting(self, Vector2(-w * 0.5 + 12, -h * 0.5 - 2), Vector2(w * 0.5 - 12, -h * 0.5 - 2), 10, 8, 14)
	if ann.sub != "":
		var sw := minf(S.text_width(ann.sub, 18) + 36, 760.0)
		var sr := Rect2(Vector2(-sw * 0.5, h * 0.5 + 12), Vector2(sw, 34))
		draw_style_box(S.card(Color(S.PAPER, a), 10, Color(S.INK, a), 2, 3), sr)
		S.text(self, Vector2(-sw * 0.5, h * 0.5 + 35), ann.sub, 18, Color(S.INK, a), "body", 800, HORIZONTAL_ALIGNMENT_CENTER, sw)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func draw_report():
	if report_t <= 0 or report_lines.is_empty(): return
	var a := clampf(report_t, 0.0, 1.0)
	var w := 420.0
	var h := 56.0 + 26.0 * report_lines.size()
	var rect := Rect2(Vector2(size.x * 0.5 - w * 0.5, size.y * 0.3 + 90), Vector2(w, h))
	draw_style_box(S.card(Color(S.PAPER, a), 18, Color(S.INK, a), 3, 5), rect)
	S.icon(self, "sun", rect.position + Vector2(32, 30), 40)
	S.text(self, rect.position + Vector2(58, 38), "Amanecer", 24, Color(S.INK, a), "title", 600)
	for i in report_lines.size():
		S.text(self, rect.position + Vector2(24, 70 + i * 26), "· " + str(report_lines[i]), 16, Color(S.INK, a), "body", 800, HORIZONTAL_ALIGNMENT_LEFT, w - 40)
