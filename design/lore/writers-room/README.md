# The lore writers' room

A planned three-lab room to set the **starting ground for ASCENDANT's lore**: the world, what ascension is, the six factions, the ascension sites, magic seeds and tone. Every race, unit and ascension grows from it. Whatever the room proposes goes to Alex. Nothing in here is approved until he signs it off.

## Seats

| seat | status |
|---|---|
| Claude | **R2 in** (`R1-claude.md`, `R2-claude-critique.md`, `R2-claude.md`; bake-off entry `../bakeoff/claude_batch.json`) |
| Codex | **R2 in** (`R1-codex.md`, `R2-codex-critique.md`, `R2-codex.md`) |
| Grok | **R2 in** (`R1-grok.md` and the uncapped `R1-grok-full.md`, `R2-grok-critique.md`, `R2-grok.md`) |

R2 ran on 2026-10-05. Each seat read the packet, its own R1 and the other two R1 pitches, then wrote a critique and a revised pitch. The revised pitches run past the 3,500-word cap (Codex 4,299, Grok 4,621), in the spirit of Alex's "don't limit ourselves unnecessarily". R3, the synthesis and the red-team vote, is next.

Codex and Grok are external services. Alex allowed them on 2026-10-04 (the `codex exec` / `grok --prompt-file` rule in the main checkout's `.claude/settings.local.json`). The director runs each seat with `PACKET.md` and a short seat brief. That brief adds one new fact, the independents (#142, "the Free Holds"), which each seat may fold into its world.

## Format

1. **R1, the pitch.** Each seat answers the writers' brief in `PACKET.md` §8 on its own, without seeing the other pitches. The output is `R1-<seat>.md`, 2,000–3,500 words. `PACKET.md` holds everything a writer needs: the full game brief, the key parts of the style bible, the two built factions, the rulers, the mandates and the engine constraints. It also carries the 2026-10-04 direction update: a 3D world map and 3D battles, with the UI staying 2D.
2. **R2, cross-critique and revise.** Each seat reads the other pitches and writes `R2-<seat>-critique.md`, covering:
   - what to steal
   - what breaks in this engine
   - what reads alike between factions
   - any IP lookalike risk

   Each seat then revises its own pitch as `R2-<seat>.md`, saying what changed and why.
3. **R3, synthesis and red-team vote.**
   - One synthesis, `R3-synthesis.md`, merges the strongest world premise, the six factions and the sites into one starting ground. It credits which seat each idea came from.
   - Each seat then red-teams the synthesis for engine fit, approachability (can a new player get each faction in two sentences?), tone, and lookalikes of existing games, films and books.
   - Each seat votes keep, change or cut on every faction and every major term. The votes are recorded in `R3-votes.md`.
   - The result goes to Alex as a proposal.
4. **The art bake-off, judged blind.**
   - Each seat writes a Ludo batch for **its two favourite new factions**: a banner, a ruler portrait and 2 unit portraits each, plus one wide world key-art vista showing a fortress with an army mustering.
   - Each batch uses 2 candidates per slot, a limit of **150 credits**, and the style bible's blocks (one verbatim block per asset class).
   - Batches live in `../bakeoff/<seat>_batch.json`. They run only with Alex's go-ahead, through the asset builder, and are ledgered like any batch.
   - Picks go onto one contact sheet with the seat names hidden and the cells shuffled. Alex judges blind, and the seats are revealed after he scores.

## Files

- `PACKET.md`: the shared packet. Every seat reads it, and nobody edits it during a round.
- `R1-claude.md`: Claude's pitch. The world is **Halfmade**, the maker who stopped at noon is **the Wright**, and ascension sites are **Noonmarks**. Its favourites for the bake-off are the Candlewake and the Stormherd.
- `R1-codex.md`: Codex's pitch, **The Oathscar** (3,381 words). Its new factions are the Glasswake Compact, the Ember Orchard, the Interval Court and the Underweather Assembly.
- `R1-grok.md`: Grok's pitch, **The Strung** (3,500 words): a world of strings held between the High Peg and the Low Peg. Its new factions are the Glazewell Choir, the Kite Houses, the Amber Procession and the Open Knot. This capped version is the one R2 critiques.
- `R1-grok-full.md`: the same world uncapped (12,297 words), kept at Alex's request. Read it for depth; R2 works from the capped pitch, so the seats compare like with like.
- `../bakeoff/claude_batch.json`: Claude's bake-off entry, 9 slots, planned only. It estimates 10.0 cr, or 21.0 with a full re-roll reserve and one fallback, under a hard cap of 25.

## Rules for every seat

- Work only in this folder and `../bakeoff/`. Don't edit `design/GAME_BRIEF.md`, `design/STYLE_BIBLE.md`, or anything outside `design/lore/`.
- Never read, print or commit secrets (`.env*`). The room never runs `tools/ludo/ludo.py`. Running a batch is the asset builder's job, and only after Alex approves.
- Every invented term needs a one-line definition, because it will need a codex entry.
- Commit with the `design:` prefix on the `lore-writers-room` branch. The room isn't pushed or opened as a PR until Alex asks.
