extends SceneTree
## The shop buttons react to a real click even while the match keeps running,
## and selling works from the interface.
##   godot --headless -s tests/shop_ui_test.gd
var failed := 0
var game

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func _initialize():
	Engine.set_meta("sin_guardar", true)
	call_deferred("run")

func frames(n:int):
	for i in n: await process_frame

func find_button(prefix:String) -> Button:
	var stack:Array = [game.ui.shop_list]
	while stack.size() > 0:
		var n:Node = stack.pop_back()
		if n is Button and (n as Button).text.begins_with(prefix) and not (n as Button).disabled and not n.is_queued_for_deletion(): return n
		stack.append_array(n.get_children())
	return null

func click(b:Button, hold_frames:int):
	## Press, let the game run (state snapshots arrive), then release.
	var at := b.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	root.push_input(down)
	await frames(hold_frames)
	var up := down.duplicate()
	up.pressed = false
	root.push_input(up)
	await frames(3)

func run():
	root.size = Vector2i(1600, 900)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await frames(5)
	game.start("solo", 1, "", "Prueba")
	await frames(20)
	var p:Dictionary = game.sim.players[1]
	p.coins = 60
	game.local_pos = Map.PLAYER_SPAWN
	p.p = Map.PLAYER_SPAWN
	await frames(3)
	game.toggle_shop()
	await frames(5)
	check(game.ui.shop.visible, "La tienda se abre junto a la casa")
	var b := find_button("Comprar · 12")
	check(b != null, "Aparece el botón de comprar el trabuco")
	if b: await click(b, 25)
	check(p.guns.has(1) and p.coins == 48, "Un clic largo compra aunque la partida siga")
	game.ui.shop_tabs[3].emit_signal("pressed")
	await frames(3)
	var sell := find_button("Vender · +6")
	check(sell != null, "La pestaña Vender ofrece el trabuco")
	if sell: await click(sell, 10)
	check(not p.guns.has(1) and p.coins == 54, "Vender desde la tienda devuelve fichas")
	game.toggle_shop()
	await frames(2)
	check(not game.ui.shop.visible, "La tienda se cierra")
	print("%d fallos" % failed)
	quit(1 if failed > 0 else 0)

const Map = preload("res://game/map.gd")
