class_name BattlePlayer
extends RefCounted
## Plays a battle event log back: the clock, the beats and the state at every beat (M3-3, #58, as re-scoped
## by design/3D_DIRECTION.md §7.6; design/M3_BATTLES.md §4.1, §5.1, §5.2). Renderer-agnostic and pure: it
## is a RefCounted with no nodes, it reads only the log, its report and BattleTimeline / BattleMoments /
## BattleCaptions / BattleExplain (rules/), and it never calls the battle rules, changes game state or draws
## a random number, so watching a battle can't change it. The 2D Simple view (BattleSimpleView) subscribes
## to it now; the 3D battle stage subscribes the same way later.
##
##   var player := BattlePlayer.new(event.numbers.log, event.numbers.report)
##   player.beat.connect(func(b, state): ...)   every beat as it fires, with the live state after it
##   player.seeked.connect(func(state): ...)    after any seek, jump, restart or skip: snap to `state`
##   player.play(); player.set_speed(4)         then call player.advance(delta) once per frame
##
## THE SCHEDULE. build() turns the log into a fixed list of beats with times in seconds at 1x (§4.1). The
## same log always gives the same beats and times (nothing depends on the frame rate, the view or its
## settings); 2x and 4x only run the clock faster. A round is:
##   round_start  0.4 s       the banner ("Round 3 of at most 8")
##   casts        M5-7: the round's cast events in log order, cast k at k x min(CAST_STAGGER, CAST_SPAN / C), then
##                CAST_HOLD; only in a round with a cast (a game with magic)
##   attacks      the round's attacks in BattleTimeline.display_order (round-robin across sides). Attack k
##                starts at k x stagger, stagger = min(0.25 s, 1.6 s / A); it lands MELEE_IMPACT later for
##                melee, or after its projectile's flight (PROJECTILES). The phase lasts until the last lands.
##   wounds       0.6 s       every wound and death of the round, at once (damage lands at the end)
##   heals        0.4 s       M4-3's Lifedrinker heals, only in a round that has one
##   morale       0.5 s       every morale check; then the round's caption
##   rout         1.5 s       only in a round a side breaks or is wiped out
##   round_end    0 s
## Before round 1 a 1.5 s deploy beat; after the last round end, feast, harvest (M4-3's Red Harvest) and
## aftermath at once and the result RESULT_DELAY later. A log event of a kind this player doesn't know gets
## an "event" beat in its place, so new log kinds never break the state. A ruler's death adds 0.6 s of 0.5x slow motion to the clock (not to the schedule),
## unless reduced_motion is set.
##
## A BEAT is {"i" (its index), "kind", "t" (seconds at 1x), "dur" (its phase's length at 1x), "event" (the
## log event it shows, -1 for none), "round", "fighter", "target", "side" (ids, -1 when none), "data"}:
##   deploy                                   data {}
##   round_start      event: the round        data {"round_cap", "banner"}
##   cast             fighter -> target       data {"spell", "name", "kind", "school", "targets", "damage", "part", "self",
##                                                 "text" (BattleExplain.explain_cast's summary)}  (M5-7)
##   attack_started   fighter -> target       data {"hit", "damage", "big", "charge", "first_charge" (its
##   attack_landed    (both per attack)            side's first Charge attack), "projectile" ("" for melee,
##                                                 "bolt", "javelin", "arcane", or "dive" for Wings), "arc",
##                                                 "delay" (start to impact, s at 1x), "shake" ({} or {"amp",
##                                                 "dur"}; on landed only), "order" (its place in the display
##                                                 order), "reach" (the log's: "front" ... "skirmish", "wings"),
##                                                 "wings" (bool), "parts" (the damage parts: Charge +4, Iron
##                                                 Hide -1), "iron_hide" (0 or -1), "blocked" (a hit Iron Hide
##                                                 or Shield Wall took some of)}
##   wound            fighter                 data {"from", "to"}
##   heal             fighter                 data {"from", "to", "healed", "dealt", "trait"} (Lifedrinker)
##   death            fighter                 data {"ruler" (bool), "shake", "slowmo" (s of slow motion)}
##   morale           side                    data {"result", "morale", "break_pct", "lost_pct", "held_by",
##                                                 "change" (BattleExplain.morale_change: {} or the notch tag)}
##   rout             side                    data {"fled": [ids]}
##   destroyed        side                    data {}
##   caption          round                   data {"lines": BattleCaptions lines}
##   round_end        round                   data {}
##   moment           fighter, side           data: the BattleMoments moment (right after the beat of its event)
##   end              side: the winner        data {"how", "winner"}
##   feast            side                    data {"healed": [[fighter, from, to]]}
##   harvest          side                    data {"gold", "fighters"} (Red Harvest)
##   aftermath                                data {"text", "lost", "fallen_rulers"}
##   event                                    data {"t": its log kind}: a kind this player doesn't know
##   result                                   data {"truncated" (bool)}: show the result card
## The beats of kinds in APPLYING fold their event into the live state when they fire (BattleTimeline.apply),
## so every log event is applied by exactly one beat. Attacks fold in display order, which is truthful
## because a round's attacks only add pending damage until the wounds land.
##
## THE CLOCK. play(), pause(), toggle(), set_speed(1 | 2 | 4), advance(real_delta) (call it every frame; it
## fires the beats whose time has come, returns them and emits `beat` for each), step() and step_back() (one
## log event, while paused), seek(event_index), seek_round(n), seek_time(t), seek_beat(b), restart(),
## jump_to_moment(kind) and next_moment() (§5.2: the moment's beat minus LEAD_IN, keeping play or pause),
## skip_to_end() (fires only the result beat). After a seek the state is exact: state() before a beat that
## shows log event i equals BattleTimeline.state_at(i) for every event that is not an attack, and the final
## state after skip_to_end(). Seeking replays no animation (`seeked`, not `beat`).
##
## READING IT. state() (a copy) or live_state() (the player's own, read-only), beats(), duration(), time(),
## round_now(), round_times(), moments(), missing_moments(), moment_time(m), captions(), caption(n),
## strength(si) (BattleExplain.side_strength now), explain(fid) (BattleExplain.explain_fighter now),
## timeline(), battle_log(), report().

