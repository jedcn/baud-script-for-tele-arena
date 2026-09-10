// Fetch the shrine's hand-drawn maps and keep them verbatim under map/shrine/.
//
// The <pre> block IS the data: in an ASCII map the column of a character is
// what says which room a connector joins. So this saves raw text and never
// reformats, re-indents or strips trailing space. Parsing happens later, from
// these files, so a parser change never needs the network and the source
// survives the site going away.

export const MAPS: { slug: string; url: string; title: string }[] = [
  { slug: 'world-map', url: 'https://tele-arena.tumblr.com/worldmap', title: 'World Map' },
  { slug: 'town-1', url: 'https://tele-arena.tumblr.com/town1', title: 'Town 1' },
  { slug: 'dungeon-1', url: 'https://tele-arena.tumblr.com/dungeon1', title: 'Dungeon 1' },
  { slug: 'dungeon-2', url: 'https://tele-arena.tumblr.com/dungeon2', title: 'Dungeon 2' },
  { slug: 'dungeon-3', url: 'https://tele-arena.tumblr.com/dungeon3', title: 'Dungeon 3' },
  { slug: 'mountains', url: 'https://tele-arena.tumblr.com/mountains', title: 'Mountains' },
  { slug: 'orc-caves', url: 'https://tele-arena.tumblr.com/orccaves', title: 'Orc Caves' },
  { slug: 'forest', url: 'https://tele-arena.tumblr.com/forest', title: 'Forest' },
  { slug: 'gnoll-caves', url: 'https://tele-arena.tumblr.com/gnollcaves', title: 'Gnoll Caves' },
  { slug: 'tower', url: 'https://tele-arena.tumblr.com/tower', title: 'Tower' },
  { slug: 'swamp', url: 'https://tele-arena.tumblr.com/swamp', title: 'Swamp' },
  { slug: 'cellars', url: 'https://tele-arena.tumblr.com/cellars', title: 'Cellars' },
  { slug: 'town-2', url: 'https://tele-arena.tumblr.com/town2', title: 'Town 2' },
  { slug: 'sewers-1', url: 'https://tele-arena.tumblr.com/sewers1', title: 'Sewers 1' },
  { slug: 'sewers-2', url: 'https://tele-arena.tumblr.com/sewers2', title: 'Sewers 2' },
  { slug: 'sewers-3', url: 'https://tele-arena.tumblr.com/sewers3', title: 'Sewers 3' },
  { slug: 'desert', url: 'https://tele-arena.tumblr.com/desert', title: 'Desert' },
  { slug: 'stoneworks-1', url: 'https://tele-arena.tumblr.com/stoneworks1', title: 'Stoneworks 1' },
  { slug: 'stoneworks-2', url: 'https://tele-arena.tumblr.com/stoneworks2', title: 'Stoneworks 2' },
  { slug: 'stoneworks-3', url: 'https://tele-arena.tumblr.com/stoneworks3', title: 'Stoneworks 3' },
  { slug: 'stoneworks-4', url: 'https://tele-arena.tumblr.com/stoneworks4', title: 'Stoneworks 4' },
  { slug: 'stoneworks-5', url: 'https://tele-arena.tumblr.com/stoneworks5', title: 'Stoneworks 5' },
  { slug: 'stoneworks-6', url: 'https://tele-arena.tumblr.com/stoneworks6', title: 'Stoneworks 6' },
  { slug: 'flagstones-1', url: 'https://tele-arena.tumblr.com/flagstones1', title: 'Flagstones 1' },
  { slug: 'flagstones-2', url: 'https://tele-arena.tumblr.com/flagstones2', title: 'Flagstones 2' },
  { slug: 'flagstones-3', url: 'https://tele-arena.tumblr.com/flagstones3', title: 'Flagstones 3' },
  { slug: 'town-3', url: 'https://tele-arena.tumblr.com/town3', title: 'Town 3' },
  { slug: 'labyrinth-1', url: 'https://tele-arena.tumblr.com/labyrinth1', title: 'Labyrinth 1' },
  { slug: 'labyrinth-2', url: 'https://tele-arena.tumblr.com/labyrinth2', title: 'Labyrinth 2' },
  { slug: 'labyrinth-3', url: 'https://tele-arena.tumblr.com/labyrinth3', title: 'Labyrinth 3' },
  { slug: 'labyrinth-4', url: 'https://tele-arena.tumblr.com/labyrinth4', title: 'Labyrinth 4' },
  { slug: 'labyrinth-5', url: 'https://tele-arena.tumblr.com/labyrinth5', title: 'Labyrinth 5' },
  { slug: 'tunnels', url: 'https://tele-arena.tumblr.com/tunnels', title: 'Tunnels' },
  { slug: 'ledge', url: 'https://tele-arena.tumblr.com/ledge', title: 'Ledge' },
  { slug: 'sweltering', url: 'https://tele-arena.tumblr.com/sweltering', title: 'Sweltering' },
  { slug: 'hewn-granite', url: 'https://tele-arena.tumblr.com/hewngranite', title: 'Hewn Granite' },
  { slug: 'valley', url: 'https://tele-arena.tumblr.com/valley', title: 'Valley' },
  { slug: 'complex-caverns-1', url: 'https://tele-arena.tumblr.com/complexcaverns1', title: 'Complex Caverns 1' },
  { slug: 'complex-caverns-2', url: 'https://tele-arena.tumblr.com/complexcaverns2', title: 'Complex Caverns 2' },
  { slug: 'complex-caverns-3', url: 'https://tele-arena.tumblr.com/complexcaverns3', title: 'Complex Caverns 3' },
  { slug: 'complex-caverns-4', url: 'https://tele-arena.tumblr.com/complexcaverns4', title: 'Complex Caverns 4' },
  { slug: 'deep-forest', url: 'https://tele-arena.tumblr.com/deepforest', title: 'Deep Forest' },
  { slug: 'town-4', url: 'https://tele-arena.tumblr.com/town4', title: 'Town 4' },
  { slug: 'stone-passages-1', url: 'https://tele-arena.tumblr.com/stonepassages1', title: 'Stone Passages 1' },
  { slug: 'stone-passages-2', url: 'https://tele-arena.tumblr.com/stonepassages2', title: 'Stone Passages 2' },
  { slug: 'stone-passages-3', url: 'https://tele-arena.tumblr.com/stonepassages3', title: 'Stone Passages 3' },
  { slug: 'stone-passages-4', url: 'https://tele-arena.tumblr.com/stonepassages4', title: 'Stone Passages 4' },
  { slug: 'stone-passages-5', url: 'https://tele-arena.tumblr.com/stonepassages5', title: 'Stone Passages 5' },
  { slug: 'stone-passages-6', url: 'https://tele-arena.tumblr.com/stonepassages6', title: 'Stone Passages 6' },
  { slug: 'stone-passages-7', url: 'https://tele-arena.tumblr.com/stonepassages7', title: 'Stone Passages 7' },
  { slug: 'stone-passages-8', url: 'https://tele-arena.tumblr.com/stonepassages8', title: 'Stone Passages 8' },
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
