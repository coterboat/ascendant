# ASCENDANT: the War Table, a UI/UX spec

Status: **DRAFT r2 by the director (Claude session, 2026-10-10), for Alex's sign-off.**
- **Direction:** Alex picked it on 10-10 from the UI directions canvas: **A's War Table, with C's Chronicle and D's lenses.** "I love having all of the data available for the nerds who want to see it visually while keeping them entirely optional for the player who just wants to do war stuff."
- **Why now:** the MVP walk's biggest complaint, by far, is the UI.
- **The look waits for Alex's art-direction notes (10-10).** This spec fixes the structure: what is where, what it shows, and how it opens and closes. The look of the plaques, cards, seal and fonts follows his notes (UX-0b, §7). Until then builders use the current theme.
- **Critics:** Codex's hostile round on r1 (30 findings, 7 blockers) is absorbed. Appendix A lists what changed.

Built on:
- **The canvas:** https://claude.ai/artifact/QXN1JqEFBKAyduRoRj4WdA (private to Alex). It holds the audit of today's screens, the shared fixes, the four directions, their after-the-turn boards and the battle viewer.
- **Specs:** `design/GAME_BRIEF.md` (the approachability rules), `design/STYLE_BIBLE.md` (UI, icons, type sizes), `design/M5_MAGIC_FOG.md` (fog's view state, sight, what is public), `design/M3_BATTLES.md` (the battle viewer, the why panel).
- **The engine on `main` at 83cf829:** `ui/`, `world3d/`, `rules/fog_rules.gd`, `rules/turn_report_text.gd`, `rules/battle_moments.gd`, and the tests in §9.

**Alex: read §11 (director's calls) and §12 (your questions) first.**

## goal
**The board is the game.** Everything else is either a piece on the table or a page in the chronicle.

A new player sees the map, a few plaques, an army card when they click an army, and their orders in plain words. They never meet a number they didn't ask for.

A veteran presses 1 to 6 and gets every number on the map, each lens with its own colour and feel. They press it again and the art comes back.

The milestone proves three things:
- **The board can carry the whole game** without a top bar or a side panel, at every supported size.
- **A turn reads like a story.** Your orders read as sentences before you end the turn. What happened arrives as announcements you can sort, show, hide, pin and dismiss, like the old Total War's start-of-turn notices.
- **Depth is opt-in.** Every number the game has is one key away, and none of it is in the way.

## the short version
- **The Table (A).** The board fills the window. On top of it sit:
  - a **realm plaque** and an **opponent plaque** with **Menu**;
  - a **rail** down the left edge (Research, Magic, Ruler, Chronicle, Lenses, Codex, ?);
  - a **selection card** beside whatever you clicked;
  - your **orders**, drawn on the board and listed in a **tray**;
  - the **End turn seal**.
- **The Chronicle (C)**, a column on the right that you open and close:
  - **Read:** the start-of-turn announcements;
  - **Plan:** your orders as sentences with their forecasts, and the seal.
- **The Lenses (D):** six optional map views, **Owner, Income, Forts, Threat, Magic and Sight**, each with its own overlay, palette and feel. Off by default; one at a time.
- **Sight speaks for itself.** Four veil looks on the land, each different in lightness and in texture, so it reads without colour or words. The words stay in the plate's hover and in the codex.
- **What goes away:**
  - the top bar and the hint row;
  - the side panel;
  - the modal turn report ("Full report" still opens today's panel);
  - sight words on the plates;
  - the Vision map mode;
  - the battle viewer's row of thirteen buttons.
- **What stays:**
  - every explanation (breakdown tooltips, the ?, codex links);
  - every forecast;
  - every order flow (only their entry points move);
  - today's Research, Ruler and Codex panels (opened from the rail);
  - the 2D map setting, at full parity except the lens blend effects;
  - hotseat.
- **No rules change.** Game records, digests and fixtures stay byte-identical. Nothing the Chronicle remembers goes into a save's game state.
- **11 tickets:** UX-0a, UX-0b and UX-1 to UX-9 (§9).

---

## 1. the Table (UX-1)

### 1.1 the layout and the host seams
Today `MapScreen.Layout` is a VBox: `TopBar` over `Body`, and `Body` is `MapView` beside the 400 px `SidePanel` (`ui/map_screen.tscn`).
- **The new layout:** `MapView` fills the screen. A new **`TableHud`** sits over `MapView`, under the `Overlays` layer, and holds the plaques, rail, tray and seal.
- **`TopBar`, `HintRow` and `SidePanel` are removed.**
  - `MapScreen.add_top_bar_control` (`ui/map_screen.gd:299`) and its callers in `GameScreen._build_hud` (`ui/game_screen.gd:1134-1154`) give way to `TableHud.add_rail_button` and `add_plaque_item`.
  - `ResearchHud` puts its chips on the rail.
  - `_hang_under_top_bar` hangs the guide and the notice under the realm plaque.
- **The host seams come first.** Several later tickets need `map_screen.gd` and `game_screen.gd`, so UX-1 lands four small host APIs there. Later tickets plug into these instead of editing the two files (§9):
  - **`TableHud`:** the plaques, rail, tray and seal slots, and the safe areas (§1.3).
  - **`SelectionHost`:** "show this army or province" and "selection cleared". It replaces `_show_details`. UX-3's cards register with it.
  - **`ReportHost`:** the report lifecycle (a turn resolved, a report is ready, a report was opened or closed). It replaces the modal report's call sites. UX-6's Chronicle registers with it.
  - **`LensHost`:** the active lens, its keys and its texture feed to the board. UX-7 registers with it.

### 1.2 input: the HUD never steals the board
- `TableHud`'s root and every empty area use `MOUSE_FILTER_IGNORE`.
- Only the interactive pieces (buttons, cards, tray, Chronicle, plaques) are `STOP`.
- The board keeps its own picking (`board3d.gd` `_gui_input`, `MOUSE_FILTER_STOP`).
- **Tests:** on the 3D board and on the 2D map, a click on empty HUD space picks the province under it. Each interactive piece eats its click and the board doesn't see it.

### 1.3 the pieces, sizes and safe areas
| piece | where | shows | opens |
|---|---|---|---|
| **realm plaque** | top left | banner, faction name, gold with income (breakdown tooltip as today), turn, the ruler and kept power (with rulers) | the Ruler panel from the ruler line |
| **opponent plaque** | top right | each rival: banner, name, Computer and its level or Player, "last seen turn N" under fog | its codex entry |
| **Menu** | top right | — | today's menu |
| **rail** | left edge | Research (progress badge), Magic (spells and mages), Ruler, Chronicle (unread badge), Lenses (the active one), Codex, ? (controls) | **today's panels, as they are**: modal, with their dimmers and `PanelFit` |
| **selection card** | beside the selection (§3) | army or province | its actions |
| **tray** | bottom centre | your orders (§3.4), gold after orders | an order's card |
| **End turn seal** | bottom right of the tray | the order count | today's end-turn flow; the Plan review if on (§5.3) |

- **The sizes we support:** a 1600×900 window at 100%, a 1600×900 window at 125% (1280×720 logical; `content_scale_factor`, `settings_store.gd:177-187`), and a 1280×720 window at 100%. Every acceptance shot and fit test runs all three.
- **The safe areas:**
  - rail: 72 px on the left;
  - plaques: 72 px along the top;
  - tray and seal: 120 px along the bottom;
  - the Chronicle, when open: 420 px on the right (360 px below 1600 logical).

  What remains is the **board's safe area**. A selection card, the guide and notices are placed only inside it.
- **Who gives way, highest first:** modal panels, then the Chronicle, the selection card, the guide and notices, the tray, and the plaques. A lower piece moves or shrinks before it overlaps a higher one.
- **Tests:** overlap assertions for every pair, at all three sizes. Today's tests only check that nothing is clipped by the viewport.
- **Below 1600 logical:**
  - rail labels hide (icon only, tooltip kept);
  - tray tokens show their number or icon, with the text in the tooltip;
  - the opponent plaque's "last seen" line moves to its tooltip.
- **Nothing a click needs ever hides:** End turn, Menu and the selection card's first action.
- **The ? button** lists every key and mouse binding, today's hint text in full. The contextual hints also stay where a new player is looking:
  - the first-game guide's steps;
  - the board's empty-selection line ("Click an army to command it");
  - the card's own tooltips.
- **At the end of a game,** "Results" takes the seal's place. **Hotseat:** the handoff screen covers the table, and the HUD rebuilds for the next player.

### 1.4 one cancel, in order
Esc, and a right-click on empty board, go through one **`UiCancel`** dispatcher that closes the topmost thing only, in this order:
1. a modal panel or dialog (research, ruler, codex, cast, menu);
2. march targeting (§3.3);
3. the Chronicle;
4. the selection card;
5. the active lens;
6. the board close-up (`board3d.gd:1230-1238`);
7. nothing left: the menu.

Codex, close-up and `GameScreen` handling (`game_screen.gd:881-895`) route through it. **Tests:** every stacked pair.

### 1.5 the 2D map
Everything in §1, §3 and §5 works the same over the 2D map (`MapCanvas` behind the HUD). Lenses on 2D (§4.0) are a flat wash and the plate values, without the 3D blend effects. **Every acceptance test runs on both boards.**

## 2. labels and sight (UX-2)

### 2.1 the label diet
Today each province plate (`world3d/board_overlay.gd`, `_build_province_plates`) stacks:
- a glyph and the name;
- "N gold";
- the fort chip with walls bars;
- enchantment badges;
- the sight text;
- a countdown badge.

The rule: **state that changes or warns is always visible; static facts appear on hover.**

| part | always | on hover, focus or select |
|---|---|---|
| name, owner dot, capital crown | ✓ | |
| cut-off mark, countdown badge, besieged mark | ✓ | |
| gold | | ✓ (icon + number) |
| garrison | | ✓ (shield + count) |
| walls | | ✓ (pips) |
| enchantments | | ✓ (and always under the Magic lens) |
| sight words | — | the plate's tooltip (§2.2) |

- **Army plates** (`_build_army_plates`) don't change. The count, "Ruler", and fog's "≈20 · 3 turns ago" are all state.
- **A lens** shows its value on every plate, always (§4).
- **The plate carries the tooltip and the codex link** that `SightLabel` carries today (`board_overlay.gd:337-340`): its hover text, right-click and F1. They move to the plate itself before the label goes. **Test:** each plate's tooltip and codex link, by mouse and by keyboard focus.

### 2.2 sight is self-evident
The levels in code are `clear`, `glimpse`, `veiled` and `never` (`ui/fog_view.gd:25-26`, `world3d/vision.gd`). The player sees them as In clear sight, Glimpsed, Out of sight and Never seen. Code uses the keys, never the labels.

Today's shader treats veiled and never-seen land almost alike (`ground_common.gdshaderinc:121-135, 166-172`). UX-2 gives each level its own look, **different in lightness and in texture**, so it reads without colour vision and without a word:

| level | lightness | texture (the non-colour channel) | armies |
|---|---|---|---|
| `clear` | full | none | as they are |
| `glimpse` | a step down | a thin drifting mist (animated) | rough silhouettes, "≈N" |
| `veiled` | two steps down, toward sepia | static hatch lines, like an old map | faded ghosts where last seen; the turn on hover |
| `never` | darkest | flat dark parchment, no terrain detail | none |

- **`Vision.look(level)`** (pure) gives each level's shader parameters.
- **Tests:**
  - the four levels give four distinct parameter sets;
  - the lightness steps are at least a set amount apart;
  - the textures differ;
  - every plate's hover names its level.
- **No words on the map.** `SightLabel` and `Vision.tag_for` leave the plates; `Vision.words` moves to the plate's tooltip; `FogView.LEVEL_CODEX` stays the codex link.
- **The Vision map mode is retired.** That is the 2D swap behind the `VisionButton` (`map_screen.gd:215-234`, 643-712). Its legend and its "why do I see this" job move to the Sight lens (§4.6).
- **Acceptance:** before and after shots at full-map zoom, in all three sizes, on both boards.

## 3. selection cards and orders (UX-3, UX-4)

### 3.1 the army card (UX-3)
Click an army (yours, or one you can see). A card opens beside its plate:
- the header: name, where, commander;
- **portraits** (`UnitPortraits`) with hp bars, the ruler gilt-ringed;
- strength (the breakdown tooltip as today) and sight range.

Its actions are the order types the army really owns:
- **March:** `MoveOrder`, through today's targeting.
- **Change route:** only for a road `MoveOrder` (`change_via`).
- **Storm or lift a siege:** at a fort it is besieging. This is today's fort-panel flow (`SiegeOrder`), opened from the card.
- **Cast a ritual:** when a caster stands in it. This is today's cast dialog.
- **Cancel its order.**

Recruiting and Fortify belong to the province (§3.2). A rival's army shows what `FogView` allows, and no actions.

### 3.2 the province card (UX-3)
Click land:
- name, owner, terrain;
- income (breakdown tooltip);
- the fort: `FortChip`, walls, recruit cap and recruits ordered;
- armies here, each a button that selects it;
- enchantments;
- **actions on an owned province:**
  - **Recruit** opens a recruit section moved from the side panel: the capital list, the fort recruit section (`map_screen.gd:1401`) and the ruler recruit section (1318);
  - **Fortify** (`FortifyOrder`, today's fort panel);
  - the fort panel itself.

### 3.3 placement and targeting
- The card sits beside the selection's screen point, inside the board's safe area (§1.3). It flips to the other side, or docks bottom left, when there is no room.
- **While you pick a march destination,** the card collapses to a slim strip docked bottom left: "March: pick a province · Esc to cancel". No card covers the board while targeting, so there is nothing to dodge.
- **Tests:** placement for provinces on every edge, at the camera's nearest and farthest zoom, at all three sizes.

### 3.4 orders on the board, and the tray (UX-4)
- **Placed orders are numbered:** march, recruit, fortify, storm or siege, and ritual.
  - The number is the order's place among the placed orders, plus one, as `OrdersController.orders()` lists them.
  - There are no new order ids. Numbers re-flow when a placed order is cancelled or moved by `change_via`, which sends it to the end; the tray's tooltip says so.
- **Realm orders aren't numbered:** research, spellbook, mandate and other one-per-turn orders. They show in the tray as an icon token, and a new one replaces the old one in place, as the rules already do (`orders_controller.gd:218-223`).
- **Marks on the board** (`board_overlay.gd`):

| order | mark |
|---|---|
| march | today's path (`_draw_move`) with its number at the middle |
| recruit | a token at the fort: the number and "+N unit" (it replaces `GhostPlate_*`) |
| fortify | a token at the province with the walls icon |
| storm, siege | a token at the fort with the siege icon |
| ritual | a token at its target province |

- **The tray:**
  - placed orders by number, then realm orders by icon;
  - hover shows `order_text(i)` and `order_breakdown(i)`;
  - clicking a token focuses its place and opens its card with Change (where allowed) and Cancel;
  - ×, or right-click, cancels;
  - gold after orders (`gold_after_recruits`) ends the tray;
  - past seven tokens it scrolls sideways.
- **The seal:** "End turn" and the order count. It runs today's end-turn flow and warnings, unchanged.
- **Tests:** add, replace, cancel and change-via for every order class, with the numbers and tokens checked after each.

## 4. the lenses (UX-7)

### 4.0 the frame
- **`MapLens`** (new, `ui/map_lens.gd`) is pure. It reads **only the viewer's view** (`turn_report_for` / `FogView` state) and the viewer's own orders. Per province it gives:
  - a tint and strength;
  - a mark (ring or hatch);
  - the plate value;
  - a breakdown for the tooltip.

  It also gives one legend.
- **The board:**
  - a `lens_tex` beside `owner_tex`, `vision_tex` and `mark_tex` (`ground_common.gdshaderinc`), plus a `lens_mode` uniform;
  - `WorldView.set_lens(mode, entries)`;
  - the province-texture width becomes **one constant**, today's `Vision.WIDTH` 16, used by every texture and by the shader's division (`ground_common.gdshaderinc:104, 127, 138`). A map with more provinces than the width is rejected before any texture is built;
  - **tests:** the exact bytes and order of all four textures.
- **Compositing order**, bottom to top:
  1. terrain;
  2. the owner wash, or a lens **wash** that replaces it;
  3. a lens **glow**;
  4. the fog veil and its texture (§2.2), so sight still reads under any lens;
  5. a lens **hatch** or **ring**;
  6. the capture sweep;
  7. interaction marks (move target, hover, selection, focus flash).

  **Tests:** screenshot tests for each lens against each fog level, and with a selection and a move target on.
- **The 2D map:** each lens is a flat `ProvinceRegion` colour plus the plate values. The 3D-only blend effects are named in the legend.
- **Plates:** with a lens on, every plate shows the lens value.
- **A legend card** (bottom left, in the safe area): the lens's question, its scale and its totals.
- **Turning lenses on and off:**
  - keys 1–6 turn a lens on; the same key, Esc (§1.4) or ` turns it off;
  - the rail's Lenses button opens a picker for the mouse;
  - one lens at a time;
  - every session starts with lenses off.
- **Accessibility:** every lens scale runs in lightness (light to dark), never hue alone.
- **Fog safety:** a fog-leak test for every lens with M5's snapshot probe (`tests/fog_test_kit.gd`). Perturb the hidden state, and the lens's textures, plate values and legend must not change.

### 4.1–4.6 the six lenses
| # | lens | its question | overlay and palette | the feel | plate value | what it may know |
|---|---|---|---|---|---|---|
| 1 | **Owner** | Who holds what? | **wash**: seat colours at full strength over muted terrain; thick borders; capitals crowned; neutral slate | a heraldic political map | the owner | owners are public (`fog_rules.gd` view fields) |
| 2 | **Income** | What is it worth? | **glow**: dark umber (poor) to bright gilt (rich) | a treasury, warm metal | **base** income, as a coin badge | base income is public. The legend's totals are **base income only, and say so**. A rival's actual income (modifiers, cut-off) is never derived |
| 3 | **Forts** | Where can armies be raised and held? | **wash**: cool slate stone; a ring per fort with its level glyph and walls pips; besieged forts a red cracked ring; works dotted | masonry, cold grey-blue | level, walls n/max, recruit cap | level and walls are **public** (as the rules have them); works where seen; a siege where the view holds both sides' armies |
| 4 | **Threat** | What could hit me next turn? | **hatch**: red ink, denser for more seen or remembered enemy strength one province away; provinces your armies can also reach pulse amber | a war-room map, red pencil | "≈ strength" and "as of turn N" | **an estimate from sightings only** (below) |
| 5 | **Magic** | Where is magic at work? | **glow**: ink-violet sigils per visible enchantment (blessing, curse, ward, Bastion) | arcane, candle-dark | the enchantments | only the enchantments `FogView` shows |
| 6 | **Sight** | Why do I see what I see? | **ring**: warm lantern rings from each sight source, by its range in provinces; Far Sight as a target marker | lantern light over a dark map | the source and its range | your own sources only |

- **Threat is an estimate,** never the rules' move legality.
  - Rival armies in the view are pooled stand-ins with view ids, and their mandates and divisions are hidden (`fog_rules.gd:352-389`). So Threat counts each seen or remembered stand-in's strength against its province's **neighbours**.
  - Road reach depends on hidden facts, so the legend says "one step; roads may reach further".
  - Your own reach (for the amber) uses your real armies and the rules.
  - **Test:** indistinguishability under hidden-state perturbation.
- **Magic shows what is in play,** not what could be cast. A ritual's reach still appears where it does today, in the cast dialog's targeting.
- **Sight** is drawn from `FogRules.sight_sources` and nothing else (`fog_rules.gd:80-99`): owned provinces, forts, armies (with the why: ruler, commander, scout) and Far Sight (range 0, a target marker).
  - A dashed ring previews next turn's sight from your queued marches. It uses the same function on your own armies' planned places, which is information that's all yours.
- **Explained:**
  - every legend names its question and scale;
  - every plate's hover gives the lens value with its breakdown;
  - a codex page, "Map lenses", has one entry per lens;
  - the Lenses button's tooltip reads "Extra map views (1–6). Off by default.";
  - the first-game guide leaves lenses out.

## 5. the Chronicle (UX-5, UX-6)

### 5.1 the column
- A right-hand column: 420 px at 1600 logical width, 360 px below.
- It lies over the board's right edge, in its safe area (§1.3). The camera's focus point shifts left while it is open.
- The rail's Chronicle button opens and closes it. It shows an **unread badge**.
- Two tabs: **Read** and **Plan**.

### 5.2 Read: the start-of-turn announcements (UX-6)
**The model.** `ChronicleModel` (new, `ui/chronicle_model.gd`) is pure. Its input:
- the viewer's report events, filtered for fog exactly as today (`turn_report_for(viewer)`);
- the **current-state needs**: the research and siege "needs you" lines the report panel builds today from state, not events (`turn_report_panel.gd:405-452`). They move into a pure function both screens use.

Its output is **announcements**, each with:
- a stable `id`: turn plus event index, or the need's key;
- `kind`, `headline`, `detail`;
- `province` (the focus target);
- `codex`;
- `battle` (for Watch and Battle report);
- `source_rows` (the full `TurnReportText` rows it came from).

**Headlines and details are written per event type** in the model: a table of short templates over each event's own fields. They are not cut out of the report's prose.
- An event type without a template falls back to a generic headline, with its full `TurnReportText` row as the detail. So nothing is lost, and the type gets a template later.
- The report's own text, the records and `TurnReportText` don't change.

**Grouping** is explicit, in the model:
- a battle and the capture of the same province on the same turn make **one card**;
- a recruit line stays as `TurnReportText` already merges it;
- nothing else groups.

**Tests:** fixture turns with several battles, several captures, a battle without a capture, and a capture without a battle.

**The kinds:**

| kind | from | icon |
|---|---|---|
| **Needs you** | `order_rejected` events, and the current-state needs | ! |
| **Battles** | `battle`, `border_battle`, storms, sallies | swords |
| **Land** | `captured`, losses, fealty, razing | flag |
| **Rulers** | `ruler_died`, sacrifices, returns | crown |
| **Magic** | `ritual_cast`, spells learned, curses, wards | sparkle |
| **Realm** | `income`, `recruited`, `research_done`, `transformed` | coin |
| **Seen abroad** | rivals' moves and captures you saw | eye |

- **The order:** importance by default: Needs you, then battles you fought, your land, rivals' land seen, rulers, magic, realm, seen abroad. Or sort by place, or by kind.
- **Show and hide:**
  - one filter chip per kind;
  - a hidden kind still counts ("3 hidden");
  - the choice is a setting, the same for every game and player (it holds no game facts).
- **A card:**
  - the kind icon;
  - the headline, and the detail in up to two lines, expanding to the full `source_rows` on click;
  - **the place**: click it to focus the board, which pulses a marker, as `_on_row_pressed` does today;
  - Watch and Battle report on battles;
  - **?** (as today);
  - **Pin**;
  - **Dismiss**.
- **Markers:** each card on view puts a numbered marker at its province, the same number as the card. They go when the card is dismissed or the column closes.
- **The summary line** heads the column: chips such as "1 battle won", "+1 province", "+2 Knights" and "Clans +2 provinces", and gold "5 → 23, +18 a turn".
- **Auto-open** at the start of a turn, a setting:
  - when something needs you;
  - when anything important happened (Needs you, your battles, your land): **the default**;
  - always;
  - never (the badge only).
- **Full report:** a link at the foot opens today's `TurnReportPanel`, unchanged.
- **Fog:** "what the computer was thinking" stays as today: one quiet line under fog, the notes after the game.

**Pins and dismissals live outside the game.** A `ChronicleStore` keeps them in a UI sidecar file beside the save, keyed by the game's identity, the seat and the announcement `id`.
- Never in `GameSession`, the save's game state, records or digests.
- **A pinned card keeps the payload it was shown with:** its rendered, fog-filtered text and its focus province. It is never re-rendered against a later state, so it can't reveal anything learned since.
- **Hotseat:** each seat's pins and dismissals are its own, and the handoff clears the column.
- **Tests:**
  - hotseat privacy (seat 2 never sees seat 1's pins);
  - a pinned card is unchanged across turns while the hidden state is perturbed;
  - a save loaded without its sidecar simply has no pins.

### 5.3 Plan: the end-of-turn review (UX-5)
- **Your orders as sentences:** placed orders by number, then realm orders.
  - Each is the order's text with its forecast: the battle forecast for a march into a fight, the cost for a recruit, the finish turn for research.
  - × cancels; clicking one focuses it.
- **Checks as cards:** today's end-turn warnings, as Needs-you cards.
- **The foot:** gold after orders, and **Seal the orders · End turn**.
- **Review before sealing** (a setting): when on, the seal opens Plan first, and the column's seal ends the turn.
  - **The default:** on for a player's first game, off after.

## 6. the battle viewer (UX-8)
**`BattleControls` stays the one controls component** (`ui/battle/battle_controls.gd`): playback state, shortcuts, the saved Why and Legend settings. `BattleSimpleView._build_controls` (`battle_simple_view.gd:1451`) still builds it, and `BattleStage3D` still inherits it (`world3d/battle_stage.gd:2`). UX-8 changes its layout and the stage's HUD, not its ownership.
- **The stage is full-bleed.**
- **Side plates (top left, top right):** name, a role chip (holding the ground, defending, attacking), the hp bar with its break notch, morale, and "breaks at N hp".
- **The centre (top):** the battle's name, the turn and round, and the condition chips.
- **The caption** is one line in a lower third. "Got it" dismisses the first-battle help.
- **Why** becomes a collapsed tab on the right edge. Opened, it is today's `BattleWhyPanel`, and its key stays.
- **The bottom bar:**
  - Restart, Play, speed (1×, 2×, 4×, one segmented control);
  - **the scrubber with moment markers:** each kind in `BattleMoments.KINDS` is drawn at its event's place, clickable, with today's tooltips. This replaces the row of moment buttons; a moment the battle lacks isn't drawn;
  - Skip to end, Legend (?), Settings, Close.
- **The queue row** shows only with more than one battle.
- **Tests:** the shortcuts and saved settings unchanged, and the 2D and 3D views both built from the one component.

## 7. the style kit (UX-0a, UX-0b)
- **UX-0a (now):**
  - **the icon set:** 24 px, and 16 px for plates. Simple stroke SVGs drawn in the repo (`assets/ui/icons/`), loaded through `UiIcons.get(name)`.
    - The set: gold, income, walls, garrison, sight, strength, battle, research, magic, ruler, codex, turn, orders, recruit, morale, hp, march, fortify, siege, lens, chronicle, pin, dismiss, needs-you.
    - The canvas's shared-fixes board is the sketch.
    - Today's code-drawn glyphs (`_Glyph`, `_MarchMark`, `SeatEmblem`) stay.
  - **The type-token API:** `UiFonts` (title, name, body, number) and a type scale in `UiPalette`, both on today's default font.
    - Today every node sets its own size (`add_theme_font_size_override`). The new HUD pieces use the tokens from the start.
  - **Gate:** today's fit tests pass.
- **UX-0b (after Alex's art notes):** the look.
  - **Fonts.** Proposed: Spectral SC for names and titles, Alegreya Sans for everything read, tabular figures. Both are SIL OFL, and their licence files ship beside them. The tokens switch over, so nothing else changes.
  - **Styles:** plaque, card, tray, seal, rail and legend `StyleBox`es; lens palettes in `UiPalette`.
  - **Gate:** the fit tests at all three sizes, run again with the new fonts.

## 8. approachability (every ticket)
- **Everything that moves keeps its explanation:**
  - the breakdown tooltip on every number (`test_map_screen.gd` pins them today; the cards inherit those tests);
  - the ? on every report line and Chronicle card;
  - codex links on every plate, card and lens.
- **The first-game guide is rewritten for the Table** (UX-9). Its steps point at an army (click it), March on the card, the tray, and the seal.
- **The codex's How to play** gains the Table, the Chronicle and the lenses.

## 9. tickets
`hard` marks the big-risk ticket.

**Order:**
1. UX-0a and UX-1 first. UX-1 lands the host seams (§1.1) before anything else plugs in.
2. Then UX-2, UX-3 and UX-8 side by side.
3. UX-4 after UX-3.
4. UX-5 after UX-4.
5. UX-6 after UX-1.
6. UX-7 after UX-2.
7. UX-0b when Alex's art notes are in.
8. UX-9 last.

**Ownership:**
- UX-1 owns `map_screen.gd`, `game_screen.gd`, `table_hud.gd` and the host seams.
- Later tickets work through the seams.
- A ticket that still must touch `map_screen.gd` or `game_screen.gd` says so in its PR, and **those merges go one at a time**: the director merges them in order and re-verifies the next against the new main.
- UX-2 owns `board_overlay.gd` and the ground shaders; UX-3 owns `ui/cards/`; UX-6 owns the Chronicle's files; UX-7 owns `map_lens.gd` and `set_lens`; UX-8 owns `ui/battle/`.
- At most three builders at once.

**The tickets:**
- **UX-0a** `code` **Icons and type tokens** (§7).
- **UX-0b** `code` **The look** (§7), after Alex's notes.
- **UX-1** `code` `hard` **The Table:**
  - the host seams, `TableHud`, the plaques, the rail (opening today's panels), the tray and seal skeleton;
  - the safe areas and give-way order;
  - the input contract (§1.2) and `UiCancel` (§1.4);
  - the top bar, hint row and side panel removed;
  - both boards.
- **UX-2** `code` **Labels and sight:** the label diet, the plate's tooltip and codex link, the four veil looks with `Vision.look`, and the Vision mode retired.
- **UX-3** `code` **Selection cards:** army and province cards with their real actions, the recruit section, placement, and the targeting strip.
- **UX-4** `code` **Orders on the board:** numbered placed orders, realm-order tokens, marks, the tray, Change and Cancel.
- **UX-5** `code` **Chronicle Plan:** sentences with forecasts, checks, the seal, and review before sealing.
- **UX-6** `code` **Chronicle Read:** `ChronicleModel` (templates, grouping, current-state needs), kinds, sorting, filters, pin and dismiss, `ChronicleStore`, markers, the summary, auto-open, Full report.
- **UX-7** `code` **Lenses:** `MapLens`, `lens_tex` and the one width constant, compositing, the six lenses, legends, keys, the codex, fog safety, 2D washes.
- **UX-8** `code` **Battle viewer** (§6).
- **UX-9** `code` **Walk and guide:** the first-game guide, How to play, the director's walk at three sizes on both boards, and the fixes it finds.

**Tests each ticket updates or adds** (in its PR, listed):

| ticket | existing suites it changes | new coverage |
|---|---|---|
| UX-1 | `test_top_bar` (becomes `test_table_hud`), `screen_fit_probe` / `test_screens_fit`, `test_mvp3_polish` (hint row, bar narrowing), `test_first_game_guide` (hang point), `test_game_screen`, `test_turn_flow_ui`, `test_computer_seats_ui`, `test_board3d` (picking), `test_ui_polish` | click-through on both boards; pairwise overlap at three sizes; stacked cancel; hotseat HUD rebuild |
| UX-2 | `test_fog_board` (sight text becomes veil levels and plate tooltips), `test_fog_ui` (Vision mode to UX-7) | `Vision.look`; plate tooltip and codex link by mouse and focus |
| UX-3 | `test_map_screen` (side panel to cards), `test_orders_ui`, `test_army_names_ui`, `test_fort_panel`, `test_map_mandates`, `test_ruler_panel` | card actions per order type; placement at edges and zooms |
| UX-4 | `test_orders_ui` (rows to tray), `test_board3d` (arrows) | numbering and replacement per order class |
| UX-5 | `test_game_screen` (end turn) | Plan review on and off |
| UX-6 | `test_turn_report_text` (wording stays pinned), `test_turn_report_codex_links`, `test_fog_report`, `test_watch_entry_ui`, `test_codex_links_ui` | `ChronicleModel` templates for every event type; grouping fixtures; store privacy; pinned-card fog perturbation |
| UX-7 | `test_fog_ui` (the Vision legend's job) | texture bytes; compositing shots; a fog leak test per lens; Threat indistinguishability |
| UX-8 | `test_battle_controls`, `test_battle_simple_view`, `test_battle_stage3d`, `test_battle_host` | moment markers; shortcuts and settings kept |

**Every ticket:**
- before and after shots at the three sizes, of a fresh default game's first three turns (`tools/shots/play_shots.gd --defaults --fresh`, with `--ui-scale=125` for the second);
- the compile check, the full suite, and boots with every flag;
- **no rules change:** records, digests and fixtures byte-identical.

## 10. out of scope
- Rules, AI and new mechanics.
- New art beyond the icon set and fonts. Art for the plaques, seal or cards (Ludo) is for Alex's art notes.
- **Re-homing the Research, Ruler and Codex panels as edge drawers.** They open from the rail as today's modals. A drawer shell (no full-screen dimmer, scroll instead of `PanelFit`) is in the parking lot.
- Replaying the turn on the board as animation (the canvas's "Replay the turn" button).
- Controller, touch and mobile.
- Maps over 16 provinces. The width constant (§4.0) makes that one change when M6 needs it.

## 11. director's calls (review these first)
1. **The hybrid** (Alex 10-10): A's table, C's chronicle, D's lenses.
2. **The modal turn report becomes the Chronicle's Read.** "Full report" keeps today's panel, so nothing is lost.
3. **Sight speaks through the veil:** four looks that differ in lightness and texture, with the words in each plate's hover and the codex. The Vision map mode folds into the Sight lens.
4. **Lenses:**
   - off by default, one at a time, keys 1–6;
   - never switched on by the game;
   - each its own blend mode and palette;
   - every scale in lightness, not hue alone;
   - each reads only the viewer's view.
5. **Threat is an honest estimate** from what you've seen, one step out. It never pretends to know a rival's roads or mandates.
6. **Only placed orders get numbers,** and they are list positions (no new order ids). Realm orders are icon tokens.
7. **The Chronicle remembers outside the game.** Pins and dismissals live in a UI sidecar, never in records. A pinned card keeps the text it was shown with.
8. **The rail opens today's panels as they are.** No drawer rewrite in this milestone.
9. **Structure before style.** UX-0a's tokens come now; UX-0b's look comes from Alex's notes.
10. **Both boards, every test.** The 2D map gets everything except the lens blend effects, and the legend says so.

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
   - a) keep it: your sight sources and next turn's sight (my pick);
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

### round 1 (Codex, hostile, on r1, 2026-10-10): 30 findings, 7 blockers. All taken; r2 is the result.
- **Blockers:**
  - the HUD's input contract (§1.2);
  - Threat as an estimate, not rules legality (§4);
  - where pins live (the UI sidecar, §5.2);
  - an explicit grouping model (§5.2);
  - the panels stay modals (§1.3, §10);
  - Sight drawn from `FogRules.sight_sources`, owned land included, with Far Sight as a marker (§4);
  - the veil needs a non-colour channel and measurable steps (§2.2).

    Codex proposed a status glyph for the last one. We took **texture** instead, since Alex wants sight wordless on the map.
- **Majors:**
  - Income totals are base income only;
  - Fort level and walls stay public, as the rules have them;
  - Magic shows only what is in play;
  - one province-texture width constant and texture byte tests;
  - a compositing order;
  - the supported-size matrix;
  - safe areas and a give-way order;
  - the targeting strip instead of hover-dodging;
  - `UiCancel`;
  - card actions mapped to real order types (Fortify on the province; Storm through the fort flow);
  - numbering only placed orders;
  - per-type headline templates instead of cut prose;
  - current-state needs as their own input;
  - frozen payloads for pinned cards;
  - the host seams and serialized merges;
  - UX-0 split;
  - 2D parity defined;
  - the plate inheriting `SightLabel`'s tooltip and codex link;
  - one battle controls component;
  - the missing test suites.
- **Minors:**
  - the `add_top_bar_control` reference fixed;
  - code keys separate from player-facing labels;
  - contextual hints kept where a new player looks.
