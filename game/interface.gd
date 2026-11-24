extends CanvasLayer
## Interface: menus, HUD, shop, build bar, minimap, pause and end screens.

signal launch(mode:String, role:int, address:String, name:String)
signal settings_changed(settings:Dictionary)
signal leave
signal resume
signal action(name:String, args:Array)
signal build_pick(kind:int)

const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const P := Data.Phase

const NAVY := Color("1d2b40")
const CREAM := Color("fff4dc")
const YELLOW := Color("ffd166")
const CORAL := Color("ff6b6b")
const MINT := Color("06d6a0")
const SKY := Color("4cc9f0")
const PINK := Color("f78fb3")
const SLOT_COLORS = ["ffd166", "4cc9f0", "f78fb3", "06d6a0"]

var theme_res := Theme.new()
var root := Control.new()
var menu := Control.new()
var menu_panel := PanelContainer.new()
var role_cards := []
var role := 0
var name_edit := LineEdit.new()
var address := LineEdit.new()
var status := Label.new()
var settings_panel := PanelContainer.new()
var help_panel := PanelContainer.new()
var settings := {"quality":2, "fullscreen":false, "volume":0.8, "music":0.6, "shake":true, "numbers":true}

var hud := Control.new()
var banner := Label.new()
var banner_sub := Label.new()
var clock_bar := ProgressBar.new()
var boss_box := VBoxContainer.new()
var boss_bar := ProgressBar.new()
var base_bar := ProgressBar.new()
var base_label := Label.new()
var res_label := Label.new()
var team_box := VBoxContainer.new()
var me_name := Label.new()
var hp_bar := ProgressBar.new()
var xp_bar := ProgressBar.new()
var ab_bar := ProgressBar.new()
var ab_label := Label.new()
var items_label := Label.new()
var gun_label := Label.new()
var ammo_label := Label.new()
var reload_bar := ProgressBar.new()
var slots_box := HBoxContainer.new()
var prompt := Label.new()
var hold_bar := ProgressBar.new()
var notice := Label.new()
var feed := VBoxContainer.new()
var announce := Label.new()
var announce_sub := Label.new()
var announce_t := 0.0
var report_box := PanelContainer.new()
var report_label := Label.new()
var report_t := 0.0
var build_bar := PanelContainer.new()
var build_cards := []
var build_hint := Label.new()
var shop := PanelContainer.new()
var shop_list := VBoxContainer.new()
var shop_tab := 0
var shop_coins := Label.new()
var map_panel := PanelContainer.new()
var map_info := Label.new()
var minimap:Control
var bigmap:Control
var pause := PanelContainer.new()
var over := PanelContainer.new()
var over_title := Label.new()
var over_text := Label.new()
var overlay:Control
var help_hint := Label.new()
var prompt_box:VBoxContainer
var ready_label := Label.new()
var markers := []
var last_state := {}
var my_id := 0
var build_kind := -1
var feed_items := []
var mm_data := {}

func _ready():
	layer = 5
	build_theme()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme_res
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_menu()
	build_hud()
	build_settings()
	build_help()
	build_pause()
	build_over()
	hud.hide()

# ================================================================== theme
func box(c:Color, radius:int = 14, margin:int = 12, border:Color = Color(0, 0, 0, 0), bw:int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)
	return s

func build_theme():
	theme_res.default_font_size = 18
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Nunito", "Fredoka", "Baloo 2", "Varela Round", "Quicksand", "Comfortaa", "Ubuntu", "Noto Sans", "sans-serif"])
	font.font_weight = 700
	theme_res.default_font = font
	theme_res.set_stylebox("panel", "PanelContainer", box(Color(NAVY, 0.92), 18, 16))
	theme_res.set_stylebox("normal", "Button", box(Color("2e4566"), 12, 12, Color("4a6a94"), 2))
	theme_res.set_stylebox("hover", "Button", box(Color("3d5a85"), 12, 12, YELLOW, 2))
	theme_res.set_stylebox("pressed", "Button", box(Color("ffd166"), 12, 12, Color("fff4dc"), 2))
	theme_res.set_stylebox("disabled", "Button", box(Color("2a3344"), 12, 12, Color("3a4458"), 2))
	theme_res.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme_res.set_color("font_color", "Button", CREAM)
	theme_res.set_color("font_hover_color", "Button", Color.WHITE)
	theme_res.set_color("font_pressed_color", "Button", NAVY)
	theme_res.set_color("font_disabled_color", "Button", Color("7f8aa0"))
	theme_res.set_stylebox("normal", "LineEdit", box(Color("14202f"), 10, 10, Color("4a6a94"), 2))
	theme_res.set_stylebox("focus", "LineEdit", box(Color("14202f"), 10, 10, YELLOW, 2))
	theme_res.set_color("font_color", "LineEdit", CREAM)
	theme_res.set_color("font_placeholder_color", "LineEdit", Color("7f8aa0"))
	theme_res.set_color("font_color", "Label", CREAM)
	theme_res.set_color("font_outline_color", "Label", Color(0.08, 0.06, 0.12, 1))
	theme_res.set_constant("outline_size", "Label", 0)
	theme_res.set_stylebox("background", "ProgressBar", box(Color(0.05, 0.06, 0.1, 0.75), 8, 0))
	theme_res.set_stylebox("fill", "ProgressBar", box(MINT, 8, 0))
	theme_res.set_constant("outline_size", "ProgressBar", 0)
	theme_res.set_stylebox("normal", "OptionButton", box(Color("2e4566"), 10, 10, Color("4a6a94"), 2))
	theme_res.set_stylebox("hover", "OptionButton", box(Color("3d5a85"), 10, 10, YELLOW, 2))
	theme_res.set_stylebox("pressed", "OptionButton", box(Color("3d5a85"), 10, 10, YELLOW, 2))
	theme_res.set_color("font_color", "OptionButton", CREAM)
	theme_res.set_color("font_color", "CheckButton", CREAM)
	theme_res.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme_res.set_stylebox("slider", "HSlider", box(Color("14202f"), 6, 0))
	theme_res.set_stylebox("grabber_area", "HSlider", box(YELLOW, 6, 0))
	theme_res.set_stylebox("grabber_area_highlight", "HSlider", box(YELLOW, 6, 0))
	theme_res.set_stylebox("panel", "PopupMenu", box(NAVY, 10, 8))
	theme_res.set_color("font_color", "PopupMenu", CREAM)

