(function (root, factory) {
  const model = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = model;
  else root.LocalFitModel = model;
})(typeof globalThis === 'undefined' ? this : globalThis, function () {
  const foodExamples = [
    { id: 'rice', name: '米饭', brand: '', category: '主食', kcal: 116, protein: 2.6, carbs: 25.9, fat: 0.3, icon: 'bowl' },
    { id: 'chicken', name: '鸡胸肉', brand: '', category: '肉类', kcal: 133, protein: 19.4, carbs: 2.5, fat: 5, icon: 'protein' },
    { id: 'egg', name: '鸡蛋', brand: '', category: '蛋类', kcal: 144, protein: 13.3, carbs: 2.8, fat: 8.8, icon: 'egg' },
    { id: 'broccoli', name: '西兰花', brand: '', category: '蔬菜', kcal: 36, protein: 4.1, carbs: 4.3, fat: 0.6, icon: 'leaf' },
    { id: 'milk', name: '纯牛奶', brand: '示例品牌', category: '奶类', kcal: 64, protein: 3.2, carbs: 5, fat: 3.6, icon: 'milk' },
    { id: 'oats', name: '燕麦片', brand: '', category: '主食', kcal: 377, protein: 15, carbs: 66.9, fat: 6.7, icon: 'grain' },
    { id: 'banana', name: '香蕉', brand: '', category: '水果', kcal: 93, protein: 1.4, carbs: 22, fat: 0.2, icon: 'fruit' },
    { id: 'tofu', name: '北豆腐', brand: '', category: '豆类', kcal: 116, protein: 9.2, carbs: 4.8, fat: 8.1, icon: 'box' },
  ];
  const exercises = [
    { id: 'squat', name: '高脚杯深蹲', sets: 3, reps: 10, group: '腿部', equipment: '哑铃' },
    { id: 'row', name: '单臂哑铃划船', sets: 3, reps: 12, group: '背部', equipment: '哑铃' },
    { id: 'push', name: '俯卧撑', sets: 3, reps: 10, group: '胸部', equipment: '自重' },
    { id: 'plank', name: '平板支撑', sets: 3, reps: 30, group: '核心', equipment: '自重' },
  ];
  const clone = value => JSON.parse(JSON.stringify(value));
  const round = value => Math.round((value + Number.EPSILON) * 10) / 10;
  const id = (state, prefix) => prefix + '-' + state.nextId++;
  function number(value, min, max, label, integer = false) {
    if (value === '' || value === null || value === undefined) throw new Error('请填写' + label);
    const result = Number(value);
    if (!Number.isFinite(result) || result < min || result > max || (integer && !Number.isInteger(result))) {
      throw new Error(label + '需为 ' + min + '–' + max + (integer ? ' 的整数' : ' 之间的数值'));
    }
    return result;
  }
  function createState(empty = false) {
    return {
      today: '2026-10-13',
      profile: { name: '小林', height: 168, waterGoal: 2000, stepGoal: 8000 },
      energyGoal: 1800,
      water: empty ? 0 : 1250,
      steps: empty ? null : 6420,
      foods: empty ? [] : clone(foodExamples),
      meals: empty ? [] : [
        { id: 'breakfast', date: '2026-10-13', name: '燕麦牛奶 · 鸡蛋 · 香蕉', slot: '早餐', time: '08:10', kcal: 416, protein: 22, carbs: 55, fat: 12, icon: 'sun' },
        { id: 'lunch', date: '2026-10-13', name: '米饭 · 香煎鸡胸 · 西兰花', slot: '午餐', time: '12:25', kcal: 612, protein: 43, carbs: 74, fat: 16, icon: 'bowl' },
        { id: 'snack', date: '2026-10-13', name: '原味酸奶', slot: '加餐', time: '15:00', kcal: 220, protein: 11, carbs: 32, fat: 6, icon: 'cup' },
      ],
      weights: empty ? [] : [
        { date: '2026-10-01', value: 63.2 }, { date: '2026-10-03', value: 63.1 },
        { date: '2026-10-05', value: 62.9 }, { date: '2026-10-07', value: 63 },
        { date: '2026-10-09', value: 62.8 }, { date: '2026-10-11', value: 62.7 },
        { date: '2026-10-12', value: 62.6 }, { date: '2026-10-13', value: 62.4 },
      ],
      plans: empty ? [] : [{ id: 'base', name: '全身力量 A', days: [2, 4, 6], source: '手动创建', exercises: clone(exercises.slice(0, 3)) }],
      active: null,
      history: empty ? [] : [
        { id: 'history-1', name: '全身力量 A', date: '2026-10-11', minutes: 32, volume: 1280, sets: new Array(9).fill({}) },
        { id: 'history-2', name: '核心与拉伸', date: '2026-10-09', minutes: 24, volume: 0, sets: new Array(6).fill({}) },
        { id: 'history-3', name: '全身力量 A', date: '2026-10-06', minutes: 35, volume: 1440, sets: new Array(10).fill({}) },
      ],
      proposalStatus: 'pending',
      nextId: 1,
    };
  }
  function totals(state, date = state.today) {
    const rows = state.meals.filter(meal => meal.date === date);
    const result = { kcal: 0, protein: 0, carbs: 0, fat: 0, remaining: 0, count: rows.length };
    for (const key of ['kcal', 'protein', 'carbs', 'fat']) result[key] = round(rows.reduce((sum, meal) => sum + (meal[key] || 0), 0));
    result.remaining = round(state.energyGoal - result.kcal);
    return result;
  }
  function addWater(state, amount) {
    state.water += number(amount, 1, 10000, '饮水量');
    return state.water;
  }
  function addFoodMeal(state, foodId, grams, slot) {
    const food = state.foods.find(item => item.id === foodId);
    if (!food) throw new Error('请先选择食物');
    const weight = number(grams, 1, 5000, '食用克数');
    if (!['早餐', '午餐', '晚餐', '加餐'].includes(slot)) throw new Error('请选择餐次');
    const meal = { id: id(state, 'meal'), date: state.today, name: food.name + ' ' + weight + ' g', slot, time: '刚刚', icon: food.icon || 'bowl' };
    for (const key of ['kcal', 'protein', 'carbs', 'fat']) meal[key] = round(food[key] * weight / 100);
    state.meals.push(meal);
    return meal;
  }
  function removeMeal(state, mealId) {
    const index = state.meals.findIndex(item => item.id === mealId);
    return index < 0 ? null : state.meals.splice(index, 1)[0];
  }
  function restoreMeal(state, meal) {
    if (meal && !state.meals.some(item => item.id === meal.id)) state.meals.push(meal);
  }
  function saveWeight(state, value) {
    const weight = number(value, 20, 300, '体重');
    const old = state.weights.find(row => row.date === state.today);
    if (old) old.value = round(weight);
    else state.weights.push({ date: state.today, value: round(weight) });
    return weight;
  }
  function updateProfile(state, input) {
    const name = String(input.name || '').trim();
    if (!name || Array.from(name).length > 20) throw new Error('昵称需为 1–20 个字符');
    const waterGoal = number(input.waterGoal, 500, 6000, '每日饮水目标', true);
    const stepGoal = number(input.stepGoal, 1000, 50000, '每日步数目标', true);
    Object.assign(state.profile, { name, waterGoal, stepGoal });
  }
  function startWorkout(state, planId, weekday) {
    if (state.active) return state.active;
    const plan = state.plans.find(item => item.id === planId);
    const todayWeekday = new Date(state.today + 'T12:00:00').getDay() || 7;
    if (!plan || weekday !== todayWeekday || !plan.days.includes(weekday)) throw new Error('仅可开始今天对应的训练日');
    if (!plan.exercises.length) throw new Error('请先为这个训练日添加动作');
    state.active = { id: id(state, 'session'), planId, name: plan.name, date: state.today, exercises: clone(plan.exercises), sets: [] };
    return state.active;
  }
  function recordSet(state, exerciseId, weight, reps) {
    if (!state.active) throw new Error('请先开始训练');
    if (!state.active.exercises.some(item => item.id === exerciseId)) throw new Error('请选择这次训练中的动作');
    const kg = number(weight, 0, 500, '重量');
    const count = number(reps, 1, 100, '次数', true);
    const set = { exerciseId, weight: kg, reps: count, volume: round(kg * count) };
    state.active.sets.push(set);
    return set;
  }
  function finishWorkout(state) {
    if (!state.active) throw new Error('当前没有进行中的训练');
    const summary = { ...state.active, minutes: 0, volume: round(state.active.sets.reduce((sum, set) => sum + set.volume, 0)) };
    state.history.unshift(summary);
    state.active = null;
    return summary;
  }
  function applyPlanProposal(state) {
    if (state.proposalStatus !== 'pending') return;
    state.plans.push({ id: id(state, 'ai-plan'), name: '轻量全身训练', days: [2, 4, 6], source: 'AI 创建', exercises: clone(exercises.slice(0, 3)) });
    state.proposalStatus = 'applied';
  }
  function ignorePlanProposal(state) {
    if (state.proposalStatus === 'pending') state.proposalStatus = 'ignored';
  }
  function searchFoods(state, query = '', category = '全部') {
    const term = query.trim().toLocaleLowerCase();
    return state.foods.filter(food => (category === '全部' || food.category === category) && (food.name + ' ' + food.brand).toLocaleLowerCase().includes(term));
  }
  function createManualPlan(state, name, selected) {
    const title = String(name).trim();
    const chosen = exercises.filter(item => selected.includes(item.id));
    if (!title || title.length > 30) throw new Error('请填写 1–30 个字符的计划名称');
    if (!chosen.length) throw new Error('请至少选择一个动作');
    const plan = { id: id(state, 'manual'), name: title, days: [2], source: '手动创建', exercises: clone(chosen) };
    state.plans.push(plan);
    return plan;
  }
  function importExamples(state) {
    let imported = 0;
    for (const food of foodExamples) {
      if (!state.foods.some(item => item.id === food.id)) { state.foods.push(clone(food)); imported++; }
    }
    return { imported, skipped: foodExamples.length - imported };
  }
  function daysEnding(today) {
    const end = new Date(today + 'T12:00:00Z');
    return Array.from({ length: 7 }, (_, index) => {
      const day = new Date(end);
      day.setUTCDate(day.getUTCDate() - 6 + index);
      return day.toISOString().slice(0, 10);
    });
  }
  function weightChart(state, mode = 'week') {
    const today = new Date(state.today + 'T12:00:00Z');
    const dates = mode === 'month'
      ? Array.from({ length: new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0)).getUTCDate() }, (_, index) =>
        state.today.slice(0, 8) + String(index + 1).padStart(2, '0'))
      : daysEnding(state.today);
    const available = state.weights.filter(row => row.date <= state.today);
    const slots = dates.map(date => ({ date, value: available.find(row => row.date === date)?.value ?? null }));
    const values = slots.filter(row => row.value !== null).map(row => row.value);
    const minimum = values.length ? Math.floor(Math.min(...values) * 2) / 2 - .5 : 60;
    const maximum = values.length ? Math.ceil(Math.max(...values) * 2) / 2 + .5 : 63;
    const ticks = Array.from({ length: 4 }, (_, index) => round(maximum - (maximum - minimum) * index / 3));
    const latest = available.slice().sort((a, b) => b.date.localeCompare(a.date))[0]?.value ?? null;
    return { slots, ticks, latest };
  }
  function recentTraining(state) {
    const dates = daysEnding(state.today);
    const rows = state.history.filter(row => dates.includes(row.date));
    return {
      count: rows.length,
      minutes: rows.reduce((sum, row) => sum + row.minutes, 0),
      volume: round(rows.reduce((sum, row) => sum + row.volume, 0)),
      days: dates.map(date => ({ date, minutes: rows.filter(row => row.date === date).reduce((sum, row) => sum + row.minutes, 0) })),
    };
  }
  function recordDish(state, dish, grams, slot) {
    if (!dish || !dish.name) throw new Error('请先选择菜品');
    const weight = number(grams, 1, 5000, '食用克数');
    if (!['早餐', '午餐', '晚餐', '加餐'].includes(slot)) throw new Error('请选择餐次');
    const meal = { date: state.today, name: dish.name + ' ' + weight + ' g', slot, time: '刚刚', icon: dish.icon || 'bowl' };
    for (const key of ['kcal', 'protein', 'carbs', 'fat']) meal[key] = round(number(dish[key], 0, 10000, '营养数值') * weight / 100);
    meal.id = id(state, 'dish-meal');
    state.meals.push(meal);
    return meal;
  }
  return { createState, totals, addWater, addFoodMeal, removeMeal, restoreMeal, saveWeight, updateProfile, startWorkout, recordSet, finishWorkout, applyPlanProposal, ignorePlanProposal, searchFoods, createManualPlan, importExamples, exercises, foodExamples, weightChart, recentTraining, recordDish };
});
