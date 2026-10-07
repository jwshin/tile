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

test('native resize keeps the held frame through refresh before and after observation', () => {
  for (const axis of ['x', 'y']) {
    const session = new Layout.DisplayLayoutState();
    const before = frame(session, 3);
    const original = root(session);
    session.dispatch({ type: 'nativeResizeStart', id: 3, axis, amount: 80 });
    const native = plain(session.visibleFrames().find(rect => rect.id === 3));
    assert.equal(native[axis === 'x' ? 'w' : 'h'], before[axis === 'x' ? 'w' : 'h'] + 80);
    session.dispatch({ type: 'nativeResizeRefresh' });
    assert.deepEqual(root(session), original);
    assert.deepEqual(plain(session.visibleFrames().find(rect => rect.id === 3)), native);
    assert(!session.layoutWrites().some(rect => rect.id === 3));
    session.dispatch({ type: 'nativeResizeObserve' });
    assert(Math.abs(frame(session, 3)[axis] - native[axis]) < 1e-9);
    for (let i = 0; i < 3; i++) session.dispatch({ type: 'nativeResizeRefresh' });
    assert(!session.layoutWrites().some(rect => rect.id === 3));
    session.dispatch({ type: 'nativeResizeRelease' });
    assert(session.layoutWrites().some(rect => rect.id === 3));
    assert(Math.abs(frame(session, 3)[axis] - native[axis]) < 1e-9);
    assertValid(session);
  }
});

// Run the real input adapter with rendering stubbed out; coordinates stay in model units.
function pointerFixture() {
  const elements = new Map();
  const listeners = new Map();
  let copied = null;
  const window = { addEventListener: listen };
  function makeElement(tagName = 'div') {
    return {
      tagName: tagName.toUpperCase(), children: [], style: {}, dataset: {},
      classList: { toggle() {} }, setAttribute() {},
      append(...children) { this.children.push(...children); },
      replaceChildren(...children) { this.children = children; },
    };
  }
  function listen(type, handler) {
    if (!listeners.has(this)) listeners.set(this, new Map());
    const events = listeners.get(this);
    if (!events.has(type)) events.set(type, []);
    events.get(type).push(handler);
  }
  function emit(target, type, event = {}) {
    event = { button: 0, pointerId: 7, target, preventDefault() {}, ...event, type };
    for (const handler of listeners.get(target)?.get(type) ?? []) handler(event);
    if (target !== window) {
      for (const handler of listeners.get(window)?.get(type) ?? []) handler(event);
    }
  }
  function element(id) {
    if (id === 'ghost') return null;
    if (!elements.has(id)) elements.set(id, {
      ...makeElement(),
      value: id === 'view' ? 'all' : '', addEventListener: listen,
      getBoundingClientRect: () => ({ left: 0, top: 0, width: 2920, height: 900 }),
      setPointerCapture(pointerId) { this.capture = pointerId; },
      hasPointerCapture(pointerId) { return this.capture === pointerId; },
      releasePointerCapture(pointerId) { this.capture = null; emit(this, 'lostpointercapture', { pointerId }); },
    });
    return elements.get(id);
  }
  const context = vm.createContext({ structuredClone, window,
    navigator: { clipboard: { async writeText(text) { copied = text; } } }, document: {
    getElementById: element, querySelectorAll: () => [], createElement: makeElement,
  } });
  const ui = html.match(/<script id="prototype-ui">([\s\S]*?)<\/script>/)[1];
  vm.runInContext(`${source}\n${ui}\nfunction render() {}\nfunction showGhost() {}\nworld={x:0,y:0,w:2920,h:900};`, context);
  const api = window.LayoutPrototype;
  const board = element('board');
  function down(id = 3) {
    const rect = api.Layout.frames(api.state).find(rect => rect.id === id);
    const tile = {
      dataset: { window: id },
      closest: selector => selector === '[data-window]' ? tile : null,
      getBoundingClientRect: () => ({ left: rect.x, top: rect.y, width: rect.w, height: rect.h }),
    };
    emit(board, 'pointerdown', { target: tile, clientX: center(rect).x, clientY: center(rect).y });
  }
  function scenarioControls(name) {
    const index = vm.runInContext(`scenarios.findIndex(scenario => scenario.name === ${JSON.stringify(name)})`, context);
    assert(index >= 0);
    vm.runInContext('renderScenario()', context);
    element('tabs').children[index].onclick();
    vm.runInContext('renderScenario()', context);
    const controls = () => element('scenario').children.find(child => child.className === 'steps').children;
    return { controls, click(index) {
      assert.equal(controls()[index].disabled, false);
      controls()[index].onclick();
      vm.runInContext('renderScenario()', context);
    } };
  }
  return { api, down, emit, board, window, scenarioControls, element,
    get copied() { return copied; }, session: vm.runInContext('model', context) };
}