signal beat(b: Dictionary, state: Dictionary)
signal seeked(state: Dictionary)
signal finished
signal playing_changed(playing: bool)
signal speed_changed(speed: int)

const SPEEDS := [1, 2, 4]
## §4.1 durations at 1x, in seconds.
const DEPLOY := 1.5
const BANNER := 0.4
const STAGGER_MAX := 0.25
const STAGGER_SPAN := 1.6
const WOUNDS := 0.6
const MORALE := 0.5
const ROUT := 1.5
const FEAST := 0.6
## M4-3's Lifedrinker heals land in their own short phase, after the wounds and before morale.
const HEAL := 0.4
## The phases after a round's attacks, in order, and how long each lasts at 1x (§4.1; the heal phase is
## this player's): wounds, heals, morale (the caption follows it), rout, round end.
const PHASES := [WOUNDS, HEAL, MORALE, ROUT, 0.0]
const PHASE_OF := {"wound": 0, "death": 0, "heal": 1, "morale": 2, "rout": 3, "destroyed": 3, "round_end": 4}
const RESULT_DELAY := 0.8
## §5.2: a jump lands this long before the moment's beat.
const LEAD_IN := 0.5
## §4.2: a melee attack's impact comes 0.12 s after it starts (the lunge's way out).
const MELEE_IMPACT := 0.12
## §4.4: a hit of this much damage or more is a big hit (bigger impact, shake).
const BIG_HIT := 8
## §4.1: a ruler's fall slows the clock to SLOWMO_RATE for SLOWMO_SECONDS of real time.
const SLOWMO_SECONDS := 0.6
const SLOWMO_RATE := 0.5
## §4.4's projectiles, by the attacker's trait (or a ruler's id). "flight" is the fixed time from release to
## impact at 1x (inside §4.4's 0.15-0.45 s clamp), so the schedule doesn't depend on where a renderer puts
## the fighters: a renderer moves the projectile at whatever speed lands it on time. "speed" and "arc" (apex
## as a share of the distance) are §4.4's, for renderers that want them.
const PROJECTILES := {
	"Volley": {"kind": "bolt", "flight": 0.25, "speed": 1400.0, "arc": 0.08},
	"Skirmish": {"kind": "javelin", "flight": 0.35, "speed": 900.0, "arc": 0.18},
	"ever_regent": {"kind": "arcane", "flight": 0.3, "speed": 1100.0, "arc": 0.0},
	# M4-3's Wings: the fighter itself swoops over the lines onto its target (a dive, not a lunge).
	"Wings": {"kind": "dive", "flight": 0.25, "speed": 1600.0, "arc": 0.3},
}
## §4.5's screen shake triggers (amplitude in px of screen motion, duration in s). Renderers keep the 0.75 s
## spacing and the reduced-motion and setting switches (BattleFx.ShakeLimiter).
const SHAKE_BIG := {"amp": 3.0, "dur": 0.15}
const SHAKE_CHARGE := {"amp": 4.0, "dur": 0.2}
const SHAKE_RULER := {"amp": 6.0, "dur": 0.25}
## M5-7: the cast step's beats, before the round's attacks.
const CAST_STAGGER := 0.3
const CAST_SPAN := 1.2
const CAST_HOLD := 0.35
const KINDS := ["cast", "deploy", "round_start", "attack_started", "attack_landed", "wound", "death", "heal", "morale", "rout", "destroyed",
	"caption", "round_end", "moment", "end", "feast", "harvest", "aftermath", "event", "result"]
