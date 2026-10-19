extends Control
# The cartesian plane: 4 quadrants, x and y from -10 to 10.
# Draws the player's circle, planted curves, the curve preview and hit pulses.

signal clicked(p: Vector2)
signal hovered(p: Vector2)

const UI = preload("res://scripts/ui.gd")
const Formula = preload("res://scripts/formula.gd")
const P := 10.0

var radius_units := 1.0 / sqrt(PI)
var mode := "none"            # none | place | relocate
var my_pos = null             # Vector2 or null (current confirmed position)
var my_color := Color("4da3ff")
var pending = null            # Vector2 or null (chosen but not yet confirmed)
var curves: Array = []        # {segments, color, alpha, label}
var preview: Array = []       # segments of the previewed curve
var preview_color := Color.WHITE
var pulses: Array = []        # {p: Vector2, age: float, color: Color}
var reveal: Array = []        # {p: Vector2, color: Color, name: String}  (game-over reveal)
var hover_pos = null

static func sample(ast: Dictionary) -> Array:
	var segs: Array = []
	var cur := PackedVector2Array()
	var prev_y := 0.0
	var has_prev := false
	var x := -P
	while x <= P + 0.0001:
		var y := Formula.evaluate(ast, x)
		var ok := is_finite(y) and absf(y) <= P
		if ok and (not has_prev or absf(y - prev_y) < 2.0):
			cur.append(Vector2(x, y))
			prev_y = y
			has_prev = true
		else:
			if cur.size() >= 2:
				segs.append(cur)
			cur = PackedVector2Array()
			if ok:
				cur.append(Vector2(x, y))
				prev_y = y
				has_prev = true
			else:
				has_prev = false
		x += 0.05
	if cur.size() >= 2:
		segs.append(cur)
	return segs

func to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x + P) / (2.0 * P) * size.x, (P - p.y) / (2.0 * P) * size.y)

func from_screen(s: Vector2) -> Vector2:
	var x := clampf(s.x / size.x * 2.0 * P - P, -P, P)
	var y := clampf(P - s.y / size.y * 2.0 * P, -P, P)
	return Vector2(snappedf(x, 0.01), snappedf(y, 0.01))

func px_per_unit() -> float:
	return size.x / (2.0 * P)

func add_pulse(p: Vector2, color: Color) -> void:
	pulses.append({"p": p, "age": 0.0, "color": color})

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_pos = from_screen(event.position)
		hovered.emit(hover_pos)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if mode != "none":
			clicked.emit(from_screen(event.position))

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_pos = null
		queue_redraw()

func _process(delta: float) -> void:
	if pulses.is_empty():
		return
	for i in range(pulses.size() - 1, -1, -1):
		pulses[i]["age"] += delta
		if pulses[i]["age"] > 2.0:
			pulses.remove_at(i)
	queue_redraw()

func _draw_segments(segs: Array, col: Color, width: float, dashed: bool = false) -> void:
	for seg in segs:
		var pts := PackedVector2Array()
		for p in seg:
			pts.append(to_screen(p))
		if not dashed:
			draw_polyline(pts, col, width, true)
		else:
			var i := 0
			while i < pts.size() - 1:
				var j := mini(i + 8, pts.size())
				if j - i >= 2:
					draw_polyline(pts.slice(i, j), col, width, true)
				i += 13

