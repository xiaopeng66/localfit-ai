const test = require('node:test');
const assert = require('node:assert/strict');
const {
  createState, totals, addWater, addFoodMeal, removeMeal, restoreMeal,
  saveWeight, updateProfile, startWorkout, recordSet, finishWorkout,
  applyPlanProposal, ignorePlanProposal, searchFoods, createManualPlan,
  importExamples, weightChart, recentTraining, recordDish,
} = require('./model.js');

const sample = () => ({
  today: '2026-10-13',
  profile: { name: '小林', height: 168, waterGoal: 2000, stepGoal: 8000 },
  energyGoal: 1800,
  water: 1250,
  foods: [{ id: 'rice', name: '米饭', brand: '', category: '主食', kcal: 116, protein: 2.6, carbs: 25.9, fat: 0.3 }],
  meals: [{ id: 'breakfast', date: '2026-10-13', name: '早餐', slot: '早餐', kcal: 416, protein: 22, carbs: 55, fat: 12 }],
  weights: [{ date: '2026-10-12', value: 62.6 }],
  plans: [{ id: 'base', name: '全身力量 A', days: [2, 4, 6], exercises: [{ id: 'squat', name: '高脚杯深蹲', sets: 3, reps: 10 }] }],
  active: null,
  history: [],
  proposalStatus: 'pending',
  nextId: 1,
});

// Failure target: view totals drift from the meal records or include a different day.
test('meal summary uses only the selected day and preserves negative remaining energy', () => {
  const state = sample();
  state.meals.push({ id: 'yesterday', date: '2026-10-12', kcal: 999, protein: 99, carbs: 99, fat: 99 });
  assert.deepEqual(totals(state), { kcal: 416, protein: 22, carbs: 55, fat: 12, remaining: 1384, count: 1 });
  state.energyGoal = 400;
  assert.equal(totals(state).remaining, -16);
});

test('adding water updates the current amount without replacing the target', () => {
  const state = sample();
  addWater(state, 250);
  assert.equal(state.water, 1500);
  assert.equal(state.profile.waterGoal, 2000);
});

test('invalid water amount cannot change state', () => {
  for (const amount of ['', 0, -1, NaN, 10001]) {
    const state = sample();
    assert.throws(() => addWater(state, amount));
    assert.equal(state.water, 1250);
  }
});

test('a 150 gram food record scales nutrients and becomes part of the summary', () => {
  const state = sample();
  const result = addFoodMeal(state, 'rice', 150, '午餐');
  assert.equal(result.kcal, 174);
  assert.equal(result.protein, 3.9);
  assert.equal(result.carbs, 38.9);
  assert.equal(totals(state).kcal, 590);
  assert.equal(totals(state).count, 2);
});

test('invalid grams and unknown food do not insert a meal', () => {
  const state = sample();
  for (const grams of ['', 0, -30, NaN, 5001]) {
    assert.throws(() => addFoodMeal(state, 'rice', grams, '晚餐'));
  }
  assert.throws(() => addFoodMeal(state, 'missing', 100, '晚餐'));
  assert.equal(state.meals.length, 1);
});

test('delete and undo restore the same record without duplicating it', () => {
  const state = sample();
  const removed = removeMeal(state, 'breakfast');
  assert.equal(totals(state).kcal, 0);
  restoreMeal(state, removed);
  restoreMeal(state, removed);
  assert.equal(totals(state).kcal, 416);
  assert.equal(state.meals.length, 1);
});

test('saving a weight replaces the same date instead of fabricating two measurements', () => {
  const state = sample();
  saveWeight(state, 62.4);
  saveWeight(state, 62.3);
  assert.deepEqual(state.weights, [{ date: '2026-10-12', value: 62.6 }, { date: '2026-10-13', value: 62.3 }]);
});

test('invalid weight cannot be written', () => {
  const state = sample();
  for (const value of ['', 0, -1, NaN, 301]) assert.throws(() => saveWeight(state, value));
  assert.equal(state.weights.length, 1);
});

