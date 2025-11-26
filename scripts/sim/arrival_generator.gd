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
	# Simple night-ops gate: if night_ops not unlocked, skip spawns at night.
	var night_locked: bool = not bool(sim.nav_capabilities.get("night_ops", false))
	if night_locked and not sim.is_daytime():
		return spawns
	var tier: int = sim.progression_tier
	while _timer >= _next_spawn:
		var chosen = _pick_aircraft_for_tier(sim.aircraft_catalog, tier)
		if chosen != null:
			spawns.append(chosen)
		_timer -= _next_spawn
		var rate: float = max(sim.traffic_rate_multiplier, 0.1)
		_next_spawn = randf_range(min_interval, max_interval) / rate
	return spawns

func _pick_aircraft_for_tier(catalog: Array, tier: int) -> Dictionary:
	if catalog.is_empty():
		return {}
	var eligible: Array = []
	for a in catalog:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var atier: int = int(a.get("tierUnlock", 0))
		if atier <= tier:
			eligible.append(a)
	if eligible.is_empty():
		eligible = catalog.duplicate()
	var total_weight := 0.0
	for a in eligible:
		total_weight += a.get("spawnWeight", 1.0)
	var r := randf() * total_weight
	for a in eligible:
		r -= a.get("spawnWeight", 1.0)
		if r <= 0:
			return a
	return eligible.back()
