extends RefCounted
# Safe formula parser/evaluator for y = f(x). No eval().
# Mirrors server/formula.js so previews match what the server resolves.
# Supports + - * / ^, parentheses, implicit multiplication (2x, 3sin(x), (x+1)(x-1)),
# constants pi and e, and sin cos tan asin acos atan sinh cosh tanh exp ln log sqrt abs floor.

const FUNCS := ["sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "exp", "ln", "log", "sqrt", "abs", "floor"]

var toks: Array = []
var pos := 0
var ops := 0
var error := ""

static func normalize(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	s = s.replace("×", "*").replace("÷", "/").replace("−", "-").replace("π", "pi").replace("**", "^")
	var re := RegEx.create_from_string("^(y|f\\(x\\))\\s*=")
	var m := re.search(s)
	if m != null:
		s = s.substr(m.get_end())
	return s.strip_edges()

static func compile(raw: String, max_ops: int = 20) -> Dictionary:
	var p = load("res://scripts/formula.gd").new()
	return p.run(raw, max_ops)

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "ast": {}, "ops": 0, "src": ""}

func run(raw: String, max_ops: int) -> Dictionary:
	var src := normalize(raw)
	if src == "":
		return _fail("Type a formula first.")
	if src.length() > 120:
		return _fail("Formula too long.")
	toks = _tokenize(src)
	if error != "":
		return _fail(error)
	pos = 0
	ops = 0
	var ast = _expr()
	if error == "" and pos < toks.size():
		error = "Unexpected input near the end of the formula."
	if error != "":
		return _fail(error)
	if ops > max_ops:
		return _fail("Too complex (%d of %d operations)." % [ops, max_ops])
	return {"ok": true, "error": "", "ast": ast, "ops": ops, "src": src}

func _tokenize(s: String) -> Array:
	var out: Array = []
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == " ":
			i += 1
		elif (c >= "0" and c <= "9") or c == ".":
			var j := i
			while j < s.length() and ((s[j] >= "0" and s[j] <= "9") or s[j] == "."):
				j += 1
			var text := s.substr(i, j - i)
			if text.count(".") > 1 or text == ".":
				error = "Bad number: " + text
				return []
			out.append({"t": "num", "v": text.to_float(), "c": false})
			i = j
		elif c >= "a" and c <= "z":
			var j2 := i
			while j2 < s.length() and s[j2] >= "a" and s[j2] <= "z":
				j2 += 1
			var w := s.substr(i, j2 - i)
			i = j2
			if w == "x":
				out.append({"t": "x", "v": 0.0, "c": false})
			elif w == "pi":
				out.append({"t": "num", "v": PI, "c": true})
			elif w == "e":
				out.append({"t": "num", "v": exp(1.0), "c": true})
			elif FUNCS.has(w):
				out.append({"t": "fn", "v": w, "c": false})
			else:
				error = "Unknown word: " + w
				return []
		elif c in "+-*/^(),":
			out.append({"t": "op", "v": c, "c": false})
			i += 1
		else:
			error = "Unexpected character: " + c
			return []
	# implicit multiplication
	var res: Array = []
	for k in range(out.size()):
		var b: Dictionary = out[k]
		if k > 0:
			var a: Dictionary = out[k - 1]
			var closing: bool = a["t"] == "num" or a["t"] == "x" or (a["t"] == "op" and a["v"] == ")")
			var opening: bool = b["t"] == "num" or b["t"] == "x" or b["t"] == "fn" or (b["t"] == "op" and b["v"] == "(")
			var both_plain_nums: bool = a["t"] == "num" and b["t"] == "num" and not a["c"] and not b["c"]
			if closing and opening and not both_plain_nums:
				res.append({"t": "op", "v": "*", "c": false})
		res.append(b)
	return res

func _peek() -> Dictionary:
	if pos < toks.size():
		return toks[pos]
	return {"t": "end", "v": "", "c": false}

func _is_op(v: String) -> bool:
	var p := _peek()
	return p["t"] == "op" and p["v"] == v

func _expr():
	var a = _term()
	while error == "" and (_is_op("+") or _is_op("-")):
		var op: String = _peek()["v"]
		pos += 1
		var b = _term()
		ops += 1
		a = {"k": "bin", "op": op, "a": a, "b": b}
	return a

func _term():
	var a = _unary()
	while error == "" and (_is_op("*") or _is_op("/")):
		var op: String = _peek()["v"]
		pos += 1
		var b = _unary()
		ops += 1
		a = {"k": "bin", "op": op, "a": a, "b": b}
	return a

func _unary():
	if _is_op("-"):
		pos += 1
		var a = _unary()
		return {"k": "neg", "a": a}
	if _is_op("+"):
		pos += 1
		return _unary()
	return _power()

func _power():
	var base = _atom()
	if error == "" and _is_op("^"):
		pos += 1
		var ex = _unary()
		ops += 1
		return {"k": "bin", "op": "^", "a": base, "b": ex}
	return base

func _atom():
	var p := _peek()
	if p["t"] == "num":
		pos += 1
		return {"k": "num", "v": p["v"]}
	if p["t"] == "x":
		pos += 1
		return {"k": "x"}
	if p["t"] == "fn":
		pos += 1
		var name: String = p["v"]
		if not _is_op("("):
			error = "Use parentheses: " + name + "(...)"
			return null
		pos += 1
		var arg = _expr()
		if error != "":
			return null
		if not _is_op(")"):
			error = "Missing )"
			return null
		pos += 1
		ops += 1
		return {"k": "fn", "n": name, "a": arg}
	if _is_op("("):
		pos += 1
		var inner = _expr()
		if error != "":
			return null
		if not _is_op(")"):
			error = "Missing )"
			return null
		pos += 1
		return inner
	error = "Unexpected end or symbol in formula."
	return null

static func evaluate(n: Dictionary, x: float) -> float:
	match n["k"]:
		"num":
			return n["v"]
		"x":
			return x
		"neg":
			return -evaluate(n["a"], x)
		"bin":
			var a: float = evaluate(n["a"], x)
			var b: float = evaluate(n["b"], x)
			match n["op"]:
				"+":
					return a + b
				"-":
					return a - b
				"*":
					return a * b
				"/":
					return a / b if b != 0.0 else INF
				"^":
					return pow(a, b)
		"fn":
			var v: float = evaluate(n["a"], x)
			match n["n"]:
				"sin":
					return sin(v)
				"cos":
					return cos(v)
				"tan":
					return tan(v)
				"asin":
					return asin(v) if v >= -1.0 and v <= 1.0 else NAN
				"acos":
					return acos(v) if v >= -1.0 and v <= 1.0 else NAN
				"atan":
					return atan(v)
				"sinh":
					return sinh(v)
				"cosh":
					return cosh(clampf(v, -50.0, 50.0))
				"tanh":
					return tanh(v)
				"exp":
					return exp(clampf(v, -50.0, 50.0))
				"ln":
					return log(v) if v > 0.0 else NAN
				"log":
					return log(v) / log(10.0) if v > 0.0 else NAN
				"sqrt":
					return sqrt(v) if v >= 0.0 else NAN
				"abs":
					return absf(v)
				"floor":
					return floorf(v)
	return NAN
