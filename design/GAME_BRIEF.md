# ASCENDANT: game brief

Status: **DRAFT v2, awaiting Alex's approval.** Nothing downstream (milestones, tickets, style bible) starts until this is approved. Changes after approval need Alex's OK.

## one line
A deep, simultaneous-turn fantasy strategy game with the spirit of Dominions 6, where your ruler trades personal power for faction-wide strength, your people can transform down locked-in paths, battles are worth watching, and every rule is visible so you never need a wiki.

## who it's for
Players who love the idea of Dominions (strange asymmetric factions, big magic, huge armies, battles decided by preparation) but bounced off its opacity. Fans of Age of Wonders 4's faction building who want harder choices and deeper strategy. And veterans of both who want real decisions without the friction.

## what "the spirit of Dominions" means here
We keep the feel, not the rulebook: wildly asymmetric factions, a build decision before the game that defines your whole strategy, deep magic, simultaneous orders, and battles you win by preparing, not by clicking. We do **not** copy dominion spread, pretender god points, or the scales system. We replace them with our own systems below.

## pillars
1. **Power is a budget you spend on your people.** Your ruler's personal might and your faction's strength come from the same pool. Every point you keep for yourself is a point your nation doesn't get.
2. **Commit and become.** Your faction develops down branching paths that lock in. Big forks change what your people are, not just what they have. No two games of the same faction need to end the same way.
3. **Preparation wins battles, and battles are worth watching.** You choose the army, commanders, formation, and simple orders. The autobattle plays out from that with great sprite animation and spell effects, and the report tells you exactly why you won or lost.
4. **Nothing hidden that matters.** Every number explains itself on hover. Every order and every lock-in shows its outcome before you commit. Randomness is shown as odds and ranges.
5. **Simultaneous turns, readable results.** Everyone orders at once, then everything resolves together in one deterministic pass, and the turn report explains every change as cause and effect.
6. **Polish over breadth.** Fewer factions, units, and spells, each distinct and well explained. UI/UX and battle presentation are features, not a finishing pass.

## core system 1: the ruler and mandates
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

## core system 2: paths of ascension (development trees)
Research is organized into **paths** per faction: military doctrine, society and economy, and magic schools.

- Most nodes are ordinary upgrades you can mix freely.
- At a few points on each path there's a **fork** that locks you in. Taking one branch closes the others for the rest of the game.
- The biggest forks are **transformations** that change what your people are. A human kingdom might ascend into a celestial host, bind itself to living iron, or pay a blood pact and become something darker. A transformation changes unit rosters and their look, the economy's rules, how provinces respond to you, and which mandates become available.
- Every fork shows a full preview first: exactly what you gain, what you lose access to, and what your units will look like.
- Age of Wonders 4 is a reference for faction-wide transformation. We go further by making the choices exclusive and permanent, and by tying them to ruler power.

## core loop (one turn)
1. **Read** the turn report: what happened, why, and what needs you.
2. **Plan** on one map screen: move armies, recruit, research, cast rituals, set battle orders. Each order shows a forecast (arrival turn, cost, research ETA, rough battle odds against what you can see).
3. **Commit** and end turn.
4. **Resolve**: all players' orders run together from a seed in a fixed, documented order (movement, battles, sieges, income, research, events).
5. Watch the battles you care about, skim the rest from their reports, and repeat. You win by holding enough **ascension sites** (victory provinces) or by eliminating rivals.

## what we keep from Dominions 6
- Strongly asymmetric factions with distinct units, magic, and playstyle.
- A defining pre-game build (now the ruler and mandates).
- A province map with terrain, population, income, and supply.
- Magic research, rituals, battle spells, and commanders gated by magic.
- Recruitment: faction units, independents, commanders who lead troops, forts that gate recruitment.
- Simultaneous orders resolved together.
- Battles that play out from your preparation, with formations and simple commander orders.

## what we cut or change
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

## battle presentation
- Autobattles are resolved by pure rules code first, then played back visually from the result. The playback never changes the outcome.
- Sprites are animated (idle, move, attack, hit, death). Spells and big hits get real effects: projectiles, impacts, screen shake, readable area markers.
- Playback controls: speed, pause, skip, and jump to key moments. Hovering a unit shows what it's doing and why.
- Readability beats spectacle: you can always tell who's winning and why. Art lead owns the look through the style bible.

## approachability rules (apply to every ticket)
1. No mechanic ships without in-game explanation in the same PR: a tooltip, a preview, or a forecast.
2. Every order, mandate, and fork previews its outcome before commit.
3. Every number shown can explain itself on hover.
4. Progressive disclosure: the simple view first, the full breakdown one hover or click away.
5. Turn and battle reports read as plain-language cause and effect, linked to the provinces, units, and rules involved.
6. Rules are pure, deterministic code resolved from a seed, so any turn or battle can be replayed and explained.
7. Plain language. No invented term without a codex entry.

## setting and tone (my recommendation)
An original high-fantasy world where rival rulers race to ascend, whether that means godhood, empire, or something stranger (hence the title). Dark but not grim, colorful and characterful. Our own factions, names, and lore. Art direction is owned by art lead once this is approved.

## scope defaults (my recommendation)
- **Platform:** desktop (Windows/Mac/Linux), mouse and keyboard.
- **Players:** single player against AI rivals first. Hotseat comes early because turns are simultaneous and deterministic. Online play is a later goal the architecture must not block.
- **Battles:** rules and a readable written report first, then animated playback. Playback quality is a pillar, not a nice-to-have.
- **Content target for a 1.0:** 4 to 6 factions, each with several ruler options, a curated mandate list, and 2 to 3 transformation forks. Maps for 2 to 6 players.

## non-goals (for now)
- Real-time anything, or direct battle micromanagement.
- Online multiplayer, matchmaking, or accounts (the door stays open).
- Mod support or scripting tools.
- A story campaign.
- Matching Dominions' content volume.
- 3D. The game is 2D, with a clean, readable map and animated sprites.

## how we'll know it's working
- A new player finishes a first game without leaving the game to look something up.
- After any lost battle, the player can say why they lost from the report alone.
- Players argue about ruler builds: keep power or spend it, and on what.
- Two games with the same faction feel different because of the forks taken.
- People watch battles because they want to, not because they have to.
