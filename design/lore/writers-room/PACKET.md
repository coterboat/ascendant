# ASCENDANT lore writers' room: the shared packet

Compiled 2026-10-04 by the Claude seat from the repo at `f79e660` (branch `lore-writers-room`). This packet is for writers who can't read the repo. Everything you need is on this page. §2 is the game brief, copied word for word. Everything else summarises the repo's design docs and data files. When this packet and the repo disagree, the repo wins. Tell the room if you find a mismatch.

Status words used below:
- **APPROVED**: Alex signed it off.
- **PROPOSED**: built or written so there is something to play, but Alex hasn't approved it. Names and numbers can change.
- **BUILT**: exists in the game's code today.

---

## 0. Direction update: the game is going 3D (2026-10-04)

Relayed by the director from Alex on 2026-10-04:
- **The world map becomes a 3D stylized world.** You see armies mustering inside fortresses, ready to spill out for war.
- **Battles become 3D too.**
- **The UI stays 2D** on top: panels, tooltips, portraits, banners, reports.

The game brief in §2 and the style bible excerpts in §3 were written before this change. They still say "2D", "sprites" and list "3D" as a non-goal. The brief can change only with Alex's OK, so the docs haven't been edited yet. Until they are, read every 2D, sprite or map-token line as **superseded for the world map and battles only**. Portraits, banners and UI art stay 2D and keep their rules.

**What this means for writers:**
- Describe each faction's look for **stylized 3D models seen from a strategy camera**, high up and at a distance:
  - its silhouette and massing at distance (what a block of 40 of them looks like from above)
  - its signature materials
  - its banner and emblem colours
- **Fortresses are hero pieces now.** Describe each faction's fortress and capital architecture as it reads on the map, and its **muster grounds**: where and how its army gathers before it spills out.
- Keep the bright, characterful tone (§3.1). The game is still colourful, still readable first, and art still never carries player colour.

---

## 1. How to use this packet

1. Read the brief (§2). It is approved, and every pitch has to fit it.
2. Skim the look (§3) and what's already built (§4–§6). Two factions, four rulers and ten mandates exist. You may deepen or re-flavour the two built factions, but they stay.
3. Read the engine constraints (§7). This is what a faction can actually *do* in this game. A faction that only looks different fails the brief.
4. Answer the writers' brief (§8) in your R1 pitch (§9 has the format).

---

## 2. The game brief (word for word)

Source: `design/GAME_BRIEF.md`. Its headings are moved down two levels to fit this page. The text is otherwise unchanged. **Remember §0:** its 2D, sprite and "3D is a non-goal" lines are being superseded for the world and battles.

### ASCENDANT: game brief

Status: **APPROVED by Alex, 2026-09-30.** Changes after approval need Alex's OK.

#### one line
A deep, simultaneous-turn fantasy strategy game with the spirit of Dominions 6, where your ruler trades personal power for faction-wide strength, your people can transform down locked-in paths, battles are worth watching, and every rule is visible so you never need a wiki.

#### who it's for
Players who love the idea of Dominions (strange asymmetric factions, big magic, huge armies, battles decided by preparation) but bounced off its opacity. Fans of Age of Wonders 4's faction building who want harder choices and deeper strategy. And veterans of both who want real decisions without the friction.

#### what "the spirit of Dominions" means here
We keep the feel, not the rulebook: wildly asymmetric factions, a build decision before the game that defines your whole strategy, deep magic, simultaneous orders, and battles you win by preparing, not by clicking. We do **not** copy dominion spread, pretender god points, or the scales system. We replace them with our own systems below.

#### pillars
1. **Power is a budget you spend on your people.** Your ruler's personal might and your faction's strength come from the same pool. Every point you keep for yourself is a point your nation doesn't get.
2. **Commit and become.** Your faction develops down branching paths that lock in. Big forks change what your people are, not just what they have. No two games of the same faction need to end the same way.
3. **Preparation wins battles, and battles are worth watching.** You choose the army, commanders, formation, and simple orders. The autobattle plays out from that with great sprite animation and spell effects, and the report tells you exactly why you won or lost.
4. **Nothing hidden that matters.** Every number explains itself on hover. Every order and every lock-in shows its outcome before you commit. Randomness is shown as odds and ranges.
5. **Simultaneous turns, readable results.** Everyone orders at once, then everything resolves together in one deterministic pass, and the turn report explains every change as cause and effect.
6. **Polish over breadth.** Fewer factions, units, and spells, each distinct and well explained. UI/UX and battle presentation are features, not a finishing pass.

