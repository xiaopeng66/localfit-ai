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

// Food edits must not mutate previously recorded meal snapshots or bypass read-only origins.
test('editing and deleting an example food preserves recorded meals', () => {
  const M = require('./model.js'), state = createState();
  addFoodMeal(state, 'rice', 150, '晚餐');
  const meals = JSON.stringify(state.meals);
  const changed = M.updateFood(state, 'rice', { name: ' 新米饭 ', brand: '示例品牌', kcal: 120, protein: 3, carbs: 26, fat: 0 });
  assert.equal(changed.name, '新米饭'); assert.equal(changed.origin, 'example');
  assert.equal(state.foods.find(f => f.id === 'rice').kcal, 120);
  assert.equal(JSON.stringify(state.meals), meals);
  M.removeFood(state, 'rice');
  assert.equal(state.foods.some(f => f.id === 'rice'), false);
  assert.equal(JSON.stringify(state.meals), meals);
});

test('food edits validate atomically and built-in food cannot be edited or deleted', () => {
  const M = require('./model.js'), state = createState();
  const original = JSON.stringify(state.foods);
  for (const patch of [{ name: '' }, { kcal: -1 }, { protein: 'abc' }, { fat: Infinity }]) {
    assert.throws(() => M.updateFood(state, 'rice', patch));
    assert.equal(JSON.stringify(state.foods), original);
  }
  M.updateFood(state, 'rice', { protein: null, kcal: 0 });
  assert.equal(state.foods[0].protein, null); assert.equal(state.foods[0].kcal, 0);
  state.foods[0].origin = 'builtIn';
  const readOnly = JSON.stringify(state.foods);
  assert.throws(() => M.updateFood(state, 'rice', { name: '改名' }), /只读/);
  assert.throws(() => M.removeFood(state, 'rice'), /只读/);
  assert.equal(JSON.stringify(state.foods), readOnly);
});

test('missing food nutrients cannot become a confirmed meal through display zero-fill', () => {
  for (const patch of [{ kcal: 0 }, { kcal: null }, { protein: null }, { carbs: undefined }, { fat: NaN }]) {
    const state = createState(); Object.assign(state.foods[0], patch);
    const before = JSON.stringify(state.meals), nextId = state.nextId;
    assert.throws(() => addFoodMeal(state, 'rice', 100, '早餐'), /营养不完整/);
    assert.equal(JSON.stringify(state.meals), before); assert.equal(state.nextId, nextId);
  }
  const state = createState(); state.foods[0].fat = 0;
  assert.equal(addFoodMeal(state, 'rice', 100, '早餐').fat, 0);
});

test('exercise library filters and local creation never change training plans or statistics', () => {
  const M = require('./model.js'), state = createState();
  const before = JSON.stringify({ exercises: M.exercises, plans: state.plans, history: state.history, stats: M.volumeStats(state) });
  const legs = M.searchExerciseLibrary(state, '深蹲', '腿');
  assert.ok(legs.length >= 2); assert.ok(legs.every(row => row.group === '腿' && row.name.includes('深蹲')));
  assert.equal(M.searchExerciseLibrary(state, '深蹲', '胸').length, 0);
  assert.ok(M.searchExerciseLibrary(state, '胸').every(row => row.group === '胸'));
  const created = M.createLibraryExercise(state, { name: ' 自定义推举 ', group: '肩', equipment: '哑铃' });
  assert.equal(created.name, '自定义推举'); assert.equal(created.difficulty, null); assert.equal(created.popularity, null);
  assert.equal(M.searchExerciseLibrary(state, '自定义', '肩')[0].id, created.id);
  for (const invalid of [{ name: '', group: '肩', equipment: '哑铃' }, { name: '动作', group: '未知', equipment: '哑铃' }, { name: '动作', group: '胸', equipment: '伪造' }]) assert.throws(() => M.createLibraryExercise(state, invalid));
  assert.equal(JSON.stringify({ exercises: M.exercises, plans: state.plans, history: state.history, stats: M.volumeStats(state) }), before);
  assert.equal(createState().exerciseLibrary.some(row => row.id === created.id), false);
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
    '2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17', '2026-10-18',
  ]);
  assert.deepEqual(chart.slots.map(row => row.value), [62.6, 62.4, null, null, null, null, null]);
  assert.equal(chart.ticks.length, 4);
  assert.ok(chart.ticks[0] >= 62.6 && chart.ticks[3] <= 62.4);
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
    { date: '2026-10-06', minutes: 35, volume: 1440, sets: [{ exerciseId: 'row', weight: 12, reps: 120, volume: 1440 }] },
    { date: '2026-10-09', minutes: 24, volume: 0, sets: [{ exerciseId: 'plank', weight: 0, reps: 30, volume: 0 }] },
    { date: '2026-10-11', minutes: 32, volume: 1280, sets: [{ exerciseId: 'squat', weight: 16, reps: 80, volume: 1280 }] },
    { date: '2026-10-14', minutes: 99, volume: 9999, sets: [{ exerciseId: 'row', weight: 99, reps: 101, volume: 9999 }] },
  ];
  state.active = { date: '2026-10-13', minutes: 20, sets: [{ exerciseId: 'row', weight: 10, reps: 10, volume: 100 }] };
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