test('profile updates validate all fields before committing any of them', () => {
  const state = sample();
  assert.throws(() => updateProfile(state, { name: '新昵称', waterGoal: 200, stepGoal: 8000 }));
  assert.equal(state.profile.name, '小林');
  updateProfile(state, { name: '  林同学  ', waterGoal: 2500, stepGoal: 10000 });
  assert.deepEqual(state.profile, { name: '林同学', height: 168, waterGoal: 2500, stepGoal: 10000 });
});

test('new workouts reject a different weekday and empty plans', () => {
  const state = sample();
  assert.throws(() => startWorkout(state, 'base', 4));
  assert.equal(state.active, null);
  state.plans[0].exercises = [];
  assert.throws(() => startWorkout(state, 'base', 2));
  assert.equal(state.active, null);
});

test('today starts one session and resuming does not replace recorded sets', () => {
  const state = sample();
  startWorkout(state, 'base', 2);
  recordSet(state, 'squat', 12, 10);
  const id = state.active.id;
  startWorkout(state, 'base', 2);
  assert.equal(state.active.id, id);
  assert.equal(state.active.sets.length, 1);
  assert.equal(state.active.sets[0].volume, 120);
});

test('invalid sets do not create activity or corrupt an active session', () => {
  const state = sample();
  assert.throws(() => recordSet(state, 'squat', 12, 10));
  startWorkout(state, 'base', 2);
  assert.throws(() => recordSet(state, 'missing', 12, 10));
  assert.throws(() => recordSet(state, 'squat', -1, 10));
  assert.throws(() => recordSet(state, 'squat', 12, 0));
  assert.throws(() => recordSet(state, 'squat', 12, 1.5));
  assert.equal(state.active.sets.length, 0);
});

test('finishing moves the session to history and preserves volume', () => {
  const state = sample();
  startWorkout(state, 'base', 2);
  recordSet(state, 'squat', 12, 10);
  recordSet(state, 'squat', 12, 8);
  const summary = finishWorkout(state);
  assert.equal(state.active, null);
  assert.equal(summary.volume, 216);
  assert.equal(summary.sets.length, 2);
  assert.equal(state.history.length, 1);
});

test('a proposal is added only on explicit apply and cannot be applied twice', () => {
  const state = sample();
  assert.equal(state.plans.length, 1);
  applyPlanProposal(state);
  applyPlanProposal(state);
  assert.equal(state.plans.length, 2);
  assert.equal(state.proposalStatus, 'applied');
});

test('ignoring a proposal does not write a plan', () => {
  const state = sample();
  ignorePlanProposal(state);
  assert.equal(state.plans.length, 1);
  assert.equal(state.proposalStatus, 'ignored');
  applyPlanProposal(state);
  assert.equal(state.plans.length, 1);
});

test('food search matches name and brand, with an honest empty result', () => {
  const state = sample();
  state.foods.push({ id: 'milk', name: '纯牛奶', brand: '光明', category: '奶类' });
  assert.deepEqual(searchFoods(state, ' 米饭 ').map(f => f.id), ['rice']);
  assert.deepEqual(searchFoods(state, '光明').map(f => f.id), ['milk']);
  assert.deepEqual(searchFoods(state, '没有这种食物'), []);
});

test('fresh empty preview has no food, meals, weights, plan, water, or invented steps', () => {
  const state = createState(true);
  assert.equal(state.foods.length, 0);
  assert.equal(state.meals.length, 0);
  assert.equal(state.weights.length, 0);
  assert.equal(state.plans.length, 0);
  assert.equal(state.water, 0);
  assert.equal(state.steps, null);
  assert.equal(state.active, null);
});

test('manual plan creation rejects missing content before inserting', () => {
  const state = sample();
  assert.throws(() => createManualPlan(state, '', ['squat']));
  assert.throws(() => createManualPlan(state, '力量 B', []));
  const plan = createManualPlan(state, '力量 B', ['squat']);
  assert.equal(plan.name, '力量 B');
  assert.equal(plan.exercises.length, 1);
  assert.deepEqual(plan.days, [2]);
  assert.equal(state.plans.length, 2);
});

