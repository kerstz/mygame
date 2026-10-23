class_name AmbientAudio
extends Node
## Unobtrusive environmental sound: rain hiss and wind, nothing else (no
## music by design). Both are synthesised once at startup into seamless
## looping buffers (filtered noise), so there is no runtime DSP cost and no
## external audio asset.

const MIX_RATE := 22050
var rain_player: AudioStreamPlayer
var wind_player: AudioStreamPlayer


func _ready() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(GameSettings.get_value("master_volume")))
	GameSettings.changed.connect(func(_k):
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(GameSettings.get_value("master_volume"), 0.0001))))
	rain_player = _make_player(_noise_loop(6.0, 0.55, 0.25, 11))
	wind_player = _make_player(_noise_loop(9.0, 0.985, 0.0, 12))


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p


## Filtered noise: `lowpass` close to 1 = deep rumble (wind), lower = hiss
## (rain). `crackle` adds sparse drop transients. The loop is made seamless by
## cross-fading its tail into its head.
func _noise_loop(seconds: float, lowpass: float, crackle: float, seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := int(seconds * MIX_RATE)
	var fade := MIX_RATE / 2
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var y := 0.0
	var y2 := 0.0
	for i in n + fade:
		var white := rng.randf_range(-1.0, 1.0)
		y = y * lowpass + white * (1.0 - lowpass)
		y2 = y2 * 0.6 + y * 0.4
		var v := y2 if lowpass > 0.9 else (white - y) * 0.5 + y2 * 0.3
		if crackle > 0.0 and rng.randf() < 0.0015:
			v += rng.randf_range(-1.0, 1.0) * crackle
		buf[i] = v
	if lowpass > 0.9:
		# Slow amplitude swell for wind gusts.
		for i in n + fade:
			buf[i] *= 6.0 * (0.6 + 0.4 * sin(TAU * float(i) / float(n) * 2.0))
	for i in fade:
		var t := float(i) / fade
		buf[i] = buf[i] * t + buf[n + i] * (1.0 - t)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func update_levels(rain: float, wind: float, delta: float) -> void:
	var amb: float = GameSettings.get_value("ambience_volume")
	_fade(rain_player, rain * amb * 0.7, delta)
	_fade(wind_player, (0.15 + wind * 0.6) * amb * 0.5, delta)


func _fade(p: AudioStreamPlayer, linear: float, delta: float) -> void:
	var cur := db_to_linear(p.volume_db)
	cur = move_toward(cur, linear, delta * 0.2)
	p.volume_db = linear_to_db(maxf(cur, 0.0001))
