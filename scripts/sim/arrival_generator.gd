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
		var chosen = _pick_aircraft_for_tier(sim, tier)
		if chosen != null:
			spawns.append(chosen)
		_timer -= _next_spawn
		var rate: float = max(sim.traffic_rate_multiplier, 0.1)
		_next_spawn = randf_range(min_interval, max_interval) / rate
	return spawns

func _pick_aircraft_for_tier(sim: SimState, tier: int) -> Dictionary:
	var catalog: Array = sim.aircraft_catalog
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
		return {}
	var t1: int = int(sim.tier_upgrade_counts.get(1, 0))
	var t2: int = int(sim.tier_upgrade_counts.get(2, 0))
	var t3: int = int(sim.tier_upgrade_counts.get(3, 0))
	var t4: int = int(sim.tier_upgrade_counts.get(4, 0))
	var weighted: Array = []
	var total_weight := 0.0
	for a in eligible:
		var cls: String = str(a.get("class", ""))
		var stand_class: String = str(a.get("standClass", ""))
		var is_small: bool = cls == "ga_small"
		var is_medium: bool = (cls == "turboprop" or stand_class == "ga_medium")
		var is_large: bool = cls in ["regional_jet", "narrowbody", "widebody", "cargo_wide", "cargo_small"]
		var votes := 0.0
		# Base votes: only small GA start with one.
		if is_small:
			votes += 1.0
		# Tier 1 upgrades: small + medium GA.
		if t1 > 0 and (is_small or is_medium):
			votes += float(t1)
		# Tier 2 upgrades: small + medium + large.
		if t2 > 0 and (is_small or is_medium or is_large):
			votes += float(t2)
		# Tier 3 upgrades: medium + large.
		if t3 > 0 and (is_medium or is_large):
			votes += float(t3)
		# Tier 4 upgrades: large only.
		if t4 > 0 and is_large:
			votes += float(t4)
		if votes <= 0.0:
			continue
		weighted.append({"aircraft": a, "weight": votes})
		total_weight += votes
	if weighted.is_empty():
		return {}
	var r := randf() * total_weight
	for entry in weighted:
		r -= float(entry.get("weight", 0.0))
		if r <= 0.0:
			return entry.get("aircraft", {})
	return weighted.back().get("aircraft", {})
