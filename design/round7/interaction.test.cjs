const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const M = require('./model.js');

// Minimal DOM boundary for Node-only event regressions. The production script and
// model run unchanged; replacement disconnects descendants and resets their focus.
function launch(query = '') {
  const listeners = new Map();
  let document;
  const decode = text => text.replace(/&(amp|lt|gt|quot|#39);/g, (_, key) => ({ amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" }[key]));
  class Element {
    constructor(tag, attrs = {}) {
      this.tagName = tag.toUpperCase(); this.attrs = attrs; this.children = []; this.parentElement = null;
      this.dataset = {}; this.style = { setProperty() {}, removeProperty() {} };
      this.classList = { toggle() {} }; this.scrollTop = 0; this.scrollHeight = 1000; this.clientHeight = 860;
      this.value = attrs.value || ''; this._html = ''; this._text = '';
      for (const [name, value] of Object.entries(attrs)) this.setAttribute(name, value);
    }
    get id() { return this.attrs.id || ''; }
    get name() { return this.attrs.name || ''; }
    get isConnected() { return this === document?.body || !!this.parentElement?.isConnected; }
    get offsetParent() { return this.closest('[hidden]') ? null : this.parentElement; }
    get form() { return this.closest('form'); }
    getAttribute(name) { return this.attrs[name] ?? null; }
    setAttribute(name, value) {
      this.attrs[name] = String(value);
      if (name.startsWith('data-')) this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = String(value);
      if (name === 'hidden' || name === 'disabled' || name === 'inert') this[name] = true;
    }
    removeAttribute(name) { delete this.attrs[name]; if (['hidden', 'disabled', 'inert'].includes(name)) this[name] = false; }
    contains(node) { return node === this || this.children.some(child => child.contains(node)); }
    matches(selector) {
      selector = selector.trim();
      if (selector.includes(',')) return selector.split(',').some(part => this.matches(part));
      const negations = [...selector.matchAll(/:not\(([^()]*(?:\([^()]*\))?[^()]*)\)/g)];
      for (const match of negations) { if (this.matches(match[1])) return false; selector = selector.replace(match[0], ''); }
      if (selector === ':disabled') return !!this.disabled;
      if (selector === ':focus') return document.activeElement === this;
      const attrs = [...selector.matchAll(/\[([^=\]]+)(?:="([^"]*)")?\]/g)];
      for (const [, name, value] of attrs) {
        const actual = ['hidden', 'disabled', 'inert'].includes(name) ? (this[name] ? '' : null) : this.getAttribute(name);
        if (actual === null || (value !== undefined && actual !== value)) return false;
      }
      selector = selector.replace(/\[[^\]]+\]/g, '');
      const id = selector.match(/#([\w-]+)/); if (id && this.id !== id[1]) return false;
      for (const [, name] of selector.matchAll(/\.([\w-]+)/g)) if (!(this.attrs.class || '').split(' ').includes(name)) return false;
      const tag = selector.match(/^[\w-]+/); return !tag || this.tagName === tag[0].toUpperCase();
    }
    closest(selector) { for (let node = this; node; node = node.parentElement) if (node.matches(selector)) return node; return null; }
    querySelectorAll(selector) {
      const result = [];
      const chains = selector.split(',').map(s => s.trim().split(/\s+(?![^\[]*\])/));
      const matchesChain = (node, chain) => {
        if (!node.matches(chain[chain.length - 1])) return false;
        let parent = node.parentElement;
        for (let i = chain.length - 2; i >= 0; i--) {
          if (chain[i] === '>') { i--; if (!parent?.matches(chain[i])) return false; parent = parent.parentElement; }
          else { while (parent && !parent.matches(chain[i])) parent = parent.parentElement; if (!parent) return false; parent = parent.parentElement; }
        }
        return true;
      };
      const walk = node => { for (const child of node.children) { if (chains.some(chain => matchesChain(child, chain))) result.push(child); walk(child); } };
      walk(this); return result;
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    set innerHTML(html) {
      if (document.activeElement !== this && this.contains(document.activeElement)) document.activeElement = document.body;
      for (const child of this.children) child.parentElement = null;
      this.children = []; this._html = html; this._text = '';
      let parent = this;
      for (const token of html.match(/<[^>]+>|[^<]+/g) || []) {
        if (token.startsWith('</')) { parent = parent.parentElement || this; continue; }
        if (!token.startsWith('<')) { parent._text += decode(token); continue; }
        if (token.startsWith('<!')) continue;
        const tag = token.match(/^<([\w-]+)/)[1]; const attrs = {};
        const rest = token.slice(tag.length + 1).replace(/\/?\s*>$/, '');
        for (const [, name, double, single, bare] of rest.matchAll(/([^\s=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s]+)))?/g)) attrs[name] = decode(double ?? single ?? bare ?? '');
        const child = new Element(tag, attrs); child.parentElement = parent; parent.children.push(child);
        if (!/^(input|img|br|hr|meta|link)$/i.test(tag) && !token.endsWith('/>')) parent = child;
      }
    }
    get innerHTML() { return this._html; }
    set textContent(text) { this._text = text; }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    focus() { if (this.isConnected && !this.disabled && !this.closest('[hidden]') && !this.closest('[inert]')) document.activeElement = this; }
    addEventListener() {}
    getBoundingClientRect() { return { x: 10, y: 100, width: 100, height: 100 }; }
  }
  const body = new Element('body');
  document = {
    body, activeElement: body, documentElement: { dataset: {} },
    getElementById: id => body.querySelector('#' + id),
    querySelector: selector => body.querySelector(selector), querySelectorAll: selector => body.querySelectorAll(selector),
    addEventListener: (name, callback) => { if (!listeners.has(name)) listeners.set(name, []); listeners.get(name).push(callback); },
  };
  body.innerHTML = '<header class="studio-bar"><button id="theme-toggle"></button><button id="empty-toggle"></button><button id="text-toggle"></button></header><aside class="design-rail"></aside><aside class="design-notes"><div id="page-notes"></div></aside><div id="preview-page-name"></div><div id="device"><main id="screen" tabindex="-1"></main><nav id="app-nav"></nav><div id="toast" hidden></div><div id="sheet-layer" hidden><section id="app-sheet"><div class="sheet-handle"></div><header><h2 id="sheet-title"></h2><button data-action="dismiss-sheet">关闭</button></header><div id="sheet-content"></div></section></div></div>';
  const state = M.createState(query.includes('empty=1'));
  class FormData {
    constructor(form) { this.controls = form.querySelectorAll('input, select, textarea'); }
    get(name) {
      const control = this.controls.find(c => c.name === name);
      if (control?.tagName !== 'SELECT' || control.value) return control?.value ?? null;
      // Untouched selects submit the app's selected option, or the first enabled option.
      const options = control.querySelectorAll('option');
      const selected = options.find(option => option.getAttribute('selected') !== null) || options.find(option => !option.disabled);
      return selected ? selected.getAttribute('value') ?? selected.textContent : null;
    }
    getAll(name) { return this.controls.filter(c => c.name === name && c.checked).map(c => c.value); }
  }
  vm.runInNewContext(fs.readFileSync(__dirname + '/app.js', 'utf8'), {
    window: { LocalFitModel: { ...M, createState: () => state } }, document,
    location: { search: query }, URLSearchParams, FormData, setTimeout: () => 1, clearTimeout() {},
  });
  const find = (selector, root = body) => { const node = root.querySelector(selector); assert.ok(node, 'Missing control: ' + selector); return node; };
  const emit = (type, target, extra = {}) => {
    const event = { target, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; }, ...extra };
    for (const callback of listeners.get(type) || []) callback(event);
    return event;
  };
  return {
    document, state, find, emit,
    screen: find('#screen'), layer: find('#sheet-layer'), sheet: find('#app-sheet'),
    click(selector, root) { const node = typeof selector === 'string' ? find(selector, root) : selector; assert.ok(node.isConnected); node.focus(); emit('click', node); return node; },
    submit(id, values) {
      const form = find('#' + id);
      for (const [name, value] of Object.entries(values)) { const control = find('[name="' + name + '"]', form); control.value = value; emit('input', control); }
      emit('submit', form);
      assert.equal(form.querySelector('.form-error')?.textContent || '', '', 'Unexpected form validation failure');
    },
  };
}
const action = (name, extra = '') => '[data-action="' + name + '"]' + extra;

test('food details preserve the compact graphic contract and mark missing facts honestly', () => {
  const app = launch('?page=nutrition&tab=foods');
  assert.equal(app.screen.querySelectorAll('.food-tags').length, 0);
  assert.match(app.find('.food-symbol img').getAttribute('src'), /assets\/food-categories\/staple\.svg$/);
  Object.assign(app.state.foods[0], { kcal: 0, protein: null, carbs: 0, fat: undefined });
  app.click(action('food-detail', '[data-id="rice"]'));
  assert.equal(app.find('.detail-density').getAttribute('style').includes('56px'), true);
  assert.equal(app.find('.detail-density circle').getAttribute('stroke-width'), '6');
  assert.equal(app.find('.detail-density b').textContent, '—');
  assert.equal(app.sheet.querySelectorAll('.food-macro-stack > div').length, 3);
  assert.deepEqual(app.sheet.querySelectorAll('.food-macro-stack b').map(e => e.textContent), ['0g','0g','0g']);
  assert.match(app.find('.food-density-note').textContent, /无热量数据/);
  assert.match(app.find('.food-detail-meta').textContent, /示例/);
  assert.match(app.sheet.textContent, /营养不完整/);
  assert.equal(app.sheet.querySelector(action('food-record')), null);
});

// Failure target: a complete detail loses its record entry, or drops the selected food id.
for (const origin of ['example', 'builtIn']) test('complete ' + origin + ' food detail records the preselected food', () => {
  const app = launch('?page=nutrition&tab=foods');
  app.state.foods.find(food => food.id === 'milk').origin = origin;
  const foods = JSON.stringify(app.state.foods), count = app.state.meals.length;
  app.click(action('food-detail', '[data-id="milk"]'));
  const record = app.sheet.querySelector(action('food-record'));
  assert.ok(record, 'Complete food details must offer recording regardless of catalog write permissions');
  assert.equal(record.dataset.id, 'milk');
  if (origin === 'builtIn') {
    assert.equal(app.sheet.querySelector(action('food-edit')), null);
    assert.equal(app.sheet.querySelector(action('food-delete')), null);
  }
  app.click(record);
  assert.equal(app.find('option[value="milk"]').getAttribute('selected'), '');
  // Do not select food or slot manually: the real form must preserve both defaults.
  app.submit('meal-form', { grams: '150' });
  assert.equal(app.layer.hidden, true);
  assert.equal(app.state.meals.length, count + 1);
  const { name, slot, kcal, protein, carbs, fat, source } = app.state.meals.at(-1);
  assert.deepEqual({ name, slot, kcal, protein, carbs, fat, source }, {
    name: '纯牛奶 150 g', slot: '晚餐', kcal: 96, protein: 4.8, carbs: 7.5, fat: 5.4, source: 'confirmed',
  });
  assert.equal(JSON.stringify(app.state.foods), foods);
});

test('detail recording remains unavailable for incomplete or explicitly blocked food', () => {
  for (const patch of [{ kcal: 0 }, { protein: null }, { carbs: undefined }, { fat: NaN }, { canJoinPlan: false }]) {
    const app = launch('?page=nutrition&tab=foods');
    Object.assign(app.state.foods.find(food => food.id === 'milk'), patch);
    app.click(action('food-detail', '[data-id="milk"]'));
    assert.equal(app.sheet.querySelector(action('food-record')), null);
  }
});

test('a stale record entry cannot open a form after food nutrients become incomplete', () => {
  const app = launch('?page=nutrition&tab=foods'), meals = JSON.stringify(app.state.meals);
  app.click(action('food-detail', '[data-id="milk"]'));
  const record = app.sheet.querySelector(action('food-record'));
  assert.ok(record, 'Complete food must first expose a recording entry');
  app.state.foods.find(food => food.id === 'milk').protein = null;
  app.click(record);
  assert.equal(app.sheet.querySelector('#meal-form'), null);
  assert.equal(JSON.stringify(app.state.meals), meals);
});

// Failure target: a changed aria-label overrides the stable identity of a replaced food row.
test('closing renamed food details restores focus to the same food id', () => {
  const app = launch('?page=nutrition&tab=foods');
  const selector = action('food-detail', '[data-id="rice"]');
  const opener = app.click(selector);
  app.click(action('food-edit'));
  app.submit('food-edit-form', { 'food-name': '新米饭' });
  assert.equal(app.find('.food-detail-title').textContent, '新米饭');
  app.click(action('dismiss-sheet'));
  const replacement = app.find(selector);
  assert.equal(opener.isConnected, false);
  assert.ok(app.document.activeElement === replacement, 'Focus must return to the renamed food row, not the page');
});

test('closing food details after renaming outside the search safely focuses the page', () => {
  const app = launch('?page=nutrition&tab=foods'), query = app.find('#food-query');
  query.value = '米饭'; app.emit('input', query);
  app.click(action('food-detail', '[data-id="rice"]')); app.click(action('food-edit'));
  app.submit('food-edit-form', { 'food-name': '白粥' });
  app.click(action('dismiss-sheet'));
  assert.equal(app.screen.querySelector(action('food-detail', '[data-id="rice"]')), null);
  assert.equal(app.find('#food-query').value, '米饭');
  assert.ok(app.document.activeElement === app.screen);
});

test('deleting the open food safely focuses the page instead of a removed row', () => {
  const app = launch('?page=nutrition&tab=foods');
  app.click(action('food-detail', '[data-id="rice"]')); app.click(action('food-delete'));
  app.click(action('confirm-food-delete'));
  assert.equal(app.layer.hidden, true);
  assert.equal(app.screen.querySelector(action('food-detail', '[data-id="rice"]')), null);
  assert.ok(app.document.activeElement === app.screen);
});

test('food edit validates and delete requires confirmation without altering meal snapshots', () => {
  const app = launch('?page=nutrition&tab=foods'), meals = JSON.stringify(app.state.meals);
  app.click(action('food-detail', '[data-id="rice"]')); app.click(action('food-edit'));
  const form = app.find('#food-edit-form');
  app.find('[name="food-name"]').value = ''; app.emit('submit', form);
  assert.match(form.querySelector('.form-error').textContent, /名称/);
  assert.equal(app.state.foods[0].name, '米饭');
  app.submit('food-edit-form', { 'food-name': '新米饭', 'food-brand': '样例', 'food-kcal': '120', 'food-protein': '3', 'food-carbs': '26', 'food-fat': '0' });
  assert.equal(app.state.foods[0].name, '新米饭');
  app.click(action('food-delete')); assert.equal(app.state.foods.length, 8);
  app.click(action('food-detail', '[data-id="rice"]')); assert.equal(app.state.foods.length, 8);
  app.click(action('food-delete')); app.click(action('confirm-food-delete'));
  assert.equal(app.state.foods.length, 7); assert.equal(app.layer.hidden, true);
  assert.equal(JSON.stringify(app.state.meals), meals);
});

test('built-in food has no write controls and incomplete food is disabled in meal form', () => {
  const app = launch('?page=nutrition&tab=foods'); app.state.foods[0].origin = 'builtIn';
  app.click(action('food-detail', '[data-id="rice"]'));
  assert.equal(app.sheet.querySelector(action('food-edit')), null); assert.equal(app.sheet.querySelector(action('food-delete')), null);
  app.click(action('dismiss-sheet')); app.state.foods[0].protein = null;
  app.click(action('nutrition-tab', '[data-tab="records"]')); app.click(action('meal-add'));
  assert.equal(app.find('option[value="rice"]').disabled, true);
});

test('exercise library is a searchable secondary page with stable input focus and real filters', () => {
  const app = launch('?page=training'); app.click(action('exercise-library'));
  assert.equal(app.layer.hidden, true); app.find('.exercise-library-page');
  assert.equal(app.screen.querySelectorAll('.muscle-filters button').length, 8);
  const input = app.find('#exercise-query'); input.focus(); input.value = '深蹲'; app.emit('input', input);
  assert.equal(app.find('#exercise-query'), input); assert.equal(app.document.activeElement, input);
  const tiles = app.screen.querySelectorAll('button.exercise-tile');
  assert.ok(tiles.length >= 2); assert.ok(tiles.every(row => row.textContent.includes('深蹲')));
  app.click(action('muscle-filter', '[data-group="胸"]'));
  assert.equal(app.screen.querySelectorAll('button.exercise-tile').length, 0);
  assert.match(app.find('.library-result-count').textContent, /0/);
  app.click(action('exercise-library-back')); assert.ok(app.screen.querySelector('.training-page'));
});

test('exercise alternatives replace one sheet and local creation stays outside plans and stats', () => {
  const app = launch('?page=training'), before = JSON.stringify({ plans: app.state.plans, history: app.state.history, stats: M.volumeStats(app.state) });
  app.click(action('exercise-library')); app.click(action('exercise-detail', '[data-id="squat"]'));
  const alternative = app.find('.exercise-alternative'), selectedId = alternative.dataset.id;
  app.click(alternative);
  assert.equal(app.find('.exercise-detail-hero').dataset.id, selectedId);
  assert.equal(app.find('#sheet-content').querySelectorAll('.exercise-detail-hero').length, 1);
  assert.equal(app.sheet.querySelector('.exercise-alternative[data-id="'+selectedId+'"]'), null);
  app.click(action('dismiss-sheet')); app.click(action('exercise-create'));
  app.submit('exercise-create-form', { 'exercise-name': '我的肩部动作', 'exercise-group': '肩', 'exercise-equipment': '哑铃' });
  assert.match(app.screen.innerHTML, /我的肩部动作/);
  const created = app.state.exerciseLibrary.find(row => row.name === '我的肩部动作'); assert.ok(created);
  assert.equal(created.difficulty, null); assert.equal(created.popularity, null);
  assert.equal(JSON.stringify({ plans: app.state.plans, history: app.state.history, stats: M.volumeStats(app.state) }), before);
});

test('detail preview parameters open only valid views and restore the html view state', () => {
  const library = launch('?page=training&view=exercise-library');
  assert.ok(library.screen.querySelector('.exercise-library-page'));
  assert.equal(library.document.documentElement.dataset.view, 'exercise-library');
  library.click(action('navigate', '[data-page="settings"]'));
  assert.notEqual(library.document.documentElement.dataset.view, 'exercise-library');
  const food = launch('?page=nutrition&tab=foods&food=milk');
  assert.equal(food.layer.hidden, false);
  assert.match(food.find('.food-detail-title').textContent, /纯牛奶/);
  assert.ok(food.sheet.querySelector('[data-action="food-edit"]'));
  for (const query of ['?page=nutrition&tab=foods&food=unknown', '?page=today&food=milk', '?page=today&view=exercise-library']) {
    const invalid = launch(query);
    assert.equal(invalid.layer.hidden, true);
    assert.equal(invalid.screen.querySelector('.exercise-library-page'), null);
  }
});

test('file operation entries explain import/export direction without promising real file access', () => {
  const app = launch('?page=nutrition&tab=foods');
  assert.match(app.find(action('import-info')).textContent, /从文件读取到食物库/);
  app.click(action('import-info')); assert.match(app.sheet.textContent, /不读取文件/);
  app.click(action('dismiss-sheet')); app.click(action('navigate', '[data-page="settings"]'));
  assert.match(app.find(action('export-food')).textContent, /保存为文件/);
});
const todaySelected = app => assert.equal(app.find(action('nutrition-date', '[data-date="2026-10-13"]')).getAttribute('aria-pressed'), 'true');
function historical(app) { app.click(action('nutrition-date', '[data-date="2026-10-10"]')); }
function generate(app) {
  app.click(action('workbench'));
  app.click(action('creation-form', '[data-prompt="plan"]'), app.sheet);
  app.submit('creation-form', { description: '每周三次力量训练' });
}

test('Today view-all resets the selected record date', () => {
  const app = launch('?page=nutrition'); historical(app);
  app.click(action('navigate', '[data-page="today"]'));
  app.click(action('nutrition-records')); todaySelected(app);
});

test('saving a dish from menus shows the newly recorded meal today', () => {
  const app = launch('?page=nutrition'); historical(app);
  app.click(action('nutrition-tab', '[data-tab="menus"]'));
  app.click(action('dish-add', '[data-slot="早餐"]'));
  app.submit('dish-form', { 'dish-grams': '200' });
  assert.equal(app.state.meals.at(-1).date, '2026-10-13');
  todaySelected(app); assert.match(app.screen.innerHTML, /牛奶燕麦粥 200 g/);
});

test('saving a food from a historical records page reveals the meal today', () => {
  const app = launch('?page=nutrition'); historical(app);
  app.click(action('meal-add'));
  app.submit('meal-form', { food: 'rice', grams: '150', slot: '晚餐' });
  todaySelected(app); assert.match(app.screen.innerHTML, /米饭 150 g/);
});

test('invalid meal does not reset the viewed historical date or close the form', () => {
  const app = launch('?page=nutrition'); historical(app); app.click(action('meal-add'));
  const form = app.find('#meal-form');
  app.find('[name="food"]', form).value = 'rice'; app.find('[name="grams"]', form).value = '';
  app.emit('submit', form);
  assert.equal(app.layer.hidden, false);
  assert.equal(app.find(action('nutrition-date', '[data-date="2026-10-10"]')).getAttribute('aria-pressed'), 'true');
  assert.match(form.querySelector('.form-error').textContent, /食用克数/);
});

for (const previous of ['ignore-proposal', 'apply-proposal']) test('new proposal after ' + previous + ' is pending and applied once only', () => {
  const app = launch('?page=ai'); generate(app); app.click(action(previous));
  const previousPlans = app.state.plans.map(plan => JSON.stringify(plan));
  generate(app);
  assert.equal(app.state.proposalStatus, 'pending');
  assert.equal(app.state.plans.length, previousPlans.length, 'Generation must not apply a plan');
  const apply = app.click(action('apply-proposal'));
  assert.equal(app.state.plans.length, previousPlans.length + 1);
  assert.deepEqual(app.state.plans.slice(0, -1).map(plan => JSON.stringify(plan)), previousPlans);
  app.emit('click', apply); // A repeated/stale activation must not create another plan.
  assert.equal(app.state.plans.length, previousPlans.length + 1);
  app.submit('chat-form', { message: '谢谢' });
  assert.equal(app.state.proposalStatus, 'applied', 'Ordinary chat must not reopen the proposal');
});

test('a stale apply control cannot apply a newly generated proposal', () => {
  const app = launch('?page=ai'); generate(app);
  const stale = app.click(action('apply-proposal'));
  generate(app); const count = app.state.plans.length;
  app.emit('click', stale);
  assert.equal(app.state.plans.length, count);
  assert.equal(app.state.proposalStatus, 'pending');
  app.click(action('apply-proposal'));
  assert.equal(app.state.plans.length, count + 1);
});

for (const [query, selector] of [
  ['?page=today', action('weight-period', '[data-period="month"]')],
  ['?page=nutrition&tab=foods', action('category', '[data-category="主食"]')],
  ['?page=today', action('water-quick')],
]) test('same-page redraw preserves focus for ' + selector, () => {
  const app = launch(query); const old = app.click(selector);
  assert.equal(old.isConnected, false);
  assert.equal(app.document.activeElement, app.find(selector));
});

for (const [query, selector, form, values] of [
  ['?page=nutrition', action('meal-add', '[data-slot="午餐"]'), 'meal-form', { food: 'rice', grams: '100', slot: '午餐' }],
  ['?page=today', action('weight-add'), 'weight-form', { weight: '63.1' }],
  ['?page=settings', action('profile-edit'), 'profile-form', { 'profile-name': '小林', 'water-goal': '2200', 'step-goal': '9000' }],
]) test(form + ' restores focus to its replacement opener after saving', () => {
  const app = launch(query); const opener = app.click(selector); app.submit(form, values);
  assert.equal(app.layer.hidden, true); assert.equal(opener.isConnected, false);
  assert.equal(app.document.activeElement, app.find(selector));
});

test('closing a session sheet after its background redraw restores the start control', () => {
  const app = launch('?page=training'); const selector = action('start-workout', '[data-id="base"]');
  app.click(selector); app.click(action('record-set', '[data-exercise="squat"]'), app.sheet);
  app.submit('set-form', { exercise: 'squat', 'set-weight': '10', 'set-reps': '10' });
  app.click(action('dismiss-sheet'), app.sheet);
  assert.equal(app.document.activeElement, app.find(selector));
});

test('weight-period change within a sheet keeps focus inside on the chosen period', () => {
  const app = launch('?page=settings'); app.click(action('weight-history'));
  const selector = action('weight-period', '[data-period="month"]'); app.click(selector, app.sheet);
  assert.equal(app.document.activeElement, app.find(selector, app.sheet));
});

test('sending chat replaces the input and focuses the new empty input', () => {
  const app = launch('?page=ai'); const old = app.find('#chat-form input'); old.focus();
  app.submit('chat-form', { message: '今天怎么吃？' });
  const input = app.find('#chat-form input');
  assert.equal(old.isConnected, false); assert.equal(input.value, '');
  assert.equal(app.document.activeElement, input);
  assert.match(app.screen.innerHTML, /今天怎么吃？/);
});

test('creation sent from another page focuses chat instead of the disappeared opener', () => {
  const app = launch('?page=today'); generate(app);
  assert.equal(app.document.activeElement, app.find('#chat-form input'));
});

test('Escape dismisses the home weight tooltip without moving focus', () => {
  const app = launch(); const bar = app.click(action('weight-point'));
  const tooltip = app.find('.weight-tooltip'); assert.equal(tooltip.hidden, false);
  const event = app.emit('keydown', bar, { key: 'Escape' });
  assert.equal(tooltip.hidden, true); assert.equal(event.defaultPrevented, true);
  assert.equal(app.document.activeElement, bar);
});

test('Escape dismisses the sheet tooltip first and the sheet on a second press', () => {
  const app = launch('?page=settings'); app.click(action('weight-history'));
  const bar = app.click(action('weight-point'), app.sheet); const tooltip = app.find('.weight-tooltip', app.sheet);
  app.emit('keydown', bar, { key: 'Escape' });
  assert.equal(tooltip.hidden, true); assert.equal(app.layer.hidden, false);
  app.emit('keydown', bar, { key: 'Escape' }); assert.equal(app.layer.hidden, true);
});
