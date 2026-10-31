extends Node

## Small original procedural sound palette; no downloaded or licensed audio.
var ambience: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
var clips: Dictionary = {}

func _ready() -> void:
	for key in ["step", "hit", "switch", "paper", "drum", "rest", "pogo", "view", "warning"]:
		clips[key] = synth(key)
	for i in range(6):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -15
		add_child(voice)
		voices.append(voice)
	ambience = AudioStreamPlayer.new()
	ambience.volume_db = -28
	ambience.stream = synth("ambient")
	add_child(ambience)
	if DisplayServer.get_name() != "headless": ambience.play()

func _exit_tree() -> void:
	if ambience != null:
		ambience.stop()
		ambience.stream = null
	for voice in voices:
		voice.stop()
		voice.stream = null
	clips.clear()

func play_cue(key: String, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless": return
	if not clips.has(key): return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = clips[key]
	voice.pitch_scale = pitch
	voice.play()

func set_era(past: bool) -> void:
	ambience.pitch_scale = 1.0 if past else 0.84

static func synth(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var length := 6.0 if kind == "ambient" else (0.7 if kind == "rest" else 0.24)
	var frames := int(rate * length)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var wave := 0.0
		if kind == "ambient":
			wave = (sin(TAU * 110 * t) * 0.35 + sin(TAU * 165 * t) * 0.17 + sin(TAU * 220 * t) * 0.1) * (0.6 + 0.4 * sin(TAU * t / length))
		else:
			var hz: float = {"step": 180, "hit": 78, "switch": 420, "paper": 720, "drum": 65, "rest": 550, "pogo": 980, "view": 250, "warning": 630}[kind]
			var envelope := sin(PI * minf(t / 0.012, 0.5)) * exp(-t * (5 if kind == "rest" else 20))
			wave = (sin(TAU * hz * t + (sin(t * 80) * 3 if kind == "paper" else 0)) + sin(TAU * hz * 1.5 * t) * 0.25) * envelope * 0.55
		data.encode_s16(i * 2, int(clampf(wave, -1, 1) * 28000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if kind == "ambient":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = frames
	return stream
