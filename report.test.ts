import { describe, expect, it } from 'bun:test';

/**
 * Run the report's inline script against a stub DOM and fail if it throws.
 *
 * A syntax check would not have caught the bug this exists for: the defect bar
 * read `overlaps` before the line that fills it had run, which is valid
 * JavaScript and a TypeError at load. The whole script died and the map
 * rendered nothing -- and nothing in the build noticed, because report.html was
 * written successfully.
 */
function runReportScript(html: string): void {
  const m = html.match(/<script>([\s\S]*?)<\/script>\s*<\/body>/) ?? html.match(/<script>([\s\S]*?)<\/script>/);
  if (!m) throw new Error('report.html has no inline script');

  const el = (): any => ({
    style: {}, dataset: {}, classList: { add() {}, remove() {}, toggle() {} },
    setAttribute() {}, getAttribute() { return null; }, removeAttribute() {},
    appendChild() {}, removeChild() {}, addEventListener() {}, remove() {},
    getBoundingClientRect: () => ({ x: 0, y: 0, width: 800, height: 600, top: 0, left: 0 }),
    querySelector: () => null, querySelectorAll: () => [],
    set innerHTML(_v: string) {}, get innerHTML() { return ''; },
    set textContent(_v: string) {}, get textContent() { return ''; },
    children: [], firstChild: null, parentNode: null,
  });
  const doc: any = {
    getElementById: () => el(), createElement: () => el(), createElementNS: () => el(),
    createTextNode: () => el(), createDocumentFragment: () => el(),
    querySelector: () => el(), querySelectorAll: () => [], addEventListener() {},
    body: el(), documentElement: el(),
  };
  const win: any = { addEventListener() {}, localStorage: { getItem: () => null, setItem() {} },
                     devicePixelRatio: 1, innerWidth: 1200, innerHeight: 800 };
  new Function('document', 'window', 'localStorage', 'requestAnimationFrame', m[1])(
    doc, win, win.localStorage, (fn: any) => fn());
}

describe('report.html', () => {
  it('runs without throwing', async () => {
    expect(() => runReportScript(Bun.file('report.html') as any)).toBeDefined();
    const html = await Bun.file('report.html').text();
    runReportScript(html);   // throws if the page would die on load
  });

  it('carries the defect payload the page needs', async () => {
    const html = await Bun.file('report.html').text();
    const g = JSON.parse(html.match(/var GRAPH = (\{[\s\S]*?\});/)![1]);
    expect(Array.isArray(g.rooms)).toBe(true);
    for (const r of g.rooms) expect(Array.isArray(r.defects)).toBe(true);
  });
});
