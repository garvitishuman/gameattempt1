extends Control
# In-game screen: hidden-position plane, turn-based curve planting, relocation, results.

signal leave_requested
signal back_to_lobby

const UI = preload("res://scripts/ui.gd")
const Formula = preload("res://scripts/formula.gd")
const Board = preload("res://scripts/board.gd")
const Calculator = preload("res://scripts/calculator.gd")
const Presets = preload("res://scripts/presets.gd")

var net: Node
var my_id := 0
var lobby_name := ""
var cfg := {"radius": 0.5642, "maxOps": 20, "curveLife": 3, "hp": 100}
var order: Array = []
var players: Array = []          # {id, name, hp, alive, done}
var phase := "placement"
var round_no := 0
var turn_id := 0
var seconds_left := 0.0
var my_pos = null                # Vector2 or null
var pending = null               # chosen, not yet confirmed
var my_next = null               # confirmed relocation target (applied when the round resolves)
var my_curves: Array = []        # {id, formula, round, expires, segments}
var known_curves: Array = []     # enemy curves revealed to me {id, owner, formula, expires, segments}
var finished := false
var flash_text := ""
var flash_time := 0.0
var my_color := UI.PLAYER_COLORS[0]

var board: Control
var calc: VBoxContainer
var status_label: Label
var round_label: Label
var timer_label: Label
var info_label: Label
var players_box: VBoxContainer
var primary: Button
var pass_btn: Button
var log_box: RichTextLabel
var subject_opt: OptionButton
var preset_flow: HFlowContainer
var overlay: Control
var overlay_title: Label
var overlay_body: Label
var preview_ok := false

func setup(n: Node, id: int, lobby: String) -> void:
	net = n
	my_id = id
	lobby_name = lobby

func _ready() -> void:
	UI.full_rect(self)
	var margin := MarginContainer.new()
	UI.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	round_label = UI.label("", 18, UI.MUTED)
	round_label.custom_minimum_size = Vector2(200, 0)
	top.add_child(round_label)
	status_label = UI.label("", 20, UI.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	top.add_child(status_label)
	timer_label = UI.label("", 18, UI.WARN)
	timer_label.custom_minimum_size = Vector2(90, 0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(timer_label)
	var leave := UI.button("Leave", 32.0)
	leave.pressed.connect(func(): leave_requested.emit())
	top.add_child(leave)
	root.add_child(top)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	# left: board + log
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	main.add_child(left)
	board = Board.new()
	board.custom_minimum_size = Vector2(560, 560)
	board.clicked.connect(_on_board_clicked)
	left.add_child(board)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.custom_minimum_size = Vector2(560, 60)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(log_box)

	# right: players, calculator, presets, actions
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)

	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", UI.sb(UI.PANEL, UI.BORDER, 1, 10, 8))
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 2)
	pp.add_child(players_box)
	right.add_child(pp)

	var cap := UI.label("Design your curve  (calculator, or just type)", 13, UI.MUTED)
	right.add_child(cap)
	calc = Calculator.new()
	calc.changed.connect(_on_formula_changed)
	calc.submitted.connect(func(_t: String): _primary())
	right.add_child(calc)
	info_label = UI.label("", 14, UI.MUTED)
	info_label.clip_text = true
	right.add_child(info_label)

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	prow.add_child(UI.label("Subject packs:", 14, UI.MUTED))
	subject_opt = OptionButton.new()
	subject_opt.focus_mode = Control.FOCUS_NONE
	for s in Presets.SUBJECTS:
		subject_opt.add_item(s["name"])
	subject_opt.item_selected.connect(func(_i: int): _fill_presets())
	prow.add_child(subject_opt)
	right.add_child(prow)
	preset_flow = HFlowContainer.new()
	preset_flow.add_theme_constant_override("h_separation", 4)
	preset_flow.add_theme_constant_override("v_separation", 4)
	right.add_child(preset_flow)

	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	pass_btn = UI.button("Pass", 44.0)
	pass_btn.pressed.connect(func(): net.send_msg({"type": "pass"}))
	arow.add_child(pass_btn)
	primary = UI.button("", 44.0)
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.add_theme_font_size_override("font_size", 20)
	primary.pressed.connect(_primary)
	arow.add_child(primary)
	right.add_child(arow)

	_build_overlay()
	_fill_presets()
	_refresh()