## Beat kinds that apply their log event to the state when they fire. "event" is any log event of a kind
## this player doesn't know yet: it still gets its one beat, so the state stays exact.
const APPLYING := ["cast", "round_start", "attack_landed", "wound", "death", "heal", "morale", "rout", "destroyed", "round_end", "end", "feast",
	"harvest", "aftermath", "event"]
const _APPLIES := {"cast": true, "round_start": true, "attack_landed": true, "wound": true, "death": true, "heal": true, "morale": true, "rout": true,
	"destroyed": true, "round_end": true, "end": true, "feast": true, "harvest": true, "aftermath": true, "event": true}
## The log event kinds with a beat of their own name; any other becomes an "event" beat.
const _OWN_BEAT := {"wound": true, "death": true, "heal": true, "morale": true, "rout": true, "destroyed": true, "round_end": true,
	"end": true, "feast": true, "harvest": true, "aftermath": true}
const EPS := 0.000001

## Turns off the ruler-fall slow motion (the view passes the reduced-motion setting).
var reduced_motion := false

var _log: Dictionary = {}
var _report: Dictionary = {}
var _tl: BattleTimeline = null
var _beats: Array = []
var _first_beat_of_event: Dictionary = {}  # event index -> the first beat that shows it
var _applying_beat_of_event: Dictionary = {}  # event index -> the beat that applies it
var _anchor_of: PackedInt32Array = PackedInt32Array()  # beat -> the beat to fold from when seeking to it
var _round_times: Array = []  # [{"round", "t", "beat"}]
var _moments: Array = []
var _moment_beats: Array = []  # beat index of each moment, in _moments' order
var _captions: Dictionary = {}  # round -> lines
var _result_beat := -1
var _duration := 0.0

var _time := 0.0
var _next := 0
var _playing := false
var _speed := 1
var _slow_left := 0.0
var _state: Dictionary = {}


func _init(battle_log: Dictionary = {}, report: Dictionary = {}) -> void:
	if not battle_log.is_empty():
		load_log(battle_log, report)


## Why `battle_log` can't be played back, in plain words, or "" when it can (§6).
static func playback_problem(battle_log: Dictionary) -> String:
	if battle_log.is_empty() or not battle_log.has("events") or not battle_log.has("fighters"):
		return "This battle was fought with the test rules and has no playback."
	if battle_log.get("truncated", false):
		return "This battle is too big to play back. The report has everything."
	return ""


## Loads a log (and its report, for the captions) and builds the schedule. The clock stops at the start.
func load_log(battle_log: Dictionary, report: Dictionary = {}) -> void:
	_log = battle_log
	_report = report
	_tl = BattleTimeline.build(battle_log)
	_moments = BattleMoments.key_moments(battle_log)
	_captions = {}
	for c in BattleCaptions.all_rounds(battle_log, report):
		_captions[int(c.round)] = c.lines
	_build()
	_time = 0.0
	_next = 0
	_slow_left = 0.0
	_state = _tl.state_at(0)


