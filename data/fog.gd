class_name FogData
## Fog of war (M5, design/M5_MAGIC_FOG.md §2, §14): the numbers and tables FogRules reads. Pure data, in
## data/factions.gd style: const dictionaries only. The rules are FogRules (rules/fog_rules.gd).
##
## Fog is a lens, not a rule (§2.1): nothing here is read by the turn resolver. These tables only decide what each
## player is shown (sight, estimates, the audience of each turn report event) and how a rebuilt event is written.

## Sight ranges (§2.3), in steps along the map's neighbour links: a province you own sees 1 province around it, an
## army 1, and a fort you own, or an army holding a commander, a ruler or a scout, 2.
const SIGHT := {"owned": 1, "army": 1, "fort": 2, "commander": 2, "ruler": 2, "scout": 2}

## Scouts (§2.3): unit types that see 2 provinces. Transformations keep the id, so Iron Knights and Thornthrowers
## are scouts too. Thornwolves arrive with magic (M5-6). New factions add rows.
const SCOUTS := ["knights", "fangthrowers", "seraphs", "thornwolves", "gleaners"]  # CW-2: the Gleaners are the Candlewake's scouts

## The sight levels (§2.3), best first: id -> the words players read.
const LEVELS := ["clear", "glimpse", "veiled"]
const LEVEL_NAMES := {"clear": "in clear sight", "glimpse": "glimpsed", "veiled": "out of sight"}
## The view note's level for a remembered army (§2.5); "clear" and "glimpse" are the sight levels.
const MEMORY := "memory"

## Estimates (§2.4): how a glimpsed total is rounded. 1 to `few` show as `few_text` and count as `few`; a larger
## total rounds to the nearest `step` of the first band it is `below` (0: no upper end), and is at least that step.
## The arithmetic is integer: step x floor((n + step / 2) / step). The ranges ("about 15" is 13-17) are computed
## from this, never tabled (FogRules.round_count).
const FEW := 2
const FEW_TEXT := "1-2"
const STEP_SMALL := 5
const SMALL_BELOW := 50
const STEP_LARGE := 10
const ESTIMATE := {"few": FEW, "few_text": FEW_TEXT, "none_text": "none",
	"steps": [{"below": SMALL_BELOW, "step": STEP_SMALL}, {"below": 0, "step": STEP_LARGE}]}

## The view id prefix of every stand-in (§2.7): "seen-<faction>-<province>", with "-b" for blessed units, "-c2",
## "-c3", ... for each further commander, and "-ruler" for the ruler. A rival's enchantment is "seen-<ritual>-<province>",
## or "seen-<ritual>" for a global one. No view id reveals a true id or how many armies there are.
const VIEW_PREFIX := "seen-"