func _build_overlay() -> void:
	overlay = Control.new()
	UI.full_rect(overlay)
	overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UI.full_rect(dim)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	UI.full_rect(center)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	overlay_title = UI.label("", 36, UI.ACCENT)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(overlay_title)
	overlay_body = UI.label("", 17, UI.TEXT)
	overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(overlay_body)
	var look := UI.button("Look at the revealed board", 40.0)
	look.pressed.connect(func(): overlay.visible = false)
	v.add_child(look)
	var back := UI.button("Back to lobby", 44.0)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(func(): back_to_lobby.emit())
	v.add_child(back)
	add_child(overlay)

func _fill_presets() -> void:
	for ch in preset_flow.get_children():
		ch.queue_free()
	var subj: Dictionary = Presets.SUBJECTS[subject_opt.selected]
	for c in subj["curves"]:
		var b := UI.button(c[0], 30.0)
		b.tooltip_text = "y = " + c[1]
		var f: String = c[1]
		b.pressed.connect(func(): calc.set_text(f))
		preset_flow.add_child(b)

# ---------------------------------------------------------------- helpers
func name_of(id: int) -> String:
	for p in players:
		if int(p["id"]) == id:
			return p["name"]
	return "Player"

func color_of(id: int) -> Color:
	return UI.color_for(order, id)

func me_info() -> Dictionary:
	for p in players:
		if int(p["id"]) == my_id:
			return p
	return {}

func tag(id: int) -> String:
	return "[color=#%s]%s[/color]" % [color_of(id).to_html(false), name_of(id)]

func log_line(bb: String) -> void:
	log_box.append_text(bb + "\n")

func flash(msg: String) -> void:
	flash_text = msg
	flash_time = 3.5
	_refresh()

func _process(delta: float) -> void:
	if seconds_left > 0.0:
		seconds_left = maxf(0.0, seconds_left - delta)
	timer_label.text = ("%ds" % int(ceil(seconds_left))) if seconds_left > 0.0 and not finished else ""
	if flash_time > 0.0:
		flash_time -= delta
		if flash_time <= 0.0:
			flash_text = ""
			_refresh()

# ---------------------------------------------------------------- input
func _on_board_clicked(p: Vector2) -> void:
	if board.mode == "none":
		return
	pending = p
	_refresh()

func _on_formula_changed(text: String) -> void:
	if text.strip_edges() == "":
		board.preview = []
		preview_ok = false
		info_label.text = "Preview appears here as a dashed white curve."
		info_label.add_theme_color_override("font_color", UI.MUTED)
	else:
		var res := Formula.compile(text, int(cfg["maxOps"]))
		if res["ok"]:
			board.preview = Board.sample(res["ast"])
			preview_ok = true
			var vis := 0
			for s in board.preview:
				vis += s.size()
			if vis < 4:
				preview_ok = false
				info_label.text = "That curve never appears on the plane."
				info_label.add_theme_color_override("font_color", UI.WARN)
			else:
				info_label.text = "y = %s     (complexity %d / %d)" % [res["src"], res["ops"], int(cfg["maxOps"])]
				info_label.add_theme_color_override("font_color", UI.GOOD)
		else:
			board.preview = []
			preview_ok = false
			info_label.text = res["error"]
			info_label.add_theme_color_override("font_color", UI.BAD)
	board.queue_redraw()
	_refresh()

func _primary() -> void:
	if finished:
		back_to_lobby.emit()
		return
	match phase:
		"placement":
			if pending != null:
				net.send_msg({"type": "place", "x": pending.x, "y": pending.y})
		"plant":
			if turn_id == my_id:
				var res := Formula.compile(calc.edit.text, int(cfg["maxOps"]))
				if not res["ok"]:
					flash(res["error"])
				elif not preview_ok:
					flash("That curve never appears on the plane.")
				else:
					net.send_msg({"type": "plant", "formula": res["src"]})
		"relocate":
			if pending != null:
				net.send_msg({"type": "relocate", "x": pending.x, "y": pending.y})

