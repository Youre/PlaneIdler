extends Node

class_name UpgradeManager

@export var sim: SimController
@export var airport_manager: AirportManager
@export var runway: Runway
@export var console_label: RichTextLabel
var owned_upgrades: Array = []
var income_multiplier: float = 1.0
var nav_capabilities := {}
var current_tier: int = 0
var active_construction: Array = []
var purchase_counts := {}

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if active_construction.is_empty():
		return
	var scaled_dt := delta * (sim.time_scale if sim != null else 1.0)
	var remaining: Array = []
	for entry in active_construction:
		var rem: float = float(entry.get("remaining", 0.0)) - scaled_dt
		entry["remaining"] = rem
		if rem <= 0.0:
			_complete_construction(entry)
		else:
			remaining.append(entry)
	active_construction = remaining

func get_available_upgrades(bank: float, only_affordable: bool = true) -> Array:
	var result: Array = []
	if sim == null or sim.sim_state == null:
		return result
	for u in sim.sim_state.upgrade_catalog:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var id: String = str(u.get("id", ""))
		if id == "" or _is_under_construction(id):
			continue
		var max_purchases: int = int(u.get("maxPurchases", 1))
		var count: int = int(purchase_counts.get(id, 0))
		if max_purchases > 0 and count >= max_purchases:
			continue
		var tier: int = int(u.get("tierUnlock", 0))
		if tier > current_tier + 1:
			# Soft gate: don't show upgrades more than one tier ahead.
			continue
		var cost: float = float(u.get("cost", 0.0))
		if only_affordable and cost > bank:
			continue
		if not _prereqs_satisfied(u):
			continue
		result.append({
			"id": id,
			"cost": cost,
			"desc": str(u.get("displayName", ""))
		})
	return result

func purchase(id: String) -> bool:
	if sim == null or sim.sim_state == null:
		return false
	var upgrade = _find_upgrade(id)
	if upgrade.is_empty():
		_log("[color=yellow]Unknown upgrade:[/color] %s" % id)
		return false
	var cost: float = float(upgrade.get("cost", 0.0))
	if not _can_afford(cost):
		_log("[color=yellow]Insufficient funds for %s[/color]" % upgrade.get("displayName", id))
		return false
	if not _prereqs_satisfied(upgrade):
		_log("[color=yellow]Prerequisites not met for %s[/color]" % upgrade.get("displayName", id))
		return false
	_spend(cost)
	var build_time: float = float(upgrade.get("buildTimeSeconds", 0.0))
	if build_time <= 0.0:
		_apply_upgrade_effects(upgrade)
		_register_purchase_completion(id, upgrade)
		_log("[color=lime]Purchased upgrade:[/color] %s (instant)" % upgrade.get("displayName", id))
	else:
		var entry: Dictionary = {
			"id": id,
			"remaining": build_time,
			"total": build_time,
			"upgrade": upgrade
		}
		active_construction.append(entry)
		_log("[color=lime]Construction started:[/color] %s (%.0fs)" % [upgrade.get("displayName", id), build_time])
	return true

func _can_afford(cost: float) -> bool:
	return sim != null and sim.sim_state.bank >= cost

func _spend(cost: float) -> void:
	sim.sim_state.bank -= cost
	sim.emit_signal("bank_changed", sim.sim_state.bank)

func _max_runway_length() -> float:
	if sim == null:
		return runway.length_m if runway != null else 0.0
	var max_len: float = 0.0
	for ac in sim.sim_state.aircraft_catalog:
		if typeof(ac) == TYPE_DICTIONARY and ac.has("runway"):
			var r = ac["runway"]
			var len = float(r.get("minLengthMeters", 0.0))
			if len > max_len:
				max_len = len
	return max_len

func _find_upgrade(id: String) -> Dictionary:
	if sim == null or sim.sim_state == null:
		return {}
	for u in sim.sim_state.upgrade_catalog:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		if str(u.get("id", "")) == id:
			return u
	return {}

func _prereqs_satisfied(upgrade: Dictionary) -> bool:
	var prereqs = upgrade.get("prerequisites", [])
	if typeof(prereqs) != TYPE_ARRAY:
		return true
	for p in prereqs:
		if not owned_upgrades.has(str(p)):
			return false
	return true

func _is_under_construction(id: String) -> bool:
	for c in active_construction:
		if str(c.get("id", "")) == id:
			return true
	return false

func _complete_construction(entry: Dictionary) -> void:
	var upgrade: Dictionary = entry.get("upgrade", {})
	var id: String = str(entry.get("id", ""))
	_apply_upgrade_effects(upgrade)
	_register_purchase_completion(id, upgrade)
	_log("[color=lime]Construction complete:[/color] %s" % upgrade.get("displayName", id))

func _register_purchase_completion(id: String, upgrade: Dictionary) -> void:
	var prev: int = int(purchase_counts.get(id, 0))
	purchase_counts[id] = prev + 1
	if not owned_upgrades.has(id):
		owned_upgrades.append(id)
	_update_tier_from_upgrade(upgrade)

func get_construction_entries() -> Array:
	var out: Array = []
	for c in active_construction:
		var up: Dictionary = c.get("upgrade", {})
		out.append({
			"id": c.get("id", ""),
			"name": up.get("displayName", c.get("id", "")),
			"remaining": float(c.get("remaining", 0.0)),
			"total": float(c.get("total", 0.0))
		})
	return out

