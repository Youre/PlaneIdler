extends Node

class_name Eligibility

static func runway_ok(runway: Runway, aircraft: Dictionary) -> bool:
	if runway == null:
		return false
	var req = aircraft.get("runway", {})
	var length_req: float = float(req.get("minLengthMeters", 0.0))
	var surface_req: String = req.get("surface", "grass")
	var width_req: String = req.get("widthClass", "narrow")
	# Allow small GA on shorter strip if requirement is low
	return runway.supports(length_req, surface_req, width_req)

static func stand_ok(stand: Stand, aircraft: Dictionary) -> bool:
	if stand == null:
		return false
	var stand_class_req: String = aircraft.get("standClass", "ga_small")
	return stand.stand_class == stand_class_req and not stand.occupied