# --- the schedule ---------------------------------------------------------------------------------

func _build() -> void:
	_beats = []
	_first_beat_of_event = {}
	_applying_beat_of_event = {}
	_round_times = []
	_moment_beats = []
	var events: Array = _log.get("events", [])
	var by_event := {}  # event index -> [moment indices]
	for k in _moments.size():
		var ev := int(_moments[k].event)
		if not by_event.has(ev):
			by_event[ev] = []
		by_event[ev].append(k)
	_moment_beats.resize(_moments.size())
	_moment_beats.fill(-1)

	var pending := []  # beats of the current block, before sorting by time
	var t := 0.0
	pending.append(_beat("deploy", t, DEPLOY, -1, 0))
	t += DEPLOY
	_flush(pending, by_event)
	var rounds := _tl.rounds()
	var end_i := BattleLog.find_event(_log, "end")
	var tail_from := events.size() if end_i < 0 else end_i
	var charge_started := {}  # side -> true once its first Charge attack has started
	for n in range(1, rounds + 1):
		var rs := _tl.round_start(n)
		var next_rs := _tl.round_start(n + 1)
		if next_rs < 0:
			next_rs = tail_from
		var rb := _beat("round_start", t, BANNER, rs, n)
		var cap := int(_log.get("round_cap", 8))
		rb.data = {"round_cap": cap, "banner": "Round %d of at most %d" % [n, cap]}
		pending.append(rb)
		_round_times.append({"round": n, "t": t})
		t += BANNER
		# M5-7: the cast step comes before the attacks, each cast in log order.
		var casts := []
		for i in range(rs + 1, next_rs):
			if String(events[i].t) == "cast":
				casts.append(i)
		if not casts.is_empty():
			var cast_gap := minf(CAST_STAGGER, CAST_SPAN / casts.size())
			for k in casts.size():
				pending.append(_cast_beat(int(casts[k]), t + k * cast_gap, n))
			t += cast_gap * casts.size() + CAST_HOLD
		# Attacks, staggered in display order.
		var order := _tl.display_order(n)
		var count := order.size()
		var charged := {}
		if count > 0:
			var stagger := minf(STAGGER_MAX, STAGGER_SPAN / count)
			var last := t
			for k in count:
				var i := int(order[k])
				var e: Dictionary = events[i]
				var start := t + k * stagger
				var data := _attack_data(e, k)
				var landed_at := start + float(data.delay)
				var sb := _beat("attack_started", start, float(data.delay), i, n)
				sb.data = data
				if data.charge and not charge_started.has(_side_of(int(e.by))):
					charge_started[_side_of(int(e.by))] = true
					data.first_charge = true
				var lb := _beat("attack_landed", landed_at, 0.0, i, n)
				lb.data = data.duplicate()
				lb.data.shake = _attack_shake(e, charged)
				for ab in [sb, lb]:
					ab.fighter = int(e.by)
					ab.target = int(e.to)
					ab.side = _side_of(int(e.by))
				pending.append(sb)
				pending.append(lb)
				last = maxf(last, landed_at)
			t = last
		_flush(pending, by_event)
		# The rest of the round, in log order, phase by phase: wounds and deaths, heals (M4-3's
		# Lifedrinker), morale checks, then a rout. A kind this player doesn't know joins the phase of the
		# event before it, and a phase never goes back, so the beats always keep the log's order.
		var phases := [[], [], [], [], []]  # PHASES' order
		var phase := 0
		for i in range(rs + 1, next_rs):
			var kind := String(events[i].t)
			if kind == "attack" or kind == "cast":
				continue
			phase = maxi(phase, int(PHASE_OF.get(kind, phase)))
			phases[phase].append(i)
		for k in PHASES.size():
			if k == 3:
				var cb := _beat("caption", t, 0.0, -1, n)
				cb.data = {"lines": _captions.get(n, [])}
				pending.append(cb)
			var list: Array = phases[k]
			if list.is_empty():
				continue
			var length := float(PHASES[k])
			for i in list:
				pending.append(_event_beat(i, t, length, n))
			t += length
		_flush(pending, by_event)
	# After the rounds: the end, a feast, the aftermath, then the result card.
	var settle := RESULT_DELAY
	for i in range(tail_from, events.size()):
		var kind := String(events[i].t)
		if kind == "round":
			continue
		pending.append(_event_beat(i, t, FEAST if kind == "feast" or kind == "harvest" else 0.0, rounds))
		if kind == "feast" or kind == "harvest":
			settle = maxf(settle, FEAST)
	_flush(pending, by_event)
	var res := _beat("result", t + settle, 0.0, -1, rounds)
	res.data = {"truncated": bool(_log.get("truncated", false))}
	pending.append(res)
	_flush(pending, by_event)
	_result_beat = _beats.size() - 1
	_duration = float(_beats[_result_beat].t)
	# Seek anchors: the deploy beat, every round start and the end beat, where the state before the beat
	# is exactly BattleTimeline.state_at(its event).
	_anchor_of.resize(_beats.size())
	var anchor := 0
	for b in _beats.size():
		var kind := String(_beats[b].kind)
		if kind == "round_start" or kind == "end":
			anchor = b
		_anchor_of[b] = anchor


