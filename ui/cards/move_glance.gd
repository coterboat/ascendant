class_name MoveGlance
extends RefCounted
## UX-3 (design/UX_WAR_TABLE.md §3.3, the director's review of #208): the compact forecast of a hovered march destination. The full
## forecast the map has always shown (OrdersController.move_preview: the arrival, the battle odds with their reasons, the siege rows)
## is a paragraph, and a paragraph laid over the board hides the provinces you are choosing between. This is the same forecast in two or
## three short lines for the card (and the march strip) to show, and the paragraph is kept whole, word for word, as `full`: the card's
## and the strip's "i" shows it on hover.
##
## Pure: it reads the controller's view and its forecasts (the same calls the preview makes, so the odds are cached, never fought
## twice) and nothing of the scene.
##
##   build(orders, army_id, to) -> {
##     "ok": bool            false for a destination the rules refuse
##     "kind": String        "refused" | "fight" | "capture" | "own" | "unseen" | "besiege" | "breach" | "empty" | "relief" | "own_fort"
##     "icon": String        a UiIcons name for the glance's mark
##     "lines": Array        two or three short lines: where and what it would be, the odds, what it brings or when it arrives
##     "full": String        move_preview's own words, unchanged
##     "codex": String       the codex entry the "i" links: battle odds where there are odds, the move rules otherwise }
## Every number in a line is the forecast's own: the odds are the battle test's win rate and verdict, the income is the province's, the
## arrival turn is the forecast's, the terrain is the battle's.


static func build(orders: OrdersController, army_id: String, to: String) -> Dictionary:
	var view := orders.view_state()
	var dest: Province = view.find_province(to) if view != null else null
	var preview := orders.move_preview(army_id, to)
	var full := String(preview.get("text", ""))
	if dest == null:
		return {"ok": false, "kind": "refused", "icon": "needs-you", "lines": [full], "full": full, "codex": "move"}
	var f := orders.move_forecast(army_id, to)
	if not bool(f.get("ok", false)):
		return {"ok": false, "kind": "refused", "icon": "needs-you", "lines": ["%s: can't be ordered" % dest.name, String(f.get("reason", ""))],
			"full": full, "codex": "orders"}
	var arrive := arrival_text(view, f)
	var kind := orders.siege_kind(army_id, to)
	if not kind.is_empty():
		return _fort(orders, view, dest, army_id, kind, arrive, full)
	var info := orders.move_odds(army_id, to)
	var viewer := orders.faction_id
	if Forecast.is_fog_view(view) and String(FogRules.sight(view, viewer).get(to, FogRules.VEILED)) == FogRules.VEILED:
		return {"ok": true, "kind": "unseen", "icon": "sight", "lines": ["%s: out of sight" % dest.name, "it may hold anything: no odds", arrive],
			"full": full, "codex": "move"}
	var enemies := foes_at(view, viewer, to)
	if not enemies.is_empty() or bool(info.get("enemy_present", false)):
		var reward := "win: +%d gold a turn" % dest.income if dest.owner != viewer else "win: you hold it"
		var odds := odds_line(info)
		var ground_text := ground(dest)
		var lines := ["%s: fight %s" % [dest.name, who_text(view, to, enemies)], odds,
			"%s · %s" % [ground_text, reward] if not ground_text.is_empty() else reward]
		return {"ok": true, "kind": "fight", "icon": "battle", "lines": lines.filter(func(l): return not String(l).is_empty()), "full": full,
			"codex": "battle_odds" if not odds.is_empty() else "move"}
	if dest.owner != viewer:
		var raid := AscensionRules.capture_gold(view, viewer, dest)
		var income := "+%d gold a turn if no enemy arrives too" % dest.income
		if int(raid.gold) > 0:
			income += ", +%d at once" % int(raid.gold)
		return {"ok": true, "kind": "capture", "icon": "march", "lines": ["%s: undefended, capture it" % dest.name, income, arrive], "full": full, "codex": "move"}
	return {"ok": true, "kind": "own", "icon": "march", "lines": ["%s: your land" % dest.name, arrive], "full": full, "codex": "move"}


