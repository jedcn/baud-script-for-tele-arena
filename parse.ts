// Turn a shrine ASCII map into rooms and connections.
//
// The drawing is a grid: a box `[X]` is a room, and the runs of `-`, `|`, `/`
// and `\` between boxes are the ways between them. So parsing is a walk over
// character cells -- start beside a box, follow a run of one connector
// character, and see which box you arrive at.
//
// Two things the format does NOT give, and which callers must supply from
// elsewhere:
//   - room names. 651 of the 755 boxes are a bare `[ ]`.
//   - true compass directions for vertical links. A stair is drawn as an
//     ordinary connector; only the `^`/`v` badges on the boxes say it is one.
//     Those edges are marked `vertical: true` for the caller to resolve.

// `start`/`end` are the bracket columns; `col` is the centre. Boxes are not all
// three characters wide -- `[Av]` and `[L6]` are four -- so a connector's
// attachment point has to be measured from the edge, not from centre +/- 2.
export type Box = { index: number; row: number; start: number; end: number; col: number;
                    label: string; badge: string };
export type Edge = { from: number; to: number; dir: string; vertical: boolean; glyph: string; door?: string };
export type ParsedMap = { boxes: Box[]; edges: Edge[]; legend: Record<string, string> };

const CONNECTORS = '-|/\\';

/** Compass direction from one grid offset to another, in drawing space. */
export function directionOf(dRow: number, dCol: number): string {
  const ns = dRow < 0 ? 'n' : dRow > 0 ? 's' : '';
  const ew = dCol < 0 ? 'w' : dCol > 0 ? 'e' : '';
  return ns + ew;
}

/** `[V^]` -> label "V", badge "^".  `[ ]` -> label "", badge "". */
function splitBox(inner: string): { label: string; badge: string } {
  const m = inner.match(/^(.*?)([\^v]*)$/);
  const label = (m?.[1] ?? inner).trim();
  return { label, badge: m?.[2] ?? '' };
}

export function findBoxes(lines: string[]): Box[] {
  const boxes: Box[] = [];
  lines.forEach((line, row) => {
    for (const m of line.matchAll(/\[([^\]]*)\]/g)) {
      const { label, badge } = splitBox(m[1]);
      // The column of the box's centre character, which is what connectors
      // line up against.
      const start = m.index!, end = m.index! + m[0].length - 1;
      boxes.push({ index: boxes.length, row, start, end,
                   col: Math.floor((start + end) / 2), label, badge });
    }
  });
  return boxes;
}

/**
 * Follow a connector run from one box and report the box it reaches.
 * `step` is the per-cell delta implied by the connector glyph.
 */
function followRun(lines: string[], boxAt: Map<string, Box>, startRow: number, startCol: number,
                   dRow: number, dCol: number, glyph: string): Box | null {
  let row = startRow, col = startCol, steps = 0;
  while (steps++ < 200) {
    const ch = lines[row]?.[col];
    if (ch === undefined) return null;
    const hit = boxAt.get(`${row},${col}`);
    if (hit) return hit;
    // A run may be padded with spaces (`[ ]     [ ]` joined by a long `-` run
    // is rare, but `|` runs skip blank rows in some maps) and may bend where a
    // diagonal meets a vertical, so accept the glyph, its family, or a space.
    // A run must stay on its own glyph. Allowing spaces let a diagonal drift
    // through a gap and attach to an unrelated box -- that is how the town 1
    // parse invented an arena-to-guild-hall edge.
    if (ch !== glyph) return null;
    row += dRow; col += dCol;
  }
  return null;
}

