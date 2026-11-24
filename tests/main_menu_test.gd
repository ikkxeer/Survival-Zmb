extends SceneTree
## Run with godot --headless -s tests/main_menu_test.gd
var failed := false
var launches := []

func check(ok:bool, message:String):
	if not ok:
		failed = true
		push_error(message)

func _initialize():
	call_deferred("run")

func frames():
	for i in 3: await process_frame

func click(b:Button):
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.position = b.get_global_rect().get_center()
	input.global_position = input.position
	input.pressed = true
	root.push_input(input,true)
	input = input.duplicate()
	input.pressed = false
	root.push_input(input,true)
	await frames()

func run():
	var ui = preload("res://game/interface.gd").new()
	root.add_child(ui)
	ui.launch.connect(func(mode, role, address, nickname): launches.append([mode,role,address,nickname]))
	ui.show_menu(true)
	await frames()
	check(not ui.menu_panel.visible and ui.solo_entry.has_focus(),"La portada debe abrirse en la elección de modo")
	await click(ui.solo_entry)
	check(ui.menu_panel.visible and not ui.join_row.visible,"El modo solitario no necesita una dirección")
	await click(ui.role_cards[2])
	ui.name_edit.text = " Luz "
	await click(ui.start_button)
	check(launches == [["solo",2,"","Luz"]],"Solitario debe conservar el nombre y el oficio")
	ui.close_setup()
	await frames()
	await click(ui.coop_entry)
	await click(ui.start_button)
	check(not launches.is_empty() and launches.back()[0] == "host","Crear partida debe iniciar un anfitrión")
	await click(ui.network_tabs.get_child(1))
	check(ui.join_row.visible and not ui.rules_row.visible,"El invitado solo configura sus propios datos")
	await click(ui.start_button)
	check(launches.size()==2 and ui.address.has_focus() and not ui.status.text.is_empty(),"Una IP vacía debe recibir un error local")
	ui.address.text = " 127.0.0.1 "
	ui.address.text_submitted.emit(ui.address.text)
	check(launches.back() == ["join",2,"127.0.0.1","Luz"],"Intro envía los datos del invitado")
	ui.toggle_panel(ui.help_panel)
	check(ui.modal_shade.visible and ui.help_panel.visible,"La ayuda debe bloquear la portada")
	ui.help_panel.hide()
	check(not ui.modal_shade.visible,"Cerrar la ayuda debe devolver el control")
	root.content_scale_factor = 1.4
	await frames()
	check(ui.root.get_rect().encloses(ui.menu_panel.get_rect()),"El panel debe caber a escala de interfaz máxima")
	quit(1 if failed else 0)
