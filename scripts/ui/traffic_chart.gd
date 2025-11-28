extends Control

class_name TrafficChart

@export var received_color: Color = Color(0.2, 0.8, 0.3, 0.9)
@export var missed_color: Color = Color(0.9, 0.2, 0.2, 0.9)
@export var border_color: Color = Color(1, 1, 1, 0.4)

var received: Array[float] = [] as Array[float]   # handled arrivals per day
var missed: Array[float] = [] as Array[float]     # diverted/missed per day

func set_data(received_data: Array[float], missed_data: Array[float]) -> void:
	received = received_data.duplicate() as Array[float]
	missed = missed_data.duplicate() as Array[float]
	queue_redraw()

func _draw() -> void:
	var rect := get_rect()
	var margin: float = 4.0
	var w := rect.size.x - margin * 2.0
	var h := rect.size.y - margin * 2.0
	if w <= 0 or h <= 0:
		return
	# Background panel
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0, 0, 0, 0.55), true)
	# Use matched-length data; pad shorter one with zeros.
	var count: int = max(received.size(), missed.size())
	if count == 0:
		return
	var r: Array[float] = received.duplicate()
	var m: Array[float] = missed.duplicate()
	while r.size() < count:
		r.append(0.0)
	while m.size() < count:
		m.append(0.0)
	# Determine scale from total traffic per day.
	var max_val: float = 0.0
	for i in range(count):
		max_val = max(max_val, float(r[i]) + float(m[i]))
	if max_val <= 0.0:
		max_val = 1.0
	var bar_spacing := 2.0
	var bar_width := (w - bar_spacing * float(count - 1)) / float(count)
	if bar_width < 1.0:
		bar_width = 1.0
	var origin := Vector2(margin, margin)
	# Border
	draw_rect(Rect2(origin, Vector2(w, h)), border_color, false)
	# Stacked bars: green (received) on bottom, red (missed) above.
	for i in range(count):
		var received_val: float = float(r[i])
		var missed_val: float = float(m[i])
		var total: float = received_val + missed_val
		if total <= 0.0:
			continue
		var total_ratio: float = clamp(total / max_val, 0.0, 1.0)
		var total_h: float = h * total_ratio
		var x := origin.x + float(i) * (bar_width + bar_spacing)
		var base_y := origin.y + h - total_h
		# Received segment
		var rec_ratio: float = clamp(received_val / max_val, 0.0, 1.0)
		var rec_h: float = h * rec_ratio
		var rec_rect := Rect2(Vector2(x, origin.y + h - rec_h), Vector2(bar_width, rec_h))
		draw_rect(rec_rect, received_color, true)
		# Missed segment stacked on top of received
		var miss_ratio: float = clamp(missed_val / max_val, 0.0, 1.0)
		var miss_h: float = h * miss_ratio
		var miss_rect := Rect2(Vector2(x, base_y), Vector2(bar_width, miss_h))
		draw_rect(miss_rect, missed_color, true)
