extends Node

class_name UpgradeManager

@export var sim: Node = null
@export var airport_manager: Node = null
@export var runway: Node = null
@export var console_label: RichTextLabel = null

var owned_upgrades = []
var income_multiplier = 1.0
var nav_capabilities = {}
var current_tier = 0
var active_construction = []      # [{ id, remaining, total, upgrade }]
var purchase_counts = {}

func _ready():
	set_process(true)

func _process(delta):
	if active_construction.is_empty():
		return
	var timescale = 1.0
	if sim != null:
		timescale = sim.time_scale
	var scaled_dt = delta * timescale
	var remaining = []
	for entry in active_construction:
		var rem = float(entry.get("remaining", 0.0)) - scaled_dt
		entry["remaining"] = rem
		if rem <= 0.0:
			_complete_construction(entry)
		else:
			remaining.append(entry)
	active_construction = remaining

func get_available_upgrades(bank, only_affordable = true):
	var result = []
	if sim == null or sim.sim_state == null:
		return result
	for u in sim.sim_state.upgrade_catalog:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var id = str(u.get("id", ""))
		if id == "" or _is_under_construction(id):
			continue
		var max_purchases = int(u.get("maxPurchases", 1))
		var count = int(purchase_counts.get(id, 0))
		if max_purchases > 0 and count >= max_purchases:
			continue
		var tier = int(u.get("tierUnlock", 0))
		if tier > current_tier + 1:
			continue
		var cost = float(u.get("cost", 0.0))
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

func purchase(id):
	if sim == null or sim.sim_state == null:
		return false
	var upgrade = _find_upgrade(id)
	if upgrade.is_empty():
		_log("[color=yellow]Unknown upgrade:[/color] %s" % id)
		return false
	var cost = float(upgrade.get("cost", 0.0))
	if not _can_afford(cost):
		_log("[color=yellow]Insufficient funds for %s[/color]" % upgrade.get("displayName", id))
		return false
	if not _prereqs_satisfied(upgrade):
		_log("[color=yellow]Prerequisites not met for %s[/color]" % upgrade.get("displayName", id))
		return false
	_spend(cost)
	var build_time = float(upgrade.get("buildTimeSeconds", 0.0))
	if build_time <= 0.0:
		_apply_upgrade_effects(upgrade)
		_register_purchase_completion(id, upgrade)
		_log("[color=lime]Purchased upgrade:[/color] %s (instant)" % upgrade.get("displayName", id))
	else:
		var entry = {
			"id": id,
			"remaining": build_time,
			"total": build_time,
			"upgrade": upgrade
		}
		active_construction.append(entry)
		_log("[color=lime]Construction started:[/color] %s (%.0fs)" % [upgrade.get("displayName", id), build_time])
	return true

func _can_afford(cost):
	return sim != null and sim.sim_state.bank >= cost

func _spend(cost):
	sim.sim_state.bank -= cost
	sim.emit_signal("bank_changed", sim.sim_state.bank)

func _find_upgrade(id):
	if sim == null or sim.sim_state == null:
		return {}
	for u in sim.sim_state.upgrade_catalog:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		if str(u.get("id", "")) == id:
			return u
	return {}

func _prereqs_satisfied(upgrade):
	var prereqs = upgrade.get("prerequisites", [])
	if typeof(prereqs) != TYPE_ARRAY:
		return true
	for p in prereqs:
		if not owned_upgrades.has(str(p)):
			return false
	return true

func _is_under_construction(id):
	for c in active_construction:
		if str(c.get("id", "")) == id:
			return true
	return false

func _complete_construction(entry):
	var upgrade = entry.get("upgrade", {})
	var id = str(entry.get("id", ""))
	_apply_upgrade_effects(upgrade)
	_register_purchase_completion(id, upgrade)
	_log("[color=lime]Construction complete:[/color] %s" % upgrade.get("displayName", id))

