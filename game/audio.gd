extends Node
## Self-contained audio: every effect is synthesised at start-up and the music is a
## tiny real-time sequencer (a festive waltz by day, a tense pulse by night).

const RATE := 22050
var bank := {}
var players3d := []
var players2d := []
var p3i := 0
var p2i := 0
var ambient := {}
var music_mode := 0          # 0 day, 1 night, 2 menu
var music_level := 0.0
var music_target := 1.0
var intensity := 0.0
var rng := RandomNumberGenerator.new()
var master := 1.0
var music_volume := 0.7
var sfx := 1.0

func _ready():
	rng.seed = 3
	build_bank()
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 60.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "Master"
		add_child(p)
		players3d.append(p)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players2d.append(p)
	for name in ["birds", "crickets", "rain"]:
		var p := AudioStreamPlayer.new()
		p.stream = bank[name]
		p.volume_db = -80
		add_child(p)
		p.play()
		ambient[name] = p
	start_music()

# ------------------------------------------------------------------ synthesis helpers
func wav(samples:PackedFloat32Array, loop:bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.mix_rate = RATE
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = samples.size()
	return s

func synth(length:float, f:Callable) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		out[i] = f.call(t, i)
	return out

func noise() -> float:
	return rng.randf() * 2.0 - 1.0

func lowpass(src:PackedFloat32Array, k:float) -> PackedFloat32Array:
	var y := 0.0
	for i in src.size():
		y += (src[i] - y) * k
		src[i] = y
	return src

func gain(src:PackedFloat32Array, g:float) -> PackedFloat32Array:
	for i in src.size(): src[i] *= g
	return src

func mix(a:PackedFloat32Array, b:PackedFloat32Array, offset:float = 0.0) -> PackedFloat32Array:
	var o := int(offset * RATE)
	if a.size() < b.size() + o: a.resize(b.size() + o)
	for i in b.size(): a[i + o] += b[i]
	return a

func build_bank():
	bank.cork = wav(synth(0.16, func(t, i): return (sin(TAU * (900.0 * t - 2600.0 * t * t)) * 0.7 + noise() * 0.4 * exp(-90 * t)) * exp(-28 * t)))
	bank.shotgun = wav(gain(mix(lowpass(synth(0.45, func(t, i): return noise() * exp(-9 * t)), 0.35), synth(0.3, func(t, i): return sin(TAU * 70 * t) * exp(-12 * t))), 0.9))
	bank.smg = wav(lowpass(synth(0.09, func(t, i): return (noise() * 0.8 + sin(TAU * 220 * t) * 0.5) * exp(-45 * t)), 0.6))
	bank.rifle = wav(mix(lowpass(synth(0.22, func(t, i): return noise() * exp(-22 * t)), 0.55), synth(0.12, func(t, i): return sin(TAU * 140 * t) * exp(-30 * t) * 0.6)))
	bank.sniper = wav(mix(lowpass(synth(0.7, func(t, i): return noise() * exp(-6 * t)), 0.4), synth(0.5, func(t, i): return sin(TAU * (180 - 120 * t) * t) * exp(-7 * t))))
	bank.launch = wav(mix(lowpass(synth(0.3, func(t, i): return noise() * exp(-14 * t)), 0.15), synth(0.3, func(t, i): return sin(TAU * (120 - 160 * t) * t) * exp(-9 * t))))
	bank.flame = wav(lowpass(synth(0.25, func(t, i): return noise() * 0.6 * (1.0 - t * 2.0)), 0.25))
	bank.turret = wav(synth(0.1, func(t, i): return signf(sin(TAU * (1400 - 6000 * t) * t)) * 0.35 * exp(-30 * t)))
	bank.zap = wav(synth(0.22, func(t, i): return (signf(sin(TAU * 90 * t)) * 0.4 + noise() * 0.5) * (0.6 + 0.4 * sin(TAU * 40 * t)) * exp(-9 * t)))
	bank.hit = wav(lowpass(synth(0.1, func(t, i): return (noise() * 0.7 + sin(TAU * 160 * t)) * exp(-40 * t)), 0.4))
	bank.pop = wav(mix(synth(0.18, func(t, i): return sin(TAU * (300 + 2400 * t) * t) * exp(-18 * t) * 0.8), synth(0.35, func(t, i): return (sin(TAU * 1568 * t) + sin(TAU * 2093 * t)) * 0.18 * exp(-10 * t)), 0.05))
	bank.explosion = wav(mix(lowpass(synth(1.1, func(t, i): return noise() * exp(-4.5 * t)), 0.12), synth(0.8, func(t, i): return sin(TAU * (60 - 30 * t) * t) * exp(-5 * t))))
	bank.swing = wav(lowpass(synth(0.22, func(t, i): return noise() * sin(PI * t / 0.22) * 0.6), 0.2))
	bank.clang = wav(synth(0.5, func(t, i): return (sin(TAU * 523 * t) + 0.6 * sin(TAU * 1247 * t) + 0.4 * sin(TAU * 2011 * t)) * 0.3 * exp(-9 * t)))
	for v in 3:
		var base:float = [95.0, 120.0, 75.0][v]
		bank["groan%d" % v] = wav(lowpass(synth(0.8, func(t, i):
			var f:float = base * (1.0 + 0.06 * sin(TAU * 5 * t) - 0.15 * t)
			var s := 0.0
			for h in range(1, 7): s += sin(TAU * f * h * t) / h * (1.4 if h == 3 or h == 4 else 0.7)
			return s * 0.3 * sin(PI * minf(1.0, t / 0.8)) + noise() * 0.03
		), 0.35))
	var knocks := PackedFloat32Array()
	for k in 3: knocks = mix(knocks, lowpass(synth(0.12, func(t, i): return (noise() * 0.6 + sin(TAU * 260 * t)) * exp(-35 * t)), 0.5), k * 0.14)
	bank.build = wav(knocks)
	bank.crash = wav(mix(lowpass(synth(0.6, func(t, i): return noise() * exp(-7 * t)), 0.3), synth(0.4, func(t, i): return sin(TAU * 110 * t) * exp(-10 * t) * 0.5)))
	bank.coin = wav(mix(synth(0.12, func(t, i): return sin(TAU * 1318 * t) * exp(-20 * t) * 0.5), synth(0.35, func(t, i): return sin(TAU * 1975 * t) * exp(-9 * t) * 0.5), 0.07))
	var arp := PackedFloat32Array()
	for k in 4: arp = mix(arp, synth(0.4, func(t, i): return sin(TAU * [523.0, 659.0, 784.0, 1046.0][k] * t) * exp(-6 * t) * 0.35), k * 0.09)
	bank.levelup = wav(arp)
	var horn := PackedFloat32Array()
	for k in 3:
		var notes:Array = [[392.0, 494.0, 587.0], [349.0, 440.0, 523.0], [330.0, 415.0, 494.0]][k]
		horn = mix(horn, synth(0.55 if k < 2 else 1.1, func(t, i):
			var s := 0.0
			for f in notes: s += (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2 * t) + 0.2 * sin(TAU * f * 3 * t))
			return s * 0.1 * minf(1.0, t * 30.0) * exp(-1.6 * t)
		), k * 0.32)
	bank.horn = wav(horn)
	var dawn := PackedFloat32Array()
	for k in 5: dawn = mix(dawn, synth(0.9, func(t, i): return (sin(TAU * [523.0, 659.0, 784.0, 988.0, 1046.0][k] * t) + 0.3 * sin(TAU * [523.0, 659.0, 784.0, 988.0, 1046.0][k] * 2.01 * t)) * exp(-4 * t) * 0.25), k * 0.12)
	bank.dawn = wav(dawn)
	bank.click = wav(synth(0.04, func(t, i): return sin(TAU * 1800 * t) * exp(-80 * t) * 0.4))
	bank.reload = wav(mix(synth(0.05, func(t, i): return noise() * exp(-90 * t) * 0.6), synth(0.06, func(t, i): return noise() * exp(-90 * t) * 0.7), 0.18))
	bank.heal = wav(synth(0.5, func(t, i): return (sin(TAU * 880 * t) + sin(TAU * 1320 * t)) * 0.2 * exp(-5 * t) * (0.7 + 0.3 * sin(TAU * 12 * t))))
	bank.spit = wav(lowpass(synth(0.25, func(t, i): return sin(TAU * (400 - 1200 * t) * t) * exp(-10 * t) + noise() * 0.2 * exp(-20 * t)), 0.5))
	bank.splat = wav(lowpass(synth(0.25, func(t, i): return noise() * exp(-16 * t)), 0.25))
	bank.thunder = wav(lowpass(synth(2.0, func(t, i): return noise() * (exp(-2.5 * t) + 0.3 * exp(-0.8 * t) * (0.5 + 0.5 * sin(TAU * 3 * t))) * 0.8), 0.06))
	bank.down = wav(synth(0.7, func(t, i): return sin(TAU * (440 - 260 * t) * t) * 0.35 * exp(-3 * t)))
	bank.alarm = wav(synth(0.4, func(t, i): return signf(sin(TAU * (880 if fmod(t, 0.2) < 0.1 else 660) * t)) * 0.18 * exp(-2 * t)))
	bank.claim = wav(mix(bank_arp([392.0, 523.0, 659.0, 784.0]), synth(0.6, func(t, i): return sin(TAU * 1046 * t) * 0.2 * exp(-4 * t)), 0.36))
	bank.bell = wav(synth(1.6, func(t, i): return (sin(TAU * 523 * t) + 0.6 * sin(TAU * 1310 * t) * exp(-3 * t) + 0.4 * sin(TAU * 2093 * t) * exp(-5 * t) + 0.3 * sin(TAU * 262 * t)) * 0.28 * exp(-2.2 * t) * minf(1.0, t * 200.0)))
	bank.fuse = wav(synth(0.3, func(t, i): return noise() * 0.3 * (0.5 + 0.5 * signf(sin(TAU * 30 * t)))))
	bank.birds = wav(synth(4.0, func(t, i):
		var s := 0.0
		for c in [[0.3, 3200.0], [1.4, 2700.0], [2.2, 3600.0], [3.1, 2900.0]]:
			var dt:float = t - c[0]
			if dt > 0 and dt < 0.25: s += sin(TAU * (c[1] + 900 * sin(TAU * 18 * dt)) * dt) * sin(PI * dt / 0.25) * 0.12
		return s
	), true)
	bank.crickets = wav(synth(2.0, func(t, i):
		var s := 0.0
		for c in [[0.0, 4200.0], [0.7, 4500.0], [1.3, 4100.0]]:
			var dt := fmod(t - c[0] + 2.0, 2.0)
			if dt < 0.3: s += sin(TAU * c[1] * t) * (0.5 + 0.5 * signf(sin(TAU * 32 * dt))) * 0.05
		return s
	), true)
	bank.rain = wav(lowpass(synth(2.0, func(t, i): return noise() * 0.35), 0.4), true)