func _update_tier_from_upgrade(upgrade: Dictionary) -> void:
	var tier: int = int(upgrade.get("tierUnlock", -1))
	if tier >= 0 and tier > current_tier:
		current_tier = tier
		if sim != null and sim.sim_state != null:
			sim.sim_state.progression_tier = current_tier

func _apply_upgrade_effects(upgrade: Dictionary) -> void:
	var effects = upgrade.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return
	for e in effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var t: String = str(e.get("type", ""))
		match t:
			"add_stand":
				_effect_add_stand(e)
			"extend_runway":
				_effect_extend_runway(e)
			"multiplier":
				_effect_multiplier(e)
			"upgrade_surface":
				_effect_upgrade_surface(e)
			"add_runway":
				_effect_add_runway(e)
			"add_taxi_exit":
				_effect_add_taxi_exit(e)
			"unlock_nav":
				_effect_unlock_nav(e)
			_:
				_log("[color=gray]Unhandled upgrade effect type:[/color] %s" % t)

func _effect_add_stand(effect: Dictionary) -> void:
	if airport_manager == null:
		return
	var stand_class: String = str(effect.get("standClass", "ga_small"))
	var count: int = int(effect.get("count", 1))
	if count <= 0:
		return
	airport_manager.add_stands(stand_class, count)
	_log("Added %d %s stand(s)" % [count, stand_class])

func _effect_extend_runway(effect: Dictionary) -> void:
	if runway == null:
		return
	var meters: float = float(effect.get("meters", 0.0))
	if meters <= 0.0:
		return
	runway.set_length(runway.length_m + meters)
	_log("Extended runway by %dm" % int(meters))
	_recenter_camera()

func _effect_multiplier(effect: Dictionary) -> void:
	var target: String = str(effect.get("target", ""))
	var value: float = float(effect.get("value", 1.0))
	if value <= 0.0:
		return
	if sim == null or sim.sim_state == null:
		return
	match target:
		"income":
			if sim.sim_state.income_multiplier <= 0.0:
				sim.sim_state.income_multiplier = 1.0
			sim.sim_state.income_multiplier *= value
			_log("Income multiplier updated to x%.2f" % sim.sim_state.income_multiplier)
		"arrival_rate":
			if sim.sim_state.traffic_rate_multiplier <= 0.0:
				sim.sim_state.traffic_rate_multiplier = 1.0
			sim.sim_state.traffic_rate_multiplier *= value
			_log("Traffic rate multiplier updated to x%.2f" % sim.sim_state.traffic_rate_multiplier)
		_:
			_log("[color=gray]Unsupported multiplier target:[/color] %s" % target)

func _effect_upgrade_surface(effect: Dictionary) -> void:
	if runway == null:
		return
	var from_surface: String = str(effect.get("from", ""))
	var to_surface: String = str(effect.get("to", ""))
	if to_surface == "":
		return
	if from_surface != "" and runway.surface != from_surface:
		_log("[color=gray]Surface upgrade skipped; current=%s expected=%s[/color]" % [runway.surface, from_surface])
		return
	runway.update_surface(to_surface)
	_log("Runway surface upgraded to %s" % to_surface)

func _effect_add_runway(effect: Dictionary) -> void:
	if airport_manager == null:
		return
	var length_m: float = float(effect.get("lengthMeters", 0.0))
	var surface: String = str(effect.get("surface", "asphalt"))
	var width_class: String = str(effect.get("widthClass", "standard"))
	var ops: String = str(effect.get("ops", "both"))
	var new_runway := airport_manager.add_parallel_runway(80.0)
	if new_runway == null:
		return
	if length_m > 0.0:
		new_runway.set_length(length_m)
	new_runway.update_surface(surface)
	if width_class == "wide":
		new_runway.width_m = max(new_runway.width_m, 45.0)
	if sim != null:
		sim.register_runway(new_runway)
		if sim.sim_state != null:
			if sim.sim_state.traffic_rate_multiplier <= 0.0:
				sim.sim_state.traffic_rate_multiplier = 1.0
			# Second runway significantly boosts traffic capacity.
			sim.sim_state.traffic_rate_multiplier *= 1.4
			_log("Traffic rate multiplier updated to x%.2f (second runway)" % sim.sim_state.traffic_rate_multiplier)
	_log("Additional runway built (%s ops)" % ops)
	_recenter_camera()

func _effect_add_taxi_exit(effect: Dictionary) -> void:
	var runway_id: String = str(effect.get("runwayId", ""))
	var kind: String = str(effect.get("kind", "standard"))
	_log("Added taxi exit on %s (%s)" % [runway_id, kind])
	# Approximate benefit: small boost to traffic throughput.
	if sim != null and sim.sim_state != null:
		if sim.sim_state.traffic_rate_multiplier <= 0.0:
			sim.sim_state.traffic_rate_multiplier = 1.0
		var bonus := (1.05 if kind == "standard" else 1.1)
		sim.sim_state.traffic_rate_multiplier *= bonus
		_log("Traffic rate multiplier updated to x%.2f (taxiway)" % sim.sim_state.traffic_rate_multiplier)

func _effect_unlock_nav(effect: Dictionary) -> void:
	var capability: String = str(effect.get("capability", ""))
	if capability == "":
		return
	nav_capabilities[capability] = true
	if sim != null and sim.sim_state != null:
		sim.sim_state.nav_capabilities[capability] = true
	_log("Navigation capability unlocked: %s" % capability)

func _log(msg: String) -> void:
	if console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)

func _recenter_camera() -> void:
	var root = get_parent()
	if root and root.has_method("_position_camera"):
		root._position_camera()
