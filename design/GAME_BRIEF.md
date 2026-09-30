# ASCENDANT: game brief

Status: **DRAFT, awaiting Alex's approval.** Nothing downstream (milestones, tickets, style bible) starts until this is approved. Changes after approval need Alex's OK.

## one line
A deep, simultaneous-turn god-war strategy game in the spirit of Dominions 6, where every rule is visible, every order shows its likely outcome before you commit, and you never need a wiki to play well.

## who it's for
Players who love the idea of Dominions (pretender gods, strange nations, magic, big armies, battles decided by preparation) but bounced off its opacity. And Dominions veterans who want the same depth with less friction.

## pillars
1. **Deep, not obscure.** Depth comes from a few systems that interlock (territory, economy, dominion, magic, armies), not from a pile of hidden special cases. If a rule exists, the game can show it to you.
2. **Nothing hidden that matters.** Every number on screen can be hovered to see where it comes from. Randomness is shown as odds and ranges, never as surprise.
3. **Preparation wins battles.** You don't micro battles. You choose the army, the commander, the formation, and a few simple orders; the battle plays out from that, and the report tells you exactly why you won or lost.
4. **Simultaneous turns, readable results.** Everyone orders at once, then everything resolves together in one deterministic pass. The turn report explains every change as cause and effect.
5. **Polish over breadth.** Fewer nations, units, and spells, each distinct and well explained, over a huge roster of near-duplicates. UI/UX is a feature, not a finishing pass.

## core loop (one turn)
1. **Read** the turn report: what happened, why, and what needs attention.
2. **Plan** on one map screen: move armies, recruit, set research, cast rituals, set battle orders. Each order shows a forecast (arrival turn, cost, research ETA, rough battle odds against what you can see).
3. **Commit** and end turn.
4. **Resolve**: all players' orders run together from a seed in a fixed, documented order (e.g. movement, then battles, then sieges, then income, then research, then events).
5. Repeat. A game is won by holding enough victory provinces (thrones) or eliminating rivals.

## what we keep from Dominions 6
- **Pretender god creation**: pick a chassis, magic paths, dominion strength, and a small set of scales. This is your build and your identity.
- **Nations** with strongly distinct units, magic, and playstyle.
- **Province map** with terrain, population, income, and supply.
- **Dominion**: your god's faith spreads across provinces and changes the land (scales like order/turmoil, growth/death). Shown as a map overlay with clear effects.
- **Magic research and paths**: research schools, gem income, rituals, battle spells, commanders gated by magic paths.
- **Recruitment and armies**: national units, independent units, commanders who lead troops, forts that gate recruitment.
- **Simultaneous orders** resolved together.
- **Battles that play out from your preparation**, with formations and simple commander scripts.

## what we cut or fix
- **Hidden rules and stats.** No mechanic the player can't inspect in-game.
- **Opaque numbers.** Every derived value has a breakdown tooltip (base, modifiers, total).
- **Screen sprawl.** One main map screen with panels, not a dozen modal screens. Common actions within two clicks.
- **Unexplained outcomes.** Battle reports and turn reports explain causes, not just results.
- **Guide-only knowledge.** A linked in-game codex: every term in a tooltip links to its entry.
- **Roster bloat.** Curated unit and spell lists; every entry must have a distinct job.
- **Busywork.** Gem transfers, repetitive recruitment, and army bookkeeping get sensible defaults and repeat-last-turn options.
- **Ambiguous resolution order.** The order in which things resolve is fixed, documented, and visible.

## approachability rules (apply to every ticket)
1. No mechanic ships without in-game explanation in the same PR: a tooltip, a preview, or a forecast.
2. Every order previews its outcome before commit.
3. Every number shown can explain itself on hover.
4. Progressive disclosure: the simple view first, the full breakdown one hover or click away.
5. Turn and battle reports read as plain-language cause and effect, with links to the provinces, units, and rules involved.
6. Rules are pure, deterministic code resolved from a seed, so any turn can be replayed and explained.
7. Language is plain. No invented jargon without a codex entry.

## setting and tone (my recommendation)
An original mythic world where rival pretenders fight to ascend to godhood (hence the title). Dark but not grim, readable and characterful rather than gritty. Not a Dominions reskin: our own nations, names, and lore. Art direction is owned by art lead once this is approved.

## scope defaults (my recommendation)
- **Platform:** desktop (Windows/Mac/Linux), mouse and keyboard.
- **Players:** single player against AI rivals first. Hotseat multiplayer is cheap because turns are simultaneous and deterministic, so it comes early. Online play is a later goal the architecture must not block.
- **Battles:** resolved in rules code first with a clear written report; a visual battle playback comes after the rules are solid.
- **Content target for a 1.0:** 4 to 6 nations, a curated set of magic paths and spells, maps for 2 to 6 players.

## non-goals (for now)
- Real-time anything, or direct battle micromanagement.
- Online multiplayer, matchmaking, or accounts (the design keeps the door open).
- Mod support or scripting tools.
- A story campaign.
- Matching Dominions' content volume.
- 3D. The game is 2D with a clean, readable map.

## how we'll know it's working
- A new player can finish a first game without leaving the game to look something up.
- After any lost battle, the player can say why they lost from the report alone.
- A veteran still finds real decisions in pretender design, dominion, and magic.
