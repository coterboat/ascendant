# ASCENDANT: the Candlewake, design spec for the third faction

Status: **DRAFT r6 by the director (Claude session, 2026-10-07 to 10-09), for Alex's sign-off.** Two Codex critic rounds are absorbed (appendix A).
- **10-6:** Alex chose the Candlewake as the extra faction.
- **10-7:** he set the order (CW1: build it right after the MVP walk, write the spec now) and the pilot (CW2: their mark on the land ships with them, as the first test of the marks system).
- **Critics:** Codex's hostile round (24 findings, appendix A) rewrote r1.
- **Numbers:** every number is a starting point. CW-2's micro-benchmarks check it first, and CW-11 tunes it.

Built on:
- **Specs:** `design/GAME_BRIEF.md` (pillars, approachability), `design/M2_RULER.md` (rulers, mandates, presets), `design/M4_ASCENSION.md` (paths, the spec format), `design/M5_MAGIC_FOG.md` (spell kinds, fog's view state) and `design/M3C_SIEGES.md` (forts, engines).
- **The lore room:**
  - `design/lore/art-pass/claude/dossier_candlewake.md` (round 4: Wick, the roster seed, the Golden and Red Wakes);
  - `design/lore/art-round-2/claude/dossier2_candlewake.md` (rulers, the Long Vigil, the Wake);
  - `design/lore/art-round-3/`.
- **Canon art:** `assets/_concept/lore/candlewake/`.
- **The engine on `main` at 3a0ddc0:**
  - battle math in `rules/auto_battle_resolver.gd`: `damage = max(1, ceil(atk/2) − floor(def/4))`, `hit% = clamp(60 + 4(atk − def), 30, 90)`;
  - turn phases in `rules/turn_resolver.gd`.

**Alex: read §14 (director's calls) and §15 (your questions) first.**

## goal
A third faction that plays like nothing in the game yet: **a tide that has to keep fighting.** Every Candlewake army burns at a flame from 0 to 3. Winning feeds it, and sitting still starves it. The dead remake the land they hold into wax, and the land remembers them after they lose it.

The milestone proves three things:
- **Momentum can be a faction's whole identity** and still read at a glance: the flame on the banner is the plan.
- **The engine takes a third faction** without changing one byte of any Crown–Clans game.
- **The marks on the land work** on one faction before six factions need them.

## the short version
- **Any two of three.** A game seats 2 players who pick from 3 factions (no mirrors).
  - The Crown and the Clans keep their capitals. The Candlewake take whichever one is free and name it the Long Vigil.
  - Crown–Clans games serialize exactly as today.
- **Wick.** Each Candlewake army has a **flame** from 0 to 3, shown on its banner and on the board as the height of its flames.
  - Win a battle: +1.
  - End a turn without a battle outside a **harbour**: −1.
  - Regulars fight at **flame − 1 attack**: −1 at 0, 0 at 1, +1 at 2, +2 at 3.
  - At 0 the army **gutters**: its regulars lose 2 hp a turn, never below 1, until it wins again.
- **The Wake.** Land they hold turns to wax: **Sitting Up**, then **the Wake-Line** after 3 turns held, then **Deep Wake** after 6.
  - A Wake-Line province is a harbour and pays 1 less gold, because the living sit up all night.
  - Lose it, and a **cold wake** lingers 2 turns per stage. While it lasts it is still a harbour for the Candlewake, and retaking it resumes the old stage.
  - Buildings melt in step on the board.
  - **The dead rise** from Deep Wake: 1 Wickwarden every 4 turns a province. The target is 10–20% of their force, a steady part of the host, not their recruitment (Alex 10-8).
- **The host:**
  - **Wickwardens:** the cheap line, with Pall (harder to hit).
  - **Gleaners:** reapers, with Siphon (heal on a hit).
  - **the Hundred-Wick:** a guttered mass, with Flare (burns up to 6 enemies as it falls).
  - **the Lamplighter**, the commander, with Toll (every enemy that falls lifts morale).
  - **Chandler's Apprentices:** mages.
  - **Candlebeasts** (Alex 10-8): beasts the Wake has poured over, in many forms. They are poured only in Deep Wake, so spreading the Wake grows the menagerie: Wax Hounds, the Tallow Stag and the Guttering Bear first (§4.5).
- **Rulers:**
  - **Half-Death**, a front-rank god. **Harvest**: once a turn, a win in its province over a player's army raises 1–2 Wickwardens.
  - **Mother Tallow, the Ninth Chandler**, a mortal line in the second rank. **Vigil**: her province holds armies at flame 1–2 or more.
- **Paths:**
  - **the Golden Wake**: the Kept, who feed on hives. Economy and a sooner Wake.
  - **the Red Wake**: they stop apologising. Flame to 4, burning down fast.
- **Two schools:**
  - **Wick:** Draw the Warmth, Kindle, Bonfire Night.
  - **Wax:** Wax Skin, Raise the Snuffed, Candlemass.
  - They reuse M5's spell kinds. The new code is one flame effect.
- **The computer** learns the flame lifecycle: fight for fuel, go home in time, don't cool a hot army.
- **13 tickets,** CW-0 to CW-12. CW-0 (the engine) and CW-1 (the scaffold) come first.
- **Art:** about 305 Ludo credits planned, 375 with reserve, every asset through the Review Table.

---

## 1. the third faction in the engine (CW-0)

### 1.1 a game holds the factions its players chose
Today `GameState._load_data()` loads every `FactionData.FACTIONS` row and places their starting armies before any player list exists (`rules/game_state.gd:59-92`). The `with_*` factories do the same, and `GameScreen.starting_state()` never passes `config.players` (`ui/game_screen.gd:376-403`).

- **A new explicit factory** builds a game from what the config chose: `GameState.create(seed, faction_ids, seat_capitals, flags, builds)`.
  - It materialises each seated faction's `capital` from `seat_capitals` **before** armies, rulers, paths, forts and independents are set up.
  - Every config that carries a faction selection goes through it.
- **The legacy constructors are frozen.** `GameState.new(seed)` and every `with_*` stay exact Crown–Clans wrappers, producing the same JSON they produce today.
- **The gate:** raw JSON and digest byte-identity for every old feature combination (M1, M2, M3c, M4, M5, independents, fog), not just the same outcomes.
- **Capitals are derived, never stored** (r2):
  - The Crown always holds crownkeep and the Clans always hold fangridge, whatever the seat order, exactly as today.
  - The Candlewake take whichever map capital is free: fangridge in a Crown–Candlewake game, crownkeep in a Clans–Candlewake game.
  - The factory sets each seated faction's `capital` from that rule before armies, rulers, paths, forts and independents exist. Nothing new is serialized, so a Crown–Clans `GameSession.record()` is byte-identical whichever path built it.
  - `Faction.capital` stays the stable province id the rules read: victory, recruiting, research, succession, the AI.
  - The faction row gains `capital_name` for display. A Crown–Candlewake game shows fangridge as "the Long Vigil".
  - Province ids never change.
- **Two seats, always.** `GameScreen.default_config()` puts every faction into `players` today (`ui/game_screen.gd:191-196`), which would make a three-player game.
  - The default and quick-start configs pick exactly 2 distinct factions: Crown–Clans by default, and 2 of 3 from the seed for quick start.
  - Tests cover all 6 ordered pairings, rematch and load.
- **No mirrors.** `rules/game_session.gd:_check_players` already rejects them.

### 1.2 the two-faction audit
CW-0's acceptance is an **exhaustive generated audit**, not this list. A script greps `data/`, `rules/`, `ai/`, `ui/`, `world3d/`, `tools/` and `tests/` for every faction id, capital id, roster unit id, `size() == 2` and `"a|b"` pair key. Each hit is fixed or marked safe in the PR. The known hits:

- **Setup:**
  - `rules/game_state.gd:59-92`
  - `ui/game_screen.gd:191-196` and `:376-403`
  - `ui/new_game_screen.gd:78` (`SEAT_COUNT`, which stays 2), `:126`, `:510` and `:678`
- **Rules:**
  - `rules/victory_check.gd:81` and `ui/victory_screen.gd:127` ("Both capitals" becomes "Every capital")
  - `rules/ascension_rules.gd:167` (two sides a faction, which still holds)
  - `rules/rules_codex.gd:531`, `:653`, `:665` and `:815` (entries that name Crown and Clans)
- **UI:**
  - `ui/map_screen.gd:141` (`state.factions[0]`)
  - `ui/turn_report_panel.gd:487` (first faction special)
  - `ui/map_layout.gd:23` (the capital mirror)
  - `ui/title_screen.gd:28` (BANNERS)
  - `ui/art.gd:66`
- **Battle views:** `ui/battle/battle_simple_view.gd:199`, `ui/battle/battle_host.gd:56` and `:423`, and `world3d/battle_stage.gd:458` refuse more than 2 sides. That is already a problem for three-sided Free Hold battles, so CW-0 makes them draw N sides.
- **Summons:** `rules/magic_rules.gd:570` and `:664`, `ui/orders_controller.gd:128` and `ui/magic_view.gd:109` hard-code `thornwolves`. They move to `MagicData.SUMMONS`.
- **3D:**
  - `world3d/kit.gd:37-46`, `:116`, `:398`, `:438`, `:470`, `:500` and `:578` (styles)
  - `world3d/scenario.gd:99` (every non-Crown commander is a Warchief)
  - `world3d/world_preview.gd:491-503`
  - `ui/battle/battle_player.gd:121`
  - `data/fog.gd:14`
- **Tools:**
  - `tools/autoplay/autoplay.gd:61` and `:201-204`, `matrix.gd:32` and `:65`, `path_matrix.gd:37` and `:75`
  - `tools/autoplay/simulator.gd:493` (a siege needs exactly two owners)
  - `tools/balance/balance.gd:13-14`, `GROUNDS`, `MIX_CYCLE:32` and `STYLES:194`
  - `tools/battle_log/games.gd:12` and `scenarios.gd:56-57`
  - `tools/replay_fixture*.gd`
- **Tests:** `tests/test_rules_model.gd:50` and `tests/test_balance.gd`.

The AI is structurally N-faction (`ai/ai_player.gd:239` reads every other faction; `:2735` any other capital). It is not Candlewake-aware; that is CW-6.

### 1.3 the faction row
`data/factions.gd` gets id `candlewake`, name "the Candlewake", `capital_name` "the Long Vigil" and start gold 45. The id meets the engine's id rules: no "-", not "independents", and no "free" prefix.

---

## 2. Wick (the faction rule, CW-2)

### 2.1 the rule
- **Flame:** every Candlewake army has a `flame` from 0 to 3. The Red Wake raises the cap to 4 (§6.3).
- **Battles use the flame the army had when the battle phase began.** That is after the rituals phase, so Kindle counts.
  - A border win doesn't buff the same turn's province battle.
  - A fort's chain of battles all use the same flame.
- **Per-turn facts:** the resolver records `fought` and `won` per army id as battles end. Losing armies are destroyed (`rules/turn_resolver.gd:846-878`), so a surviving army that fought has won.
- **Regulars fight at flame − 1 attack:** −1 at 0, 0 at 1, +1 at 2, +2 at 3 (and +3 at 4 for the Red Wake). Commanders, rulers, mages and summons are never affected.
- **New armies:**
  - The start army is at flame 1.
  - A recruit order names its destination in a serialized field `into`. It is either an army id (an army you own at the recruiting place) or `"new:<group>"`.
    - Every order sharing a group forms one new army, in order sequence, with the lowest new id.
    - That army starts at flame 1 (2 with Kindling), set once.
    - The field is validated when orders are submitted and again when they resolve. A missing or invalid army falls back to a new army, and the report says so.
    - Without `into`, an order behaves as today: it joins the first eligible army by id. So Crown and Clans orders don't change.
  - Joining an existing army sets that army's flame to `min(its flame, the recruits' flame)`: recruiting into a hot army cools it.
  - The order's forecast shows the result before you commit. Co-located armies never merge on their own.
- **No splits or merges.** The game has no such orders. Flame belongs to the army id. Armies that share a province or fight on one side each keep their own flame and their own bonus.

### 2.2 the end of the turn, and the Wick step
**The order (r2):** captures → recruitment → **the wake step** (§3.3) → **the Wick step** → income.
- The wake step runs first, so a province that reaches the Wake-Line this turn shelters an idle army in this turn's Wick step and costs its gold in this turn's income.
- Both steps use the end clock `E = state.current_turn + 1`: the turn number the next turn will show.

**Effective flame in battle** is `min(flame + battle bonus, cap)`. The cap is 3, or 4 for the Red Wake, and the battle bonus is Bonfire Night's. The attack change is `effective flame − 1`.

**The Wick step** is one deterministic pass, in army-id order.

1. **Won a battle this turn:** +1 (Pyre Roads, Red Wake: +2). At most once a turn.
2. **Else, no battle this turn:**
   - outside a harbour: −1 (Red Wake: −2);
   - in a harbour: no change.

   An army created this turn skips this step.
3. **Red Wake:** a flame above 3 that didn't win this turn drops to 3, even in a harbour.
4. **Vigil:** armies in Mother Tallow's province rise to at least her floor (§4.2). Vigil never raises a flame above 3.
5. **Clamp** to 0 and the cap.
6. **Guttering:** at flame 0, every regular loses 2 hp, never below 1. An army is never deleted this way, and rulers and commanders never gutter.

**A harbour is:**
- a fort you own;
- a Wake-Line or Deep Wake province you own (§3);
- a cold wake of your own (§3.3).

Siege camps are not harbours: they want the storm, not the wait.

### 2.3 why it plays, and what it costs
- **The question every turn:** go home and hold the flame, or push on and grow it.
- **Fuel:**
  - Early, the fuel is Free Holds: they always fight. A win over a Free Hold raises flame, but it never Harvests (§4.2).
  - Late, the fuel is rival armies.
- **The counter is refusing battle:** walls, harbours, and armies that slip away.

**Against the math, the curve is flame − 1 on purpose.** Codex's round 1 showed +1 attack per flame on a 6-gold body broke the cost curve (appendix A).
- **Flame 1 is even:** a Wickwarden (7 gold) against a grouped Spearman (8 gold, defence 9) hits 60% for 3, about 1.8 a round. The Spearman hits it 59% for 3, about 1.77.
- **Flame 3 is a real edge, not a rout:** 68% for 4, about 2.7 a round. It takes two straight wins and no recruits to get there.

### 2.4 fog
- **Exact flame** is visible in clear sight and in the report of a battle you fought in.
- **Glimpsed and remembered armies** show "flame unknown". The 3D figures show a neutral wick.
- **The fog allow-list, memory and perturbation tests** get a `flame` case, as M5-1's indistinguishability tests do.
- **Reports** never say which unseen army found harbour where.

### 2.5 explained (shipped in the same ticket)
- **The army card and banner:** 0–3 pips. "Flame 2: its regulars fight at +1 attack. If it doesn't win this turn and isn't in a harbour, it drops to 1."
- **The orders forecast,** one line a Candlewake army: "Second Procession: flame 2 → 3 if it wins; → 1 if it ends outside a harbour."
- **The recruit forecast:** "Joining the Second Procession cools it from flame 3 to 1. A new army starts at 1."
- **The battle odds and the why panel:** "Wick: +1 attack (flame 2)."
- **The turn report** shows one net line an army: "The Second Procession burns hotter: flame 3." "The Third Procession is guttering: its regulars lost 2 hp."
- **The codex:** "Wick", "Harbour" and "Guttering".
- **The board:** flame height on every figure (§10).

---

## 3. the Wake (the marks pilot, CW-3)

### 3.1 the generic engine piece (built once, for every faction later)
- **Where it lives:** marks sit in a top-level `marks` dictionary that holds **only non-empty entries**. It is omitted from the state and the save entirely when no seated faction has a `MarkData` row, so Crown–Clans games serialize exactly as today.
- **An entry:** `{faction, since_turn}`, or a scar `{faction, stage, until_turn}`, or both.
- **The stage** is computed, not stored:
  - `since_turn` is the end clock `E` (§2.2) of the turn the province was taken.
  - `held = E − since_turn`, and the faction's thresholds turn that into a stage.
  - A capital counts as held since `since_turn = −6`, so Deep Wake from the start.
- **Rules hooks:** the faction's `MarkData` row names each stage's effects (gold delta, harbour) and its scar rules. Only the Candlewake have a row in this milestone.
- **Fog:** marks and scars are public, like terrain and owners.

### 3.2 the Candlewake's mark
| stage | name | held | does |
|---|---|---|---|
| 1 | Sitting Up | taken this turn or later | nothing yet: a lilac flame in every window |
| 2 | the Wake-Line | 3 turns | a harbour for Wick; the province pays −1 gold |
| 3 | Deep Wake | 6 turns | as the Wake-Line, and **the dead rise** (§3.6) |

Every household keeps a candle in its window all night, as you do for the dead, and each flame gives a little warmth as the host passes. Nobody is hurt. The wax is the receipt.

### 3.3 the cold wake (the scar), with exact timing
The wake step runs after captures and recruitment, before the Wick step, on the end clock `E` (§2.2).

| case | what happens |
|---|---|
| the Candlewake take a province | its mark starts at `since_turn = E` (stage 1) |
| anyone takes a Candlewake province | its mark becomes a scar: `stage` = the stage it had at the previous wake step, `until_turn = E + 2 × stage`. The taker's own mark (if any) starts at `since_turn = E` |
| a wake step with `E ≥ until_turn` | the scar is removed before the Wick step |
| a scar is active | in every Wick step with `E < until_turn`, which is exactly `2 × stage` steps counting its creation turn; it is a harbour for Candlewake armies ending the turn there |
| the Candlewake retake a scarred province | the scar is **consumed**: the mark resumes at `since_turn = E − threshold(scar stage)`, so the stage returns at once (a harbour that same Wick step). The scar's time is not refreshed |
| a province is taken and retaken in one turn | impossible: capture resolves once a turn |

**Worked example.** The Candlewake take Thornvale during turn 4, so `E = 5` and `since_turn = 5`.

| end of turn | E | held | stage | harbour in this Wick step | income |
|---|---|---|---|---|---|
| 4 | 5 | 0 | Sitting Up | no | full |
| 5 | 6 | 1 | Sitting Up | no | full |
| 6 | 7 | 2 | Sitting Up | no | full |
| 7 | 8 | 3 | **Wake-Line** | **yes** | −1 |
| 10 | 11 | 6 | **Deep Wake** | yes | −1 |

The Crown take it during turn 8 (`E = 9`), so the scar is the Wake-Line (stage 2) with `until_turn = 13`. It shelters Candlewake armies at the ends of turns 8 to 11 (`E` = 9 to 12) and is removed at the end of turn 12.

This is the "map tells the war story" part (Alex 10-7): you can read from the ground who held what, for how long, and who took it from them.

### 3.4 explained
- **The province tooltip:** "Wake-Line (held 4 turns): Candlewake armies keep their flame here. The living sit up all night: −1 gold. Deep Wake in 2 turns."
- **A scar:** "A cold wake. The Candlewake held it to the Wake-Line; it fades in 3 turns. Their armies still find harbour here, and if they retake it, it relights at once."
- **The turn report:**
  - "Thornvale wakes: the Wake-Line."
  - "A cold wake forms at Rivermarch."
  - "Rivermarch relights."
- **The codex:** "The Wake", and "Marks on the land", which says other peoples' marks are coming.

### 3.5 on the board (CW-8)
- **Ground:** one pale-wax tint at three strengths, spreading from roads and buildings through a mask. A scar's tint fades over its turns.
- **Buildings melt in step** (Alex 10-6; the canon `candlewake_melt.png`): every village, mill, watchtower and fort has three melt meshes. Scarred buildings keep the melt, unlit.
- **Lights:** a flame sprite in each window (stage 1 and up), and candle-posts along roads (stage 2 and up).
- **Quality ladder:**
  - low: tint and window flames;
  - medium: adds posts and building melts;
  - high: adds drips and flicker.

### 3.6 the Risen: the dead rise from Deep Wake (Alex 10-8)
As a province becomes more made in their likeness, its dead turn to wax and rise again. It was one of Alex's favourite Dominions mechanics. **It is a trickle, not their recruitment:** the Candlewake must never depend on it, or they'd be stranded once there was nothing left to consume.

- **When:** in the wake step, each Deep Wake province you own raises **1 Wickwarden** every 4 turns it has been Deep Wake, at `held` = 10, 14, 18 and so on. The capital counts as Deep Wake from the start, so it raises one at the ends of turns 3, 7, 11 and so on.
- **Where:** a Risen Wickwarden joins the lowest-id Candlewake regular army in that province, at that army's flame (it doesn't cool it). If there is none, it forms a new army there at flame 1. That army counts as created this turn and skips the idle step.
- **No hard cap** (Alex 10-8). CW-11 tunes the cadence (every 4 turns) and the Deep Wake threshold toward the target: the Risen are **10–20% of the Candlewake's total force** (band W6). Several provinces rising in the same turn resolve in province-id order.
- **Paths** change it: the Golden Wake makes it a steady stream (§6.2). The Red Wake leaves it alone and swells Harvest instead (§6.3).
- **Explained:**
  - the province tooltip: "Deep Wake: the dead rise here. Next Wickwarden in 2 turns.";
  - the turn report: "At Thornvale the dead rose: 1 Wickwarden.";
  - a codex line under "The Wake".
- **Fog:** a Risen army is an army like any other, so it is seen when its province is.

---

## 4. the host (CW-2)

### 4.1 units
House rule: attacks are odd, and defence is 4k or 4k+1.

| unit | hp/atk/def/mor | gold | rank | trait |
|---|---|---|---|---|
| **Wickwardens** | 7/9/8/8 | 7 | front | **Pall:** attackers hit it at `clamp(60 + 4 × (atk − def) − 5, 30, 90)` (the −5 inside the clamp) |
| **Gleaners** | 6/11/4/7 | 8 | front | **Siphon:** a Gleaner still standing at the end of a round in which it landed a hit heals 1 hp |
| **the Hundred-Wick** | 20/13/5/9 | 18 | front | **Flare:** when it falls, 2 damage to up to 6 standing enemy front-rank fighters |
| **the Lamplighter** (commander) | 22/11/9/12 | 30 | back | **Toll:** each enemy fighter that falls in the battle gives its side +1 morale, up to +3 a battle |
| **Chandler's Apprentices** (mage) | 8/7/5/9 | 17 | second | Mage (M5) |

**A round, in order** (the r2 contract):
1. Attacks and battle-spell damage land, simultaneously as today.
2. Deaths are applied.
3. **Flares** resolve one Hundred-Wick at a time, in (side id, army id, unit index) order. Each picks its targets by current hp, highest first, with ties broken by side id, then army id, then unit index. Fighters killed by an earlier Flare are gone before the next one picks.
   - Flare only hits enemies, and only the Candlewake have Flare (there are no mirrors), so a Flare never kills a Hundred-Wick.
4. Flare deaths are applied.
5. **Siphon:** each standing Gleaner that landed a hit this round heals 1 (2 for Red Gleaners). A curse that blocks healing (Bloodrot) blocks it.
6. **Toll** counts this round's enemy deaths: regulars, commanders and rulers, from attacks, spells and Flare, but not summons. Its morale counts in this round's morale check.
7. The morale check, as today.
- **The start army:** 2 Wickwardens, Gleaners, the Hundred-Wick and the Lamplighter, 70 gold, against the Crown's 73 and the Clans' 76.
- **Code:** the four traits are code in `AutoBattleResolver`. Each gets a `TRAIT_TEXT` line, a why-panel line and a caption:
  - "the Hundred-Wick flared as it fell: 2 damage to 6 Spearmen";
  - "Toll: 3 enemies fell, +3 morale";
  - "the Gleaners drank 1 hp".
- **Fog:** Gleaners are the Candlewake scouts.
- **The look** (Alex 10-7): the rank-and-file are **pure wax**, poured and melted bodies with no armour or skulls and a lilac flame for a wick. Eyes or no eyes is being judged in the Review Table (art round 6c).

### 4.2 rulers
- **Stats:** each stat is a `RulerData` triple `{base, gain, per}`, giving `base + gain × floor(k / per)`, where `k` is kept power. All division is floor division.
- **Ability rank** is `1 + floor(k / 3)`, up to 4. It is not the battle rank (front or second).
- **The power pool** is 10.

| ruler | type, battle rank, morale | hp | atk | def | ability | death |
|---|---|---|---|---|---|---|
| **Half-Death** | god, front, 13 | {20, 3, 1} | {9, 1, 1} | {5, 1, 2} | **Harvest** | back in 1 turn, 3 kept power smaller (as the Great Thornmane) |
| **Mother Tallow, the Ninth Chandler** | mortal line, second, 10 | {14, 1, 1} | {7, 1, 2} | {6, 1, 2} | **Vigil** | the Tenth Chandler, in 2 turns, at half kept power |

- **Harvest.** Once a turn, when a battle Half-Death fought in, in Half-Death's province, is won:
  - against at least one player's army, 1 Wickwarden rises at ability ranks 1–2, and 2 at ranks 3–4;
  - against only a Free Hold, a **reduced Harvest** of 1 Wickwarden at any rank. A strong early game is part of the faction (Alex 10-8);
  - a fort's chain counts once.
  - A ruler travels in its own army with no units (the engine's invariant), so the Wickwardens join **the lowest-id Candlewake regular army that fought in that battle**, at that army's flame. They rose in the fire, so they don't cool it.
  - If no such army survives, they form a new army in the province at flame 1 (2 with Kindling). It counts as created this turn and skips that turn's idle step.
  - It never raises the enemy's dead.
- **Vigil.** In the Wick step (after idle loss, before guttering), armies in Mother Tallow's province rise to at least flame 1/1/2/2 by rank. It never goes above 3.
- **Half-Death is the tide:** keep power high and chain wins, or sacrifice it early for mandates, since a god comes back. The Candlewake say it is what is left of the Wright, who died at noon, mid-stroke.
- **Mother Tallow is patience:** park her where the host gathers. She is the one warm face among the dead, and her taper burns gold.

### 4.3 mandates
The six shared mandates, plus:
- **Kindling** (3): new armies and recruits start at flame 2.
- **Tallow Levy** (3): Wickwardens cost 5.

### 4.4 presets
| preset | ruler | mandates | kept |
|---|---|---|---|
| **the Long Procession** | Half-Death | none | 10 |
| **the Ninth Chandler's Vigil** | Mother Tallow | Kindling, Tallow Levy, Heavy Tithes | 0 |
| **the Harvest Moot** | Half-Death | Kindling, Iron Discipline | 4 |

### 4.5 candlebeasts (Alex 10-8, CW-12)
The Hundred-Wick's art sparked it: **beasts the Wake has poured over.** The wax remembers a shape and fills it, so they come in as many forms as the land had beasts. The family is where the Candlewake roster grows after launch; three forms ship first.

- **Poured, not bred:** a candlebeast can be recruited only in a **Deep Wake** province you hold (the capital counts from the start). That is the Wake's second payoff, beside the Risen (§3.6), and it puts the menagerie where the faction has been longest. It is a field on the unit row (`requires_mark_stage: "deep"`), checked by recruitment like any other gate.
- **Wick as usual:** candlebeasts are regulars, so they fight at flame − 1 and gutter like the rest.
- **Not Risen:** the Risen and Harvest raise Wickwardens only, so the 10–20% target (W6) stays clean.
- **No new trait code.** Each form reuses a trait the engine already has:

| form | hp/atk/def/mor | gold | rank | trait (reused) |
|---|---|---|---|---|
| **Wax Hounds** | 5/9/4/7 | 6 | front | **Skirmish:** they hunt past the line to the archers |
| **the Tallow Stag** | 9/11/4/8 | 10 | front | **Charge:** +damage in the first round, more in a forest |
| **the Guttering Bear** | 14/11/8/9 | 13 | front | **Berserk:** wounded wax burns hotter (+attack below full hp) |

- **The look:** the same pure poured wax as the host (§4.1, §10), animal-shaped, hollow where the eyes would be, a lilac wick burning from the spine. The bear is mid-melt, slumping as it walks.
- **Explained:**
  - the recruit list shows them in every province, greyed where they can't be poured: "Candlebeasts are poured only where the Wake runs deep. Thornvale is on the Wake-Line: Deep Wake in 3 turns.";
  - the unit tooltip carries the family line ("A candlebeast: poured in Deep Wake") above its trait;
  - a codex page, "Candlebeasts", that lists the forms and grows as new ones ship.
- **The player picks the form** (Alex 10-9, §15 item 6): any form, in any Deep Wake province.
- **Later forms (parking lot, not in CW):** a form for each faction's dead land (a wax Thornmane where the Clans fell); gilded beasts on the Golden Wake and burning ones on the Red. Forms the land picks belong to a game-wide terrain pass (§13).

---

## 5. forts and sieges
- **The ladder:** the M3c fort ladder as is.
- **The kit:** stepped towers of melted candles.
- **The capital:** the Long Vigil. A ring of candle towers around one candle as tall as a keep, in a city of the dead (canon, being redone in round 3b).
- **The engine:** the **Guttering Ram**, 18 gold, the Siege Ram's numbers, in `FortData.ENGINES`.
- **A fort they own is a harbour, and a siege camp is not.**

---

## 6. paths (M4, CW-4)

### 6.1 ordinary nodes
| node | research | does |
|---|---|---|
| Thicker Tallow | 10 | Wickwardens +3 hp |
| Sitting Up Early | 10 | the Wake-Line comes 1 turn sooner (3 → 2) |
| Brighter Flare | 15 | Flare deals 3 |
| Hungry Gleaners | 15 | Gleaners +2 attack |

An Oath needs any 2 of them, as in M4.

### 6.2 the Golden Wake (Oath of the Kept, 20, then 30)
The Kept win. They feed on hives and meadows instead of people, and the wax turns honey-gold. **This is the side that cools down** (Alex 10-8): a defensive, money-making Candlewake that leaves Wick alone and grows its host from the land.
- **Transformation:** Wickwardens become **Combwardens**: +2 hp, +1 morale.
- **New unit:** **Amber Saints**, 24/11/9/11, 22 gold, front, with **Iron Hide** (reused).
- **Province rule, Meadow Wake:** Wake provinces pay +1 gold instead of −1, and the Wake-Line comes 1 turn sooner. It stacks with Sitting Up Early, to at least 1 turn.
- **The Long Sleep (the Risen, §3.6):** the dead also rise from Wake-Line provinces, and every 3 turns instead of 4. It pumps out troops over time: the Golden Wake's target is the top of W6's range.
- Forswears **Muster Grounds**.

### 6.3 the Red Wake (Oath of the Snuffed, 20, then 30)
They stop apologising, and the wax runs cherry-red. **This side fuels the fire** (Alex 10-8): it burns hot and swells the horde through battle, not the land.
- **Flame cap 4.** An army above 3 that doesn't win drops to 3 the same turn, even in a harbour. An army idle outside a harbour loses 2.
- **Vigil and Kindle** never raise a flame above 3.
- **Transformation:** Gleaners become **Red Gleaners**: +2 attack, −2 hp, and Siphon heals 2.
- **New unit:** **Pyre-Walkers**, 16/13/5/9, 18 gold, front, with **Berserk** (reused).
- **Province rule, Pyre Roads:** a win gives +2 flame instead of +1, once a turn. It applies when the battle's province was owned by the Candlewake and at the Wake-Line or deeper **at the start of the battle phase**. A scar retaken that turn doesn't qualify.
- **Effective flame** caps at 4 (§2.2): Bonfire Night can't lift a flame-4 army past +3 attack.
- **The Swelling (Harvest):** every Harvest raises 1 more Wickwarden, from player armies and Free Holds alike. The Risen stay at the base rate.
- Forswears **Iron Discipline**.

### 6.4 explained
- **The lock-in preview** shows each fork's flame and gold effects in numbers.
- **Province tooltips** show Meadow Wake's +1 gold.
- **The Red Wake's army card** shows "4/4: drops to 3 if it doesn't win".
- **Pyre Roads** gets a forecast line.

---

## 7. magic (M5, CW-5): the Wick and Wax schools
- **Tiers:** as M5: I 10, II 15, mastery 20, III 25. Tier III needs the aligned Oath.
- **Spell kinds:** M5's existing kinds where they fit.
- **New code:** a **flame** effect (±flame on one army, capped) and a battle-only **flame bonus** global.

| school | tier I (battle) | tier II (ritual) | tier III (greater) |
|---|---|---|---|
| **Wick** (Red-aligned) | **Draw the Warmth** (bolt): 3 sure damage to the weakest enemy in reach, no self-bleed | **Kindle** (flame, 10 gold, range 2): a friendly army +1 flame now, never above 3 | **Bonfire Night** (global, 30 gold): through T+2, your regulars fight as if 1 flame hotter (battle only) |
| **Wax** (Golden-aligned) | **Wax Skin** (shield): +4 defence to 6 open-ground front units | **Raise the Snuffed** (summon, 4 gold a body): 3 Snuffed (7/9/8/8, Pall) through T+4 | **Candlemass** (blessing, 25 gold, range 2): one army heals 12 a turn and gets +1 morale through T+4 |

- **Casters:**
  - **Chandler's Apprentices**, once a spell is known.
  - **Half-Death** casts Draw the Warmth from turn 1, plus the Wick rituals.
  - **Mother Tallow** casts the Wax rituals.
  - Far Sight, as for everyone.
- **Default spellbook:** Draw the Warmth, then Wax Skin.
- **Raise the Snuffed** uses CW-0's summons generalisation.
- **Explained:** every spell gets M5's cast dialog, spellbook preview, `cast` event, caption and why line. Kindle's forecast shows the army's flame after the rituals phase.

---

## 8. the computer (CW-6)
The existing AI reads only what it already knows: `ai/ai_player.gd:67-76` and `:1240-1491` value existing traits, and it pours gold into the capital garrison (`:38-40`). CW-6 adds Candlewake-specific state evaluation and action scoring, under fog through its own view.

1. **Fuel.** An army at flame ≤ 1 with a winnable fight in reach (the battle guess counts flame) moves to it. Free Holds count early.
2. **Harbour in time.** An army that will drop to 0 with no winnable fight in reach heads for the nearest harbour. It never ends a turn at 0 outside a harbour when one is reachable.
3. **Recruit destination.** It doesn't cool a flame-2+ army unless that army is outnumbered: recruits go to a new or cooler army.
4. **Harvest.** It keeps Half-Death fighting in its own province when the odds allow.
5. **Vigil.** It parks Mother Tallow at the busiest muster.
6. **The Wake.** It holds taken provinces three turns behind the front, keeps Deep Wake provinces (the Risen), and retakes scars first.
7. **Paths and rituals:**
   - Golden presets build the Wake.
   - Red presets chase Pyre Roads.
   - It uses Kindle on the hottest army about to drop, and Bonfire Night before a planned big battle.
   - Magic AI needs M5-10, and CW-6 adds these rules on top.
8. **Against the Candlewake.** When a Candlewake army at flame ≥ 2 threatens a province and the guess is under 45%, the opponent prefers a fort or a retreat that denies battle.

**Tests:** deterministic fog-on autoplay tests, plus the early smoke run (the S-6 lesson): 4 Candlewake–Crown and 4 Candlewake–Clans games, each seat order, before the unit tests are trusted.

---

## 9. balance (CW-11), and benchmarks first (CW-2)
- **CW-2 micro-benchmarks** (`tools/balance/matchups.gd`):
  - each Candlewake unit against each Crown and Clans unit at flame 0–3, plus 4 for the Red Wake;
  - on open ground, forest, hills and in a fort;
  - against Shield Wall, Iron Hide and Blood Frenzy.
  - **Gate:** at flame 1, equal-gold pairs stay within the existing 20–80% and mixed armies within 30–70%.
- **The band functions become pair-keyed.** Crown–Clans keeps every existing band and its byte gates (H, P7).
- **Two configs:** every band runs with independents on (the contract, Alex 10-5) and off (report), and in both seat orders.

| band | target |
|---|---|
| **C3** | each pair (Crown–Clans, Crown–Candlewake, Clans–Candlewake) 40–60% over pooled presets |
| **W1** | the median flame at the start of a Candlewake battle is 1.3–2.3 |
| **W2** | guttering happens in 10–40% of Candlewake games; no army spends more than 60% of its turns at the cap |
| **W3** | Harvest is 10–20% of the Candlewake's total force (Red Wake: 20–30%) |
| **W6** | the Risen are 10–20% of the Candlewake's total force (Golden Wake toward 20%) |
| **W4** | the median number of Wake-Line provinces at turn 12 is ≥ 2; the Wake's gold cost is ≤ 10% of income |
| **W5** | median decisive game 10–16 turns in Candlewake pairs |
| **P1c** | each Candlewake fork side 40–60% |

**Knobs, in order:**
1. the flame curve;
2. the idle loss;
3. the Wake-Line threshold;
4. Harvest;
5. unit gold;
6. Pall.

---

## 10. 3D and art direction
- **Massing:** a slumped, uneven crowd, heads sunk into shoulders, never a rectangle. From the strategy camera a block of 40 is an ivory blot glittering with lilac points.
- **Flame height is the flame,** on every figure:
  - smoke at 0;
  - a tall lilac flame at 3;
  - cherry-red at 4 for the Red Wake;
  - honey-gold glints on the Golden Wake's wax.
- **The palette:**
  - ivory tallow;
  - soot-black wicks;
  - lilac flame;
  - brass snuffers.

  The living's warmth burns gold. A Candlewake wick burns lilac, the colour of something being used up.
- **Banner:** lilac with a soot border, a hem cut into wax drips, and an ivory candle ringed by flames.
- **Muster:** the dead shuffle out of the Vigil's mouth in no order and thicken into a tide.
- **Lookalike guards:**
  - no candlesticks with faces;
  - no flaming skulls;
  - no grim reapers;
  - no oath-bound dead;
  - no green and black.

  Keep "dark but not grim": Alex flagged a mound of wax heads in round 3b.
- **Faces are empty** (Alex 10-8, his verdict on art round 6c: eyeless). The host are **hollow shells**: a hood or helm of wax gives shape to a face that is nothing, with only the lilac wick-light inside. They are warlike, not sad.
  - The reference is the canon `candlewake_tide.png`.
  - Rank-and-file are pure wax; the hood and helm shapes vary by unit so the host reads as an army.
  - **The lookalike guard:** the hooded void is an old archetype. Stay clear of the famous one's tells: no black riders on black horses, no spiked iron crowns, no pale-blade daggers. Ours are ivory wax lit lilac from inside, dripping.

---

## 11. art (CW-9 and CW-10)
Every asset goes through the Review Table (`review/cw_*`). Models are judged in the orbit viewer against what the game has now.

| what | count | credits |
|---|---|---|
| unit, commander, mage and ruler model families (4 poses) | 7 | ~105 |
| path looks and new units | 4 | ~60 |
| candlebeast families (Wax Hounds, the Tallow Stag, the Guttering Bear; base first, then 4 poses) | 3 | ~45 |
| portraits | 11 | ~17 |
| fort kit (3 tiers) and the Long Vigil | 4 | ~20 |
| building melts (village a/b, mill, watchtower, fort, × 3) | 15 | ~45 |
| banner, emblem, spell icons, flame VFX | ~10 | ~15 |
| **total** | | **~305, 375 with reserve** |

Rates are from `studio/ledgers/asc-3d-factions.jsonl`: 3.0 a model, 1.5 a 3-candidate picture call, 0.5 a pose edit.

---

## 12. tickets
`hard` marks the big-risk ticket.

**Order:**
1. CW-0, then CW-1.
2. Then CW-2, and CW-7 and CW-9 alongside it.
3. Then CW-3 (the Wake builds on Wick).
4. Then CW-4, CW-5 and CW-6.
5. Then CW-8, CW-10 and CW-12 (candlebeasts need Deep Wake from CW-3).
6. CW-11 closes the milestone.

0. **CW-0** `code` `hard` **Three factions in the engine** (§1):
   - the explicit factory;
   - frozen legacy constructors;
   - seat capitals and `capital_name`;
   - default and quick-start pick 2;
   - the generated two-faction audit;
   - N-side battle views;
   - summons from data.
   - **Gate:** raw JSON and digest byte-identity for every old feature combination.
1. **CW-1** `code` **Scaffold:**
   - optional `flame` on armies and the top-level `marks`, both omitted when unused;
   - save and load;
   - the fog allow-list (flame in clear sight only);
   - the Wick step and wake step as phase hooks;
   - event contracts: `flame_changed`, `guttered`, `harvest`, `mark_stage`, `scar_formed`, `scar_consumed`.
2. **CW-2** `code` **The host and Wick** (§2, §4):
   - the faction row, units, rulers, mandates and presets;
   - the four traits;
   - recruit destination;
   - the micro-benchmarks (§9);
   - every §2.5 explanation.
3. **CW-3** `code` **The Wake** (§3): `MarkData`, stages, the cold wake truth table (§3.3), the Risen (§3.6), tooltips, report lines and codex.
4. **CW-4** `code` **Paths** (§6), with §6.4's explanations.
5. **CW-5** `code` **Wick and Wax** (§7).
6. **CW-6** `code` **The computer** (§8), with the early smoke run.
7. **CW-7** `code` **New game and screens:** 3 factions to 2 seats, `capital_name` everywhere a capital is named, title banners and the victory text.
8. **CW-8** `code` **3D:** flame height, wax massing, the fort kit, and the Wake on the board (§3.5).
9. **CW-9** `design` **Art lead:** manifest rows from the canon. Eyes are settled: empty hooded shells (§10).
10. **CW-10** `asset` **Asset builder:** the Ludo batches into the Review Table (§11).
11. **CW-11** `code` **Balance:** pair-keyed matrices and the W bands (§9).
12. **CW-12** `code` **Candlebeasts** (§4.5): the three unit rows, the Deep Wake recruit gate with its greyed-out reason, the codex page, and their place in the computer's recruit choice. Their art rides in CW-10, base model approved before any pose.

**Default:** the Candlewake ship behind a "Candlewake (preview)" box until CW-11's bands pass.

---

## 13. out of scope
- three-player maps and a third seat;
- mirror matches;
- army split and merge orders;
- retreats (losing armies are still destroyed);
- Crown and Clans marks (the engine is ready for them);
- battle fog for battles you didn't fight (M6);
- Candlewake voice lines.
- **A game-wide terrain pass** (Alex 10-9): how a province's land shapes what can be recruited there, which units are available and who defends it, for every faction. Candlebeast forms picked by the land would roll up under it.

## 14. director's calls (review these first)
1. **Any two of three.** The Crown and the Clans keep their capitals, and the Candlewake take the free one. That is derived, not stored, so old records are untouched. It is the cheapest honest third faction on a 2-player map.
2. **Wick:**
   - win +1;
   - idle outside a harbour −1;
   - no loss transition, since losers are destroyed;
   - battles use the flame from the start of the battle phase;
   - one Wick step in a fixed order;
   - flame − 1 attack.
3. **Free Hold wins raise flame but never Harvest.** Flame from any fight is the faction; Harvest is the snowball, so only player armies feed it.
4. **Recruits cool what they join.** The order names its destination and previews the flame. A new army is a fair choice, not an exploit: it is cold and separate.
5. **The marks engine is generic, and only the Candlewake have a row.** It is omitted from Crown–Clans states.
6. **The Golden Wake is economy, and the Red Wake is momentum.** The Golden Wake no longer touches Wick (Codex: "flame never falls" erased the faction's tension).
7. **New code stays small:**
   - four host traits;
   - the flame effect and the battle flame global;
   - reused Iron Hide, Berserk, bolt, shield, summon and blessing.

## 15. Alex's answers (2026-10-08)
1. **The flame curve:** a) flame − 1. "Sounds like a good balanced start."
2. **Free Holds as fuel:** flame yes, and **a reduced Harvest** (1 Wickwarden). "A strong early game should be part of his strengths. It's OK to break a few things if everyone has access to broken shit."
3. **The Golden Wake:** a) keep. Golden lets a player cool down into a defensive, money-making style; Red fuels the fire.
4. **Eyes:** eyeless, in his art round 6c verdict: "more warlike, empty shells with hoods of wax to give shape" (§10).
5. **His new idea (§3.6):** as their land is made in their likeness, the dead turn to wax and rise again. The Golden Wake keeps it pumping, and the Red Wake swells the horde through Harvest instead.
6. **Candlebeasts (§4.5): who picks the form?** c) the player picks now (any form in a Deep Wake province), and the land picks later. "We could think smarter about how terrain ties into recruitment, available units, defenders, etc. in general, and that can roll up under there if and when we decide to go down that route." Land-picked forms wait for a game-wide terrain pass (§13).

**Design notes for every faction:**
- Asymmetric power spikes are welcome when every faction has its own. The bands are guardrails, not a flattening.
- **Targets, not hard caps** (Alex 10-8): when we aim for a number, it's a range to tune toward (e.g. the Risen at 10–20% of the force), not a rule that clips play. Within reason: a cap that defines how a mechanic works (Flare's 6 targets, Harvest once a turn) is fine.

---

## appendix A. critic rounds

### round 1 (Codex, hostile, 2026-10-07): 24 findings, 6 blockers
**Taken:**
1. **Losers are destroyed** (`turn_resolver.gd:846-878`), so "−1 on a loss" was unreachable. It was removed.
2. **Factory and seat capitals:** players arrive after state construction, and the capital belongs to the faction. Added the explicit factory, frozen legacy constructors, and seat capitals materialised before setup.
3. **`default_config` seated every faction.** Configs now pick exactly 2, tested over all 6 pairings.
4. **Flame timing:** battles use start-of-phase flame, per-turn facts are recorded, and one ordered Wick step runs.
5. **No split or merge orders:** that language was removed, and flame belongs to the army id.
6. **Recruiting:** the order names its destination and previews the cooling.
7. **Costs:** +1 attack a flame on a 6-gold Pall body broke the curve. Now:
   - flame − 1;
   - Wickwardens cost 7 with Pall at −5%;
   - Gleaners cost 8 and heal once a round;
   - micro-benchmarks are gated in CW-2.
8. **Flare** is capped at 6 front-rank fighters, with its timing defined.
9. **Harvest** fires once a turn, only against player armies, at 1–2.
10. **The Wake timing:** a truth table, the scar consumed on retake, no decay on its creation turn.
11. **Byte identity:** marks are omitted when unused, in a top-level dictionary of non-empty entries.
12. **Fog:** exact flame only in clear sight.
13. **The Golden Wake** no longer stops flame loss.
14. **The Red Wake:** cap 4, drops above 3 without a win, and Vigil and Kindle stop at 3.
15. **Vigil** sits at a fixed place in the Wick step.
16. **Magic** was redesigned onto existing kinds, plus one flame effect.
17. **The audit** is generated, with the missed hits listed.
18. **The AI section** was expanded.
19. **Explanations** are listed per ticket.
20. **The scaffold ticket CW-1** was added, and the Wake now follows Wick.
21. **The byte gate** is at the raw JSON level.

**Taken in part:**
- **Free Holds as fuel (finding 12):** flame stays, Harvest is removed. Flame from any fight is the faction's identity, and the bands cover independents on and off.
- **Recruit laundering (finding 7):** a new cold army is a legitimate choice, so there is no cap.

### round 2 (Codex, on r2, 2026-10-08): 14 precision findings, no new design holes
All 14 were taken.
- **Capitals:** derived from the faction set, never serialized. Saved seat capitals would have broken the byte gate (findings 1 and 14).
- **Harvest's destination:** a ruler's army holds only its ruler, so the Wickwardens join the lowest-id regular army that fought, or form a new one.
- **Recruits:** a serialized `into` field with new-army groups.
- **The end clock:** `E = current_turn + 1`. The wake step runs before the Wick step, so a new Wake-Line shelters at once. Worked turn tables for the mark and the scar.
- **The round order:** Pall's formula inside the clamp; Flare's targeting and tie-breaks; Siphon only while standing, blocked by Bloodrot; Toll per battle, counted before that round's morale check.
- **Pyre Roads** reads the battle-phase snapshot.
- **Effective flame** is capped, so Bonfire Night can't exceed it.
- **Ruler stats** are written as `{base, gain, per}` triples, with ability rank named apart from battle rank.