## Sorts a block of beats by time (stably), numbers them, indexes them and adds each moment right after the
## first beat of its event.
func _flush(pending: Array, by_event: Dictionary) -> void:
	for k in pending.size():
		pending[k]["_seq"] = k
	pending.sort_custom(func(a, b): return a.t < b.t - EPS or (absf(a.t - b.t) <= EPS and a._seq < b._seq))
	for b in pending:
		b.erase("_seq")
		_push(b)
		var ev := int(b.event)
		if ev < 0:
			continue
		if APPLYING.has(b.kind):
			_applying_beat_of_event[ev] = b.i
		if not _first_beat_of_event.has(ev):
			_first_beat_of_event[ev] = b.i
			for k in by_event.get(ev, []):
				var m: Dictionary = _moments[k]
				var mb := _beat("moment", b.t, 0.0, ev, int(m.round))
				mb.fighter = int(m.fighter)
				mb.side = int(m.get("side", -1))
				mb.data = m
				_push(mb)
				_moment_beats[k] = mb.i
	pending.clear()


func _push(b: Dictionary) -> void:
	b.i = _beats.size()
	_beats.append(b)


func _beat(kind: String, t: float, dur: float, event: int, round_no: int) -> Dictionary:
	return {"i": -1, "kind": kind, "t": t, "dur": dur, "event": event, "round": round_no, "fighter": -1, "target": -1, "side": -1, "data": {}}


## M5-7: the beat for cast event `i`.
func _cast_beat(i: int, t: float, round_no: int) -> Dictionary:
	var e: Dictionary = _log.events[i]
	var b := _beat("cast", t, CAST_STAGGER, i, round_no)
	b.fighter = int(e.by)
	b.target = int(e.targets[0]) if not Array(e.targets).is_empty() else -1
	b.side = _side_of(int(e.by))
	b.data = {"spell": String(e.spell), "name": MagicRules.spell_name(String(e.spell)), "kind": String(e.kind), "school": String(e.school),
		"targets": BattleLog._ints(e.targets), "damage": int(e.get("damage", 0)), "part": e.get("part", {}).duplicate(), "self": int(e.get("self", 0)),
		"text": BattleExplain._cap(String(BattleExplain.explain_cast(_log, i).get("what", ""))) + "."}
	return b


