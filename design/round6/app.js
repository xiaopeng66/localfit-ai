(() => {
  'use strict';
  const M = window.LocalFitModel;
  const params = new URLSearchParams(location.search);
  const pages = { today: '今日', nutrition: '饮食', ai: 'AI 助手', training: '训练', settings: '我的' };
  let state = M.createState(params.get('empty') === '1');
  const ui = {
    page: Object.hasOwn(pages, params.get('page')) ? params.get('page') : 'today',
    empty: params.get('empty') === '1', nutrition: 'records', training: 'plans',
    weightPeriod: 'week', query: '', category: '全部', sheet: null,
    messages: [], proposal: false, selectedDay: 2, dishChoice: { 早餐: 0, 午餐: 0, 晚餐: 0 }, theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  };
  const screen = document.getElementById('screen');
  const layer = document.getElementById('sheet-layer');
  const sheet = document.getElementById('app-sheet');
  const toastElement = document.getElementById('toast');
  let returnFocus = null;
  let toastTimer;
  let undoMeal = null;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
  const format = value => Number(value).toLocaleString('zh-CN', { maximumFractionDigits: 1 });
  const paths = {
    home: '<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
    bowl: '<path d="M3 11h18a9 9 0 0 1-18 0ZM8 21h8M8 3v4m4-5v5m4-4v4"/>',
    spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5ZM20 2v4m-2-2h4"/>',
    dumbbell: '<path d="m4 8 4-4m8 16 4-4M2 10l4 4m4-12 4 4m-7 5 4-4 6 6-4 4Zm-5 5 4 4m4-12 4 4"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    right: '<path d="m9 5 7 7-7 7"/>',
    back: '<path d="m14 5-7 7 7 7"/>',
    down: '<path d="m5 9 7 7 7-7"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    water: '<path d="M12 2c-2 4-7 8-7 12a7 7 0 0 0 14 0c0-4-5-8-7-12Z"/><path d="M8 14a4 4 0 0 0 3 4"/>',
    steps: '<path d="M7 4c3 0 3 4 2 6s-3 3-4 1S4 4 7 4ZM5 16c2-1 4 0 4 2s-3 4-4 2-1-3 0-4ZM17 2c3 1 2 5 1 7s-3 2-4 0 0-7 3-7Zm-2 11c2-1 4 1 3 3s-3 3-4 1 0-3 1-4Z"/>',
    scale: '<rect x="3" y="3" width="18" height="18" rx="4"/><path d="M7 8a7 7 0 0 1 10 0l-2 5H9Zm5 3 2-4"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"/>',
    cup: '<path d="M4 7h13v9a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Zm13 1h2a3 3 0 0 1 0 6h-2M7 2v2m4-2v2"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 10h18m-14 5h3m4 0h3"/>',
    leaf: '<path d="M4 20C1 7 11 3 21 3c0 11-5 20-17 17Zm0 0L16 8M9 15V9"/>',
    protein: '<path d="M5 5c4-4 12-1 14 3s1 10-3 11-5-3-7-5-7-4-4-9Z"/><path d="M9 6c3-1 7 2 8 4"/>',
    egg: '<path d="M19 15a7 7 0 0 1-14 0C5 8 9 3 12 3s7 5 7 12Z"/>',
    milk: '<path d="M8 2h8v4l3 4v12H5V10l3-4Zm0 4h8M5 10h14m-9 5h4"/>',
    grain: '<path d="M12 22V4M12 8C7 8 5 5 6 2c4 0 6 2 6 6Zm0 6c-5 0-7-3-6-6 4 0 6 2 6 6Zm0 6c-5 0-7-3-6-6 4 0 6 2 6 6Zm0-9c5 0 7-3 6-6-4 0-6 2-6 6Zm0 6c5 0 7-3 6-6-4 0-6 2-6 6Z"/>',
    fruit: '<path d="M10 6C8 3 5 3 4 5c-4 6 3 16 10 14 5-2 7-8 6-12-1 7-8 8-10-1Zm8-1 2-3"/>',
    box: '<path d="m3 7 9-4 9 4v11l-9 4-9-4Zm0 0 9 4 9-4m-9 4v11"/>',
    camera: '<path d="M8 5 6 8H3v13h18V8h-3l-2-3Z"/><circle cx="12" cy="14" r="4"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
    send: '<path d="m4 11 16-7-7 16-2-7Zm7 2 9-9"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    trash: '<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
    edit: '<path d="m4 16 12-12 4 4L8 20H4Zm9-9 4 4"/>',
    book: '<path d="M12 5C8 2 3 3 3 3v16s5-1 9 2c4-3 9-2 9-2V3s-5-1-9 2Zm0 0v16"/>',
    shield: '<path d="m12 2 8 3v7c0 5-5 8-8 10-3-2-8-5-8-10V5Zm-4 9 3 3 5-5"/>',
    download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
    upload: '<path d="M12 16V4m-5 5 5-5 5 5M4 16v5h16v-5"/>',
    target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
    settings: '<path d="m9 3-.5 3-3 1-.5 3-2 2 2 2 .5 3 3 1 .5 3h6l.5-3 3-1 .5-3 2-2-2-2-.5-3-3-1-.5-3Z"/><circle cx="12" cy="12" r="3"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v1"/>',
    play: '<path d="m8 4 12 8-12 8Z"/>',
    moon: '<path d="M20 14A9 9 0 0 1 10 3a9 9 0 1 0 10 11Z"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 5v2"/>',
  };
  const icon = (name, size = 20) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.info}</svg>`;
  const chip = (name, extra = '') => `<span class="icon-chip ${extra}">${icon(name)}</span>`;
  const button = (text, action, extra = '', attributes = '') => `<button type="button" class="btn ${extra}" data-action="${action}" ${attributes}>${text}</button>`;
  const note = text => `<p class="sheet-note">${text}</p>`;
  const empty = (name, title, message, action = '') => `<div class="empty-state">${chip(name)}<strong>${title}</strong><p>${message}</p>${action}</div>`;
  const head = (title, subtitle, controls = '') => `<header class="page-head"><div><h1>${title}</h1><p class="page-date">${subtitle}</p></div>${controls || `<button class="avatar" data-action="navigate" data-page="settings" aria-label="查看我的资料">${escape(Array.from(state.profile.name)[0])}</button>`}</header>`;
  const link = (text, action, attributes = '') => `<button class="link-button" type="button" data-action="${action}" ${attributes}>${text}</button>`;
  const form = (id, content, submit) => `<form id="${id}" novalidate>${content}<p class="form-error" role="alert"></p><button class="btn primary block confirm" type="submit">${submit}</button></form>`;
  const field = (label, id, value, attributes = '') => `<div class="form-field"><label for="${id}">${label}</label><input id="${id}" name="${id}" value="${escape(value)}" ${attributes}></div>`;
  function macros(total) {
    return `<div class="macro-summary">${[['protein', '蛋白质', 110], ['carbs', '碳水', 220], ['fat', '脂肪', 50]].map(([key, label, target]) => `<div class="macro-column"><span><i class="macro-dot ${key}"></i>${label}</span><div><b>${format(total[key])}</b><small> / ${target} g</small></div><div class="macro-track"><i class="${key}" style="width:${Math.min(100, total[key] / target * 100)}%"></i></div></div>`).join('')}</div>`;
  }
  function energy() {
    const total = M.totals(state);
    const percentage = Math.min(100, Math.round(total.kcal / state.energyGoal * 100));
    return `<section class="card energy-summary"><div class="card-row"><h2 class="section-title">今日能量</h2><span class="quiet-label">目标 ${format(state.energyGoal)} kcal</span></div><div class="energy-main"><div class="energy-numbers"><p>已摄入</p><div class="hero-value">${format(total.kcal)}<small>kcal</small></div><div class="energy-balance">${total.remaining >= 0 ? '还可摄入' : '已超出目标'} <b>${format(Math.abs(total.remaining))}</b> kcal</div></div><div class="energy-ring"><svg viewBox="0 0 120 120"><circle class="ring-track" cx="60" cy="60" r="49" fill="none" stroke-width="8"/><circle cx="60" cy="60" r="49" fill="none" stroke="var(--brand)" stroke-width="8" stroke-linecap="round" stroke-dasharray="${percentage / 100 * 307.9} 307.9"/></svg><div class="ring-center">${icon('bowl', 28)}<span class="ring-label">已达 ${percentage}%</span></div></div></div>${macros(total)}</section>`;
  }
  function weightBlock(large = false) {
    const chart = M.weightChart(state, ui.weightPeriod);
    const minimum = chart.ticks[3];
    const span = chart.ticks[0] - minimum;
    return `<section class="card weight-card"><div class="card-row"><h2 class="section-title">体重趋势</h2><div class="weight-tools"><div class="mini-tabs" role="group" aria-label="体重周期"><button data-action="weight-period" data-period="week" aria-pressed="${ui.weightPeriod === 'week'}">周</button><button data-action="weight-period" data-period="month" aria-pressed="${ui.weightPeriod === 'month'}">月</button></div><button class="icon-button circle-soft" data-action="weight-add" aria-label="记录体重">${icon('plus', 16)}</button></div></div><div class="weight-caption"><div class="weight-trend-value">${chart.latest === null ? '—' : format(chart.latest)}<small>kg</small></div><span>${chart.latest === null ? '记录第一次体重' : '最近一次记录'}${ui.weightPeriod === 'month' ? ' · 10 月' : ''}</span></div><div class="weight-chart ${large ? 'large' : ''}" aria-label="${ui.weightPeriod === 'week' ? '最近七天' : '本月'}体重图"><div class="chart-axis">${chart.ticks.map(tick => `<span>${tick.toFixed(1)}</span>`).join('')}</div><div class="weight-plot"><div class="chart-rules" aria-hidden="true"><i></i><i></i><i></i><i></i></div><div class="weight-columns ${ui.weightPeriod}">${chart.slots.map((row, index) => `<button class="weight-slot ${row.value === null ? 'no-data' : ''} ${row.date === state.today ? 'current' : ''}" data-action="weight-point" data-date="${row.date}" aria-label="${row.date.slice(5).replace('-', '月')}日，${row.value === null ? '未记录' : row.value + ' 千克'}"><span class="weight-bar-space"><i style="height:${row.value === null ? 0 : Math.max(5, (row.value - minimum) / span * 100)}%"></i>${row.value === null ? '<span class="no-data-dot"></span>' : ''}</span><small>${ui.weightPeriod === 'week' || index % 5 === 0 || index === 30 ? Number(row.date.slice(-2)) : ''}</small></button>`).join('')}</div></div></div><p class="chart-hint">${chart.latest === null ? '空槽代表尚未记录，不会自动补值' : '点击柱条查看当天记录；空槽表示未记录'}</p></section>`;
  }
  function mealRows(rows, removable = false) {
    return rows.map(meal => `<div class="meal-row">${chip(meal.icon || 'bowl', 'meal-symbol')}<div class="meal-info"><div class="meal-name">${escape(meal.slot)}<span>${escape(meal.time || '')}</span></div><div class="meal-meta">${escape(meal.name)}</div></div><div class="meal-kcal">${format(meal.kcal)}<small>kcal</small></div>${removable ? `<button class="icon-button" data-action="delete-meal" data-id="${escape(meal.id)}" aria-label="删除${escape(meal.slot)}记录：${escape(meal.name)}">${icon('trash', 16)}</button>` : ''}</div>`).join('');
  }
  function todayPage() {
    const rows = state.meals.filter(row => row.date === state.today);
    return `<div class="page today-page">${head(`你好，${escape(state.profile.name)}`, '10 月 13 日，星期二')}${energy()}${weightBlock()}<button class="ai-entry-line" data-action="workbench">${chip('spark', 'mint')}<span><b>AI 创作</b><small>让想法变成适合你的计划</small></span>${icon('right', 17)}</button><section class="card meals-card"><div class="section-title with-link"><h2 class="section-title">今天吃了什么</h2>${link('查看全部', 'nutrition-records')}</div>${rows.length ? mealRows(rows.slice(0, 3)) : empty('bowl', '从第一餐开始', '拍照识别或从食物库选择，轻松记录。')}${button(`${icon('plus', 16)} 记录饮食`, 'meal-add', 'block outline-brand')}</section><div class="water-steps-row"><section class="card metric-card water-card"><div class="metric-top"><h2 class="section-title">饮水</h2><span class="water-icon">${icon('water', 18)}</span></div><div class="metric-value">${format(state.water)}<small>ml</small></div><p class="metric-label">目标 ${format(state.profile.waterGoal)} ml</p><div class="progress-track"><div class="progress-fill" style="width:${Math.min(100, state.water / state.profile.waterGoal * 100)}%"></div></div>${button('+ 250 ml', 'water-quick', 'small water-button')}</section><section class="card metric-card"><div class="metric-top"><h2 class="section-title">步数</h2><span class="muted">${icon('steps', 18)}</span></div><div class="metric-value">${state.steps === null ? '—' : format(state.steps)}<small>步</small></div><p class="metric-label">${state.steps === null ? '尚未读取运动数据' : '目标 ' + format(state.profile.stepGoal) + ' 步'}</p><div class="progress-track"><div class="progress-fill brand" style="width:${state.steps === null ? 0 : Math.min(100, state.steps / state.profile.stepGoal * 100)}%"></div></div>${link('查看详情', 'steps-detail')}</section></div><p class="page-end">慢慢积累，每一笔都有意义。</p></div>`;
  }
  function nutritionPage() {
    return `<div class="page nutrition-page">${head('饮食', '把每一餐，记得更清楚', `<div class="head-actions"><button class="icon-button" data-action="camera" aria-label="拍照识别食物">${icon('camera')}</button><button class="icon-button circle-soft" data-action="meal-add" aria-label="添加饮食记录">${icon('plus')}</button></div>`)}<div class="tabs" role="tablist" aria-label="饮食分类">${[['records', '记录'], ['menus', '菜单'], ['foods', '食物库']].map(([key, title]) => `<button role="tab" aria-selected="${ui.nutrition === key}" data-action="nutrition-tab" data-tab="${key}">${title}</button>`).join('')}</div>${ui.nutrition === 'records' ? nutritionRecords() : ui.nutrition === 'menus' ? nutritionMenus() : nutritionFoods()}</div>`;
  }
  function nutritionRecords() {
    const total = M.totals(state);
    const slots = ['早餐', '午餐', '晚餐', '加餐'];
    return `<div class="date-picker"><span>${icon('calendar', 17)} 2026 年 10 月 13 日</span><span class="pill today">今天</span></div><section class="nutrition-summary"><div class="summary-strip"><div><span class="quiet-label">今日摄入</span><div class="num">${format(total.kcal)}<small>kcal</small></div></div><div class="summary-remaining"><span class="quiet-label">${total.remaining < 0 ? '超出目标' : '距目标还差'}</span><b>${format(Math.abs(total.remaining))}<small> kcal</small></b></div></div><div class="energy-progress"><i style="width:${Math.min(100, total.kcal / state.energyGoal * 100)}%"></i></div>${macros(total)}</section><div class="meal-timeline">${slots.map(slot => {
      const rows = state.meals.filter(row => row.date === state.today && row.slot === slot);
      return `<section class="card meal-slot-card"><div class="slot-heading"><h2>${slot}</h2><span>${rows.length ? format(rows.reduce((sum, row) => sum + row.kcal, 0)) + ' kcal' : '尚未记录'}</span><button class="icon-button" data-action="meal-add" data-slot="${slot}" aria-label="记录${slot}">${icon('plus', 18)}</button></div>${rows.length ? mealRows(rows, true) : `<button class="empty-meal" data-action="meal-add" data-slot="${slot}">${icon('bowl', 19)}<span>给${slot}留一个位置</span></button>`}</section>`;
    }).join('')}</div><div class="sticky-action">${button(`${icon('plus', 18)} 记录饮食`, 'meal-add', 'primary block')}</div>`;
  }
  const dishes = [
    { id: 'oat-bowl', name: '牛奶燕麦粥', kcal: 96, protein: 4.7, carbs: 13.4, fat: 2.6, icon: 'bowl', place: '一食堂 · 早餐窗口' },
    { id: 'egg-custard', name: '鲜蔬蒸蛋', kcal: 84, protein: 7.6, carbs: 3.1, fat: 4.6, icon: 'egg', place: '一食堂 · 蒸菜窗口' },
    { id: 'chicken-dish', name: '西兰花炒鸡丁', kcal: 118, protein: 14.2, carbs: 5.8, fat: 4.3, icon: 'protein', place: '二食堂 · 家常菜窗口' },
    { id: 'tofu-dish', name: '番茄烧豆腐', kcal: 92, protein: 5.8, carbs: 6.7, fat: 4.9, icon: 'leaf', place: '二食堂 · 素菜窗口' },
  ];
  const dishCandidates = slot => slot === '早餐' ? dishes.slice(0, 2) : dishes.slice(2);
  function nutritionMenus() {
    return `<div class="section-title with-link"><h2 class="section-title">每日菜品推荐</h2><span class="pill">本地已分析菜品</span></div><p class="intro-copy">先看看今天的候选，选好份量后再加入饮食记录。</p>${ui.empty ? empty('bowl', '还没有已分析菜品', '先维护食堂目录或分析菜品，再查看每日候选。', button('管理食堂目录', 'canteen-directory', 'outline-brand')) : ['早餐', '午餐', '晚餐'].map(slot => {
      const candidates = dishCandidates(slot);
      const dish = candidates[ui.dishChoice[slot] % candidates.length];
      return `<section class="card dish-recommendation"><div class="section-title with-link"><h3 class="section-title">${slot}推荐</h3>${link('换一个', 'swap-dish', `data-slot="${slot}"`)}</div><div class="dish-title">${chip(dish.icon, 'mint')}<div><h3>${dish.name}</h3><p>${dish.place}</p></div></div><div class="macro-tags"><span class="macro-tag protein">蛋白质 ${dish.protein} g</span><span class="macro-tag carbs">${dish.kcal} kcal / 100 g</span></div><div class="dish-action-row">${link(`查看候选 ${candidates.length} 道`, 'dish-candidates', `data-slot="${slot}"`)}${button(`加入${slot}`, 'dish-add', 'outline-brand', `data-id="${dish.id}" data-slot="${slot}"`)}</div></section>`;
    }).join('')}<button class="list-link" data-action="canteen-directory">${chip('book')}<span><b>管理食堂目录</b><small>地点、窗口与菜品</small></span>${icon('right', 16)}</button><p class="subtle-note">候选与营养值为演示样例；本稿不重写实际推荐算法。加入餐次会记为已吃，保存前请确认。</p>`;
  }
  function foodResults() {
    const rows = M.searchFoods(state, ui.query, ui.category);
    return `<div class="section-title with-link"><span class="quiet-label">${ui.query ? '找到' : '全部'} ${rows.length} 种食物</span><span class="quiet-label">每 100 g</span></div>${rows.length ? `<div class="card food-list">${rows.map(food => `<button class="food-row" data-action="food-detail" data-id="${food.id}" aria-label="查看${escape(food.name)}">${chip(food.icon, 'food-symbol')}<span class="food-main"><span class="food-name">${escape(food.name)}</span><span class="food-tags">${escape(food.category)}${food.brand ? ' · ' + escape(food.brand) : ''}</span></span><span class="food-kcal">${food.kcal}<small>kcal</small></span>${icon('right', 15)}</button>`).join('')}</div>` : empty('search', state.foods.length ? '没有找到这类食物' : '食物库还是空的', state.foods.length ? '试试其他名称，或切换分类。' : '新安装时为空库，可导入自己的食物数据。', state.foods.length ? button('清除筛选', 'clear-filter', 'small') : button('导入示例食物', 'import-examples', 'outline-brand'))}`;
  }
  function nutritionFoods() {
    return `<label class="search-field">${icon('search', 18)}<input type="search" id="food-query" value="${escape(ui.query)}" placeholder="搜索食物名称或品牌" aria-label="搜索食物名称或品牌"></label><div class="food-category-row" aria-label="食物类别">${['全部', '主食', '肉类', '蛋类', '蔬菜', '奶类', '水果', '豆类'].map(category => `<button data-action="category" data-category="${category}" aria-pressed="${ui.category === category}">${category}</button>`).join('')}</div><div id="food-results" class="food-results" aria-live="polite">${foodResults()}</div><div class="library-footer">${link(`${icon('upload', 16)} 导入食物数据`, 'import-info')}${link('食物管理', 'food-management')}</div><p class="subtle-note">当前为演示食物，营养值仅用于界面预览。</p>`;
  }
  function proposal() {
    return `<section class="card proposal-card"><div class="card-row"><span class="pill proposal-tag">${icon('edit', 13)}训练计划草案</span><span class="quiet-label">${state.proposalStatus === 'pending' ? '待你确认' : state.proposalStatus === 'applied' ? '已应用' : '已忽略'}</span></div><h3>轻量全身训练</h3><p class="intro-copy">每周 3 次，从熟悉的动作开始。</p><div class="proposal-exercises">${['高脚杯深蹲', '单臂哑铃划船', '俯卧撑'].map((name, index) => `<div><span>${name}</span><b>3 组 × ${index === 1 ? 12 : 10} 次</b></div>`).join('')}</div>${state.proposalStatus === 'pending' ? `<div class="form-actions">${button('忽略', 'ignore-proposal', 'ghost')}${button('应用计划', 'apply-proposal', 'primary')}</div><p class="status-line">确认应用后，才会加入训练计划。</p>` : `<p class="proposal-status">${icon(state.proposalStatus === 'applied' ? 'check' : 'close', 17)}${state.proposalStatus === 'applied' ? '已应用到演示训练计划' : '已忽略，未写入任何计划'}</p>`}</section>`;
  }
  function aiPage() {
    return `<div class="page ai-page">${head('AI 助手', '一起把计划，变得可执行')}<p class="chat-demo-notice">离线演示对话，不调用 AI 服务</p><div class="chat-scroll"><div class="assistant-intro"><span class="assistant-symbol">${icon('spark', 30)}</span><h2>从今天的一小步开始。</h2><p>聊聊吃什么、怎么练，<br>也可以一起整理你的计划。</p></div>${ui.messages.map(message => `<div class="bubble ${message.role}">${escape(message.text).replace(/\n/g, '<br>')}</div>`).join('')}${ui.proposal ? proposal() : `<div class="conversation-starters"><button data-action="ai-prompt" data-prompt="今天晚餐怎么搭配？">${icon('bowl', 18)}<span>今天晚餐怎么搭配？</span>${icon('right', 15)}</button><button data-action="ai-plan">${icon('dumbbell', 18)}<span>制定轻量训练计划</span>${icon('right', 15)}</button></div>`}</div><div class="chat-footer"><div class="quick-actions"><button data-action="camera">${icon('camera', 15)}拍照识别</button><button data-action="album">${icon('image', 15)}相册</button><button data-action="workbench">${icon('spark', 15)}AI 创作</button></div><form id="chat-form" class="chat-input-bar"><input name="message" aria-label="发给 AI 助手的消息" placeholder="说说你的想法…" autocomplete="off" maxlength="1000"><button type="submit" aria-label="发送消息">${icon('send', 20)}</button></form><p>建议供参考，身体不适请咨询专业人士。</p></div></div>`;
  }
  function trainingStats() {
    const stats = M.recentTraining(state);
    return `<section class="card training-summary"><div class="section-title with-link"><h2 class="section-title">近 7 天</h2><span class="quiet-label">10.07 — 10.13</span></div><div class="training-overview"><div><b>${stats.count}<small>次</small></b><span>训练次数</span></div><div><b>${stats.minutes}<small>min</small></b><span>累计时长</span></div><div><b>—<small>kcal</small></b><span>消耗未估算</span></div></div><div class="week-bars">${stats.days.map(day => `<div class="bar-col"><div class="bar ${day.date === state.today ? 'active' : ''}" style="height:${day.minutes ? Math.max(6, day.minutes / Math.max(40, ...stats.days.map(row => row.minutes)) * 42) : 3}px" title="${day.date}：${day.minutes} 分钟"></div><span class="bar-label">${Number(day.date.slice(-2))}日</span></div>`).join('')}</div></section>`;
  }
  function trainingPage() {
    const plans = state.plans;
    return `<div class="page training-page">${head('训练', '把专注，留给每一个动作', `<button class="icon-button" data-action="exercise-library" aria-label="查看动作库">${icon('book', 22)}</button>`)}${trainingStats()}<div class="tabs" role="tablist" aria-label="训练分类">${[['plans', '我的计划'], ['history', '训练历史']].map(([key, title]) => `<button role="tab" aria-selected="${ui.training === key}" data-action="training-tab" data-tab="${key}">${title}</button>`).join('')}</div>${state.active ? `<button class="active-session" data-action="active-workout"><span class="session-pulse"></span><span><b>${escape(state.active.name)}</b><small>进行中 · 已记录 ${state.active.sets.length} 组</small></span><span>继续${icon('right', 15)}</span></button>` : ''}${ui.training === 'plans' ? `${plans.length ? plans.map(plan => `<section class="card plan-card"><div class="plan-head"><span class="pill">${escape(plan.source || '我的计划')}</span><button class="icon-button" data-action="plan-detail" data-id="${plan.id}" aria-label="查看${escape(plan.name)}计划详情">${icon('right', 18)}</button></div><h2>${escape(plan.name)}</h2><p>${plan.exercises.length} 个动作 · 每周 ${plan.days.length} 次</p><div class="plan-days" aria-label="每周训练安排">${['一', '二', '三', '四', '五', '六', '日'].map((day, index) => `<span class="day-chip ${plan.days.includes(index + 1) ? 'on' : ''} ${index === 1 ? 'today' : ''}">${day}</span>`).join('')}</div><div class="plan-today"><span>${plan.days.includes(2) ? '今天是训练日' : '今天休息，恢复也很重要'}</span>${button(state.active ? '继续训练' : '开始训练', 'start-workout', 'primary', `data-id="${plan.id}" ${!state.active && !plan.days.includes(2) ? 'disabled' : ''}`)}</div></section>`).join('') : empty('dumbbell', '你的第一个计划，正在等你', '手动创建，或先让 AI 给一份草案。', button('创建训练计划', 'create-plan', 'primary'))}<div class="create-plan-row">${button(`${icon('plus', 17)} 手动创建`, 'create-plan', 'block')}${button(`${icon('spark', 17)} AI 创建`, 'ai-plan', 'block outline-brand')}</div>` : trainingHistory()}<button class="list-link" data-action="exercise-library">${chip('book')}<span><b>动作库</b><small>先了解动作，再开始训练</small></span>${icon('right', 16)}</button></div>`;
  }
  function trainingHistory() {
    return state.history.length ? `<section class="card history-list">${state.history.map(row => `<button class="history-row" data-action="history-detail" data-id="${row.id}">${chip('check')}<span class="history-main"><span class="h-name">${escape(row.name)}</span><span class="h-meta">${row.date.slice(5).replace('-', ' 月 ')} 日 · ${row.minutes} 分钟 · ${row.sets.length} 组</span></span>${icon('right', 16)}</button>`).join('')}</section>` : empty('calendar', '还没有训练记录', '完成一次训练后，会在这里留下足迹。');
  }
  function settingsRow(name, title, subtitle, action, extra = '') {
    return `<button class="settings-row ${extra}" data-action="${action}">${chip(name)}<span class="settings-main"><span class="settings-title">${title}</span>${subtitle ? `<span class="settings-sub">${subtitle}</span>` : ''}</span><span class="chev">${icon('right', 15)}</span></button>`;
  }
  function settingsPage() {
    const last = M.weightChart(state).latest;
    return `<div class="page settings-page">${head('我的', '关于你，也关于你的数据', '<span class="local-badge">本地优先</span>')}<button class="card profile-card" data-action="profile-edit"><span class="avatar">${escape(Array.from(state.profile.name)[0])}</span><span class="profile-main"><span class="profile-name">${escape(state.profile.name)}</span><span class="profile-meta">查看与编辑个人资料</span></span>${icon('right', 17)}</button><div class="quick-stats profile-stats"><div class="stat"><b>${state.meals.length}</b><span>饮食记录</span></div><div class="stat"><b>${state.history.length}</b><span>完成训练</span></div><div class="stat"><b>${last === null ? '—' : last}<small> kg</small></b><span>最近体重</span></div></div><section><h2 class="group-label">身体与目标</h2><div class="card settings-group">${settingsRow('user', '个人资料', '身体数据、活动水平与偏好', 'profile-edit')}${settingsRow('target', '每日目标', '饮水 ' + format(state.profile.waterGoal) + ' ml · 步数 ' + format(state.profile.stepGoal), 'profile-edit')}${settingsRow('scale', '体重记录', '查看趋势或记录今天的体重', 'weight-history')}</div></section><section><h2 class="group-label">AI 与数据</h2><div class="card settings-group">${settingsRow('spark', 'AI 模型', '服务提供商与模型', 'ai-settings')}${settingsRow('shield', '备份数据', '口令加密的 .lfb 文件', 'backup')}${settingsRow('upload', '恢复数据', '从加密备份恢复', 'restore-info')}${settingsRow('download', '导出饮食记录', '', 'export-diet')}${settingsRow('download', '导出训练记录', '', 'export-training')}${settingsRow('download', '导出食物数据', '', 'export-food')}${settingsRow('clock', '自动本地备份', '现有备份策略与开关不变', 'auto-backup-info')}</div></section><section><h2 class="group-label">食材与设备</h2><div class="card settings-group">${settingsRow('bowl', '食材数据库', state.foods.length + ' 条演示食物', 'open-foods')}${settingsRow('plus', '添加食物数据', '手动添加或导入目录', 'food-management')}${settingsRow('book', '维护地点 / 窗口 / 菜品', '食堂目录与已分析菜品', 'canteen-directory')}${settingsRow('steps', '步数与身体活动', '运动数据与权限', 'steps-detail')}${settingsRow('scale', '电子体重秤', '接口预留，小米秤暂未适配', 'scale-info')}</div></section><section><h2 class="group-label">关于</h2><div class="card settings-group">${settingsRow('info', '关于 LocalFit AI', '版本、帮助、来源与反馈', 'about')}</div></section><div class="card settings-group">${settingsRow('trash', '清除所有数据', '此设计稿只展示确认流程', 'clear-preview', 'danger')}</div><p class="page-end">LocalFit AI<br><span>让每一次记录，回到你自己。</span></p></div>`;
  }
  const designNotes = {
    today: [['能量，一眼读懂', '保留营养语义色，用餐盘环与大数字建立主次，而不是放一整块绿色背景。'], ['体重，诚实地展示', '每一天都有位置；没记录就留空，不用连线制造不存在的变化。'], ['动作，靠近内容', '记饮食、记体重、加水，都放在相应信息旁。']],
    nutrition: [['三种信息，各就各位', '记录是已吃的事实，菜单是每日菜品推荐，食物库是营养资料。'], ['列表，方便扫读', '名称左对齐、能量右对齐；线性小图标替代并不存在的食物照片。'], ['空状态，不伪造', '新装食物库保持为空，导入后的数据再逐条呈现。']],
    ai: [['先对话，再行动', '中央 AI 入口仍然直接进入对话，不绕到功能大厅。'], ['草案与事实分开', '生成计划后明确显示应用与忽略，只有应用才加入计划。'], ['输入，始终顺手', '照片入口与输入框合在底部，建议卡不挤占操作区。']],
    training: [['今天的行动更突出', '计划、每周安排和开始按钮在同一区域，减少来回寻找。'], ['统计，不冒充精确', '次数与时长来自记录；未估算的训练消耗显示横线。'], ['每组，都有反馈', '记录动作、重量与次数后立即显示，训练中途退出也能继续。']],
    settings: [['围绕用途重新分组', '身体与目标、AI 与数据、食材与设备、关于，各自成组。'], ['数据，由你掌握', '本地备份、三类导出与食物管理不混在同一个大列表里。'], ['危险操作，独立确认', '清空内置食物与清空全部数据分开，不做同义按钮。']],
  };
  function render(keepScroll = false) {
    const scroll = screen.scrollTop;
    screen.innerHTML = ({ today: todayPage, nutrition: nutritionPage, ai: aiPage, training: trainingPage, settings: settingsPage })[ui.page]();
    document.getElementById('preview-page-name').textContent = pages[ui.page];
    document.getElementById('app-nav').innerHTML = [['today', 'home', '今日'], ['nutrition', 'bowl', '饮食'], ['ai', 'spark', 'AI'], ['training', 'dumbbell', '训练'], ['settings', 'user', '我的']].map(([key, name, label]) => `<button class="nav-item ${key === 'ai' ? 'nav-ai' : ''}" data-action="navigate" data-page="${key}" ${ui.page === key ? 'aria-current="page"' : ''}><span class="nav-icon">${icon(name, key === 'ai' ? 25 : 22)}</span><span>${label}</span></button>`).join('');
    document.querySelectorAll('.page-directory button').forEach(item => {
      if (item.dataset.page === ui.page) item.setAttribute('aria-current', 'page');
      else item.removeAttribute('aria-current');
    });
    document.getElementById('page-notes').innerHTML = designNotes[ui.page].map(([title, text]) => `<div class="note-item"><b>${title}</b><span>${text}</span></div>`).join('');
    screen.scrollTop = keepScroll ? scroll : 0;
    document.title = `${pages[ui.page]} · LocalFit AI 界面升级稿`;
  }
  function navigate(page) {
    if (!Object.hasOwn(pages, page)) return;
    closeSheet();
    ui.page = page;
    render();
  }
  function toast(message, canUndo = false) {
    clearTimeout(toastTimer);
    toastElement.innerHTML = `<span>${escape(message)}</span>${canUndo ? '<button data-action="undo-meal">撤销</button>' : ''}`;
    toastElement.hidden = false;
    toastTimer = setTimeout(() => { toastElement.hidden = true; }, canUndo ? 8000 : 3400);
  }
  function openSheet(title, content, kind = 'standard') {
    if (layer.hidden) returnFocus = document.activeElement;
    ui.sheet = kind;
    document.getElementById('sheet-title').textContent = title;
    document.getElementById('sheet-content').innerHTML = content;
    const draggable = ['plan', 'active'].includes(kind);
    sheet.classList.toggle('training-sheet', draggable);
    const sheetHandle = sheet.querySelector('.sheet-handle');
    sheetHandle.setAttribute('tabindex', draggable ? '0' : '-1');
    sheetHandle.setAttribute('aria-hidden', String(!draggable));
    if (draggable) sheetHandle.setAttribute('role', 'button');
    else sheetHandle.removeAttribute('role');
    sheet.style.removeProperty('height');
    layer.hidden = false;
    screen.inert = true;
    document.getElementById('app-nav').inert = true;
    document.querySelector('.studio-bar').inert = true;
    document.querySelector('.design-rail').inert = true;
    document.querySelector('.design-notes').inert = true;
    sheet.scrollTop = 0;
    const focus = sheet.querySelector('input:not([type="checkbox"]), select, button');
    focus?.focus({ preventScroll: true });
  }
  function closeSheet() {
    if (layer.hidden) return;
    layer.hidden = true;
    ui.sheet = null;
    screen.inert = false;
    document.getElementById('app-nav').inert = false;
    document.querySelector('.studio-bar').inert = false;
    document.querySelector('.design-rail').inert = false;
    document.querySelector('.design-notes').inert = false;
    if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
    else screen.focus({ preventScroll: true });
  }
  function mealForm(slot = '晚餐', foodId) {
    if (!state.foods.length) {
      openSheet('记录饮食', `${empty('bowl', '先准备你的食物库', '当前预览没有食物数据。导入明确标示的示例食物后，即可体验克数换算与记录。', button('导入示例食物', 'import-examples', 'primary'))}${note('本稿不启动相机、不读取文件，也不会写入 App 数据。')}`);
      return;
    }
    openSheet('记录饮食', form('meal-form', `<div class="form-field"><label for="meal-food">选择食物</label><select id="meal-food" name="food">${state.foods.map(food => `<option value="${food.id}" ${food.id === foodId ? 'selected' : ''}>${escape(food.name)} · ${food.kcal} kcal / 100 g</option>`).join('')}</select></div>${field('食用克数（g）', 'grams', '100', 'type="number" inputmode="decimal" min="1" max="5000" step="any"')}<div class="form-field"><label for="meal-slot">餐次</label><select id="meal-slot" name="slot">${['早餐', '午餐', '晚餐', '加餐'].map(value => `<option ${value === slot ? 'selected' : ''}>${value}</option>`).join('')}</select></div>${note('记录到 10 月 13 日。营养值按实际填写克数换算。')}`, '保存饮食记录'));
  }
  function weightForm() {
    const old = state.weights.find(row => row.date === state.today);
    openSheet('记录体重', form('weight-form', `<p class="intro-copy">2026 年 10 月 13 日</p>${field('今天的体重（kg）', 'weight', old?.value || '', 'type="number" inputmode="decimal" min="20" max="300" step="0.1" placeholder="例如 62.4"')}${note('同一天再次保存会更新本次记录，不会叠加重复测量。')}`, '保存体重'));
  }
  function profileForm() {
    openSheet('个人资料与目标', form('profile-form', `${field('昵称', 'profile-name', state.profile.name, 'maxlength="20" autocomplete="off"')}${field('每日饮水目标（ml）', 'water-goal', state.profile.waterGoal, 'type="number" inputmode="numeric" min="500" max="6000" step="1"')}${field('每日步数目标（步）', 'step-goal', state.profile.stepGoal, 'type="number" inputmode="numeric" min="1000" max="50000" step="1"')}${note('本稿演示昵称与两个目标的编辑；App 中其他身体数据与偏好不作调整。')}`, '保存资料'));
  }
  function showFood(foodId) {
    const food = state.foods.find(row => row.id === foodId);
    if (!food) return;
    openSheet(food.name, `<div class="food-detail-heading">${chip(food.icon, 'food-symbol')}<div><h3>${escape(food.name)}</h3><p>${escape(food.category)}${food.brand ? ' · ' + escape(food.brand) : ''}</p></div></div><div class="detail-energy"><b>${food.kcal}</b><span>kcal / 100 g</span></div><dl class="nutrition-table">${[['蛋白质', food.protein], ['碳水化合物', food.carbs], ['脂肪', food.fat]].map(([name, value]) => `<div><dt>${name}</dt><dd>${value} g</dd></div>`).join('')}</dl>${note('示例营养数据，仅用来展示信息结构。')}${button('记录这份食物', 'food-record', 'primary block confirm', `data-id="${food.id}"`)}`);
  }
  function planDetail(id, day = 2) {
    const plan = state.plans.find(row => row.id === id);
    if (!plan) return;
    ui.selectedDay = day;
    openSheet('计划详情', `<div class="plan-detail-heading"><span class="pill">${escape(plan.source || '我的计划')}</span><h3>${escape(plan.name)}</h3><p>选择一个训练日查看安排</p></div><div class="plan-day-tabs" role="group" aria-label="计划训练日">${plan.days.map(value => `<button data-action="plan-day" data-id="${id}" data-day="${value}" aria-pressed="${value === day}">周${'一二三四五六日'[value - 1]}${value === 2 ? '<small>今天</small>' : ''}</button>`).join('')}</div><div class="exercise-list">${plan.exercises.map(exercise => `<div class="exercise-row">${chip('dumbbell')}<div class="exercise-main"><div class="ex-name">${escape(exercise.name)}</div><div class="ex-meta">${exercise.sets} 组 × ${exercise.reps} ${exercise.id === 'plank' ? '秒' : '次'} · ${escape(exercise.equipment || '')}</div></div></div>`).join('')}</div>${note(day === 2 ? '拖动上方把手可展开详情；收起不会误关闭。' : '只有今天对应的训练日可新开始。其他日期保留查看与编辑入口。')}<div class="form-actions">${button('编辑安排', 'plan-edit-info')}${button(state.active ? '继续训练' : '开始训练', 'start-workout', 'primary', `data-id="${id}" ${!state.active && day !== 2 ? 'disabled' : ''}`)}</div>`, 'plan');
  }
  function activeWorkout() {
    if (!state.active) return;
    const active = state.active;
    openSheet('正在训练', `<div class="active-heading"><span class="pill today"><i class="session-pulse"></i>进行中</span><h3>${escape(active.name)}</h3><p>已记录 ${active.sets.length} 组 · 容量 ${format(active.sets.reduce((sum, row) => sum + row.volume, 0))} kg</p></div><div>${active.exercises.map(exercise => {
      const sets = active.sets.filter(row => row.exerciseId === exercise.id);
      return `<div class="session-exercise"><div class="exercise-row">${chip('dumbbell')}<div class="exercise-main"><div class="ex-name">${escape(exercise.name)}</div><div class="ex-meta">计划 ${exercise.sets} 组 × ${exercise.reps} ${exercise.id === 'plank' ? '秒' : '次'}</div></div><span class="pill">${sets.length} / ${exercise.sets}</span></div>${sets.map((row, index) => `<div class="set-row"><span>${icon('check', 15)}第 ${index + 1} 组</span><b>${row.weight} kg × ${row.reps} 次</b></div>`).join('')}${button(`${icon('plus', 15)} 记录一组`, 'record-set', 'block small', `data-exercise="${exercise.id}"`)}</div>`;
    }).join('')}</div><div class="form-actions">${button('稍后继续', 'dismiss-sheet')}${button('结束训练', 'finish-confirm', 'primary')}</div>${note('本稿不运行真实训练计时。退出弹层不会丢失本页已记录的组。')}`, 'active');
  }
  function recordSetForm(id) {
    const active = state.active;
    if (!active) return;
    const exercise = active.exercises.find(row => row.id === id);
    if (exercise?.id === 'plank') {
      openSheet('计时动作', `${note('平板支撑等计时动作保留原 App 处理方式；本稿只演示按重量与次数记录的动作，不把秒数当成重复次数。')}${button('返回训练', 'active-workout', 'primary block')}`);
      return;
    }
    openSheet('记录一组', form('set-form', `<div class="form-field"><label for="set-exercise">动作</label><select name="exercise" id="set-exercise">${active.exercises.filter(row => row.id !== 'plank').map(row => `<option value="${row.id}" ${row.id === id ? 'selected' : ''}>${escape(row.name)}</option>`).join('')}</select></div><div class="form-grid">${field('重量（kg）', 'set-weight', id === 'push' ? '0' : '12', 'type="number" inputmode="decimal" min="0" max="500" step="any"')}${field('次数', 'set-reps', exercise?.reps || 10, 'type="number" inputmode="numeric" min="1" max="100" step="1"')}</div>${note('自重动作的外加重量可填 0。记录后立即计入本次训练。')}`, '保存这一组'));
  }
  function manualPlanForm() {
    openSheet('手动创建计划', form('plan-form', `${field('计划名称', 'plan-name', '', 'maxlength="30" placeholder="例如：下班后的力量训练"')}<fieldset><legend>选择动作</legend>${M.exercises.filter(row => row.id !== 'plank').map(row => `<label class="checkbox-row"><input type="checkbox" name="exercise" value="${row.id}"><span><b>${row.name}</b><small>${row.group} · ${row.equipment} · ${row.sets} 组 × ${row.reps} 次</small></span></label>`).join('')}</fieldset>${note('设计稿中的新计划安排在周二，方便体验今天开始训练的流程；正式 App 的自由安排功能不变。')}`, '创建计划'));
  }
  function respond(text, plan = false) {
    const message = String(text).trim();
    if (!message) { toast('先写下一点想法'); return; }
    ui.messages.push({ role: 'user', text: message });
    if (plan) {
      ui.proposal = true;
      ui.messages.push({ role: 'ai', text: '这是一份演示训练草案。你可以先检查动作，再决定是否应用。' });
    } else {
      ui.messages.push({ role: 'ai', text: /晚餐|吃法|吃什么|搭配/.test(message)
        ? '示例建议：晚餐可以搭配一份主食、蛋白质食物和蔬菜，份量结合今天的摄入与饥饿感调整。\n这只是建议，不会自动生成饮食记录。'
        : '这是离线交互演示，不会真正分析这条消息。正式 App 会通过你配置的 AI 服务继续对话；计划草案仍需明确确认后才会应用。' });
    }
    navigate('ai');
    screen.scrollTop = screen.scrollHeight;
  }
  function workbench() {
    openSheet('AI 创作', `<p class="intro-copy">从一个具体想法开始，结果先在对话里讨论。</p><div class="workbench-grid">${[
      ['book', '解析学校菜单', '从菜单文本开始整理', '帮我解析一份学校菜单'],
      ['bowl', '分析菜品营养', '梳理菜名与配料信息', '帮我分析一道菜的营养'],
      ['sun', '生成今日吃法', '只在对话中提供建议', '今天的吃法怎么安排？'],
      ['leaf', '这道菜怎么吃', '讨论份量、搭配与替换', '这道菜怎么搭配更合适？'],
      ['dumbbell', '训练计划', '先看草案，再确认应用', 'plan'],
      ['target', '常吃搭配', '围绕自己的本地食材', '用我常吃的食材构思搭配'],
    ].map(([name, title, subtitle, prompt]) => `<button data-action="${prompt === 'plan' ? 'ai-plan' : 'ai-prompt'}" ${prompt === 'plan' ? '' : `data-prompt="${prompt}"`}>${chip(name, 'mint')}<b>${title}</b><small>${subtitle}</small></button>`).join('')}</div>${note('创作页是对话起点。当前为演示样例，既不联网生成，也不写入真实数据。')}`);
  }
  function info(title, text) {
    openSheet(title, `${note(text)}${button('知道了', 'dismiss-sheet', 'primary block')}`);
  }
  const infoPages = {
    camera: ['拍照识别', '正式 App 会请求相机权限并进入识别确认页。本稿不启动相机，也不会伪造识别成功。你仍可用食物库体验手动记录。'],
    album: ['从相册选择', '正式 App 可选择照片后确认识别结果。本稿不读取本地相册或上传任何图片。'],
    'steps-detail': ['运动步数', '这里展示的是演示步数。实际读数与系统运动权限、设备支持有关；未取得数据时显示「—」，不伪装为已同步。'],
    'canteen-directory': ['管理食堂目录', '现有 App 按地点、窗口、菜品维护食堂资料，再分析并加入菜品库。本稿保留这个二级入口，不把目录管理混进每日推荐，也不创建真实菜品。'],
    'plan-edit-info': ['编辑训练安排', '正式 App 的动作与日期编辑能力保持不变。本稿展示计划详情、今日开始、逐组记录和继续训练，不修改真实安排。'],
    'ai-settings': ['AI 配置', '保留服务提供商、模型与密钥配置入口。本稿不收集 API Key、不发送网络请求，也不会显示“已连接”之类未经验证的状态。'],
    backup: ['备份与恢复', '正式 App 使用加密 .lfb 备份。本稿只展示入口，不读取、导入、下载或覆盖任何真实备份。备份格式与原有数据契约保持不变。'],
    'restore-info': ['恢复数据', '正式 App 从口令加密 .lfb 备份恢复数据。本稿不选择文件、不解密备份，也不会覆盖现有数据库。'],
    'auto-backup-info': ['自动本地备份', '正式 App 的自动备份策略与开关保持不变。设计稿不启动定时任务、不创建真实备份，当前状态也不代表设备已开启备份。'],
    'scale-info': ['电子体重秤', '电子秤接口已预留；小米等私有协议尚未适配。这不是可连接设备的完成态，不展示虚构体重或连接成功。'],
    permissions: ['权限管理', '相机、媒体与运动权限继续由正式 App 和系统管理。本稿不请求权限，不伪造“已授权”。'],
    'update-info': ['检查更新', '正式 App 保留检查更新入口。本稿不会访问版本服务，不伪造“已是最新版本”。'],
    'license-info': ['数据来源与许可证', '正式 App 的来源说明与许可证保留。本稿只使用自绘线性图标和明确标注的示例数据，没有加载网络字体或图片。'],
    'help-info': ['帮助文档', '本稿可体验五页导航、记录与撤销、体重编辑、食物检索、菜品推荐、AI 草案应用以及训练流程；相机、备份、更新等展示说明，不执行真实操作。'],
    'feedback-info': ['反馈', '正式 App 的反馈方式不变。此离线设计稿不发送任何外部消息或收集反馈数据。'],
    'export-diet': ['导出饮食记录', '正式 App 会导出饮食数据。本稿不生成真实导出文件，仅确认入口和中文命名。'],
    'export-training': ['导出训练记录', '正式 App 会导出训练数据。本稿不生成真实导出文件，仅确认入口和中文命名。'],
    'export-food': ['导出食物数据', '正式 App 保持现有 21 列食物数据契约，兼容旧版导入。本稿不读取或生成真实文件。'],
  };
  function perform(action, target) {
    const data = target.dataset;
    if (infoPages[action]) return info(...infoPages[action]);
    switch (action) {
      case 'navigate': navigate(data.page); break;
      case 'width': setWidth(Number(data.value)); break;
      case 'theme': setTheme(ui.theme === 'light' ? 'dark' : 'light'); break;
      case 'empty':
        ui.empty = !ui.empty; state = M.createState(ui.empty); ui.messages = []; ui.proposal = false; ui.query = ''; ui.category = '全部';
        document.getElementById('empty-toggle').textContent = ui.empty ? '恢复示例数据' : '查看空状态';
        document.getElementById('empty-toggle').setAttribute('aria-pressed', String(ui.empty));
        closeSheet(); render(); toast(ui.empty ? '已切换为空数据预览' : '已恢复示例数据'); break;
      case 'dismiss-sheet': closeSheet(); break;
      case 'weight-period': ui.weightPeriod = data.period; render(true); if (ui.sheet === 'weights') showWeights(); break;
      case 'weight-point': {
        const row = state.weights.find(item => item.date === data.date && item.date <= state.today);
        toast(`${data.date.slice(5).replace('-', ' 月 ')} 日：${row ? row.value + ' kg' : '未记录'}`); break;
      }
      case 'weight-add': weightForm(); break;
      case 'weight-history': showWeights(); break;
      case 'water-quick': M.addWater(state, 250); render(true); toast('已记录 250 ml 饮水'); break;
      case 'meal-add': mealForm(data.slot); break;
      case 'food-record': mealForm('晚餐', data.id); break;
      case 'delete-meal': undoMeal = M.removeMeal(state, data.id); render(true); toast('已删除本条饮食记录', true); break;
      case 'undo-meal': M.restoreMeal(state, undoMeal); undoMeal = null; render(true); toast('已恢复饮食记录'); break;
      case 'nutrition-records': ui.nutrition = 'records'; navigate('nutrition'); break;
      case 'nutrition-tab': ui.nutrition = data.tab; render(); break;
      case 'category': ui.category = data.category; render(true); break;
      case 'clear-filter': ui.query = ''; ui.category = '全部'; render(); break;
      case 'food-detail': showFood(data.id); break;
      case 'import-examples': {
        const result = M.importExamples(state); closeSheet(); render(true);
        toast(`示例导入 ${result.imported} 条，跳过重复 ${result.skipped} 条`); break;
      }
      case 'import-info':
        openSheet('导入食物数据', `${note('正式 App 使用现有 21 列结构，兼容旧版 8 列。这里不读取文件，只用 8 条固定示例演示导入后的列表与重复跳过反馈。')}${button('导入 8 条示例食物', 'import-examples', 'primary block')}`); break;
      case 'food-management':
        openSheet('食物库管理', `${settingsRow('upload', '导入食物数据', '使用本页示例演示', 'import-info')}${settingsRow('bowl', '浏览食物库', `${state.foods.length} 条演示数据`, 'open-foods')}${settingsRow('trash', '清空内置食物', '不等于清空所有数据', 'clear-built-in')}${note('新装正式 App 不再随包回灌食物。这里的 8 条示例仅用于设计预览。')}`); break;
      case 'open-foods': ui.nutrition = 'foods'; navigate('nutrition'); break;
      case 'clear-built-in': info('清空内置食物', '当前预览没有内置食物；示例数据不属于 App 内置记录。此动作不会清空饮食、体重、训练或个人资料。'); break;
      case 'swap-dish': ui.dishChoice[data.slot]++; render(true); toast('已切换另一道示例菜品'); break;
      case 'dish-candidates':
        openSheet(`${data.slot}候选`, `<div class="candidate-list">${dishCandidates(data.slot).map(dish => `<button class="food-row" data-action="dish-add" data-id="${dish.id}" data-slot="${data.slot}">${chip(dish.icon, 'mint')}<span class="food-main"><span class="food-name">${dish.name}</span><span class="food-tags">${dish.place}</span></span><span class="food-kcal">${dish.kcal}<small>kcal / 100 g</small></span></button>`).join('')}</div>${note('这些候选是固定演示样例，不代表实际推荐引擎计算结果。')}`); break;
      case 'dish-add': {
        const dish = dishes.find(row => row.id === data.id);
        if (dish) openSheet(`加入${data.slot}`, form('dish-form', `<input type="hidden" name="dish" value="${dish.id}"><input type="hidden" name="slot" value="${data.slot}"><h3>${dish.name}</h3><p class="intro-copy">${dish.kcal} kcal / 100 g · ${dish.place}</p>${field('实际食用克数（g）', 'dish-grams', '200', 'type="number" inputmode="decimal" min="1" max="5000" step="any"')}${note(`确认后会记为今天${data.slot}已吃的饮食，不是未来计划。仅影响当前设计稿。`)}`, `确认加入${data.slot}`));
        break;
      }
      case 'workbench': workbench(); break;
      case 'ai-prompt': respond(data.prompt); break;
      case 'ai-plan': respond('帮我制定一个轻量全身训练计划', true); break;
      case 'apply-proposal': M.applyPlanProposal(state); render(true); toast('计划已加入演示训练列表'); break;
      case 'ignore-proposal': M.ignorePlanProposal(state); render(true); toast('已忽略，没有写入计划'); break;
      case 'training-tab': ui.training = data.tab; render(); break;
      case 'plan-detail': {
        const plan = state.plans.find(row => row.id === data.id); planDetail(data.id, plan?.days.includes(2) ? 2 : plan?.days[0]); break;
      }
      case 'plan-day': planDetail(data.id, Number(data.day)); break;
      case 'start-workout': M.startWorkout(state, data.id, 2); render(true); activeWorkout(); break;
      case 'active-workout': activeWorkout(); break;
      case 'record-set': recordSetForm(data.exercise); break;
      case 'finish-confirm':
        openSheet('结束这次训练？', `<p class="intro-copy">已记录 ${state.active?.sets.length || 0} 组。结束后会保存到本页训练历史。</p>${note('训练时长在此原型中不计时，历史展示 0 分钟，不伪造运动时长。')}<div class="form-actions">${button('继续训练', 'active-workout')}${button('确认结束', 'finish-workout', 'primary')}</div>`); break;
      case 'finish-workout': {
        const summary = M.finishWorkout(state); ui.training = 'history'; closeSheet(); render(); toast(`训练已保存，共 ${summary.sets.length} 组`); break;
      }
      case 'create-plan': manualPlanForm(); break;
      case 'exercise-library':
        openSheet('动作库', `<p class="intro-copy">按部位与器械认识动作。下列为界面示例。</p>${M.exercises.map(row => `<div class="exercise-row">${chip('dumbbell')}<div class="exercise-main"><div class="ex-name">${row.name}</div><div class="ex-meta">${row.group} · ${row.equipment}</div></div></div>`).join('')}${note('完整动作资料沿用 App，本稿不新增动作教学或视频。')}`); break;
      case 'history-detail': {
        const row = state.history.find(item => item.id === data.id);
        if (row) openSheet('训练回顾', `<div class="detail-energy"><b>${row.sets.length}</b><span>已完成组数</span></div><h3>${escape(row.name)}</h3><dl class="nutrition-table"><div><dt>训练日期</dt><dd>${row.date}</dd></div><div><dt>训练时长</dt><dd>${row.minutes} 分钟</dd></div><div><dt>总容量</dt><dd>${format(row.volume)} kg</dd></div><div><dt>估算消耗</dt><dd>—</dd></div></dl>${note('历史样例用于排版。新完成的预览训练不虚构计时或卡路里。')}`); break;
      }
      case 'profile-edit': profileForm(); break;
      case 'about': openSheet('关于 LocalFit AI', `<div class="food-detail-heading">${chip('leaf', 'mint')}<div><h3>LocalFit AI</h3><p>第六轮界面设计提案</p></div></div><div class="settings-group">${settingsRow('download', '检查更新', '', 'update-info')}${settingsRow('book', '数据来源与许可证', '', 'license-info')}${settingsRow('info', '帮助文档', '', 'help-info')}${settingsRow('edit', '反馈', '', 'feedback-info')}</div>${note('仅在当前页内存中操作，刷新复原；未修改 Flutter App。')}`); break;
      case 'exports': openSheet('导出数据', `<div class="settings-group">${settingsRow('download', '导出饮食记录', '', 'export-diet')}${settingsRow('download', '导出训练记录', '', 'export-training')}${settingsRow('download', '导出食物数据', '', 'export-food')}</div>${note('此处仅预览操作入口，不下载真实数据。')}`); break;
      case 'clear-preview': openSheet('清空所有数据', `<div class="danger-notice">真实 App 中，此操作会影响本地记录，必须独立确认。</div><p class="intro-copy">当前是设计稿，只能清空此页演示数据，刷新即可恢复；不会删除任何 App 文件。</p><div class="form-actions">${button('取消', 'dismiss-sheet')}${button('清空本页示例', 'confirm-clear-preview', 'danger')}</div>`); break;
      case 'confirm-clear-preview': state = M.createState(true); ui.empty = true; ui.messages = []; ui.proposal = false; closeSheet(); render(); document.getElementById('empty-toggle').textContent = '恢复示例数据'; document.getElementById('empty-toggle').setAttribute('aria-pressed', 'true'); toast('只清空了当前预览示例'); break;
    }
  }
  function showWeights() {
    openSheet('体重记录', `${weightBlock(true)}${button('记录今天的体重', 'weight-add', 'primary block')}${state.weights.slice().sort((a, b) => b.date.localeCompare(a.date)).map(row => `<div class="set-row"><span>${row.date}</span><b>${row.value} kg</b></div>`).join('')}`, 'weights');
  }
  function setTheme(theme) {
    ui.theme = theme;
    document.documentElement.dataset.theme = theme;
    const toggle = document.getElementById('theme-toggle');
    toggle.textContent = theme === 'dark' ? '浅色预览' : '深色预览';
    toggle.setAttribute('aria-pressed', String(theme === 'dark'));
  }
  function setWidth(width) {
    const actual = [360, 390, 430].includes(width) ? width : 390;
    document.getElementById('device').style.setProperty('--device-width', actual + 'px');
    document.querySelectorAll('[data-action="width"]').forEach(item => item.setAttribute('aria-pressed', String(Number(item.dataset.value) === actual)));
  }
  document.addEventListener('click', event => {
    const target = event.target.closest('[data-action]');
    if (!target || target.disabled) return;
    try { perform(target.dataset.action, target); }
    catch (error) { toast(error.message || '操作未完成，请检查输入'); }
  });
  document.addEventListener('input', event => {
    if (event.target.id === 'food-query') {
      ui.query = event.target.value;
      document.getElementById('food-results').innerHTML = foodResults();
    }
  });
  document.addEventListener('submit', event => {
    event.preventDefault();
    const target = event.target;
    const data = new FormData(target);
    try {
      switch (target.id) {
        case 'meal-form': M.addFoodMeal(state, data.get('food'), data.get('grams'), data.get('slot')); closeSheet(); render(true); toast('饮食记录已保存'); break;
        case 'weight-form': M.saveWeight(state, data.get('weight')); closeSheet(); render(true); toast('体重已保存'); break;
        case 'profile-form': M.updateProfile(state, { name: data.get('profile-name'), waterGoal: data.get('water-goal'), stepGoal: data.get('step-goal') }); closeSheet(); render(true); toast('资料与目标已保存'); break;
        case 'set-form': M.recordSet(state, data.get('exercise'), data.get('set-weight'), data.get('set-reps')); render(true); activeWorkout(); toast('已保存这一组'); break;
        case 'plan-form': M.createManualPlan(state, data.get('plan-name'), data.getAll('exercise')); ui.training = 'plans'; navigate('training'); toast('训练计划已创建'); break;
        case 'dish-form': M.recordDish(state, dishes.find(row => row.id === data.get('dish')), data.get('dish-grams'), data.get('slot')); closeSheet(); ui.nutrition = 'records'; render(); toast('菜品已加入今天的饮食记录'); break;
        case 'chat-form': respond(data.get('message')); break;
      }
    } catch (error) {
      const feedback = target.querySelector('.form-error');
      if (feedback) feedback.textContent = error.message || '请检查输入';
      else toast(error.message || '操作未完成');
    }
  });
  document.addEventListener('keydown', event => {
    if (layer.hidden) return;
    if (event.key === 'Escape') { event.preventDefault(); closeSheet(); return; }
    if (event.key === 'Tab') {
      const focusable = [...sheet.querySelectorAll('button:not(:disabled), input:not(:disabled), select:not(:disabled), a[href], [tabindex="0"]')].filter(element => element.offsetParent !== null);
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    }
  });
  const handle = document.querySelector('.sheet-handle');
  handle.setAttribute('role', 'button');
  handle.setAttribute('tabindex', '0');
  handle.setAttribute('aria-label', '展开或收起训练详情');
  handle.removeAttribute('aria-hidden');
  let drag = null;
  handle.addEventListener('pointerdown', event => {
    if (!['active', 'plan'].includes(ui.sheet)) return;
    drag = { y: event.clientY, height: sheet.getBoundingClientRect().height };
    handle.setPointerCapture(event.pointerId);
  });
  handle.addEventListener('pointermove', event => {
    if (!drag) return;
    const height = Math.max(300, Math.min(document.getElementById('device').clientHeight * .92, drag.height + drag.y - event.clientY));
    sheet.style.height = height + 'px';
  });
  function endDrag() {
    if (!drag) return;
    const deviceHeight = document.getElementById('device').clientHeight;
    sheet.style.height = (sheet.getBoundingClientRect().height > deviceHeight * .72 ? .92 : .6) * deviceHeight + 'px';
    drag = null;
  }
  handle.addEventListener('pointerup', endDrag);
  handle.addEventListener('pointercancel', endDrag);
  handle.addEventListener('keydown', event => {
    if (!['Enter', ' '].includes(event.key) || !['active', 'plan'].includes(ui.sheet)) return;
    event.preventDefault();
    const height = document.getElementById('device').clientHeight;
    sheet.style.height = (sheet.getBoundingClientRect().height > height * .72 ? .6 : .92) * height + 'px';
  });
  if (params.get('embed') === '1') document.documentElement.dataset.embed = '1';
  setTheme(ui.theme);
  setWidth(Number(params.get('width')));
  if (ui.empty) {
    document.getElementById('empty-toggle').textContent = '恢复示例数据';
    document.getElementById('empty-toggle').setAttribute('aria-pressed', 'true');
  }
  document.querySelectorAll('[data-icon]').forEach(element => { element.innerHTML = icon(element.dataset.icon, 18); });
  render();
})();
