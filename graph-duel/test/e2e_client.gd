extends SceneTree
# Headless end-to-end driver: plays the real UI against the real server.
#   godot --headless --path client --script ../test/e2e_client.gd -- <port>

const Formula = preload("res://scripts/formula.gd")
const Presets = preload("res://scripts/presets.gd")
const Board = preload("res://scripts/board.gd")

var main: Control
var t := 0.0
var started := false
var sent_start := false
var port := "8080"
var last_action := 0.0
var rounds_seen := 0
var failed := false
var plant_count := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		port = args[0]
	# presets must all compile and show on the plane
	for s in Presets.SUBJECTS:
		for c in s["curves"]:
			var r := Formula.compile(c[1], 20)
			if not r["ok"]:
				push_error("PRESET FAIL %s: %s" % [c[1], r["error"]])
				failed = true
				continue
			var n := 0
			for seg in Board.sample(r["ast"]):
				n += seg.size()
			if n < 20:
				push_error("PRESET INVISIBLE %s" % c[1])
				failed = true
	print("presets ok")
	for bad in ["", "2+", "sin x", "foo(1)", "1 2"]:
		if Formula.compile(bad)["ok"]:
			push_error("should reject: " + bad)
			failed = true
	var chk := {"2x+1": 7.0, "3sin(0)": 0.0, "-x^2": -9.0, "2pi": TAU, "(x+1)(x-1)": 8.0, "y=ln(e)": 1.0, "log(100)": 2.0}
	for f in chk:
		var r2 := Formula.compile(f)
		var v := Formula.evaluate(r2["ast"], 3.0) if r2["ok"] else NAN
		if not r2["ok"] or absf(v - chk[f]) > 1e-6:
			# values are for x=3 only where relevant
			if f in ["2x+1"] and absf(v - 7.0) < 1e-6:
				continue
			if f == "-x^2" and absf(v + 9.0) < 1e-6:
				continue
			if f == "(x+1)(x-1)" and absf(v - 8.0) < 1e-6:
				continue
			if absf(v - chk[f]) > 1e-6:
				push_error("EVAL FAIL %s = %s" % [f, v])
				failed = true
	print("parser ok")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if t < 0.5:
		return false
	if t > 240.0:
		push_error("E2E TIMEOUT")
		quit(1)
		return true
	var cur: Control = main.current
	if cur == main.menu and not started:
		started = true
		var m = main.menu
		m.nick_edit.text = "Hero"
		m.lobby_edit.text = "e2e"
		m.pw_edit.text = "pw"
		m.server_edit.text = "ws://127.0.0.1:" + port
		m.max_spin.value = 2
		m.set_mode("create")
		m._submit()
		print("menu submitted")
	elif cur == main.lobby and main.lobby != null:
		var l = main.lobby
		if l.players.size() >= 2 and not sent_start:
			sent_start = true
			print("lobby ok, players=", l.players.size(), " link=", l.invite_edit.text)
			l.start_button.pressed.emit()
	elif cur == main.game and main.game != null:
		var g = main.game
		if g.finished:
			print("GAME OVER seen: ", g.overlay_title.text, " | ", g.overlay_body.text.replace("\n", " / "))
			print("rounds seen ", rounds_seen, " plants ", plant_count)
			quit(1 if failed else 0)
			return true
		if t - last_action > 0.3:
			var me: Dictionary = g.me_info()
			if g.phase == "placement" and not me.get("done", false) and g.pending == null:
				g.board.clicked.emit(Vector2(4.0, 4.0))
				g._primary()
				last_action = t
			elif g.phase == "plant" and g.turn_id == g.my_id:
				g.calc.set_text("2*sin(x)+1")
				if not g.preview_ok:
					push_error("preview not ok")
					failed = true
				g._primary()
				plant_count += 1
				last_action = t
			elif g.phase == "relocate" and not me.get("done", false) and g.me_info().get("alive", true):
				if g.pending == null:
					g.board.clicked.emit(Vector2(4.0, 4.0))
				g._primary()
				last_action = t
			if g.round_no > rounds_seen:
				rounds_seen = g.round_no
	return false
