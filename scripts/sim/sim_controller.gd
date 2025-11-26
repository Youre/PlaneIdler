extends Node

class_name SimController

@export var arrival_generator: ArrivalGenerator
@export var sim_state: SimState
@export var stand_manager: StandManager
@export var console_label: RichTextLabel
@export var runway: Runway
@export var aircraft_scene: PackedScene
signal bank_changed(new_bank: float)
@export var time_scale: float = 1.0

var _dwell_timers: Array = [] # Array of dictionaries: { "stand": Stand, "remaining": float }
var _actors: Array = []
var _flyovers: Array = []
var _flyby_timer: float = 0.0
var _flyby_next: float = 60.0
const CULL_DISTANCE: float = 650.0
var _runways: Array = []
var _stand_actors: Dictionary = {} # Stand -> AircraftActor
var _cleanup_accum: float = 0.0
var _runway_busy: bool = false
var _arrival_queue: Array = []
var _departure_queue: Array = []

func _ready() -> void:
	randomize()
	if arrival_generator == null:
		arrival_generator = ArrivalGenerator.new()
	add_child(arrival_generator)
	if sim_state == null:
		sim_state = SimState.new()
	add_child(sim_state)
	if stand_manager == null:
		stand_manager = StandManager.new()
	add_child(stand_manager)
	arrival_generator.reset()
	_flyby_timer = 0.0
	_flyby_next = randf_range(45.0, 90.0)

func set_catalogs(aircraft: Array, upgrades: Array) -> void:
	sim_state.aircraft_catalog = aircraft
	sim_state.upgrade_catalog = upgrades

func set_stands(stand_nodes: Array) -> void:
	stand_manager.register_stands(stand_nodes)
	# assume main runway is sibling node named Runway under AirportRoot
	if runway == null:
		var airport = get_parent().get_node_or_null("AirportRoot")
		if airport:
			runway = airport.get_node_or_null("Runway")
	_runways.clear()
	if runway != null:
		_runways.append(runway)

func register_runway(r: Runway) -> void:
	if r == null:
		return
	if not _runways.has(r):
		_runways.append(r)

func _process(delta: float) -> void:
	if sim_state == null:
		return
	var scaled_dt = delta * time_scale
	sim_state.advance(scaled_dt)
	_process_arrivals(scaled_dt)
	_process_dwell(scaled_dt)
	_process_flyby(scaled_dt)
	_cull_far_actors()
	_cleanup_accum += scaled_dt
	if _cleanup_accum >= 10.0:
		_cleanup_accum = 0.0
		_cleanup_stale_actors()

func _process_arrivals(delta: float) -> void:
	var spawns = arrival_generator.update(delta, sim_state)
	for aircraft in spawns:
		_handle_arrival_request(aircraft)

func _select_runway_for_aircraft(aircraft: Dictionary) -> Runway:
	if runway != null and Eligibility.runway_ok(runway, aircraft):
		return runway
	# fallback: check any additional runways we know about
	for r in _runways:
		if r != runway and Eligibility.runway_ok(r, aircraft):
			return r
	return null


func _start_dwell_timer(stand: Stand, dwell_minutes: Dictionary) -> void:
	var dur_min = dwell_minutes.get("min", 1)
	var dur_max = dwell_minutes.get("max", 3)
	# Speed up departures for testing (scale down)
	var dwell_seconds = randf_range(float(dur_min) * 15.0, float(dur_max) * 30.0)
	var timer_entry = { "stand": stand, "remaining": dwell_seconds }
	_dwell_timers.append(timer_entry)

func _process_dwell(delta: float) -> void:
	var still_active: Array = []
	for entry in _dwell_timers:
		entry["remaining"] = entry["remaining"] - delta
		if entry["remaining"] <= 0.0:
			var stand: Stand = entry["stand"]
			if stand:
				if _runway_busy:
					_departure_queue.append(stand)
				else:
					_runway_busy = true
					_spawn_departure_actor(stand)
		else:
			still_active.append(entry)
	_dwell_timers = still_active

func _process_flyby(delta: float) -> void:
	_flyby_timer += delta
	if _flyby_timer >= _flyby_next:
		_spawn_flyby()
		_flyby_timer = 0.0
		_flyby_next = randf_range(45.0, 90.0)

