# Spell icons (ART-M5-2D, #224)

One painted icon per spell, ritual and blood mandate of the magic (`data/magic.gd` SPELLS, plus Tithe of Blood): 14 keys. They
are for the research panel's Magic tab (beside each spell's name), the battle spellbook and the codex. The Magic tab has no
per-spell icon today, so wiring them in is part of this ticket's last step, once Alex has picked the look.

## The files
- `<spell id>.png`, 256x256, square and full bleed: one bold symbol on a deep ground in its school's colour (the schools'
  colours are `world3d/spell_plan.gd`'s). No frame, no text, the same for every faction.
- They show at about 20 to 40 px, beside the UX-0a stroke icons (`assets/ui/icons/`), which is the size they are judged at.

## How they are made (base first)
1. **Base:** 3 icons (Sunlance, Briar Snare, Blood Moon) in three styles (**emblem**, the style bible's spell icon; **cel**;
   **painted**), with the 2 base portraits (Adepts, Thornwolves), in the Review Table batch `review/m5_2d/` (local).
2. **The rest** in the look Alex picks. He keeps or rejects each in the Review Table.
3. **Install accepted** copies the kept icons here and the portraits to `assets/portraits/<faction>/<unit id>.webp`
   (`Art.portrait` reads them with no code change), then the icons are wired in with shots at 1280x720 and 1600x900.

## The 14 subjects (a draft for the full round)
| key | school | subject |
|---|---|---|
| `sunlance` | Sun | a spear of blazing sunlight driving diagonally down |
| `dawn_blessing` | Sun | a rising sun behind a raised open hand |
| `sunburst` | Sun | a sun bursting into blinding rays |
| `shield_of_law` | Law | a tall shield ringed with blue light |
| `sanctum_ward` | Law | a dome of blue light over a small tower |
| `bastion` | Law | a stone fort rising out of the ground in blue light |
| `briar_snare` | Wild | a loop of thorny briar snapping tight around a sword's blade |
| `call_the_pack` | Wild | a howling wolf's head wreathed in briar |
| `wake_the_greenwrath` | Wild | a stag skull crowned with thorns and leaves |
| `bloodbolt` | Blood | a streak of blood flying like an arrow |
| `bloodrot` | Blood | a crimson drop turning black and cracked |
| `blood_moon` | Blood | a full crimson moon with drops of blood falling from it |
| `far_sight` | common | a glowing eye in a ring of pale light |
| `tithe_of_blood` | Blood (a mandate) | a gold coin with blood dripping onto it |
