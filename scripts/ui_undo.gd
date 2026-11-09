class_name UiUndo
extends RefCounted
## Undo (Ctrl+Z): takes back the last building placed, road laid or building demolished, if it was
## within the last 10 seconds, with everything paid back: a site's materials (delivered or used), a
## road's bridge planks, and for a demolished building the goods it gave back are taken again and it
## stands as before (its workers and soldiers come back by themselves).

const WINDOW := 10.0   # seconds of real time

var main: Main
var last := {}          # what can be undone: {"kind", "t", ...}


func _init(p_owner: Main) -> void:
	main = p_owner


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func placed(b: Sim.Bld) -> void:
	if b == null:
		return
	last = {"kind": "place", "t": _now(), "id": b.id, "roads": main.sim.logistics.last_laid.duplicate(), "planks": main.sim.logistics.last_bridge_planks}


func road_built() -> void:
	last = {"kind": "road", "t": _now(), "roads": main.sim.logistics.last_laid.duplicate(), "planks": main.sim.logistics.last_bridge_planks}


## Call just before demolishing b: notes what it was and what the stores held, to work out the refund.
func before_demolish(b: Sim.Bld) -> Dictionary:
	var me := main.sim.human()
	return {"kind": "demolish", "ty": b.ty, "x": b.x, "y": b.y, "door": b.door, "prio": b.prio, "ready": b.state == "ready",
		"want_n": b.want_n, "want_kinds": b.want_kinds.duplicate(), "archer_want": b.archer_want, "sally": b.sally, "policy": b.policy,
		"stock": me.stock.duplicate()}


func demolished(rec: Dictionary) -> void:
	var me := main.sim.human()
	var back := {}
	for k in me.stock:
		var d := float(me.stock[k]) - float((rec.stock as Dictionary).get(k, 0.0))
		if d > 0.0:
			back[k] = d
	rec.erase("stock")
	rec["back"] = back
	rec["t"] = _now()
	last = rec


func undo() -> void:
	if last.is_empty() or _now() - float(last.t) > WINDOW:
		main._show_hint("Nothing to undo (only the last 10 seconds can be undone).", 2.5)
		last = {}
		return
	var sim: Sim = main.sim
	var me := sim.human()
	var why := ""
	match String(last.kind):
		"place":
			var b: Sim.Bld = sim.by_id.get(int(last.id))
			if b == null or b.dead or b.state != "build":
				why = "That building is already finished or gone."
			else:
				var at := sim.idx(b.x, b.y)
				for k in b.onsite:
					sim.give(me, k, float(b.onsite[k]), at)
				for k in b.spent:
					sim.give(me, k, float(b.spent[k]), at)
				b.onsite = {}
				b.spent = {}
				var name := String(b.def.name).to_lower()
				sim.destroy(b)
				_unroad(last.roads, int(last.planks))
				main._show_hint("Undone: the %s site is gone and its materials are back in store." % name, 2.5)
		"road":
			_unroad(last.roads, int(last.planks))
			main._show_hint("Undone: the road is gone%s." % (" and its planks are back" if int(last.planks) > 0 else ""), 2.5)
		"demolish":
			if not bool(last.ready):
				why = "A demolished building site can't be brought back; place it again."
			elif sim.can_place(String(last.ty), int(last.x), int(last.y), 1, int(last.door)) != "" and sim.bld_at(int(last.x), int(last.y)) != null:
				why = "Something stands there now."
			else:
				for k in last.back:
					sim.take(me, k, float(last.back[k]))
				var b := sim.add_bld(String(last.ty), int(last.x), int(last.y), me, true, int(last.door))
				b.prio = int(last.prio); b.want_n = int(last.want_n); b.want_kinds = last.want_kinds
				b.archer_want = int(last.archer_want); b.sally = bool(last.sally); b.policy = int(last.policy)
				if sim.is_mil(b) or b.def.get("claim_only", false):
					sim.mil_fill(me)
					sim.recompute_territory()
				main.view.sel_id = b.id
				main._show_hint("Undone: the %s stands again." % String(b.def.name).to_lower(), 2.5)
	if why != "":
		main._show_hint(why, 2.5)
	last = {}
	main._refresh_all()


func _unroad(tiles: PackedInt32Array, planks: int) -> void:
	var sim: Sim = main.sim
	var n := 0
	for c in tiles:
		if sim.road[c] == 1 and sim.bmap[c] == 0:
			sim.road[c] = 0
			sim.pave[c] = 0
			sim.changed_tiles.append(c)
			n += 1
	if n > 0:
		sim.logistics.net_dirty(1)
	if planks > 0:
		sim.give(sim.human(), "planks", float(planks))