test('diagnostics controls preserve all window kinds, active gestures, and frozen evidence', async () => {
  const fixture = pointerFixture();
  const { api, element, session } = fixture;
  const scenario = fixture.scenarioControls('State diagnostics');
  for (let index = 0; index < 10; index++) {
    const label = scenario.controls()[index].textContent;
    const before = plain(session.diagnostics());
    const previous = element('diagnostics-report').textContent;
    scenario.click(index);
    if (label.includes('Capture')) {
      assert.deepEqual(plain(session.diagnostics()), before);
      const captured = JSON.parse(element('diagnostics-report').textContent);
      if (index === 4) {
        assert.equal(captured.state.windows[1].mode, 'tiled');
        assert.equal(captured.state.windows[3].mode, 'floating');
        assert.equal(captured.state.windows[4].mode, 'suspended');
      }
      if (index === 6) assert.equal(captured.gesture.id, 3);
      if (index === 9) assert.equal(captured.state.observationsPaused, true);
    } else assert.equal(element('diagnostics-report').textContent, previous);
  }
  const before = plain(session.diagnostics());
  element('capture-diagnostics').onclick();
  await element('copy-diagnostics').onclick();
  assert.equal(fixture.copied, element('diagnostics-report').textContent);
  assert.deepEqual(plain(session.diagnostics()), before);
  const detached = session.diagnostics();
  detached.state.windows[1].mode = 'changed copy';
  assert.equal(api.state.windows[1].mode, 'tiled');
  assert.equal(element('diagnostics-panel').open, true);
  assertValid({ state: api.state });
});

test('Claude eligibility guided controls retain dialog, fixed, overlay, and preference boundaries', () => {
  const fixture = pointerFixture();
  const scenario = fixture.scenarioControls('Claude window eligibility');
  scenario.click(0);
  assert.equal(fixture.api.state.windows[4].mode, 'tiled');
  assert.equal(fixture.api.state.windows[4].fullscreenButton, 'missing');
  scenario.click(1);
  assert.equal(fixture.api.state.windows[5].mode, 'tiled');
  assert.equal(fixture.api.state.windows[5].fullscreenButton, 'disabled');
  const tiled = plain(fixture.api.state.displays[0].root);
  scenario.click(2);
  assert.equal(fixture.api.state.windows[6].mode, 'floating');
  scenario.click(3);
  assert.equal(fixture.api.state.windows[7].mode, 'floating');
  scenario.click(4);
  assert.equal(fixture.api.state.windows[7].mode, 'floating');
  assert.match(fixture.api.state.message, /non-resizable/);
  const beforeOverlay = plain(fixture.api.state.windows);
  const focusBeforeOverlay = fixture.api.state.focused;
  scenario.click(5);
  assert.deepEqual(plain(fixture.api.state.windows), beforeOverlay);
  assert.equal(fixture.api.state.focused, focusBeforeOverlay);
  assert.match(fixture.api.state.message, /unmanaged/);
  scenario.click(6);
  assert.equal(fixture.api.state.windows[8].mode, 'floating');
  scenario.click(7);
  assert.equal(fixture.api.state.windows[4].mode, 'tiled');
  assert.equal(fixture.api.state.windows[5].mode, 'tiled');
  scenario.click(8);
  assert.equal(fixture.api.state.windows[9].mode, 'floating');
  assert.match(fixture.api.state.message, /app preference/);
  assert.deepEqual(plain(fixture.api.state.displays[0].root), tiled);
  assertValid({ state: fixture.api.state });
});

