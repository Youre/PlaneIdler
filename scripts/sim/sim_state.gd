extends Node

class_name SimState

var time_seconds: float = 0.0
var bank: float = 0.0
var aircraft_catalog: Array = []
var upgrade_catalog: Array = []

var active_arrivals: Array = []
var active_parking: Array = []

func advance(dt: float) -> void:
	time_seconds += dt
