import { describe, expect, it } from 'bun:test';
import { annotate } from './annotate';

describe('annotate', () => {
  it('marks a box without disturbing the drawing around it', () => {
    expect(annotate('[a]-[b]', new Map([[1, '?']]))).toBe('[a]-[?]');
  });
  it('keeps the brackets so it still reads as a map', () => {
    expect(annotate('[Av]', new Map([[0, '!']]))).toBe('[! ]');
  });
  it('leaves unmarked boxes alone', () => {
    expect(annotate('[a]\n |\n[b]', new Map())).toBe('[a]\n |\n[b]');
  });
});

import { findChecked } from './annotate';

describe('findChecked', () => {
  const checked = [{ area: 'first-dungeon-level-1', room: 'cave-31', direction: 'se',
                     verdict: 'drawing-wrong', when: '2026-09-09' }];
  it('marks a conflict that has been settled in game', () => {
    expect(findChecked(checked, 'first-dungeon-level-1', 'cave-31',
      'the drawing goes se from here to a room we cannot reach')?.verdict).toBe('drawing-wrong');
  });
  it('does not match a different direction from the same room', () => {
    expect(findChecked(checked, 'first-dungeon-level-1', 'cave-31',
      'the drawing goes nw from here')).toBeUndefined();
  });
  it('does not match the same room name in another area', () => {
    expect(findChecked(checked, 'sewers-level-1', 'cave-31', 'the drawing goes se')).toBeUndefined();
  });
});