test('native discovery guided controls tile Chrome beside ChatGPT without notifications', () => {
  const fixture = pointerFixture();
  const scenario = fixture.scenarioControls('Native discovery without notifications');
  const initial = plain(fixture.api.state.displays[0].root);
  assert.equal(fixture.api.state.windows[1].bundleId, 'com.openai.codex');
  scenario.click(0);
  assert.deepEqual(plain(fixture.api.state.displays[0].root), initial);
  scenario.click(1);
  const chrome = fixture.api.state.nativeApps['com.google.Chrome'].windowId;
  assert.equal(fixture.api.state.nativeApps['com.google.Chrome'].notificationSetupDeferred, true);
  assert.equal(fixture.api.state.windows[chrome].bundleId, 'com.google.Chrome');
  assert.equal(fixture.api.state.windows[chrome].mode, 'tiled');
  assert.deepEqual(plain(fixture.api.Layout.ids(fixture.api.state.displays[0].root)), [1, chrome]);
  const tree = plain(fixture.api.state.displays[0].root);
  for (const step of [2, 3, 4, 5, 6, 7, 8]) {
    scenario.click(step);
    assert.deepEqual(plain(fixture.api.state.displays[0].root), tree);
    assert.equal(Object.keys(fixture.api.state.windows).length, 2);
    assert.equal(fixture.api.state.nativeApps['com.google.Chrome'].windowId, chrome);
    const support = fixture.api.state.nativeApps['com.google.Chrome'].subscribedNotifications;
    assert.equal(support, step < 6 ? 'none' : step < 8 ? 'partial' : 'all');
    if (step === 4 || step === 6 || step === 8) {
      assert.equal(fixture.api.state.nativeApps['com.google.Chrome'].notificationSetupDeferred, false);
    }
  }
  assertValid({ state: fixture.api.state });
});

test('native snapshot controls respect classification while notification support changes', () => {
  const { api, element } = pointerFixture();
  element('app-bundle').value = 'com.google.Chrome';
  element('kind').value = 'normal';
  element('fullscreen-button').value = 'enabled';
  element('native-notifications').value = 'none';
  element('native-readable').value = 'no';
  element('native-app').onclick();
  element('native-refresh').onclick();
  assert.equal(Object.keys(api.state.windows).length, 3);
  element('native-readable').value = 'yes';
  element('native-app').onclick();
  element('native-refresh').onclick();
  assert.equal(api.state.windows[4].mode, 'tiled');
  element('native-refresh').onclick();
  assert.equal(Object.keys(api.state.windows).length, 4);
  element('app-bundle').value = 'com.example.dialog';
  element('kind').value = 'dialog';
  element('native-app').onclick();
  element('native-refresh').onclick();
  assert.equal(api.state.windows[5].mode, 'floating');
  element('app-bundle').value = 'com.example.overlay';
  element('kind').value = 'overlay';
  element('native-app').onclick();
  element('native-refresh').onclick();
  assert.equal(Object.keys(api.state.windows).length, 5);
  assertValid({ state: api.state });
});

test('window creation controls supply fullscreen metadata and keep overlays out of managed windows', () => {
  const { api, element } = pointerFixture();
  element('kind').value = 'normal';
  element('app-bundle').value = 'com.example.editor';
  element('fullscreen-button').value = 'disabled';
  element('create').onclick();
  assert.equal(api.state.windows[4].mode, 'floating');
  element('app-bundle').value = 'com.anthropic.claudefordesktop';
  element('create').onclick();
  assert.equal(api.state.windows[5].mode, 'tiled');
  assert.equal(api.state.windows[5].fullscreenButton, 'disabled');
  element('fullscreen-button').value = 'missing';
  element('create').onclick();
  assert.equal(api.state.windows[6].mode, 'tiled');
  assert.equal(api.state.windows[6].fullscreenButton, 'missing');
  const beforeOverlay = plain(api.state.windows);
  element('kind').value = 'overlay';
  element('create').onclick();
  assert.deepEqual(plain(api.state.windows), beforeOverlay);
  assert.equal(api.state.focused, 6);
  assertValid({ state: api.state });
});

