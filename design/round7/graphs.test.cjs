const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = require('./model.js');
const api = name => {
  assert.equal(typeof model[name], 'function', `${name} must be exported by the UMD model`);
  return model[name];
};
const empty = today => ({ ...model.createState(true), today: today || '2026-10-13' });

// Failure target: calendar charts silently revert to a trailing seven-day range or leak future data.
test('week weight slots run Monday through Sunday, filtering future values within that same week', () => {
  const state = empty();
  state.weights = [{ date: '2026-10-11', value: 70 }, { date: '2026-10-12', value: 62.6 }, { date: '2026-10-13', value: 62.4 }, { date: '2026-10-14', value: 20 }];
  const chart = model.weightChart(state);
  assert.deepEqual(chart.slots.map(s => s.date), ['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17', '2026-10-18']);
  assert.deepEqual(chart.slots.map(s => s.value), [62.6, 62.4, null, null, null, null, null]);
  assert.equal(chart.latest, 62.4);
  assert.ok(chart.ticks[3] > 20);
});

test('week boundaries work on Sunday, Monday and across a year boundary', () => {
  for (const [today, first, last] of [['2026-10-18', '2026-10-12', '2026-10-18'], ['2026-10-19', '2026-10-19', '2026-10-25'], ['2027-01-01', '2026-12-28', '2027-01-03']]) {
    const chart = model.weightChart(empty(today));
    assert.equal(chart.slots.length, 7);
    assert.equal(chart.slots[0].date, first);
    assert.equal(chart.slots[6].date, last);
  }
});

test('month grids retain every date in leap, ordinary and century February and 30/31-day months', () => {
  for (const [today, length] of [['2024-02-29', 29], ['2026-02-12', 28], ['2000-02-29', 29], ['2100-02-28', 28], ['2026-04-13', 30], ['2026-10-13', 31]]) {
    const chart = model.weightChart(empty(today), 'month');
    assert.equal(chart.slots.length, length);
    assert.equal(chart.slots[0].date, today.slice(0, 8) + '01');
    assert.equal(chart.slots.at(-1).date, today.slice(0, 8) + length);
    assert.ok(chart.slots.every(s => s.value === null && s.axisLabel === ''));
  }
});

test('month axis labels show only valued slots on 1,5,10,15,20,25 and the actual last day', () => {
  const state = empty('2024-02-29');
  state.weights = [1, 2, 5, 10, 15, 20, 25, 28, 29].map(day => ({ date: '2024-02-' + String(day).padStart(2, '0'), value: 62 }));
  const chart = model.weightChart(state, 'month');
  assert.deepEqual(chart.slots.filter(s => s.axisLabel).map(s => s.axisLabel), ['2/1', '2/5', '2/10', '2/15', '2/20', '2/25', '2/29']);
  state.today = '2024-02-14';
  assert.deepEqual(model.weightChart(state, 'month').slots.filter(s => s.axisLabel).map(s => s.axisLabel), ['2/1', '2/5', '2/10']);
  state.weights = [{ date: '2024-02-02', value: 62 }];
  assert.ok(model.weightChart(state, 'month').slots.every(s => s.axisLabel === ''));
});

// Failure target: same-date reads select the first inserted row or sort timestamps lexically.
test('weight slots and latest choose the newest updatedAt independently of insertion order', () => {
  const state = empty();
  state.weights = [
    { date: state.today, value: 61, updatedAt: '2026-10-13T09:00:00Z' },
    { date: state.today, value: 62, updatedAt: '2026-10-13T16:00:00+08:00' },
    { date: '2026-10-12', value: 70, updatedAt: '2026-10-14T00:00:00Z' },
    { date: '2026-10-14', value: 20, updatedAt: '2026-10-14T01:00:00Z' },
  ];
  const before = JSON.stringify(state);
  for (const mode of ['week', 'month']) {
    const chart = model.weightChart(state, mode);
    assert.equal(chart.slots.find(s => s.date === state.today).value, 61);
    assert.equal(chart.latest, 61);
  }
  assert.equal(JSON.stringify(state), before);
});