func label(parent:Control, text:String, size:int = 18, color:Color = CREAM, outline:int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func button(parent:Control, text:String, cb:Callable, height:int = 44) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = height
	b.pressed.connect(cb)
	b.pressed.connect(func(): action.emit("ui_click", []))
	parent.add_child(b)
	return b

func bar(parent:Control, fill:Color, h:int = 14) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_stylebox_override("fill", box(fill, 8, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

func vbox(parent:Control, sep:int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v

func hbox(parent:Control, sep:int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h

func panel(parent:Control, c:Color = Color(NAVY, 0.88), radius:int = 16, margin:int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(c, radius, margin))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func anchor(c:Control, ax:float, ay:float, off:Vector2):
	## Pin a control to a point of the screen; it grows away from the nearest edges.
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = off.x
	c.offset_right = off.x
	c.offset_top = off.y
	c.offset_bottom = off.y
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if ax == 0.5 else (Control.GROW_DIRECTION_BEGIN if ax == 1.0 else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BOTH if ay == 0.5 else (Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_END)

# ================================================================== menu
func build_menu():
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var deco := Control.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func(): draw_bunting(deco))
	menu.add_child(deco)
	var title_box := vbox(menu, 0)
	title_box.position = Vector2(64, 44)
	label(title_box, "COOPERATIVO · 1–4 VECINOS", 18, YELLOW, 6)
	var t := label(title_box, "La última verbena", 68, CREAM, 18)
	t.add_theme_color_override("font_outline_color", Color("2a1f3d"))
	label(title_box, "Las guirnaldas siguen encendidas. Al anochecer llegan los brotados.", 20, Color("e8ecff"), 8)
	menu.add_child(menu_panel)
	menu_panel.add_theme_stylebox_override("panel", box(Color(NAVY, 0.93), 22, 22))
	menu_panel.position = Vector2(64, 200)
	menu_panel.custom_minimum_size = Vector2(600, 0)
	var col := vbox(menu_panel, 10)
	label(col, "¿Cómo te llamas?", 16, YELLOW)
	col.add_child(name_edit)
	name_edit.placeholder_text = "Tu nombre en el barrio"
	name_edit.max_length = 14
	name_edit.custom_minimum_size.y = 40
	label(col, "Elige tu oficio", 16, YELLOW)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in 4:
		var card := Button.new()
		card.custom_minimum_size = Vector2(275, 112)
		card.toggle_mode = true
		card.button_pressed = i == 0
		var rc := Color(Data.ROLES[i].color)
		card.add_theme_stylebox_override("normal", box(Color("24364f"), 14, 12, Color(rc, 0.4), 2))
		card.add_theme_stylebox_override("hover", box(Color("2c4260"), 14, 12, rc, 2))
		card.add_theme_stylebox_override("pressed", box(Color(rc.darkened(0.55), 0.95), 14, 12, rc, 4))
		card.add_theme_stylebox_override("hover_pressed", box(Color(rc.darkened(0.5), 0.95), 14, 12, rc, 4))
		card.pressed.connect(pick_role.bind(i))
		grid.add_child(card)
		var inner := vbox(card, 2)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 14
		inner.offset_top = 8
		inner.offset_right = -10
		label(inner, Data.ROLES[i].name, 22, rc.lightened(0.2), 4)
		label(inner, "Q · " + Data.ROLES[i].ability, 14, YELLOW)
		var d := label(inner, Data.ROLES[i].desc, 13, Color("cfd8ee"))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 245
		role_cards.append(card)
	var row := hbox(col, 10)
	var solo := button(row, "▶  Jugar en solitario", func(): emit_launch("solo"), 52)
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.add_theme_font_size_override("font_size", 22)
	var host := button(row, "Crear partida en red", func(): emit_launch("host"), 52)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row2 := hbox(col, 10)
	row2.add_child(address)
	address.placeholder_text = "IP del anfitrión (p. ej. 192.168.1.20)"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.custom_minimum_size.y = 44
	button(row2, "Unirse", func(): emit_launch("join"))
	var row3 := hbox(col, 10)
	for item in [["Ajustes", func(): toggle_panel(settings_panel)], ["Cómo se juega", func(): toggle_panel(help_panel)], ["Salir", func(): get_tree().quit()]]:
		var b := button(row3, item[0], item[1], 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(status)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", YELLOW)
	status.custom_minimum_size.x = 540
	var tip := label(menu, "Ratón y teclado · F1 ayuda en partida", 15, Color(1, 1, 1, 0.7), 6)
	anchor(tip, 0.0, 1.0, Vector2(64, -16))

func draw_bunting(c:Control):
	var w := c.size.x
	var colors := [CORAL, YELLOW, MINT, SKY, PINK, Color("c59dff")]
	for row in 2:
		var y0 := 8.0 + row * 26
		var sag := 22.0 + row * 8
		var count := int(w / 46)
		var pts := PackedVector2Array()
		for i in count + 1:
			var x := float(i) / count * w
			pts.append(Vector2(x, y0 + sag * sin(PI * float(i) / count)))
		c.draw_polyline(pts, Color(0.2, 0.15, 0.25, 0.7), 2.0)
		for i in count:
			var a := pts[i]
			var b := pts[i + 1]
			var m := (a + b) * 0.5
			c.draw_colored_polygon(PackedVector2Array([a + (b - a) * 0.15, a + (b - a) * 0.85, m + Vector2(0, 24)]), colors[(i + row * 3) % colors.size()])

func pick_role(i:int):
	role = i
	for j in role_cards.size(): role_cards[j].button_pressed = j == i

func emit_launch(mode:String):
	launch.emit(mode, role, address.text.strip_edges(), name_edit.text.strip_edges())

func toggle_panel(p:Control):
	var show := not p.visible
	for q in [settings_panel, help_panel]: q.visible = false
	p.visible = show

# ================================================================== settings & help
func build_settings():
	root.add_child(settings_panel)
	settings_panel.visible = false
	settings_panel.add_theme_stylebox_override("panel", box(Color(NAVY, 0.96), 20, 22))
	settings_panel.custom_minimum_size = Vector2(520, 0)
	anchor(settings_panel, 0.5, 0.5, Vector2.ZERO)
	var col := vbox(settings_panel, 12)
	label(col, "Ajustes", 30, YELLOW, 6)
	var q := OptionButton.new()
	for n in ["Baja (portátiles)", "Media", "Alta", "Ultra (niebla volumétrica y desenfoque)"]: q.add_item(n)
	q.selected = settings.quality
	q.item_selected.connect(func(i): set_setting("quality", i))
	row_with(col, "Calidad gráfica", q)
	var fs := CheckButton.new()
	fs.toggled.connect(func(v): set_setting("fullscreen", v))
	row_with(col, "Pantalla completa", fs)
	for item in [["volume", "Volumen general"], ["music", "Música"]]:
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 1
		s.step = 0.05
		s.value = settings[item[0]]
		s.custom_minimum_size = Vector2(220, 24)
		s.value_changed.connect(func(v): set_setting(item[0], v))
		row_with(col, item[1], s)
	for item in [["shake", "Sacudidas de cámara"], ["numbers", "Números de daño"]]:
		var c := CheckButton.new()
		c.button_pressed = settings[item[0]]
		c.toggled.connect(func(v): set_setting(item[0], v))
		row_with(col, item[1], c)
	button(col, "Cerrar", func(): settings_panel.hide())

func row_with(parent:Control, text:String, ctl:Control):
	var r := hbox(parent, 12)
	var l := label(r, text, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ctl)

func set_setting(key:String, value):
	settings[key] = value
	settings_changed.emit(settings)

func build_help():
	root.add_child(help_panel)
	help_panel.visible = false
	help_panel.add_theme_stylebox_override("panel", box(Color(NAVY, 0.96), 20, 22))
	anchor(help_panel, 0.5, 0.5, Vector2(0, 0))
	help_panel.custom_minimum_size = Vector2(860, 0)
	var col := vbox(help_panel, 10)
	label(col, "Cómo se juega", 30, YELLOW, 6)
	var text := label(col, "", 16)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 810
	text.text = """De día rebusca materiales y fichas, rescata vecinos, conquista propiedades y prepara defensas alrededor de la casa de la verbena. De noche los brotados atacan por los frentes anunciados: aguanta hasta que no quede ninguno. Si cae la casa o todo el equipo, se acaba la fiesta.

WASD moverse · Ratón apuntar · Clic izquierdo disparar · Clic derecho o V sartenazo · Espacio voltereta · Mayús correr
R recargar · 1–7 o rueda cambiar de arma · E (mantener) rebuscar, reparar, reanimar o liberar · Q habilidad del oficio
G lanzar traca · H botiquín · B modo construcción (1–8 elige, clic coloca, F mejora, X desmonta) · T tienda en la casa
C conquistar propiedad · Tab mapa del barrio · Clic central marcar un punto al equipo · N listo para la noche · Esc pausa

Materiales: compartidos por todo el equipo. Fichas: personales, para armas, mejoras y objetos.
Cada propiedad conquistada aporta una ventaja al amanecer, pero los brotados también irán a por su estandarte.
Barricada y alambrada se saltan; bobina, torreta y foco necesitan corriente durante un apagón (generador o Gasolinera)."""
	button(col, "Cerrar", func(): help_panel.hide())

# ================================================================== HUD
func build_hud():
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	hud.add_child(overlay)
	# top centre banner
	var top := vbox(hud, 4)
	anchor(top, 0.5, 0.0, Vector2(0, 14))
	top.custom_minimum_size = Vector2(520, 0)
	var bp := panel(top, Color(NAVY, 0.88), 16, 12)
	var bc := vbox(bp, 4)
	bc.add_child(banner)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_color_override("font_color", YELLOW)
	bc.add_child(clock_bar)
	clock_bar.show_percentage = false
	clock_bar.custom_minimum_size.y = 10
	clock_bar.add_theme_stylebox_override("fill", box(YELLOW, 6, 0))
	bc.add_child(banner_sub)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_font_size_override("font_size", 15)
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_sub.add_theme_color_override("font_color", Color("cfd8ee"))
	top.add_child(boss_box)
	var bl := label(boss_box, "GIGANTÓN", 16, Color("ff9ad5"), 6)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_bar)
	boss_bar.show_percentage = false
	boss_bar.custom_minimum_size.y = 16
	boss_bar.add_theme_stylebox_override("fill", box(Color("c45ad8"), 8, 0))
	boss_box.visible = false
	top.add_child(ready_label)
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_label.add_theme_font_size_override("font_size", 15)
	ready_label.add_theme_constant_override("outline_size", 6)
	# top left: the house and shared stock
	var tl := panel(hud, Color(NAVY, 0.88), 16, 12)
	tl.position = Vector2(16, 14)
	tl.custom_minimum_size = Vector2(300, 0)
	var tlc := vbox(tl, 6)
	tlc.add_child(base_label)
	base_label.add_theme_font_size_override("font_size", 17)
	tlc.add_child(base_bar)
	base_bar.show_percentage = false
	base_bar.custom_minimum_size.y = 16
	base_bar.add_theme_stylebox_override("fill", box(Color("ffb35c"), 8, 0))
	tlc.add_child(res_label)
	res_label.add_theme_font_size_override("font_size", 16)
	# team list
	hud.add_child(team_box)
	team_box.position = Vector2(16, 150)
	team_box.add_theme_constant_override("separation", 6)
	team_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# message feed
	hud.add_child(feed)
	anchor(feed, 0.0, 1.0, Vector2(18, -205))
	feed.custom_minimum_size = Vector2(520, 120)
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# bottom left: me
	var me := panel(hud, Color(NAVY, 0.9), 16, 14)
	anchor(me, 0.0, 1.0, Vector2(16, -16))
	me.custom_minimum_size = Vector2(330, 0)
	var mc := vbox(me, 5)
	mc.add_child(me_name)
	me_name.add_theme_font_size_override("font_size", 19)
	hp_bar.show_percentage = false
	mc.add_child(hp_bar)
	hp_bar.custom_minimum_size.y = 18
	hp_bar.add_theme_stylebox_override("fill", box(MINT, 8, 0))
	mc.add_child(xp_bar)
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size.y = 6
	xp_bar.add_theme_stylebox_override("fill", box(YELLOW, 4, 0))
	var abr := hbox(mc, 8)
	abr.add_child(ab_label)
	ab_label.add_theme_font_size_override("font_size", 15)
	ab_label.custom_minimum_size.x = 170
	abr.add_child(ab_bar)
	ab_bar.show_percentage = false
	ab_bar.custom_minimum_size = Vector2(120, 12)
	ab_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ab_bar.add_theme_stylebox_override("fill", box(SKY, 6, 0))
	mc.add_child(items_label)
	items_label.add_theme_font_size_override("font_size", 16)
	# bottom right: weapon
	var wp := panel(hud, Color(NAVY, 0.9), 16, 14)
	anchor(wp, 1.0, 1.0, Vector2(-16, -16))
	wp.custom_minimum_size = Vector2(360, 0)
	var wc := vbox(wp, 4)
	var wr := hbox(wc, 8)
	wr.add_child(gun_label)
	gun_label.add_theme_font_size_override("font_size", 19)
	gun_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wr.add_child(ammo_label)
	ammo_label.add_theme_font_size_override("font_size", 26)
	ammo_label.add_theme_color_override("font_color", YELLOW)
	wc.add_child(reload_bar)
	reload_bar.show_percentage = false
	reload_bar.custom_minimum_size.y = 6
	reload_bar.add_theme_stylebox_override("fill", box(YELLOW, 4, 0))
	wc.add_child(slots_box)
	slots_box.add_theme_constant_override("separation", 4)
	for i in Data.WEAPONS.size():
		var s := Label.new()
		s.custom_minimum_size = Vector2(44, 30)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		s.add_theme_font_size_override("font_size", 14)
		slots_box.add_child(s)
	# prompt
	var pc := vbox(hud, 4)
	prompt_box = pc
	anchor(pc, 0.5, 1.0, Vector2(0, -24))
	pc.custom_minimum_size = Vector2(600, 0)
	pc.add_child(notice)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_color_override("font_color", YELLOW)
	notice.add_theme_constant_override("outline_size", 8)
	notice.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.95))
	pc.add_child(prompt)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 19)
	prompt.add_theme_constant_override("outline_size", 8)
	prompt.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.95))
	pc.add_child(hold_bar)
	hold_bar.show_percentage = false
	hold_bar.custom_minimum_size = Vector2(260, 10)
	hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hold_bar.add_theme_stylebox_override("fill", box(MINT, 6, 0))
	# big announcement
	var ac := vbox(hud, 0)
	anchor(ac, 0.5, 0.5, Vector2(0, 0))
	ac.custom_minimum_size = Vector2(900, 0)
	ac.add_child(announce)
	announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce.add_theme_font_size_override("font_size", 64)
	announce.add_theme_constant_override("outline_size", 18)
	announce.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.16, 1))
	ac.add_child(announce_sub)
	announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_sub.add_theme_font_size_override("font_size", 24)
	announce_sub.add_theme_constant_override("outline_size", 10)
	announce_sub.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.16, 1))
	announce_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# dawn report
	hud.add_child(report_box)
	report_box.add_theme_stylebox_override("panel", box(Color(Color("3d2f5a"), 0.92), 16, 16))
	anchor(report_box, 0.5, 0.0, Vector2(0, 170))
	report_box.custom_minimum_size = Vector2(440, 0)
	report_box.add_child(report_label)
	report_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_box.visible = false
	report_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# minimap
	var mmp := panel(hud, Color(NAVY, 0.88), 16, 8)
	anchor(mmp, 1.0, 0.0, Vector2(-16, 14))
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(250, 222)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(func(): draw_map(minimap, false))
	mmp.add_child(minimap)
	hud.add_child(help_hint)
	anchor(help_hint, 1.0, 0.0, Vector2(-20, 262))
	help_hint.text = "F1 ayuda · Tab mapa · Esc pausa"
	help_hint.add_theme_font_size_override("font_size", 14)
	help_hint.add_theme_constant_override("outline_size", 6)
	help_hint.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.95))
	build_buildbar()
	build_shop()
	build_map()

