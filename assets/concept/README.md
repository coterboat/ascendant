# Concept art (2D, Bright Cel)

Made by batch `asc-mvp-batch` (2026-10-04) as reference for the coming 3D models. Each image is a Ludo still, picked from 3 candidates; prompts, request ids and picks are in `tools/ludo/batches/asc-mvp-batch.json`, per-call costs in `studio/ledgers/asc-mvp-batch.jsonl`, the contact sheet is `studio/contact-sheets/asc-mvp-concept.png`.

Not wired into the game, except the codex plates (below). Nothing here is a final model; it is the source image the 3D job feeds to Ludo `model3d` (image to GLB), and art for the codex and lore pages.

## Fortresses (`fortresses/`)
1024×1024 webp with real alpha (removeBackground, `creative_edit: false`), structure centred with about 6% margin. One whole structure in a high three-quarter view, on its own patch of ground.

| file | what it is | intended 3D use |
|---|---|---|
| `crownkeep.webp` | Crownkeep, the Aurel Crown capital: pale stone curtain wall, blue conical tower roofs, a square keep with the golden sun ornament and the sunstone window, crown banners, gate facing the viewer | `model3d` source for the Crown capital/fortress on the 3D map (where armies muster) |
| `fangridge.webp` | Fangridge, the Thornmane Clans stronghold: a rocky ridge crowned with a palisade of logs and giant bone tusks, thatched longhouses, beast-skull banners, a tusk-framed door | `model3d` source for the Clans capital/fortress |

## Units and commanders (`units/`)
webp with real alpha, up to 1024×1024 (the bear is 932²), figure centred with about 6% margin. Full figure, front three-quarter view, neutral standing pose (four legs down for the bear), flat even lighting so the texture carries little baked shading. Each one was styled from that unit's own shipped portrait (`assets/portraits/<faction>/<unit>.webp`), so the costume, palette and face match the 2D series.

Scale cues for the 3D job (the images are each framed to their own height, so scale comes from this table, not the pixels):

| file | unit | class | intended height | intended 3D use |
|---|---|---|---|---|
| `spearmen.webp` | Aurel Crown spearmen | infantry | 1.8 m (spear tip 2.6 m) | `model3d` source; spear upright, round shield on the left arm |
| `crossbowmen.webp` | Aurel Crown crossbowmen | ranged | 1.7 m | `model3d` source; crossbow held across the body, quiver at the hip |
| `knights.webp` | Aurel Crown knights | mounted | 2.6 m to the helm (horse 1.6 m at the shoulder) | `model3d` source; rider and horse as one model, lance upright |
| `knight_captain.webp` | Aurel Crown knight-captain | commander | 1.85 m | `model3d` source; sword point-down, blue cloak |
| `tuskers.webp` | Thornmane tuskers | heavy infantry | 2.2 m | `model3d` source; stone club resting on the ground |
| `fangthrowers.webp` | Thornmane fangthrowers | ranged | 1.9 m | `model3d` source; javelin upright, bundle on the back |
| `war_bear.webp` | Thornmane war bear | monster/beast | 1.7 m at the shoulder, about 3 m long | `model3d` source; quadruped, bone shoulder plates, moss |
| `warchief.webp` | Thornmane warchief | commander | 2.3 m (staff tip 2.7 m) | `model3d` source; horned-skull totem staff upright |

The four rulers have portraits only (`assets/portraits/rulers/`); their full-body concepts were not asked for in this batch.

## Codex plates (`codex/`)
768×768 webp (opaque), a small landscape vignette that fades into a pale parchment border. For the in-game codex terrain entries and lore pages; not a 3D source.

**In the game (#272):** each plate is named for the codex page it illustrates, `<RulesCodex key>.webp` (`terrain_forest.webp` for the Forest page), and that page shows it at the top, on a band of its own parchment as wide as the page (`Art.codex_plate`, `ui/codex_panel.gd`). A new plate named that way shows with no code change; `tests/test_codex_panel.gd` fails on a plate whose name is no codex page, since no page would ever show it. Import plates with mipmaps on: the page draws them at about a third of their size.

| file | codex page | what it shows |
|---|---|---|
| `terrain_plains.webp` | Plains | open grassland, dirt road and fence, a lone oak |
| `terrain_forest.webp` | Forest | bold round canopies over a sunlit path, mossy rocks and ferns |
| `terrain_hills.webp` | Hills | ochre rolling hills, rock outcrops, a watchtower on the far crest |

The three were `plains.webp`, `forest.webp` and `hills.webp` until #272 named them for their pages; `tools/ludo/batches/asc-mvp-batch.json` keeps the names the batch wrote.
