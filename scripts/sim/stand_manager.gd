extends Node

class_name StandManager

var stands: Array = []

func register_stands(list: Array) -> void:
	stands = list

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