const model = require('./model.js');
const api = name => {
  assert.equal(typeof model[name], 'function', `${name} must be exported by the UMD model`);
  return model[name];
};
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-10, `${actual} != ${expected}`);

// Failure target: sample meals lose their item-level evidence or contaminate today's total.
test('sample records retain 1248 kcal today and seed a seven-day window with a real gap', () => {
  const state = createState();
  assert.equal(totals(state).kcal, 1248);
  assert.deepEqual(state.meals.filter(m => m.date === state.today).map(m => [m.id, m.source, m.itemCount]), [
    ['breakfast', 'confirmed', 3], ['lunch', 'estimated', 3], ['snack', 'confirmed', 1],
  ]);
  const prior = new Set(state.meals.filter(m => m.date < state.today).map(m => m.date));
  assert.ok(prior.has('2026-10-07'));
  assert.ok(prior.has('2026-10-12'));
  assert.ok(prior.size > 0 && prior.size < 6);
  for (const meal of state.meals) {
    assert.ok(meal.date >= '2026-10-07' && meal.date <= state.today);
    assert.ok(['confirmed', 'estimated'].includes(meal.source));
    assert.ok(Number.isInteger(meal.itemCount) && meal.itemCount > 0);
  }
});

test('sample profile provides explicit metabolism and calorie range instead of inventing a derived BMR', () => {
  const state = createState();
  assert.equal(state.profile.bmr, 1430);
  assert.equal(state.profile.calorieMin, 1700);
  assert.equal(state.profile.calorieMax, 1900);
});

test('food additions are one confirmed item and dish additions are one estimated item', () => {
  const state = createState();
  const food = addFoodMeal(state, 'rice', 100, '晚餐');
  const dish = recordDish(state, { name: '炖菜', kcal: 120, protein: 8, carbs: 15, fat: 3 }, 100, '晚餐');
  assert.deepEqual([food.source, food.itemCount], ['confirmed', 1]);
  assert.deepEqual([dish.source, dish.itemCount], ['estimated', 1]);
});

// Failure target: hard-coded confidence uses meal counts instead of item counts or survives deletion.
test('confidence derives the four-of-seven source fraction and follows add/delete/restore', () => {
  const confidence = api('confidence');
  const state = createState();
  assert.deepEqual(confidence(state), { confirmed: 4, estimated: 3, total: 7, ratio: 4 / 7 });
  const meal = addFoodMeal(state, 'rice', 100, '晚餐');
  assert.deepEqual(confidence(state), { confirmed: 5, estimated: 3, total: 8, ratio: 5 / 8 });
  removeMeal(state, meal.id);
  assert.equal(confidence(state).ratio, 4 / 7);
  restoreMeal(state, meal);
  recordDish(state, { name: '炖菜', kcal: 120, protein: 8, carbs: 15, fat: 3 }, 100, '晚餐');
  assert.deepEqual(confidence(state), { confirmed: 5, estimated: 4, total: 9, ratio: 5 / 9 });
});

test('confidence filters dates and distinguishes no evidence from zero confirmed evidence', () => {
  const confidence = api('confidence');
  const state = createState(true);
  assert.deepEqual(confidence(state), { confirmed: 0, estimated: 0, total: 0, ratio: null });
  state.meals = [{ date: '2026-10-12', source: 'estimated', itemCount: 2 }];
  assert.equal(confidence(state).ratio, null);
  assert.deepEqual(confidence(state, '2026-10-12'), { confirmed: 0, estimated: 2, total: 2, ratio: 0 });
});

test('confidence ignores missing, nonfinite, fractional and unknown evidence metadata', () => {
  const confidence = api('confidence');
  const state = createState(true);
  for (const itemCount of [undefined, null, '', '3', -1, 0, 1.5, NaN, Infinity]) {
    state.meals.push({ date: state.today, source: 'confirmed', itemCount });
  }
  state.meals.push({ date: state.today, source: 'unverified', itemCount: 5 });
  assert.deepEqual(confidence(state), { confirmed: 0, estimated: 0, total: 0, ratio: null });
  assert.equal(confidence({ today: state.today }).ratio, null);
});

