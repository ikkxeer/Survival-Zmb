extends RefCounted
## Player preferences: graphics, audio, comfort and key bindings.
## Saved to user://ajustes.cfg with a version so future releases can migrate it.

const PATH := "user://ajustes.cfg"
const VERSION := 2

const ACTIONS = [
	["up", "Avanzar", KEY_W], ["down", "Retroceder", KEY_S], ["left", "Izquierda", KEY_A], ["right", "Derecha", KEY_D],
	["sprint", "Correr", KEY_SHIFT], ["roll", "Voltereta", KEY_SPACE], ["use", "Usar (mantener)", KEY_E],
	["reload", "Recargar", KEY_R], ["ability", "Habilidad", KEY_Q], ["grenade", "Traca", KEY_F],
	["medkit", "Botiquín", KEY_H], ["melee", "Sartenazo", KEY_V], ["build", "Construir", KEY_B],
	["shop", "Tienda", KEY_T], ["claim", "Conquistar", KEY_C], ["map", "Plano", KEY_M],
	["ping", "Pedir apoyo", KEY_G], ["ready", "Listo / campana", KEY_N], ["demolish", "Desmontar", KEY_X],
]

var values := {
	"quality": 2, "fullscreen": false, "volume": 0.8, "music": 0.6, "sfx": 1.0,
	"shake": true, "flashes": true, "numbers": false, "sensitivity": 1.0, "ui_scale": 1.0, "name": "",
	"captions": true, "colorblind": false,
}
var binds := {}

func _init():
	for a in ACTIONS: binds[a[0]] = a[2]

func load_file() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK: return false
	var version := int(cfg.get_value("meta", "version", 0))
	if version > VERSION: return false
	for k in values:
		var v = cfg.get_value("ajustes", k, values[k])
		if typeof(v) == typeof(values[k]) or (values[k] is float and v is int): values[k] = v
	# v2: the cleaner interface hides damage numbers unless the player turns them back on
	if version < 2: values.numbers = false
	for a in ACTIONS:
		var code = cfg.get_value("teclas", a[0], a[2])
		if code is int and code > 0: binds[a[0]] = code
	return true

func save_file() -> bool:
	## Write to a temporary file first so a crash never leaves a half-written config.
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	for k in values: cfg.set_value("ajustes", k, values[k])
	for k in binds: cfg.set_value("teclas", k, binds[k])
	var tmp := PATH + ".tmp"
	if cfg.save(tmp) != OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH)) == OK

func key_of(action:String) -> int:
	return binds.get(action, 0)

func action_for(code:int) -> String:
	for k in binds:
		if binds[k] == code: return k
	return ""

func pressed(action:String) -> bool:
	return Input.is_physical_key_pressed(binds.get(action, 0))

func key_name(action:String) -> String:
	var code:int = binds.get(action, 0)
	match code:
		KEY_SPACE: return "Espacio"
		KEY_SHIFT: return "Mayús"
		KEY_TAB: return "Tab"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
	return OS.get_keycode_string(code)

func rebind(action:String, code:int) -> String:
	## Assign a key; if another action used it, the two swap. Returns the swapped action or "".
	if code in [KEY_ESCAPE, KEY_F1] or not binds.has(action): return ""
	var other := action_for(code)
	if other != "" and other != action: binds[other] = binds[action]
	binds[action] = code
	return other if other != action else ""

func reset_binds():
	for a in ACTIONS: binds[a[0]] = a[2]
