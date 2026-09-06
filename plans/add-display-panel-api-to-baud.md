# Plan: Add a generic `displayPanel()` API to baud

Status: **proposed, not started.** Written up so the decision can be made cold;
see "Reasons to hold off" at the end before building anything.

## Context

baud (~/src/baud) is a TypeScript/Ink terminal BBS client embedding Lua 5.4 via
wasmoon. Lua scripts call baud-provided globals — `send()`, `echo()`,
`createTrigger()`, `setStatus()`, `dbOpen()`.

The motivating use case is a live minimap for Tele-Arena: a small always-visible
box showing the rooms around the character and which one they're standing in.
But baud should **not** learn what a room is. It should expose a generic
rectangular panel of styled text, and this repo decides that panel is a map.
Another script could put a party list, an inventory, or a quest log in it.

This is the same seam baud already uses: `setStatus()` doesn't know what HP is,
`dbOpen()` doesn't know what a room is.

## Findings: how Ink actually renders (verified in ink 5.2.1)

These constrain the design, and two of them are non-obvious.

**baud is not "all `<Static>`".** Only `OutputArea` is Static. `InputArea` and
`StatusArea` are already in the dynamic region — the bordered cyan box at the
bottom of the screen *is* the non-Static half. Adding a panel makes that region
taller; it does not introduce a new rendering mode.

**`<Static>` is not a pane or a viewport.** From `ink.js`, Static content is
written to stdout once and forgotten; it lives in the *terminal's* native
scrollback. So you cannot allocate it "50% of the screen" — it gets everything
above the dynamic region, unbounded. The dynamic region is always the last N
lines, pinned to the bottom, because `log-update` erases by counting lines up
from the cursor:

```js
stream.write(ansiEscapes.eraseLines(previousLineCount) + output);
```

The achievable split is therefore `[unbounded scrollback] / [N pinned rows]`.
That looks like a 50/50 split if N ≈ rows/2. What is *not* achievable without
abandoning `<Static>` is a fixed-height, independently-scrolling output pane.

**There is a performance cliff, not a slope** (`ink.js:120`):

```js
if (outputHeight >= this.options.stdout.rows) {
  this.options.stdout.write(ansiEscapes.clearTerminal + this.fullStaticOutput + output);
}
```

If the dynamic region ever reaches full terminal height, Ink stops incremental
updates and rewrites `fullStaticOutput` — *the entire accumulated session
scrollback* — on every frame. In baud that is every line the BBS has sent since
connect, so it degrades continuously as the session runs. Staying below
`stdout.rows` is a hard requirement, not a nicety.

**Redraw cost is already throttled.** Ink throttles dynamic renders to ~32ms
(`throttle(this.onRender, 32)`), so pushing a new panel on every room change is
not a performance concern.

Note: `~/src/ink` is an upstream reading copy at 6.6.0. baud resolves
`ink@5.2.1` from npm and is not linked to it. Line numbers above are 5.2.1.

## The API

One global, two calls:

| Call | Effect |
|---|---|
| `displayPanel(rows)` | show / replace panel contents |
| `displayPanel(nil)`  | hide the panel |

A **row** is either a plain string or a list of segments
`{ text, fg, bg, bold, inverse, dim }`. Mixing the two forms in one call is
allowed. The string shorthand matters: most panels (inventory, party, quest log)
never need per-cell colour — a map is the unusual case.

```lua
displayPanel({
  "north-plaza",
  { { text = "[", fg = "white" }, { text = "@", fg = "yellow", inverse = true }, { text = "]" } },
  { { text = " | ", fg = "cyan" } },
})
```

Nested-table marshalling across wasmoon was verified before writing this plan:
a Lua list-of-lists-of-tables arrives as nested JS arrays/objects, and mixed
string/segment rows survive intact.

Panel is **off by default**. Toggling needs no new command plumbing —
`App.tsx:461` already executes arbitrary Lua, so `/lua toggleMap()` works the
moment the script defines that global.

## Deliberate decisions

**No function form.** `setStatus` also accepts a *function*, which baud
re-evaluates after every batch of server data (`App.tsx:149`). That is right for
a cheap HP gauge and wrong here — re-rasterizing a map on every incoming line
would be waste. `displayPanel` is push-only; the script decides when it is
dirty. This asymmetry with `setStatus` is intentional and should carry a comment
at the definition, or it will read as an oversight.

**The height clamp is baud's job, not the script's.** Only baud knows
`stdout.rows`, and the cliff above is baud's failure mode. A script must not be
able to wedge the client by pushing 500 rows. `PanelArea` truncates to
`stdout.rows - inputHeight - 2` and prints `… +N more`; a script may push
whatever it likes and simply gets less of it. This also handles terminal resize
for free, which a hardcoded 50% split would not.

