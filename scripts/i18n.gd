class_name I18n
extends RefCounted
## Interface languages: English (the game's own text) and Polish. Each data/lang_<code>.json (and the
## same name in the mods folder) maps the English text to its translation; "_language" holds the
## language's own name. tools/extract_strings.py collects the text to translate from the scripts and
## the data files.
##
## The game itself always works in English: the simulation, the event log and saves keep English text,
## so a save plays the same in every language. Text is translated only where it is shown: every label,
## button, tooltip and window title translates itself (Godot's auto-translate), and drawn text goes
## through tr(). A language file is loaded as a Table, which besides exact matches understands text
## built from a template: "%s is finished." in the file also translates "Sawmill is finished.", with
## the building's name translated in turn. Text of several lines is translated line by line.

## [code, name] of every language found, English first.
static func languages() -> Array:
	var out := [["en", "English"]]
	for code in _codes():
		var d := _read(code)
		out.append([code, String(d.get("_language", code))])
	return out


static func _codes() -> Array:
	var codes := []
	for dir in ["res://data", "user://data"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			# exported games list imported files with a .remap suffix; the json itself is kept as is
			if f.begins_with("lang_") and f.ends_with(".json"):
				var c := f.trim_prefix("lang_").trim_suffix(".json")
				if not codes.has(c):
					codes.append(c)
	codes.sort()
	return codes


static func _read(code: String) -> Dictionary:
	var out := {}
	for path in ["res://data/lang_%s.json" % code, "user://data/lang_%s.json" % code]:
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				out.merge(d, true)
	return out


static var _tables: Array = []
static var _added := false


## Loads every language and switches to code ("en" or "" for English).
static func setup(code: String) -> void:
	if _tables.is_empty():
		for c in _codes():
			var t := Table.new()
			t.locale = c
			t.load_dict(_read(c))
			_tables.append(t)
	set_language(code)


static func set_language(code: String) -> void:
	if code != "" and code != "en" and not _added and not _tables.is_empty():
		# the tables join the translation server the first time another language is chosen; being
		# written in script, they have to leave it again before the engine shuts down
		_added = true
		for t in _tables:
			TranslationServer.add_translation(t)
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null and tree.root.is_inside_tree():
			tree.root.tree_exiting.connect(unload)
	TranslationServer.set_locale(code if code != "" else "en")


## Takes the languages off the translation server (at exit; a test script that quits from _init
## calls it itself).
static func unload() -> void:
	if _added:
		for t in _tables:
			TranslationServer.remove_translation(t)
	_added = false


## The current language's text for s (s itself in English).
static func t(s: String) -> String:
	return String(TranslationServer.translate(s))


## One language's texts. Exact keys are looked up first; keys with %s, %d or %f in them also serve as
## templates for text that was built from them. A translation may give forms for counts, split by "|":
## the name on its own, then one, two to four, five and more: "Deski|deska|deski|desek" for planks, so
## "12 planks" becomes "12 desek". A template's forms are chosen by its first number. In a template's
## translation "%.0s" takes its value but shows nothing (for an English plural "s", say).
class Table extends Translation:
	var msgs := {}                 # English -> translation (forms still joined by "|")
	var lower := {}                # english.to_lower() -> translation, for names written in lower case
	var by_start := {}             # first two letters (lower case) -> [[RegEx, translation, kinds], ...]
	var loose: Array = []          # templates that start with a value
	var cache := {}
	var tag_re := RegEx.create_from_string("\\[/?[a-z_]+(?:=[^\\]]*)?\\]")
	var num_re := RegEx.create_from_string("^([-+]?[0-9][0-9.,]*%?|×[0-9]+|[0-9]+×)( +)(.+)$")
	var spec_re := RegEx.create_from_string("%[-+0-9.]*[sdfxX]")
	var _letters := RegEx.create_from_string("[^\\W\\d_]{2}")
	var _words := RegEx.create_from_string("[A-Za-z]{3,}")

	func load_dict(d: Dictionary) -> void:
		var tpl: Array = []
		for k in d:
			var key := String(k)
			var val := String(d[k])
			if key.begins_with("_") or val == "":
				continue
			_add(key, val, tpl)
			# text shown line by line is looked up without the spaces and line breaks around it
			var sk := key.strip_edges()
			if sk != key and sk != "" and not d.has(sk):
				_add(sk, val.strip_edges(), tpl)
		tpl.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
		# pieces the code puts before or after other text: " (near %s)", "Needs "
		var parts: Array = []
		for k in msgs:
			var key := String(k)
			var lit := spec_re.sub(key.replace("%%", ""), "", true)
			if _words.search(lit) == null or key.strip_edges() == "" or key.contains("\n"):
				continue
			if key.begins_with(" ") and not key.ends_with(" "):
				parts.append(["%s" + key, "%s" + String(msgs[k]), lit.length()])
			elif key.ends_with(" ") and not key.begins_with(" "):
				parts.append([key + "%s", String(msgs[k]) + "%s", lit.length()])
		parts.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
		tpl.append_array(parts)
		for e in tpl:
			var key := String(e[0])
			var re := RegEx.create_from_string("^" + _pattern(key) + "$")
			if not re.is_valid():
				continue
			var kinds := []
			for m in spec_re.search_all(key.replace("%%", "")):
				var sp := m.get_string()
				kinds.append(sp[sp.length() - 1])
			var entry := [re, e[1], kinds, key.contains("%d %s"), key.contains("[")]
			if key.begins_with("%") and not key.begins_with("%%"):
				loose.append(entry)
			else:
				var st := key.substr(0, 2).to_lower()
				if not by_start.has(st):
					by_start[st] = []
				by_start[st].append(entry)

	func _add(key: String, val: String, tpl: Array) -> void:
		if msgs.has(key):
			return
		msgs[key] = val
		var lk := key.to_lower()
		# headings in capitals ("CLEAR") are not names: "clear" weather is not the "CLEAR" tool group
		if not lower.has(lk) and key != key.to_upper():
			lower[lk] = val
		if key.contains("%") and spec_re.search(key) != null:
			var lit := spec_re.sub(key.replace("%%", ""), "", true)
			# a template needs some words of its own, or it would match anything
			if _words.search(lit) != null:
				tpl.append([key, val, lit.length()])

	## A key turned into a regular expression: each %s/%d/%f becomes a group.
	func _pattern(key: String) -> String:
		var out := ""
		var i := 0
		while i < key.length():
			var ch := key[i]
			if ch == "%":
				if i + 1 < key.length() and key[i + 1] == "%":
					out += "%"
					i += 2
					continue
				var m := spec_re.search(key, i)
				if m != null and m.get_start() == i:
					var spec := m.get_string()
					var kind := spec[spec.length() - 1]
					if kind == "s":
						out += "(.*?)"
					elif kind == "f":
						out += "([-+]?[0-9]+(?:\\.[0-9]+)?)"
					else:
						out += "([-+]?[0-9]+)"
					i = m.get_end()
					continue
			out += "\\" + ch if ".^$*+?()[]{}|\\/".contains(ch) else ch
			i += 1
		return out

	## Which form goes with the count n. A translation with forms reads "name|one|few|many"
	## (Polish: 1, 2 to 4 (but not 12 to 14), and the rest, which also takes fractions as "few").
	static func form(v: String, n: float) -> String:
		if v.count("|") != 3:
			return v
		var f := v.split("|")
		var i := absi(int(n))
		if absf(n - roundf(n)) > 0.001:
			return f[2]
		if i == 1:
			return f[1]
		if i % 10 >= 2 and i % 10 <= 4 and (i % 100 < 12 or i % 100 > 14):
			return f[2]
		return f[3]

	## A translation shown without a count: its first form.
	static func plain(v: String) -> String:
		if v.count("|") != 3:
			return v
		return v.split("|")[0]

	func _get_message(src: StringName, _ctx: StringName) -> StringName:
		return StringName(text(String(src)))

	func _get_plural_message(src: StringName, _plural: StringName, _n: int, _ctx: StringName) -> StringName:
		return StringName(text(String(src)))

	## The translation of s, or s when nothing fits.
	func text(s: String) -> String:
		if msgs.has(s):
			return plain(msgs[s])
		if cache.has(s):
			return cache[s]
		var out := _find(s, 0, -1.0)
		if cache.size() > 20000:
			cache.clear()
		cache[s] = out
		return out

	## n is the count in front of s (-1 when there is none), to choose a name's form.
	func _find(s: String, depth: int, n: float) -> String:
		if msgs.has(s):
			return form(msgs[s], n) if n >= 0.0 else plain(msgs[s])
		if s.length() < 2 or depth > 5 or not _letters.search(s):
			return s
		# several lines: each on its own
		if s.contains("\n"):
			var lines := s.split("\n")
			for k in lines.size():
				lines[k] = _sub(lines[k], depth)
			return "\n".join(lines)
		# spaces around it
		var core := s.strip_edges()
		if core != s:
			if core == "":
				return s
			var at := s.find(core)
			return s.substr(0, at) + _sub(core, depth) + s.substr(at + core.length())
		# names written in lower (or upper) case
		var lk := s.to_lower()
		if lower.has(lk):
			var v: String = form(lower[lk], n) if n >= 0.0 else plain(lower[lk])
			if s == lk and not v.contains("%"):
				return v.to_lower()
			if s.left(1) == s.left(1).to_upper():
				return v.left(1).to_upper() + v.substr(1)
			return v
		# a sentence mark after a known text
		for p in [".", ":", "!", "?", ",", ";"]:
			if s.ends_with(p) and s.length() > 2:
				var base := s.substr(0, s.length() - 1)
				if msgs.has(base) or lower.has(base.to_lower()):
					return _find(base, depth + 1, n) + p
		# text built from a template
		var r := _template(s, depth)
		if r != "":
			return r
		# a count in front: "12 planks", "+5% speed"
		var m := num_re.search(s)
		if m != null:
			var num := m.get_string(1).trim_suffix("%").replace(",", "").replace("×", "")
			var rest := _find(m.get_string(3), depth + 1, num.to_float() if not m.get_string(1).ends_with("%") else -1.0)
			if rest != m.get_string(3):
				return m.get_string(1) + m.get_string(2) + rest
		# markup: translate the words between the tags
		if s.contains("["):
			var parts := []
			var pos := 0
			var changed := false
			for tm in tag_re.search_all(s):
				if tm.get_start() > pos:
					var seg := s.substr(pos, tm.get_start() - pos)
					var tseg := _sub(seg, depth)
					changed = changed or tseg != seg
					parts.append(tseg)
				parts.append(tm.get_string())
				pos = tm.get_end()
			if pos > 0:
				if pos < s.length():
					var seg2 := s.substr(pos)
					var tseg2 := _sub(seg2, depth)
					changed = changed or tseg2 != seg2
					parts.append(tseg2)
				if changed:
					return "".join(parts)
		# lists and sentences: each part on its own
		for sep in ["  ", " · ", " | ", "; ", ". ", ", ", " — ", ": ", " / ", " and ", " or "]:
			if s.contains(sep):
				var bits := s.split(sep)
				var changed2 := false
				for k in bits.size():
					var tb := _sub(bits[k], depth)
					if tb != bits[k]:
						changed2 = true
						bits[k] = tb
				if changed2:
					var tsep: String = sep
					if sep == " and " or sep == " or ":
						tsep = " " + plain(msgs.get(sep.strip_edges(), sep.strip_edges())) + " "
					return tsep.join(bits)
		return s

	func _sub(s: String, depth: int) -> String:
		if msgs.has(s):
			return plain(msgs[s])
		if cache.has(s):
			return cache[s]
		var out := _find(s, depth + 1, -1.0)
		cache[s] = out
		return out

	func _template(s: String, depth: int) -> String:
		var lists: Array = []
		var st := s.substr(0, 2).to_lower()
		if by_start.has(st):
			lists.append(by_start[st])
		lists.append(loose)
		var tagged := s.contains("[")
		for list in lists:
			for e in list:
				# text with markup in it is built from pieces: a loose template without markup of its
				# own would swallow the tags; the pieces between the tags are translated instead
				if tagged and list == loose and not e[4]:
					continue
				var m: RegExMatch = (e[0] as RegEx).search(s)
				if m == null:
					continue
				var kinds: Array = e[2]
				var args := []
				var first_num := -1.0
				var last_num := -1.0
				for g in range(1, m.get_group_count() + 1):
					var a := m.get_string(g)
					var kind: String = kinds[g - 1] if g - 1 < kinds.size() else "s"
					if kind != "s":
						args.append(a)
						last_num = a.to_float()
						if first_num < 0.0: first_num = absf(last_num)
					else:
						# a name right after a count takes the form for that count ("%d %s")
						args.append(_find(a, depth + 1, last_num) if e[3] and last_num >= 0.0 else _sub(a, depth))
						last_num = -1.0
				return _fill(form(String(e[1]), first_num) if first_num >= 0.0 else plain(String(e[1])), args)
		return ""

	## The translation with the values put in, in order.
	func _fill(tr_text: String, args: Array) -> String:
		var out := ""
		var i := 0
		var n := 0
		while i < tr_text.length():
			var ch := tr_text[i]
			if ch == "%":
				if i + 1 < tr_text.length() and tr_text[i + 1] == "%":
					out += "%"
					i += 2
					continue
				var m := spec_re.search(tr_text, i)
				if m != null and m.get_start() == i:
					# "%.0s" leaves its value out (an English "s" for plurals, say)
					if m.get_string() != "%.0s":
						out += String(args[n]) if n < args.size() else ""
					n += 1
					i = m.get_end()
					continue
			out += ch
			i += 1
		return out