func build_buildbar():
	hud.add_child(build_bar)
	build_bar.add_theme_stylebox_override("panel", box(Color(NAVY, 0.93), 18, 12))
	anchor(build_bar, 0.5, 1.0, Vector2(0, -192))
	build_bar.custom_minimum_size = Vector2(940, 0)
	var col := vbox(build_bar, 8)
	var row := hbox(col, 8)
	for i in Data.STRUCTURES.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(108, 70)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): build_pick.emit(i))
		row.add_child(b)
		var inner := vbox(b, 0)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_top = 5
		inner.offset_left = 6
		var k := label(inner, "%d · %s" % [i + 1, Data.STRUCTURES[i].name], 14, CREAM)
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.custom_minimum_size.x = 96
		var cost := label(inner, "", 14, YELLOW)
		build_cards.append([b, cost])
	col.add_child(build_hint)
	build_hint.add_theme_font_size_override("font_size", 15)
	build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_bar.visible = false

func build_shop():
	hud.add_child(shop)
	shop.add_theme_stylebox_override("panel", box(Color(NAVY, 0.96), 20, 18))
	anchor(shop, 0.5, 0.5, Vector2(0, 0))
	shop.custom_minimum_size = Vector2(760, 600)
	var col := vbox(shop, 10)
	var head := hbox(col, 10)
	var t := label(head, "Tienda de la verbena", 30, YELLOW, 6)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(shop_coins)
	shop_coins.add_theme_font_size_override("font_size", 20)
	var tabs := hbox(col, 8)
	for i in 3:
		var b := button(tabs, ["Armas", "Equipo", "Barrio"][i], func():
			shop_tab = i
			refresh_shop(), 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	scroll.add_child(shop_list)
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 8)
	var foot := label(col, "T o Esc para cerrar · Las fichas son tuyas; los materiales son del equipo", 14, Color("aab4cc"))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop.visible = false