// Failure target: BMI reads an arbitrary record, rounds before classifying, or fabricates absent health facts.
test('health derives BMI from latest eligible weight while retaining explicit profile facts', () => {
  const health = api('health');
  const state = createState();
  const result = health(state);
  near(result.bmi, 62.4 / (1.68 * 1.68));
  near(result.bmiPosition, (result.bmi - 15) * 5);
  assert.equal(result.bmiLabel, '正常');
  assert.equal(result.bmr, 1430);
  assert.deepEqual(result.range, { min: 1700, max: 1900 });
  assert.equal(result.waterRatio, 0.625);
  saveWeight(state, 63);
  near(health(state).bmi, 63 / (1.68 * 1.68));
});

test('health respects adult BMI thresholds and clamps only the axis position', () => {
  const health = api('health');
  const state = createState(true);
  state.profile.height = 200;
  for (const [bmi, label, position] of [
    [10, '偏瘦', 0], [18.49, '偏瘦', 17.45], [18.5, '正常', 17.5],
    [23.99, '正常', 44.95], [24, '超重', 45], [27.99, '超重', 64.95], [28, '肥胖', 65], [40, '肥胖', 100],
  ]) {
    state.weights = [{ date: state.today, value: bmi * 4 }];
    assert.equal(health(state).bmiLabel, label);
    near(health(state).bmiPosition, position);
  }
});

test('absent health inputs return null instead of invented zero or normal labels', () => {
  const health = api('health');
  assert.deepEqual(health({ today: '2026-10-13' }), {
    bmi: null, bmiPosition: null, bmiLabel: null, bmr: null, range: null, waterRatio: null,
  });
  const state = createState(true);
  assert.equal(health(state).bmi, null);
  assert.equal(health(state).bmr, null);
  assert.equal(health(state).range, null);
  assert.equal(health(state).waterRatio, 0);
});

test('health rejects invalid numeric inputs and reversed calorie ranges', () => {
  const health = api('health');
  for (const bad of [null, undefined, '', '168', 0, -1, NaN, Infinity]) {
    const state = createState();
    state.profile.height = bad;
    state.profile.bmr = bad;
    state.profile.waterGoal = bad;
    state.profile.calorieMin = bad;
    assert.equal(health(state).bmi, null);
    assert.equal(health(state).bmr, null);
    assert.equal(health(state).waterRatio, null);
    assert.equal(health(state).range, null);
  }
  const state = createState();
  state.profile.calorieMin = 2000;
  assert.equal(health(state).range, null);
  for (const water of [-1, null, undefined, '', '0', NaN, Infinity]) {
    state.water = water;
    assert.equal(health(state).waterRatio, null);
  }
});

test('water ratios preserve valid zero and over-goal consumption', () => {
  const health = api('health');
  const state = createState();
  state.water = 0;
  assert.equal(health(state).waterRatio, 0);
  state.water = 3000;
  assert.equal(health(state).waterRatio, 1.5);
});

// Failure target: density normalizes across the current list rather than the fixed 1000 kcal scale.
test('density uses a fixed 1000 kcal scale and clamps the ring without clamping the value', () => {
  const density = api('density');
  for (const [value, ratio] of [[116, 0.116], [377, 0.377], [1000, 1], [1200, 1]]) {
    assert.deepEqual(density(value), { value, ratio });
  }
});

// Intentional contract correction: native kcalOrMissing treats upstream 0 as absent.
test('density treats zero and missing calories as unknown', () => {
  const density = api('density');
  for (const input of [0, null, undefined, '', '116', -1, NaN, Infinity]) {
    assert.deepEqual(density(input), { value: null, ratio: 0 });
  }
});

// Failure target: macro fractions use grams or reported kcal rather than 4/4/9 energy.
test('macro ratios use macro energy, not grams or an unrelated kcal total', () => {
  const macroRatios = api('macroRatios');
  assert.deepEqual(macroRatios({ protein: 10, carbs: 20, fat: 10, kcal: 9999 }), {
    protein: 40 / 210, carbs: 80 / 210, fat: 90 / 210,
  });
  assert.deepEqual(macroRatios({ protein: 0, carbs: 0, fat: 1 }), { protein: 0, carbs: 0, fat: 1 });
});

