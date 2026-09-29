const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

// Exercise the same DOM-independent model embedded in the standalone prototype.
const html = fs.readFileSync(path.join(__dirname, '../dev-docs/layout-prototype.html'), 'utf8');
const source = html.match(/<script id="layout-logic">([\s\S]*?)<\/script>/)[1];
const context = vm.createContext({ structuredClone });
vm.runInContext(`${source}\nglobalThis.model = Layout;`, context);
const Layout = context.model;
const plain = value => JSON.parse(JSON.stringify(value));
const center = rect => ({ x: rect.x + rect.w / 2, y: rect.y + rect.h / 2 });
const frame = (session, id) => Layout.frames(session.state).find(rect => rect.id === id);
const root = session => plain(session.state.displays[0].root);

function assertValid(session) {
  const state = session.state;
  for (const display of state.displays) assert(Layout.valid(state, display));
  const ids = state.displays.flatMap(display => Layout.ids(display.root));
  assert.equal(ids.length, new Set(ids).size);
  assert.deepEqual(ids.slice().sort(), Object.values(state.windows)
    .filter(window => window.mode === 'tiled' && window.display != null).map(window => window.id).sort());
}

test('another owner with matching window IDs cannot cancel a gesture or preview', () => {
  const first = new Layout.DisplayLayoutState();
  first.begin({ id: 3 });
  first.move(center(frame(first, 1)));
  first.move(center(Layout.display(first.state, 'B')));
  const gesture = first.gesture;
  const preview = plain(gesture.preview);
  const second = new Layout.DisplayLayoutState();
  second.begin({ id: 3 });
  second.dispatch({ type: 'delete', id: 3 });
  second.release();
  assert.equal(first.gesture, gesture);
  assert.deepEqual(plain(first.gesture.preview), preview);
  assert(first.state.windows[3]);
  assert(!second.state.windows[3]);
});

test('creation cancels live swaps before inserting and stale movement cannot replay them', () => {
  const session = new Layout.DisplayLayoutState();
  const expected = Layout.reduce(session.state, { type: 'create' });
  const original = root(session);
  session.begin({ id: 3 });
  session.move(center(frame(session, 1)));
  assert.notDeepEqual(root(session), original);
  session.dispatch({ type: 'create' });
  assert.equal(session.gesture, null);
  assert(session.blocked);
  session.move(center(Layout.display(session.state, 'B')));
  assert.equal(session.begin({ id: 1 }), false);
  session.release();
  assert.deepEqual(plain(session.state), plain(expected));
  assert.equal(session.begin({ id: 1 }), true);
});

test('close and screen disconnection survive stale release and cancellation', () => {
  for (const action of [{ type: 'delete', id: 3 }, { type: 'disconnect', display: 'A' }]) {
    const session = new Layout.DisplayLayoutState();
    const expected = Layout.reduce(session.state, action);
    session.begin({ id: 3 });
    session.move(center(Layout.display(session.state, 'B')));
    assert(session.gesture.preview);
    session.dispatch(action);
    session.release(true);
    session.cancel();
    assert.deepEqual(plain(session.state), plain(expected));
    assertValid(session);
  }
});

test('cross-screen release discards incidental source swaps', () => {
  const session = new Layout.DisplayLayoutState();
  const expected = Layout.reduce(session.state, { type: 'transfer', id: 3, destination: 'B' });
  session.begin({ id: 3 });
  session.move(center(frame(session, 1)));
  session.move(center(Layout.display(session.state, 'B')));
  assert.equal(session.state.windows[3].display, 'A');
  session.release();
  assert.deepEqual(plain(session.state), plain(expected));
  assertValid(session);
});

test('leaving a screen clears the target latch before returning', () => {
  const initial = Layout.reduce(Layout.seed(), { type: 'delete', id: 3 });
  const session = new Layout.DisplayLayoutState(Layout.reduce(initial, { type: 'ratio', display: 'A', path: '', ratio: .3 }));
  const original = root(session);
  session.begin({ id: 1 });
  session.move(center(frame(session, 2)));
  assert.notDeepEqual(root(session), original);
  session.move(center(Layout.display(session.state, 'B')));
  session.move(center(frame(session, 2)));
  session.release();
  assert.deepEqual(root(session).children, original.children);
  assert(Math.abs(root(session).ratio - original.ratio) < 1e-9);
  assertValid(session);
});

test('resize cancellation restores the snapshot and outside-screen release cancels', () => {
  const session = new Layout.DisplayLayoutState();
  const initial = plain(session.state);
  const split = Layout.geometry(session.state).splits[0];
  const start = center(split.divider);
  session.begin({ kind: 'split', point: start, split });
  session.move({ x: start.x + 100, y: start.y });
  assert.notDeepEqual(root(session), plain(initial.displays[0].root));
  assertValid(session);
  session.release(true);
  assert.deepEqual(plain(session.state), initial);
  session.begin({ id: 3 });
  session.move({ x: -100, y: -100 });
  session.release();
  assert.deepEqual(root(session), plain(initial.displays[0].root));
});
