extends Node

class_name ArrivalGenerator

@export var min_interval: float = 30.0  # faster for early testing; can raise later
@export var max_interval: float = 60.0
@export var initial_delay: float = 5.0

var _timer: float = 0.0
var _next_spawn: float = 0.0

func reset() -> void:
	_timer = 0.0
	_next_spawn = initial_delay

func update(dt: float, sim: SimState) -> Array:
	_timer += dt
	var spawns: Array = []
	while _timer >= _next_spawn:
		var chosen = _pick_aircraft(sim.aircraft_catalog)
		if chosen != null:
			spawns.append(chosen)
		_timer -= _next_spawn
		_next_spawn = randf_range(min_interval, max_interval)
	return spawns

func _pick_aircraft(catalog: Array) -> Dictionary:
	if catalog.is_empty():
		return {}
	var total_weight := 0.0
	for a in catalog:
		total_weight += a.get("spawnWeight", 1.0)
	var r := randf() * total_weight
	for a in catalog:
		r -= a.get("spawnWeight", 1.0)
		if r <= 0:
			return a
	return catalog.back()