**baud draws the border, the script draws the content.** The one piece of policy
baud keeps: it owns the chrome (matching the input box's rounded style) and is
the only side that knows the terminal width. A title is then just the script's
first row — which is why there is no options bag.

**One panel, no id** (YAGNI). Adding a name parameter later is
backwards-compatible if two concurrent panels ever turn out to be needed.

**Hand-rolled coercion, not zod.** `setStatus` validates by hand
(`String(s.text ?? '')`, truthy → `true | undefined`). zod is used only for
config-file schemas in this codebase. Match the local style.

## Files to change (baud, ~80 lines)

- `src/state/AppState.ts` — `PanelSegment` / `PanelRow` types, `panel: PanelRow[] | null`, `SET_PANEL` action
- `src/state/StateContext.tsx:151` — reducer case, beside `SET_STATUS_SEGMENTS`
- `src/scripting/LuaEngine.ts` — `displayPanel` on the `ScriptApi` interface + `global.set`
- `src/ui/App.tsx:298` — coercion mirroring `setStatus`, and `<PanelArea/>` above the input box
- `src/ui/PanelArea.tsx` — new; the `useStdout()` clamp lives here
- `tests/ui-components.test.tsx` — render + truncation tests (`ink-testing-library` renders without a TTY)

## Acceptance check

From baud's `/lua` console:

```
/lua displayPanel({ "hello", { { text = "world", fg = "yellow", inverse = true } } })
/lua displayPanel(nil)
```

The first shows a bordered two-line box above the input; the second removes it.
Pushing 500 rows must truncate rather than clear-and-redraw the session.

## First consumer: the Tele-Arena minimap (this repo)

Lives in a new `ta_map.lua` — not `main.lua`, which is at 155/200 locals.
`toggleMap()` flips a flag and either pushes a freshly-rasterized grid or calls
`displayPanel(nil)`.

Rendering scheme: **4 columns × 2 rows per room**, 3-char glyph `[·]`. That is
the minimum pitch that renders all eight compass directions, and the 2:1 ratio
matches terminal cell aspect so diagonals read as roughly 45°.

| Direction | Character, relative to glyph centre |
|---|---|
| `e` / `w`   | `-` at ±2 cols |
| `n` / `s`   | `\|` at ∓1 row |
| `ne` / `sw` | `/` at ±2 cols, ∓1 row |
| `nw` / `se` | `\` at ∓2 cols, ∓1 row |
| `u` / `d`   | no cell available — badge *inside* the glyph (`^` / `v` / `↕`) |

Two consequences to decide rather than discover:

- `ne` from A and `nw` from B land in the **same** character cell. Crossing
  diagonals must collapse to `X`.
- `u`/`d` have nowhere to go in the plane, hence the in-glyph badge — the same
  call `report.ts` already makes with its ▲/▼ badges.

The direction vocabulary is **11 tokens, not 10**: the eight compass points,
`u` (22 edges), `d` (22 edges), and `passage` (2 edges). `passage` is the
great-lake ferry — a symmetric teleport between the two towns' docks — and has
no planar representation at all. It should be listed in text, not drawn.

Marker characters: `@` you (yellow, inverse), `·` plain room, `^`/`v`/`↕`
vertical exits (magenta), walked connectors cyan, unwalked frontier stubs dim
grey, locked doors red.

Coordinates come from a BFS out from the player's room, dead-reckoned,
first-write-wins — so the neighbourhood nearest the player stays geometrically
honest when a loop miscloses. This is deliberately *not* `report.ts`'s
Gauss-Seidel relaxation, which is the right call for a whole-floor view and
overkill for a 3-deep local one.

A working prototype was rendered against the live `tele-arena.db` (760 rooms,
1607 exits, 49 unwalked stubs, 8 areas). Depth 4 from `north-plaza`:

```
╭────────────────────────╮
│ north-plaza  (@ = you) │
│         [·]            │
│          |             │
│     [·] [v] [^]        │
│        \ | /           │
│     [·]-[@]-[v]        │
│        / | \           │
│     [·]-[·]-[·]        │
│        / | /           │
│     [·] [·]            │
│      |                 │
│     [·]                │
│    /                   │
│ [·]                    │
╰────────────────────────╯
```

Measured sizes from `north-plaza`: depth 3 → 11×11 chars, depth 4 → 13×15,
depth 5 → 15×19, depth 7 → 19×27. Depth 3–5 is the usable range for a
persistent panel. In a mock App shell, toggling a 7-row map took the dynamic
region from 5 rows to 14 — comfortably under the cliff on any normal terminal.

## Prior art: the shrine's hand-drawn TOWN 1 map

A 30-year-old hand-drawn map of the first town (from the tele-arena shrine)
turned up after the above was written. It independently arrives at most of the
same scheme — `[X]` glyphs, `-` `|` `\` `/` connectors, `^`/`v` badges inside
the glyph for vertical exits, colour per room class — which is good evidence
those choices are right. Where it differs, **it is better**, and the plan below
should follow it rather than the scheme sketched above.

Our DB reproduces it. North plaza's six exits match the drawing edge for edge
(`w` temple, `e` arena, `n` guild-hall, `s` south-plaza, `nw` equipment-shop,
`ne` tavern), and rendering rooms 1–13 in its style gives:

```
      [D]
       |
       |
 [E]  [Gv] [T^]
    \  |  /
     \ | /
 [t]--[*]--[Av]
       |
       |
 [a]--[ ]--[W]
       |
       |
      [M]
```

### Five corrections it implies

**1. Vertical pitch is 3 rows, not 2, and diagonals get two characters.**
A single connector char leaves a diagonal ambiguous about which pair it joins.
With a two-character diagonal the slope is explicit, and two crossing diagonals
interleave across different cells instead of landing on the same one — so the
`X` collapse described earlier becomes a rare fallback rather than a routine
case. Pitch is 5 cols × 3 rows per room.

**2. Show landmarks, not a neighbourhood.** The original plan drew BFS depth-3
around the player. The historical map instead draws *what you would want to walk
to* — and its room set is exactly computable:

```sql
SELECT * FROM rooms r WHERE r.name IN (
  SELECT name FROM rooms r2 WHERE r2.area_id = r.area_id
  GROUP BY name HAVING count(*) = 1);
```

That is the 13 boxes on the drawing, and it excludes precisely what the drawing
omits: repeated-name wilderness (first-town has swamp ×30, forest ×28, cave ×5,
clearing ×4). It yields 18 rooms for first-dungeon, 15 first-town, 11
second-town, 7 third-town. For first-town the rule picks up two rooms the
drawing does not have — `ruined plaza` and `ancient temple` — which are outside
the historical map's scope rather than errors.

**3. Off-map exits become text labels**, not drawn edges: "Passage to Town 2",
"down to Dungeon", "Mountains", "Private Room". This solves the `passage` ferry,
which has no planar representation, and gives frontier/boundary edges somewhere
to go. Adopt it.

**4. Flatten `u`/`d` onto one canvas for small maps.** The earlier plan badged
vertical exits inside the parent glyph and did not draw the destination at all.
The historical map does both: it badges the glyph *and* places the vertical
neighbour as an adjacent box with the opposite badge, joined by an ordinary
connector — `[Gv]` guild beside `[V^]` vaults, `[T^]` tavern below `[v]` private
room. No floor tabs needed.

This matters because those two rooms are reachable **only** by `u`/`d` (guild
`d`→vaults, tavern `u`→private room). A renderer that walks compass edges alone
silently drops them — ours did, on the first attempt. The data is correct; the
renderer was not.

This is a small-map technique. For the 179-room, 3-floor first dungeon,
flattening is wrong and `report.ts`'s floor tabs remain right.

**5. Glyph letters carry meaning**, with a key beneath: `t` temple, `a` armor
shop, `W` weapon shop, `*` north plaza. A bare `·` says only that a room exists.
Deriving the letter from the room name needs a collision rule (temple and tavern
both want `T`; the drawing uses `t` and `T`).

### What this changes about the proposal

It splits the idea in two, and they are not equally good:

- **An area landmark map** — the historical map, generated live, with "you are
  here" highlighted. Small (13 rooms fits in ~13 rows), stable, genuinely useful
  while playing, and mostly derivable from data we already have.
- **A local neighbourhood minimap** — the original BFS-depth-3 sketch. Still
  subject to the "only correct while mapping is on" problem below.

The landmark map is the stronger of the two, and it weakens one objection in
"Reasons to hold off": a landmark map does not need a trustworthy
`currentRoomId` to be *useful*, only to draw the "you are here" marker. Without
it, it degrades to a static-but-correct area map rather than becoming wrong.


## Reasons to hold off

Recorded honestly, because the case is not obviously closed:

- **`report.ts` may already be enough.** The browser map is interactive,
  zoomable, shows every floor and area, and is one `just report` away. A 15×19
  character panel is strictly less capable. The only thing it adds is *while
  playing, without leaving the terminal* — which matters during mapping runs and
  probably not otherwise.
- **The panel is only correct while mapping is on.** `currentRoomId` is
  explicitly untrustworthy outside mapping mode (see `handleRoomEntry`), and
  `navigate-to` deliberately suspends mapping for the duration of a walk. So
  during the long routed walks — arguably when a minimap is most wanted — there
  is no reliable "you are here" to draw. Fixing that is a larger change to how
  position is tracked, and is the real prerequisite.
- **It permanently costs screen height.** Every row given to the panel is a row
  of game text not visible. Default-off mitigates this but does not remove it.
- **Scope.** The baud half is genuinely small and generic and would be useful
  regardless. The tele-arena half — rasterizer, viewport, floor handling,
  redraw triggers — is the larger and less certain piece.

A reasonable middle path: build the baud `displayPanel()` half only. It is
independently useful, testable without any map code, and leaves the map question
open.
