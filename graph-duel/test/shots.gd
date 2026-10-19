extends SceneTree
# Renders screenshots of each screen (needs a display: run under xvfb-run).
const GameScreen = preload("res://scripts/game_screen.gd")
var main: Control
var out := "/tmp/claude-0/shots"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	run()

func shot(name: String) -> void:
	for i in range(4):
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name, " ", img.get_size())

func run() -> void:
	await shot("1_menu")
	main.menu.pw_edit.text = "k7x2mq"
	main.menu.pw_edit.secret = false
	main.menu.nick_edit.text = "Garvit"
	main.my_id = 1
	main.lobby_name = "swift-sine-42"
	main.password = "k7x2mq"
	main.server_url = "ws://localhost:8080"
	main.show_lobby()
	main.lobby.update_players(4, 1, [{"id": 1, "name": "Garvit", "hp": 100, "alive": true, "done": false}, {"id": 2, "name": "Ada", "hp": 100, "alive": true, "done": false}, {"id": 3, "name": "Linus", "hp": 100, "alive": true, "done": false}])
	await shot("2_lobby")
	var g = GameScreen.new()
	g.setup(main.net, 1, "swift-sine-42")
	main._swap(g)
	main.game = g
	await process_frame
	var cfg := {"radius": 0.5642, "maxOps": 20, "curveLife": 3, "hp": 100, "plane": 10}
	var plist := [{"id": 1, "name": "Garvit", "hp": 100, "alive": true, "done": false}, {"id": 2, "name": "Ada", "hp": 100, "alive": true, "done": false}, {"id": 3, "name": "Linus", "hp": 100, "alive": true, "done": false}, {"id": 4, "name": "Grace", "hp": 100, "alive": true, "done": false}]
	g.handle_message({"type": "start", "config": cfg, "order": [1, 2, 3, 4]})
	g.handle_message({"type": "state", "phase": "placement", "round": 0, "turn": null, "seconds": 80, "players": plist})
	g.board.clicked.emit(Vector2(-4.2, 3.5))
	await shot("3_placement")
	g.handle_message({"type": "placed", "x": -4.2, "y": 3.5})
	plist[1]["done"] = true
	g.handle_message({"type": "state", "phase": "plant", "round": 1, "turn": 1, "seconds": 55, "players": plist})
	g.handle_message({"type": "plant_ok", "curve": {"id": "1-1-ab", "formula": "4*sin(x)", "round": 1, "expires": 3}})
	g.handle_message({"type": "state", "phase": "plant", "round": 2, "turn": 1, "seconds": 55, "players": plist})
	g.calc.set_text("3sin(x)*cos(0.3x)+0.1x^2-2")
	await shot("4_plant_turn")
	g.handle_message({"type": "state", "phase": "relocate", "round": 2, "turn": null, "seconds": 40, "players": plist})
	g.board.clicked.emit(Vector2(5.5, -6.0))
	await shot("5_relocate")
	g.handle_message({"type": "round_result", "round": 2, "hits": [{"victim": 1, "attacker": 3, "dmg": 31, "curveId": "2-3-zz", "formula": "x-1", "d": 0.2, "at": {"x": 5.5, "y": -6.0}}, {"victim": 2, "attacker": 1, "dmg": 12, "curveId": "1-1-ab", "formula": "4*sin(x)", "d": 0.5, "at": {"x": 2.0, "y": 3.0}}], "hp": {"1": 69, "2": 88, "3": 100, "4": 100}, "eliminated": []})
	g.handle_message({"type": "state", "phase": "between", "round": 2, "turn": null, "seconds": 0, "players": g.players})
	await shot("6_after_hit")
	g.handle_message({"type": "game_over", "winners": [1], "reason": "last_standing", "hp": {"1": 69, "2": 0, "3": 0, "4": 0}, "positions": [{"id": 1, "x": 5.5, "y": -6.0}, {"id": 2, "x": -7.0, "y": 2.0}, {"id": 3, "x": 1.0, "y": 8.0}, {"id": 4, "x": 8.0, "y": 8.0}], "curves": [{"id": "2-3-zz", "owner": 3, "formula": "x-1"}, {"id": "2-2-yy", "owner": 2, "formula": "5/x"}, {"id": "2-4-qq", "owner": 4, "formula": "0.2*x^2-5"}]})
	await shot("7_game_over")
	g.overlay.visible = false
	await shot("8_reveal")
	quit(0)
