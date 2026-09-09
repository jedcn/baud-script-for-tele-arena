import { describe, expect, it } from 'bun:test';
import { mapForArea } from './where';

describe('mapForArea', () => {
  it('finds the shrine map covering an area we have walked', () => {
    expect(mapForArea('first-dungeon-level-1')?.name).toBe('dungeon-1');
    expect(mapForArea('sewers-level-2')?.name).toBe('sewers-2');
  });
  // The desert and the stoneworks have drawings but no database side, so
  // nothing to reconcile against and nothing to point at yet.
  it('returns null for an area with no reconciliation', () => {
    expect(mapForArea('desert')).toBeNull();
    expect(mapForArea('stoneworks')).toBeNull();
  });
});
