class_name SoundSynth
extends RefCounted
## Synthesises the game's original sound effects from small recipes (Milestone 22): layers of
## filtered noise and pitched tones, each with its own delay, attack and exponential decay,
## mixed and normalised. Pure and deterministic: the same recipe and seed always give the same
## samples, so the generator tool is repeatable.
##
## A recipe is {"length": seconds, "layers": [layer, ...], "peak": 0..1 (default 0.9)}.
## A layer is {"type": "noise" | "tone", "gain", "delay", "attack", "decay"} plus:
## - noise: "lowpass" and "highpass" (Hz, optional), "crackle" (0..1: sparse pops instead of hiss);
## - tone: "freq", "freq_end" (a sweep, optional), "harmonics" (extra partials' gain, optional),
##   "wobble" (random pitch jitter 0..1, optional).

const RATE: int = 44100


## Samples (-1..1, mono, [constant RATE] Hz) for [param recipe], seeded by [param noise_seed].
static func render(recipe: Dictionary, noise_seed: int) -> PackedFloat32Array:
	var count := maxi(int(float(recipe.get("length", 0.5)) * RATE), 1)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var dice := RandomNumberGenerator.new()
	dice.seed = noise_seed
	for layer: Dictionary in recipe.get("layers", []):
		_add_layer(mix, layer, dice)
	_normalise(mix, float(recipe.get("peak", 0.9)))
	# A short fade at the end so nothing clicks off.
	var fade := mini(int(0.005 * RATE), count)
	for i: int in fade:
		mix[count - 1 - i] *= float(i) / fade
	return mix


## A 16-bit mono stream of [param samples].
static func to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream


static func _add_layer(mix: PackedFloat32Array, layer: Dictionary, dice: RandomNumberGenerator) -> void:
	var gain := float(layer.get("gain", 1.0))
	var start := int(float(layer.get("delay", 0.0)) * RATE)
	var attack := maxf(float(layer.get("attack", 0.001)), 0.0001)
	var decay := maxf(float(layer.get("decay", 0.1)), 0.0001)
	var is_tone := str(layer.get("type", "noise")) == "tone"
	var low := _pole(float(layer.get("lowpass", 0.0)))
	var high := _pole(float(layer.get("highpass", 0.0)))
	var crackle := float(layer.get("crackle", 0.0))
	var freq := float(layer.get("freq", 440.0))
	var freq_end := float(layer.get("freq_end", freq))
	var harmonics := float(layer.get("harmonics", 0.0))
	var wobble := float(layer.get("wobble", 0.0))
	var phase := dice.randf() * TAU
	var low_state := 0.0
	var high_state := 0.0
	# The layer lasts until its envelope is inaudible (about 7 decay constants).
	var span := mini(int((attack + decay * 7.0) * RATE), mix.size() - start)
	for i: int in span:
		var t := float(i) / RATE
		var envelope := minf(t / attack, 1.0) * exp(-maxf(t - attack, 0.0) / decay)
		var sample := 0.0
		if is_tone:
			var progress := t / (attack + decay * 3.0)
			var current := lerpf(freq, freq_end, clampf(progress, 0.0, 1.0)) * (1.0 + wobble * 0.02 * dice.randf_range(-1.0, 1.0))
			phase += TAU * current / RATE
			sample = sin(phase) + harmonics * 0.5 * sin(phase * 2.0) + harmonics * 0.25 * sin(phase * 3.0)
		elif crackle > 0.0:
			sample = dice.randf_range(-1.0, 1.0) if dice.randf() < crackle * 0.02 else 0.0
		else:
			sample = dice.randf_range(-1.0, 1.0)
		if low > 0.0:
			low_state += low * (sample - low_state)
			sample = low_state
		if high > 0.0:
			# One-pole high-pass: what the low-pass at that cutoff takes away.
			high_state += high * (sample - high_state)
			sample -= high_state
		mix[start + i] += sample * envelope * gain


## The one-pole filter coefficient for a cutoff in Hz (0 = filter off).
static func _pole(cutoff: float) -> float:
	if cutoff <= 0.0:
		return 0.0
	return 1.0 - exp(-TAU * cutoff / RATE)


static func _normalise(mix: PackedFloat32Array, peak: float) -> void:
	var loudest := 0.0
	for sample: float in mix:
		loudest = maxf(loudest, absf(sample))
	if loudest <= 0.0:
		return
	var scale := peak / loudest
	for i: int in mix.size():
		mix[i] *= scale