func _register_purchase_completion(id, upgrade):
	var prev = int(purchase_counts.get(id, 0))
	purchase_counts[id] = prev + 1
	if not owned_upgrades.has(id):
		owned_upgrades.append(id)
	_update_tier_from_upgrade(upgrade)
	if sim != null and sim.sim_state != null:
		var utier = int(upgrade.get("tierUnlock", -1))
		if utier >= 0:
			var cur = int(sim.sim_state.tier_upgrade_counts.get(utier, 0))
			sim.sim_state.tier_upgrade_counts[utier] = cur + 1

func get_construction_entries():
	var out = []
	for c in active_construction:
		var up = c.get("upgrade", {})
		out.append({
			"id": c.get("id", ""),
			"name": up.get("displayName", c.get("id", "")),
			"remaining": float(c.get("remaining", 0.0)),
			"total": float(c.get("total", 0.0))
		})
	return out

func _update_tier_from_upgrade(upgrade):
	var tier = int(upgrade.get("tierUnlock", -1))
	if tier >= 0 and tier > current_tier:
		current_tier = tier
		if sim != null and sim.sim_state != null:
			sim.sim_state.progression_tier = current_tier

func _apply_upgrade_effects(upgrade):
	var id = str(upgrade.get("id", ""))
	var effects = upgrade.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return
	for e in effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var t = str(e.get("type", ""))
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
			"widen_runway":
				_effect_widen_runway(e)
			"add_hangar":
				_effect_add_hangar(e)
			_:
				_log("[color=gray]Unhandled upgrade effect type:[/color] %s" % t)

	if id == "tower_upgrade":
		if sim != null and sim.sim_state != null:
			sim.sim_state.nav_capabilities["atc"] = true
		if airport_manager != null:
			var tower = airport_manager.get_node_or_null("Tower")
			if tower:
				tower.visible = true
	if id == "fuel_farm" and airport_manager != null:
		var fuel = airport_manager.get_node_or_null("FuelStation")
		if fuel:
			fuel.visible = true
	if id == "ils_lighting" and airport_manager != null:
		if airport_manager.has_method("build_runway_lights"):
			airport_manager.build_runway_lights()
	if id.begins_with("ga_hangar_fbo") and airport_manager != null:
		var hangars = airport_manager.get_node_or_null("Hangars")
		if hangars:
			hangars.visible = true

func _effect_widen_runway(effect):
	if airport_manager == null:
		return
	var min_width = float(effect.get("minWidthMeters", 45.0))
	if min_width <= 0.0:
		return
	if airport_manager.has_method("widen_runways"):
		airport_manager.widen_runways(min_width)
	elif runway != null and runway.width_m < min_width:
		runway.set_width(min_width)

func _effect_add_stand(effect):
	if airport_manager == null:
		return
	var stand_class = str(effect.get("standClass", "ga_small"))
	var count = int(effect.get("count", 1))
	if count <= 0:
		return
	airport_manager.add_stands(stand_class, count)
	if sim != null and airport_manager.has_method("get_stands"):
		var stands = airport_manager.get_stands()
		if stands.size() > 0:
			sim.set_stands(stands)
	_log("Added %d %s stand(s)" % [count, stand_class])

func _effect_add_hangar(effect):
	var slots = int(effect.get("slots", 0))
	if slots <= 0:
		return
	var service_class = str(effect.get("serviceClass", "ga"))
	var fbo_fee = float(effect.get("fboFee", 0.0))
	if airport_manager != null and airport_manager.has_method("add_hangars"):
		airport_manager.add_hangars(slots)
	if sim != null and sim.has_method("register_hangar_slots"):
		sim.register_hangar_slots(slots, service_class, fbo_fee)
	_log("Added %d hangar bay(s) with FBO service" % slots)

func _effect_extend_runway(effect):
	if runway == null:
		return
	var meters = float(effect.get("meters", 0.0))
	if meters <= 0.0:
		return
	runway.set_length(runway.length_m + meters)
	_log("Extended runway by %dm" % int(meters))
	_recenter_camera()

