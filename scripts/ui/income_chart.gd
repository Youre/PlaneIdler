extends Control

class_name IncomeChart

@export var bar_color: Color = Color(0.2, 0.8, 0.3, 0.9)
@export var border_color: Color = Color(1, 1, 1, 0.4)

var values: Array = []        # numeric values to plot
var fallback_bank: float = 0  # current bank, for fallback visualization

func set_data(data: Array, bank: float) -> void:
	values = data.duplicate()
	fallback_bank = bank
	queue_redraw()

func _draw() -> void:
	var rect := get_rect()
	var margin: float = 4.0
	var w := rect.size.x - margin * 2.0
	var h := rect.size.y - margin * 2.0
	if w <= 0 or h <= 0:
		return
	# Draw dark background panel so the chart is always visible.
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0, 0, 0, 0.55), true)
	# Choose data source: recent daily income, or fall back to current bank.
	var data: Array = values.duplicate()
	var has_positive := false
	for v in data:
		if float(v) > 0.0:
			has_positive = true
			break
	if not has_positive and fallback_bank > 0.0:
		data.clear()
		data.append(fallback_bank)
	if data.is_empty():
		return
	var max_val: float = 0.0
	for v in data:
		max_val = max(max_val, float(v))
	if max_val <= 0.0:
		max_val = 1.0
	var bar_count := data.size()
	var bar_spacing := 2.0
	var bar_width := (w - bar_spacing * float(bar_count - 1)) / float(bar_count)
	if bar_width < 1.0:
		bar_width = 1.0
	# In _draw(), local coordinates start at (0, 0) for this Control,
	# so we only offset by the local margin and ignore rect.position
	# (which is in the parent's space).
	var origin := Vector2(margin, margin)
	# Draw border
	draw_rect(Rect2(origin, Vector2(w, h)), border_color, false)
	# Draw bars (oldest to newest from left to right).
	for i in range(bar_count):
		var v: float = float(data[i])
		var ratio: float = clamp(v / max_val, 0.0, 1.0)
		var bar_h: float = h * ratio
		var x: float = origin.x + float(i) * (bar_width + bar_spacing)
		var y: float = origin.y + h - bar_h
		var bar_rect := Rect2(Vector2(x, y), Vector2(bar_width, bar_h))
		draw_rect(bar_rect, bar_color, true)
