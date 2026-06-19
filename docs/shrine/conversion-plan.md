# Shrine Conversion Plan

## Goal

Archive pages from [tele-arena.tumblr.com](https://tele-arena.tumblr.com/) as local markdown files. The game is over 30 years old and the content could disappear at any time.

## File naming

Derive the filename from the link label in `README.md`:

- Uppercase the label
- Replace spaces with underscores
- Add `.md` extension

Examples:
- `[Max Stats](...)` → `MAX_STATS.md`
- `[Promoted Exp Chart](...)` → `PROMOTED_EXP_CHART.md`
- `[Weapons & Armor](...)` → `WEAPONS_ARMOR.md`

## Page structure

Each converted file follows this structure:

```
# Title of Page (title case, from the page's main header)

*Source: [TELE-ARENA SHRINE](https://tele-arena.tumblr.com/<slug>)*

<verbatim free text, if any>

## Section Header (title case, from the page's section headers)

| Col1 | Col2 | ... |
|------|------|-----|
| ...  | ...  | ... |

<verbatim free text, if any>
```

## Rules

**Drop:** The site-wide navigation block that appears on every page (the `|`-separated list of links).

**Header conversion:**
- Main page header → `#` (title case)
- Table/section headers → `##` (title case)

**Tables:** Convert to standard markdown tables. Use the actual column headers from the page — do not invent or rename columns.

**Free text:** Copy verbatim. Do not paraphrase, summarize, or rewrite prose that appears outside tables.

**Source link:** Add an italicized source line at the top of every file pointing back to the original Tumblr URL.

## README updates

After creating a local file, update `README.md` to replace the Tumblr URL with a relative link to the local file:

```markdown
* [Max Stats](MAX_STATS.md)
```

## Workflow

1. Fetch the target URL with WebFetch
2. Write the local `.md` file
3. Update `README.md` to point to the local file
4. Commit

## Pages completed

- [Max Stats](MAX_STATS.md)
- [Weapons & Armor](WEAPONS_ARMOR.md)
- [Magic Items](MAGIC_ITEMS.md)
- [Spells](SPELLS.md)
- [Promotions](PROMOTIONS.md)
- [Promoted Exp Chart](PROMOTED_EXP_CHART.md)
