extends Node

class_name StandManager

var stands: Array = []

func register_stands(list: Array) -> void:
	stands = list

func get_stands() -> Array:
	return stands

func stats_for_class(stand_class: String) -> Dictionary:
	var total := 0
	var free := 0
	for s in stands:
		if s.stand_class == stand_class:
			total += 1
			if not s.occupied:
				free += 1
	return { "total": total, "free": free }

func find_free(stand_class: String) -> Stand:
	for s in stands:
		if s.stand_class == stand_class and not s.occupied:
			return s
	return null

func occupy(stand: Stand, dwell_minutes: Dictionary) -> void:
	if stand == null:
		return
	stand.set_occupied(true)
	# Timer handling will be done by SimController; just mark visual here.
