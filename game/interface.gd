extends CanvasLayer
signal launch(mode:String,role:int,address:String)
signal graphics_changed(high:bool)
signal leave
var menu := PanelContainer.new()
var role := OptionButton.new()
var address := LineEdit.new()
var status := Label.new()
var hud := MarginContainer.new()
var banner := Label.new()
var stats := Label.new()
var guide := Label.new()
var msg := Label.new()
var quit := Button.new()
var help := true

func panel(color:String,margin:int):
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color)
	s.set_corner_radius_all(12)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s

func label(parent:Control,value:String,size:int,color:String):
	var l := Label.new()
	parent.add_child(l)
	l.text = value
	l.add_theme_font_size_override("font_size",size)
	l.modulate = Color(color)
	return l

func button(parent:Control,caption:String,callback:Callable):
	var b := Button.new()
	parent.add_child(b)
	b.text = caption
	b.custom_minimum_size.y = 37
	b.pressed.connect(callback)
	return b

func launch_mode(mode:String):
	launch.emit(mode,role.selected,address.text.strip_edges())

func _ready():
	add_child(menu)
	menu.position = Vector2(46,44)
	menu.custom_minimum_size.x = 390
	menu.add_theme_stylebox_override("panel",panel("203c45f4",25))
	var stack := VBoxContainer.new()
	menu.add_child(stack)
	stack.add_theme_constant_override("separation",8)
	label(stack,"COOPERATIVO  /  1–4",15,"f5c573")
	label(stack,"La última verbena",36,"fff2d6")
	label(stack,"Defiende la casa hasta el amanecer.",17,"d4e6de")
	label(stack,"Tu papel en el barrio",15,"f5c573")
	stack.add_child(role)
	for r in preload("res://game/match.gd").ROLES: role.add_item(r)
	button(stack,"Jugar en solitario",launch_mode.bind("solo"))
	button(stack,"Crear partida en red",launch_mode.bind("host"))
	stack.add_child(address)
	address.placeholder_text = "Dirección IP del anfitrión"
	button(stack,"Conectarse",launch_mode.bind("join"))
	var quality := CheckButton.new()
	stack.add_child(quality)
	quality.text = "Sombras y suavizado de bordes"
	quality.button_pressed = true
	quality.toggled.connect(func(high): graphics_changed.emit(high))
	stack.add_child(status)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color("ffdc91")
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left","top","right","bottom"]: hud.add_theme_constant_override("margin_"+edge,18)
	var col := VBoxContainer.new()
	hud.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var card := PanelContainer.new()
	top.add_child(card)
	card.add_theme_stylebox_override("panel",panel("203c45ed",12))
	var lines := VBoxContainer.new()
	card.add_child(lines)
	lines.add_child(banner)
	banner.add_theme_font_size_override("font_size",22)
	banner.modulate = Color("ffdc95")
	lines.add_child(stats)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(space)
	top.add_child(quit)
	quit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	quit.text = "Volver al menú"
	quit.pressed.connect(func(): leave.emit())
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	col.add_child(msg)
	msg.add_theme_constant_override("outline_size",6)
	var footer := PanelContainer.new()
	col.add_child(footer)
	footer.add_theme_stylebox_override("panel",panel("203c45ed",10))
	footer.add_child(guide)
	hud.hide()

func render(s:Dictionary,id:int):
	if not s.players.has(id): return
	var p = s.players[id]
	banner.text = "%s   /   OLEADA %02d" % [s.phase.to_upper(),s.wave]
	if s.phase == "Noche": banner.text += "   ·   %d intrusos   ·   %s" % [s.remaining,s.event]
	elif s.phase != "Fin": banner.text += "   ·   %ds" % ceili(maxf(0,s.clock))
	stats.text = "Casa %d%%    Salud %d    Materiales %d    Fichas %d    Equipo %d/4" % [ceili(s.core),ceili(p.hp),s.wood,p.coins,s.players.size()]
	msg.text = p.notice if p.message_time > 0 else ""
	if p.hp <= 0: msg.text = "Has caído. Un compañero puede levantarte con E."
	if s.phase == "Fin": msg.text = "La verbena ha terminado. Llegasteis a la oleada %d." % s.wave
	var ctl = preload("res://game/match.gd")
	var tool:String = ctl.WEAPONS[p.gun]
	guide.text = "%s   ·   %s   ·   M plano   ·   G apoyo   ·   F1 controles" % [ctl.ROLES[p.role],tool]
	if help:
		guide.text += "   ·   C conquistar (8 materiales)   ·   R reforzar (4)"
		guide.text += "\nWASD moverse   ·   Izq. disparar   ·   Arrastra con der. para girar   ·   Rueda zoom   ·   E recoger, reparar o reanimar"
		guide.text += "\nEn plataforma: B barricada (%d) / T bobina (%d)   ·   En casa: 1 lanzacorchos / 2 trabuco (9 fichas) / 3 carabina (14)" % [2 if p.role == 0 else 3,6 if p.role == 0 else 7]