#### core system 1: the ruler and mandates
Every faction is led by a **ruler**. A ruler can be anything: a living god, an undying lich, a dragon, a council of archmages, or an ordinary human king.

- Each ruler starts with a pool of **ruler power**.
- Power you **keep** makes the ruler personally strong: combat stats, spell mastery, battlefield presence, and abilities that affect their province.
- Power you **spend** buys **mandates**: faction-wide traits that shape how your whole nation plays.
- Example mandates:
  - *Royal Armories*: every recruited unit comes with an equipment upgrade.
  - *Iron Discipline*: armies hold formation and never rout while their commander stands.
  - *King's Roads*: +1 movement inside your own territory.
  - *Tithe of Blood*: sacrifices fuel rituals instead of gold.
  - *Sworn Vassals*: independent provinces join you more cheaply.
- So an ordinary man ruling a human kingdom can have the best-equipped, most organized army in the land, because he spent nearly everything on his people. A demigod ruler is a one-person army leading a thinner nation. Most builds sit in between.
- Some mandates are faction-exclusive, some are shared. Each faction's ruler options are curated so the choice is always interesting.
- **Mid-game sacrifice:** the ruler can give up more power later for new mandates (permanent, previewed before you confirm). This is a big lever in desperate moments or to lean into a winning plan.
- **Risk:** a weak ruler is easier to kill. Losing your ruler is severe but not always the end. Mortal lines have heirs, undying rulers reform slowly, and gods get weaker. Each faction's rules are shown in-game.

#### core system 2: paths of ascension (development trees)
Research is organized into **paths** per faction: military doctrine, society and economy, and magic schools.

- Most nodes are ordinary upgrades you can mix freely.
- At a few points on each path there's a **fork** that locks you in. Taking one branch closes the others for the rest of the game.
- The biggest forks are **transformations** that change what your people are. A human kingdom might ascend into a celestial host, bind itself to living iron, or pay a blood pact and become something darker. A transformation changes unit rosters and their look, the economy's rules, how provinces respond to you, and which mandates become available.
- Every fork shows a full preview first: exactly what you gain, what you lose access to, and what your units will look like.
- Age of Wonders 4 is a reference for faction-wide transformation. We go further by making the choices exclusive and permanent, and by tying them to ruler power.

#### core loop (one turn)
1. **Read** the turn report: what happened, why, and what needs you.
2. **Plan** on one map screen: move armies, recruit, research, cast rituals, set battle orders. Each order shows a forecast (arrival turn, cost, research ETA, rough battle odds against what you can see).
3. **Commit** and end turn.
4. **Resolve**: all players' orders run together from a seed in a fixed, documented order (movement, battles, sieges, income, research, events).
5. Watch the battles you care about, skim the rest from their reports, and repeat. You win by holding enough **ascension sites** (victory provinces) or by eliminating rivals.

#### what we keep from Dominions 6
- Strongly asymmetric factions with distinct units, magic, and playstyle.
- A defining pre-game build (now the ruler and mandates).
- A province map with terrain, population, income, and supply.
- Magic research, rituals, battle spells, and commanders gated by magic.
- Recruitment: faction units, independents, commanders who lead troops, forts that gate recruitment.
- Simultaneous orders resolved together.
- Battles that play out from your preparation, with formations and simple commander orders.

#### what we cut or change
- **Dominion spread, pretender god points, and scales:** replaced by ruler power, mandates, and paths.
- **Hidden rules and stats:** nothing the player can't inspect in-game.
- **Opaque numbers:** every derived value has a breakdown tooltip.
- **Screen sprawl:** one main map screen with panels. Common actions within two clicks.
- **Unexplained outcomes:** battle and turn reports explain causes, not just results.
- **Guide-only knowledge:** an in-game codex, linked from every term.
- **Roster bloat:** curated units and spells, each with a distinct job.
- **Busywork:** gem and resource shuffling, repetitive recruitment, and army bookkeeping get sensible defaults and repeat-last-turn options.
- **Ambiguous resolution order:** fixed, documented, and visible.
- **Dated battle presentation:** readable, animated sprites with strong spell and impact effects.