func _handle_arrival_request(aircraft: Dictionary) -> void:
	var stand_class: String = aircraft.get("standClass", "ga_small")
	var dwell_minutes: Dictionary = aircraft.get("dwellMinutes", {})
	var use_runway = _select_runway_for_aircraft(aircraft)
	var runway_ok = use_runway != null
	if not runway_ok:
		var reason = _runway_diversion_reason(aircraft)
		_log_diversion(aircraft, reason)
		_spawn_flyover(aircraft)
		return
	if _runway_busy and _has_atc():
		_arrival_queue.append(aircraft)
		return
	var stand: Stand = stand_manager.find_free(stand_class)
	if stand and not _runway_busy:
		# Reserve and apply effects immediately
		stand_manager.occupy(stand, dwell_minutes)
		_start_dwell_timer(stand, dwell_minutes)
		_log_arrival(aircraft, stand)
		_add_income(aircraft)
		_runway_busy = true
		_spawn_actor_for_arrival(aircraft, stand)
	else:
		var reason := ""
		if stand_manager != null:
			var stats = stand_manager.stats_for_class(stand_class)
			var total: int = int(stats.get("total", 0))
			var free: int = int(stats.get("free", 0))
			if total == 0:
				reason = "no %s stands built" % stand_class
			elif free <= 0:
				reason = "all %s stands occupied (%d total)" % [stand_class, total]
			else:
				reason = "capacity unavailable"
		else:
			reason = "capacity unavailable"
		_log_diversion(aircraft, reason)
		_spawn_flyover(aircraft)

func _has_atc() -> bool:
	if sim_state == null:
		return false
	return bool(sim_state.nav_capabilities.get("atc", false))

func _add_income(aircraft: Dictionary) -> void:
	var fees = aircraft.get("fees", {})
	var landing = fees.get("landing", 0.0)
	var dwell = fees.get("parkingPerMinute", 0.0) * float(aircraft.get("dwellMinutes", {}).get("min", 1))
	var amount = landing + dwell
	if sim_state != null:
		amount *= max(0.0, sim_state.income_multiplier)
	sim_state.bank += amount
	emit_signal("bank_changed", sim_state.bank)
	_log("[color=green]+%.0f[/color] bank=%.0f" % [amount, sim_state.bank])

func _log(msg: String, to_console: bool = true) -> void:
	if to_console and console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)

func _spawn_actor_for_arrival(aircraft: Dictionary, stand: Stand) -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor: AircraftActor = _stand_actors.get(stand, null)
	if actor == null:
		actor = aircraft_scene.instantiate()
		get_parent().add_child(actor)
		actor.speed_mps = 40.0
		_actors.append(actor)
		_stand_actors[stand] = actor
		# Apply color scheme based on aircraft size category for new actors.
		actor.set_category_color(_class_category_for_aircraft(aircraft))
	var fwd = runway.global_transform.basis.x.normalized() # runway length axis
	var right = runway.global_transform.basis.z.normalized()
	var start = runway.global_transform.origin - fwd * 250.0 + Vector3(0, 12, 0)
	var runway_touch = runway.global_transform.origin + Vector3(0, 0.2, 0)
	var stand_pos = stand.global_transform.origin + Vector3(0, 0.7, 0)
	actor.start_path([start, runway_touch, stand_pos], func():
		# Arrival complete; keep actor parked at stand until departure.
		_stand_actors[stand] = actor
		_runway_busy = false
		_service_runway_queue()
	)

func _spawn_departure_actor(stand: Stand) -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor: AircraftActor = _stand_actors.get(stand, null)
	if actor == null or not is_instance_valid(actor):
		actor = aircraft_scene.instantiate()
		get_parent().add_child(actor)
		actor.speed_mps = 35.0
		_actors.append(actor)
	else:
		actor.speed_mps = 35.0
	actor.set_lifetime(10.0)
	var fwd = runway.global_transform.basis.x.normalized()
	var start = stand.global_transform.origin + Vector3(0, 0.5, 0)
	var runway_point = runway.global_transform.origin + fwd * 15.0
	var exit = runway.global_transform.origin + fwd * 300.0 + Vector3(0, 6, 0)
	actor.depart([start, runway_point, exit], func():
		_safe_free_actor(actor, _actors)
		_stand_actors.erase(stand)
		if stand:
			stand.set_occupied(false)
			_log("%s departed from %s" % [stand.label, stand.stand_class])
		_runway_busy = false
		_service_runway_queue()
	)

