extends AudioStreamPlayer

var sounds: Array[AudioStreamWAV] = []


func _ready() -> void:
	for kind in range(4):
		sounds.append(make_sound(kind))


func strike(kind: int) -> void:
	stream = sounds[kind]
	play()


func make_sound(kind: int) -> AudioStreamWAV:
	const RATE := 22050
	var clip := AudioStreamWAV.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 407 + kind
	var metal := kind != 0
	var hz: float = [110.0, 540.0, 860.0, 375.0][kind]
	var length := 0.28 if kind >= 2 else 0.15
	var decay := 15.0 if kind >= 2 else 34.0
	var frames := int(RATE * length)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / RATE
		var tone := sin(TAU * hz * t)
		if metal:
			tone += 0.46 * sin(TAU * hz * 2.31 * t) + 0.31 * sin(TAU * hz * 3.73 * t)
		var sample := tone * exp(-t * decay) * 0.25
		sample += rng.randf_range(-0.52, 0.52) * exp(-t * 130.0)
		sample *= minf(t * 1300.0, 1.0)
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	clip.data = bytes
	return clip
