# Map schema

The map moves out of SQLite and into checked-in JSON: one file per area under
`map/areas/`, plus an index. JSON because it diffs, reviews and hand-edits, and
because everything downstream — a static site, a baud panel, a router — reads it
without a database.

## What it has to support

| goal | what the schema owes it |
|---|---|
| scrape existing maps | a shape a parser can emit and a human can check |
| modern HTML rendering | layout that is separate from, and subordinate to, topology |
| track a character live | stable room ids that never change |
| flag game/map disagreement | provenance: which claim came from where |
| dynamic routing | gates as data — keys, spoken words, levers — not prose |
| map new regions | partial knowledge as a first-class state, not a gap |

## Five decisions, each paid for this week

**1. Ids are strings, `area/room`, and never change.**
`first-town/north-plaza`, `stoneworks-1/chamber-4`. Integer ids made every diff
unreadable and every merge destructive. A string id survives re-encoding, reads
in a route definition, and can be grepped.

**2. Topology is truth; layout is a drawing hint.**
Coordinates are stored under `layout`, marked presentational, and never consulted
for identity. Dead-reckoned `x/y` are what broke the desert: two rooms an edge
apart were recorded eight cells apart, and loop closure matched on the number.
The renderer may use `layout`; nothing else may.

**3. Facts and state are different things.**
"There is a lever here" is a fact. "That lever is thrown" is state, true for
everyone and gone at the daily reset. Only facts live in the JSON. State belongs
to a running session.

**4. Every claim carries its source.**
`src: "shrine:stoneworks-1"` versus `src: "walked:2026-08-16"`. This is what
makes disagreement detection possible: when the game contradicts the map, you
need to know whether you are arguing with a 30-year-old drawing of a different
version or with something you walked yourself last week.

**5. A key is a relation, and a coupling is an edge that is not an exit.**
The single most load-bearing finding of the survey. A door names the key that
opens it; a room names the key it yields; a lever in one room disarms a trap in
another. All three are links between two named rooms, and none is an exit.

## Shape

```jsonc
{
  "area": "stoneworks-1",
  "name": "The Stoneworks, Level 1",
  "region": "stoneworks",          // optional: levels of one place
  "level": 1,
  "src": "shrine:stoneworks-level-1",   // default for everything below
  "rooms": [
    {
      "id": "stoneworks-1/entry-chamber",
      "name": "stonework chamber",        // what the game prints
      "description": "...",               // optional; carries doors and devices
      "spawn": false,                     // town 1's `*`
      "dark": false,

      "exits": {
        "n":  { "to": "desert/desert-22" },
        "e":  { "to": "stoneworks-1/corridor-1" },
        "s":  { "to": null },             // known to exist, never walked
        "w":  { "to": "stoneworks-1/corridor-9",
                "door": { "material": "stone", "key": "iron" },
                "hidden": true },         // the room's description denies it

        // Some ways are gated by what you CARRY rather than by a lock you open:
        // "Green Rune required to enter Town 3". Unlike a key it is not spent
        // on a door, so a router must check possession, not unlocking.
        "sw": { "to": "third-town/town-square", "requires": ["green rune"] },

        // And some are gated by an action taken elsewhere -- a chasm that only
        // opens when a lever two rooms away is pulled.
        "ne": { "to": "stoneworks-6/beyond-west-chasm",
                "opened_by": "stoneworks-6/lever-6" }
      },

      // Things you do here. Covers devices AND remote couplings, because they
      // are the same shape: a verb, an effect, and where the effect lands.
      "actions": [
        { "verb": "say komi",    "effect": "gate",     "target": "stoneworks-1/entry-chamber#e" },
        { "verb": "pull lever",  "effect": "disarm",   "target": "stoneworks-1/corridor-14" },
        { "verb": "push stone",  "effect": "teleport", "target": "stoneworks-1/corridor-30" },
        { "verb": "push stone",  "effect": "signal",   "target": null,
          "note": "the floor vibrates faintly; effect not yet located" }
      ],

      "guardian": { "monster": "cyclops", "count": 2, "yields": ["bronze key"] },

      // `disarm` names the action that turns it off, or null for one that
      // cannot be -- stoneworks level 6 is drawn with "traps that can't be
      // turned off", against levels 1-5 where each has its own lever.
      "trap":     { "type": "falling stone", "damage": 180, "remedy": "rope",
                    "disarm": "stoneworks-1/lever-room" },
      "items":    ["white rune"],       // a rune lies in a room; see `requires`
      "notes":    ["`say arok` is needed again on the way back"],

      "layout":   { "x": 0, "y": 0 },     // drawing only, never identity
      "src":      "walked:2026-08-16"     // overrides the file default
    }
  ]
}
```

### Field notes

- **`exits`** is keyed by direction, which is unique per room. `to: null` means
  *known to exist, not yet walked* — the frontier state, and the thing a mapper
  needs to represent honestly rather than by omission.
- **`u`/`d`** are ordinary exits. Depth is derivable by counting them from an
  anchor and is not stored, since a stored depth is only ever a stale copy.
- **`passage`** (the ferry) is an exit whose reverse is itself.
- **`actions[].target`** is a room id, or `room#direction` when the effect lands
  on an exit, or `null` when the effect is known to exist but not yet located —
  which is a real state, and better recorded than dropped.
- **`effect`** is one of `gate` (opens a way), `disarm`, `teleport`, `signal`
  (something happened elsewhere, unlocated). A `gate` action and the exit's
  `opened_by` are the same fact from both ends, so a scraper writes both and a
  checker can cross-examine them.
- **`exits[].requires`** is possession, not unlocking: you must be carrying the
  green rune to enter third town, and you still have it afterwards. Distinct
  from `door.key`, which opens a specific lock. Runes also gate things
  *negatively* -- the arena refuses you once you carry one -- so a router needs
  them as state either way.
- **`guardian.yields`** is the source end of a key relation; a door's
  `door.key` is the far end. A router joins them.

## Open questions

1. **Two rooms, one fingerprint.** `stone-lvl-3` and `-4` both start from a
   "stonework chamber" with exits `{w,u}`, so a name+exit-set lookup is
   ambiguous. Stable ids fix this for routes, but the *live* "which room am I
   in" problem remains, and it is the one that broke three sessions.
2. **How much does provenance need to nest?** Per-room and per-exit is proposed.
   Per-field would be heavier and might be needed for a room walked recently
   whose door data came from a drawing.
3. **Where does `layout` come from?** Generated once by a layout pass and then
   hand-adjustable, or always generated? Hand-adjustable means it must survive
   a re-scrape, which means it needs its own file.