## Who sees each turn report event (§2.8). "whole": who gets the event as the resolver wrote it ("actor": the
## faction it is about, its first faction; "factions": every faction it names, such as both sides of a battle;
## "all": everyone). "others": what everybody else gets: "rebuilt" (a new event from SAFE_NUMBERS, view ids and a
## TEXT template), "move" (a seen move, pooled per faction, start and first step, rebuilt), or "none".
## An event type not listed here goes to its actor alone, which can never leak.
const AUDIENCE := {
	# orders and sacrifices: private
	"order_rejected": {"whole": "actor", "others": "none"},
	"sacrificed": {"whole": "actor", "others": "none"},
	# movement: a rival move out of a province you could see is rebuilt, pooled and rounded
	"army_moved": {"whole": "actor", "others": "move"},
	# battles: both sides saw the whole battle (participants get view ids, §2.8)
	"battle": {"whole": "factions", "others": "none"},
	"border_battle": {"whole": "factions", "others": "none"},
	# M3c sieges: everyone in a siege is there (with two factions, both sides); the walls are public on the map
	"siege_started": {"whole": "factions", "others": "none"},
	"walls_damaged": {"whole": "factions", "others": "none"},
	"walls_breached": {"whole": "factions", "others": "none"},
	"siege_lifted": {"whole": "factions", "others": "none"},
	"siege_ended": {"whole": "factions", "others": "none"},
	"walls_repaired": {"whole": "actor", "others": "none"},
	"construction_started": {"whole": "actor", "others": "none"},
	"construction_halted": {"whole": "actor", "others": "none"},
	"construction_razed": {"whole": "factions", "others": "none"},
	"fort_built": {"whole": "actor", "others": "rebuilt"},
	"storm_called_off": {"whole": "actor", "others": "none"},
	"sally_called_off": {"whole": "actor", "others": "none"},
	"sally_found_nothing": {"whole": "actor", "others": "none"},
	# capture: owners are public
	"captured": {"whole": "actor", "others": "rebuilt"},
	"raided": {"whole": "actor", "others": "none"},
	"vassal_joined": {"whole": "actor", "others": "rebuilt"},
	"vassal_contested": {"whole": "factions", "others": "rebuilt"},
	# ARM-1 musters (splits, merges, commander swaps): the owner's alone. A rival never sees the order; it sees the result
	# through its sight at the end of the turn, pooled and rounded like any army (FogRules.pool_now)
	"army_split": {"whole": "actor", "others": "none"},
	"units_transferred": {"whole": "actor", "others": "none"},
	"armies_merged": {"whole": "actor", "others": "none"},
	"commanders_swapped": {"whole": "actor", "others": "none"},
	"army_disbanded": {"whole": "actor", "others": "none"},
	# recruits, gold, research and healing: private (hidden recruits show only as a changed sighting)
	"recruited": {"whole": "actor", "others": "none"},
	"income": {"whole": "actor", "others": "none"},
	"research_gained": {"whole": "actor", "others": "none"},
	"research_done": {"whole": "actor", "others": "none"},
	"mending": {"whole": "actor", "others": "none"},
	"ruler_healed": {"whole": "actor", "others": "none"},
	"path_healed": {"whole": "actor", "others": "none"},
	# heralds: public
	"ruler_died": {"whole": "actor", "others": "rebuilt"},
	"ruler_arrived": {"whole": "actor", "others": "rebuilt"},
	"succession_waiting": {"whole": "actor", "others": "rebuilt"},
	"oath_sworn": {"whole": "actor", "others": "rebuilt"},
	"transformed": {"whole": "actor", "others": "rebuilt"},
	"wild_spread": {"whole": "actor", "others": "rebuilt"},
	# magic (M5-6 emits these): a Bastion fort is public; a global ritual is heralded (numbers "global": true)
	"fort_raised": {"whole": "actor", "others": "rebuilt"},
	"ritual_cast": {"whole": "actor", "others": "rebuilt_if_global"},
	# M5-6: a curse's bite goes whole to the faction bitten (its first faction); the caster, named second, hears that it
	# bit, rebuilt with no count of what stands there ("rebuilt_named": only factions the event names). Every other
	# ritual event (ritual_fell to the land's owner, the caster's own casts, payments, readings, heals) goes to its
	# first faction alone, the default.
	"curse_bit": {"whole": "actor", "others": "rebuilt_named"},
	# CW-1 (#252, design/CANDLEWAKE.md §2.4, §3.1): flames are their owner's alone (a rival never learns which unseen army found
	# harbour where), and so is a Harvest (a rival sees the risen through its sight); the marks on the land are public
	"flame_changed": {"whole": "actor", "others": "none"},
	"guttered": {"whole": "actor", "others": "none"},
	"harvest": {"whole": "actor", "others": "none"},
	"mark_stage": {"whole": "actor", "others": "rebuilt"},
	"scar_formed": {"whole": "actor", "others": "rebuilt"},
	"scar_consumed": {"whole": "actor", "others": "rebuilt"},
	# the end of the game: the fog lifts (§2.1)
	"game_over": {"whole": "all", "others": "none"},
}

## The numbers a rebuilt event carries, and nothing else (§14). Only the numbers a game has are carried: a capture
## carries the fort's level and walls only in a game with sieges, where forts are public (M5-1's call).
## "move" is a rebuilt rival move; its "total" is a round count (FogRules.round_count), its "types" unit type ids.
## Never carried: units_changed, hp_total, own_text, research ETAs, gold, true army ids.
const SAFE_NUMBERS := {
	"captured": ["income", "is_capital", "fort_level", "walls", "recruit_from"],
	"vassal_joined": ["income"],
	"vassal_contested": ["income"],
	"ruler_died": ["ruler", "kind", "name", "generation", "kept_power", "successor_turn", "successor_power"],
	"ruler_arrived": ["ruler", "kind", "name", "generation", "kept_power", "max_hp", "attack", "defense", "ability_rank"],
	"succession_waiting": ["successor_turn", "successor_power", "successor_generation"],
	"oath_sworn": ["node", "branch", "closed", "turn"],
	"transformed": ["node", "branch", "renamed", "new_unit", "province_rule", "opens_mandate", "forswears", "turn"],
	"wild_spread": ["province", "from_terrain", "terrain"],
	"fort_built": ["province", "level", "walls"],
	"fort_raised": ["province"],
	"ritual_cast": ["ritual", "until_turn"],
	"ritual_fell": ["ritual", "faction", "until_turn", "budget"],
	"curse_bit": ["ritual", "until_turn", "budget", "province"],
	"mark_stage": ["province", "stage"],  # CW-1
	"scar_formed": ["province", "stage", "until_turn"],
	"scar_consumed": ["province", "stage"],
	"move": ["faction", "from", "to", "total", "types"],
}