#### battle presentation
- Autobattles are resolved by pure rules code first, then played back visually from the result. The playback never changes the outcome.
- Sprites are animated (idle, move, attack, hit, death). Spells and big hits get real effects: projectiles, impacts, screen shake, readable area markers.
- Playback controls: speed, pause, skip, and jump to key moments. Hovering a unit shows what it's doing and why.
- Readability beats spectacle: you can always tell who's winning and why. Art lead owns the look through the style bible.

#### approachability rules (apply to every ticket)
1. No mechanic ships without in-game explanation in the same PR: a tooltip, a preview, or a forecast.
2. Every order, mandate, and fork previews its outcome before commit.
3. Every number shown can explain itself on hover.
4. Progressive disclosure: the simple view first, the full breakdown one hover or click away.
5. Turn and battle reports read as plain-language cause and effect, linked to the provinces, units, and rules involved.
6. Rules are pure, deterministic code resolved from a seed, so any turn or battle can be replayed and explained.
7. Plain language. No invented term without a codex entry.

#### setting and tone (my recommendation)
An original high-fantasy world where rival rulers race to ascend, whether that means godhood, empire, or something stranger (hence the title). Dark but not grim, colorful and characterful. Our own factions, names, and lore. Art direction is owned by art lead once this is approved.

#### scope defaults (my recommendation)
- **Platform:** desktop (Windows/Mac/Linux), mouse and keyboard.
- **Players:** single player against AI rivals first. Hotseat comes early because turns are simultaneous and deterministic. Online play is a later goal the architecture must not block.
- **Battles:** rules and a readable written report first, then animated playback. Playback quality is a pillar, not a nice-to-have.
- **Content target for a 1.0:** 4 to 6 factions, each with several ruler options, a curated mandate list, and 2 to 3 transformation forks. Maps for 2 to 6 players.

#### non-goals (for now)
- Real-time anything, or direct battle micromanagement.
- Online multiplayer, matchmaking, or accounts (the door stays open).
- Mod support or scripting tools.
- A story campaign.
- Matching Dominions' content volume.
- 3D. The game is 2D, with a clean, readable map and animated sprites.

#### how we'll know it's working
- A new player finishes a first game without leaving the game to look something up.
- After any lost battle, the player can say why they lost from the report alone.
- Players argue about ruler builds: keep power or spend it, and on what.
- Two games with the same faction feel different because of the forks taken.
- People watch battles because they want to, not because they have to.

---

## 3. The style bible, key parts

Source: `design/STYLE_BIBLE.md`. **FINAL: direction "Bright Cel", picked by Alex on 2026-09-30.** It is owned by the art lead, and only the art lead changes it. Below are the parts writers need: tone, palette and readability. Production details (Ludo calls, canvases, gates) are left out. **Per §0, its sprite and map-token rules will be replaced by 3D rules for the world and battles. Its portrait, banner, colour and UI rules still hold.**

### 3.1 Tone and direction
- Original **high fantasy**, dark but not grim, **colourful and characterful**.
- Rulers can be anything. Factions **transform** through lock-in forks.
- Battles are worth watching, and **readability beats spectacle.**
- **Bright Cel**: bold, clean high fantasy. Thick even outlines, flat saturated colour with one hard shadow tone and one highlight tone, and big readable shapes. **Darkness comes from subject and palette, not texture.** It is the most legible style at small sizes.
- Rejected directions: Illuminated Storybook and Vivid Tabletop.

### 3.2 Palette
**Player colours belong to the player slot, never to a faction.** Unit, portrait and banner art never carries player colour. The game draws player identity in code (rings, plaques, province tints), each colour paired with an emblem so the game also reads in greyscale:

| slot | name | hex | emblem |
|---|---|---|---|
| P1 | Vermilion | `#D8432C` | circle |
| P2 | Cobalt | `#2D5BD1` | square |
| P3 | Gold | `#F1C232` | triangle |
| P4 | Sky | `#62C3F0` | diamond |
| P5 | Jade | `#2E9E6A` | hexagon |
| P6 | Magenta | `#D14FA8` | Greek cross |
| IND | Slate (independents) | `#5B5750` | heater shield |

**Faction material palettes** are worn in the art and don't depend on player colour:
- **Aurel Crown:** steel, white linen, royal blue, gold.
- **Thornmane Clans:** tawny fur, bone, moss green, crimson war paint.
- New factions need their own palettes, distinct from these two and from each other at a glance.

