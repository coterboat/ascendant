class_name SeededRNG
## Pure seeded RNG wrapper. All rules/ randomness goes through this.
## Uses Godot's RandomNumberGenerator internally. Seeded at creation.
## No global rand* calls anywhere in rules/.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value

func randi() -> int:
	return _rng.randi()

func randf() -> float:
	return _rng.randf()

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func get_seed() -> int:
	return _rng.seed

func get_state() -> int:
	return _rng.state

func set_state(s: int) -> void:
	_rng.state = s

## Seed and state are full 64-bit values, so they are stored as strings (see Serial) to survive JSON.
func to_dict() -> Dictionary:
	return {
		"seed": Serial.int64_to_str(_rng.seed),
		"state": Serial.int64_to_str(_rng.state),
	}

static func from_dict(data: Dictionary) -> SeededRNG:
	var rng := SeededRNG.new(Serial.to_int(data.get("seed", 0)))
	rng.set_state(Serial.to_int(data.get("state", 0)))
	return rng
