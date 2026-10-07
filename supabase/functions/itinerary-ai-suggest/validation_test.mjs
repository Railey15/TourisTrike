import assert from 'node:assert/strict';
import test from 'node:test';
import { isExactSelectedDestinationOrder } from './validation.mjs';

const selected = ['a', 'b', 'c'];
test('AI may reorder exactly the selected destinations', () => {
  assert.equal(isExactSelectedDestinationOrder(['b', 'a', 'c'], selected), true);
});
test('unknown, missing, and duplicate IDs are rejected', () => {
  for (const order of [['b', 'x', 'c'], ['a', 'b'], ['a', 'a', 'b']]) {
    assert.equal(isExactSelectedDestinationOrder(order, selected), false);
  }
});
