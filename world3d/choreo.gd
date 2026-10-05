## The armies' choreography on the 3D board, the pure part (no nodes): which pose a figure stands in for
## each beat of a turn's playback, the procedural motion laid over it, the playback's phases and their
## captions, and the sound each beat plays (design/3D_DIRECTION.md 6.4, 7.3; STYLE_BIBLE.md 8).
##
## Poses (world3d/models.gd draws a model per pose when the model table has one, else the ready model):
##   ready    standing in the yard, on a stage, holding, recoiling, re-forming, cheering
##   march    filing out of the gate, marching the roads, marching in through the gate, gathering
##   strike   the blow of a clash (a short lunge toward the enemy)
##   fallen   the dead: after the topple, the figure lies in its fallen pose (or the ready model on its back)
##   cheer    a winner's cheer (rulers have a model for it; everyone else cheers in the ready model)
##
## Motion (motion()): a march hops and sways; a strike lunges a quarter of the gap and back; a recoil
## knocks back for 0.15 s; a fall topples about the feet, then the fallen pose takes over; a cheer hops.
## Every phase offset comes from a hash of the figure's id, never from a random number generator.
##
## Phases, in the turn report's order (TurnReportPanel.PHASE_TITLES keys): movement, battles, sieges (M3c S-4, a game
## with sieges), capture, recruitment. Each plays only when the turn has something in it, under its caption.
##
## Sounds (GameAudio.sfx, from the board): a beat's sound comes from its kind and its index in the turn
## (sound_for), never from a random number generator, and playing it never changes anything.
extends RefCounted

## The report's phase keys the playback shows, in order, with their captions.
const PHASES := ["movement", "battles", "sieges", "capture", "recruitment"]
const CAPTIONS := {"movement": "Movement", "battles": "Battles", "sieges": "Sieges", "capture": "Captures", "recruitment": "Recruits"}
## What each caption means, for the playback bar's tooltip and the legend.
const CAPTION_HELP := {
	"movement": "Every army ordered to march leaves by its gate (or the edge of its province) and marches the roads. Armies that will meet the enemy stop where the battle is.",
	"battles": "Each battle plays a short exchange where it is fought: the blows, then the fallen. Losers topple; a winner's losses fall too. At a fort, a sally spills out of the gate, a storm meets the walls and a breach battle meets in the gap. The turn report has the full battle.",
	"sieges": "Each fort's turn of siege, in the report's order: the besiegers' camps go up round the walls with their chevron banners, the siege works and engines strike and the walls take their damage look, a breach collapses the gate side, a lifted siege folds its camps; masons repair walls, and scaffolding raises a new fort.",
	"capture": "Land changes hands: the new owner's colour sweeps out from its arriving column, and a captured fortress raises its banners.",
	"recruitment": "Recruits march in through their fort's gate and form up in its yard; scaffolding goes up where a fort was ordered; everyone settles where the turn left them.",
}

## The kinds of beat the playback has, and the pose each one shows.
const BEAT_POSES := {
	"stand": "ready", "idle": "ready", "hold": "ready", "recoil": "ready", "reform": "ready", "cheer": "cheer",
	"topple": "ready",
	"march": "march", "file_out": "march", "march_in": "march", "gather": "march", "deploy": "march", "rout": "march",
	"strike": "strike", "lunge": "strike",
	"fallen": "fallen", "dead": "fallen",
}

## The sound of each beat kind; a list alternates by the beat's index (M3: "alternate with battle_hit").
const BEAT_SOUNDS := {
	"march": ["march"],
	"clash": ["battle_clash"],
	"strike": ["battle_hit", "battle_clash"],
	"fall": ["unit_fall"],
	"capture": ["capital_captured"],
	"recruit": ["recruit"],
	## M3c S-4: the fort beats (Playback.plan's "forts"), by the kind armies.gd gives them (FORT_BEATS)
	"siege": ["rout_horn"],
	"wall_hit": ["battle_hit", "battle_clash"],
	"breach": ["battle_charge"],
	"siege_over": ["rout_horn"],
	"repair": ["order_queued"],
	"scaffold": ["order_queued"],
	"built": ["research_complete"],
	"razed": ["unit_fall"],
}

