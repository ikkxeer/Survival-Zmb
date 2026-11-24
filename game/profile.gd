extends RefCounted
## Progress kept between matches: experience per role, ranks with unlocks, wins.
## Saved in user://perfil.cfg with a version. Writes go to a temporary file that
## replaces the old one only when complete, and the previous copy is kept as .bak,
## so closing the game while saving never loses more than the last update.

const PATH := "user://perfil.cfg"
const VERSION := 1
const RANKS = [0, 120, 350, 700]
const UNLOCKS = [
	["Empieza con 4 materiales extra para el equipo", "Vida máxima +15"],
	["Empieza con 3 botiquines", "Vida máxima +15"],
	["Empieza con el Trabuco de confeti", "Vida máxima +15"],
	["Empieza con 8 fichas extra", "Vida máxima +15"],
]

var role_xp := [0, 0, 0, 0]
var matches := 0
var wins := 0
var best_night := 0

static func rank_for(xp:int) -> int:
	var r := 1
	for i in RANKS.size():
		if xp >= RANKS[i]: r = i + 1
	return mini(r, RANKS.size())

func rank(role:int) -> int:
	return rank_for(role_xp[clampi(role, 0, 3)])

func next_goal(role:int) -> int:
	var r := rank(role)
	return RANKS[r] if r < RANKS.size() else -1

func unlocked(role:int) -> Array:
	## Descriptions of the perks earned so far for a role (rank 2 onwards).
	var out := []
	var r := rank(role)
	for i in range(2, r + 1):
		if i - 2 < UNLOCKS[role].size(): out.append(UNLOCKS[role][i - 2])
	return out

func add_xp(role:int, amount:int) -> bool:
	## Returns true when the role reaches a new rank.
	var before := rank(role)
	role_xp[clampi(role, 0, 3)] += maxi(0, amount)
	return rank(role) > before

func load_file() -> bool:
	for path in [PATH, PATH + ".bak"]:
		if read(path): return true
	return false

func read(path:String) -> bool:
	if not FileAccess.file_exists(path): return false
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK: return false
	var v = cfg.get_value("meta", "version", -1)
	if not (v is int) or v < 1 or v > VERSION: return false
	var xp = cfg.get_value("perfil", "experiencia", null)
	if not (xp is Array) or xp.size() != 4: return false
	for i in 4:
		if not (xp[i] is int) or xp[i] < 0: return false
	role_xp = xp.duplicate()
	matches = int(cfg.get_value("perfil", "partidas", 0))
	wins = int(cfg.get_value("perfil", "victorias", 0))
	best_night = int(cfg.get_value("perfil", "mejor_noche", 0))
	return true

func save_file() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("perfil", "experiencia", role_xp)
	cfg.set_value("perfil", "partidas", matches)
	cfg.set_value("perfil", "victorias", wins)
	cfg.set_value("perfil", "mejor_noche", best_night)
	var tmp := PATH + ".tmp"
	if cfg.save(tmp) != OK: return false
	var real := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(real + ".bak")
		DirAccess.rename_absolute(real, real + ".bak")
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real) == OK