test('macro ratios do not fabricate a donut for absent, invalid or all-zero nutrients', () => {
  const macroRatios = api('macroRatios');
  for (const input of [undefined, null, {}, { protein: 0, carbs: 0, fat: 0 }]) assert.equal(macroRatios(input), null);
  for (const bad of [null, undefined, '', '10', -1, NaN, Infinity]) {
    for (const key of ['protein', 'carbs', 'fat']) {
      assert.equal(macroRatios({ protein: 10, carbs: 10, fat: 10, [key]: bad }), null);
    }
  }
});

// Failure target: achievements are recomputed from today's short history rather than the stored maximum.
test('achievements show historical maximum snapshots without decrementing after record deletion', () => {
  const achievements = api('achievements');
  const state = createState();
  const before = achievements(state);
  assert.deepEqual(before.map(a => [a.label, a.target]), [
    ['7天连续打卡', 7], ['营养达人', 7], ['运动健将', 10], ['健康饮食', 30],
  ]);
  assert.ok(before.some(a => a.unlocked));
  assert.ok(before.some(a => a.tier === 'silver'));
  assert.ok(before.some(a => a.tier === 'bronze' && a.progress > 0));
  for (const row of before) {
    assert.ok(row.icon.length > 0);
    assert.equal(row.count, Math.floor(row.progress * row.target));
  }
  state.meals = [];
  state.history = [];
  assert.deepEqual(achievements(state), before);
});

test('achievement thresholds use inclusive silver and gold boundaries without early target counts', () => {
  const achievements = api('achievements');
  const state = createState(true);
  for (const [progress, tier, unlocked] of [[0.49, 'bronze', false], [0.5, 'silver', false], [0.99, 'silver', false], [1 - Number.EPSILON, 'silver', false], [1, 'gold', true], [2, 'gold', true]]) {
    state.achievementProgress = { 'streak-7': progress, 'nutrition-master': progress, 'workout-athlete': progress, 'healthy-diet': progress };
    for (const row of achievements(state)) {
      assert.equal(row.tier, tier);
      assert.equal(row.unlocked, unlocked);
      assert.equal(row.progress, Math.min(progress, 1));
      assert.equal(row.count, unlocked ? row.target : Math.floor(progress * row.target));
      if (!unlocked) assert.ok(row.count < row.target);
    }
  }
});

test('empty or invalid achievement snapshots never fabricate achieved progress', () => {
  const achievements = api('achievements');
  for (const state of [createState(true), {}, { achievementProgress: { 'streak-7': NaN, 'nutrition-master': Infinity, 'workout-athlete': -1, 'healthy-diet': '1' } }]) {
    const rows = achievements(state);
    assert.equal(rows.length, 4);
    for (const row of rows) assert.deepEqual([row.progress, row.count, row.unlocked, row.tier], [0, 0, false, 'bronze']);
  }
});

// Failure target: placeholder sets or stale cached volume misstate the training source data.
test('sample historical sets are real and reproduce all three existing volume totals', () => {
  const state = createState();
  assert.deepEqual(state.history.map(h => h.sets.length), [9, 6, 10]);
  assert.deepEqual(state.history.map(h => h.sets.reduce((sum, set) => sum + set.weight * set.reps, 0)), [1280, 0, 1440]);
  assert.deepEqual(state.history.map(h => h.volume), [1280, 0, 1440]);
  for (const session of state.history) {
    assert.equal(session.status, 'finished');
    for (const set of session.sets) {
      assert.ok(model.exercises.some(e => e.id === set.exerciseId));
      assert.equal(set.volume, set.weight * set.reps);
      assert.ok(set.reps > 0);
    }
  }
});

test('finishing recalculates set volume from weights and repetitions rather than cached volume', () => {
  const state = sample();
  startWorkout(state, 'base', 2);
  recordSet(state, 'squat', 12, 10);
  state.active.sets[0].volume = 9999;
  const summary = finishWorkout(state);
  assert.equal(summary.volume, 120);
  assert.equal(summary.sets[0].volume, 120);
  assert.equal(summary.status, 'finished');
});

test('recent training derives real volume and ignores explicitly unfinished sessions', () => {
  const state = sample();
  state.history = [
    { date: state.today, status: 'finished', minutes: 5, volume: 9999, sets: [{ exerciseId: 'row', weight: 12, reps: 10, volume: 9999 }] },
    { date: state.today, status: 'active', minutes: 99, sets: [{ exerciseId: 'row', weight: 100, reps: 100, volume: 10000 }] },
  ];
  assert.deepEqual(recentTraining(state), {
    count: 1, minutes: 5, volume: 120,
    days: ['2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10', '2026-10-11', '2026-10-12', '2026-10-13'].map(date => ({ date, minutes: date === state.today ? 5 : 0 })),
  });
});
