# ASCENDANT: the War Table, a UI/UX spec

Status: **DRAFT r1 by the director (Claude session, 2026-10-10), for Alex's sign-off.**
- **Direction:** Alex picked it on 10-10 from the UI directions canvas: **A's War Table, with C's Chronicle and D's lenses.** "I love having all of the data available for the nerds who want to see it visually while keeping them entirely optional for the player who just wants to do war stuff."
- **Why now:** the MVP walk's biggest complaint, by far, is the UI.
- **The look waits for Alex's art-direction notes (10-10).** This spec fixes the structure (what is where, what it shows, how it opens and closes). The look of plaques, cards, seal, fonts and icons (§7) follows his notes; until then builders use the current theme.

Built on:
- **The canvas:** https://claude.ai/artifact/QXN1JqEFBKAyduRoRj4WdA (private to Alex). It holds the audit of today's screens, the shared fixes, the four directions, their after-the-turn boards and the battle viewer.
- **Specs:** `design/GAME_BRIEF.md` (the approachability rules), `design/STYLE_BIBLE.md` (UI, icons, type sizes), `design/M5_MAGIC_FOG.md` (fog's view state, sight levels, what is public), `design/M3_BATTLES.md` (the battle viewer, the why panel).
- **The engine on `main` at 83cf829:** `ui/`, `world3d/`, `rules/turn_report_text.gd`, `rules/battle_moments.gd`, and the tests that pin layout and text (§9).

**Alex: read §11 (director's calls) and §12 (your questions) first.**

## goal
**The board is the game.** Everything else is either a piece on the table or a page in the chronicle.

A new player sees the map, a few plaques, an army card when they click an army, and their orders in plain words. They never meet a number they didn't ask for.

A veteran presses 1 to 6 and gets every number on the map, each lens with its own colour and feel. They press it again and the art comes back.

The milestone proves three things:
- **The board can carry the whole game** without a top bar or a side panel, at 1600×900, 1280×720 and 125%.
- **A turn reads like a story.** Your orders read as sentences before you end the turn. What happened arrives as announcements you can sort, show, hide, pin and dismiss, like the old Total War's start-of-turn notices.
- **Depth is opt-in.** Every number the game has is one key away, and none of it is in the way.

## the short version
- **The Table (A).** The board fills the window. On top of it sit:
  - a **realm plaque** (top left) and an **opponent plaque** with **Menu** (top right);
  - a **rail** down the left edge: Research, Magic, Ruler, Chronicle, Lenses, Codex. Each opens its panel as a drawer over the board;
  - a **selection card** beside whatever you clicked (an army or a province), with its actions;
  - your **orders**, drawn on the board as numbered marks and listed in a **tray** along the bottom;
  - the **End turn seal**.
- **The Chronicle (C)**, a column on the right that you open and close:
  - **Read** (the start of a turn): what happened, as announcements by kind. Sort them, show or hide whole kinds, pin, dismiss, click to see one on the map, watch a battle, ask why.
  - **Plan** (the end of a turn): your orders as sentences with their forecasts, and the seal.
- **The Lenses (D):** six optional map views: **Owner, Income, Forts, Threat, Magic, Sight.** They are off by default and one is on at a time. Each has its own overlay, palette and feel, plus a legend.
- **Sight speaks for itself.** The veil on the land says what you can see. No "glimpsed" or "never seen" on the map; the words stay in tooltips and the codex.
- **What goes away:**
  - the top bar and the hint row;
  - the side panel's long scroll;
  - the modal turn report (it becomes the Chronicle's Read; "Full report" still opens today's panel);
  - sight words on the plates;
  - the Vision map mode;
  - the battle viewer's row of thirteen buttons.
- **What stays:**
  - every explanation (breakdown tooltips, the ?, codex links);
  - every forecast;
  - every order flow (only their entry points move);
  - the 2D map setting;
  - hotseat.
- **No rules change.** Game records, digests and fixtures stay byte-identical.
- **10 tickets,** UX-0 to UX-9 (§9).

---

## 1. the Table (UX-1)

### 1.1 the layout
Today `MapScreen.Layout` is a VBox: `TopBar` over `Body`, and `Body` is `MapView` beside the 400 px `SidePanel` (`ui/map_screen.tscn`).
- **The new layout:** `MapView` fills the screen. A new **`TableHud`** (a full-rect Control over `MapView`, under the `Overlays` layer) holds the plaques, rail, tray and seal.
- **The board keeps its input.** Clicks that land on the board and not on a HUD piece go to the board as today.
- **`TopBar`, `HintRow` and `SidePanel` are removed.**
  - `add_top_bar_control` (`game_screen.gd:1134`) gives way to `TableHud.add_rail_button` / `add_plaque_item`.
  - `ResearchHud` puts its chips on the rail.
  - `_hang_under_top_bar` hangs the guide and the notice under the realm plaque instead.

### 1.2 the pieces
| piece | where | shows | opens |
|---|---|---|---|
| **realm plaque** | top left | banner, faction name, gold with income (breakdown tooltip as today), turn, the ruler and kept power (with rulers) | the Ruler drawer on the ruler line |
| **opponent plaque** | top right | each rival: banner, name, Computer and its level or Player, "last seen turn N" under fog | its codex entry |
| **Menu** | top right, beside the opponent plaque | — | today's menu |
| **rail** | left edge, vertical | Research (progress badge), Magic (spells and mages), Ruler, Chronicle (unread badge), Lenses (the active one), Codex | each its panel as a drawer from the left (today's panels, re-homed; `PanelFit` kept) |
| **selection card** | beside the selection (§3) | army or province | its actions |
| **tray** | bottom centre | your orders as numbered tokens, gold after orders (§3.4) | an order's card |
| **End turn seal** | bottom right of the tray | the order count | today's end-turn flow; the Plan review if on (§5.3) |
| **controls** | rail, the last button "?" | every key and mouse binding (today's hint text, in full) | — |

- **At the end of a game,** "Results" takes the seal's place.
- **Hotseat** is unchanged: the handoff screen covers the table.

### 1.3 fitting
- **Every piece fits at 1600×900, 1280×720 and 125%.** Settings' 125% lays the screen out at 1280×720 (`settings_store.gd:183`).
- **At 1280 wide:**
  - rail labels hide (icon only, tooltip kept);
  - tray tokens show the number and an icon, with the text in the tooltip;
  - the opponent plaque drops the "last seen" line to its tooltip.
- **Nothing a click needs ever hides.** End turn, Menu and the selection card's first action are always on screen.

### 1.4 the 2D map
The Table works over the 2D map the same way (`MapCanvas` behind the HUD). Labels and lenses on 2D are best effort (§4.0).

## 2. labels and sight (UX-2)

### 2.1 the label diet
Today each province plate (`board_overlay.gd`, `_build_province_plates`) stacks:
- a glyph and the name;
- "N gold";
- the fort chip with walls bars;
- enchantment badges;
- the sight text;
- a countdown badge.

The rule: **state that changes or warns is always visible; static facts appear on hover.**

| part | always | on hover or select |
|---|---|---|
| name, owner dot, capital crown | ✓ | |
| cut-off mark (besieged income) | ✓ | |
| countdown badge (capture wait, works) | ✓ | |
| besieged mark | ✓ | |
| gold | | ✓ (icon + number) |
| garrison | | ✓ (shield + count) |
| walls | | ✓ (pips; the fort chip's bar) |
| enchantments | | ✓ (and always under the Magic lens) |
| sight words | — removed (§2.2) | |

- **Army plates** (`_build_army_plates`) don't change. The count, "Ruler", and fog's "≈20 · 3 turns ago" are all state.
- **A lens** swaps the hover numbers for its own value and shows it always (§4).

### 2.2 sight is self-evident
The veil is already in the shader: `vision_tex` holds 0 never seen, 85 remembered, 170 glimpsed and 255 clear (`world3d/shaders/ground_common.gdshaderinc`), and MVP-3 veils props by level. Sight becomes **only** the veil, tuned so each level reads at full-map zoom without a word:

| level | the land | armies |
|---|---|---|
| **clear** (In clear sight) | full colour, no veil | models as they are |
| **glimpsed** | a thin drifting mist; colours muted a step | rough silhouettes, "≈N" |
| **remembered** (Out of sight) | a heavier veil, desaturated toward sepia | faded ghosts where last seen; hover says the turn |
| **never seen** | deep, dark veil; terrain shape only | none |

- **No words.** `SightLabel` and `Vision.tag_for` leave the plates.
  - The hover tooltip keeps `Vision.words`.
  - The codex keeps `FogView.LEVEL_CODEX`.
  - The first-game guide's Fog of war line keeps its tooltip.
- **The Vision map mode is retired.** That is the 2D swap behind the `VisionButton` (`map_screen.gd:215-234`, 643-712). Its legend and its "why do I see this" job move to the Sight lens (§4.6).
- **Acceptance:** at 1600×900, full-map zoom, a director's screenshot shows four distinct levels to someone who has never read the codex. Before and after shots go in the PR.

## 3. selection cards and orders (UX-3, UX-4)

### 3.1 the army card (UX-3)
Click an army (yours or one you can see). A card opens **beside its plate**:
- the header: name, where, commander;
- a **row of portraits** (`UnitPortraits`) with hp bars, the ruler gilt-ringed;
- strength (breakdown tooltip as today) and sight range;
- **actions:**
  - March (M);
  - Recruit here, at your fort;
  - Fortify;
  - Siege or Storm, at an enemy fort;
  - cast a ritual, when a caster stands in it;
  - Cancel its order.
- **Each action calls the existing `OrdersController` flow.** Only the button moved.
- **A rival's army** shows what fog allows (`FogView`), and no actions.

### 3.2 the province card (UX-3)
Click land:
- name, owner, terrain;
- income (breakdown tooltip);
- the fort (`FortChip`, walls, recruit cap and recruits ordered);
- armies here, each a button that selects it;
- enchantments;
- **Recruit:** the section the side panel has today (the capital list, the fort recruit section at `map_screen.gd:1401` and the ruler recruit section at 1318), moved into a **Recruit drawer** opened from the card.

### 3.3 placement
- The card sits beside the selection's screen point and flips sides to stay on screen.
- It never covers its own selection or the province the mouse is hovering as a move target.
- When the selection is off-screen, the card docks bottom left.
- Esc or clicking empty land closes it.
- At 1280×720 the portrait row wraps to two lines before the card grows past 360 px.

### 3.4 orders on the board, and the tray (UX-4)
- **Numbers:** an order's number is its position in `OrdersController.orders()`, plus one. There are no new order ids.
  - The numbers re-flow when an order is cancelled, or moved by `change_via` (which sends it to the end). The tray says so in its tooltip.
- **Marks on the board** (`board_overlay.gd`):

| order | mark |
|---|---|
| march | today's path (`_draw_move`) with a number token at its middle |
| recruit | a token at the fort: number and "+N unit" |
| fortify | a token at the fort with the walls icon |
| siege, storm | a token at the fort with the siege icon |
| ritual | a token at its target province |
| research, spellbook, mandate, other realm orders | tray only (they have no place) |

  - The existing ghost plate "+2 queued · 5 gold left" (`GhostPlate_*`) becomes the recruit token.
  - The existing march mark (`_MarchMark`) on an army plate stays.
- **The tray:**
  - one token per order, in order;
  - hover shows `order_text(i)` and `order_breakdown(i)`;
  - clicking a token focuses its place and opens its card with Change and Cancel;
  - ×, or right-click, cancels;
  - the tray ends with **gold after orders** (`gold_after_recruits`);
  - past seven tokens it scrolls sideways.
- **The seal:** "End turn" and the order count. It runs today's end-turn flow and warnings, unchanged.

## 4. the lenses (UX-7)

### 4.0 the frame
- **`MapLens`** (new, `ui/map_lens.gd`) is pure and testable. From `(state, fog view, viewer)` it gives, per province:
  - a tint colour and strength;
  - a ring or hatch mark;
  - the label value;
  - a breakdown for the tooltip.

  It also gives one legend.
- **The 3D board:**
  - a `lens_tex` (16×1 RGBA, like `owner_tex`) and a `lens_mode` uniform in `ground_common.gdshaderinc`;
  - blend modes: **wash** (replace the owner wash), **glow** (emissive by strength), **hatch** (diagonal ink by strength) and **ring** (an outline at the province edge);
  - `WorldView.set_lens(mode, colours)`, beside `set_owners`.
- **The 2D map:** `ProvinceRegion` colours, best effort. 3D ships first.
- **Plates:** the hover number becomes the lens value and shows always.
- **A legend card** (bottom left): the lens's question, its scale and the totals.
- **Turning lenses on and off:**
  - keys 1–6 turn a lens on; the same key, Esc or ` turns it off;
  - the rail's Lenses button opens a picker for the mouse;
  - one lens at a time;
  - every session starts with lenses off, so a new player never meets one unasked.
- **Accessibility:** a lens's scale runs in lightness as well as hue (light to dark), never hue alone.
- **Fog:** a lens shows only what `FogView` lets the viewer know. Where a value is remembered, not current, the label says "as of turn N".

### 4.1–4.6 the six lenses
| # | lens | its question | overlay and palette | the feel | label value | fog |
|---|---|---|---|---|---|---|
| 1 | **Owner** | Who holds what? | **wash**: seat colours at full strength over muted terrain; thick borders; capitals crowned; neutral slate | a heraldic political map | owner's name | owners are public (M5 §2.2) |
| 2 | **Income** | What is it worth? | **glow**: dark umber (poor) to bright gilt (rich) | a treasury, warm metal | gold a turn, as a coin badge; totals in the legend (on the map, yours, each rival's) | base income is public; modifiers (cut off, enchantments) only where clear |
| 3 | **Forts** | Where can armies be raised and held? | **wash**: cool slate stone; a ring per fort with its level glyph and walls pips; besieged forts a red cracked ring; works dotted | masonry, cold grey-blue | level, walls n/max, recruit cap | level public; walls, siege and works where seen, "as of turn N" |
| 4 | **Threat** | What can hit me next turn? | **hatch**: red ink, denser for more enemy strength that can reach the province next turn; your own reach as a soft outline in your colour; provinces both can reach pulse amber | a war-room map, red pencil | enemy strength in reach ("≈" under fog) | only armies you see or remember, as of their turn; no knowledge is grey hatching with "?" |
| 5 | **Magic** | Where is magic at work? | **glow**: ink-violet sigils per enchantment (blessing, curse, ward, Bastion), ritual reach, Far Sight's cone | arcane, candle-dark | the enchantments | only what `FogView` shows today |
| 6 | **Sight** | Why do I see what I see? | **ring**: warm lantern cones from each sight source (army, commander, fort, scout) with its radius; a dashed line for what your queued moves would reveal next turn | lantern light over a dark map | the source and radius | your own sources only (no leak) |

- **Threat** reuses the rules' move legality (pure, roads included), never a UI guess. It is tested against the same positions as the AI's reach.
- **Explained:**
  - each legend names its question and its scale;
  - each plate's hover gives the lens value with its breakdown;
  - a codex page, "Map lenses", has one entry per lens;
  - the Lenses button's tooltip reads "Extra map views (1–6). Off by default.";
  - the first-game guide does not mention lenses (they are the optional layer).

## 5. the Chronicle (UX-5, UX-6)

### 5.1 the column
- A right-hand column: 420 px at 1600 wide, 360 px at 1280.
- It lies **over** the board's right edge. The board stays full-bleed under it, and the camera's focus point shifts left while it is open.
- The rail's Chronicle button opens and closes it. It shows an **unread badge** (the count of announcements not yet seen).
- Two tabs: **Read** and **Plan**.

### 5.2 Read: the start-of-turn announcements (UX-6)
- **The source** is the same report as today: `turn_report_for(viewer)` events, worded by `TurnReportText.rows`. **No new wording logic;** a card's headline and detail are cut from the same text. A battle groups with its capture and aftermath lines into one card.
- **The kinds** come from the event `type` (`rules/turn_resolver.gd`):

| kind | event types (examples) | icon |
|---|---|---|
| **Needs you** | `order_rejected`, the report's "needs you" lines (`turn_report_panel.gd` 405, 426) | ! |
| **Battles** | `battle`, `border_battle`, storms, sallies | swords |
| **Land** | `captured`, losses, fealty, razing | flag |
| **Rulers** | `ruler_died`, sacrifices, returns | crown |
| **Magic** | `ritual_cast`, spells learned, curses, wards | sparkle |
| **Realm** | `income`, `recruited`, `research_done`, `transformed` | coin |
| **Seen abroad** | rivals' moves and captures you saw | eye |

- **The order:** importance by default: Needs you, then battles you fought, your land, rivals' land seen, rulers, magic, realm, seen abroad. Or sort by place, or by kind.
- **Show and hide:**
  - one filter chip per kind at the top of the column;
  - a hidden kind still counts ("3 hidden");
  - the choice is remembered in settings.
- **A card:**
  - the kind icon;
  - a one-line headline and up to two detail lines;
  - **the place**: click it to focus the board, which pulses a marker, as `_on_row_pressed` does today;
  - Watch and Battle report on battles;
  - **?** (the codex entry, as today);
  - **Pin** (it stays across turns until unpinned);
  - **Dismiss**.
- **Markers:** each card on view puts a numbered marker on the board at its province, the same number as the card. Markers go when the card is dismissed or the column closes.
- **The summary line** heads the column: chips such as "1 battle won", "+1 province", "+2 Knights" and "Clans +2 provinces", and gold "5 → 23, +18 a turn".
- **Auto-open** at the start of a turn, a setting:
  - when something needs you;
  - when anything important happened (Needs you, your battles, your land): **the default**;
  - always;
  - never (the badge only).
- **Full report:** a link at the column's foot opens today's `TurnReportPanel`, unchanged, with its ?, Watch and phases.
- **Fog:** the "what the computer was thinking" notes stay as today: a quiet line under fog, the notes after the game.
- **Hotseat:** each player's chronicle is their own (the viewer's report). Dismissals and pins are per player.

### 5.3 Plan: the end-of-turn review (UX-5)
- **Your orders as sentences,** numbered as on the board and in the tray (§3.4).
  - Each is the order's text with its forecast: the battle forecast for a march into a fight, the cost for a recruit, the finish turn for research.
  - × cancels; clicking one focuses it.
- **Checks as cards:** today's end-turn warnings, if any, as Needs-you cards.
- **The foot:** gold after orders, and **Seal the orders · End turn**.
- **Review before sealing** (a setting): when on, the seal opens Plan first and the column's seal ends the turn.
  - **The default:** on for a player's first game, off after.
- The Plan tab is always there through the Chronicle button.

## 6. the battle viewer (UX-8)
`BattleSimpleView._build_controls` and `BattleControls._build` (`ui/battle/battle_controls.gd:363-425`):
- **The stage is full-bleed.** `BattleStage3D` inherits the same controls.
- **Side plates (top left, top right):** name, a role chip (holding the ground, defending, attacking), the hp bar with its break notch, morale, and "breaks at N hp".
- **The centre (top):** the battle's name, the turn and round, and the condition chips (terrain, walls and cover).
- **The caption** is one line in a lower third, and "Got it" dismisses the first-battle help.
- **Why** becomes a collapsed tab on the right edge. Opened, it is today's `BattleWhyPanel`, and its key stays.
- **The bottom bar:**
  - Restart, Play, speed (1×, 2×, 4× as one segmented control);
  - **the timeline with moment markers:** `BattleMoments.KINDS` drawn at their event's place on the scrubber, clickable, with the same tooltips. This replaces the row of moment buttons; a moment the battle doesn't have isn't drawn;
  - Skip to end, Legend (?), Settings, Close.
- **The battle queue row** shows only with more than one battle.

## 7. the style kit (UX-0)
The **content** of UX-0 can start now. The **look** (fonts, panel styles, colours of the plaques, cards and seal) waits for Alex's art-direction notes.
- **Icons:** a 24 px set (16 px for plates), simple stroke SVGs drawn in the repo (`assets/ui/icons/`), loaded through `UiIcons.get(name)`.
  - The set: gold, income, walls, garrison, sight, strength, battle, research, magic, ruler, codex, turn, orders, recruit, morale, hp, march, fortify, siege, lens, chronicle, pin, dismiss, needs-you.
  - The canvas's shared-fixes board is the sketch.
  - Today's code-drawn glyphs (`_Glyph`, `_MarchMark`, `SeatEmblem`) stay.
- **Fonts (proposed):** Spectral SC for names and titles, Alegreya Sans for everything read, tabular figures for numbers. Both are SIL OFL; their licence files ship beside them.
  - The theme's `default_font` becomes Alegreya Sans.
  - A `UiFonts` helper gives title, name and number fonts.
  - Today every node sets its own size (`add_theme_font_size_override`). UX-0 adds a small type scale to `UiPalette`, and the HUD pieces use it.
- **Panels:** plaque, card, tray, seal, rail and legend `StyleBox`es in `ascendant_theme.tres`, plus lens palettes in `UiPalette`.

## 8. approachability (every ticket)
- **Everything that moves keeps its explanation:**
  - the breakdown tooltip on every number (`test_map_screen.gd` pins them today);
  - the ? on every report line and Chronicle card;
  - codex links.
- **The first-game guide is rewritten for the Table** (UX-9). Its steps point at an army (click it), March on the card, the tray, and the seal.
- **The codex's How to play** gains the Table, the Chronicle and the lenses.

## 9. tickets
`hard` marks the big-risk ticket.

**Order:**
1. UX-0's icons and UX-1 first.
2. Then UX-2, UX-3 and UX-8 side by side.
3. UX-4 after UX-3.
4. UX-5 after UX-4.
5. UX-6 after UX-1.
6. UX-7 after UX-2.
7. UX-9 last.

At most three builders at once. File ownership:
- UX-1: `map_screen`, `game_screen` and the new `table_hud`;
- UX-2: `board_overlay` and the ground shaders;
- UX-3: the new `ui/cards/`;
- UX-8: `ui/battle/`;
- UX-6: the Chronicle's own files.

0. **UX-0** `code` **Style kit:** the icon set and `UiIcons`; fonts and `UiFonts` (after Alex's notes); theme styles and the type scale.
   - **Gate:** `test_screens_fit` still passes with the new font.
1. **UX-1** `code` `hard` **The Table:** `TableHud`; the plaques; the rail with drawers (Research, Magic, Ruler, Codex, Controls); the tray and seal skeleton; the board full-bleed; the top bar, hint row and side panel removed; fits at three sizes.
   - **Tests:** `test_top_bar.gd` becomes `test_table_hud.gd`; `screen_fit_probe.gd`, `test_mvp3_polish.gd` (hint row, bar narrowing) and `test_first_game_guide.gd` (hang point) update.
2. **UX-2** `code` **Labels and sight:** the label diet; the four veil looks; sight words off the plates; the Vision map mode retired.
   - **Tests:** `test_fog_board.gd`'s sight-text assertions become veil-level assertions; `test_fog_ui.gd`'s Vision mode tests move to UX-7.
3. **UX-3** `code` **Selection cards:** the army card; the province card with its Recruit drawer; placement.
   - **Tests:** `test_map_screen.gd` (side panel contents) and `test_orders_ui.gd` (`Order_*` rows) move to the cards and tray.
4. **UX-4** `code` **Orders on the board:** numbered marks, tray tokens, Change and Cancel, gold after orders.
5. **UX-5** `code` **Chronicle Plan:** order sentences with forecasts, the checks, the seal, and review before sealing.
6. **UX-6** `code` **Chronicle Read:** kinds, importance, sort, show and hide, pin and dismiss, markers, the summary line, the auto-open setting, and Full report.
   - **Tests:** `test_turn_report_text.gd`'s wording stays pinned; new tests cover the kinds, the filters and the markers.
7. **UX-7** `code` **Lenses:** `MapLens`, `lens_tex` and the blend modes, the six lenses, legends, keys, the codex, fog safety.
   - **Gate:** a fog-leak test for every lens, using M5's snapshot probe (`tests/fog_test_kit.gd`).
8. **UX-8** `code` **Battle viewer:** §6.
   - **Tests:** `test_battle_controls`, `test_battle_simple_view`, `test_battle_stage3d` and `test_battle_host` update.
9. **UX-9** `code` **Walk and guide:** the first-game guide, How to play, the director's walk at three sizes, and the fixes it finds.

**Every ticket:**
- screenshots before and after at 1600×900, 1280×720 and 125%, of a fresh default game's first three turns (`tools/shots/play_shots.gd --defaults --fresh`, with `--ui-scale=125`);
- the compile check, the full suite, and boots with every flag;
- **no rules change:** records, digests and fixtures byte-identical;
- tests that pin UI text or layout are updated in the same PR, and the PR lists them.

## 10. out of scope
- Rules, AI and new mechanics.
- New art beyond the icon set and fonts. Art for the plaques, seal or cards (Ludo) is for Alex's art notes to decide.
- Replaying the turn on the board as animation. The canvas's "Replay the turn" button is in the parking lot.
- Controller, touch and mobile.
- Maps over 16 provinces. The board's 16×1 province textures stay; M6 grows them.

## 11. director's calls (review these first)
1. **The hybrid** (Alex 10-10): A's table, C's chronicle, D's lenses.
2. **The modal turn report becomes the Chronicle's Read.** "Full report" keeps today's panel, so nothing is lost.
3. **Sight speaks only through the veil.** The words live in tooltips and the codex. The Vision map mode folds into the Sight lens.
4. **Lenses:**
   - off by default, one at a time, keys 1–6;
   - never switched on by the game;
   - each with its own blend mode and palette;
   - every scale reads in lightness, not hue alone.
5. **Order numbers are list positions** (no new order ids). They re-flow on cancel, and the tray says so.
6. **The 2D map stays a setting.** The Table works over it; lenses there are best effort.
7. **Structure before style.** UX-1 to UX-8 use today's theme until UX-0's look lands from Alex's notes.
8. **Approachability keeps its bar.** Nothing loses its tooltip, ? or codex link in the move.

## 12. questions for Alex
1. **Chronicle auto-open at the start of a turn:**
   - a) when something important happened (my pick: Needs you, your battles, your land);
   - b) always, as in Total War;
   - c) never (the badge only).
2. **Review before sealing** (the seal opens Plan first):
   - a) on for a player's first game, then off, as a setting (my pick);
   - b) always;
   - c) never (the tray only).
3. **The Sight lens:**
   - a) keep it, as sight sources and next turn's sight (my pick);
   - b) drop it; the veil says enough.
4. **End turn:**
   - a) the wax seal (my pick; its art from your notes);
   - b) a plain gilt button.
5. **Fonts:**
   - a) Spectral SC and Alegreya Sans (my pick);
   - b) your art notes decide.
6. **The lens set:** Owner, Income, Forts, Threat, Magic and Sight. Add or cut any? (Default: these six.)

---

## appendix A. critic rounds
(Codex's hostile round on r1 goes here.)
