// Fetch the shrine's hand-drawn maps and keep them verbatim under map/shrine/.
//
// The <pre> block IS the data: in an ASCII map the column of a character is
// what says which room a connector joins. So this saves raw text and never
// reformats, re-indents or strips trailing space. Parsing happens later, from
// these files, so a parser change never needs the network and the source
// survives the site going away.

export const MAPS: { slug: string; url: string; title: string }[] = [
  { slug: 'town-1',   url: 'https://tele-arena.tumblr.com/town1',    title: 'Town 1' },
  { slug: 'dungeon-1', url: 'https://tele-arena.tumblr.com/dungeon1', title: 'Dungeon Level 1' },
  { slug: 'dungeon-2', url: 'https://tele-arena.tumblr.com/dungeon2', title: 'Dungeon Level 2' },
  { slug: 'dungeon-3', url: 'https://tele-arena.tumblr.com/dungeon3', title: 'Dungeon Level 3' },
  { slug: 'town-2',   url: 'https://tele-arena.tumblr.com/town2',    title: 'Town 2' },
  { slug: 'sewers-1', url: 'https://tele-arena.tumblr.com/sewers1',  title: 'Sewers Level 1' },
  { slug: 'sewers-2', url: 'https://tele-arena.tumblr.com/sewers2',  title: 'Sewers Level 2' },
  { slug: 'sewers-3', url: 'https://tele-arena.tumblr.com/sewers3',  title: 'Sewers Level 3' },
  { slug: 'desert',   url: 'https://tele-arena.tumblr.com/desert',   title: 'The Desert' },
];

const ENTITIES: Record<string, string> = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ',
};

/**
 * Pull the map out of a page. Only tags are removed and entities decoded --
 * every space is load-bearing, so nothing is trimmed except a trailing blank
 * line, and lines keep their exact leading and interior whitespace.
 */
export function extractPre(html: string): string | null {
  const m = html.match(/<pre[^>]*>([\s\S]*?)<\/pre>/i);
  if (!m) return null;
  const text = m[1]
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
    .replace(/&[a-z]+;/gi, e => ENTITIES[e.toLowerCase()] ?? e);
  return text.replace(/^\n+/, '').replace(/\s+$/, '') + '\n';
}

if (import.meta.main) {
  const { mkdirSync } = await import('node:fs');
  mkdirSync('map/shrine', { recursive: true });
  let failed = 0;
  for (const { slug, url, title } of MAPS) {
    try {
      const res = await fetch(url, { headers: { 'user-agent': 'baud-script-for-tele-arena (map archival)' } });
      if (!res.ok) { console.error(`  ${slug.padEnd(11)} HTTP ${res.status}`); failed++; continue; }
      const pre = extractPre(await res.text());
      if (!pre) { console.error(`  ${slug.padEnd(11)} no <pre> block found`); failed++; continue; }
      const header = `# ${title}\n# ${url}\n# fetched ${new Date().toISOString().slice(0, 10)}\n\n`;
      await Bun.write(`map/shrine/${slug}.txt`, header + pre);
      const boxes = (pre.match(/\[[^\]]*\]/g) ?? []).length;
      console.log(`  ${slug.padEnd(11)} ${String(pre.split('\n').length).padStart(3)} lines, ${String(boxes).padStart(3)} boxes`);
    } catch (e) {
      console.error(`  ${slug.padEnd(11)} ${(e as Error).message}`); failed++;
    }
  }
  process.exit(failed === 0 ? 0 : 1);
}