## The siege rows (a move into a fort): what it would be, the walls or the odds, and when it arrives. The odds are the siege
## forecast's own (FortView.siege_odds, cached).
static func _fort(orders: OrdersController, view: GameState, dest: Province, army_id: String, kind: String, arrive: String, full: String) -> Dictionary:
	var viewer := orders.faction_id
	var level := SiegeRules.level_name(dest.fort_level)
	var with_move: Array = orders.orders() + [orders.move_order_for(army_id, dest.id)]
	var lines := []
	var icon := "siege"
	match kind:
		"besiege":
			var joins := SiegeRules.besiegers(view, dest.id).any(func(a): return a.owner == viewer)
			lines.append("%s: %s the %s" % [dest.name, "join the siege of" if joins else "besiege", level.to_lower()])
			var storm := _short_odds(FortView.siege_odds("storm", view, viewer, dest.id, with_move))
			lines.append("walls %d of %d%s" % [dest.walls, SiegeRules.walls_max(dest.fort_level), " · storm now: %s" % storm if not storm.is_empty() else ""])
		"breach":
			lines.append("%s: attack through the breach" % dest.name)
			var breach := _short_odds(FortView.siege_odds("breach", view, viewer, dest.id, with_move))
			if not breach.is_empty():
				lines.append("odds %s" % breach)
		"empty":
			lines.append("%s: take the empty %s" % [dest.name, level.to_lower()])
		"relief":
			lines.append("%s: relieve the siege" % dest.name)
			var relief := _short_odds(FortView.siege_odds("relief", view, viewer, dest.id, with_move))
			lines.append("fights outside the walls%s" % (" · odds %s" % relief if not relief.is_empty() else ""))
		_:
			lines.append("%s: your own %s" % [dest.name, level.to_lower()])
			icon = "walls"
	lines.append(arrive)
	return {"ok": true, "kind": kind if kind != "own" else "own_fort", "icon": icon, "lines": lines, "full": full,
		"codex": "storm" if kind == "besiege" else "siege"}


## "100%, likely win" from a battle test's win rate and its verdict, with a fog game's second figure; "" when there is no battle.
static func odds_line(info: Dictionary) -> String:
	var odds: Dictionary = info.get("odds", {})
	if odds.is_empty():
		return ""
	if bool(odds.get("no_odds", false)):
		return "no odds: out of sight"
	if not odds.has("win_rate"):
		return ""
	var text := "odds %d%%, %s" % [roundi(float(odds.win_rate) * 100.0), String(odds.get("label", ""))]
	if bool(info.get("fog", false)):
		text = "odds %d%% (%s)" % [roundi(float(odds.win_rate) * 100.0), String(odds.get("label", ""))]
		var top: Dictionary = odds.get("top", {})
		if top.has("win_rate"):
			text += " · %d%% at range top" % roundi(float(top.win_rate) * 100.0)
	return text


## "likely win" from a siege odds result ({"label", ...}), without its test-battle count; "" for none.
static func _short_odds(odds: Dictionary) -> String:
	return String(odds.get("label", "")) if not odds.is_empty() and odds.has("label") else ""


## The terrain the defender fights on, in the battle's own numbers: "hills +1/+1" is +1 defense and +1 attack; a fort's walls are the siege rows'.
static func ground(p: Province) -> String:
	if p.fort_level > 0:
		return ""
	var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(p.terrain, {})
	var defense := int(bonus.get("defense", 0))
	var attack := int(bonus.get("attack", 0))
	if defense == 0 and attack == 0:
		return p.terrain
	return "%s +%d/+%d" % [p.terrain, defense, attack]


## The owners of the armies standing in `pid` that are not `viewer`'s, other than ones only remembered (a ghost under fog), sorted.
static func foes_at(view: GameState, viewer: String, pid: String) -> Array:
	var out := []
	for a in view.armies:
		if a.location == pid and a.owner != viewer and String(a.seen.get("level", "")) != FogData.MEMORY and not out.has(a.owner):
			out.append(a.owner)
	out.sort()
	return out


## "the Free Holds" for a neutral garrison, "the Thornmane Clans" for a faction's army (and "X and Y" for two).
static func who_text(view: GameState, pid: String, owners: Array) -> String:
	if owners == [IndependentData.FACTION_ID] and view.garrison_at(pid) != null:
		return "the %s" % IndependentData.FACTION_NAME
	var names := []
	for fid in owners:
		var f := view.find_faction(String(fid))
		names.append(("the %s" % f.faction_name) if f != null else "an army")
	return " and ".join(names) if not names.is_empty() else "the army there"


## "there at the start of turn 3" (a road move says how it goes): the forecast's own arrival turn.
static func arrival_text(view: GameState, f: Dictionary) -> String:
	var turn := int(f.get("arrival_turn", 0))
	var by := ""
	if not String(f.get("via", "")).is_empty():
		var via := view.find_province(String(f.via))
		by = "by road through %s, " % (via.name if via != null else "the road")
	return "%sthere at the start of turn %d" % [by, turn]