func bank_arp(freqs:Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in freqs.size():
		out = mix(out, synth(0.35, func(t, i): return (sin(TAU * freqs[k] * t) + 0.3 * sin(TAU * freqs[k] * 3 * t)) * exp(-6 * t) * 0.25), k * 0.09)
	return out

# ------------------------------------------------------------------ playback
func play(name:String, at = null, volume:float = 0.0, pitch:float = 1.0):
	if not bank.has(name): return
	if at is Vector3:
		var p:AudioStreamPlayer3D = players3d[p3i]
		p3i = (p3i + 1) % players3d.size()
		p.stream = bank[name]
		p.global_position = at
		p.volume_db = volume + linear_to_db(maxf(master * sfx, 0.001))
		p.pitch_scale = pitch * rng.randf_range(0.95, 1.05)
		p.play()
	else:
		var p:AudioStreamPlayer = players2d[p2i]
		p2i = (p2i + 1) % players2d.size()
		p.stream = bank[name]
		p.volume_db = volume + linear_to_db(maxf(master * sfx, 0.001))
		p.pitch_scale = pitch
		p.play()

func set_ambience(day:float, wet:float, active:bool):
	var m := linear_to_db(maxf(master, 0.001))
	ambient.birds.volume_db = (-20.0 + m) if active and day > 0.5 and wet < 0.5 else -80.0
	ambient.crickets.volume_db = (-24.0 + m) if active and day < 0.5 else -80.0
	ambient.rain.volume_db = (-14.0 + m) if active and wet > 0.3 else -80.0

# ------------------------------------------------------------------ music
## Loops are rendered note by note in a worker thread at start-up, then cross-faded.
const SCALE_MAJOR = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
const DAY_MELODY = [4, -1, 2, 4, 5, 4, 2, -1, 0, 1, 2, 4, 3, -1, 1, -1, 4, 5, 7, 5, 4, 2, 3, 2, 1, 0, 1, 2, 0, -1, -1, -1,
	7, -1, 5, 4, 5, 7, 8, -1, 7, 5, 4, 2, 4, -1, -1, -1, 2, 3, 4, 5, 4, 2, 1, 2, 0, -1, 4, -1, 0, -1, -1, -1]
const DAY_CHORDS = [0, 0, 5, 5, 7, 7, 0, 0, 5, 5, 0, 0, 7, 7, 0, 0]
const NIGHT_BASS = [0, 0, 3, 0, 5, 0, 3, 2]
var tracks := {}
var music_task := -1
var track_players := {}

func midi(n:float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)

func start_music():
	for name in ["day", "night", "combat"]:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80
		add_child(p)
		track_players[name] = p
	music_task = WorkerThreadPool.add_task(render_all)

func _exit_tree():
	if music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(music_task)
		music_task = -1

func render_all():
	var day := render(0)
	var night := render(1)
	var combat := render(2)
	call_deferred("music_ready", day, night, combat)

func music_ready(day:PackedFloat32Array, night:PackedFloat32Array, combat:PackedFloat32Array):
	track_players.day.stream = wav(day, true)
	track_players.night.stream = wav(night, true)
	track_players.combat.stream = wav(combat, true)
	for p in track_players.values(): p.play()

func note(buf:PackedFloat32Array, at:float, freq:float, amp:float, decay:float, kind:int):
	var start := int(at * RATE)
	var length := mini(int(minf(7.0 / decay, 3.0) * RATE), buf.size() - start)
	var w := TAU * freq / RATE
	var r := RandomNumberGenerator.new()
	for k in length:
		var t := float(k) / RATE
		var env := minf(1.0, t * 80.0) * exp(-decay * t) * amp
		var ph := w * k
		var v := 0.0
		match kind:
			0: v = sin(ph + 0.6 * sin(ph * 2.0))
			1: v = sin(ph) + 0.35 * sin(ph * 2.0) + 0.15 * sin(ph * 3.0)
			2: v = 2.0 * absf(fmod(freq * t, 1.0) * 2.0 - 1.0) - 1.0
			3: v = sin(ph + 2.0 * sin(ph * 3.5) * exp(-6.0 * t))
			4: v = r.randf() * 2.0 - 1.0
		var idx := (start + k) % buf.size()
		buf[idx] += v * env

func render(mode:int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	if mode == 0:
		var step := 60.0 / 138.0 / 2.0
		var steps := DAY_CHORDS.size() * 6
		buf.resize(int(steps * step * RATE))
		for n in steps:
			var at := n * step
			var bar := n / 6
			var pos := n % 6
			var root:int = 60 + DAY_CHORDS[bar]
			if pos == 0: note(buf, at, midi(root - 12), 0.42, 4.0, 1)
			if pos == 2 or pos == 4:
				for off in [0, 4, 7]: note(buf, at, midi(root + off), 0.065, 9.0, 1)
			var mi := (n / 2) % DAY_MELODY.size()
			if n % 2 == 0 and DAY_MELODY[mi] >= 0:
				note(buf, at, midi(72 + SCALE_MAJOR[DAY_MELODY[mi]]), 0.15, 3.0, 0)
			if pos == 5 and bar % 2 == 1: note(buf, at, midi(84 + SCALE_MAJOR[(bar * 3) % 7]), 0.05, 4.0, 3)
	else:
		var step := 60.0 / 108.0 / 2.0
		var steps := NIGHT_BASS.size() * 8
		buf.resize(int(steps * step * RATE))
		for n in steps:
			var at := n * step
			var root:int = 45 + NIGHT_BASS[n / 8]
			if mode == 1:
				if n % 2 == 0: note(buf, at, midi(root - 12), 0.45, 3.0, 2)
				if n % 8 == 0: note(buf, at, midi(root + 12), 0.1, 1.2, 0)
				if n % 16 == 12: note(buf, at, midi(root + 15), 0.11, 2.0, 3)
			else:
				if n % 4 == 2: note(buf, at, midi(root), 0.16, 6.0, 1)
				if n % 2 == 1: note(buf, at, 6000.0, 0.04, 30.0, 4)
				if n % 4 == 0: note(buf, at, midi(root - 24), 0.32, 8.0, 0)
				if n % 8 == 6: note(buf, at, midi(root + 7), 0.08, 5.0, 3)
	var peak := 0.001
	for v in buf: peak = maxf(peak, absf(v))
	return gain(buf, 0.8 / peak)

func set_music(mode:int, combat:float):
	music_mode = mode
	intensity = combat

func _process(dt:float):
	if track_players.is_empty() or track_players.day.stream == null: return
	music_level = move_toward(music_level, 1.0, dt * 0.4)
	var base := linear_to_db(maxf(music_volume * master * music_level, 0.0005))
	var want := {"day": 1.0 if music_mode != 1 else 0.0, "night": 1.0 if music_mode == 1 else 0.0, "combat": intensity if music_mode == 1 else 0.0}
	for name in track_players:
		var p:AudioStreamPlayer = track_players[name]
		var cur := db_to_linear(p.volume_db - base) if p.volume_db > -79 else 0.0
		cur = move_toward(cur, want[name], dt * 0.5)
		p.volume_db = base - 8.0 + linear_to_db(maxf(cur, 0.0005)) if cur > 0.001 else -80.0