func _circle(p: Vector2, col: Color, filled: bool = true) -> void:
	var c := to_screen(p)
	var r := radius_units * px_per_unit()
	if filled:
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.35))
	draw_arc(c, r, 0.0, TAU, 48, col, 2.5, true)
	draw_circle(c, 2.5, col)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b0d1a"))
	# quadrant tint + labels
	var half := size / 2.0
	draw_rect(Rect2(half.x, 0, half.x, half.y), Color(1, 1, 1, 0.012))
	draw_rect(Rect2(0, half.y, half.x, half.y), Color(1, 1, 1, 0.012))
	var qcol := Color(0.56, 0.59, 0.78, 0.35)
	draw_string(font, Vector2(size.x - 34, 26), "I", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, qcol)
	draw_string(font, Vector2(14, 26), "II", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, qcol)
	draw_string(font, Vector2(14, size.y - 14), "III", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, qcol)
	draw_string(font, Vector2(size.x - 40, size.y - 14), "IV", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, qcol)
	# grid
	for i in range(-10, 11):
		var major := i % 5 == 0
		var gc := Color("232a5a") if major else Color("161b3a")
		draw_line(to_screen(Vector2(i, -P)), to_screen(Vector2(i, P)), gc, 1.0)
		draw_line(to_screen(Vector2(-P, i)), to_screen(Vector2(P, i)), gc, 1.0)
	var axis := Color("5560b8")
	draw_line(to_screen(Vector2(0, -P)), to_screen(Vector2(0, P)), axis, 2.0)
	draw_line(to_screen(Vector2(-P, 0)), to_screen(Vector2(P, 0)), axis, 2.0)
	var tc := Color(0.56, 0.59, 0.78, 0.8)
	for i in range(-8, 9, 2):
		if i == 0:
			continue
		var sx := to_screen(Vector2(i, 0))
		draw_string(font, sx + Vector2(-8, 16), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tc)
		var sy := to_screen(Vector2(0, i))
		draw_string(font, sy + Vector2(6, 4), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tc)
	# curves (planted / revealed)
	for c in curves:
		var col: Color = c["color"]
		col.a = c["alpha"]
		_draw_segments(c["segments"], col, 3.0)
		var lab: String = c.get("label", "")
		if lab != "" and not c["segments"].is_empty():
			var seg: PackedVector2Array = c["segments"][0]
			var anchor: Vector2 = seg[seg.size() / 2]
			for s in c["segments"]:
				for p in s:
					if absf(p.x - 6.0) < absf(anchor.x - 6.0):
						anchor = p
			var sp := to_screen(anchor) + Vector2(4, -8)
			sp.x = clampf(sp.x, 4.0, size.x - 120.0)
			sp.y = clampf(sp.y, 14.0, size.y - 6.0)
			draw_string_outline(font, sp, lab, HORIZONTAL_ALIGNMENT_LEFT, 170, 12, 4, Color(0.04, 0.05, 0.1, 0.95))
			draw_string(font, sp, lab, HORIZONTAL_ALIGNMENT_LEFT, 170, 12, Color(col.r, col.g, col.b, minf(1.0, col.a + 0.3)))
	# preview of the curve about to be planted
	if not preview.is_empty():
		_draw_segments(preview, Color(1, 1, 1, 0.9), 2.5, true)
	# positions
	for r in reveal:
		_circle(r["p"], r["color"])
		draw_string(font, to_screen(r["p"]) + Vector2(-20, -radius_units * px_per_unit() - 6), r["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, r["color"])
	if reveal.is_empty():
		if my_pos != null:
			var faded := pending != null
			var col2 := my_color
			if faded:
				col2.a = 0.4
			_circle(my_pos, col2, not faded)
			if not faded:
				draw_string(font, to_screen(my_pos) + Vector2(-8, -radius_units * px_per_unit() - 6), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, my_color)
		if pending != null:
			_circle(pending, Color.WHITE)
			draw_string(font, to_screen(pending) + Vector2(-26, radius_units * px_per_unit() + 16), "(%.1f, %.1f)" % [pending.x, pending.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if mode != "none" and hover_pos != null:
			var hc := to_screen(hover_pos)
			draw_arc(hc, radius_units * px_per_unit(), 0.0, TAU, 40, Color(1, 1, 1, 0.35), 1.5, true)
			draw_string(font, hc + Vector2(radius_units * px_per_unit() + 6, -4), "(%.1f, %.1f)" % [hover_pos.x, hover_pos.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	# hit pulses
	for pl in pulses:
		var age: float = pl["age"]
		var a := clampf(1.0 - age / 2.0, 0.0, 1.0)
		var pc: Color = pl["color"]
		var sp2 := to_screen(pl["p"])
		draw_arc(sp2, 10.0 + age * 38.0, 0.0, TAU, 40, Color(pc.r, pc.g, pc.b, a), 3.0, true)
		draw_circle(sp2, 5.0, Color(pc.r, pc.g, pc.b, a))
	draw_rect(Rect2(Vector2.ZERO, size), UI.BORDER, false, 2.0)
	if mode != "none":
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.6), false, 2.0)
