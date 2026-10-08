# 3D concept pictures (pipeline inputs)

The picked pictures every model in `assets/models/` was made from (batch `asc-3d-factions`,
`tools/ludo/asc_3d_factions.py`). They are inputs, like `assets/_anchors/`: kept so a model can be
re-rolled or a pose edited later without Ludo URLs (which die after 7 days). Godot ignores the folder
(`.gdignore`); candidates stay in the gitignored `candidates/`.

- `<faction>/<unit>_<pose>.webp`: a unit's or ruler's picture per pose. The `ready` picture is an edit
  of the unit's concept art (`assets/concept/units/`) or a style transfer from the ruler's portrait;
  `march`, `strike`, `fallen` (and the rulers' `cheer`) are edits of the `ready` picture.
- `<faction>/<unit>__<transformation id>_<pose>.webp` (batch `asc-3d-paths`): a transformation's look of
  the unit it changes, each an edit of that unit's picked pose picture with the bible §5 block;
  `<faction>/<new unit>_<pose>.webp`: the transformations' new units, the `ready` picture styled from the
  fork's variant picture, cut out and laid on plain grey (their soft shadows fused into floor slabs).
- `<faction>/standard_bearer_<faction>.webp`, `<faction>/musician_<faction>.webp`: army extras,
  edits of a picked unit picture of the same faction.
- `independents/<unit>_<pose>.webp` (batch `asc-3d-free-holds`, `tools/ludo/asc_3d_free_holds.py`): the Free Holds'
  four units, each `ready` picture styled from a greyscale anchor (a Crown spearman for the Free Spears, a Clans
  fangthrower for the Wildkin; the Hill Slingers and the Hold Captain from the Free Spears pick, a same-faction anchor)
  and the poses edited from it; `independents/<unit>_portrait.webp` the finished 384x512 portraits, before the owner
  judges them (the shipped copy goes to `assets/portraits/independents/` only when the install action runs).
- `<faction>/fortress_<faction>.webp`, `fort_<faction>.webp`, `camp_<faction>.webp`; `world/`:
  villages (`_a`, `_b`), the mill, the watchtower and the scenery (trees, rocks, standing stones).

webp q90, at most 1024 px. A soft ground shadow under the feet was painted out of the figure picks
before modelling (it would come back as a fused base).
