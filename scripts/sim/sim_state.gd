extends Node

class_name SimState

var time_seconds: float = 0.0
var bank: float = 0.0
var aircraft_catalog: Array = []
var upgrade_catalog: Array = []
var income_multiplier: float = 1.0
var nav_capabilities := {}
var progression_tier: int = 0
var traffic_rate_multiplier: float = 1.0
var tier_upgrade_counts := {}

var active_arrivals: Array = []
var active_parking: Array = []

const MINUTES_PER_DAY: float = 1440.0
const DAY_START_MIN: float = 6.0 * 60.0   # 06:00
const DAY_END_MIN: float = 20.0 * 60.0    # 20:00
# At time_scale = 1:
# - Day (06:00–20:00, 14 hours / 840 minutes) lasts 10 real minutes -> 840 / 600 = 1.4 min sim-time per sim-second.
# - Night (20:00–06:00, 10 hours / 600 minutes) lasts 2.5 real minutes -> 600 / 150 = 4.0 min sim-time per sim-second.
const DAY_RATE_MIN_PER_SEC: float = 1.4
const NIGHT_RATE_MIN_PER_SEC: float = 4.0

var clock_minutes: float = DAY_START_MIN   # in-game clock, 0–1440 (wraps each day)

func advance(dt: float) -> void:
	time_seconds += dt
	var rate: float = DAY_RATE_MIN_PER_SEC if is_daytime() else NIGHT_RATE_MIN_PER_SEC
	clock_minutes += dt * rate
	clock_minutes = fposmod(clock_minutes, MINUTES_PER_DAY)

func is_daytime() -> bool:
	return clock_minutes >= DAY_START_MIN and clock_minutes < DAY_END_MIN

func get_clock_hhmm() -> String:
	var mins: int = int(clock_minutes) % int(MINUTES_PER_DAY)
	var hh: int = mins / 60
	var mm: int = mins % 60
	return "%02d:%02d" % [hh, mm]