export function parseMap(text: string): ParsedMap {
  const all = text.split('\n');
  const body = all.filter(l => !l.startsWith('#'));
  // The legend starts at the first line that looks like `X = something`.
  const legendAt = body.findIndex(l => /^\s*\S{1,3}\s*=\s*\S/.test(l));
  const lines = legendAt === -1 ? body : body.slice(0, legendAt);
  const legend: Record<string, string> = {};
  // A legend line can carry more than one entry -- sewers level 2 pairs the key
  // and its door on the same line ("o = Onyx key          O = Onyx key door").
  // Taking the line as a single entry lost every door glyph on that map.
  for (const l of legendAt === -1 ? [] : body.slice(legendAt))
    for (const m of l.matchAll(/(\S{1,3})\s*=\s*(.*?)(?=\s{2,}\S{1,3}\s*=|\s*$)/g))
      if (m[2]) legend[m[1]] = m[2].trim();

  const boxes = findBoxes(lines);
  // Every cell a box occupies, so a run knows when it has arrived.
  const boxAt = new Map<string, Box>();
  for (const b of boxes)
    for (let c = b.col - 1; c <= b.col + 1; c++) boxAt.set(`${b.row},${c}`, b);

  const seen = new Set<string>();
  const edges: Edge[] = [];
  for (const b of boxes) {
    // Look one cell out from the box in each of the eight directions; a
    // connector there begins a run.
    for (const [dRow, dCol] of [[0, 1], [0, -1], [-1, 0], [1, 0], [-1, 1], [-1, -1], [1, 1], [1, -1]]) {
      // Attach from the box's edge. These are hand drawings, so a diagonal is
      // as likely to sit directly under the bracket as one column outside it --
      // `[ ]` with `/ \` beneath at the bracket columns is a common fork, and
      // insisting on the outside column alone left those boxes unconnected.
      const row = b.row + dRow;
      const cols = dCol > 0 ? [b.end + 1, b.end] : dCol < 0 ? [b.start - 1, b.start] : [b.col];
      let col = -1, ch = '';
      for (const c of cols) {
        const candidate = lines[row]?.[c];
        if (candidate && CONNECTORS.includes(candidate)) { col = c; ch = candidate; break; }
      }
      if (col === -1) continue;
      const other = followRun(lines, boxAt, row + dRow, col + dCol, dRow, dCol, ch);
      if (!other || other.index === b.index) continue;
      const key = [b.index, other.index].sort((x, y) => x - y).join('-');
      if (seen.has(key)) continue;
      seen.add(key);
      // A stair is drawn like any other connector; the badges are the only
      // hint. Flag it rather than guess a compass direction for it.
      const vertical = /[\^v]/.test(b.badge) && /[\^v]/.test(other.badge);
      edges.push({ from: b.index, to: other.index, glyph: ch, vertical,
                   dir: directionOf(other.row - b.row, other.col - b.col) });
    }
  }
  // A locked door is drawn as a marker sitting ON the way between two rooms:
  // `#` everywhere, and on sewers level 2 a letter the legend defines ("O =
  // Onyx key door"). It is not part of a run, and being hand-drawn it is often
  // a column off the true line -- dungeon 1's bronze door misses by one. So
  // markers get their own pass, joining the two nearest boxes on opposite
  // sides rather than following geometry exactly.
  const doorGlyphs = new Set<string>(['#']);
  for (const [glyph, meaning] of Object.entries(legend))
    if (glyph.length === 1 && /\bdoor\b/i.test(meaning)) doorGlyphs.add(glyph);

  lines.forEach((line, row) => {
    for (let col = 0; col < line.length; col++) {
      if (!doorGlyphs.has(line[col]) || boxAt.has(`${row},${col}`)) continue;
      const near = boxes
        .map(b => ({ b, d: Math.max(Math.abs(b.row - row), Math.min(Math.abs(b.start - col), Math.abs(b.end - col))) }))
        .filter(x => x.d <= 3)
        .sort((x, y) => x.d - y.d);
      // Opposite sides: one box before the marker in reading order, one after.
      const before = near.find(x => x.b.row < row || (x.b.row === row && x.b.end < col));
      const after = near.find(x => x.b.row > row || (x.b.row === row && x.b.start > col));
      if (!before || !after) continue;
      const key = [before.b.index, after.b.index].sort((x, y) => x - y).join('-');
      const existing = edges.find(e => [e.from, e.to].sort((x, y) => x - y).join('-') === key);
      const door = legend[line[col]] ?? 'locked door';
      if (existing) { existing.door = door; continue; }
      seen.add(key);
      edges.push({ from: before.b.index, to: after.b.index, glyph: line[col], door,
                   vertical: /[\^v]/.test(before.b.badge) && /[\^v]/.test(after.b.badge),
                   dir: directionOf(after.b.row - before.b.row, after.b.col - before.b.col) });
    }
  });

  return { boxes, edges, legend };
}