## The texts of rebuilt and synthetic events (§2.8). {placeholders} are filled from the event's safe numbers and
## the public names of the provinces, factions, nodes and unit types they name, never from the resolver's own text.
## A template whose key ends in a suffix ("captured_capital") is a sentence added when its numbers say so. A sentence
## may open with a name written for running text ({faction} is "the Aurel Crown"): FogRules capitalises the first
## letter of every sentence once a template is filled (#284).
const TEXT := {
	"captured": "{faction} captured {province}. It now pays them {income} gold per turn.",
	"captured_lost": " {previous} lost it.",
	"captured_capital": " This is the capital of {previous}: they cannot recruit until they retake it.",
	"captured_fort": " It came with its {fort} (walls {walls} of {walls_max}).",
	"vassal_joined": "{province} swore fealty to {faction} (Sworn Vassals) and joined it without a fight. It now pays them {income} gold per turn.",
	"vassal_contested": "{province} was sought by both {factions} through Sworn Vassals, so it joined nobody this turn.",
	"ruler_died": "{name}, the ruler of {faction}, is dead. A successor (kept power {successor_power}) arrives at their capital at the end of turn {successor_turn}, if they hold it then.",
	"ruler_arrived": "{name} now rules {faction}: kept power {kept_power}, {max_hp} hit points, attack {attack}, defense {defense}, ability rank {ability_rank}.",
	"succession_waiting": "The successor of {faction} (kept power {successor_power}) was due by the end of turn {successor_turn}, but they don't hold their capital, so the successor waits until they do.",
	"oath_sworn": "{faction} swore {node_ref} on turn {turn}: they are on the way to becoming {branch_ref}, and {closed_ref} is closed to them for good.",
	"transformed": "{faction} became {branch_ref} on turn {turn} ({node_name}).",
	"transformed_renamed": " Their {old_name} are now {new_name}.",
	"transformed_new_unit": " They can now recruit {new_unit_name}.",
	"transformed_mandate": " {mandate_name} is open to their ruler.",
	"wild_spread": "{province} turned to forest for {faction} (the Wild Spreads); it was {from_terrain}.",
	"fort_built": "{faction} finished {fort_phrase} at {province} (walls {walls} of {walls_max}).",
	"fort_raised": "{faction} raised a fort at {province} (Bastion).",
	"ritual_cast": "{faction} cast {ritual}, in effect through turn {until_turn}.",
	"ritual_fell": "{ritual} fell on {province} ({faction}), through turn {until_turn}.",
	"curse_bit": "Your {ritual} bit {faction}'s fighters at {province}: it takes up to {budget} hit points a turn from them, through turn {until_turn}.",
	# CW-1: the same words MarkRules.event_sentence gives the marks' owner (they are public)
	"mark_stage": "{Province} wakes: {stage_name}.",
	"scar_formed": "A cold wake forms at {province}.",
	"scar_consumed": "{Province} relights.",
	"move": "An army of {faction} ({fighters}: {types}) marched from {from} to {to}.",
	"move_away": "An army of {faction} ({fighters}: {types}) marched out of {from} toward {to}, out of your sight.",
	# synthetic events (§2.8): what is left over between the view before the turn and the view after it
	"sighting_changed": "You now see {fighters} of {faction} at {province} ({level}).",
	"sighting_lost": "You no longer see that army of {faction} at {province}.",
	"memory_added": "{province} is out of your sight now: you last saw {fighters} of {faction} there, on turn {turn}.",
	"army_changed": "Your army at {province} now holds {fighters}.",
	"army_gone": "Your army at {province} is gone.",
}

## The codex entry each synthetic event links (§11.4).
const SYNTHETIC_CODEX := {"sighting_changed": "sight", "sighting_lost": "sight", "memory_added": "last_seen",
	"army_changed": "sight"}

## The synthetic event types (§2.8), in the order they are written after the real events.
const SYNTHETIC_TYPES := ["sighting_changed", "sighting_lost", "memory_added", "army_changed"]