**Terrain** is colourful but quieter than the pieces: plains `#B3B86A`, forest `#3F7A55`, hills `#B08A5E`. Proposed for later: farmland, mountains `#8D88A0`, swamp, waste, tundra, sea `#2F7A93`, deep sea.

**UI** is deep indigo panels (`#1C1B2A`) with gilt accents (`#E6B84E`). Portraits sit on a softly graded deep indigo background, so a figure must separate from dark indigo.

### 3.3 Readability rules writers should design for
- **Every figure has a light area and a dark area** (one lighter than L\* 70, one darker than L\* 30), with a mid-tone overall. A faction that is all pale or all dark has to fix that with an accent.
- **Unit classes read by silhouette** (written for sprites, and the same idea carries to 3D massing):
  - infantry: weapon upright near the body
  - heavy infantry: big shield or weapon
  - ranged: weapon angled away
  - mounted: wider than tall, with the mount's legs visible
  - commander: a standard, staff or raised weapon well above the head
  - caster: a bell-shaped robe and a glowing focus
  - flyer: wings wider than tall
  - monster: fills its frame
- **Banners:** one bold invented emblem, readable at 48 px tall and in greyscale. The two built banners differ in hue, value and emblem shape at a glance.
- **Portraits:** head and shoulders, three-quarter view, with a named held item visible. The faction has to read from materials and palette at 96×128 px.
- **The art never contains text or logos, and every emblem is invented.** Re-roll anything that looks like a real flag.
- **Transformations keep recognisability.** A transformed unit keeps its silhouette, pose, what its hands hold, and its class read. **One faction accent keeps its hue** (plume, tabard trim or banner cloth). Only the materials, the palette of those materials, and overlays change. The bible already sketches three human-kingdom transformations, and the real forks are fixed later (M4):
  - **ironform:** armour, shield and skin become dark riveted living iron with glowing orange seams
  - **celestial:** white-gold radiant armour with a soft ring of light behind the head
  - **bloodpact:** crimson and black, small bone spurs, glowing red eyes

---

## 4. What's built: the two factions (BUILT)

Source: `data/factions.gd` and the shipped art prompts. Both factions start with 45 gold, and their starting armies cost about the same. Stats were tuned so the starting armies win 40–60% against each other.

**Stat glossary:**
- **hp:** hit points. Wounds carry over between battles, and units don't heal on their own.
- **attack / defense:** set hit chance and damage (§7.2).
- **morale:** how much of its starting hp a side can lose before it breaks (routs).
- **cost:** recruit price in gold. In M1 you recruit only at your capital.

### 4.1 The Aurel Crown (`kingdom`): a disciplined human kingdom
**Look:** steel, white linen, royal blue and gold. Its banner is royal-blue cloth with a white border and a lower edge cut into three points, with a golden crown above a rising sun. The capital is **Crownkeep** (plains, fort). The Ever-Regent's **sunstone** is kept there.

| unit | hp | atk | def | mor | cost | trait | look (shipped portraits) |
|---|---|---|---|---|---|---|---|
| Spearmen | 8 | 9 | 7 | 6 | 8 | **Shield Wall** | young weathered face, open steel helm with a blue plume, blue tabard with gold trim, long spear |
| Crossbowmen | 8 | 11 | 9 | 7 | 10 | **Volley** | padded blue-and-white gambeson, kettle hat, loaded crossbow across the chest |
| Knights | 18 | 11 | 9 | 12 | 20 | **Charge** | steel plate with gold trim, blue surcoat, white warhorse, upright lance |
| Knight Captain (commander) | 26 | 13 | 13 | 12 | 35 | **Inspire** | grizzled bearded veteran, gilt plate, blue cloak with a crown-and-sun clasp, sword held hilt-up |

### 4.2 The Thornmane Clans (`beasts`): wild beast tribes
**Look:** tawny fur, bone, moss green and crimson war paint. Its banner is ochre hide cloth with a crimson border and a torn lower edge hung with small bones, with a bone-white horned beast skull wreathed in green thorns. The capital is **Fangridge** (plains, fort).

| unit | hp | atk | def | mor | cost | trait | look (shipped portraits) |
|---|---|---|---|---|---|---|---|
| Tuskers | 14 | 11 | 4 | 7 | 11 | **Berserk** | hulking boar-headed beastman, tusks, crimson stripes, moss-green harness with bone plates, stone-headed club |
| Fangthrowers | 8 | 11 | 5 | 7 | 8 | **Skirmish** | lean wolf-headed beastwoman, crimson muzzle paint, bone-tipped javelins |
| War Bear | 23 | 13 | 8 | 9 | 22 | **Fury** | huge brown bear with moss and thorny vines in its fur, bone shoulder plates, crimson handprints |
| Warchief (commander) | 31 | 15 | 9 | 12 | 35 | **Pack Leader** | towering lion-maned beastman, mane braided with bones and thorns, horned-skull totem staff |