test('example import fills an empty preview and skips the same rows on repeat', () => {
  const state = createState(true);
  const first = importExamples(state);
  assert.equal(first.imported, 8);
  assert.equal(first.skipped, 0);
  const second = importExamples(state);
  assert.equal(second.imported, 0);
  assert.equal(second.skipped, 8);
  assert.equal(state.foods.length, 8);
});

test('weekly weight columns keep missing dates empty instead of joining separate measurements', () => {
  const state = sample();
  state.weights.push({ date: '2026-10-08', value: 63 }, { date: '2026-10-13', value: 62.4 });
  const chart = weightChart(state, 'week');
  assert.deepEqual(chart.slots.map(row => row.date), [
    '2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10', '2026-10-11', '2026-10-12', '2026-10-13',
  ]);
  assert.deepEqual(chart.slots.map(row => row.value), [null, 63, null, null, null, 62.6, 62.4]);
  assert.equal(chart.ticks.length, 4);
  assert.ok(chart.ticks[0] >= 63 && chart.ticks[3] <= 62.4);
});

test('monthly weight grid includes the full month but never renders a future or missing value as a measurement', () => {
  const state = sample();
  state.weights.push({ date: '2026-10-20', value: 60 });
  const chart = weightChart(state, 'month');
  assert.equal(chart.slots.length, 31);
  assert.equal(chart.slots[0].date, '2026-10-01');
  assert.equal(chart.slots[30].date, '2026-10-31');
  assert.equal(chart.slots[11].value, 62.6);
  assert.equal(chart.slots[19].value, null);
  assert.equal(chart.slots[0].value, null);
});

test('empty weight chart supplies empty slots without a made-up latest weight', () => {
  const chart = weightChart(createState(true), 'week');
  assert.equal(chart.latest, null);
  assert.deepEqual(chart.slots.map(row => row.value), [null, null, null, null, null, null, null]);
});

test('recent training counts only completed sessions within the displayed seven days', () => {
  const state = sample();
  state.history = [
    { date: '2026-10-06', minutes: 35, volume: 1440, sets: [{}] },
    { date: '2026-10-09', minutes: 24, volume: 0, sets: [{}, {}] },
    { date: '2026-10-11', minutes: 32, volume: 1280, sets: [{}, {}, {}] },
    { date: '2026-10-14', minutes: 99, volume: 9999, sets: [{}] },
  ];
  state.active = { date: '2026-10-13', minutes: 20, sets: [{}] };
  const stats = recentTraining(state);
  assert.equal(stats.count, 2);
  assert.equal(stats.minutes, 56);
  assert.equal(stats.volume, 1280);
  assert.deepEqual(stats.days.map(row => row.minutes), [0, 0, 24, 0, 32, 0, 0]);
});

test('joining a recommended dish writes one consumed meal and recalculates today without creating a plan', () => {
  const state = sample();
  const dish = { id: 'stew', name: '示例炖菜', kcal: 120, protein: 8, carbs: 15, fat: 3, icon: 'bowl' };
  recordDish(state, dish, 250, '晚餐');
  assert.equal(state.meals.length, 2);
  assert.equal(state.meals[1].slot, '晚餐');
  assert.equal(state.meals[1].kcal, 300);
  assert.equal(state.meals[1].protein, 20);
  assert.equal(totals(state).kcal, 716);
  assert.equal(state.plans.length, 1);
  assert.equal(state.foods.length, 1);
});

test('invalid recommended dish portions never write a partial meal', () => {
  const state = sample();
  const dish = { name: '示例炖菜', kcal: 120, protein: 8, carbs: 15, fat: 3 };
  assert.throws(() => recordDish(state, dish, 0, '晚餐'));
  assert.throws(() => recordDish(state, dish, 250, '未知餐次'));
  assert.throws(() => recordDish(state, null, 250, '晚餐'));
  assert.equal(state.meals.length, 1);
});