func _log_arrival(aircraft: Dictionary, stand: Stand) -> void:
	_log("[color=cyan]%s[/color] arrived -> %s (dwell %d-%d min)" % [
		aircraft.get("displayName", "Aircraft"),
		stand.label,
		int(aircraft.get("dwellMinutes", {}).get("min", 1)),
		int(aircraft.get("dwellMinutes", {}).get("max", 3))
	])

func _log_diversion(aircraft: Dictionary, reason: String) -> void:
	_log("[color=red]%s diverted[/color] (%s)" % [
		aircraft.get("displayName", "Aircraft"),
		reason
	])

func _spawn_flyover(aircraft: Dictionary) -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor = aircraft_scene.instantiate()
	get_parent().add_child(actor)
	actor.speed_mps = 60.0
	actor.set_divert_visual()
	if actor is AircraftActor:
		var aa: AircraftActor = actor
		aa.set_category_color(_class_category_for_aircraft(aircraft))
		aa.set_lifetime(30.0)
	var dir = 1.0 if randf() > 0.5 else -1.0
	var lateral_sign = 1.0 if randf() > 0.5 else -1.0
	var lateral = randf_range(80.0, 140.0) * lateral_sign
	var alt = _cruise_altitude_for_aircraft(aircraft, 30.0, 55.0)
	var fwd = runway.global_transform.basis.x.normalized()
	var right = runway.global_transform.basis.z.normalized()
	var start = runway.global_transform.origin - fwd * 450.0 * dir + right * lateral + Vector3(0, alt, 0)
	var mid = runway.global_transform.origin + right * (lateral * 0.35) + Vector3(0, alt - 5, 0)
	var end = runway.global_transform.origin + fwd * 450.0 * dir + right * lateral + Vector3(0, alt + 5, 0)
	actor.start_path([start, mid, end], func():
		_safe_free_actor(actor, _flyovers)
	)
	_flyovers.append(actor)

func _spawn_flyby() -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor = aircraft_scene.instantiate()
	get_parent().add_child(actor)
	actor.speed_mps = 55.0
	if actor is AircraftActor:
		var aa: AircraftActor = actor
		aa.set_category_color("large")
		aa.set_lifetime(30.0)
	var dir = 1.0 if randf() > 0.5 else -1.0
	var lateral_sign = 1.0 if randf() > 0.5 else -1.0
	var lateral = randf_range(200.0, 320.0) * lateral_sign
	var alt = _cruise_altitude_for_aircraft({"class": "narrowbody"}, 70.0, 110.0)
	var fwd = runway.global_transform.basis.x.normalized()
	var right = runway.global_transform.basis.z.normalized()
	var start = runway.global_transform.origin - fwd * 550.0 * dir + right * lateral + Vector3(0, alt, 0)
	var mid = runway.global_transform.origin + right * (lateral * 0.4) + Vector3(0, alt, 0)
	var end = runway.global_transform.origin + fwd * 550.0 * dir + right * lateral + Vector3(0, alt, 0)
	actor.start_path([start, mid, end], func():
		_safe_free_actor(actor, _flyovers)
	)
	_flyovers.append(actor)

func _cull_far_actors() -> void:
	var center: Vector3 = runway.global_transform.origin if runway != null else Vector3.ZERO
	for actor in _actors.duplicate():
		if not actor or not is_instance_valid(actor):
			_actors.erase(actor)
			continue
		if actor.is_inside_tree() and actor.global_transform.origin.distance_to(center) > CULL_DISTANCE:
			actor.queue_free()
			_actors.erase(actor)
	for actor in _flyovers.duplicate():
		if not actor or not is_instance_valid(actor):
			_flyovers.erase(actor)
			continue
		if actor.is_inside_tree() and actor.global_transform.origin.distance_to(center) > CULL_DISTANCE:
			actor.queue_free()
			_flyovers.erase(actor)