test('unmanaged overlay preserves distinct native fullscreen and logical focus', () => {
  const fullscreen = Layout.reduce(Layout.seed(), { type: 'suspend', id: 3, reason: 'fullscreen' });
  assert.equal(fullscreen.nativeFocused, 3);
  assert.equal(fullscreen.focused, 2);
  const overlay = { type: 'create', kind: 'overlay', bundleId: 'com.anthropic.claudefordesktop' };
  const session = new Layout.DisplayLayoutState(fullscreen);
  for (const result of [Layout.reduce(fullscreen, overlay), session.dispatch(overlay)]) {
    assert.deepEqual(plain({ ...result, message: fullscreen.message }), plain(fullscreen));
    assert.match(result.message, /unmanaged/);
  }
});

test('unmanaged overlay control preserves the active drag owner, preview, and pointer stream', () => {
  const { api, element, down, emit, board, session } = pointerFixture();
  down(3);
  const first = center(api.Layout.frames(api.state).find(rect => rect.id === 1));
  emit(board, 'pointermove', { clientX: first.x, clientY: first.y });
  const destination = center(api.Layout.display(api.state, 'B'));
  emit(board, 'pointermove', { clientX: destination.x, clientY: destination.y });
  const gesture = session.gesture;
  assert(gesture?.preview);
  const before = plain(api.state);
  const preview = plain(gesture.preview);
  element('kind').value = 'overlay';
  element('app-bundle').value = 'com.anthropic.claudefordesktop';
  element('fullscreen-button').value = 'missing';
  element('create').onclick();
  assert.equal(session.gesture, gesture);
  assert.deepEqual(plain(api.gesture.preview), preview);
  assert.deepEqual(plain({ ...api.state, message: before.message }), before);
  assert.equal(board.hasPointerCapture(7), true);
  emit(board, 'pointerup', { clientX: destination.x, clientY: destination.y });
  assert.equal(api.gesture, null);
  assert.equal(api.state.windows[3].display, 'B');
  assertValid({ state: api.state });
});

test('native resize timing guided buttons exercise the complete delayed-observation sequence', () => {
  const fixture = pointerFixture();
  const scenario = fixture.scenarioControls('Native resize timing');
  const original = plain(fixture.api.state.displays);
  scenario.click(0);
  scenario.click(1);
  assert.deepEqual(plain(fixture.api.state.displays), original);
  assert.match(fixture.api.state.message, /held W3 keeps its native frame/);
  scenario.click(2);
  assert.notDeepEqual(plain(fixture.api.state.displays), original);
  const observed = plain(fixture.api.state.displays);
  scenario.click(3);
  assert.deepEqual(plain(fixture.api.state.displays), observed);
  scenario.click(4);
  assert.match(fixture.api.state.message, /normal frame writes resume/);
});

test('floating cancellation guided controls preserve restoration and independent creation', () => {
  const fixture = pointerFixture();
  const scenario = fixture.scenarioControls('Floating cancellation');
  const original = plain(fixture.api.state.windows[3].rect);
  scenario.click(0);
  scenario.click(1);
  assert.notDeepEqual(plain(fixture.api.state.windows[3].rect), original);
  scenario.click(2);
  assert.deepEqual(plain(fixture.api.state.windows[3].rect), original);
  const afterCreation = plain(fixture.api.state);
  scenario.click(3);
  scenario.click(4);
  assert.deepEqual(plain(fixture.api.state), afterCreation);
  assert(fixture.api.state.windows[4]);
});