### 4.3 The eight traits (BUILT, exact in-game text)
Every unit has exactly one trait with one effect:
- **Shield Wall:** Gets +2 defense while any other fighter on its side still stands.
- **Volley:** Shoots from the second rank, behind its side's units without Volley. While at least as many of those stand as units with Volley, they shield it: only enemies with Skirmish can attack it. Commanders stand further back, so they don't count.
- **Charge:** Deals +4 damage with every hit in the first round of a battle (+3 in a forest).
- **Inspire:** While it stands, its side gets +2 morale, on top of the +2 any standing commander gives.
- **Berserk:** Gets +3 attack while below full hit points.
- **Skirmish:** Can attack the enemy's second rank (its units with Volley) as well as its front rank, even while the front rank shields them.
- **Fury:** While it stands, every enemy side gets -2 morale (at most -3 in all, however many roar).
- **Pack Leader:** While it stands, every unit on its side gets +1 attack.

### 4.4 The M1 map (BUILT)
The map has 14 provinces, mirrored for a fair two-player start. Plains, forest and hills each have an income, and four provinces have forts. The names set the existing naming register: Crownkeep, Westwatch, Stonegate, Highcrag, Rivermarch, Greenglade, Thornvale, Deepwood, Wildmoor, Blackwood, Ebonpeak, Ironspike, Bloodfen, Fangridge. Today you win by capturing the enemy capital. Ascension sites come later.

---

## 5. The four rulers (PROPOSED, built behind a preview toggle)

Source: `data/rulers.gd` and `design/M2_RULER.md`. Each faction picks one of two rulers before the game.
- **Every ruler has a power pool of 10.** Power you **keep** sets the ruler's hp, attack, defense and the rank (1–4) of its one province ability. Power you **spend** buys mandates (§6).
- The ruler travels alone as its own army and fights in battles. It gives +2 morale to its side while it stands.
- **A ruler's death never ends the game.** Succession depends on the ruler's **kind**.

| ruler | faction | kind | battle rank | stats at 0 → 10 kept | province ability | succession | flavour (codex line) |
|---|---|---|---|---|---|---|---|
| **King Corvane** (Corvane II, III… as heirs) | Crown | mortal line | front | 18/9/8 → 38/14/13 | **Royal Court**: the province he's in earns +2/3/4/5 gold | heir in 2 turns, half power | An ordinary man of the Aurel line. Spend his power and he governs the best-equipped kingdom in the land. Keep it and he rides to war as a paladin. |
| **the Ever-Regent** | Crown | undying | second (behind the front, like Volley) | 14/8/6 → 24/18/11 | **Mending Light**: your wounded units in his province heal 3/6/9/12 hp a turn | re-forms in 4 turns, full power | An archmage who bound his life to the sunstone in Crownkeep. He cannot die, only be broken, and he re-forms slowly. |
| **the Great Thornmane** | Clans | god | front | 24/8/7 → 54/18/12 | **Dread**: every enemy side in a province battle it fights in has −1 morale (adds to Fury) | returns in 1 turn, −3 power for good | The clans' beast-god, walking among them in a body of briar and fur. When the body is slain, the god takes a new one, a little less of itself each time. |
| **the Ninth Fang** (the Tenth Fang… as heirs) | Clans | mortal line | front | 20/9/7 → 40/19/12 | **Warband Muster**: recruit 1/2/3/4 units a turn where the Fang stands, not only at the capital | heir in 2 turns, half power | The high chieftain of the old fang bloodline. When one Fang falls, the next of the blood takes the mantle. |

For scale: a 10-kept ruler is worth one and a half to two commanders in battle. A 0-kept front-rank ruler falls in about two thirds of even mid-game battles.

Planned 3D looks for the rulers: King Corvane wears a crowned helm and carries a longsword and kite shield. The Ever-Regent is a caster with a sunstone staff and a glowing focus. The Great Thornmane is a large beast of briar and fur. The Ninth Fang carries a bone-hilted greatblade.

