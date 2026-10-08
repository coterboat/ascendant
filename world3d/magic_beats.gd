## The map's magic beats, the pure part (no nodes; M5-9, #120; design/M5_MAGIC_FOG.md §6.3, §12.3): which of a turn's ritual beats
## (Playback.plan's "rituals") play before the marches and which after the battles, how long the rituals phase takes, and what the
## playback bar's captions say. world3d/armies.gd schedules them, world3d/enchant_decals.gd draws them. Nothing here reads the
## game beyond the state it is given for names, and nothing changes it.
##
##   early(beats), late(beats)   the rituals phase's beats (cast, turned aside, fell, paid in blood, an enchantment begins, a fort
##                               raised, a reading) and the enchantments phase's (a summoning, a blessing healing, a curse biting, an
##                               ending, a summon fading), each in report order
##   span(n)                     the seconds the rituals phase takes before the marches begin
##   detail(beats, state)        the playback bar's words for a phase: "Dawn Blessing and Bloodrot"
extends RefCounted

const SpellPlan := preload("res://world3d/spell_plan.gd")
const GAP := 0.42 ## seconds between two ritual beats of the rituals phase
const MAX_SPAN := 2.4


static func early(beats: Array) -> Array:
	return beats.filter(func(b): return not SpellPlan.LATE_EVENTS.has(String(b.get("kind", ""))))


static func late(beats: Array) -> Array:
	return beats.filter(func(b): return SpellPlan.LATE_EVENTS.has(String(b.get("kind", ""))))


## How long `n` ritual beats take before the marches begin (0 for none; the last effect plays on under the marches).
static func span(n: int) -> float:
	return 0.0 if n <= 0 else minf(MAX_SPAN, 0.5 + GAP * float(n))


## The seconds between two of `n` ritual beats: GAP, or less when there are so many that they would run past the phase's span.
static func gap(n: int) -> float:
	return GAP if n <= 1 else minf(GAP, (span(n) - 0.5) / float(n))


## The words for a phase of ritual beats: the distinct rituals cast ("Dawn Blessing and Bloodrot"), else what happened.
static func detail(beats: Array, _state: GameState = null) -> String:
	var names: Array = []
	for b in beats:
		var r := String(b.get("ritual", ""))
		var label := MagicRules.spell_name(r) if not r.is_empty() else ""
		if label.is_empty():
			label = {"fort_raised": "A fort rises", "summoned": "Creatures are summoned", "blessing_healed": "Blessed armies heal", "curse_bit": "A curse bites",
				"enchantment_ended": "An enchantment ends", "summon_faded": "Summoned creatures fade", "far_sight_reading": "A reading"}.get(String(b.get("kind", "")), "")
		if not label.is_empty() and not names.has(label):
			names.append(label)
	if names.is_empty():
		return ""
	if names.size() > 3:
		return "%d workings" % beats.size()
	return " and ".join(names) if names.size() < 3 else "%s, %s and %s" % names
