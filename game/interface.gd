extends CanvasLayer
## Interface: menus, HUD, shop, build bar, minimap, pause and end screens.

signal launch(mode:String, role:int, address:String, name:String)
signal settings_changed(settings:Dictionary)
signal leave
signal resume
signal action(name:String, args:Array)
signal build_pick(kind:int)
signal rematch
signal close_map

const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const P := Data.Phase
const St = preload("res://game/ui/style.gd")
const Map3D = preload("res://game/ui/map3d.gd")
const HUD = preload("res://game/ui/hud.gd")

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
var settings := {"quality":2, "fullscreen":false, "volume":0.8, "music":0.6, "sfx":1.0, "shake":true, "flashes":true, "numbers":false, "sensitivity":1.0, "ui_scale":1.0}
var prefs
var profile
var rank_labels := []
var record_label:Label
var continue_button:Button
var variant := 0
var variant_desc:Label
var settings_list := VBoxContainer.new()
var bind_buttons := {}
var waiting_bind := ""
var help_text:Label
var orbit_reticle := Label.new()

var hud := Control.new()
var canvas = HUD.new()
var board := PanelContainer.new()
var board_list := VBoxContainer.new()
var build_bar := PanelContainer.new()
var build_cards := []
var build_hint := Label.new()
var shop := PanelContainer.new()
var shop_list := VBoxContainer.new()
var shop_tab := 0
var shop_tabs := []
var shop_coins := Label.new()
var shop_sig := ""
var board_sig := ""
var map_panel := PanelContainer.new()
var map_info := Label.new()
var minimap:Control
var minimap_panel := PanelContainer.new()
var map3d = Map3D.new()
var bigmap:Control
var pause := PanelContainer.new()
var over := PanelContainer.new()
var over_title := Label.new()
var over_text := Label.new()
var rematch_button:Button
var can_rematch := true
var over_wait := 0.0
var last_state := {}
var my_id := 0
var build_kind := -1
var mm_data := {}

func _exit_tree():
	## Let go of the viewport textures so the renderer can free them at exit.
	St._fonts.clear()

func _ready():
	layer = 5
	build_theme()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme_res
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_menu()
	add_child(map3d)
	build_hud()
	build_settings()
	build_help()
	build_pause()
	build_over()
	hud.hide()

# ================================================================== theme
func box(c:Color, radius:int = 14, margin:int = 12, border:Color = Color(0, 0, 0, 0), bw:int = 0) -> StyleBoxFlat:
	var s := St.card(c, radius, border, bw, 4 if bw > 0 else 0)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	return s

func paper_box(c:Color = St.PAPER, radius:int = 22, margin:int = 18, border:Color = St.INK) -> StyleBoxFlat:
	## Cream paper card with a plum ink outline and a solid drop shadow.
	var s := St.card(c, radius, border, 3, 6)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.8
	s.content_margin_bottom = margin * 0.8
	return s

func title(parent:Control, text:String, color:Color = St.INK, size:int = 32) -> Label:
	## Rounded title font with a coloured underline ribbon drawn below.
	var l := label(parent, text, size, color)
	l.add_theme_font_override("font", St.font("title", 600))
	return l

func build_theme():
	theme_res.default_font_size = 18
	theme_res.default_font = St.font("body", 750)
	var btn := func(fill:Color, border:Color = St.INK, shadow:int = 4) -> StyleBoxFlat:
		var b := St.card(fill, 14, border, 3, shadow)
		b.content_margin_left = 14
		b.content_margin_right = 14
		b.content_margin_top = 6
		b.content_margin_bottom = 6
		return b
	theme_res.set_stylebox("panel", "PanelContainer", paper_box())
	theme_res.set_stylebox("normal", "Button", btn.call(St.CARD))
	theme_res.set_stylebox("hover", "Button", btn.call(St.SUN))
	theme_res.set_stylebox("pressed", "Button", btn.call(St.CORAL, St.INK, 1))
	theme_res.set_stylebox("hover_pressed", "Button", btn.call(St.CORAL.lightened(0.1), St.INK, 1))
	theme_res.set_stylebox("disabled", "Button", btn.call(St.PAPER_DARK, Color(St.INK, 0.35), 0))
	theme_res.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme_res.set_font("font", "Button", St.font("title", 550))
	theme_res.set_color("font_color", "Button", St.INK)
	theme_res.set_color("font_hover_color", "Button", St.INK)
	theme_res.set_color("font_pressed_color", "Button", Color.WHITE)
	theme_res.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme_res.set_color("font_focus_color", "Button", St.INK)
	theme_res.set_color("font_disabled_color", "Button", Color(St.INK, 0.4))
	theme_res.set_stylebox("normal", "LineEdit", box(Color.WHITE, 12, 12, St.INK, 3))
	theme_res.set_stylebox("focus", "LineEdit", box(Color.WHITE, 12, 12, St.CORAL, 3))
	theme_res.set_color("font_color", "LineEdit", St.INK)
	theme_res.set_color("caret_color", "LineEdit", St.CORAL)
	theme_res.set_color("font_placeholder_color", "LineEdit", Color(St.INK, 0.4))
	theme_res.set_color("font_color", "Label", St.INK)
	theme_res.set_color("font_outline_color", "Label", St.INK)
	theme_res.set_constant("outline_size", "Label", 0)
	theme_res.set_stylebox("background", "ProgressBar", box(Color(St.INK, 0.15), 8, 0))
	theme_res.set_stylebox("fill", "ProgressBar", box(St.MINT, 8, 0))
	theme_res.set_stylebox("normal", "OptionButton", btn.call(St.CARD))
	theme_res.set_stylebox("hover", "OptionButton", btn.call(St.SUN))
	theme_res.set_stylebox("pressed", "OptionButton", btn.call(St.SUN, St.INK, 1))
	theme_res.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	theme_res.set_color("font_color", "OptionButton", St.INK)
	theme_res.set_color("font_hover_color", "OptionButton", St.INK)
	theme_res.set_color("font_pressed_color", "OptionButton", St.INK)
	theme_res.set_color("font_focus_color", "OptionButton", St.INK)
	theme_res.set_color("font_color", "CheckButton", St.INK)
	theme_res.set_color("font_hover_color", "CheckButton", St.INK)
	theme_res.set_color("font_pressed_color", "CheckButton", St.INK)
	theme_res.set_color("font_hover_pressed_color", "CheckButton", St.INK)
	theme_res.set_color("font_focus_color", "CheckButton", St.INK)
	theme_res.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	theme_res.set_stylebox("slider", "HSlider", box(Color(St.INK, 0.18), 6, 0))
	theme_res.set_stylebox("grabber_area", "HSlider", box(St.CORAL, 6, 0))
	theme_res.set_stylebox("grabber_area_highlight", "HSlider", box(St.CORAL, 6, 0))
	theme_res.set_stylebox("panel", "PopupMenu", paper_box(St.CARD, 14, 8))
	theme_res.set_color("font_color", "PopupMenu", St.INK)
	theme_res.set_color("font_hover_color", "PopupMenu", St.INK)
	theme_res.set_stylebox("hover", "PopupMenu", box(St.SUN, 8, 4))
	theme_res.set_stylebox("panel", "TooltipPanel", paper_box(St.CARD, 12, 10))
	theme_res.set_color("font_color", "TooltipLabel", St.INK)
	theme_res.set_stylebox("scroll", "VScrollBar", box(Color(St.INK, 0.1), 6, 0))
	theme_res.set_stylebox("grabber", "VScrollBar", box(St.WOOD, 6, 0))
	theme_res.set_stylebox("grabber_highlight", "VScrollBar", box(St.CORAL, 6, 0))
	theme_res.set_stylebox("grabber_pressed", "VScrollBar", box(St.CORAL, 6, 0))