**Ready-made builds (presets):**
- Crown: Warrior King (no mandates), Iron Crown (Royal Armories, Heavy Tithes, Veteran Levies), Regent's Court (Royal Armories, King's Roads, keeping 5).
- Clans: Beast-God Unbound (no mandates), Clan Moot (Iron Discipline, Blood Frenzy, Sworn Vassals), Blood of the Fang (Iron Discipline, Drilled Ranks, keeping 5).

---

## 6. The ten mandates (PROPOSED)

Source: `data/mandates.gd`. Mandates are faction-wide traits bought with ruler power.
- Six are shared, and each faction has two of its own.
- They cost 2–4 power, and the total must fit in the pool of 10.
- They work from turn 1 and **never go away, even when the ruler dies.**
- **Mid-game sacrifice:** once per turn, a living ruler can give up more power for a new mandate, at its price **+1**. The game shows a before → after preview first.

| mandate | who | cost | effect |
|---|---|---|---|
| Iron Discipline | shared | 3 | Your side never breaks (routs) while one of your commanders in that battle stands, except at the end of the last round. |
| Drilled Ranks | shared | 2 | Your fighters' base hit chance is 70% instead of 60%. |
| Veteran Levies | shared | 3 | Your regular units have +2 maximum hit points. |
| Heavy Tithes | shared | 4 | Every province you own earns +2 gold per turn. |
| Muster Grounds | shared | 4 | Recruits cost a fifth less: a fifth of the price, rounded down, comes off. |
| Sworn Vassals | shared | 4 | Each turn, one neutral province next to your land swears fealty and joins you. |
| Royal Armories | Crown | 3 | Your regular units have +1 attack. |
| King's Roads | Crown | 2 | Armies can move two provinces in one turn inside your own territory. |
| Blood Frenzy | Clans | 3 | Your fighters below full hit points have +3 attack. A Tusker's Berserk adds to it, for +6. |
| Feast of Victory | Clans | 3 | After each battle you win, your fighters still standing heal to full hit points. |

The brief also names *Tithe of Blood* (sacrifices fuel rituals instead of gold). It waits for magic.

---

## 7. Engine constraints: what any lore has to fit

Write factions the engine can play. These are the levers a faction can pull. Asymmetry should come from **which levers a faction pulls and how hard**, not from new systems nobody has built. One new faction-wide rule per faction is fine, and so is a new trait per unit. A brand-new subsystem needs a very good reason.

### 7.1 Units, commanders, rulers
- **A unit is hp, attack, defense, morale, cost and ONE trait.** One trait, one effect, said in one plain sentence (see §4.3 for the register).
- **Commanders** lead armies (at most one per army). They fight from behind everyone and add +2 morale to their side while they stand, plus their own trait.
- **Rulers** (§5) trade kept power for mandates. Each has a kind (mortal line, undying, god) that sets succession, a battle rank, and one province ability whose strength scales with kept power.
- **"Regular units"** means roster units, not commanders or rulers. **"Fighters"** means all three.

### 7.2 Battles: autoresolved, then explained (and soon watched in 3D)
- Pure rules code decides the battle from a seed. Playback (3D now, per §0) only shows what the rules decided and never changes it. The report says in plain words **why** a side won.
- **Rounds:** at most 8. Every standing fighter attacks once per round, all at the same time, so a fighter that falls still strikes that round.
- **Ranks:**
  - Units form the front rank.
  - Volley units stand in a second rank, shielded while the front is at least as big. Skirmish reaches them anyway.
  - Commanders stand behind everyone.
- **Hit chance** = 60% + 4% per point of attack above the target's defense, kept between 30% and 90%.
- **Damage** = attack ÷ 2 (rounded up) − defense ÷ 4 (rounded down), at least 1.
- **Morale and rout:** a side breaks once it has lost 20% + 5% × morale of its starting hp (kept between 25% and 95%). Commanders, rulers, Inspire, Fury and Dread move morale.
- **A side that breaks loses, and every army on the losing side is destroyed.** There are no retreats yet.
- **Terrain helps only the defender** (the side that held the province):
  - forest: +2 defense
  - hills: +1 attack and +1 defense
  - a fort adds +2 defense
- **Border battles** (two armies swapping provinces) and meetings where everyone arrived that turn have no defender, so nobody gets terrain.
- **After 8 rounds** the defender holds if it is still standing.