# ---------------------------------------------------------------- UI refresh
func _refresh() -> void:
	if not is_node_ready():
		return
	var me := me_info()
	var alive: bool = me.get("alive", true)
	var done: bool = me.get("done", false)
	var my_turn := phase == "plant" and turn_id == my_id and alive
	board.my_color = my_color
	board.my_pos = my_pos
	board.pending = pending
	board.radius_units = float(cfg["radius"])
	board.mode = "none"
	pass_btn.visible = false
	primary.disabled = true
	var status := ""
	var col := UI.TEXT
	round_label.text = "%s   Round %d" % [lobby_name, round_no] if round_no > 0 else lobby_name
	if finished:
		status = "Game over."
		primary.text = "Back to lobby"
		primary.disabled = false
	elif not alive:
		status = "You were eliminated. Spectating."
		col = UI.BAD
		primary.text = "Eliminated"
	else:
		match phase:
			"placement":
				board.mode = "place"
				if pending != null:
					primary.text = "Lock in position (%.1f, %.1f)" % [pending.x, pending.y]
					primary.disabled = false
					status = "Click again to adjust, then lock in."
				elif done:
					primary.text = "Position locked"
					status = "Locked. Waiting for the others... (click to change)"
				else:
					primary.text = "Click the plane to place your circle"
					status = "Place your circle anywhere. Nobody else sees it."
			"plant":
				if my_turn:
					primary.text = "Plant curve  (Enter)"
					primary.disabled = not preview_ok
					pass_btn.visible = true
					status = "YOUR TURN: design a curve and plant it."
					col = UI.GOOD
				else:
					primary.text = "Waiting for %s..." % name_of(turn_id)
					status = "%s is planting a curve." % name_of(turn_id)
			"relocate":
				if done:
					primary.text = "Move confirmed"
					status = "Waiting for the others to relocate..."
				else:
					board.mode = "relocate"
					status = "Relocate: pick a new spot. Landing on someone's curve hurts."
					col = UI.WARN
					if pending != null:
						primary.text = "Move to (%.1f, %.1f)" % [pending.x, pending.y]
						primary.disabled = false
					else:
						primary.text = "Click the plane to choose where to move"
			_:
				primary.text = "Resolving..."
				status = "Round %d resolved. Next round starting..." % round_no
	if flash_text != "":
		status = flash_text
		col = UI.BAD
	status_label.text = status
	status_label.add_theme_color_override("font_color", col)
	_rebuild_players()
	_rebuild_curves()
	board.queue_redraw()

func _rebuild_players() -> void:
	for ch in players_box.get_children():
		ch.queue_free()
	for p in players:
		var id := int(p["id"])
		var alive: bool = p["alive"]
		var c := color_of(id)
		if not alive:
			c = c.darkened(0.6)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var nm := UI.label(p["name"] + ("  (you)" if id == my_id else ""), 15, c if alive else UI.MUTED)
		nm.custom_minimum_size = Vector2(150, 0)
		nm.clip_text = true
		row.add_child(nm)
		var bar := ProgressBar.new()
		bar.max_value = float(cfg["hp"])
		bar.value = maxf(0.0, float(p["hp"]))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("fill", UI.sb(c, Color(0, 0, 0, 0), 0, 4, 2))
		row.add_child(bar)
		var hp := UI.label(str(maxi(0, int(p["hp"]))), 15)
		hp.custom_minimum_size = Vector2(34, 0)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(hp)
		var st := ""
		if not alive:
			st = "out"
		else:
			match phase:
				"placement":
					st = "ready" if p["done"] else "placing..."
				"plant":
					st = "planting..." if id == turn_id else ("planted" if p["done"] else "waiting")
				"relocate":
					st = "moved" if p["done"] else "moving..."
		var stl := UI.label(st, 13, UI.MUTED)
		stl.custom_minimum_size = Vector2(80, 0)
		row.add_child(stl)
		players_box.add_child(row)