func label(parent:Control, text:String, size:int = 18, color:Color = St.INK, outline:int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", St.INK)
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

func panel(parent:Control, c:Color = St.CARD, radius:int = 16, margin:int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(c, radius, margin, St.INK, 2))
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
	title_box.position = Vector2(64, 58)
	var tag := label(title_box, "COOPERATIVO · 1–4 VECINOS", 18, St.SUN, 8)
	tag.add_theme_font_override("font", St.font("title", 600))
	var t := title(title_box, "La última verbena", St.PAPER, 76)
	t.add_theme_constant_override("outline_size", 22)
	t.add_theme_color_override("font_outline_color", St.INK)
	label(title_box, "Las guirnaldas siguen encendidas. Al anochecer llegan los brotados.", 20, St.PAPER, 9)
	menu.add_child(menu_panel)
	menu_panel.add_theme_stylebox_override("panel", paper_box(St.PAPER, 26, 22))
	menu_panel.position = Vector2(64, 200)
	menu_panel.custom_minimum_size = Vector2(600, 0)
	var col := vbox(menu_panel, 10)
	var nrow := hbox(col, 10)
	label(nrow, "¿Cómo te llamas?", 16, St.INK_SOFT)
	nrow.add_child(name_edit)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.placeholder_text = "Tu nombre en el barrio"
	name_edit.max_length = 14
	name_edit.custom_minimum_size.y = 40
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in 4:
		var card := Button.new()
		card.custom_minimum_size = Vector2(275, 128)
		card.toggle_mode = true
		card.button_pressed = i == 0
		var rc := Color(Data.ROLES[i].color)
		card.add_theme_stylebox_override("normal", box(St.CARD, 16, 12, Color(St.INK, 0.35), 2))
		card.add_theme_stylebox_override("hover", box(rc.lightened(0.75), 16, 12, St.INK, 3))
		card.add_theme_stylebox_override("pressed", box(rc.lightened(0.55), 16, 12, St.INK, 4))
		card.add_theme_stylebox_override("hover_pressed", box(rc.lightened(0.5), 16, 12, St.INK, 4))
		card.pressed.connect(pick_role.bind(i))
		grid.add_child(card)
		var inner := vbox(card, 2)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 14
		inner.offset_top = 8
		inner.offset_right = -10
		title(inner, Data.ROLES[i].name, rc.darkened(0.35), 24)
		var top := hbox(inner, 8)
		var title_label := inner.get_child(0)
		inner.remove_child(title_label)
		top.add_child(title_label)
		rank_labels.append(label(top, "", 13, St.MINT.darkened(0.35)))
		label(inner, "Q · " + Data.ROLES[i].ability, 14, St.INK)
		var d := label(inner, Data.ROLES[i].desc, 12, St.INK_SOFT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 245
		role_cards.append(card)
	var vrow := hbox(col, 10)
	label(vrow, "Reglas de la partida", 16, St.INK_SOFT)
	var vopt := OptionButton.new()
	for v in Data.VARIANTS: vopt.add_item(v.name)
	vopt.item_selected.connect(func(i):
		variant = i
		variant_desc.text = Data.VARIANTS[i].desc if i > 0 else ""
		variant_desc.visible = i > 0)
	vopt.tooltip_text = "Variantes opcionales que cambian rutas y construcción"
	vopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(vopt)
	variant_desc = label(col, "", 13, St.INK_SOFT)
	variant_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	variant_desc.custom_minimum_size.x = 540
	variant_desc.visible = false
	record_label = label(col, "", 14, St.INK_SOFT)
	record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_label.custom_minimum_size.x = 540
	continue_button = button(col, "", func(): emit_launch("continue"), 46)
	continue_button.add_theme_stylebox_override("normal", box(St.SUN, 14, 12, St.INK, 3))
	continue_button.visible = false
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
	status.add_theme_color_override("font_color", St.CORAL.darkened(0.2))
	status.custom_minimum_size.x = 540
	var tip := label(menu, "Ratón y teclado · F1 ayuda en partida", 15, St.PAPER, 6)
	anchor(tip, 1.0, 1.0, Vector2(-24, -16))

func draw_bunting(c:Control):
	var w := c.size.x
	var colors:Array = St.FESTIVE
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

func refresh_profile():
	## Role cards show the rank earned in previous matches and the perks it gives.
	if profile == null: return
	for i in rank_labels.size():
		var r:int = profile.rank(i)
		var goal:int = profile.next_goal(i)
		rank_labels[i].text = "Rango %d%s" % [r, "" if goal < 0 else " · %d/%d" % [profile.role_xp[i], goal]]
		role_cards[i].tooltip_text = "Ventajas: " + (", ".join(profile.unlocked(i)) if profile.unlocked(i).size() else "aún ninguna") + "\nRango 2: %s · Rango 3: %s" % [profile.UNLOCKS[i][0], profile.UNLOCKS[i][1]]
	var saved:Dictionary = preload("res://game/checkpoint.gd").peek()
	continue_button.visible = not saved.is_empty()
	if continue_button.visible:
		var names:Array = saved.players.slice(0, 3)
		continue_button.text = "⟳  Continuar: noche %d · %s%s" % [saved.wave - 1, ", ".join(names), " (en red)" if saved.mode == "host" else ""]
	if prefs != null and name_edit.text == "": name_edit.text = prefs.values.get("name", "")
	record_label.text = "Partidas %d · Victorias %d · Mejor noche %d · Rango %d de %s: %s" % [profile.matches, profile.wins, profile.best_night, profile.rank(role), Data.ROLES[role].name, ", ".join(profile.unlocked(role)) if profile.unlocked(role).size() else "sube de rango jugando con este oficio"]

func pick_role(i:int):
	role = i
	for j in role_cards.size(): role_cards[j].button_pressed = j == i
	refresh_profile()

func emit_launch(mode:String):
	launch.emit(mode, role, address.text.strip_edges(), name_edit.text.strip_edges())

func toggle_panel(p:Control):
	var show := not p.visible
	for q in [settings_panel, help_panel]: q.visible = false
	p.visible = show
	if show: p.move_to_front()
	waiting_bind = ""

# ================================================================== settings & help
func build_settings():
	root.add_child(settings_panel)
	settings_panel.visible = false
	settings_panel.add_theme_stylebox_override("panel", paper_box(St.PAPER, 24, 24))
	settings_panel.custom_minimum_size = Vector2(620, 0)
	anchor(settings_panel, 0.5, 0.5, Vector2.ZERO)
	var col := vbox(settings_panel, 10)
	title(col, "Ajustes", St.INK, 34)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	settings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_list.add_theme_constant_override("separation", 10)
	scroll.add_child(settings_list)
	button(col, "Cerrar", func(): settings_panel.hide())

func sync_settings():
	## Rebuild the settings controls from the saved preferences.
	if prefs != null: settings = prefs.values
	for c in settings_list.get_children(): c.queue_free()
	bind_buttons.clear()
	var col := settings_list
	label(col, "Imagen", 20, SKY)
	var q := OptionButton.new()
	for n in ["Baja (portátiles)", "Media", "Alta", "Ultra (niebla volumétrica y desenfoque)"]: q.add_item(n)
	q.selected = settings.quality
	q.item_selected.connect(func(i): set_setting("quality", i))
	row_with(col, "Calidad gráfica", q)
	var fs := CheckButton.new()
	fs.button_pressed = settings.fullscreen
	fs.toggled.connect(func(v): set_setting("fullscreen", v))
	row_with(col, "Pantalla completa", fs)
	label(col, "Sonido", 20, SKY)
	for item in [["volume", "Volumen general", 0.0, 1.0], ["sfx", "Efectos", 0.0, 1.0], ["music", "Música", 0.0, 1.0]]:
		slider_row(col, item[0], item[1], item[2], item[3], 0.05)
	label(col, "Comodidad y accesibilidad", 20, SKY)
	slider_row(col, "sensitivity", "Sensibilidad de la cámara", 0.3, 2.5, 0.1)
	slider_row(col, "ui_scale", "Tamaño de la interfaz", 0.8, 1.4, 0.05)
	for item in [["shake", "Sacudidas de cámara"], ["flashes", "Destellos y relámpagos"], ["numbers", "Números de daño"]]:
		var c := CheckButton.new()
		c.button_pressed = settings[item[0]]
		c.toggled.connect(func(v): set_setting(item[0], v))
		row_with(col, item[1], c)
	label(col, "Controles (clic y pulsa una tecla)", 20, SKY)
	if prefs != null:
		for a in prefs.ACTIONS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(150, 34)
			b.focus_mode = Control.FOCUS_NONE
			b.text = prefs.key_name(a[0])
			b.pressed.connect(func():
				waiting_bind = a[0]
				refresh_binds())
			row_with(col, a[1], b)
			bind_buttons[a[0]] = b
		button(col, "Restaurar teclas", func():
			prefs.reset_binds()
			refresh_binds()
			settings_changed.emit(settings), 36)
	refresh_help()

func slider_row(col:Control, key:String, text:String, lo:float, hi:float, step:float):
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = settings[key]
	s.custom_minimum_size = Vector2(220, 24)
	s.value_changed.connect(func(v): set_setting(key, v))
	row_with(col, text, s)

func refresh_binds():
	for k in bind_buttons:
		bind_buttons[k].text = "Pulsa una tecla…" if waiting_bind == k else prefs.key_name(k)
	refresh_help()

func capture_key(code:int) -> bool:
	## While a binding is being edited, the next key goes to it (Esc cancels).
	if waiting_bind == "": return false
	if code != KEY_ESCAPE:
		var swapped:String = prefs.rebind(waiting_bind, code)
		if swapped != "": say("«%s» pasa a %s" % [swapped, prefs.key_name(swapped)], St.SUN)
	waiting_bind = ""
	refresh_binds()
	settings_changed.emit(settings)
	return true

func k(action:String) -> String:
	return prefs.key_name(action) if prefs != null else "?"

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
	help_panel.add_theme_stylebox_override("panel", paper_box(St.PAPER, 24, 24))
	anchor(help_panel, 0.5, 0.5, Vector2(0, 0))
	help_panel.custom_minimum_size = Vector2(860, 0)
	var col := vbox(help_panel, 10)
	title(col, "Cómo se juega", St.INK, 34)
	help_text = label(col, "", 16)
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text.custom_minimum_size.x = 810
	button(col, "Cerrar", func(): help_panel.hide())

# ================================================================== HUD
func refresh_help():
	if help_text == null: return
	help_text.text = """De día rebusca materiales y fichas, rescata vecinos, conquista propiedades y prepara defensas alrededor de la casa de la verbena. De noche los brotados atacan por los frentes anunciados: aguanta hasta que no quede ninguno. Si cae la casa o todo el equipo, se acaba la fiesta.

%s%s%s%s moverse · Ratón apuntar · Clic izquierdo disparar · %s voltereta · %s correr · Rueda acercar o alejar la cámara
Arrastra con el botón derecho para girar la cámara · Clic derecho corto o %s sartenazo · %s recargar · 1–7 cambiar de arma
%s (mantener) rebuscar, reparar, reanimar o liberar · %s habilidad del oficio · %s traca · %s botiquín · %s tienda en la casa
%s construir (1–8 o rueda elige, clic coloca, %s mejora, %s desmonta) · %s conquistar · %s o Tab plano (clic en él para señalar)
%s pedir apoyo en tu posición (también si has caído) · Clic central señalar el punto del cursor · %s listo para la noche · Esc pausa

Materiales: compartidos por todo el equipo. Fichas: personales, para armas, mejoras y objetos.
Cada propiedad conquistada aporta una ventaja al amanecer, pero los brotados también irán a por su estandarte.
Barricada y alambrada se saltan; bobina, torreta y foco necesitan corriente durante un apagón (generador o Gasolinera).
Si una defensa cae, el aviso de brecha indica el acceso hasta que construyáis otra en ese lado.""" % [
		k("up"), k("left"), k("down"), k("right"), k("roll"), k("sprint"), k("melee"), k("reload"), k("use"), k("ability"),
		k("grenade"), k("medkit"), k("shop"), k("build"), k("grenade"), k("demolish"), k("claim"), k("map"), k("ping"), k("ready")]

func build_hud():
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(canvas)
	hud.add_child(orbit_reticle)
	orbit_reticle.text = "+"
	orbit_reticle.add_theme_font_size_override("font_size", 34)
	orbit_reticle.add_theme_constant_override("outline_size", 8)
	orbit_reticle.add_theme_color_override("font_outline_color", St.INK)
	orbit_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor(orbit_reticle, 0.5, 0.5, Vector2.ZERO)
	orbit_reticle.visible = false
	# small map in a paper frame with bunting
	var mmp := minimap_panel
	mmp.add_theme_stylebox_override("panel", paper_box(St.CARD, 22, 8))
	mmp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(mmp)
	anchor(mmp, 1.0, 0.0, Vector2(-24, 22))
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(196, 176)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(func(): draw_map(minimap, false))
	mmp.add_child(minimap)
	var deco := Control.new()
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.draw.connect(func(): St.bunting(deco, Vector2(10, -2), Vector2(deco.size.x - 10, -2), 8, 6, 12, 2))
	mmp.add_child(deco)
	build_buildbar()
	build_shop()
	build_map()
	hud.add_child(board)
	board.add_theme_stylebox_override("panel", paper_box(Color("f3d9b0"), 22, 22, Color("8b5e3c")))
	board.custom_minimum_size = Vector2(660, 0)
	anchor(board, 0.5, 0.5, Vector2.ZERO)
	var bcol := vbox(board, 10)
	title(bcol, "Tablón de encargos", Color("8b5e3c"))
	label(bcol, "Uno corto cerca de la plaza y otro ambicioso lejos. Caducan al anochecer.", 15, St.INK_SOFT)
	bcol.add_child(board_list)
	board_list.add_theme_constant_override("separation", 10)
	var close := button(bcol, "Cerrar", func(): board.visible = false, 40)
	close.focus_mode = Control.FOCUS_NONE
	board.visible = false

func build_buildbar():
	hud.add_child(build_bar)
	build_bar.add_theme_stylebox_override("panel", paper_box(St.PAPER, 22, 12))
	anchor(build_bar, 0.5, 1.0, Vector2(0, -192))
	build_bar.custom_minimum_size = Vector2(1060, 0)
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
		var k := label(inner, "%d · %s" % [i + 1, Data.STRUCTURES[i].name], 14, St.INK)
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.custom_minimum_size.x = 96
		var cost := label(inner, "", 14, St.INK)
		build_cards.append([b, cost])
	# the last card is not a defence: it takes things down and gives half back
	var db := Button.new()
	db.custom_minimum_size = Vector2(108, 70)
	db.toggle_mode = true
	db.focus_mode = Control.FOCUS_NONE
	db.add_theme_stylebox_override("normal", box(St.CORAL.lightened(0.55), 14, 12, St.INK, 3))
	db.add_theme_stylebox_override("hover", box(St.CORAL.lightened(0.3), 14, 12, St.INK, 3))
	db.add_theme_stylebox_override("pressed", box(St.CORAL, 14, 12, St.INK, 3))
	db.pressed.connect(func(): build_pick.emit(Data.STRUCTURES.size()))
	row.add_child(db)
	var dinner := vbox(db, 0)
	dinner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dinner.offset_top = 5
	dinner.offset_left = 6
	var dk := label(dinner, "9 · Desmontar", 14, St.INK)
	dk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dk.custom_minimum_size.x = 96
	build_cards.append([db, label(dinner, "X · ½ vuelve", 13, St.INK_SOFT)])
	col.add_child(build_hint)
	build_hint.add_theme_font_size_override("font_size", 15)
	build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_bar.visible = false

func build_shop():
	hud.add_child(shop)
	shop.add_theme_stylebox_override("panel", paper_box(St.PAPER, 26, 22))
	anchor(shop, 0.5, 0.5, Vector2(0, 0))
	shop.custom_minimum_size = Vector2(800, 620)
	var col := vbox(shop, 12)
	var head := hbox(col, 10)
	var t := title(head, "Puesto de la verbena", St.INK, 34)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chip := panel(head, St.SUN, 16, 14)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(shop_coins)
	shop_coins.add_theme_font_size_override("font_size", 19)
	shop_coins.add_theme_font_override("font", St.font("title", 600))
	shop_coins.add_theme_color_override("font_color", St.INK)
	var tabs := hbox(col, 8)
	shop_tabs.clear()
	for i in 4:
		var b := Button.new()
		b.text = ["Armas", "Equipo", "Barrio", "Vender"][i]
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.custom_minimum_size.y = 42
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", box(St.CORAL, 14, 12, St.INK, 3))
		b.pressed.connect(func():
			shop_tab = i
			for j in shop_tabs.size(): shop_tabs[j].button_pressed = j == i
			action.emit("ui_click", [])
			refresh_shop(true))
		tabs.add_child(b)
		shop_tabs.append(b)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 450)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	scroll.add_child(shop_list)
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 10)
	var foot := label(col, "T o Esc para cerrar · Las fichas son tuyas; los materiales son del equipo", 14, St.INK_SOFT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop.visible = false

func shop_row(name:String, desc:String, btn_text:String, enabled:bool, cb:Callable, accent:Color = St.SUN):
	## One stall card: a coloured stripe, the item, a short description and its button.
	var p := PanelContainer.new()
	var sb := box(St.CARD, 16, 14, St.INK, 2)
	sb.border_width_left = 12
	sb.border_color = St.INK
	sb.content_margin_left = 20
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	shop_list.add_child(p)
	var stripe := Control.new()
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stripe.draw.connect(func():
		stripe.draw_style_box(St.card(accent, 10, Color(0, 0, 0, 0), 0, 0), Rect2(Vector2(-16, -8), Vector2(10, stripe.size.y + 16))))
	p.add_child(stripe)
	var r := hbox(p, 12)
	var info := vbox(r, 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title(info, name, St.INK, 20)
	var d := label(info, desc, 14, St.INK_SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 470
	var b := button(r, btn_text, cb, 44)
	b.custom_minimum_size.x = 180
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if enabled: b.add_theme_stylebox_override("normal", box(accent.lightened(0.45), 14, 12, St.INK, 3))

func shop_signature(s:Dictionary, p:Dictionary) -> String:
	var claimed := []
	for si in s.si: claimed.append(si[0])
	return var_to_str([shop_tab, p.coins, s.mat, p.guns, p.gun, p.med, p.tr, p.res, s.clvl, claimed, s.pl.size()])

func refresh_shop(force:bool = false):
	## Rebuilt only when something it shows changes, so a click never lands on a
	## button that was replaced between pressing and releasing the mouse.
	var s := last_state
	if s.is_empty() or not s.pl.has(my_id): return
	var p:Dictionary = s.pl[my_id]
	var sig := shop_signature(s, p)
	if sig == shop_sig and not force: return
	shop_sig = sig
	for c in shop_list.get_children():
		shop_list.remove_child(c)
		c.queue_free()
	shop_coins.text = "%d fichas · %d materiales" % [p.coins, s.mat]
	match shop_tab:
		0:
			for g in Data.WEAPONS.size():
				var w:Dictionary = Data.WEAPONS[g]
				var owned:bool = p.guns.has(g)
				var locked:bool = w.req >= 0 and not s.si[w.req][0]
				var stats := "Daño %d · %.1f disparos/s · cargador %d · %d m" % [w.dmg * w.pellets, 1.0 / w.rate, w.mag, w.range]
				if not owned:
					var why := "" if not locked else " · necesita %s" % Data.SITES[w.req].name
					shop_row(w.name + why, w.desc + "\n" + stats, "Comprar · %d" % w.price, not locked and p.coins >= w.price, func(): action.emit("buy_gun", [g]), Color(w.color))
				else:
					var lvl:int = p.guns[g]
					if lvl < 3:
						var cost:int = w.up[lvl - 1]
						shop_row("%s · nivel %d" % [w.name, lvl], "Mejora a nivel %d: +25%% de daño.\n%s" % [lvl + 1, stats], "Mejorar · %d" % cost, p.coins >= cost, func(): action.emit("up_gun", [g]), Color(w.color))
					else:
						shop_row("%s · nivel máximo" % w.name, stats, "En uso" if p.gun == g else "Equipar", p.gun != g, func(): action.emit("switch", [g]), Color(w.color))
					if w.reserve > 0:
						shop_row("Munición: " + w.name, "Rellena la reserva (ahora %d)." % p.res[g], "Rellenar · %d" % w.ammo_price, p.coins >= w.ammo_price, func(): action.emit("ammo", [g]), St.WOOD)
		1:
			shop_row("Botiquín · %d/3" % p.med, "%s para curarte 55 de salud. Si caes, te levanta." % k("medkit"), "Comprar · %d" % Data.MEDKIT.price, p.coins >= Data.MEDKIT.price and p.med < 3, func(): action.emit("buy_medkit", []), St.MINT)
			shop_row("Traca · %d/6" % p.tr, "%s para lanzarla: explota en área. También se fabrican en el banco de taller." % k("grenade"), "Comprar · %d" % Data.GRENADE.price, p.coins >= Data.GRENADE.price and p.tr < 6, func(): action.emit("buy_traca", []), St.CORAL)
			shop_row("Lote para el equipo", "Deja en el porche munición, un botiquín, una traca y 40 de salud para un compañero. Cuesta 4 materiales comunes.", "Preparar · 4 mat.", s.mat >= 4 and s.pl.size() > 1, func(): action.emit("bundle", []), St.SKY)
		2:
			var lvl:int = s.clvl
			if lvl < 3:
				var m:int = Data.CORE_UPGRADE.mat[lvl]
				var c:int = Data.CORE_UPGRADE.coins[lvl]
				shop_row("Casa reforzada · nivel %d" % (lvl + 1), "Tapiar ventanas y apuntalar: +50 de resistencia máxima y reparación inmediata. Mejora colectiva.", "%d mat. + %d fichas" % [m, c], s.mat >= m and p.coins >= c, func(): action.emit("core_up", []), St.WOOD)
			else:
				shop_row("Casa reforzada al máximo", "La casa no puede reforzarse más.", "—", false, func(): pass, St.WOOD)
			for i in Data.SITES.size():
				var claimed:bool = s.si[i][0]
				shop_row(Data.SITES[i].name + (" · del barrio" if claimed else ""), Data.SITES[i].bonus, "Conquistada" if claimed else "Ve a su estandarte", false, func(): pass, Color(Data.SITES[i].color))
		3:
			var any := false
			for g in Data.WEAPONS.size():
				if g == 0 or not p.guns.has(g): continue
				any = true
				var w:Dictionary = Data.WEAPONS[g]
				var value := sell_value(p, g)
				shop_row("%s · nivel %d" % [w.name, p.guns[g]], "Te devuelven la mitad de lo invertido en el arma y sus mejoras.", "Vender · +%d" % value, true, func(): action.emit("sell_gun", [g]), Color(w.color))
			if p.med > 0: shop_row("Botiquín · tienes %d" % p.med, "Véndelo si andas corto de fichas.", "Vender · +%d" % (Data.MEDKIT.price / 2), true, func(): action.emit("sell_item", ["medkit"]), St.MINT)
			if p.tr > 0: shop_row("Traca · tienes %d" % p.tr, "Véndela si andas corto de fichas.", "Vender · +%d" % (Data.GRENADE.price / 2), true, func(): action.emit("sell_item", ["traca"]), St.CORAL)
			if not any and p.med == 0 and p.tr == 0:
				var l := label(shop_list, "No tienes nada que vender todavía. La pistola de feria se queda contigo.", 16, St.INK_SOFT)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func sell_value(p:Dictionary, g:int) -> int:
	## Mirrors Match.sell_value so the button shows the exact refund.
	if not p.guns.has(g) or g == 0: return 0
	var w:Dictionary = Data.WEAPONS[g]
	var spent:int = w.price
	for i in int(p.guns[g]) - 1: spent += int(w.up[i])
	return spent / 2

const BIG_MAP := Vector2(1000, 640)
var close_button:Button
var map_tween:Tween

func build_map():
	## The big map is the minimap grown large: a paper frame with the same 3D
	## model of the neighbourhood, opening out of the minimap's corner in a blink.
	hud.add_child(map_panel)
	map_panel.add_theme_stylebox_override("panel", paper_box(St.CARD, 26, 10))
	anchor(map_panel, 0.5, 0.5, Vector2(0, 0))
	bigmap = Control.new()
	bigmap.custom_minimum_size = BIG_MAP
	bigmap.clip_contents = true
	bigmap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bigmap.draw.connect(func(): draw_map(bigmap, true))
	map_panel.add_child(bigmap)
	map3d.set_sizes(map3d.mini_size, BIG_MAP)
	var deco := Control.new()
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.draw.connect(func():
		St.bunting(deco, Vector2(30, -4), Vector2(deco.size.x - 30, -4), 18, 10, 18, 1)
		var tw := St.text_width("El barrio", 22, "title", 650) + 44
		deco.draw_style_box(St.card(St.SUN, 12, St.INK, 3, 3), Rect2(Vector2(24, deco.size.y - 26), Vector2(tw, 38)))
		St.text(deco, Vector2(24, deco.size.y + 1), "El barrio", 22, St.INK, "title", 650, HORIZONTAL_ALIGNMENT_CENTER, tw))
	map_panel.add_child(deco)
	close_button = Button.new()
	close_button.text = "✕"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(48, 48)
	close_button.tooltip_text = "Cerrar el plano"
	for st in ["normal", "hover", "pressed"]:
		close_button.add_theme_stylebox_override(st, St.card(St.CORAL if st != "hover" else St.CORAL.lightened(0.2), 24, St.INK, 3, 4 if st != "pressed" else 1))
	close_button.add_theme_font_override("font", St.font("title", 700))
	close_button.add_theme_font_size_override("font_size", 26)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]: close_button.add_theme_color_override(c, Color.WHITE)
	close_button.pressed.connect(func():
		action.emit("ui_click", [])
		close_map.emit())
	deco.add_child(close_button)
	deco.resized.connect(func(): close_button.position = Vector2(deco.size.x - 30, -18))
	map_panel.visibility_changed.connect(func():
		if not map_panel.visible: return
		# grow out of the minimap in the top-right corner
		if map_tween: map_tween.kill()
		var full := BIG_MAP + Vector2(20, 14)
		map_panel.pivot_offset = Vector2(full.x, 0)
		map_panel.scale = Vector2(0.2, 0.2)
		map_panel.modulate.a = 0.0
		var from := minimap_panel.get_global_rect()
		var rest := get_viewport().get_visible_rect().size * 0.5 / maxf(0.1, get_tree().root.content_scale_factor) - full * 0.5
		map_panel.position = rest + (from.end - Vector2(0, from.size.y) - (rest + Vector2(full.x, 0))) * 0.6
		map_tween = create_tween().set_parallel(true)
		map_tween.tween_property(map_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		map_tween.tween_property(map_panel, "position", rest, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		map_tween.tween_property(map_panel, "modulate:a", 1.0, 0.12))
	map_panel.visible = false

func build_pause():
	root.add_child(pause)
	pause.add_theme_stylebox_override("panel", paper_box(St.PAPER, 26, 26))
	anchor(pause, 0.5, 0.5, Vector2(0, 0))
	pause.custom_minimum_size = Vector2(400, 0)
	var col := vbox(pause, 12)
	var t := title(col, "Pausa", St.INK, 38)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(col, "Reanudar", func(): resume.emit())
	button(col, "Ajustes", func(): toggle_panel(settings_panel))
	button(col, "Cómo se juega", func(): toggle_panel(help_panel))
	button(col, "Abandonar partida", func(): leave.emit())
	pause.visible = false

func build_over():
	root.add_child(over)
	over.add_theme_stylebox_override("panel", paper_box(St.PAPER, 28, 28))
	anchor(over, 0.5, 0.5, Vector2(0, 0))
	over.custom_minimum_size = Vector2(600, 0)
	var col := vbox(over, 12)
	col.add_child(over_title)
	over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_title.add_theme_font_size_override("font_size", 40)
	over_title.add_theme_font_override("font", St.font("title", 650))
	col.add_child(over_text)
	over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_text.custom_minimum_size.x = 540
	rematch_button = button(col, "Revancha con el mismo grupo", func(): rematch.emit())
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

func say(text:String, c:Color = St.SUN):
	canvas.toast(text, c)

func big(title_text:String, sub:String, c:Color = St.SUN, time:float = 3.5):
	canvas.announce(title_text, sub, c, time)

func show_report(lines:Array):
	canvas.report(lines)

func toggle_shop(open:bool):
	shop.visible = open
	if open: refresh_shop(true)

func fmt_time(t:float) -> String:
	var s := ceili(maxf(0.0, t))
	return "%d:%02d" % [s / 60, s % 60]

func render(s:Dictionary, id:int, local:Dictionary, dt:float):
	last_state = s
	my_id = id
	if not s.pl.has(id): return
	var p:Dictionary = s.pl[id]
	local["notes"] = notes_for(s, p)
	if prefs != null:
		for a in prefs.ACTIONS: canvas.keys[a[0]] = prefs.key_name(a[0])
	canvas.indicators = mm_data.get("indicators", [])
	canvas.feed(s, id, local, dt)
	# build bar
	build_bar.visible = local.get("build", -1) >= 0
	if build_bar.visible:
		for i in build_cards.size():
			var b:Button = build_cards[i][0]
			b.button_pressed = i == local.build
			if i >= local.costs.size(): continue
			var cost:int = local.costs[i]
			var lab:Label = build_cards[i][1]
			lab.text = "%d" % cost
			lab.add_theme_color_override("font_color", St.INK if s.mat >= cost else St.CORAL)
		build_hint.text = local.get("build_hint", "")
	if board.visible and Engine.get_process_frames() % 15 == 0: refresh_board(false)
	if shop.visible: refresh_shop()
	if map_panel.visible:
		bigmap.queue_redraw()
	map3d.update(s, mm_data.get("me", Vector2.ZERO), mm_data.get("yaw", 0.0), minimap_panel.visible, map_panel.visible)
	minimap.queue_redraw()
	minimap_panel.visible = s.ph != P.OVER
	over_wait = over_wait + dt if s.ph == P.OVER else 0.0
	var settle := 5.0 if s.get("vic", false) else (5.5 if s.get("core", 1.0) <= 0 else 1.5)
	if s.ph == P.OVER and not over.visible and over_wait > settle:
		over.visible = true
		var won:bool = s.get("vic", false)
		over_title.text = "¡La verbena está encendida!" if won else "Se acabó la verbena"
		over_title.add_theme_color_override("font_color", St.SUN.darkened(0.25) if won else St.CORAL)
		rematch_button.visible = can_rematch
		rematch_button.text = "Revancha con el mismo grupo" if can_rematch else "Esperando al anfitrión…"
		var lines := []
		lines.append(str(s.rep[0]) if s.rep.size() > 0 else "")
		lines.append("Aguantasteis %d noches · %d brotados derrotados · %d vecinos rescatados" % [s.stats.nights, s.stats.kills, s.stats.rescued])
		var installed := 0
		for x in s.get("pc", []): if x[0] == 4: installed += 1
		if not won: lines.append("Piezas de la verbena instaladas: %d de 4" % installed)
		for q in s.pl.values(): lines.append("%s (%s, nivel %d): %d derribos · %d lotes recogidos por otros" % [q.name, Data.ROLES[q.role].name, q.lvl, q.kills, q.get("helped", 0)])
		over_text.text = "\n".join(lines)

func notes_for(s:Dictionary, p:Dictionary) -> Array:
	## The paper note: the first-day checklist and the jobs you have taken.
	var lines:Array = first_day_steps(s, p)
	var jobs := []
	for j in s.get("jobs", []):
		if j[5] != 1: continue
		var d := roundi(p.p.distance_to(Vector2(j[3], j[4])))
		var where:String = j[11]
		match j[1]:
			"relevo": jobs.append("▢ Relevo en %s%s" % [where, "" if j[12] else " (sin localizar)"])
			"defensa": jobs.append("▢ Aguanta en %s · %d/%d s" % [where, int(j[8]), int(Data.JOB_DEFENSE_TIME)])
			"transporte": jobs.append("▢ %s · %d m" % ["Lleva la caja al porche" if j[9] == my_id else "Trae la caja de " + where, d])
			_: jobs.append("▢ Busca en %s · %d m" % [where, d])
	if jobs.is_empty(): return lines
	if lines.is_empty(): return ["Encargos"] + jobs
	return lines + jobs

func jobs_text(s:Dictionary, p:Dictionary) -> String:
	var lines := []
	for j in s.get("jobs", []):
		if j[5] != 1: continue
		var d := roundi(p.p.distance_to(Vector2(j[3], j[4])))
		var extra := ""
		if j[1] == "defensa": extra = " · %d/%d s" % [int(j[8]), int(Data.JOB_DEFENSE_TIME)]
		if j[1] == "transporte" and j[9] >= 0: extra = " · de camino al porche"
		if j[1] == "relevo":
			if not j[12]:
				lines.append("▢ Relevo eléctrico en algún lugar de %s · sin localizar (la exploradora lo encuentra con Q)" % j[11])
				continue
			extra = " · llévalo al cuadro de la casa" if j[9] >= 0 else " · localizado"
		lines.append("▢ %s en %s · %d m%s" % [Data.JOBS[j[1]].name, j[11], d, extra])
	return "\n".join(lines)

func toggle_board():
	board.visible = not board.visible
	if board.visible: refresh_board()

func refresh_board(force:bool = true):
	var s := last_state
	if s.is_empty() or not s.pl.has(my_id): return
	var p:Dictionary = s.pl[my_id]
	var jobs_sig := []
	for j in s.get("jobs", []): jobs_sig.append([j[0], j[5], j[12], roundi(p.p.distance_to(Vector2(j[3], j[4])) / 10.0)])
	var sig := var_to_str([jobs_sig, s.get("cm", []), s.get("cp", []), s.si])
	if sig == board_sig and not force: return
	board_sig = sig
	for c in board_list.get_children():
		board_list.remove_child(c)
		c.queue_free()
	for j in s.get("jobs", []):
		var card := panel(board_list, St.CARD, 14, 12)
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var r := hbox(card, 12)
		var info := vbox(r, 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := "%s %s · %s" % ["Encargo corto:" if j[2] == "corto" else "Encargo ambicioso:", Data.JOBS[j[1]].name.to_lower(), j[11]]
		label(info, title, 19, St.INK if j[2] == "corto" else St.CORAL.darkened(0.3))
		var d := roundi(p.p.distance_to(Vector2(j[3], j[4])))
		if not j[12]: d = roundi(p.p.distance_to(Vector2(j[3], j[4])) / 10.0) * 10
		var how:String = Data.JOBS[j[1]].desc + (" durante %d s" % int(Data.JOB_DEFENSE_TIME) if j[1] == "defensa" else "")
		var l := label(info, "%s. A %d m · riesgo %s · recompensa +%d materiales y +%d fichas para todos" % [how, d, j[10], j[6], j[7]], 14, St.INK_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 420
		var id:int = j[0]
		match int(j[5]):
			0: button(r, "Aceptar", func(): action.emit("job_accept", [id]), 40).custom_minimum_size.x = 120
			1: button(r, "Abandonar", func(): action.emit("job_abandon", [id]), 40).custom_minimum_size.x = 120
			2: label(r, "✔ Cumplido", 16, St.MINT.darkened(0.3))
			3: label(r, "✘ Fallido", 16, St.CORAL.darkened(0.2))
	var cm:Array = s.get("cm", [])
	if cm.is_empty(): return
	title(board_list, "Comunidad: ¿dónde trabaja cada vecino?", Color("8b5e3c"), 20)
	var cp:Array = s.get("cp", [])
	for m in cm.size():
		var row := hbox(board_list, 10)
		var kind:int = cm[m]
		var where:int = cp[m] if m < cp.size() else -1
		var l2 := label(row, "%s · en casa: %s" % [Data.SURVIVORS[kind].name, Data.SURVIVORS[kind].desc.to_lower()], 14, St.INK_SOFT)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.custom_minimum_size.x = 380
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var opt := OptionButton.new()
		opt.add_item("En casa", -1)
		for i in Data.SITES.size():
			if s.si[i][0]: opt.add_item("En %s (+50 %%)" % Data.SITES[i].name, i)
		for idx in opt.item_count:
			if opt.get_item_id(idx) == where: opt.select(idx)
		var member := m
		opt.item_selected.connect(func(idx): action.emit("assign", [member, opt.get_item_id(idx)]))
		opt.focus_mode = Control.FOCUS_NONE
		row.add_child(opt)

func goal_text(s:Dictionary) -> String:
	var pcs:Array = s.get("pc", [])
	if pcs.is_empty(): return ""
	if s.get("vic", false): return "✦ ¡La verbena está encendida!"
	if s.get("fin", -1.0) > 0: return "✦ ¡La gran verbena! Aguantad %d s" % ceili(s.fin)
	var done := 0
	var missing := []
	for i in pcs.size():
		if pcs[i][0] == 4: done += 1
		else: missing.append(Data.SITES[Data.PIECES[i].site].name)
	if done == pcs.size(): return "✦ Verbena lista: encendedla en el escenario (E)"
	return "✦ Verbena %d/%d · piezas en %s" % [done, pcs.size(), ", ".join(missing)]

func first_day_steps(s:Dictionary, p:Dictionary) -> Array:
	## Checklist for the first afternoon so new players always know a next step.
	if s.w != 1 or s.ph != P.PREP: return []
	var looted := false
	for v in s.lo: if not v: looted = true
	var front:int = s.fr[0] if s.fr.size() > 0 else 2
	var built := false
	var st:PackedInt32Array = s.st
	for i in range(0, st.size(), 8):
		var c := Vector2(st[i] % 74 - 37 + 0.5, st[i] / 74 - 33 + 0.5)
		var d := c - Map.BASE_CENTER
		var sec := (1 if d.x > 0 else 3) if absf(d.x) > absf(d.y) else (2 if d.y > 0 else 0)
		if sec == front: built = true
	var risky:bool = s.cm.size() > 0 or s.sv.any(func(v): return v[4] == 1)
	for si in s.si: if si[0]: risky = true
	var lines := ["Primer día"]
	lines.append(("✔ " if looted else "▢ ") + "Rebusca donde brilla ✦")
	lines.append(("✔ " if built else "▢ ") + "Construye al %s (%s)" % [Map.FRONT_NAMES[front], k("build")])
	lines.append(("✔ " if risky else "▢ ") + "Rescata o conquista (%s)" % k("claim"))
	lines.append(("✔ " if p.ready else "▢ ") + "Toca la campana (%s)" % k("ready"))
	return lines

func alert_text(s:Dictionary) -> String:
	## Most urgent warning first: the house, then open breaches, then defences under attack.
	var lines := []
	var br:Array = s.get("br", [])
	for i in range(0, br.size(), 3):
		if br[i + 2] > 0: lines.append("⚠ ¡Golpean la casa por el %s!" % Map.FRONT_NAMES[i / 3])
	for i in range(0, br.size(), 3):
		if br[i + 1] > 0: lines.append("⚠ Brecha al %s: reconstruid una defensa" % Map.FRONT_NAMES[i / 3])
	for i in range(0, br.size(), 3):
		if br[i] > 0 and br[i + 1] == 0: lines.append("Defensa del %s bajo ataque" % Map.FRONT_NAMES[i / 3])
	var sh:Array = s.get("sh", [])
	for i in sh.size():
		if sh[i] > 0: lines.append("Atacan el estandarte de %s" % Data.SITES[i].name)
	return "\n".join(lines.slice(0, 3))

func weakest_access(s:Dictionary) -> String:
	## Sum of standing defence health per side of the house.
	var hp := [0, 0, 0, 0]
	var count := [0, 0, 0, 0]
	var st:PackedInt32Array = s.st
	for i in range(0, st.size(), 8):
		if not Data.STRUCTURES[st[i + 1]].block and st[i + 1] != Data.S_WIRE: continue
		var c := Vector2(st[i] % 74 - 37 + 0.5, st[i] / 74 - 33 + 0.5)
		if c.distance_to(Map.BASE_CENTER) > Map.BASE_BUILD_RADIUS + 1: continue
		var d := c - Map.BASE_CENTER
		var sec := (1 if d.x > 0 else 3) if absf(d.x) > absf(d.y) else (2 if d.y > 0 else 0)
		hp[sec] += st[i + 3]
		count[sec] += 1
	var weakest := 0
	for i in 4: if hp[i] < hp[weakest]: weakest = i
	return "Acceso más débil: %s (%d defensas, %d de resistencia)" % [Map.FRONT_NAMES[weakest], count[weakest], hp[weakest]]

func bigmap_world(pos:Vector2):
	## World point under a screen position on the big map, or null outside it.
	if not map_panel.visible or map_panel.scale.x < 0.98: return null
	var r := bigmap.get_global_rect()
	if not r.has_point(pos): return null
	return map3d.ground_at(true, pos - r.position)

func map_text(s:Dictionary) -> String:
	var lines := []
	for i in Data.SITES.size():
		var si:Array = s.si[i]
		lines.append("%s %s\n   %s" % ["★" if si[0] else "·", Data.SITES[i].name + (" (%d%%)" % int(100.0 * si[1] / si[2]) if si[0] else ""), Data.SITES[i].bonus])
	lines.append("")
	lines.append(goal_text(s))
	lines.append("Cada pieza aparece al conquistar su propiedad: llevadla al escenario de la plaza.")
	lines.append(weakest_access(s))
	lines.append("Conquistar cuesta %d materiales (%s junto al estandarte, de día y sin brotados cerca)." % [s.cc, k("claim")])
	lines.append("")
	lines.append("Norte arriba · ◇ estandarte · • brotado · ✚ compañero caído")
	lines.append("Clic en el plano para señalar · %s pedir apoyo · %s para cerrar" % [k("ping"), k("map")])
	if s.cm.size() > 0:
		var names := []
		for k in s.cm: names.append(Data.SURVIVORS[k].name)
		lines.append("Comunidad: " + ", ".join(names))
	return "\n".join(lines)

# ================================================================== drawing
func world_to_map(_c:Control, p:Vector2, big:bool, h:float = 0.6) -> Vector2:
	## Projects a world point through the 3D map camera.
	return map3d.project(big, Vector3(p.x, h, p.y))

func proj_ring(c:Control, big:bool, center:Vector2, radius:float, col:Color, width:float, a0:float = 0.0, a1:float = TAU):
	var pts := PackedVector2Array()
	var steps := maxi(8, int(absf(a1 - a0) / TAU * 48.0))
	for i in steps + 1:
		var a := a0 + (a1 - a0) * i / steps
		pts.append(world_to_map(c, center + Vector2(cos(a), sin(a)) * radius, big, 0.15))
	c.draw_polyline(pts, col, width, true)

func map_dot(c:Control, pos:Vector2, r:float, col:Color):
	c.draw_circle(pos + Vector2(0, 1.5), r + 1.5, Color(St.INK, 0.35))
	c.draw_circle(pos, r + 1.5, St.INK)
	c.draw_circle(pos, r, col)

func draw_map(c:Control, big:bool):
	var s := last_state
	if s.is_empty(): return
	c.draw_texture_rect(map3d.texture(big), Rect2(Vector2.ZERO, c.size), false)
	var k := map3d.scale_at(big, Vector2.ZERO if big else mm_data.get("me", Vector2.ZERO))
	var kk := clampf(k / 9.0, 0.7, 1.6)
	for i in Map.SITES.size():
		var si:Array = s.si[i]
		var col := Color(Data.SITES[i].color) if si[0] else Color("8a8f9c")
		var b := world_to_map(c, Map.SITES[i].beacon, big, 1.0)
		if si[0]: proj_ring(c, big, Map.SITES[i].beacon, Map.SITE_BUILD_RADIUS, Color(1, 1, 1, 0.7), 2.0)
		map_dot(c, b, (7.0 if big else 4.5) * kk, col.lightened(0.3))
		if big: St.text(c, b + Vector2(10, -8), Data.SITES[i].name, 14, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, St.INK)
	proj_ring(c, big, Map.BASE_CENTER, Map.BASE_BUILD_RADIUS, Color(1, 1, 1, 0.55), 2.0)
	if big:
		for i in Map.LOOT.size():
			if s.lo[i]: c.draw_circle(world_to_map(c, Map.LOOT[i].p, big, 0.4), 3.0, Color("fff3b0"))
	for f in s.fr:
		for pt in Map.FRONTS[f]:
			var m := world_to_map(c, pt.clamp(Vector2(-36, -32), Vector2(36, 32)), big)
			c.draw_circle(m, (7.0 if big else 4.5) * kk, Color(1, 0.3, 0.3, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)))
	var en:PackedFloat32Array = s.en
	for i in range(0, en.size(), 8):
		var kind := int(en[i + 1])
		var ep := world_to_map(c, Vector2(en[i + 2], en[i + 3]), big, 0.8 if kind != 7 else 2.0)
		var ecol := Color("ff4d6d") if int(en[i + 6]) & 4 == 0 else Color("b07a8a")
		if kind == 8: ecol = Color("b9a6ff")
		var er := 6.0 if kind == 7 else (4.0 if kind == 8 else 2.6)
		c.draw_circle(ep, er * kk * (1.3 if big else 1.0), St.INK)
		c.draw_circle(ep, (er - 1.0) * kk * (1.3 if big else 1.0), ecol)
	for sv in s.sv: St.text(c, world_to_map(c, Vector2(sv[1], sv[2]), big, 2.0) + Vector2(-5, 7), "!", 20, St.SUN, "title", 700, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, St.INK)
	for d in s.dr: map_dot(c, world_to_map(c, Vector2(d[1], d[2]), big, 0.8), 5.0 * kk, Color("4cc9f0"))
	var stage_pos := world_to_map(c, Map.STAGE, big, 0.6)
	c.draw_style_box(St.card(Color("e8665a"), 4, St.INK, 2, 0), Rect2(stage_pos - Vector2(9, 5), Vector2(18, 10)))
	for j in s.get("jobs", []):
		if j[5] != 1 or not j[12]: continue
		var jm := world_to_map(c, Vector2(j[3], j[4]), big, 1.2)
		c.draw_style_box(St.card(St.MINT, 3, St.INK, 2, 0), Rect2(jm - Vector2(6, 6), Vector2(12, 12)))
		if big: St.text(c, jm + Vector2(10, 5), "Encargo", 13, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, St.INK)
	var pcs:Array = s.get("pc", [])
	for i in pcs.size():
		if pcs[i][0] == 0 or pcs[i][0] == 4: continue
		var pm := world_to_map(c, Vector2(pcs[i][1], pcs[i][2]), big, 1.0)
		map_dot(c, pm, (7.0 if big else 4.5) * kk, Color(Data.PIECES[i].color))
		if big: St.text(c, pm + Vector2(10, 5), Data.PIECES[i].name, 13, Color.WHITE, "title", 600, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, St.INK)
	var br:Array = s.get("br", [])
	for i in range(0, br.size(), 3):
		if br[i] > 0 or br[i + 1] > 0 or br[i + 2] > 0:
			var mid:float = [-PI * 0.5, 0.0, PI * 0.5, PI][i / 3]
			var bcol := CORAL if br[i + 1] > 0 or br[i + 2] > 0 else Color("ffb35c")
			proj_ring(c, big, Map.BASE_CENTER, Map.BASE_BUILD_RADIUS, bcol, 5.0, mid - 0.6, mid + 0.6)
	for pid in s.pl:
		var q:Dictionary = s.pl[pid]
		if q.ping == null: continue
		var pm := world_to_map(c, q.ping, big, 0.2)
		var col := CORAL if q.st != 0 else Color(SLOT_COLORS[q.slot % 4])
		var pr := 9.0 + 3.0 * sin(Time.get_ticks_msec() * 0.01)
		c.draw_arc(pm, pr, 0, TAU, 20, St.INK, 5.0, true)
		c.draw_arc(pm, pr, 0, TAU, 20, col, 2.5, true)
		c.draw_colored_polygon(PackedVector2Array([pm + Vector2(0, -4), pm + Vector2(4, 0), pm + Vector2(0, 4), pm + Vector2(-4, 0)]), col)
	for pid in s.pl:
		var q:Dictionary = s.pl[pid]
		var pos := world_to_map(c, q.p, big, 1.2)
		var col := Color(SLOT_COLORS[q.slot % 4])
		var mine:bool = pid == my_id
		map_dot(c, pos, (6.5 if mine else 5.0) * kk, col if q.st == 0 else CORAL)
		if q.st != 0:
			c.draw_line(pos - Vector2(5, 5), pos + Vector2(5, 5), St.INK, 2.5)
			c.draw_line(pos - Vector2(5, -5), pos + Vector2(5, -5), St.INK, 2.5)
		if mine:
			var tip := world_to_map(c, q.p + q.aim * 3.0, big, 1.2)
			c.draw_line(pos, tip, St.INK, 4.0, true)
			c.draw_line(pos, tip, col, 2.0, true)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(St.INK, 0.0), false, 2.0)
