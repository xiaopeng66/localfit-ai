const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const M = require('./model.js');

function renderPage(query, override) {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, {
      id, hidden: true, innerHTML: '', textContent: '', scrollTop: 0,
      style: { setProperty() {}, removeProperty() {} },
      classList: { toggle() {} }, dataset: {},
      setAttribute() {}, removeAttribute() {}, addEventListener() {},
      querySelector: selector => element(selector), focus() {},
    });
    return elements.get(id);
  };
  const document = {
    documentElement: { dataset: {} }, title: '', activeElement: null,
    getElementById: element, querySelector: element, querySelectorAll: () => [],
    addEventListener() {},
  };
  const model = override ? { ...M, createState: () => override } : M;
  vm.runInNewContext(fs.readFileSync(__dirname + '/app.js', 'utf8'), {
    window: { LocalFitModel: model }, document,
    location: { search: query }, URLSearchParams, setTimeout, clearTimeout,
  });
  return element('screen').innerHTML;
}

test('today draws the complete calorie ring and separate weight, water and meal budget graphics', () => {
  const html = renderPage('?page=today');
  for (const graphic of ['calorie-macros', 'weight', 'water-steps', 'meal-budget']) {
    assert.match(html, new RegExp('data-graphic="' + graphic + '"'));
  }
  assert.match(html, /class="data-ring calorie-ring"/);
  assert.equal((html.match(/data-action="weight-point"/g) || []).length, 2);
  assert.equal((html.match(/weight-slot no-data/g) || []).length, 5);
});

test('empty step permission state exposes a badge and no invented progress', () => {
  const html = renderPage('?page=today&empty=1');
  const steps = html.split('>步数</h2>')[1].split('</section>')[0];
  assert.match(steps, /未授权/);
  assert.doesNotMatch(steps, /data-track|查看详情/);
});

test('missing BMI is an empty scale without a marker or category label', () => {
  const html = renderPage('?page=settings&empty=1');
  const bmi = html.split('bmi-metric')[1].split('class="health-metric"')[0];
  assert.match(bmi, /bmi-scale unknown/);
  assert.doesNotMatch(bmi, /gauge-marker|>偏瘦<|>正常</);
});

test('food list uses density mini rings rather than daily completion', () => {
  const html = renderPage('?page=nutrition&tab=foods');
  assert.equal((html.match(/class="data-ring food-density"/g) || []).length, 8);
  assert.match(html, /满刻度 1000 kcal\/100g/);
});

test('food with unknown calories renders a dash instead of zero', () => {
  const state = M.createState(); state.foods[0].kcal = null;
  const html = renderPage('?page=nutrition&tab=foods', state);
  assert.match(html, /每100g能量密度 —/);
});

test('diet preview exposes seven date choices and does not fake a trend from empty input', () => {
  const html = renderPage('?page=nutrition&empty=1');
  assert.equal((html.match(/data-action="nutrition-date"/g) || []).length, 7);
  assert.match(html, /近 7 日还没有记录/);
  assert.doesNotMatch(html, /class="trend-column"/);
});

test('no calorie goal means no nutrition target line', () => {
  const state=M.createState();state.energyGoal=null;
  const html=renderPage('?page=nutrition',state);
  assert.doesNotMatch(html,/class="target-line"/);
  assert.match(html,/未设目标/);
});

test('all design variants retain data graphics while C changes the reading order', () => {
  const a=renderPage('?page=today&variant=a'),c=renderPage('?page=today&variant=c');
  assert.ok(a.indexOf('data-graphic="weight"')<a.indexOf('今天吃了什么'));
  assert.ok(c.indexOf('今天吃了什么')<c.indexOf('data-graphic="weight"'));
  for(const variant of ['a','b','c']) {
    const html=renderPage('?page=settings&variant='+variant);
    assert.match(html,/data-graphic="health-gauges"/);
    assert.match(html,/data-graphic="achievements"/);
    assert.equal((html.match(/class="achievement-row"/g)||[]).length,4);
  }
});

test('user profile content is escaped before rendering', () => {
  const state=M.createState();state.profile.name='<img src=x onerror=alert(1)>';
  const html=renderPage('?page=settings',state);
  assert.doesNotMatch(html,/<img/);
  assert.match(html,/&lt;img/);
});

test('macro energy fractions render as percentages for the current intake', () => {
  const html = renderPage('?page=today');
  const ratios = html.split('class="macro-ratios"')[1].split('</div>')[0];
  assert.match(ratios, /蛋白质 24%/);
  assert.match(ratios, /碳水 51%/);
  assert.match(ratios, /脂肪 24%/);
  assert.doesNotMatch(ratios, /0\.\d+%/);
});

test('old mapped volume does not invent a recent four-week trend', () => {
  const state = M.createState();
  state.history = [{ date: '2026-08-01', minutes: 1, status: 'finished', sets: [{ exerciseId: 'squat', weight: 10, reps: 10 }] }];
  const html = renderPage('?page=training', state);
  assert.doesNotMatch(html, /class="volume-bars"/);
  assert.match(html, /class="muscle-distribution"/);
});

test('training weeks can have volume even when no muscle mapping is available', () => {
  const state=M.createState();state.history=[{date:'2026-10-13',minutes:1,status:'finished',sets:[{exerciseId:'unknown',weight:10,reps:10}]}];
  const html=renderPage('?page=training',state);
  assert.match(html,/class="volume-bars"/);
  assert.match(html,/暂无可分配的训练容量/);
});