test('laptop minimum guided controls allow smaller tiles and retain known application limits', () => {
  const fixture = pointerFixture();
  const scenario = fixture.scenarioControls('Laptop minimum');
  scenario.click(0);
  scenario.click(1);
  const nested = fixture.api.Layout.frames(fixture.api.state).find(rect => rect.id === 5);
  assert(nested.w < 320 && nested.h < 200);
  scenario.click(2);
  scenario.click(3);
  const minimum = fixture.api.Layout.frames(fixture.api.state).find(rect => rect.id === 5);
  assert(Math.abs(minimum.w - 160) < 1e-9);
  assert(Math.abs(minimum.h - 100) < 1e-9);
  scenario.click(4);
  const known = fixture.api.Layout.frames(fixture.api.state).find(rect => rect.id === 5);
  assert(known.w >= 240 && known.h >= 180);
  const before = plain(fixture.api.state.displays[0].root);
  scenario.click(5);
  assert.equal(fixture.api.state.windows[6].mode, 'floating');
  assert.deepEqual(plain(fixture.api.state.displays[0].root), before);
  assertValid({ state: fixture.api.state });
});

test('minimum rejection and recovery guided controls still demonstrate their policies', () => {
  const fixture = pointerFixture();
  const minimum = fixture.scenarioControls('Minimum sizes');
  minimum.click(0);
  const before = plain(fixture.api.state.displays[0].root);
  minimum.click(1);
  minimum.click(2);
  assert.equal(fixture.api.state.windows[4].mode, 'floating');
  assert.deepEqual(plain(fixture.api.state.displays[0].root), before);
  minimum.click(3);
  const width = fixture.api.Layout.frames(fixture.api.state).find(rect => rect.id === 1).w;
  minimum.click(4);
  assert(Math.abs(fixture.api.Layout.frames(fixture.api.state).find(rect => rect.id === 1).w - width) < 1e-9);
  const recovery = fixture.scenarioControls('Recovery');
  recovery.click(0);
  assert(fixture.api.state.displays[0].root.ratio < .85);
  assert.equal(fixture.api.state.recovered.length, 0);
  recovery.click(1);
  assert(fixture.api.state.recovered.length > 0);
  const floating = Object.values(fixture.api.state.windows).filter(window => window.mode === 'floating').map(window => window.id);
  recovery.click(2);
  assert.deepEqual(Object.values(fixture.api.state.windows).filter(window => window.mode === 'floating').map(window => window.id), floating);
  assertValid({ state: fixture.api.state });
});

test('pointercancel rolls back the gesture and accepts the very next drag', () => {
  const { api, down, emit, board } = pointerFixture();
  down();
  const initial = plain(api.state);
  const target = center(api.Layout.frames(api.state).find(rect => rect.id === 1));
  emit(board, 'pointermove', { clientX: target.x, clientY: target.y });
  assert.notDeepEqual(plain(api.state.displays), initial.displays);
  emit(board, 'pointercancel');
  assert.deepEqual(plain(api.state), initial);
  assert.equal(api.gesture, null);
  assert.equal(board.hasPointerCapture(7), false);
  down();
  assert.equal(api.gesture?.id, 3);
});

test('held-pointer cancellation stays blocked until a terminal event outside the board', () => {
  for (const cancel of ['Escape', 'lifecycle']) {
    for (const terminal of ['pointerup', 'pointercancel']) {
      const { api, down, emit, board, window } = pointerFixture();
      down();
      if (cancel === 'Escape') emit(window, 'keydown', { key: 'Escape', target: board });
      else api.dispatch({ type: 'create' });
      assert.equal(api.gesture, null);
      const windowIds = Object.keys(api.state.windows);
      down();
      assert.equal(api.gesture, null, `${cancel} must block held-pointer samples`);
      emit(window, terminal);
      down();
      assert.equal(api.gesture?.id, 3, `${terminal} must permit the next drag after ${cancel}`);
      assert.deepEqual(Object.keys(api.state.windows), windowIds);
    }
  }
});