func _effect_multiplier(effect):
	var target = str(effect.get("target", ""))
	var value = float(effect.get("value", 1.0))
	if value <= 0.0:
		return
	if sim == null or sim.sim_state == null:
		return
	if target == "income":
		if sim.sim_state.income_multiplier <= 0.0:
			sim.sim_state.income_multiplier = 1.0
		sim.sim_state.income_multiplier *= value
		_log("Income multiplier updated to x%.2f" % sim.sim_state.income_multiplier)
	elif target == "arrival_rate":
		if sim.sim_state.traffic_rate_multiplier <= 0.0:
			sim.sim_state.traffic_rate_multiplier = 1.0
		sim.sim_state.traffic_rate_multiplier *= value
		_log("Traffic rate multiplier updated to x%.2f" % sim.sim_state.traffic_rate_multiplier)
	else:
		_log("[color=gray]Unsupported multiplier target:[/color] %s" % target)

func _effect_upgrade_surface(effect):
	if runway == null:
		return
	var from_surface = str(effect.get("from", ""))
	var to_surface = str(effect.get("to", ""))
	if to_surface == "":
		return
	if from_surface != "" and runway.surface != from_surface:
		_log("[color=gray]Surface upgrade skipped; current=%s expected=%s[/color]" % [runway.surface, from_surface])
		return
	runway.update_surface(to_surface)
	_log("Runway surface upgraded to %s" % to_surface)

func _effect_add_runway(effect):
	if airport_manager == null:
		return
	var length_m = float(effect.get("lengthMeters", 0.0))
	var surface = str(effect.get("surface", "asphalt"))
	var width_class = str(effect.get("widthClass", "standard"))
	var ops = str(effect.get("ops", "both"))
	var new_runway = airport_manager.add_parallel_runway(80.0)
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
			sim.sim_state.traffic_rate_multiplier *= 1.4
			_log("Traffic rate multiplier updated to x%.2f (second runway)" % sim.sim_state.traffic_rate_multiplier)
	_log("Additional runway built (%s ops)" % ops)
	_recenter_camera()

func _effect_add_taxi_exit(effect):
	var runway_id = str(effect.get("runwayId", ""))
	var kind = str(effect.get("kind", "standard"))
	_log("Added taxi exit on %s (%s)" % [runway_id, kind])
	if airport_manager != null:
		# Enable the procedural taxiway network once any taxiway
		# upgrade is purchased, so we don't show taxiways before
		# the first upgrade.
		if airport_manager.has_method("set_taxiways_enabled"):
			airport_manager.set_taxiways_enabled(true)
		# Legacy visual helpers for taxi loop / rapid exit.
		# Align them with the runway so they appear parallel
		# instead of crossing at odd angles.
		var node_name = "RapidExit" if kind == "rapid" else "TaxiLoop"
		var node = airport_manager.get_node_or_null(node_name)
		if node:
			node.visible = true
			if runway != null:
				node.rotation.y = runway.rotation.y
	if sim != null and sim.sim_state != null:
		if sim.sim_state.traffic_rate_multiplier <= 0.0:
			sim.sim_state.traffic_rate_multiplier = 1.0
		var bonus = 1.05
		if kind == "rapid":
			bonus = 1.1
		sim.sim_state.traffic_rate_multiplier *= bonus
		_log("Traffic rate multiplier updated to x%.2f (taxiway)" % sim.sim_state.traffic_rate_multiplier)

func _effect_unlock_nav(effect):
	var capability = str(effect.get("capability", ""))
	if capability == "":
		return
	nav_capabilities[capability] = true
	if sim != null and sim.sim_state != null:
		sim.sim_state.nav_capabilities[capability] = true
	_log("Navigation capability unlocked: %s" % capability)

func _log(msg):
	if console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)

func _recenter_camera():
	var root = get_parent()
	if root and root.has_method("_position_camera"):
		root._position_camera()
