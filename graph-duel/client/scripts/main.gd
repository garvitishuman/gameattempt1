extends Control
# Screen router: menu -> lobby -> game -> lobby. Owns the network client.

const UI = preload("res://scripts/ui.gd")
const Net = preload("res://scripts/net.gd")
const MenuScreen = preload("res://scripts/menu_screen.gd")
const LobbyScreen = preload("res://scripts/lobby_screen.gd")
const GameScreen = preload("res://scripts/game_screen.gd")
const Invite = preload("res://scripts/invite.gd")

var net: Node
var menu: Control
var lobby: Control
var game: Control
var current: Control
var pending_action: Dictionary = {}
var server_url := ""
var password := ""
var my_id := 0
var lobby_name := ""
var in_game := false
var last_lobby: Dictionary = {}

func _ready() -> void:
	theme = UI.make_theme()
	UI.full_rect(self)
	var bg := ColorRect.new()
	bg.color = UI.BG
	UI.full_rect(bg)
	add_child(bg)
	net = Net.new()
	add_child(net)
	net.connected.connect(_on_connected)
	net.closed.connect(_on_closed)
	net.message.connect(_on_message)
	show_menu()
	# optional: godot -- --invite="graphduel://join?..."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--invite="):
			menu.apply_invite_text(a.substr(9))

func _swap(node: Control) -> void:
	if current != null:
		current.queue_free()
	current = node
	add_child(node)

func show_menu(error: String = "") -> void:
	in_game = false
	game = null
	lobby = null
	menu = MenuScreen.new()
	menu.create_requested.connect(func(server: String, lobby_n: String, pw: String, max_p: int, nick: String):
		pending_action = {"type": "create", "lobby": lobby_n, "password": pw, "max": max_p, "name": nick}
		_connect(server, pw))
	menu.join_requested.connect(func(server: String, lobby_n: String, pw: String, nick: String):
		pending_action = {"type": "join", "lobby": lobby_n, "password": pw, "name": nick}
		_connect(server, pw))
	_swap(menu)
	if error != "":
		menu.show_error(error)

func _connect(server: String, pw: String) -> void:
	server_url = server
	password = pw
	net.close_conn()
	var err: int = net.open_url(server)
	if err != OK:
		menu.show_error("Bad server address.")

func _on_connected() -> void:
	if not pending_action.is_empty():
		net.send_msg(pending_action)
		pending_action = {}

func _on_closed(reason: String) -> void:
	pending_action = {}
	show_menu(reason)

func show_lobby() -> void:
	in_game = false
	game = null
	lobby = LobbyScreen.new()
	lobby.set_info(lobby_name, password, server_url, my_id)
	if not last_lobby.is_empty():
		lobby.update_players(int(last_lobby["max"]), int(last_lobby["creator"]), last_lobby["players"])
	lobby.start_requested.connect(func(): net.send_msg({"type": "start"}))
	lobby.leave_requested.connect(_leave)
	_swap(lobby)

func _leave() -> void:
	net.send_msg({"type": "leave"})
	net.close_conn()
	show_menu()

func _on_message(msg: Dictionary) -> void:
	var t := str(msg.get("type", ""))
	match t:
		"joined":
			last_lobby = {}
			my_id = int(msg["you"])
			lobby_name = str(msg["lobby"])
			show_lobby()
		"lobby":
			last_lobby = msg
			if lobby != null and is_instance_valid(lobby):
				lobby.update_players(int(msg["max"]), int(msg["creator"]), msg["players"])
			elif menu != null and current == menu:
				pass
		"start":
			in_game = true
			game = GameScreen.new()
			game.setup(net, my_id, lobby_name)
			game.leave_requested.connect(_leave)
			game.back_to_lobby.connect(show_lobby)
			_swap(game)
			game.handle_message(msg)
		"error":
			if current == menu:
				menu.show_error(str(msg["msg"]))
				net.close_conn()
			elif lobby != null and current == lobby:
				lobby.hint_label.text = str(msg["msg"])
			elif game != null:
				game.handle_message(msg)
		"left_lobby":
			pass
		_:
			if game != null and is_instance_valid(game) and current == game:
				game.handle_message(msg)