## The beat for a non-attack log event.
func _event_beat(i: int, t: float, dur: float, round_no: int) -> Dictionary:
	var e: Dictionary = _log.events[i]
	var kind := String(e.t)
	var b := _beat(kind if _OWN_BEAT.has(kind) else "event", t, dur, i, round_no)
	if b.kind == "event":
		b.data = {"t": kind}
	match kind:
		"wound":
			b.fighter = int(e.f)
			b.side = _side_of(int(e.f))
			b.data = {"from": int(e.from), "to": int(e.to)}
		"death":
			b.fighter = int(e.f)
			b.side = _side_of(int(e.f))
			var ruler: bool = _log.fighters[int(e.f)].role == "ruler"
			b.data = {"ruler": ruler, "shake": SHAKE_RULER.duplicate() if ruler else {}, "slowmo": SLOWMO_SECONDS if ruler else 0.0}
		"heal":
			b.fighter = int(e.f)
			b.side = _side_of(int(e.f))
			b.data = {"from": int(e.from), "to": int(e.to), "healed": int(e.to) - int(e.from), "dealt": int(e.get("dealt", 0)),
				"trait": String(e.get("trait", ""))}
		"harvest":
			b.side = int(e.side)
			b.data = {"gold": int(e.get("gold", 0)), "fighters": int(e.get("fighters", 0))}
		"morale":
			b.side = int(e.side)
			b.data = {"result": String(e.result), "morale": int(e.morale), "break_pct": int(e.break_pct), "lost_pct": int(e.lost_pct),
				"held_by": int(e.held_by), "change": BattleExplain.morale_change(_log, i)}
		"rout":
			b.side = int(e.side)
			b.data = {"fled": BattleLog._ints(e.fled)}
		"destroyed":
			b.side = int(e.side)
		"end":
			b.side = int(e.winner)
			b.data = {"how": String(e.how), "winner": int(e.winner)}
		"feast":
			b.side = int(e.side)
			b.data = {"healed": e.healed}
		"aftermath":
			b.data = {"text": String(e.get("text", "")), "lost": BattleLog._ints(e.get("lost", [])),
				"fallen_rulers": BattleLog._ints(e.get("fallen_rulers", []))}
	return b


func _attack_data(e: Dictionary, order: int) -> Dictionary:
	var f: Dictionary = _log.fighters[int(e.by)]
	var proj := projectile_of(f)
	var hit: bool = e.hit
	var damage := int(e.damage) if hit else 0
	var bonus: Dictionary = e.get("bonus", {})
	var defense: Dictionary = e.get("defense", {})
	return {"hit": hit, "damage": damage, "big": hit and damage >= BIG_HIT, "charge": bonus.has(AutoBattleResolver.CHARGE),
		"projectile": String(proj.get("kind", "")), "arc": float(proj.get("arc", 0.0)),
		"delay": float(proj.get("flight", MELEE_IMPACT)), "shake": {}, "order": order, "reach": String(e.get("reach", "front")),
		"wings": String(e.get("reach", "")) == "wings", "parts": bonus.duplicate(),
		"iron_hide": int(bonus.get(AutoBattleResolver.IRON_HIDE, 0)),
		"blocked": hit and (bonus.has(AutoBattleResolver.IRON_HIDE) or defense.get("parts", {}).has(AutoBattleResolver.SHIELD_WALL)),
		"first_charge": false}


## §4.5: the first Charge hit of each side in round 1, else a big hit.
func _attack_shake(e: Dictionary, charged: Dictionary) -> Dictionary:
	if not e.hit:
		return {}
	var si := _side_of(int(e.by))
	if int(e.n) == 1 and e.bonus.has(AutoBattleResolver.CHARGE) and not charged.has(si):
		charged[si] = true
		return SHAKE_CHARGE.duplicate()
	if int(e.damage) >= BIG_HIT:
		return SHAKE_BIG.duplicate()
	return {}


## The projectile a fighter shoots ({} for melee): §4.4's table, by trait or by a ruler's id.
static func projectile_of(f: Dictionary) -> Dictionary:
	var ruler: Dictionary = f.get("ruler", {})
	var ruler_id := String(ruler.get("id", ""))
	if f.get("role", "") == "ruler" and PROJECTILES.has(ruler_id):
		return PROJECTILES[ruler_id]
	return PROJECTILES.get(String(f.get("trait", "")), {})


func _side_of(fid: int) -> int:
	return int(_log.fighters[fid].side)


# --- the clock ------------------------------------------------------------------------------------

func play() -> void:
	if is_finished():
		restart()
	if not _playing:
		_playing = true
		playing_changed.emit(true)


func pause() -> void:
	if _playing:
		_playing = false
		_slow_left = 0.0
		playing_changed.emit(false)