test('same-date records without timestamps or with tied timestamps choose the last insertion', () => {
  for (const updatedAt of [undefined, '2026-10-13T09:00:00Z', 'invalid']) {
    const state = empty();
    state.weights = [{ date: state.today, value: 65, updatedAt }, { date: state.today, value: 64, updatedAt }];
    assert.equal(model.weightChart(state).latest, 64);
    assert.equal(model.weightChart(state).slots[1].value, 64);
  }
});

test('dated weight updates take precedence over unknown timestamps', () => {
  const state = empty();
  state.weights = [{ date: state.today, value: 61, updatedAt: '2026-10-13T09:00:00Z' }, { date: state.today, value: 64 }];
  assert.equal(model.weightChart(state).latest, 61);
});

test('saveWeight updates the latest same-day row rather than the first matching row', () => {
  for (const stamped of [false, true]) {
    const state = empty();
    state.weights = [
      { date: state.today, value: 65, ...(stamped ? { updatedAt: '2026-10-13T08:00:00Z' } : {}) },
      { date: state.today, value: 64, ...(stamped ? { updatedAt: '2026-10-13T09:00:00Z' } : {}) },
    ];
    model.saveWeight(state, 63.2);
    assert.deepEqual(state.weights.map(s => s.value), [65, 63.2]);
    assert.equal(state.weights.length, 2);
    assert.equal(model.weightChart(state).latest, 63.2);
    assert.equal(model.weightChart(state).slots[1].value, 63.2);
  }
});

test('saveWeight follows timestamp order even if the newest record was inserted earlier', () => {
  const state = empty();
  state.weights = [
    { date: state.today, value: 64, updatedAt: '2026-10-13T09:00:00Z' },
    { date: state.today, value: 65, updatedAt: '2026-10-13T08:00:00Z' },
  ];
  model.saveWeight(state, 63.2);
  assert.deepEqual(state.weights.map(s => s.value), [63.2, 65]);
  assert.equal(model.weightChart(state).latest, 63.2);
});

test('invalid weight rows are not real measurements and latest still works outside the displayed range', () => {
  const state = empty();
  state.weights = [{ date: '2026-09-20', value: 64 }];
  for (const value of [null, undefined, '', '62', 0, -1, NaN, Infinity]) state.weights.push({ date: state.today, value });
  state.weights.push({ date: '2026-02-30', value: 60 }, { date: 'bad-date', value: 50 });
  const chart = model.weightChart(state);
  assert.equal(chart.latest, 64);
  assert.ok(chart.slots.every(s => s.value === null));
  assert.ok(chart.ticks.every(Number.isFinite));
  assert.equal(model.weightChart({ today: state.today }).latest, null);
});

// Failure target: missing-day trend values become fabricated zero intake, or records count as days.
test('nutrition trend returns a trailing seven-day window with null gaps and valid zero intake', () => {
  const nutritionTrend = api('nutritionTrend');
  const state = empty();
  state.meals = [
    { date: '2026-10-06', kcal: 999 }, { date: '2026-10-07', kcal: 100.2 }, { date: '2026-10-07', kcal: 200.1 },
    { date: '2026-10-09', kcal: 0 }, { date: '2026-10-12', kcal: 400 }, { date: state.today, kcal: 500 }, { date: '2026-10-14', kcal: 999 },
  ];
  assert.deepEqual(nutritionTrend(state), {
    days: [
      { date: '2026-10-07', kcal: 300.3 }, { date: '2026-10-08', kcal: null }, { date: '2026-10-09', kcal: 0 },
      { date: '2026-10-10', kcal: null }, { date: '2026-10-11', kcal: null }, { date: '2026-10-12', kcal: 400 }, { date: '2026-10-13', kcal: 500 },
    ], trackedDays: 4, target: 1800,
  });
});

