import { describe, expect, it } from 'bun:test';
import { extractPre, MAPS } from './scrape';

describe('extractPre', () => {
  // Column position is what says which rooms a connector joins, so leading and
  // interior whitespace is data, not formatting.
  it('preserves leading and interior spacing exactly', () => {
    const out = extractPre('<pre>   [ ]-[ ]\n      \\\n       [ ]</pre>');
    expect(out).toBe('   [ ]-[ ]\n      \\\n       [ ]\n');
  });

  it('decodes the entities a map actually contains', () => {
    expect(extractPre('<pre>[&lt;]&amp;[&gt;]&nbsp;&#42;</pre>')).toBe('[<]&[>] *\n');
  });

  it('turns <br> into a newline and drops other tags', () => {
    expect(extractPre('<pre>[a]<br/><span>[b]</span></pre>')).toBe('[a]\n[b]\n');
  });

  it('strips leading blank lines but keeps one trailing newline', () => {
    expect(extractPre('<pre>\n\n[ ]\n\n\n</pre>')).toBe('[ ]\n');
  });

  it('returns null when the page has no map', () => {
    expect(extractPre('<html><body>no map here</body></html>')).toBeNull();
  });

  it('takes the first pre block when a page has several', () => {
    expect(extractPre('<pre>[a]</pre><pre>[b]</pre>')).toBe('[a]\n');
  });
});

describe('MAPS', () => {
  it('has a unique slug per map and only shrine URLs', () => {
    expect(new Set(MAPS.map(m => m.slug)).size).toBe(MAPS.length);
    for (const m of MAPS) expect(m.url).toStartWith('https://tele-arena.tumblr.com/');
  });
});