### 7.3 Economy and the map
- **Provinces** have terrain, income (gold) and neighbours, and some have forts. Recruiting happens at the capital (more places later: forts gate recruitment). Neutral provinces exist and can be won.
- **Planned:** supply, population, sieges, independents you can recruit, and more terrains (sea, mountains, swamp, waste, tundra).

### 7.4 Simultaneous turns
- **Everyone orders at once.** Then everything resolves together in one fixed, documented order from a seed: movement, battles, sieges, income, research, events. Replaying the same orders always gives the same result.
- **Forecasts:** every order shows arrival, cost and rough battle odds against what you can see. Randomness is shown as odds and ranges.
- **Hotseat play:** a handoff screen hides each player's orders from the other.

### 7.5 Transformations (M4, planned)
- Each faction's research is organised into paths. A few **forks lock in**: taking one branch closes the others for good.
- **The biggest forks are transformations** that change what the people *are*:
  - unit rosters and their look
  - the economy's rules
  - how provinces respond to you
  - which mandates become available
- Every fork shows a full preview first. Plan for 2–3 transformation forks per faction at 1.0.

### 7.6 Magic (M5, planned)
- Magic schools, research, rituals on the map, battle spells, and commanders gated by magic.
- **Fog of war** arrives with magic.
- Nothing exists yet, so school *seeds* are welcome.

### 7.7 Approachability (applies to every idea)
- Every mechanic needs in-game explanation (tooltip, preview or forecast). **Every invented term needs a codex entry,** so invent few terms and make them plain.
- A new player has to finish a first game without a wiki. Write factions you can explain in two sentences.

### 7.8 Scope
- The target for 1.0 is **4 to 6 factions**, each with several ruler options, a curated mandate list and 2 to 3 transformation forks. Maps are for 2 to 6 players.
- Polish over breadth: fewer, sharper things.

---

## 8. The writers' brief

Propose the **starting ground for the whole game's lore**: the foundation that every race, unit and ascension grows from. Answer all seven parts.

1. **The world premise, and what "ascension" literally is.** Give a cosmology that makes the core systems feel inevitable in the fiction:
   - why a ruler's power is a budget split between self and people
   - what a mandate *is*
   - why mid-game sacrifice costs extra
   - why mandates outlive the ruler
   - why rulers of different kinds come back differently
   - why transformations lock in
2. **The source(s) of power.**
3. **Six factions in total.** Keep the **Aurel Crown** and the **Thornmane Clans** (you may deepen or re-flavour them) and add **4 new** ones. For each faction give:
   - **identity and fantasy:** who they are and what playing them feels like
   - **playstyle asymmetry in this engine:** which levers (§7) it pulls, and **what that does to your decisions on a turn**. It has to play differently, not just look different.
   - **2 ruler concepts:** kind (mortal line, undying, god, or something new), battle rank, and a province-ability idea
   - **a roster seed:** 3 units and 1 commander, **one trait each** (a one-sentence effect). Rough stats are welcome and optional.
   - **2 ascension or transformation branches:** what the people become, and how roster, economy and look change
   - **visual identity for stylized 3D models from a strategy camera** (§0):
     - silhouette and massing at distance
     - signature materials and palette (distinct from the other five, reading small and bright)
     - banner and emblem colours
     - **fortress and capital architecture**, and **muster grounds**
   - **a naming language guide:** sounds, word-building, and sample names for people, places and units
4. **Rivalries,** and why simultaneous turns turn them into drama.
5. **Ascension sites** (the victory provinces) in the world: what they are, why rulers want them, and how they look on the map.
6. **Magic school seeds.**
7. **Tone:** dark but not grim, colourful, characterful, original. **No IP lookalikes:** no thinly veiled elves, dwarves, orcs, Warhammer or Dominions nations, or recognisable characters, factions or settings from other games, films or books. Flag any risk you see in your own pitch.

---

## 9. Format for R1

- **One markdown file,** `design/lore/writers-room/R1-<seat>.md`, of **2,000–3,500 words.**
- Cover §8 parts 1–7 in order. Give the six factions equal care, and say what each one's asymmetry does to a player's turn.
- **Numbers are sketches.** Design owns balance. Use the engine's terms (hp, attack, defense, morale, cost, rounds, ranks, gold, provinces).
- **Plain language.** Put an invented term in **bold** the first time and define it in one line (it will need a codex entry).
- Don't edit any other file. R2 (critique and revise) and R3 (synthesis and vote) build on these files. See `README.md` in this folder.
