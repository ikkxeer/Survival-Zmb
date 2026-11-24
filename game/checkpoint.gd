extends RefCounted
## Dawn checkpoint of a match (solo or host) so an interrupted session can continue.
## Same safety as the profile: temporary file, atomic rename and a .bak of the previous one.

const PATH := "user://partida.sav"
const VERSION := 1

static func exists() -> bool:
	return peek() != {}

static func peek() -> Dictionary:
	## Summary for the menu without loading the whole match.
	var d := read_any()
	if d.is_empty(): return {}
	return {"wave": d.wave, "players": d.players.keys(), "mode": d.get("mode", "solo"), "date": d.get("date", "")}

static func read_any() -> Dictionary:
	for p in [PATH, PATH + ".bak"]:
		var d := read(p)
		if not d.is_empty(): return d
	return {}

static func read(path:String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8: return {}
	var data = bytes_to_var(bytes)
	if not (data is Dictionary) or data.get("version", -1) != VERSION: return {}
	for key in ["wave", "players", "structures", "sites", "pieces", "materials", "core"]:
		if not data.has(key): return {}
	return data

static func write(data:Dictionary) -> bool:
	data["version"] = VERSION
	data["date"] = Time.get_datetime_string_from_system()
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return false
	f.store_buffer(var_to_bytes(data))
	f = null
	var real := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(real + ".bak")
		DirAccess.rename_absolute(real, real + ".bak")
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real) == OK

static func clear():
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