test('nutrition trend does not invent observations or targets from missing and invalid fields', () => {
  const nutritionTrend = api('nutritionTrend');
  const state = empty();
  for (const kcal of [undefined, null, '', '100', -1, NaN, Infinity]) state.meals.push({ date: state.today, kcal });
  assert.equal(nutritionTrend(state).trackedDays, 0);
  assert.ok(nutritionTrend(state).days.every(s => s.kcal === null));
  for (const target of [undefined, null, '', '1800', 0, -1, NaN, Infinity]) {
    state.energyGoal = target;
    assert.equal(nutritionTrend(state).target, null);
  }
  assert.equal(nutritionTrend({ today: state.today }).trackedDays, 0);
});

test('seeded nutrition trend has historical values and a gap without changing the current 1248 kcal', () => {
  const nutritionTrend = api('nutritionTrend');
  const trend = nutritionTrend(model.createState());
  assert.equal(trend.days.length, 7);
  assert.ok(trend.trackedDays > 1 && trend.trackedDays < 7);
  assert.ok(trend.days.some(d => d.kcal === null));
  assert.equal(trend.days.at(-1).kcal, 1248);
});

test('nutrition trend crosses leap day and year end without losing dates', () => {
  const nutritionTrend = api('nutritionTrend');
  assert.deepEqual(nutritionTrend(empty('2024-03-02')).days.map(d => d.date), ['2024-02-25', '2024-02-26', '2024-02-27', '2024-02-28', '2024-02-29', '2024-03-01', '2024-03-02']);
  assert.equal(nutritionTrend(empty('2027-01-02')).days[0].date, '2026-12-27');
});

// Failure target: minutes, set counts, cached volume or active/future sessions stand in for kg*reps.
test('volumeStats uses four Monday weekly buckets with real per-set volume and excludes active/future history', () => {
  const volumeStats = api('volumeStats');
  const state = empty();
  const session = (date, weight, reps, extra = {}) => ({ date, status: 'finished', minutes: 999, volume: 9999, sets: [{ exerciseId: 'squat', weight, reps, volume: 9999 }], ...extra });
  state.history = [
    session('2026-09-20', 100, 100), session('2026-09-21', 10, 10), session('2026-09-27', 5, 10),
    session('2026-09-28', 20, 10), session('2026-10-04', 5, 10), session('2026-10-05', 30, 10),
    session('2026-10-11', 5, 10), session('2026-10-12', 40, 10), session('2026-10-13', 5, 10),
    session('2026-10-14', 100, 100), session('2026-10-19', 100, 100),
    session('2026-10-13', 100, 100, { status: 'active' }), session('2026-10-13', 100, 100, { status: 'cancelled' }),
  ];
  state.active = session('2026-10-13', 100, 100);
  const before = JSON.stringify(state);
  assert.deepEqual(volumeStats(state), {
    weeks: [{ date: '2026-09-21', volume: 150 }, { date: '2026-09-28', volume: 250 }, { date: '2026-10-05', volume: 350 }, { date: '2026-10-12', volume: 450 }],
    groups: [{ name: '腿部', volume: 11200, ratio: 1 }], total: 11200,
  });
  assert.equal(JSON.stringify(state), before);
});

test('volume groups sum exercise-group kg*reps, skip unknown groups and never split a session equally', () => {
  const volumeStats = api('volumeStats');
  const state = empty();
  state.history = [{ date: state.today, sets: [
    { exerciseId: 'squat', weight: 10, reps: 10 }, { exerciseId: 'row', weight: 20, reps: 10 },
    { exerciseId: 'push', weight: 5, reps: 10 }, { exerciseId: 'plank', weight: 0, reps: 30 },
    { exerciseId: 'squat', weight: 10, reps: 5 }, { exerciseId: 'unknown', weight: 10, reps: 10 },
  ] }];
  const stats = volumeStats(state);
  assert.deepEqual(stats.groups, [
    { name: '腿部', volume: 150, ratio: 0.375 }, { name: '背部', volume: 200, ratio: 0.5 },
    { name: '胸部', volume: 50, ratio: 0.125 }, { name: '核心', volume: 0, ratio: 0 },
  ]);
  // Total is the all-history grouped volume; weekly buckets retain all actual lifted volume.
  assert.equal(stats.total, 400);
  assert.equal(stats.weeks.at(-1).volume, 500);
});

