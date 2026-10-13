# Notice medallions (UX-ART, #222)

One painted round image per announcement type of the Chronicle (`design/UX_WAR_TABLE.md` §5.2): 32 image keys, the list in
`ChronicleModel.IMAGES` (UX-6, #218). `NoticeArt` loads `assets/ui/notices/<key>.png`, falls back to `<kind>.png`, then to the
placeholder (the kind's icon on a coloured disc), so a file landing here needs no code change.

## The files
- `<key>.png`, 512x512 RGBA, already cut to the disc (the game cuts it again at load). The painting runs on under the
  transparent corners, so the game's resize leaves no dark fringe at the rim.
- Shown at 52 px in the stack (46 when compact), 44 px on a card; at 1280x720 (a 0.8 scale) that is about 42 px on screen,
  which is the size they are judged at.
- The game draws the ring, the unread gilt, a + or - badge on the lower right and a pin on the upper right. The art keeps that
  rim clear, never paints the outcome in, has no text, and is the same for every faction (faction flavour is parked, §10).

## How they are made (base first)
1. **Style samples (done):** four keys in five styles from the art seats, judged in the Review Table batch `review/ux_art/`
   (local, gitignored), each drawn by the game's own `NoticeMedallion` at 1280x720. **Alex 10-13: d, the bright cel look** (the
   subject large in front of a bright sky with one low hill), as the base that each faction's set is made from.
2. **The standard set (the base round):** all 32 in d, into the same batch. Alex keeps or rejects each one. In every set,
   needs-you gets a pale parchment ground in place of the shared sky, so it still jumps out of the stack.
3. **The faction sets**, derived from the standard set once it is kept: the same subjects with each faction's sky and
   materials (the Crown's blue sky, sun pommels and white stone; the Clans' ochre and crimson dusk, bone, briar and red paint;
   the Candlewake's violet dusk, ivory wax and lilac flame, once the faction is in the game). They go in
   `assets/ui/notices/<faction id>/<key>.png`, and `NoticeArt` shows the viewer's own set (`NoticeArt.viewer`).
4. **Install accepted** (`python3 tools/review/review.py apply ux_art`) copies every kept take here.

## The 32 subjects (Alex 10-13: fine)
| key | kind | subject |
|---|---|---|
| `needs_you` | Needs you | a single bronze bell swung mid-ring |
| `battle_won` | Battles | two crossed swords raised point-up in a laurel wreath |
| `battle_lost` | Battles | a broken sword lying across a split, dented shield |
| `army_lost` | Battles | a fallen standard with a snapped pole, an empty helmet beside it |
| `siege_begun` | Battles | a roofed battering ram at a closed fortress gate |
| `walls_breached` | Battles | a stone wall with a jagged gap smashed through it, blocks tumbling |
| `siege_ended` | Battles | a siege ladder lying abandoned in the grass before a wall that still stands |
| `order_void` | Battles | an arrow stuck in the ground well short of a tall wall |
| `province_taken` | Land | a plain cream banner planted upright on a green hilltop, flying |
| `province_lost` | Land | a hill-fort tower whose flagpole has snapped, the torn banner falling, smoke rising |
| `province_seen` | Seen abroad | a banner being raised on a far hilltop, small and hazy |
| `fealty_to_you` | Land | a kneeling figure offering a sword hilt-first toward the viewer |
| `fealty_to_rival` | Seen abroad | a kneeling figure far off, offering a sword toward a distant banner |
| `fealty_contested` | Land | two hands from opposite sides reaching for one sword |
| `fort_built` | Land | a finished stone tower, a wooden crane and scaffolding still beside it |
| `fort_works` | Land | a mason's hammer and chisel on a half-cut stone block |
| `terrain_changed` | Land | a single tree, one half green, the other half turned to another land |
| `raided` | Land | a tipped strongbox spilling gold coins, a torch lying beside it |
| `ruler_fallen` | Rulers | a crown lying tipped on the ground beside a dropped sceptre |
| `ruler_returned` | Rulers | a crown set back on an empty throne in morning light |
| `sacrifice` | Rulers | a crown laid on a stone altar, a flame rising from it |
| `healing` | Rulers | a rolled bandage and a sprig of herbs under a soft warm glow |
| `spell_learned` | Magic | an open palm with a bright spark of magic floating above it |
| `ritual_cast` | Magic | a ring of small standing stones, a column of light rising from the centre |
| `research_done` | Realm | an open book with a beam of light rising from its pages |
| `recruits_raised` | Realm | three spears standing together, a new round shield leaning on them |
| `treasury` | Realm | a stack of gold coins beside a small open chest |
| `transformed` | Realm | a figure in a column of light, its outline changing as sparks rise |
| `oath_sworn` | Realm | a raised open hand above a sword laid flat on an altar |
| `muster` | Realm | two war banners whose poles cross, tied together with a cord |
| `army_seen` | Seen abroad | a line of spear tips cresting a far ridge |
| `sighting` | Seen abroad | a brass spyglass pointed at a far horizon |