func shop_row(title:String, desc:String, btn_text:String, enabled:bool, cb:Callable, accent:Color = YELLOW):
	var p := panel(shop_list, Color("24364f"), 12, 12)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var r := hbox(p, 12)
	var info := vbox(r, 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(info, title, 18, accent)
	var d := label(info, desc, 14, Color("cfd8ee"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 470
	var b := button(r, btn_text, cb, 40)
	b.custom_minimum_size.x = 170
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func refresh_shop():
	for c in shop_list.get_children(): c.queue_free()
	var s := last_state
	if s.is_empty() or not s.pl.has(my_id): return
	var p:Dictionary = s.pl[my_id]
	shop_coins.text = "Fichas: %d · Materiales: %d" % [p.coins, s.mat]
	match shop_tab:
		0:
			for g in Data.WEAPONS.size():
				var w:Dictionary = Data.WEAPONS[g]
				var owned:bool = p.guns.has(g)
				var locked:bool = w.req >= 0 and not s.si[w.req][0]
				var stats := "Daño %d · Cadencia %.1f/s · Cargador %d · Alcance %d m" % [w.dmg * w.pellets, 1.0 / w.rate, w.mag, w.range]
				if not owned:
					var why := "" if not locked else "  (necesita %s)" % Data.SITES[w.req].name
					shop_row(w.name + why, w.desc + "\n" + stats, "Comprar · %d" % w.price, not locked and p.coins >= w.price, func(): action.emit("buy_gun", [g]), Color(w.color))
				else:
					var lvl:int = p.guns[g]
					if lvl < 3:
						var cost:int = w.up[lvl - 1]
						shop_row("%s · nivel %d" % [w.name, lvl], "Mejora a nivel %d: +25%% de daño.\n%s" % [lvl + 1, stats], "Mejorar · %d" % cost, p.coins >= cost, func(): action.emit("up_gun", [g]), Color(w.color))
					else:
						shop_row("%s · nivel máximo" % w.name, stats, "Equipar", true, func(): action.emit("switch", [g]), Color(w.color))
					if w.reserve > 0:
						shop_row("Munición: " + w.name, "Rellena la reserva (%d)." % p.res[g], "Rellenar · %d" % w.ammo_price, p.coins >= w.ammo_price, func(): action.emit("ammo", [g]), Color("aab4cc"))
		1:
			shop_row("Botiquín (%d/3)" % p.med, "H para curarte 55 de salud. Si caes, te levanta.", "Comprar · %d" % Data.MEDKIT.price, p.coins >= Data.MEDKIT.price and p.med < 3, func(): action.emit("buy_medkit", []), MINT)
			shop_row("Traca (%d/6)" % p.tr, "G para lanzarla: explota en área. También se fabrican en el banco de taller.", "Comprar · %d" % Data.GRENADE.price, p.coins >= Data.GRENADE.price and p.tr < 6, func(): action.emit("buy_traca", []), CORAL)
		2:
			var lvl:int = s.clvl
			if lvl < 3:
				var m:int = Data.CORE_UPGRADE.mat[lvl]
				var c:int = Data.CORE_UPGRADE.coins[lvl]
				shop_row("Casa reforzada · nivel %d" % (lvl + 1), "Tapiar ventanas y apuntalar: +50 de resistencia máxima y reparación inmediata. Mejora colectiva.", "%d mat. + %d fichas" % [m, c], s.mat >= m and p.coins >= c, func(): action.emit("core_up", []), Color("ffb35c"))
			else:
				shop_row("Casa reforzada al máximo", "La casa no puede reforzarse más.", "—", false, func(): pass)
			for i in Data.SITES.size():
				var claimed:bool = s.si[i][0]
				shop_row(Data.SITES[i].name + (" · del barrio" if claimed else ""), Data.SITES[i].bonus, "Conquistada" if claimed else "Ve a su estandarte (C)", false, func(): pass, Color(Data.SITES[i].color))

func build_map():
	hud.add_child(map_panel)
	map_panel.add_theme_stylebox_override("panel", box(Color(NAVY, 0.95), 20, 16))
	anchor(map_panel, 0.5, 0.5, Vector2(0, 0))
	var row := hbox(map_panel, 18)
	bigmap = Control.new()
	bigmap.custom_minimum_size = Vector2(700, 620)
	bigmap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bigmap.draw.connect(func(): draw_map(bigmap, true))
	row.add_child(bigmap)
	var col := vbox(row, 8)
	label(col, "El barrio", 28, YELLOW, 6)
	col.add_child(map_info)
	map_info.custom_minimum_size.x = 300
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.add_theme_font_size_override("font_size", 15)
	map_panel.visible = false

func build_pause():
	root.add_child(pause)
	pause.add_theme_stylebox_override("panel", box(Color(NAVY, 0.96), 22, 26))
	anchor(pause, 0.5, 0.5, Vector2(0, 0))
	pause.custom_minimum_size = Vector2(400, 0)
	var col := vbox(pause, 12)
	var t := label(col, "Pausa", 34, YELLOW, 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(col, "Reanudar", func(): resume.emit())
	button(col, "Ajustes", func(): toggle_panel(settings_panel))
	button(col, "Cómo se juega", func(): toggle_panel(help_panel))
	button(col, "Abandonar partida", func(): leave.emit())
	pause.visible = false

func build_over():
	root.add_child(over)
	over.add_theme_stylebox_override("panel", box(Color(Color("2a1f3d"), 0.96), 24, 28))
	anchor(over, 0.5, 0.5, Vector2(0, 0))
	over.custom_minimum_size = Vector2(600, 0)
	var col := vbox(over, 12)
	col.add_child(over_title)
	over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_title.add_theme_font_size_override("font_size", 40)
	over_title.add_theme_color_override("font_color", PINK)
	col.add_child(over_text)
	over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_text.custom_minimum_size.x = 540
	button(col, "Volver al menú", func(): leave.emit())
	over.visible = false

# ================================================================== HUD updates
func show_menu(v:bool):
	menu.visible = v
	hud.visible = not v
	if v:
		over.visible = false
		pause.visible = false
		shop.visible = false
		map_panel.visible = false

func say(text:String, c:Color = CREAM):
	var l := label(feed, text, 16, c, 7)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	feed_items.append([l, 7.0])
	while feed_items.size() > 6:
		feed_items.pop_front()[0].queue_free()

func big(title:String, sub:String, c:Color = YELLOW, time:float = 3.5):
	announce.text = title
	announce.add_theme_color_override("font_color", c)
	announce_sub.text = sub
	announce_t = time

func show_report(lines:Array):
	report_label.text = "☀  AMANECER  ☀\n" + "\n".join(lines)
	report_box.visible = true
	report_t = 7.0

func toggle_shop(open:bool):
	shop.visible = open
	if open: refresh_shop()

func fmt_time(t:float) -> String:
	var s := ceili(maxf(0.0, t))
	return "%d:%02d" % [s / 60, s % 60]

func render(s:Dictionary, id:int, local:Dictionary, dt:float):
	last_state = s
	my_id = id
	if not s.pl.has(id): return
	var p:Dictionary = s.pl[id]
	# banner
	var ph:int = s.ph
	var ev:Dictionary = Data.NIGHT_EVENTS[s.ev]
	var fronts := []
	for f in s.fr: fronts.append(Map.FRONT_NAMES[f])
	var front_text:String = " y ".join(fronts) if fronts.size() <= 2 else ", ".join(fronts.slice(0, fronts.size() - 1)) + " y " + fronts[-1]
	match ph:
		P.PREP:
			banner.text = "DÍA %d · PREPARACIÓN · %s" % [s.w, fmt_time(s.c)]
			clock_bar.max_value = s.cl
			clock_bar.value = s.c
			banner_sub.text = "Esta noche: %s · Llegarán por el %s" % [ev.name, front_text]
		P.NIGHT:
			banner.text = "NOCHE %d · %s · %d brotados" % [s.w, ev.name.to_upper(), s.rem]
			clock_bar.max_value = maxf(1, s.tot)
			clock_bar.value = s.rem
			banner_sub.text = ev.desc + " Frentes: " + front_text
		P.DAWN:
			banner.text = "AMANECER · %s" % fmt_time(s.c)
			clock_bar.max_value = s.cl
			clock_bar.value = s.c
			banner_sub.text = "Recuperad fuerzas: la tienda y las reparaciones esperan"
		P.OVER:
			banner.text = "FIN DE LA VERBENA"
			banner_sub.text = ""
	banner.add_theme_color_override("font_color", Color("b9a6ff") if ph == P.NIGHT else YELLOW)
	boss_box.visible = s.boss.size() > 0
	if boss_box.visible: boss_bar.value = s.boss[1] * 100.0
	var readies := 0
	var alive := 0
	for q in s.pl.values():
		if q.st == 0:
			alive += 1
			if q.ready: readies += 1
	ready_label.visible = ph == P.PREP
	ready_label.text = ("✔ Listo · " if p.ready else "N: listo para la noche · ") + "%d/%d preparados" % [readies, alive]
	ready_label.add_theme_color_override("font_color", MINT if p.ready else Color("cfd8ee"))
	# house & stock
	base_label.text = "🏠 Casa de la verbena  %d/%d" % [ceili(s.core), int(s.cmax)]
	base_bar.max_value = s.cmax
	base_bar.value = s.core
	var claimed := 0
	for si in s.si: if si[0]: claimed += 1
	res_label.text = "🪵 Materiales %d   🏳 Territorio %d/6   👥 Comunidad %d" % [s.mat, claimed, s.cm.size()]
	# team
	var ids:Array = s.pl.keys()
	ids.sort()
	while team_box.get_child_count() > ids.size() - 1:
		var c := team_box.get_child(team_box.get_child_count() - 1)
		team_box.remove_child(c)
		c.queue_free()
	var row := 0
	for other in ids:
		if other == id: continue
		var q:Dictionary = s.pl[other]
		var card:PanelContainer
		if row < team_box.get_child_count():
			card = team_box.get_child(row)
		else:
			card = panel(team_box, Color(NAVY, 0.82), 12, 10)
			card.custom_minimum_size = Vector2(240, 0)
			var v := vbox(card, 3)
			label(v, "", 15)
			bar(v, MINT, 10)
		var v:VBoxContainer = card.get_child(0)
		var l:Label = v.get_child(0)
		var b:ProgressBar = v.get_child(1)
		var state_txt := ""
		if q.st == 1: state_txt = "  ⚠ CAÍDO %ds" % ceili(q.bleed)
		if q.st == 2: state_txt = "  ✝ vuelve al amanecer"
		l.text = "%s · %s Nv%d%s" % [q.name, Data.ROLES[q.role].name, q.lvl, state_txt]
		l.add_theme_color_override("font_color", Color(SLOT_COLORS[q.slot % 4]) if q.st == 0 else CORAL)
		b.max_value = q.hpmax
		b.value = q.hp
		row += 1
	# me
	me_name.text = "%s · %s · Nivel %d" % [p.name, Data.ROLES[p.role].name, p.lvl]
	me_name.add_theme_color_override("font_color", Color(Data.ROLES[p.role].color).lightened(0.25))
	hp_bar.max_value = p.hpmax
	hp_bar.value = p.hp
	(hp_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = MINT if p.hp > p.hpmax * 0.35 else CORAL
	var lvl:int = p.lvl
	var lo:int = Data.XP_LEVELS[lvl - 1]
	var hi:int = Data.XP_LEVELS[mini(lvl, Data.XP_LEVELS.size() - 1)]
	xp_bar.max_value = maxf(1, hi - lo)
	xp_bar.value = p.xp - lo if lvl < Data.XP_LEVELS.size() else xp_bar.max_value
	var cd:float = Data.ROLES[p.role].cd * (1.0 - 0.06 * (p.lvl - 1))
	ab_label.text = "Q · %s%s" % [Data.ROLES[p.role].ability, "" if p.ab <= 0 else " %ds" % ceili(p.ab)]
	ab_label.add_theme_color_override("font_color", SKY if p.ab <= 0 else Color("8090a8"))
	ab_bar.max_value = cd
	ab_bar.value = cd - p.ab
	items_label.text = "🪙 %d fichas   ✚ %d botiquín (H)   🧨 %d tracas (G)" % [p.coins, p.med, p.tr]
	# weapon
	var g:int = p.gun
	var w:Dictionary = Data.WEAPONS[g]
	gun_label.text = "%s  Nv%d" % [w.name, p.guns.get(g, 1)]
	gun_label.add_theme_color_override("font_color", Color(w.color).lightened(0.2))
	var res:int = p.res.get(g, -1)
	ammo_label.text = "%d / %s" % [p.mag.get(g, 0), "∞" if res < 0 else str(res)]
	ammo_label.add_theme_color_override("font_color", CORAL if p.mag.get(g, 0) == 0 else YELLOW)
	reload_bar.visible = p.rl > 0
	reload_bar.max_value = maxf(0.01, p.rlmax)
	reload_bar.value = p.rlmax - p.rl
	for i in slots_box.get_child_count():
		var sl:Label = slots_box.get_child(i)
		var owned:bool = p.guns.has(i)
		sl.text = str(i + 1)
		var st := box(Color(Data.WEAPONS[i].color).darkened(0.35) if i == g else (Color("2e4566") if owned else Color(0.1, 0.12, 0.18, 0.6)), 8, 4, YELLOW if i == g else Color(0, 0, 0, 0), 2 if i == g else 0)
		sl.add_theme_stylebox_override("normal", st)
		sl.add_theme_color_override("font_color", CREAM if owned else Color("55607a"))
	# prompt
	notice.text = p.notice
	var pr:String = local.get("prompt", "")
	prompt.text = pr if pr != "" else p.prompt
	if p.hold != "" and p.hm > 0:
		hold_bar.visible = true
		hold_bar.max_value = p.hm
		hold_bar.value = p.ht
	else:
		hold_bar.visible = false
	# build bar
	build_bar.visible = local.get("build", -1) >= 0
	prompt_box.offset_top = -330.0 if build_bar.visible else -24.0
	prompt_box.offset_bottom = prompt_box.offset_top
	if build_bar.visible:
		for i in build_cards.size():
			var b:Button = build_cards[i][0]
			b.button_pressed = i == local.build
			var cost:int = local.costs[i]
			var lab:Label = build_cards[i][1]
			lab.text = "%d mat." % cost
			lab.add_theme_color_override("font_color", YELLOW if s.mat >= cost else CORAL)
		build_hint.text = local.get("build_hint", "")
	# timers
	announce_t -= dt
	var a := clampf(announce_t, 0.0, 1.0)
	announce.modulate.a = a
	announce_sub.modulate.a = a
	announce.scale = Vector2.ONE
	report_t -= dt
	report_box.visible = report_t > 0
	report_box.modulate.a = clampf(report_t, 0.0, 1.0)
	for i in range(feed_items.size() - 1, -1, -1):
		feed_items[i][1] -= dt
		feed_items[i][0].modulate.a = clampf(feed_items[i][1], 0.0, 1.0)
		if feed_items[i][1] <= 0:
			feed_items[i][0].queue_free()
			feed_items.remove_at(i)
	if shop.visible and Engine.get_process_frames() % 10 == 0: refresh_shop()
	if map_panel.visible:
		map_info.text = map_text(s)
		bigmap.queue_redraw()
	minimap.queue_redraw()
	overlay.queue_redraw()
	if s.ph == P.OVER and not over.visible:
		over.visible = true
		over_title.text = "Se acabó la verbena"
		var lines := []
		lines.append(str(s.rep[0]) if s.rep.size() > 0 else "")
		lines.append("Aguantasteis %d noches · %d brotados derrotados · %d vecinos rescatados" % [s.stats.nights, s.stats.kills, s.stats.rescued])
		for q in s.pl.values(): lines.append("%s (%s, nivel %d): %d derribos" % [q.name, Data.ROLES[q.role].name, q.lvl, q.kills])
		over_text.text = "\n".join(lines)

func map_text(s:Dictionary) -> String:
	var lines := []
	for i in Data.SITES.size():
		var si:Array = s.si[i]
		lines.append("%s %s\n   %s" % ["🏳" if si[0] else "·", Data.SITES[i].name + (" (%d%%)" % int(100.0 * si[1] / si[2]) if si[0] else ""), Data.SITES[i].bonus])
	lines.append("")
	lines.append("Conquistar cuesta %d materiales (C junto al estandarte, de día y sin brotados cerca)." % s.cc)
	if s.cm.size() > 0:
		var names := []
		for k in s.cm: names.append(Data.SURVIVORS[k].name)
		lines.append("Comunidad: " + ", ".join(names))
	return "\n".join(lines)

# ================================================================== drawing
func world_to_map(c:Control, p:Vector2, big:bool) -> Vector2:
	var area := Rect2(-37, -33, 74, 66)
	if not big:
		var center:Vector2 = mm_data.get("me", Vector2.ZERO)
		area = Rect2(center - Vector2(22, 19.5), Vector2(44, 39))
	return (p - area.position) / area.size * c.size

func draw_map(c:Control, big:bool):
	var s := last_state
	if s.is_empty(): return
	var sc := c.size / Vector2(74, 66) if big else c.size / Vector2(44, 39)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("5fa860"))
	for z in Map.ROADS_H:
		var a := world_to_map(c, Vector2(-40, z - 2), big)
		c.draw_rect(Rect2(a, Vector2(80, 4) * sc), Color("7a8498"))
	for x in Map.ROADS_V:
		var a := world_to_map(c, Vector2(x - 2, -40), big)
		c.draw_rect(Rect2(a, Vector2(4, 80) * sc), Color("7a8498"))
	c.draw_rect(Rect2(world_to_map(c, Vector2(-11, -9), big), Vector2(22, 18) * sc), Color("e8c890"))
	for h in Map.HOUSES: c.draw_rect(Rect2(world_to_map(c, h.rect.position, big), h.rect.size * sc), Color("c98b7a"))
	for i in Map.SITES.size():
		var si:Array = s.si[i]
		var r:Rect2 = Map.SITES[i].rect
		var col := Color(Data.SITES[i].color) if si[0] else Color("8a8f9c")
		c.draw_rect(Rect2(world_to_map(c, r.position, big), r.size * sc), col)
		var b := world_to_map(c, Map.SITES[i].beacon, big)
		if si[0]: c.draw_arc(b, Map.SITE_BUILD_RADIUS * sc.x, 0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)
		c.draw_circle(b, 4.0 if not big else 6.0, col.lightened(0.3))
		if big: c.draw_string(ThemeDB.fallback_font, b + Vector2(8, -6), Data.SITES[i].name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	c.draw_rect(Rect2(world_to_map(c, Map.BASE.position, big), Map.BASE.size * sc), Color("ffd166"))
	c.draw_arc(world_to_map(c, Map.BASE_CENTER, big), Map.BASE_BUILD_RADIUS * sc.x, 0, TAU, 48, Color(1, 1, 1, 0.35), 1.5)
	var st:PackedInt32Array = s.st
	for i in range(0, st.size(), 8):
		var cell := st[i]
		var wp := Vector2(cell % 74 - 37 + 0.5, cell / 74 - 33 + 0.5)
		c.draw_rect(Rect2(world_to_map(c, wp - Vector2(0.5, 0.5), big), sc), Color("6b4f3c") if st[i + 1] < 2 else Color("4cc9f0"))
	if big:
		for i in Map.LOOT.size():
			if s.lo[i]: c.draw_circle(world_to_map(c, Map.LOOT[i].p, big), 3.0, Color("fff3b0"))
	for f in s.fr:
		for pt in Map.FRONTS[f]:
			var m := world_to_map(c, pt.clamp(Vector2(-36, -32), Vector2(36, 32)), big)
			var col := Color(1, 0.3, 0.3, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008))
			c.draw_circle(m, 6.0 if big else 4.0, col)
	var en:PackedFloat32Array = s.en
	for i in range(0, en.size(), 8):
		var kind := int(en[i + 1])
		c.draw_circle(world_to_map(c, Vector2(en[i + 2], en[i + 3]), big), (5.0 if kind == 7 else 2.2) * (1.4 if big else 1.0), Color("ff4d6d") if int(en[i + 6]) & 4 == 0 else Color("b07a8a"))
	for sv in s.sv: c.draw_string(ThemeDB.fallback_font, world_to_map(c, Vector2(sv[1], sv[2]), big) - Vector2(3, -6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, YELLOW)
	for d in s.dr: c.draw_circle(world_to_map(c, Vector2(d[1], d[2]), big), 5.0, Color("4cc9f0"))
	for m in markers:
		c.draw_arc(world_to_map(c, m[0], big), 7.0, 0, TAU, 16, m[1], 2.0)
	for pid in s.pl:
		var q:Dictionary = s.pl[pid]
		var pos := world_to_map(c, q.p, big)
		var col := Color(SLOT_COLORS[q.slot % 4])
		c.draw_circle(pos, 6.0 if pid == my_id else 4.5, Color(0.1, 0.08, 0.14))
		c.draw_circle(pos, 4.5 if pid == my_id else 3.5, col if q.st == 0 else CORAL)
		if pid == my_id:
			c.draw_line(pos, pos + q.aim * 12.0, col, 2.0)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.25), false, 2.0)

func draw_overlay():
	var vp := overlay.size
	for m in mm_data.get("indicators", []):
		var sp:Vector2 = m[0]
		var col:Color = m[1]
		var text:String = m[2]
		var onscreen:bool = m[3]
		if onscreen:
			overlay.draw_circle(sp + Vector2(0, -6), 7.0, Color(0.1, 0.08, 0.14, 0.8))
			overlay.draw_circle(sp + Vector2(0, -6), 5.0, col)
			continue
		var center := vp * 0.5
		var dir := (sp - center).normalized()
		var edge := center + dir * minf(absf((vp.x * 0.5 - 50) / maxf(0.001, absf(dir.x))), absf((vp.y * 0.5 - 50) / maxf(0.001, absf(dir.y))))
		var perp := Vector2(-dir.y, dir.x)
		overlay.draw_colored_polygon(PackedVector2Array([edge + dir * 18, edge - dir * 6 + perp * 12, edge - dir * 6 - perp * 12]), col)
		overlay.draw_string(ThemeDB.fallback_font, edge - dir * 30 - Vector2(40, -6), text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.WHITE)
