// Run with node tools/babylon/test_lobby_loading.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const elements = {};
for (const id of ['browser-content', 'action-loading', 'loading-world', 'loading-stage', 'connection-lost']) {
  elements[id] = { style: {}, textContent: '', innerHTML: '' };
}
let paints = 0;
Object.defineProperty(elements['browser-content'], 'innerHTML', {
  get() { return this.html || ''; },
  set(value) { this.html = value; paints++; },
});
const callbacks = [];
const intervals = [];
let now = 1000000;
class FakeDate { getTime() { return now; } }
const context = {
  Date: FakeDate,
  setInterval(fn) { intervals.push(fn); },
  document: { documentElement: { scrollTop: 0 }, getElementById: id => elements[id] },
  window: { pageYOffset: 0, scrollTo(x, y) { this.pageYOffset = y; } },
  setTimeout(fn) { callbacks.push(fn); },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../modular_babylon/lobby/loading.js'), 'utf8'), context);
const flush = () => { while (callbacks.length) callbacks.shift()(); };
const render = (html, view, revision, complete = false) => {
  context.renderLobby(JSON.stringify({ html, view, revision, complete }));
  flush();
};
const click = (stage = 'Waiting for confirmation...') => context.beginAction({
  getAttribute(name) { return name === 'data-world' ? 'Test world' : stage; },
});

render('world list', 'mine', 0, true);
context.window.pageYOffset = 420;
render('updated player counts', 'mine', 0);
assert.equal(context.window.pageYOffset, 420, 'background updates preserve scroll');
const previousPaints = paints;
render('updated player counts', 'mine', 0);
assert.equal(paints, previousPaints, 'identical status does not repaint');
assert.equal(click(), true);
assert.equal(elements['browser-content'].style.display, 'none');
assert.equal(elements['action-loading'].style.display, 'block');
assert.equal(elements['loading-world'].textContent, 'Test world');
assert.equal(click(), false, 'duplicate actions are blocked');
render('late background poll', 'mine', 0);
assert.equal(elements['action-loading'].style.display, 'block', 'late polls cannot hide loading');
context.showLobbyLoading('Test world', 'Deleting world and all saved checkpoints...');
assert.match(elements['loading-stage'].textContent, /Deleting world/);
render('deleted world absent', 'mine', 1, true);
assert.equal(elements['browser-content'].innerHTML, 'deleted world absent');
assert.equal(elements['action-loading'].style.display, 'none');
assert.equal(context.window.pageYOffset, 420, 'completion returns to previous scroll');
render('stale response', 'mine', 0, true);
assert.equal(elements['browser-content'].innerHTML, 'deleted world absent');
click('Saving and stopping...');
render('stopping poll', 'mine', 1);
assert.equal(elements['action-loading'].style.display, 'block');
render('stopped list', 'mine', 2, true);
assert.equal(context.window.pageYOffset, 420);
click('Loading worlds...');
render('active list', 'active', 3, true);
assert.equal(context.window.pageYOffset, 0, 'new tab starts at the top');
context.window.pageYOffset = 95;
click('Loading worlds...');
render('my list', 'mine', 4, true);
assert.equal(context.window.pageYOffset, 420, 'each tab retains its position');
click();
render('my list', 'mine', 5, true); // cancelling a native dialog
assert.equal(elements['action-loading'].style.display, 'none');
assert.equal(context.window.pageYOffset, 420);

// Heartbeats keep the page; when they stop, the reconnect screen replaces it for good.
const tick = () => intervals.forEach(fn => fn());
now += 12000;
tick();
assert.notEqual(elements['connection-lost'].style.display, 'block', 'a short gap is not a lost connection');
context.lobbyAlive();
now += 14000;
tick();
assert.notEqual(elements['connection-lost'].style.display, 'block', 'heartbeats keep the lobby');
click('Loading worlds...');
now += 16000;
tick();
assert.equal(elements['connection-lost'].style.display, 'block', 'silence shows the reconnect screen');
assert.equal(elements['action-loading'].style.display, 'none', 'a pending action no longer spins forever');
assert.equal(elements['browser-content'].style.display, 'none');
assert.equal(click(), false, 'links do nothing once the connection is lost');
render('late list', 'mine', 9, true);
assert.equal(elements['browser-content'].style.display, 'none', 'nothing replaces the reconnect screen');
console.log('Lobby loading, cancellation, stale-poll, scroll and lost-connection checks passed.');