func _rebuild_curves() -> void:
	var items: Array = []
	var life_adj := 0 if phase == "between" else 1
	for c in my_curves:
		var rem := int(c["expires"]) - round_no + life_adj
		items.append({"segments": c["segments"], "color": my_color, "alpha": clampf(0.35 + 0.22 * rem, 0.3, 1.0), "label": "%s  [%d left]" % [c["formula"], maxi(rem, 0)] if not finished else c["formula"]})
	for c in known_curves:
		var rem2 := int(c["expires"]) - round_no + life_adj
		var lab: String = "%s: %s" % [name_of(int(c["owner"])), c["formula"]]
		items.append({"segments": c["segments"], "color": color_of(int(c["owner"])), "alpha": 0.9 if finished else clampf(0.35 + 0.22 * rem2, 0.3, 0.95), "label": lab})
	board.curves = items

func _curve_round(curve_id: String) -> int:
	return int(curve_id.split("-")[0])

# ---------------------------------------------------------------- server messages
func handle_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"start":
			cfg = msg["config"]
			order = []
			for x in msg["order"]:
				order.append(int(x))
			my_color = color_of(my_id)
			my_pos = null
			pending = null
			my_next = null
			my_curves.clear()
			known_curves.clear()
			board.reveal = []
			board.pulses.clear()
			board.preview = []
			finished = false
			overlay.visible = false
			round_no = 0
			phase = "placement"
			log_box.clear()
			log_line("[color=#8f96c8]Game started. Place your circle. Positions stay hidden.[/color]")
			_on_formula_changed(calc.edit.text)
		"state":
			var prev := phase
			phase = str(msg["phase"])
			round_no = int(msg["round"])
			var t = msg.get("turn")
			turn_id = int(t) if t != null else 0
			seconds_left = float(msg.get("seconds", 0))
			players = msg["players"]
			if phase == "relocate" and prev != "relocate":
				pending = null
				my_next = null
				log_line("[color=#ffb04d]Relocate! Everyone moves now.[/color]")
			if phase == "plant" and prev != "plant":
				log_line("[color=#8f96c8]--- Round %d: planting turns ---[/color]" % round_no)
			_refresh()
		"placed":
			my_pos = Vector2(float(msg["x"]), float(msg["y"]))
			pending = null
			_refresh()
		"relocated":
			my_next = Vector2(float(msg["x"]), float(msg["y"]))
			pending = my_next
			_refresh()
		"plant_ok":
			var cv: Dictionary = msg["curve"]
			var res := Formula.compile(str(cv["formula"]), 99)
			if res["ok"]:
				my_curves.append({"id": cv["id"], "formula": cv["formula"], "round": int(cv["round"]), "expires": int(cv["expires"]), "segments": Board.sample(res["ast"])})
			log_line("You planted [color=#%s]y = %s[/color]" % [my_color.to_html(false), cv["formula"]])
			_refresh()
		"planted":
			var by := int(msg["by"])
			if by != my_id:
				log_line("%s %s." % [tag(by), "passed" if msg.get("passed", false) else "planted a curve"])
		"round_result":
			_on_round_result(msg)
		"game_over":
			_on_game_over(msg)
		"left":
			log_line("[color=#8f96c8]%s left the game.[/color]" % str(msg["name"]))
		"error":
			flash(str(msg["msg"]))