func toggle() -> void:
	if _playing:
		pause()
	else:
		play()


func is_playing() -> bool:
	return _playing


## 1, 2 or 4 (anything else is ignored). Returns whether it was accepted.
func set_speed(s: int) -> bool:
	if not SPEEDS.has(s):
		return false
	if s != _speed:
		_speed = s
		speed_changed.emit(s)
	return true


func speed() -> int:
	return _speed


## Moves the clock on by `real_delta` seconds of real time (times the speed, slowed during a ruler's fall)
## and fires every beat whose time has come. Returns the beats fired. Does nothing while paused.
func advance(real_delta: float) -> Array:
	if not _playing or is_finished() or real_delta <= 0.0:
		return []
	var dt := real_delta * _speed
	if _slow_left > 0.0:
		var slow := minf(real_delta, _slow_left)
		_slow_left -= slow
		dt = (slow * SLOWMO_RATE + (real_delta - slow)) * _speed
	_time = minf(_time + dt, _duration)
	return _fire_until(_time)


## Fires the beats up to and including the next one that applies a log event (one step of §5.3's "."),
## moving the clock to it. Returns the beats fired.
func step() -> Array:
	var fired := []
	while _next < _beats.size():
		var b: Dictionary = _beats[_next]
		_time = maxf(_time, float(b.t))
		fired.append(b)
		_fire_one()
		if APPLYING.has(b.kind):
			break
	return fired


## Goes back to just before the last log event applied (§5.3's ","): the state before it.
func step_back() -> void:
	var b := _next - 1
	while b >= 0 and not APPLYING.has(_beats[b].kind):
		b -= 1
	seek_beat(maxi(b, 0))


## Lands just before beat `b` fires: the state is every earlier beat's, and the clock is at its time.
func seek_beat(b: int) -> void:
	if _beats.is_empty():
		return
	b = clampi(b, 0, _beats.size() - 1)
	_next = b
	_time = float(_beats[b].t)
	_slow_left = 0.0
	_state = _state_before(b)
	seeked.emit(_state)


## Lands just before log event `event_index` is shown (its first beat). events.size() lands on the result
## card's beat, with the final state.
func seek(event_index: int) -> void:
	var n: int = _log.get("events", []).size()
	if event_index >= n:
		seek_beat(_result_beat)
		return
	event_index = maxi(event_index, 0)
	seek_beat(int(_first_beat_of_event.get(event_index, 0)))


## Lands on round `n`'s banner. Returns false when there is no round n.
func seek_round(n: int) -> bool:
	var i := _tl.round_start(n) if _tl != null else -1
	if i < 0:
		return false
	seek(i)
	return true


## Moves the clock to `t` (seconds at 1x): every beat before `t` has fired, the beats at `t` are next.
## The scrubber uses this: the state is shown at once, and no animation replays.
func seek_time(t: float) -> void:
	if _beats.is_empty():
		return
	t = clampf(t, 0.0, _duration)
	var lo := 0
	var hi := _beats.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(_beats[mid].t) < t - EPS:
			lo = mid + 1
		else:
			hi = mid
	_next = mini(lo, _beats.size() - 1)
	_time = t
	_slow_left = 0.0
	_state = _state_before(_next)
	seeked.emit(_state)


func restart() -> void:
	seek_beat(0)


## Jumps to the next moment of `kind` after the playhead (wrapping to the first), LEAD_IN before its beat,
## keeping play or pause (§5.2). Returns the moment, or {} when the battle has none of that kind.
func jump_to_moment(kind: String) -> Dictionary:
	var picks := []
	for k in _moments.size():
		if kind.is_empty() or _moments[k].kind == kind:
			picks.append(k)
	if picks.is_empty():
		return {}
	var pick: int = picks[0]
	for k in picks:
		if _moment_t(k) - LEAD_IN > _time + EPS:
			pick = k
			break
	seek_time(maxf(0.0, _moment_t(pick) - LEAD_IN))
	return _moments[pick]


## §5.3's M: the next key moment of any kind.
func next_moment() -> Dictionary:
	return jump_to_moment("")