## M3c S-4: each fort event's beat kind (the sound above, the board's dust and shake).
const FORT_BEATS := {
	"siege_started": "siege", "walls_damaged": "wall_hit", "walls_breached": "breach", "siege_lifted": "siege_over",
	"siege_ended": "siege_over", "walls_repaired": "repair", "construction_started": "scaffold",
	"construction_halted": "halted", "fort_built": "built", "construction_razed": "razed",
}

const HOP := 0.75 ## a march step's hop, world units at piece scale
const SWAY := 0.08 ## a march step's side-to-side tilt (radians)
const STEP_RATE := 9.0 ## march steps per second (radians of the step's sine)
const LUNGE := 0.25 ## a strike lunges this share of the gap to the enemy
const LUNGE_TIME := 0.36 ## seconds out and back
const STRIKE_HOLD := 0.3 ## the strike pose shows this long from the impact
const RECOIL := 0.15 ## seconds of knockback
const RECOIL_DIST := 0.7
const TOPPLE := 0.45 ## seconds to topple about the feet
const CHEER_HOP := 1.1


## The pose a figure shows in a beat of kind `beat` ("ready" for anything unknown).
static func pose_for(beat: String) -> String:
	return String(BEAT_POSES.get(beat, "ready"))


## The procedural motion over a pose: `beat` its kind, `t` seconds into it, `phase` the figure's own
## offset (hash_phase). Returns {"hop" (up), "tilt" (sideways sway, radians), "lunge" (forward, world
## units for a gap of 1: multiply by the gap), "back" (knockback, world units), "fall" (0 standing ..
## 1 lying), "pose"}.
static func motion(beat: String, t: float, phase: float = 0.0) -> Dictionary:
	var m := {"hop": 0.0, "tilt": 0.0, "lunge": 0.0, "back": 0.0, "fall": 0.0, "pose": pose_for(beat)}
	match beat:
		"march", "file_out", "march_in", "deploy", "rout":
			var ph: float = t * STEP_RATE * (1.5 if beat == "rout" else 1.0) + phase
			m["hop"] = absf(sin(ph)) * HOP
			m["tilt"] = sin(ph) * SWAY
		"strike", "lunge":
			var k: float = clampf(t / LUNGE_TIME, 0.0, 1.0)
			m["lunge"] = sin(k * PI) * LUNGE
			m["pose"] = "strike" if t < STRIKE_HOLD + LUNGE_TIME * 0.5 else "ready"
		"recoil":
			var r: float = clampf(t / RECOIL, 0.0, 1.0)
			m["back"] = sin(r * PI) * RECOIL_DIST
			m["tilt"] = -sin(r * PI) * 0.12
		"topple":
			m["fall"] = smoothstep(0.0, 1.0, clampf(t / TOPPLE, 0.0, 1.0))
			if t >= TOPPLE:
				m["pose"] = "fallen"
		"fallen", "dead":
			m["fall"] = 1.0
		"cheer":
			m["hop"] = absf(sin(t * 7.0 + phase)) * CHEER_HOP
	return m


## A figure's step phase, from a hash of its army id and index (cosmetic, never the game's dice).
static func hash_phase(id: String, k: int) -> float:
	return float(absi(hash(id + ":" + str(k))) % 6283) / 1000.0


## A 0..1 offset from a hash of `id` and `k` (who strikes a little earlier in a clash).
static func hash01(id: String, k: int) -> float:
	return float(absi(hash(id + "#" + str(k))) % 1000) / 1000.0


## The sound a beat of `kind` plays: its BEAT_SOUNDS entry, alternating by the beat's index in the turn.
## "" for a beat that plays none.
static func sound_for(kind: String, index: int) -> String:
	var list: Array = BEAT_SOUNDS.get(kind, [])
	if list.is_empty():
		return ""
	return String(list[posmod(index, list.size())])


## The caption of a report phase key ("" for a phase the playback doesn't show).
static func caption(phase: String) -> String:
	return String(CAPTIONS.get(phase, ""))