func _cleanup_stale_actors() -> void:
	# As a last resort, remove any aircraft actors that are no longer
	# active and not parked at a stand, to prevent visual clusters of
	# stuck boxes.
	var parked: Array = _stand_actors.values()
	for actor in _actors.duplicate():
		if not actor or not is_instance_valid(actor):
			_actors.erase(actor)
			continue
		if parked.has(actor):
			continue
		if actor is AircraftActor:
			var aa: AircraftActor = actor
			if not aa._active:
				_safe_free_actor(actor, _actors)
	for actor in _flyovers.duplicate():
		if not actor or not is_instance_valid(actor):
			_flyovers.erase(actor)
			continue
		if actor is AircraftActor:
			var aa2: AircraftActor = actor
			if not aa2._active:
				_safe_free_actor(actor, _flyovers)
	# If runway is marked busy but no active aircraft remain, release it
	# so queued arrivals/departures are not blocked forever.
	if _runway_busy:
		var busy_found := false
		for actor in _actors:
			if actor and is_instance_valid(actor) and actor is AircraftActor:
				var aa3: AircraftActor = actor
				if aa3._active:
					busy_found = true
					break
		if not busy_found:
			_runway_busy = false
			_service_runway_queue()

func _service_runway_queue() -> void:
	if _runway_busy:
		return
	# Landings have priority when ATC is available.
	if _arrival_queue.size() > 0 and _has_atc():
		var aircraft: Dictionary = _arrival_queue.pop_front()
		_handle_arrival_request(aircraft)
		return
	if _departure_queue.size() > 0:
		var stand: Stand = _departure_queue.pop_front()
		if stand != null:
			_runway_busy = true
			_spawn_departure_actor(stand)

func _class_category_for_aircraft(aircraft: Dictionary) -> String:
	var cls: String = str(aircraft.get("class", ""))
	var stand_class: String = str(aircraft.get("standClass", ""))
	var is_small: bool = cls == "ga_small"
	var is_medium: bool = (cls == "turboprop" or stand_class == "ga_medium")
	var is_large: bool = cls in ["regional_jet", "narrowbody", "widebody", "cargo_wide", "cargo_small"]
	if is_small:
		return "small"
	if is_medium:
		return "medium"
	if is_large:
		return "large"
	return "small"

func _cruise_altitude_for_aircraft(aircraft: Dictionary, base_min: float, base_max: float) -> float:
	var cls: String = str(aircraft.get("class", "ga_small"))
	var min_alt = base_min
	var max_alt = base_max
	match cls:
		"ga_small":
			min_alt = 30.0
			max_alt = 55.0
		"turboprop":
			min_alt = 40.0
			max_alt = 65.0
		"regional_jet":
			min_alt = 50.0
			max_alt = 80.0
		"narrowbody":
			min_alt = 60.0
			max_alt = 95.0
		"widebody", "cargo_wide":
			min_alt = 70.0
			max_alt = 110.0
		"cargo_small":
			min_alt = 50.0
			max_alt = 80.0
		_:
			min_alt = base_min
			max_alt = base_max
	return randf_range(min_alt, max_alt)

func _safe_free_actor(actor: Node, list: Array) -> void:
	if actor != null and is_instance_valid(actor):
		actor.queue_free()
	if list.has(actor):
		list.erase(actor)

func _runway_diversion_reason(aircraft: Dictionary) -> String:
	var rwy: Runway = runway
	if rwy == null and _runways.size() > 0:
		rwy = _runways[0]
	if rwy == null:
		return "no runway available"
	var req = aircraft.get("runway", {})
	var length_req: float = float(req.get("minLengthMeters", 0.0))
	var surface_req: String = req.get("surface", "grass")
	var width_req: String = req.get("widthClass", "narrow")
	if rwy.length_m < length_req:
		return "runway too short (needs ≥ %dm, have %dm)" % [int(length_req), int(rwy.length_m)]
	var function_surface_rank := func(s: String) -> int:
		match s:
			"grass":
				return 0
			"asphalt":
				return 1
			"concrete":
				return 2
			_:
				return -1
	if function_surface_rank.call(rwy.surface) < function_surface_rank.call(surface_req):
		return "runway surface too weak (needs %s, have %s)" % [surface_req, rwy.surface]
	if width_req == "wide" and rwy.width_m < 45.0:
		return "runway too narrow for wide-body aircraft"
	return "runway not suitable"