func _on_round_result(msg: Dictionary) -> void:
	var hpmap: Dictionary = msg["hp"]
	for p in players:
		var k := str(int(p["id"]))
		if hpmap.has(k):
			p["hp"] = float(hpmap[k])
	var after_round := int(msg["round"])
	if my_next != null:
		my_pos = my_next
	var my_here = my_pos
	if msg["hits"].is_empty():
		log_line("[color=#5be39a]Round %d: nobody was hit.[/color]" % after_round)
	for h in msg["hits"]:
		var victim := int(h["victim"])
		var attacker := int(h["attacker"])
		var dmg := int(h["dmg"])
		if victim == my_id:
			log_line("[color=#ff4d6d]You landed on %s's curve  y = %s  and took %d damage.[/color]" % [name_of(attacker), str(h.get("formula", "?")), dmg])
			if my_here != null:
				board.add_pulse(my_here, UI.BAD)
			if h.has("formula") and not _known(str(h["curveId"])):
				var res := Formula.compile(str(h["formula"]), 99)
				if res["ok"]:
					known_curves.append({"id": h["curveId"], "owner": attacker, "formula": h["formula"], "expires": _curve_round(str(h["curveId"])) + int(cfg["curveLife"]) - 1, "segments": Board.sample(res["ast"])})
		elif attacker == my_id:
			var at := Vector2(float(h["at"]["x"]), float(h["at"]["y"]))
			board.add_pulse(at, my_color)
			log_line("[color=#5be39a]Your curve y = %s hit %s for %d damage, near (%.1f, %.1f).[/color]" % [str(h.get("formula", "?")), name_of(victim), dmg, at.x, at.y])
		else:
			log_line("%s's curve hit %s for %d." % [tag(attacker), tag(victim), dmg])
	for x in msg["eliminated"]:
		var eid := int(x)
		for p in players:
			if int(p["id"]) == eid:
				p["alive"] = false
		if eid == my_id:
			log_line("[color=#ff4d6d]You have been eliminated.[/color]")
		else:
			log_line("%s was eliminated." % tag(eid))
	# expire old curves
	var keep := after_round + 1
	my_curves = my_curves.filter(func(c): return int(c["expires"]) >= keep)
	known_curves = known_curves.filter(func(c): return int(c["expires"]) >= keep)
	pending = null
	my_next = null
	_refresh()

func _known(curve_id: String) -> bool:
	for c in known_curves:
		if c["id"] == curve_id:
			return true
	return false

func _on_game_over(msg: Dictionary) -> void:
	finished = true
	var hpmap: Dictionary = msg.get("hp", {})
	for p in players:
		var k := str(int(p["id"]))
		if hpmap.has(k):
			p["hp"] = float(hpmap[k])
	# reveal everything
	var rev: Array = []
	for r in msg.get("positions", []):
		if r["x"] != null:
			rev.append({"p": Vector2(float(r["x"]), float(r["y"])), "color": color_of(int(r["id"])), "name": name_of(int(r["id"]))})
	board.reveal = rev
	known_curves.clear()
	my_curves.clear()
	for c in msg.get("curves", []):
		var res := Formula.compile(str(c["formula"]), 99)
		if res["ok"]:
			known_curves.append({"id": c["id"], "owner": int(c["owner"]), "formula": c["formula"], "expires": 9999, "segments": Board.sample(res["ast"])})
	pending = null
	var winners: Array = []
	for w in msg["winners"]:
		winners.append(int(w))
	var names: Array = []
	for w in winners:
		names.append(name_of(w))
	var reason := str(msg.get("reason", ""))
	if winners.size() > 1:
		overlay_title.text = "Draw: %s" % " & ".join(names)
		overlay_title.add_theme_color_override("font_color", UI.WARN)
	elif winners.has(my_id):
		overlay_title.text = "YOU WIN!"
		overlay_title.add_theme_color_override("font_color", UI.GOOD)
	else:
		overlay_title.text = "%s wins" % " & ".join(names) if not names.is_empty() else "Nobody wins"
		overlay_title.add_theme_color_override("font_color", UI.ACCENT)
	var why := {"last_standing": "Last one standing.", "mutual_destruction": "Everyone fell in the same round. Highest HP takes it.", "round_limit": "Round limit reached. Highest HP takes it.", "opponents_left": "Everyone else left the game."}
	var lines: Array = [why.get(reason, "")]
	var sorted := players.duplicate()
	sorted.sort_custom(func(a, b): return float(a["hp"]) > float(b["hp"]))
	for p in sorted:
		lines.append("%s: %d HP" % [p["name"], maxi(0, int(p["hp"]))])
	overlay_body.text = "\n".join(lines)
	overlay.visible = true
	log_line("[color=#ffb04d]Game over. All positions and curves are revealed on the board.[/color]")
	_refresh()
