extends RefCounted
# Invite links: graphduel://join?lobby=NAME&pw=PASSWORD&server=ws%3A%2F%2Fhost%3A8080

static func build(server: String, lobby: String, password: String) -> String:
	return "graphduel://join?lobby=%s&pw=%s&server=%s" % [lobby.uri_encode(), password.uri_encode(), server.uri_encode()]

static func parse(text: String) -> Dictionary:
	var t := text.strip_edges()
	var q := t.find("?")
	if q < 0 or not t.begins_with("graphduel://"):
		return {}
	var out := {"lobby": "", "pw": "", "server": ""}
	for pair in t.substr(q + 1).split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and out.has(kv[0]):
			out[kv[0]] = kv[1].uri_decode()
	if out["lobby"] == "" or out["pw"] == "":
		return {}
	return out
