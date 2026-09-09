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