## Goes straight to the result card: the final state, and only the result beat fires.
func skip_to_end() -> void:
	if _beats.is_empty():
		return
	_next = _result_beat
	_time = float(_beats[_result_beat].t)
	_slow_left = 0.0
	_state = _tl.final_state()
	seeked.emit(_state)
	_fire_until(_time)


func is_finished() -> bool:
	return _next >= _beats.size()


func _fire_until(t: float) -> Array:
	var fired := []
	while _next < _beats.size() and float(_beats[_next].t) <= t + EPS:
		fired.append(_beats[_next])
		_fire_one()
	return fired


func _fire_one() -> void:
	var b: Dictionary = _beats[_next]
	_next += 1
	if _APPLIES.has(b.kind):
		_apply(_state, int(b.event))
	if b.kind == "death" and float(b.data.slowmo) > 0.0 and not reduced_motion and _playing:
		_slow_left = float(b.data.slowmo)
	beat.emit(b, _state)
	if b.kind == "result":
		_time = _duration
		if _playing:
			_playing = false
			playing_changed.emit(false)
		finished.emit()


## BattleTimeline.apply, keeping "event" at the furthest event applied (attacks fold in display order).
func _apply(state: Dictionary, i: int) -> void:
	var before := int(state.event)
	BattleTimeline.apply(_log, state, i)
	state.event = maxi(before, i + 1)


## The state before beat `b` fires: the timeline's exact state at its anchor, then the beats in between.
func _state_before(b: int) -> Dictionary:
	if b >= _beats.size():
		return _tl.final_state()
	var a := _anchor_of[b]
	var ev := int(_beats[a].event)
	var state := _tl.state_at(ev if ev >= 0 else 0)
	for k in range(a, b):
		var kb: Dictionary = _beats[k]
		if APPLYING.has(kb.kind):
			_apply(state, int(kb.event))
	return state


# --- reading it -----------------------------------------------------------------------------------

## The state now (a copy): BattleTimeline's state shape.
func state() -> Dictionary:
	return _state.duplicate(true)


## The player's own state Dictionary, updated in place as beats fire. Read it, never change it.
func live_state() -> Dictionary:
	return _state


## Every beat in order (the player's own Array: read it, never change it).
func beats() -> Array:
	return _beats


## The index of the next beat to fire.
func next_beat() -> int:
	return _next


## The battle's length at 1x, to the result card.
func duration() -> float:
	return _duration


## The clock, in seconds at 1x.
func time() -> float:
	return _time


func round_now() -> int:
	return int(_state.get("round", 0))


## [{"round", "t"}]: when each round's banner starts, at 1x (the scrubber's ticks).
func round_times() -> Array:
	return _round_times


func moments() -> Array:
	return _moments


## {kind: why there is none} (BattleMoments.missing), for the disabled jump buttons.
func missing_moments() -> Dictionary:
	return BattleMoments.missing(_log)


## When moment `m`'s beat fires, at 1x (-1 when it isn't one of this battle's moments).
func moment_time(m: Dictionary) -> float:
	for k in _moments.size():
		if _moments[k].kind == m.get("kind") and int(_moments[k].event) == int(m.get("event", -2)):
			return _moment_t(k)
	return -1.0


func _moment_t(k: int) -> float:
	var b: int = _moment_beats[k]
	return float(_beats[b].t) if b >= 0 else -1.0


## [{"round", "lines"}]: BattleCaptions for every round.
func captions() -> Array:
	var out := []
	var keys := _captions.keys()
	keys.sort()
	for n in keys:
		out.append({"round": n, "lines": _captions[n]})
	return out


func caption(n: int) -> Array:
	return _captions.get(n, [])


## The strength bar of side `si` now (BattleExplain.side_strength).
func strength(si: int) -> Dictionary:
	return BattleExplain.side_strength(_log, _state, si)


## The hover explanation of fighter `fid` now (BattleExplain.explain_fighter at the live state).
func explain(fid: int) -> Dictionary:
	return BattleExplain.explain_fighter(_tl, fid, int(_state.event), _state)


func timeline() -> BattleTimeline:
	return _tl


func battle_log() -> Dictionary:
	return _log


func report() -> Dictionary:
	return _report
