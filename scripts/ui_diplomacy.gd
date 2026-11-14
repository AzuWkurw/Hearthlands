class_name UiDiplomacy
extends RefCounted
## The Diplomacy window: alliances, peace, war and trade with rivals.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var dip_props: VBoxContainer
var dip_web: RichTextLabel
var trade_want_n: SpinBox
var trade_repeat: CheckBox
var trade_hint: Label
var standing_box: VBoxContainer


func _init(p_owner: Main) -> void:
	main = p_owner


func _on_diplomacy_changed() -> void:
	if main.dip_panel.visible:
		_fill_diplomacy()
	_update_dip_button()


func _update_dip_button() -> void:
	var n := main.sim.proposals.size()
	main.dip_btn.text = tr("Diplomacy (%d)") % n if n > 0 else "Diplomacy"


func _build_diplomacy_panel() -> void:
	main.dip_panel = main._overlay()
	var v := main._body(main.dip_panel)
	var row := HBoxContainer.new(); v.add_child(row)
	var tl := main._label("Diplomacy", 24, Main.BRASS); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(tl)
	row.add_child(main._button("Close", func(): main.dip_panel.visible = false))
	var info := main._label("Every realm starts at war. Peace stops attacks both ways; allies also help defend each other's buildings nearby. Opinion rises with gifts, fair trades, peace and shared enemies, and falls when you attack or break a treaty. With at least half the rivals defeated, an alliance with all who remain is an allied victory.", 13, Main.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	v.add_child(info)
	main.dip_rivals = VBoxContainer.new(); v.add_child(main.dip_rivals)
	v.add_child(main._label("Offers to you", 16, Main.BRASS))
	dip_props = VBoxContainer.new(); v.add_child(dip_props)
	v.add_child(main._label("Trade or gift", 16, Main.BRASS))
	var tr := HBoxContainer.new(); v.add_child(tr)
	tr.add_child(main._label("With"))
	main.trade_who = OptionButton.new(); tr.add_child(main.trade_who)
	tr.add_child(main._label("  you give"))
	main.trade_give = _res_option(false); tr.add_child(main.trade_give)
	main.trade_give_n = SpinBox.new(); main.trade_give_n.min_value = 1; main.trade_give_n.max_value = 999; main.trade_give_n.value = 10; tr.add_child(main.trade_give_n)
	var tr2 := HBoxContainer.new(); v.add_child(tr2)
	tr2.add_child(main._label("and ask for"))
	main.trade_want = _res_option(true); tr2.add_child(main.trade_want)
	trade_want_n = SpinBox.new(); trade_want_n.min_value = 1; trade_want_n.max_value = 999; trade_want_n.value = 5; tr2.add_child(trade_want_n)
	tr2.add_child(main._button("Ask a fair amount", _trade_quote))
	tr2.add_child(main._button("Make the offer", _trade_offer))
	var tr3 := HBoxContainer.new(); v.add_child(tr3)
	trade_repeat = CheckBox.new()
	trade_repeat.text = "Repeat every 5 minutes (a standing offer)"
	tr3.add_child(trade_repeat)
	trade_hint = main._label("", 13, Main.DIM)
	trade_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trade_hint.custom_minimum_size = Vector2(760, 0)
	v.add_child(trade_hint)
	for w in [main.trade_who, main.trade_give, main.trade_want]:
		(w as OptionButton).item_selected.connect(func(_i): _update_hint())
	for sb in [main.trade_give_n, trade_want_n]:
		(sb as SpinBox).value_changed.connect(func(_v): _update_hint())
	main.trade_result = main._label("", 13, Main.DIM)
	main.trade_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.trade_result.custom_minimum_size = Vector2(760, 0)
	v.add_child(main.trade_result)
	v.add_child(main._label("Standing offers", 16, Main.BRASS))
	standing_box = VBoxContainer.new(); v.add_child(standing_box)
	v.add_child(main._label("Between rivals", 16, Main.BRASS))
	dip_web = main._rich(); dip_web.custom_minimum_size = Vector2(760, 0); v.add_child(dip_web)
	main.dip_panel.visible = false


func _res_option(with_nothing: bool) -> OptionButton:
	var o := OptionButton.new()
	if with_nothing:
		o.add_item("nothing (a gift)")
		o.set_item_metadata(0, "")
	for r in GameData.resources:
		if not main.res_shown(String(r.id)):
			continue
		o.add_item(String(r.name))
		o.set_item_metadata(o.item_count - 1, String(r.id))
		o.set_item_icon(o.item_count - 1, Tex.get_tex("res_" + String(r.id)))
		o.get_popup().set_item_icon_max_width(o.item_count - 1, 20)
	o.add_theme_constant_override("icon_max_width", 20)
	return o


func _open_diplomacy() -> void:
	if main.sim.players.is_empty():
		return
	_fill_diplomacy()
	main.dip_panel.visible = true


func _fill_diplomacy() -> void:
	for c in main.dip_rivals.get_children():
		c.queue_free()
	for c in dip_props.get_children():
		c.queue_free()
	var me := main.sim.human()
	var my_str := Diplomacy.strength(main.sim, me)
	var keep_who = main.trade_who.get_selected_metadata() if main.trade_who.item_count > 0 else null
	main.trade_who.clear()
	for q in main.sim.players:
		if not q.ai or not q.alive:
			continue
		var rel := Diplomacy.relation(main.sim, 1, q.id)
		var op := Diplomacy.opinion(q, 1)
		var row := HBoxContainer.new()
		var l := main._rich()
		l.custom_minimum_size = Vector2(430, 0)
		l.text = tr("[color=#%s]■[/color] [b]%s[/b] [color=#9a9c88]%s, level %d[/color]\n%s · thinks of you: %s (%d) · army %d vs your %d") % [q.color.to_html(false), q.name, q.pers, q.skill, Diplomacy.NAMES[rel], Diplomacy.mood(op), roundi(op), roundi(Diplomacy.strength(main.sim, q)), roundi(my_str)]
		if rel == Diplomacy.PEACE and Diplomacy.borders(main.sim, 1, q.id):
			l.text += tr("\n[color=#e0b060]Your borders touch: their patience wears thin over time. A gift or a trade wins it back; at war they will march.[/color]") if q.pers != "builder" else tr("\n[color=#9a9c88]Your borders touch, but builders are patient neighbours.[/color]")
		row.add_child(l)
		if rel == Diplomacy.WAR:
			row.add_child(main._button("Offer peace", _dip_propose.bind(q.id, "peace")))
		if rel == Diplomacy.PEACE:
			row.add_child(main._button("Propose alliance", _dip_propose.bind(q.id, "alliance")))
		if rel != Diplomacy.WAR:
			row.add_child(main._button("Declare war", _dip_war.bind(q.id)))
			main.trade_who.add_item(q.name)
			main.trade_who.set_item_metadata(main.trade_who.item_count - 1, q.id)
			if keep_who != null and int(keep_who) == q.id:
				main.trade_who.select(main.trade_who.item_count - 1)
		main.dip_rivals.add_child(row)
	if main.trade_who.item_count == 0:
		main.trade_who.add_item("(nobody at peace with you)")
		main.trade_who.set_item_metadata(0, 0)
	if main.sim.proposals.is_empty():
		dip_props.add_child(main._label("No offers waiting.", 13, Main.DIM))
	for pr in main.sim.proposals:
		var who := main.sim.players[int(pr.from) - 1]
		var text := ""
		match String(pr.kind):
			"peace": text = "%s offers peace." % who.name
			"alliance": text = "%s proposes an alliance." % who.name
			"tribute": text = "%s demands %s as tribute (refuse, and war may follow)." % [who.name, Diplomacy.goods_text(pr.want)]
			"help": text = "Your ally %s asks you to join its war against %s (refuse, and it trusts you less)." % [who.name, main.sim.players[int(pr.get("target", 1)) - 1].name]
			_: text = "%s offers %s for your %s." % [who.name, Diplomacy.goods_text(pr.give), Diplomacy.goods_text(pr.want)]
		var row2 := HBoxContainer.new()
		var l2 := main._label(text + "  (%d s left)" % maxi(0, int(Diplomacy.PROPOSAL_LIFE - (main.sim.time - float(pr.t)))), 14)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(l2)
		row2.add_child(main._button("Accept", _dip_accept.bind(int(pr.id))))
		row2.add_child(main._button("Decline", func(): Diplomacy.decline(main.sim, int(pr.id))))
		dip_props.add_child(row2)
	var web := []
	for a in main.sim.players:
		for b in main.sim.players:
			if a.ai and b.ai and a.alive and b.alive and a.id < b.id and Diplomacy.relation(main.sim, a.id, b.id) != Diplomacy.WAR:
				web.append("%s and %s: %s" % [a.name, b.name, Diplomacy.NAMES[Diplomacy.relation(main.sim, a.id, b.id)].to_lower()])
	dip_web.text = "\n".join(web) if web.size() > 0 else "[color=#9a9c88]All rivals are at war with each other.[/color]"
	for c in standing_box.get_children():
		c.queue_free()
	if main.sim.standing.is_empty():
		standing_box.add_child(main._label("None. Tick \"Repeat every 5 minutes\" before making an offer.", 13, Main.DIM))
	for so in main.sim.standing:
		var q2 := main.sim.players[int(so.to) - 1]
		var row3 := HBoxContainer.new()
		var w := "" if (so.want as Dictionary).is_empty() else tr(" for %s") % Diplomacy.goods_text(so.want)
		var l3 := main._label(tr("To %s: %s%s, every %d min, next in %d s (made %d so far)") % [q2.name, Diplomacy.goods_text(so.give), w, int(float(so.every) / 60.0), maxi(0, int(float(so.next) - main.sim.time)), int(so.done)], 14)
		l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row3.add_child(l3)
		row3.add_child(main._button("Stop", func():
			main.sim.standing.erase(so)
			_fill_diplomacy()))
		standing_box.add_child(row3)
	_update_hint()
	_update_dip_button()


## Under the trade: whether you have a market, the carts' way, and whether the realm would take it.
func _update_hint() -> void:
	if trade_hint == null or main.sim.players.is_empty():
		return
	var me := main.sim.human()
	var parts := _trade_parts()
	if Diplomacy.market(main.sim, me) == null:
		trade_hint.text = "You need a market to trade: build one (Stores and roads). Carts carry the goods from it."
		trade_hint.add_theme_color_override("font_color", Color("e0b060"))
		return
	if int(parts[0]) == 0:
		trade_hint.text = "Make peace with a realm to trade with it."
		trade_hint.add_theme_color_override("font_color", Main.DIM)
		return
	var q := main.sim.players[int(parts[0]) - 1]
	var kind := "gift" if (parts[2] as Dictionary).is_empty() else "trade"
	var why := Diplomacy.ai_answer(main.sim, q, kind, 1, parts[1], parts[2])
	var a := Diplomacy.market(main.sim, me)
	var b := Diplomacy.market(main.sim, q, true)
	var way := ""
	if a != null and b != null:
		way = tr(" Carts take about %d s each way.") % int(maxf(4.0, Vector2(a.x - b.x, a.y - b.y).length() / Diplomacy.CART_SPEED))
	if why == "":
		trade_hint.text = tr("%s would accept.") % q.name + way
		trade_hint.add_theme_color_override("font_color", Color("86ad5c"))
	else:
		trade_hint.text = why + way
		trade_hint.add_theme_color_override("font_color", Color("e0b060"))


func _dip_propose(who: int, kind: String) -> void:
	var r := Diplomacy.propose(main.sim, 1, who, kind)
	var q := main.sim.players[who - 1]
	main.trade_result.text = ("%s accepted." % q.name) if r == "" else r
	_fill_diplomacy()


func _dip_war(who: int) -> void:
	Diplomacy.declare_war(main.sim, 1, who)
	_fill_diplomacy()


func _dip_accept(id: int) -> void:
	var r := Diplomacy.accept(main.sim, id)
	main.trade_result.text = "Done." if r == "" else r
	_fill_diplomacy()


func _trade_parts() -> Array:
	var who := int(main.trade_who.get_selected_metadata())
	var give := {String(main.trade_give.get_selected_metadata()): int(main.trade_give_n.value)}
	var want_id := String(main.trade_want.get_selected_metadata())
	var want := {} if want_id == "" else {want_id: int(trade_want_n.value)}
	return [who, give, want, want_id]


func _trade_quote() -> void:
	var parts := _trade_parts()
	if int(parts[0]) == 0:
		main.trade_result.text = "Make peace with a realm before trading with it."
		return
	if String(parts[3]) == "":
		main.trade_result.text = "A gift needs nothing in return. Press Make the offer."
		return
	var q := main.sim.players[int(parts[0]) - 1]
	var n := Diplomacy.fair_amount(main.sim, q, 1, parts[1], parts[3])
	if n <= 0:
		main.trade_result.text = tr("%s would not give any %s for that.") % [q.name, GameData.res_name(parts[3]).to_lower()]
	else:
		trade_want_n.value = n
		main.trade_result.text = tr("%s would give up to %d %s for %s.") % [q.name, n, GameData.res_name(parts[3]).to_lower(), Diplomacy.goods_text(parts[1])]


func _trade_offer() -> void:
	var parts := _trade_parts()
	if int(parts[0]) == 0:
		main.trade_result.text = "Make peace with a realm before trading with it."
		return
	var kind := "gift" if (parts[2] as Dictionary).is_empty() else "trade"
	var q := main.sim.players[int(parts[0]) - 1]
	var r := Diplomacy.propose(main.sim, 1, q.id, kind, parts[1], parts[2])
	if trade_repeat.button_pressed and (r == "" or r == "pending"):
		Diplomacy.add_standing(main.sim, q.id, parts[1], parts[2], 300.0)
	if r == "":
		main.trade_result.text = tr("%s accepted. Their opinion of you is now %d.") % [q.name, roundi(Diplomacy.opinion(q, 1))]
	else:
		main.trade_result.text = r
	_fill_diplomacy()
	main._refresh_all()
