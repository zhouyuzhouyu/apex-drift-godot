extends Node

## Procedural Motorsport AudioManager Autoload
## Generates rich, license-free synthesized WAV loops & SFX at startup and manages
## continuous dynamic engine, tire screech, wind, nitro, and optional synthwave BGM.

const SAMPLE_RATE := 22050

var sfx_streams: Dictionary = {}
var bgm_player: AudioStreamPlayer
var engine_player: AudioStreamPlayer
var engine_sub_player: AudioStreamPlayer
var screech_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer
var nitro_player: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx: int = 0
var _driving_audio_active: bool = false
var _is_dummy_audio: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_dummy_audio = (AudioServer.get_driver_name() == "Dummy")
	_build_streams()
	_build_players()
	apply_volumes()
	GameState.settings_changed.connect(apply_volumes)


func _exit_tree() -> void:
	if GameState.settings_changed.is_connected(apply_volumes):
		GameState.settings_changed.disconnect(apply_volumes)
	for p in [bgm_player, engine_player, engine_sub_player, screech_player, wind_player, nitro_player]:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in sfx_pool:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
	sfx_pool.clear()
	sfx_streams.clear()


func _build_streams() -> void:
	# Load GEVP MIT engine sample if present and ensure forward looping; fall back to procedural loop
	var gevp_wav := load("res://addons/gevp/sounds/4000.wav")
	if gevp_wav is AudioStreamWAV:
		var wav: AudioStreamWAV = gevp_wav
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			if wav.format == AudioStreamWAV.FORMAT_8_BITS or wav.format == AudioStreamWAV.FORMAT_16_BITS:
				var dup: AudioStreamWAV = wav.duplicate()
				dup.loop_mode = AudioStreamWAV.LOOP_FORWARD
				dup.loop_begin = 0
				var bps := (2 if dup.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if dup.stereo else 1)
				dup.loop_end = dup.data.size() / maxi(1, bps)
				sfx_streams["engine_main"] = dup
			else:
				sfx_streams["engine_main"] = _make_engine_loop(133.3, 1.2)
		else:
			sfx_streams["engine_main"] = wav
	else:
		sfx_streams["engine_main"] = _make_engine_loop(133.3, 1.2)

	sfx_streams["engine_sub"] = _make_engine_loop(72.0, 1.0)
	sfx_streams["tire_screech"] = _make_screech_loop(0.9)
	sfx_streams["wind_loop"] = _make_wind_loop(1.4)
	sfx_streams["nitro_loop"] = _make_nitro_loop(0.8)
	sfx_streams["bgm_loop"] = _make_synthwave_bgm()

	sfx_streams["countdown_beep"] = _make_tone(520.0, 0.16, 0.55, "square_soft")
	sfx_streams["countdown_go"] = _make_chord([659.25, 880.0, 1318.5], 0.42, 0.65)
	sfx_streams["lap_chime"] = _make_arpeggio([587.33, 880.0, 1174.66], 0.08, 0.48)
	sfx_streams["final_lap"] = _make_arpeggio([659.25, 783.99, 1046.5, 1318.5], 0.075, 0.55)
	sfx_streams["race_finish"] = _make_arpeggio([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.09, 0.60)
	sfx_streams["collision"] = _make_impact_thud(0.24)
	sfx_streams["gear_shift"] = _make_gear_pop(0.08)
	sfx_streams["nitro_ignite"] = _make_sweep(180.0, 740.0, 0.25, 0.55)
	sfx_streams["boost_pad"] = _make_sweep(420.0, 1480.0, 0.22, 0.48)
	sfx_streams["ui_click"] = _make_tone(680.0, 0.045, 0.28, "sine")
	sfx_streams["ui_confirm"] = _make_arpeggio([520.0, 780.0], 0.05, 0.34)


func _build_players() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.stream = sfx_streams["bgm_loop"]
	bgm_player.autoplay = false
	add_child(bgm_player)

	engine_player = AudioStreamPlayer.new()
	engine_player.stream = sfx_streams["engine_main"]
	add_child(engine_player)

	engine_sub_player = AudioStreamPlayer.new()
	engine_sub_player.stream = sfx_streams["engine_sub"]
	add_child(engine_sub_player)

	screech_player = AudioStreamPlayer.new()
	screech_player.stream = sfx_streams["tire_screech"]
	add_child(screech_player)

	wind_player = AudioStreamPlayer.new()
	wind_player.stream = sfx_streams["wind_loop"]
	add_child(wind_player)

	nitro_player = AudioStreamPlayer.new()
	nitro_player.stream = sfx_streams["nitro_loop"]
	add_child(nitro_player)

	for i in range(8):
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_pool.append(p)


func apply_volumes() -> void:
	var master_v := float(GameState.settings.get("master_volume", 0.85))
	var music_v := float(GameState.settings.get("music_volume", 0.45)) * master_v
	if music_v <= 0.01:
		bgm_player.volume_db = -80.0
	else:
		bgm_player.volume_db = linear_to_db(music_v * 0.38)
		if not _is_dummy_audio and not bgm_player.playing:
			bgm_player.play()


func start_driving_audio() -> void:
	_driving_audio_active = true
	if _is_dummy_audio:
		return
	if not engine_player.playing:
		engine_player.volume_db = -40.0
		engine_player.play()
	if not engine_sub_player.playing:
		engine_sub_player.volume_db = -40.0
		engine_sub_player.play()
	if not screech_player.playing:
		screech_player.volume_db = -80.0
		screech_player.play()
	if not wind_player.playing:
		wind_player.volume_db = -80.0
		wind_player.play()
	if not nitro_player.playing:
		nitro_player.volume_db = -80.0
		nitro_player.play()


func stop_driving_audio() -> void:
	_driving_audio_active = false
	engine_player.stop()
	engine_sub_player.stop()
	screech_player.stop()
	wind_player.stop()
	nitro_player.stop()


func update_driving_audio(rpm: float, max_rpm: float, throttle: float, speed_kmh: float, slip_intensity: float, nitro_active: bool) -> void:
	if not _driving_audio_active or _is_dummy_audio:
		return
	var master_v := float(GameState.settings.get("master_volume", 0.85))
	var sfx_v := float(GameState.settings.get("sfx_volume", 0.90)) * master_v
	if sfx_v <= 0.01 or get_tree().paused:
		engine_player.volume_db = -80.0
		engine_sub_player.volume_db = -80.0
		screech_player.volume_db = -80.0
		wind_player.volume_db = -80.0
		nitro_player.volume_db = -80.0
		return

	for p in [engine_player, engine_sub_player, screech_player, wind_player, nitro_player]:
		if not p.playing:
			p.play()

	var rpm_ratio := clampf(rpm / maxf(max_rpm, 1000.0), 0.10, 1.25)
	engine_player.pitch_scale = clampf(rpm / 4000.0, 0.35, 2.65)
	var eng_gain := (0.20 + throttle * 0.24 + rpm_ratio * 0.14) * sfx_v
	engine_player.volume_db = linear_to_db(maxf(eng_gain, 0.0005))

	engine_sub_player.pitch_scale = clampf(0.55 + rpm_ratio * 1.45, 0.45, 2.3)
	var sub_gain := (0.14 + throttle * 0.18) * sfx_v
	engine_sub_player.volume_db = linear_to_db(maxf(sub_gain, 0.0005))

	var screech_gain := clampf((slip_intensity - 0.18) * 0.42, 0.0, 0.34) * sfx_v
	screech_player.pitch_scale = clampf(0.85 + speed_kmh * 0.0022, 0.80, 1.45)
	screech_player.volume_db = -80.0 if screech_gain < 0.005 else linear_to_db(screech_gain)

	var wind_gain := clampf((speed_kmh - 70.0) / 220.0, 0.0, 1.0) * 0.26 * sfx_v
	wind_player.pitch_scale = clampf(0.75 + speed_kmh / 260.0, 0.75, 1.85)
	wind_player.volume_db = -80.0 if wind_gain < 0.004 else linear_to_db(wind_gain)

	var nitro_gain := (0.38 if nitro_active else 0.0) * sfx_v
	nitro_player.pitch_scale = 1.15 + clampf(speed_kmh / 350.0, 0.0, 0.45)
	nitro_player.volume_db = -80.0 if nitro_gain < 0.005 else linear_to_db(nitro_gain)


func play_sfx(name: String, pitch: float = 1.0, volume_scale: float = 1.0) -> void:
	if _is_dummy_audio or not sfx_streams.has(name):
		return
	var master_v := float(GameState.settings.get("master_volume", 0.85))
	var sfx_v := float(GameState.settings.get("sfx_volume", 0.90)) * master_v * volume_scale
	if sfx_v <= 0.01:
		return
	var p := sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % sfx_pool.size()
	p.stream = sfx_streams[name]
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(maxf(sfx_v * 0.55, 0.001))
	p.play()


# --- Procedural WAV Generators (16-bit PCM Mono) ---

func _pack_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _make_engine_loop(base_freq: float, duration: float) -> AudioStreamWAV:
	var cycles := maxi(1, int(round(base_freq * duration)))
	var n := int(round(float(cycles) * float(SAMPLE_RATE) / base_freq))
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var ph := TAU * base_freq * t
		var s := 0.45 * sin(ph) + 0.30 * sin(ph * 2.0 + 0.4) + 0.16 * sin(ph * 3.0) + 0.09 * sin(ph * 4.0) + 0.06 * sin(ph * 0.5)
		buf[i] = tanh(s * 1.4) * 0.62
	return _pack_wav(buf, true)


func _make_screech_loop(duration: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4201
	var lp := 0.0
	var bp := 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var white := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, white, 0.35)
		bp = lerpf(bp, lp, 0.12)
		var squeal := sin(TAU * (1180.0 + 65.0 * sin(TAU * 4.0 * t)) * t) * 0.38
		var squeal2 := sin(TAU * 1690.0 * t) * 0.22
		var v := (lp - bp) * 0.45 + squeal + squeal2
		# Smooth crossfade window near edges for clean loop
		buf[i] = clampf(v * 0.65, -1.0, 1.0)
	_smooth_loop_seam(buf, 300)
	return _pack_wav(buf, true)


func _make_wind_loop(duration: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	var lp := 0.0
	for i in range(n):
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.07)
		buf[i] = lp * 0.85
	_smooth_loop_seam(buf, 400)
	return _pack_wav(buf, true)


func _make_nitro_loop(duration: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
		var jet := lp * 0.68 + sin(TAU * 92.0 * t) * 0.28 + sin(TAU * 184.0 * t) * 0.14
		buf[i] = clampf(jet * 0.72, -1.0, 1.0)
	_smooth_loop_seam(buf, 300)
	return _pack_wav(buf, true)


func _make_synthwave_bgm() -> AudioStreamWAV:
	# Energetic 128 BPM 8-bar synthwave driving loop (A minor -> F -> C -> G)
	var bpm := 128.0
	var step_dur := 60.0 / bpm * 0.25 # 16th note
	var total_steps := 64 # 4 bars of 16th notes
	var duration := step_dur * float(total_steps)
	var n := int(round(duration * SAMPLE_RATE))
	var buf := PackedFloat32Array()
	buf.resize(n)

	var bass_roots := [110.0, 87.31, 130.81, 98.0] # A2, F2, C3, G2
	var arp_chords := [
		[220.0, 261.63, 329.63, 440.0], # Am
		[174.61, 220.0, 261.63, 349.23], # F
		[261.63, 329.63, 392.0, 523.25], # C
		[196.0, 246.94, 293.66, 392.0]   # G
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 128128

	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var step := int(t / step_dur) % total_steps
		var bar := step / 16
		var step_in_bar := step % 16
		var local_t := fmod(t, step_dur)
		var env_step := exp(-local_t * 14.0)

		# Driving 8th/16th synth bass
		var bfreq: float = bass_roots[bar]
		var bass_env := exp(-local_t * 9.0)
		var bass := (sin(TAU * bfreq * t) * 0.6 + sin(TAU * bfreq * 2.0 * t) * 0.25) * bass_env * 0.34

		# Sparkling arpeggio
		var chord: Array = arp_chords[bar]
		var afreq: float = chord[step_in_bar % 4]
		var arp := sin(TAU * afreq * t) * env_step * 0.16

		# Four-on-the-floor kick drum
		var kick := 0.0
		if step_in_bar % 4 == 0:
			var k_freq := 135.0 * exp(-local_t * 28.0) + 46.0
			kick = sin(TAU * k_freq * local_t) * exp(-local_t * 18.0) * 0.42

		# Crisp off-beat hi-hat
		var hat := 0.0
		if step_in_bar % 2 == 1:
			hat = rng.randf_range(-1.0, 1.0) * exp(-local_t * 55.0) * 0.11

		buf[i] = clampf((bass + arp + kick + hat) * 0.80, -1.0, 1.0)

	_smooth_loop_seam(buf, 220)
	return _pack_wav(buf, true)


func _make_tone(freq: float, duration: float, amp: float, kind: String) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env := minf(1.0, t / 0.008) * (1.0 - (t / duration) * 0.65)
		var s := sin(TAU * freq * t)
		if kind == "square_soft":
			s = tanh(s * 2.4)
		buf[i] = s * env * amp
	return _pack_wav(buf, false)


func _make_chord(freqs: Array, duration: float, amp: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env := minf(1.0, t / 0.01) * exp(-t * 4.5)
		var sum := 0.0
		for f in freqs:
			sum += sin(TAU * float(f) * t)
		buf[i] = (sum / maxf(1.0, float(freqs.size()))) * env * amp
	return _pack_wav(buf, false)


func _make_arpeggio(freqs: Array, note_dur: float, amp: float) -> AudioStreamWAV:
	var total := note_dur * float(freqs.size()) + 0.18
	var n := int(total * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for idx in range(freqs.size()):
		var start_s := int(float(idx) * note_dur * SAMPLE_RATE)
		var note_len := int((note_dur + 0.16) * SAMPLE_RATE)
		var f := float(freqs[idx])
		for j in range(note_len):
			var pos := start_s + j
			if pos >= n:
				break
			var lt := float(j) / float(SAMPLE_RATE)
			var env := minf(1.0, lt / 0.006) * exp(-lt * 10.0)
			buf[pos] = clampf(buf[pos] + sin(TAU * f * lt) * env * amp, -1.0, 1.0)
	return _pack_wav(buf, false)


func _make_sweep(f0: float, f1: float, duration: float, amp: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in range(n):
		var u := float(i) / float(n)
		var freq := lerpf(f0, f1, u)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env := sin(PI * u)
		buf[i] = tanh(sin(phase) * 1.5) * env * amp
	return _pack_wav(buf, false)


func _make_impact_thud(duration: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 551
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var thud := sin(TAU * (120.0 * exp(-t * 18.0) + 38.0) * t) * exp(-t * 14.0)
		var crunch := rng.randf_range(-1.0, 1.0) * exp(-t * 26.0) * 0.45
		buf[i] = clampf((thud * 0.8 + crunch) * 0.85, -1.0, 1.0)
	return _pack_wav(buf, false)


func _make_gear_pop(duration: float) -> AudioStreamWAV:
	var n := int(duration * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var pop := sin(TAU * 150.0 * t) * exp(-t * 42.0) * 0.55 + rng.randf_range(-1.0, 1.0) * exp(-t * 50.0) * 0.35
		buf[i] = clampf(pop, -1.0, 1.0)
	return _pack_wav(buf, false)


func _smooth_loop_seam(buf: PackedFloat32Array, blend_len: int) -> void:
	var n := buf.size()
	var m := mini(blend_len, n / 4)
	for i in range(m):
		var w := float(i) / float(m)
		var end_idx := n - m + i
		buf[end_idx] = lerpf(buf[end_idx], buf[i], w)