test('empty and bodyweight volume remain actual zero, with no total-zero division', () => {
  const volumeStats = api('volumeStats');
  const state = empty();
  assert.deepEqual(volumeStats(state).groups, []);
  assert.equal(volumeStats(state).total, 0);
  assert.ok(volumeStats(state).weeks.every(w => w.volume === 0));
  state.history = [{ date: state.today, minutes: 300, sets: [{ exerciseId: 'plank', weight: 0, reps: 30 }] }];
  assert.deepEqual(volumeStats(state).groups, [{ name: '核心', volume: 0, ratio: 0 }]);
  assert.equal(volumeStats(state).total, 0);
  assert.equal(volumeStats({ today: state.today }).total, 0);
});

test('invalid sets, malformed dates and missing sets cannot inject NaN or cached volume', () => {
  const volumeStats = api('volumeStats');
  const state = empty();
  state.history = [
    { date: state.today, volume: 9999 }, { date: '2026-02-30', sets: [{ exerciseId: 'row', weight: 10, reps: 10 }] },
    { date: state.today, sets: [{}, { exerciseId: 'row', weight: -1, reps: 10 }, { exerciseId: 'row', weight: 10, reps: 1.5 }, { exerciseId: 'row', weight: 10, reps: 0 }] },
  ];
  for (const bad of [null, undefined, '', '10', NaN, Infinity]) {
    state.history[2].sets.push({ exerciseId: 'row', weight: bad, reps: 10 }, { exerciseId: 'squat', weight: 10, reps: bad });
  }
  assert.equal(volumeStats(state).total, 0);
  assert.ok(volumeStats(state).weeks.every(w => w.volume === 0));
  assert.deepEqual(volumeStats(state).groups, []);
});

test('volume weekly buckets remain chronological across year end and include legacy completed history', () => {
  const volumeStats = api('volumeStats');
  const state = empty('2027-01-01');
  state.history = [{ date: '2026-12-28', sets: [{ exerciseId: 'row', weight: 10, reps: 10 }] }];
  assert.deepEqual(volumeStats(state).weeks, [{ date: '2026-12-07', volume: 0 }, { date: '2026-12-14', volume: 0 }, { date: '2026-12-21', volume: 0 }, { date: '2026-12-28', volume: 100 }]);
});

test('sample volume trend preserves the original 1280/0/1440 source totals as one completed week', () => {
  const volumeStats = api('volumeStats');
  const stats = volumeStats(model.createState());
  assert.deepEqual(stats.weeks.map(w => w.volume), [0, 0, 2720, 0]);
  assert.equal(stats.total, 2720);
  assert.equal(stats.groups.reduce((sum, g) => sum + g.volume, 0), 2720);
});

// Failure target: adding graph APIs drops old exports or breaks the browser UMD branch.
test('CommonJS and browser UMD retain all old exports alongside the seven new APIs', () => {
  const old = ['createState', 'totals', 'addWater', 'addFoodMeal', 'removeMeal', 'restoreMeal', 'saveWeight', 'updateProfile', 'startWorkout', 'recordSet', 'finishWorkout', 'applyPlanProposal', 'ignorePlanProposal', 'searchFoods', 'createManualPlan', 'importExamples', 'exercises', 'foodExamples', 'weightChart', 'recentTraining', 'recordDish'];
  const additions = ['health', 'density', 'nutritionTrend', 'confidence', 'macroRatios', 'achievements', 'volumeStats'];
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(require.resolve('./model.js'), 'utf8'), context);
  for (const name of [...old, ...additions]) {
    assert.ok(Object.hasOwn(model, name), `CommonJS export ${name}`);
    assert.equal(typeof context.LocalFitModel[name], typeof model[name], `browser export ${name}`);
  }
  assert.equal(context.LocalFitModel.totals(context.LocalFitModel.createState()).kcal, 1248);
});
