extends VBoxContainer
# Scientific calculator keypad + formula line. You can also just type with the keyboard.

signal changed(text: String)
signal submitted(text: String)

const UI = preload("res://scripts/ui.gd")

var edit: LineEdit

const KEYS := [
	["sin", "sin(", "cos", "cos(", "tan", "tan(", "asin", "asin(", "acos", "acos(", "atan", "atan("],
	["ln", "ln(", "log", "log(", "exp", "exp(", "sqrt", "sqrt(", "|x|", "abs(", "floor", "floor("],
	["7", "7", "8", "8", "9", "9", "(", "(", ")", ")", "DEL", "<DEL>"],
	["4", "4", "5", "5", "6", "6", "×", "*", "÷", "/", "CLR", "<CLR>"],
	["1", "1", "2", "2", "3", "3", "+", "+", "-", "-", "x", "x"],
	["0", "0", ".", ".", "x^y", "^", "pi", "pi", "e", "e", "x^2", "^2"],
]

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	edit = LineEdit.new()
	edit.placeholder_text = "y = f(x)   e.g. 3sin(x) + 0.1x^2"
	edit.add_theme_font_size_override("font_size", 22)
	edit.custom_minimum_size = Vector2(0, 44)
	edit.text_changed.connect(func(t: String): changed.emit(t))
	edit.text_submitted.connect(func(t: String): submitted.emit(t))
	add_child(edit)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for row in KEYS:
		for i in range(0, row.size(), 2):
			var shown: String = row[i]
			var payload: String = row[i + 1]
			var b := UI.button(shown, 30.0)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var is_fn := shown.length() > 2
			if is_fn or shown in ["DEL", "CLR"]:
				b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_press.bind(payload))
			grid.add_child(b)

func _press(payload: String) -> void:
	if payload == "<CLR>":
		set_text("")
	elif payload == "<DEL>":
		var c := edit.caret_column
		if c > 0:
			edit.text = edit.text.erase(c - 1, 1)
			edit.caret_column = c - 1
			changed.emit(edit.text)
	else:
		edit.insert_text_at_caret(payload)
		changed.emit(edit.text)
	edit.grab_focus()

func set_text(t: String) -> void:
	edit.text = t
	edit.caret_column = t.length()
	changed.emit(t)

func set_enabled(on: bool) -> void:
	edit.editable = on
	for ch in get_children():
		if ch is GridContainer:
			for b in ch.get_children():
				(b as Button).disabled = not on
