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
  // Library-only examples reuse names from the original design; never feed training statistics.
  const muscleGroups = ['胸', '背', '腿', '肩', '手臂', '核心', '全身'];
  const equipmentTypes = ['自重', '杠铃', '哑铃', '器械', '绳索', '其他'];
  const libraryExamples = [
    ...exercises.map(row => ({ id: row.id, name: row.name, group: row.group.replace('部', ''), equipment: row.equipment })),
    { id: 'library-barbell-squat', name: '杠铃深蹲', group: '腿', equipment: '杠铃' },
    { id: 'library-hack-squat', name: '哈克深蹲', group: '腿', equipment: '器械' },
    { id: 'library-bodyweight-squat', name: '徒手深蹲', group: '腿', equipment: '自重' },
    { id: 'library-dumbbell-press', name: '哑铃卧推', group: '胸', equipment: '哑铃' },
    { id: 'library-pull-up', name: '引体向上', group: '背', equipment: '自重' },
    { id: 'library-crunch', name: '卷腹', group: '核心', equipment: '自重' },
  ].map(row => ({ ...row, difficulty: null, popularity: null, origin: 'example' }));
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
  const nonnegative = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
  const positive = value => nonnegative(value) && value > 0;
  const clamp = value => Math.max(0, Math.min(1, value));
  function validDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(value + 'T12:00:00Z');
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }
  function shiftDate(value, days) {
    const date = new Date(value + 'T12:00:00Z');
    date.setUTCDate(date.getUTCDate() + days);
    return date.toISOString().slice(0, 10);
  }
  function mondayOf(value) {
    const weekday = new Date(value + 'T12:00:00Z').getUTCDay() || 7;
    return shiftDate(value, 1 - weekday);
  }
  function timestamp(row) {
    const value = typeof row.updatedAt === 'number' ? row.updatedAt : Date.parse(row.updatedAt);
    return Number.isFinite(value) ? value : -Infinity;
  }
  // Known update times win; ties and missing timestamps use the last insertion.
  function newest(rows) {
    return rows.reduce((best, row) => !best || timestamp(row) >= timestamp(best) ? row : best, null);
  }
  function weightsByDate(state) {
    const byDate = new Map();
    for (const row of state.weights || []) {
      if (!validDate(row.date) || row.date > state.today || !positive(row.value)) continue;
      const previous = byDate.get(row.date);
      if (!previous || timestamp(row) >= timestamp(previous)) byDate.set(row.date, row);
    }
    return byDate;
  }
  function latestWeight(byDate) {
    const latest = [...byDate.keys()].sort().pop();
    return byDate.get(latest)?.value ?? null;
  }
  function setVolume(set) {
    if (!set || !nonnegative(set.weight) || !Number.isInteger(set.reps) || set.reps <= 0) return null;
    const volume = set.weight * set.reps;
    return Number.isFinite(volume) ? volume : null;
  }
  function sessionVolume(session) {
    return round((session.sets || []).reduce((sum, set) => sum + (setVolume(set) ?? 0), 0));
  }
  function completedHistory(state) {
    // Legacy prototype history has no status; explicit unfinished statuses never count.
    return (state.history || []).filter(row => validDate(row.date) && row.date <= state.today &&
      (row.status === undefined || row.status === 'finished'));
  }
  function sampleHistory(id, name, date, minutes, sets) {
    const records = sets.map(([exerciseId, weight, reps]) => ({ exerciseId, weight, reps, volume: weight * reps }));
    return { id, name, date, minutes, status: 'finished', sets: records, volume: sessionVolume({ sets: records }) };
  }
  function createState(empty = false) {
    return {
      today: '2026-10-13',
      profile: { name: '小林', height: 168, waterGoal: 2000, stepGoal: 8000,
        bmr: empty ? null : 1430, calorieMin: empty ? null : 1700, calorieMax: empty ? null : 1900 },
      // Explicit historical maxima, not a reconstruction from this short preview history.
      achievementProgress: empty ? {} : { 'streak-7': 1, 'nutrition-master': 5 / 7, 'workout-athlete': 0.3, 'healthy-diet': 0.8 },
      energyGoal: 1800,
      water: empty ? 0 : 1250,
      steps: empty ? null : 6420,
      foods: empty ? [] : foodExamples.map(food => ({ ...food, origin: 'example' })),
      exerciseLibrary: clone(libraryExamples),
      meals: empty ? [] : [
        { id: 'breakfast', date: '2026-10-13', name: '燕麦牛奶 · 鸡蛋 · 香蕉', slot: '早餐', time: '08:10', kcal: 416, protein: 22, carbs: 55, fat: 12, icon: 'sun', source: 'confirmed', itemCount: 3 },
        { id: 'lunch', date: '2026-10-13', name: '米饭 · 香煎鸡胸 · 西兰花', slot: '午餐', time: '12:25', kcal: 612, protein: 43, carbs: 74, fat: 16, icon: 'bowl', source: 'estimated', itemCount: 3 },
        { id: 'snack', date: '2026-10-13', name: '原味酸奶', slot: '加餐', time: '15:00', kcal: 220, protein: 11, carbs: 32, fat: 6, icon: 'cup', source: 'confirmed', itemCount: 1 },
        // The six prior dates deliberately leave Oct 10 untracked (not zero intake).
        { id: 'prior-07', date: '2026-10-07', name: '燕麦 · 牛奶', slot: '早餐', time: '08:00', kcal: 460, protein: 24, carbs: 62, fat: 13, icon: 'sun', source: 'confirmed', itemCount: 2 },
        { id: 'prior-08', date: '2026-10-08', name: '鸡胸肉饭', slot: '午餐', time: '12:00', kcal: 630, protein: 42, carbs: 75, fat: 18, icon: 'bowl', source: 'estimated', itemCount: 3 },
        { id: 'prior-09', date: '2026-10-09', name: '豆腐蔬菜饭', slot: '晚餐', time: '18:20', kcal: 580, protein: 28, carbs: 72, fat: 19, icon: 'leaf', source: 'confirmed', itemCount: 3 },
        { id: 'prior-11', date: '2026-10-11', name: '鸡蛋 · 牛奶', slot: '早餐', time: '08:30', kcal: 360, protein: 23, carbs: 30, fat: 16, icon: 'sun', source: 'confirmed', itemCount: 2 },
        { id: 'prior-12', date: '2026-10-12', name: '米饭 · 鸡胸 · 蔬菜', slot: '午餐', time: '12:10', kcal: 610, protein: 40, carbs: 74, fat: 16, icon: 'bowl', source: 'estimated', itemCount: 3 },
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
        sampleHistory('history-1', '全身力量 A', '2026-10-11', 32, [
          ['squat', 20, 10], ['squat', 20, 10], ['squat', 20, 10],
          ['row', 20, 12], ['row', 20, 12], ['row', 20, 10],
          ['push', 0, 10], ['push', 0, 10], ['push', 0, 10],
        ]),
        sampleHistory('history-2', '核心与拉伸', '2026-10-09', 24, [
          ['plank', 0, 30], ['plank', 0, 30], ['plank', 0, 30],
          ['plank', 0, 30], ['plank', 0, 30], ['plank', 0, 30],
        ]),
        sampleHistory('history-3', '全身力量 A', '2026-10-06', 35, [
          ['squat', 24, 10], ['squat', 24, 10], ['squat', 24, 10],
          ['row', 20, 12], ['row', 20, 12], ['row', 20, 12],
          ['push', 0, 10], ['push', 0, 10], ['push', 0, 10], ['push', 0, 10],
        ]),
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
    if (!foodCanRecord(food)) throw new Error('营养不完整，请补全热量与三项营养后再记录');
    const weight = number(grams, 1, 5000, '食用克数');
    if (!['早餐', '午餐', '晚餐', '加餐'].includes(slot)) throw new Error('请选择餐次');
    const meal = { id: id(state, 'meal'), date: state.today, name: food.name + ' ' + weight + ' g', slot, time: '刚刚', icon: food.icon || 'bowl', source: 'confirmed', itemCount: 1 };
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
    const old = newest(state.weights.filter(row => row.date === state.today));
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
    const sets = state.active.sets.map(set => ({ ...set, volume: round(setVolume(set) ?? 0) }));
    const summary = { ...state.active, sets, status: 'finished', minutes: 0, volume: sessionVolume({ sets }) };
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
  function foodCanRecord(food) {
    return !!food && food.canJoinPlan !== false && positive(food.kcal) && ['protein', 'carbs', 'fat'].every(key => nonnegative(food[key]));
  }
  function editableFood(state, foodId) {
    const food = state.foods.find(row => row.id === foodId);
    if (!food) throw new Error('这条食物已不在示例库中');
    if (food.origin !== 'example') throw new Error('此条目只读，不能编辑或删除');
    return food;
  }
  function updateFood(state, foodId, input) {
    const food = editableFood(state, foodId);
    const next = { ...food };
    if (Object.hasOwn(input, 'name')) {
      next.name = String(input.name ?? '').trim();
      if (!next.name || Array.from(next.name).length > 80) throw new Error('食物名称需为 1–80 个字符');
    }
    if (Object.hasOwn(input, 'brand')) {
      next.brand = String(input.brand ?? '').trim();
      if (Array.from(next.brand).length > 80) throw new Error('品牌不能超过 80 个字符');
    }
    for (const [key, label, maximum] of [['kcal', '热量', 1000], ['protein', '蛋白质', 100], ['carbs', '碳水', 100], ['fat', '脂肪', 100]]) {
      if (!Object.hasOwn(input, key)) continue;
      const value = input[key];
      next[key] = value === null || value === undefined || String(value).trim() === '' ? null : number(value, 0, maximum, label);
    }
    Object.assign(food, next);
    return food;
  }
  function removeFood(state, foodId) {
    const food = editableFood(state, foodId);
    state.foods.splice(state.foods.indexOf(food), 1);
    return food;
  }
  function searchExerciseLibrary(state, query = '', group = '全部') {
    const term = query.trim().toLocaleLowerCase();
    return (state.exerciseLibrary || []).filter(row => (group === '全部' || row.group === group) &&
      (row.name + ' ' + row.group).toLocaleLowerCase().includes(term));
  }
  function createLibraryExercise(state, input) {
    const name = String(input.name ?? '').trim();
    if (!name || Array.from(name).length > 80) throw new Error('动作名称需为 1–80 个字符');
    if (!muscleGroups.includes(input.group)) throw new Error('请选择目标肌群');
    if (!equipmentTypes.includes(input.equipment)) throw new Error('请选择器械类型');
    const row = { id: id(state, 'library-user'), name, group: input.group, equipment: input.equipment,
      difficulty: null, popularity: null, origin: 'user' };
    state.exerciseLibrary.push(row);
    return row;
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
      if (!state.foods.some(item => item.id === food.id)) { state.foods.push({ ...food, origin: 'example' }); imported++; }
    }
    return { imported, skipped: foodExamples.length - imported };
  }
  function daysEnding(today) {
    return Array.from({ length: 7 }, (_, index) => shiftDate(today, index - 6));
  }
  function weightChart(state, mode = 'week') {
    const today = new Date(state.today + 'T12:00:00Z');
    const dates = mode === 'month'
      ? Array.from({ length: new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0)).getUTCDate() }, (_, index) =>
        state.today.slice(0, 8) + String(index + 1).padStart(2, '0'))
      : Array.from({ length: 7 }, (_, index) => shiftDate(mondayOf(state.today), index));
    const available = weightsByDate(state);
    const slots = dates.map((date, index) => {
      const value = available.get(date)?.value ?? null;
      const day = Number(date.slice(8));
      const axisLabel = mode === 'month'
        ? value !== null && ([1, 5, 10, 15, 20, 25].includes(day) || day === dates.length)
          ? Number(date.slice(5, 7)) + '/' + day : ''
        : ['一', '二', '三', '四', '五', '六', '日'][index];
      return { date, value, axisLabel };
    });
    const values = slots.filter(row => row.value !== null).map(row => row.value);
    const minimum = values.length ? Math.floor(Math.min(...values) * 2) / 2 - .5 : 60;
    const maximum = values.length ? Math.ceil(Math.max(...values) * 2) / 2 + .5 : 63;
    const ticks = Array.from({ length: 4 }, (_, index) => round(maximum - (maximum - minimum) * index / 3));
    return { slots, ticks, latest: latestWeight(available) };
  }
  function recentTraining(state) {
    const dates = daysEnding(state.today);
    const rows = completedHistory(state).filter(row => dates.includes(row.date));
    return {
      count: rows.length,
      minutes: rows.reduce((sum, row) => sum + row.minutes, 0),
      volume: round(rows.reduce((sum, row) => sum + sessionVolume(row), 0)),
      days: dates.map(date => ({ date, minutes: rows.filter(row => row.date === date).reduce((sum, row) => sum + row.minutes, 0) })),
    };
  }
  function recordDish(state, dish, grams, slot) {
    if (!dish || !dish.name) throw new Error('请先选择菜品');
    const weight = number(grams, 1, 5000, '食用克数');
    if (!['早餐', '午餐', '晚餐', '加餐'].includes(slot)) throw new Error('请选择餐次');
    const meal = { date: state.today, name: dish.name + ' ' + weight + ' g', slot, time: '刚刚', icon: dish.icon || 'bowl', source: 'estimated', itemCount: 1 };
    for (const key of ['kcal', 'protein', 'carbs', 'fat']) meal[key] = round(number(dish[key], 0, 10000, '营养数值') * weight / 100);
    meal.id = id(state, 'dish-meal');
    state.meals.push(meal);
    return meal;
  }
  function health(state) {
    const profile = state.profile || {};
    const weight = latestWeight(weightsByDate(state));
    const derivedBmi = positive(weight) && positive(profile.height) ? weight / (profile.height / 100) ** 2 : null;
    const bmi = positive(derivedBmi) ? derivedBmi : null;
    const waterRatio = nonnegative(state.water) && positive(profile.waterGoal) ? state.water / profile.waterGoal : null;
    return {
      bmi,
      bmiPosition: bmi === null ? null : clamp((bmi - 15) / 20) * 100,
      bmiLabel: bmi === null ? null : bmi < 18.5 ? '偏瘦' : bmi < 24 ? '正常' : bmi < 28 ? '超重' : '肥胖',
      bmr: positive(profile.bmr) ? profile.bmr : null,
      range: positive(profile.calorieMin) && positive(profile.calorieMax) && profile.calorieMax >= profile.calorieMin
        ? { min: profile.calorieMin, max: profile.calorieMax } : null,
      waterRatio: nonnegative(waterRatio) ? waterRatio : null,
    };
  }
  function density(kcal) {
    return positive(kcal) ? { value: kcal, ratio: clamp(kcal / 1000) } : { value: null, ratio: 0 };
  }
  function nutritionTrend(state) {
    const days = daysEnding(state.today).map(date => {
      const rows = (state.meals || []).filter(meal => meal.date === date && nonnegative(meal.kcal));
      return { date, kcal: rows.length ? round(rows.reduce((sum, meal) => sum + meal.kcal, 0)) : null };
    });
    return { days, trackedDays: days.filter(day => day.kcal !== null).length, target: positive(state.energyGoal) ? state.energyGoal : null };
  }
  function confidence(state, date = state.today) {
    let confirmed = 0;
    let estimated = 0;
    for (const meal of state.meals || []) {
      if (meal.date !== date || !Number.isInteger(meal.itemCount) || meal.itemCount <= 0) continue;
      if (meal.source === 'confirmed') confirmed += meal.itemCount;
      if (meal.source === 'estimated') estimated += meal.itemCount;
    }
    const total = confirmed + estimated;
    return { confirmed, estimated, total, ratio: total ? confirmed / total : null };
  }
  function macroRatios(total) {
    if (!total || !['protein', 'carbs', 'fat'].every(key => nonnegative(total[key]))) return null;
    const protein = total.protein * 4;
    const carbs = total.carbs * 4;
    const fat = total.fat * 9;
    const energy = protein + carbs + fat;
    return positive(energy) ? { protein: protein / energy, carbs: carbs / energy, fat: fat / energy } : null;
  }
  function achievements(state) {
    const specs = [
      ['streak-7', '7天连续打卡', 7, 'sun'],
      ['nutrition-master', '营养达人', 7, 'bowl'],
      ['workout-athlete', '运动健将', 10, 'dumbbell'],
      ['healthy-diet', '健康饮食', 30, 'leaf'],
    ];
    return specs.map(([key, label, target, icon]) => {
      const saved = state.achievementProgress?.[key];
      const progress = nonnegative(saved) ? clamp(saved) : 0;
      const unlocked = progress >= 1;
      return { label, tier: unlocked ? 'gold' : progress >= .5 ? 'silver' : 'bronze', progress, unlocked,
        count: unlocked ? target : Math.min(target - 1, Math.floor(progress * target)), target, icon };
    });
  }
  function volumeStats(state) {
    const monday = mondayOf(state.today);
    const weeks = Array.from({ length: 4 }, (_, index) => ({ date: shiftDate(monday, (index - 3) * 7), volume: 0 }));
    const grouped = new Map();
    for (const session of completedHistory(state)) {
      const bucket = weeks.find(week => week.date === mondayOf(session.date));
      if (bucket) bucket.volume += sessionVolume(session);
      // Group distribution and total cover all completed, non-future history, not just four weeks.
      for (const set of session.sets || []) {
        const volume = setVolume(set);
        const group = exercises.find(exercise => exercise.id === set?.exerciseId)?.group;
        if (volume === null || !group) continue;
        grouped.set(group, (grouped.get(group) || 0) + volume);
      }
    }
    for (const week of weeks) week.volume = round(week.volume);
    const total = round([...grouped.values()].reduce((sum, volume) => sum + volume, 0));
    const groups = [...new Set(exercises.map(exercise => exercise.group))].filter(name => grouped.has(name))
      .map(name => ({ name, volume: round(grouped.get(name)), ratio: total > 0 ? grouped.get(name) / total : 0 }));
    return { weeks, groups, total };
  }
  return { createState, totals, addWater, addFoodMeal, removeMeal, restoreMeal, saveWeight, updateProfile, startWorkout, recordSet, finishWorkout, applyPlanProposal, ignorePlanProposal, searchFoods, foodCanRecord, updateFood, removeFood, searchExerciseLibrary, createLibraryExercise, muscleGroups, equipmentTypes, createManualPlan, importExamples, exercises, foodExamples, weightChart, recentTraining, recordDish, health, density, nutritionTrend, confidence, macroRatios, achievements, volumeStats };
});
