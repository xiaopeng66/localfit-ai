(() => {
  'use strict';
  const M = window.LocalFitModel;
  const params = new URLSearchParams(location.search);
  const pages = { today: '今日', nutrition: '饮食', ai: 'AI 助手', training: '训练', settings: '我的' };
  let state = M.createState(params.get('empty') === '1');
  const ui = {
    page: Object.hasOwn(pages, params.get('page')) ? params.get('page') : 'today',
    empty: params.get('empty') === '1', nutrition: ['records','menus','foods'].includes(params.get('tab')) ? params.get('tab') : 'records', training: 'plans', date: state.today,
    weightPeriod: 'week', query: '', category: '全部', sheet: null,
    exerciseQuery: '', muscle: '全部', trainingReturn: 'plans',
    messages: [], proposal: false, selectedDay: 2, dishChoice: { 早餐: 0, 午餐: 0, 晚餐: 0 }, theme: params.get('theme') === 'dark' ? 'dark' : 'light',
  };
  const variant = ['a', 'b', 'c'].includes(params.get('variant')) ? params.get('variant') : 'a';
  document.documentElement.dataset.variant = variant;
  const screen = document.getElementById('screen');
  const layer = document.getElementById('sheet-layer');
  const sheet = document.getElementById('app-sheet');
  const toastElement = document.getElementById('toast');
  let returnFocus = null;
  let toastTimer;
  let undoMeal = null;
  let proposalSequence = 0;
  // Store semantic identity, not just a DOM node that innerHTML will disconnect.
  function captureFocus(element = document.activeElement) {
    if (!element || element === document.body) return null;
    const root = [screen, document.getElementById('app-nav'), sheet].find(node => node.contains(element));
    // A record's label can change after editing; its action and data id remain stable.
    const attributes = element.id ? [['id', element.id]] : element.dataset.action && element.dataset.id
      ? [['data-action', element.dataset.action], ['data-id', element.dataset.id]]
      : [
        ...Object.entries(element.dataset).map(([key, value]) => ['data-' + key.replace(/[A-Z]/g, letter => '-' + letter.toLowerCase()), value]),
        ['aria-label', element.getAttribute('aria-label')],
        ['name', element.getAttribute('name')],
      ].filter(([, value]) => value !== null);
    const matches = node => node.tagName === element.tagName && attributes.every(([key, value]) => node.getAttribute(key) === value);
    const candidates = root && attributes.length ? [...root.querySelectorAll(element.id ? '[id]' : '[data-action], input, textarea, select')].filter(matches) : [];
    return { element, root, matches, index: candidates.indexOf(element), identified: attributes.length > 0 };
  }
  function restoreFocus(saved, fallback = screen) {
    let target = saved?.element;
    if (!target?.isConnected && saved?.root && saved.identified) {
      const candidates = [...saved.root.querySelectorAll('[id], [data-action], input, textarea, select')].filter(saved.matches);
      target = candidates[saved.index] || candidates[0];
    }
    if (!target?.isConnected || target.disabled || target.closest('[hidden], [inert]')) target = fallback;
    target?.focus({ preventScroll: true });
  }
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
    'file-import': '<path d="M14 3H6v5m0 8v5h14V9l-6-6v6h6M2 12h11m-4-4 4 4-4 4"/>',
    'file-export': '<path d="M14 3H4v18h10M14 3v6h6l-6-6M11 15h11m-4-4 4 4-4 4"/>',
    'muscle-back': '<circle cx="12" cy="4" r="2"/><path d="M8 9c0-2 8-2 8 0l-2 6h-4Zm2 6-5 4h14l-5-4M7 10l-4 5m14-5 4 5"/>',
    'muscle-shoulders': '<circle cx="12" cy="4" r="2"/><path d="m3 8 9 2 9-2M12 10v5m0 0-5 7m5-7 5 7"/>',
    'muscle-arms': '<path d="M8 13V5a2 2 0 0 1 4 0v7-8a2 2 0 0 1 4 0v8-5a2 2 0 0 1 4 0v8c0 4-3 7-7 7-3 0-5-2-7-4l-3-4a2 2 0 0 1 3-2l2 2Z"/>',
    'muscle-core': '<path d="M12 5C7-1 1 5 4 11l8 10 8-10c3-6-3-12-8-6Zm0 0-2 5 4 3-2 4"/>',
    'muscle-legs': '<circle cx="14" cy="3" r="2"/><path d="m12 7-3 5H5m7-5 4 5h4M12 7l-1 8-5 6m5-6 5 3v4"/>',
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
  const safeRatio = value => Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0;
  function ring(ratio, value, label, color = 'var(--brand)', size = 120, className = '', strokeWidth) {
    const stroke = strokeWidth ?? (size <= 56 ? 4 : 9);
    const r = size / 2 - (strokeWidth ? stroke / 2 : size <= 56 ? 4 : 8);
    const perimeter = 2 * Math.PI * r;
    return `<span class="data-ring ${className}" style="--ring-size:${size}px;--ring-color:${color}" role="img" aria-label="${escape(label)} ${escape(value)}"><svg viewBox="0 0 ${size} ${size}" aria-hidden="true"><circle cx="${size/2}" cy="${size/2}" r="${r}" fill="none" stroke="var(--track)" stroke-width="${stroke}"/><circle cx="${size/2}" cy="${size/2}" r="${r}" fill="none" stroke="${color}" opacity="${safeRatio(ratio)>0?1:0}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${perimeter * safeRatio(ratio)} ${perimeter}" transform="rotate(-90 ${size/2} ${size/2})"/></svg><span class="data-ring-center" aria-hidden="true"><b>${value}</b>${size > 56 ? `<small>${label}</small>` : ''}</span></span>`;
  }
  const track = (ratio, color='var(--brand)') => `<div class="data-track"><i style="width:${safeRatio(ratio)*100}%;background:${color}"></i></div>`;
  function macros(total) {
    return `<div class="macro-summary">${[['protein','蛋白质',110],['carbs','碳水',220],['fat','脂肪',50]].map(([key,label,target])=>`<div class="macro-column"><span><i class="macro-dot ${key}"></i>${label}</span><div><b>${format(total[key])}</b><small> / ${target} g</small></div>${track(total[key]/target,`var(--${key})`)}</div>`).join('')}</div>`;
  }
  function sourceSummary(date = state.today) {
    const c=M.confidence(state,date);
    return `<div class="source-summary">${ring(c.ratio,'','已确认食物项占比','var(--brand)',20)}<span>已确认 ${c.confirmed} 项 <span class="muted">/ 估算 ${c.estimated} 项</span></span></div>`;
  }
  function energy(date=state.today) {
    const total=M.totals(state,date), ratios=M.macroRatios(total), hasGoal=state.energyGoal>0;
    const status=!hasGoal?'未设目标':total.kcal>state.energyGoal?'已超目标':total.kcal>=state.energyGoal*.9?'接近上限':'额度充足';
    return `<section class="card energy-summary" data-graphic="calorie-macros"><div class="card-row"><h2 class="section-title">${date===state.today?'今日':'当日'}营养</h2><span class="pill ${hasGoal&&total.kcal>state.energyGoal?'warning':'today'}">${status}</span></div><div class="energy-main">${ring(hasGoal?total.kcal/state.energyGoal:0,format(total.kcal),'已摄入 kcal','var(--brand)',120,'calorie-ring')}${macros(total)}</div><div class="energy-foot"><span>${hasGoal?'目标 '+format(state.energyGoal)+' kcal':'尚未设定目标'}</span><span>${hasGoal?`${total.remaining>=0?'还可摄入':'超出'} <b>${format(Math.abs(total.remaining))}</b> kcal`:'设置目标后查看进度'}</span></div><div class="macro-ratios">${ratios?`能量占比 <span><i class="macro-dot protein"></i>蛋白质 ${Math.round(ratios.protein*100)}%</span><span><i class="macro-dot carbs"></i>碳水 ${Math.round(ratios.carbs*100)}%</span><span><i class="macro-dot fat"></i>脂肪 ${Math.round(ratios.fat*100)}%</span>`:'暂无记录，记录后显示营养占比'}</div></section>`;
  }
  function weightBlock(large = false) {
    const chart=M.weightChart(state,ui.weightPeriod), minimum=chart.ticks[3], span=chart.ticks[0]-minimum;
    const month=ui.weightPeriod==='month';
    return `<section class="card weight-card" data-graphic="weight"><div class="card-row"><h2 class="section-title">体重趋势</h2><div class="weight-tools"><div class="mini-tabs" role="group" aria-label="体重周期"><button data-action="weight-period" data-period="week" aria-pressed="${!month}">周</button><button data-action="weight-period" data-period="month" aria-pressed="${month}">月</button></div><button class="icon-button circle-soft" data-action="weight-add" aria-label="记录体重">${icon('plus',16)}</button></div></div><div class="weight-caption"><div class="weight-trend-value">${chart.latest===null?'—':format(chart.latest)}<small>kg</small></div><span>最近记录<small>${month?'10 月 · 每日一格':'本周 · 周一至周日'}</small></span></div><div class="weight-chart ${large?'large':''}" aria-label="${month?'本月':'本周'}体重柱图"><div class="chart-axis">${chart.ticks.map(t=>`<span>${t.toFixed(1)}</span>`).join('')}</div><div class="weight-plot"><div class="chart-rules" aria-hidden="true"><i></i><i></i><i></i><i></i></div><div class="weight-columns ${ui.weightPeriod}">${chart.slots.map((row,index)=>{
      const label=month?([1,5,10,15,20,25,chart.slots.length].includes(index+1)&&row.value!==null?index+1:''):'一二三四五六日'[index];
      const bar=`<span class="weight-bar-space"><i style="height:${row.value===null?0:Math.max(3,(row.value-minimum)/span*100)}%"></i></span><small>${label}</small>`;
      return row.value===null?`<span class="weight-slot no-data" aria-label="${row.date}，无记录">${bar}</span>`:`<button class="weight-slot ${row.date===state.today?'current':''}" data-action="weight-point" data-date="${row.date}" data-value="${row.value}" aria-label="${row.date}，${row.value} 千克">${bar}</button>`;
    }).join('')}</div><div class="weight-tooltip" role="status" hidden></div></div></div><p class="chart-hint">${chart.latest===null?'尚无体重记录，日期留空':'点击柱条看记录，空白日期未记录'}</p></section>`;
  }
  function dailyMetrics() {
    return `<div class="water-steps-row" data-graphic="water-steps"><section class="card metric-card water-card"><div class="metric-top"><h2 class="section-title">饮水</h2><span class="water-icon">${icon('water',18)}</span></div><div class="metric-value">${format(state.water)}<small>ml</small></div><p class="metric-label">目标 ${format(state.profile.waterGoal)} ml</p>${track(state.water/state.profile.waterGoal,'var(--water)')}${button('+ 250 ml','water-quick','small water-button')}</section><section class="card metric-card"><div class="metric-top"><h2 class="section-title">步数</h2>${state.steps===null?'<span class="pill">未授权</span>':icon('steps',18)}</div><div class="metric-value">${state.steps===null?'—':format(state.steps)}<small>步</small></div>${state.steps===null?'':`<p class="metric-label">目标 ${format(state.profile.stepGoal)} 步</p>${track(state.steps/state.profile.stepGoal)}${link('查看详情','steps-detail')}`}</section></div>`;
  }
  function nextMeal() {
    const total=M.totals(state), remaining=Math.max(0,total.remaining);
    return `<section class="card next-meal" data-graphic="meal-budget"><div class="card-row"><h2 class="section-title">下一餐，留给晚餐</h2>${chip('moon','mint')}</div><div class="budget-line"><b>${state.energyGoal>0?format(remaining):'—'}<small> kcal</small></b><span class="muted">${state.energyGoal>0?'今日剩余额度':'尚未设定热量目标'}</span></div>${track(total.kcal/state.energyGoal)}<div class="budget-facts"><span>${icon('bowl',16)}${total.count} 笔已记</span><span>${icon('target',16)}目标 ${state.energyGoal>0?format(state.energyGoal):'—'}</span></div>${button(`${icon('plus',16)} 记录晚餐`,'meal-add','outline-brand block','data-slot="晚餐"')}</section>`;
  }
  function mealRows(rows, removable = false) {
    return rows.map(meal => `<div class="meal-row">${chip(meal.icon || 'bowl', 'meal-symbol')}<div class="meal-info"><div class="meal-name">${escape(meal.slot)}<span>${escape(meal.time || '')}</span></div><div class="meal-meta">${escape(meal.name)}</div></div><div class="meal-kcal">${format(meal.kcal)}<small>kcal</small></div>${removable ? `<button class="icon-button" data-action="delete-meal" data-id="${escape(meal.id)}" aria-label="删除${escape(meal.slot)}记录：${escape(meal.name)}">${icon('trash', 16)}</button>` : ''}</div>`).join('');
  }
  function todayPage() {
    const rows=state.meals.filter(row=>row.date===state.today);
    const meals=`<section class="card meals-card"><div class="section-title with-link"><h2 class="section-title">今天吃了什么</h2>${link('查看全部','nutrition-records')}</div>${rows.length?mealRows(rows):empty('bowl','从第一餐开始','从食物库选择，记录实际吃下的食物。')}${sourceSummary()}${button(`${icon('plus',16)} 记录饮食`,'meal-add','block outline-brand')}</section>`;
    const ai=`<button class="ai-entry-line" data-action="workbench">${chip('spark','mint')}<span><b>AI 创作</b><small>饮食与训练，从一个想法开始</small></span>${icon('right',17)}</button>`;
    const activity=state.active?`<section class="card"><div class="card-row"><h2 class="section-title">${escape(state.active.name)}</h2><span class="pill today">进行中</span></div>${sessionProgress()}${button('继续训练','active-workout','primary block')}</section>`:'';
    const content=variant==='c'?energy()+meals+nextMeal()+dailyMetrics()+activity+weightBlock()+ai:variant==='b'?energy()+dailyMetrics()+weightBlock()+nextMeal()+meals+activity+ai:energy()+weightBlock()+dailyMetrics()+nextMeal()+meals+activity+ai;
    return `<div class="page today-page">${head(`你好，${escape(state.profile.name)}`,'10 月 13 日，星期二')}<div class="sample-strip"><i class="local-dot"></i>示例数据 · 仅本页内存，刷新重置</div>${content}</div>`;
  }
  function nutritionPage() {
    return `<div class="page nutrition-page">${head('饮食', '把每一餐，记得更清楚', `<div class="head-actions"><button class="icon-button" data-action="camera" aria-label="拍照识别食物">${icon('camera')}</button><button class="icon-button circle-soft" data-action="meal-add" aria-label="添加饮食记录">${icon('plus')}</button></div>`)}<div class="tabs" role="tablist" aria-label="饮食分类">${[['records', '记录'], ['menus', '菜单'], ['foods', '食物库']].map(([key, title]) => `<button role="tab" aria-selected="${ui.nutrition === key}" data-action="nutrition-tab" data-tab="${key}">${title}</button>`).join('')}</div>${ui.nutrition === 'records' ? nutritionRecords() : ui.nutrition === 'menus' ? nutritionMenus() : nutritionFoods()}</div>`;
  }
  function nutritionTrend() {
    const stats=M.nutritionTrend(state), max=Math.max(2200,stats.target||0,...stats.days.map(d=>d.kcal||0));
    return `<section class="card nutrition-trend" data-graphic="nutrition-trend"><div class="card-row"><h2 class="section-title">七日摄入趋势</h2><span class="quiet-label">${stats.trackedDays} 天有记录</span></div>${!stats.trackedDays?'<div class="chart-empty">近 7 日还没有记录。</div>':`<div class="nutrition-bar-chart"><div class="trend-axis"><span>${format(max)}</span><span>0</span></div><div class="trend-plot">${stats.target?`<div class="target-line" style="bottom:${stats.target/max*100}%"><span>目标 ${format(stats.target)}</span></div>`:''}<div class="trend-columns">${stats.days.map(d=>`<div class="trend-column" aria-label="${d.date} ${d.kcal===null?'无记录':d.kcal+' kcal'}"><div class="trend-bar-area"><i style="height:${d.kcal===null?3:Math.max(2,d.kcal/max*100)}%;background:${d.kcal===null?'var(--border)':stats.target&&d.kcal>stats.target?'var(--protein)':'var(--brand)'}"></i></div><small>${Number(d.date.slice(-2))}</small></div>`).join('')}</div></div></div><p class="chart-hint">单位 kcal · 灰色短柱为无记录${stats.target?' · 虚线为每日目标':''}</p>`}</section>`;
  }
  function nutritionRecords() {
    const stats=M.nutritionTrend(state), slots=['早餐','午餐','晚餐','加餐'];
    const dates=`<div class="date-strip" data-graphic="date-intake" role="group" aria-label="饮食记录日期">${stats.days.map(d=>`<button data-action="nutrition-date" data-date="${d.date}" aria-pressed="${ui.date===d.date}" aria-label="${d.date} ${d.kcal===null?'无记录':d.kcal+' kcal'}"><small>${'日一二三四五六'[new Date(d.date+'T12:00:00Z').getUTCDay()]}</small><b>${Number(d.date.slice(-2))}</b><span class="date-mini"><i style="height:${d.kcal===null?0:Math.max(6,Math.min(100,d.kcal/2200*100))}%"></i></span></button>`).join('')}</div>`;
    const timeline=`<div class="meal-timeline">${slots.map(slot=>{
      const rows=state.meals.filter(row=>row.date===ui.date&&row.slot===slot);
      return `<section class="card meal-slot-card"><div class="slot-heading">${chip(slot==='早餐'?'sun':slot==='午餐'?'bowl':slot==='晚餐'?'moon':'cup')}<h2>${slot}</h2><span>${rows.length?format(rows.reduce((sum,r)=>sum+r.kcal,0))+' kcal':'尚未记录'}</span>${ui.date===state.today?`<button class="icon-button" data-action="meal-add" data-slot="${slot}" aria-label="记录${slot}">${icon('plus',18)}</button>`:''}</div>${rows.length?mealRows(rows,ui.date===state.today):`<p class="empty-meal">${ui.date===state.today?'还没记录这一餐':'当天没有这餐记录'}</p>`}</section>`;
    }).join('')}</div>`;
    return `${dates}<p class="selected-date">${ui.date.replaceAll('-',' / ')}${ui.date===state.today?' · 今天':''}</p>${energy(ui.date)}${sourceSummary(ui.date)}${variant==='c'?timeline+nutritionTrend():nutritionTrend()+timeline}${ui.date===state.today?button(`${icon('plus',18)} 记录饮食`,'meal-add','primary block'):note('历史样例只读；切回今天可体验记录。')}`;
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
  function foodSymbol(food, className = 'food-symbol') {
    const categories = { 主食: 'staple', 肉类: 'protein', 蛋类: 'protein', 豆类: 'protein', 蔬菜: 'vegetable', 水果: 'fruit', 奶类: 'dairy', 饮料: 'beverage', 零食: 'snack', 调味品: 'condiment', 成品菜: 'prepared', 其他: 'other' };
    const known = ['staple', 'protein', 'vegetable', 'fruit', 'dairy', 'beverage', 'snack', 'condiment', 'prepared', 'other'];
    const category = known.includes(food.category) ? food.category : Object.hasOwn(categories, food.category) ? categories[food.category] : 'other';
    return `<span class="${className}"><img src="assets/food-categories/${category}.svg" width="40" height="40" alt="" aria-hidden="true"></span>`;
  }
  function foodResults() {
    const rows=M.searchFoods(state,ui.query,ui.category);
    return `<div class="section-title with-link"><span class="quiet-label">${rows.length} 种食物</span><span class="quiet-label">kcal / 100g</span></div>${rows.length?`<div class="card food-list">${rows.map(food=>{
      const d=M.density(food.kcal);
      return `<button class="food-row" data-action="food-detail" data-id="${escape(food.id)}" aria-label="查看${escape(food.name)}${M.foodCanRecord(food)?'':'，营养不完整'}" title="${escape(food.name)}">${foodSymbol(food)}<span class="food-main"><span class="food-name">${escape(food.name)}</span>${M.foodCanRecord(food)?'':'<span class="food-warning" aria-label="营养不完整">'+icon('info',14)+'</span>'}</span>${ring(d.ratio,d.value===null?'—':format(d.value),'每100g能量密度','var(--brand)',36,'food-density')}</button>`;
    }).join('')}</div>`:empty('search',state.foods.length?'没有找到这类食物':'食物库还是空的',state.foods.length?'试试其他名称或分类。':'新安装时为空库，可导入自己的食物数据。',state.foods.length?button('清除筛选','clear-filter','small'):button('导入示例食物','import-examples','outline-brand'))}<p class="chart-hint">环 = 每 100g 能量密度 · 满刻度 1000 kcal/100g</p>`;
  }
  function nutritionFoods() {
    return `<label class="search-field">${icon('search', 18)}<input type="search" id="food-query" value="${escape(ui.query)}" placeholder="搜索食物名称或品牌" aria-label="搜索食物名称或品牌"></label><div class="food-category-row" aria-label="食物类别">${['全部', '主食', '肉类', '蛋类', '蔬菜', '奶类', '水果', '豆类'].map(category => `<button data-action="category" data-category="${category}" aria-pressed="${ui.category === category}">${category}</button>`).join('')}</div><div id="food-results" class="food-results" aria-live="polite">${foodResults()}</div><div class="library-footer">${link(`${icon('file-import', 16)} <span>导入食物数据<small>从文件读取到食物库</small></span>`, 'import-info')}${link('食物管理', 'food-management')}</div><p class="subtle-note">当前为演示食物，营养值仅用于界面预览。</p>`;
  }
  function proposal() {
    return `<section class="card proposal-card"><div class="card-row"><span class="pill proposal-tag">${icon('edit', 13)}训练计划草案</span><span class="quiet-label">${state.proposalStatus === 'pending' ? '待你确认' : state.proposalStatus === 'applied' ? '已应用' : '已忽略'}</span></div><h3>轻量全身训练</h3><p class="intro-copy">每周 3 次，从熟悉的动作开始。</p><div class="proposal-exercises">${['高脚杯深蹲', '单臂哑铃划船', '俯卧撑'].map((name, index) => `<div><span>${name}</span><b>3 组 × ${index === 1 ? 12 : 10} 次</b></div>`).join('')}</div>${state.proposalStatus === 'pending' ? `<div class="form-actions">${button('忽略', 'ignore-proposal', 'ghost', `data-proposal="${ui.proposal}"`)}${button('应用计划', 'apply-proposal', 'primary', `data-proposal="${ui.proposal}"`)}</div><p class="status-line">确认应用后，才会加入训练计划。</p>` : `<p class="proposal-status">${icon(state.proposalStatus === 'applied' ? 'check' : 'close', 17)}${state.proposalStatus === 'applied' ? '已应用到演示训练计划' : '已忽略，未写入任何计划'}</p>`}</section>`;
  }
  function aiPage() {
    return `<div class="page ai-page">${head('AI 助手', '一起把计划，变得可执行')}<p class="chat-demo-notice">离线演示对话，不调用 AI 服务</p><div class="chat-scroll"><div class="assistant-intro"><span class="assistant-symbol">${icon('spark', 30)}</span><h2>从今天的一小步开始。</h2><p>聊聊吃什么、怎么练，<br>也可以一起整理你的计划。</p></div>${ui.messages.map(message => `<div class="bubble ${message.role}">${escape(message.text).replace(/\n/g, '<br>')}</div>`).join('')}${ui.proposal ? proposal() : `<div class="conversation-starters"><button data-action="ai-prompt" data-prompt="今天晚餐怎么搭配？">${icon('bowl', 18)}<span>今天晚餐怎么搭配？</span>${icon('right', 15)}</button><button data-action="ai-plan">${icon('dumbbell', 18)}<span>制定轻量训练计划</span>${icon('right', 15)}</button></div>`}</div><div class="chat-footer"><div class="quick-actions"><button data-action="camera">${icon('camera', 15)}拍照识别</button><button data-action="album">${icon('image', 15)}相册</button><button data-action="workbench">${icon('spark', 15)}AI 创作</button></div><form id="chat-form" class="chat-input-bar"><input name="message" aria-label="发给 AI 助手的消息" placeholder="说说你的想法…" autocomplete="off" maxlength="1000"><button type="submit" aria-label="发送消息">${icon('send', 20)}</button></form><p>建议供参考，身体不适请咨询专业人士。</p></div></div>`;
  }
  function trainingStats() {
    const stats = M.recentTraining(state);
    return `<section class="card training-summary"><div class="section-title with-link"><h2 class="section-title">近 7 天</h2><span class="quiet-label">10.07 — 10.13</span></div><div class="training-overview"><div><b>${stats.count}<small>次</small></b><span>训练次数</span></div><div><b>${stats.minutes}<small>min</small></b><span>累计时长</span></div><div><b>—<small>kcal</small></b><span>消耗未估算</span></div></div><div class="week-bars">${stats.days.map(day => `<div class="bar-col" role="img" aria-label="${day.date}：${day.minutes} 分钟"><div class="bar ${day.date === state.today ? 'active' : ''}" style="height:${day.minutes ? Math.max(6, day.minutes / Math.max(40, ...stats.days.map(row => row.minutes)) * 80) : 3}px" title="${day.date}：${day.minutes} 分钟"></div><span class="bar-label">${Number(day.date.slice(-2))}日</span></div>`).join('')}</div></section>`;
  }
  function trainingPage() {
    if (ui.training === 'library') return exerciseLibraryPage();
    const plans = state.plans;
    return `<div class="page training-page">${head('训练', '把专注，留给每一个动作', `<button class="icon-button" data-action="exercise-library" aria-label="查看动作库">${icon('book', 22)}</button>`)}${trainingStats()}<div class="tabs" role="tablist" aria-label="训练分类">${[['plans', '我的计划'], ['history', '训练历史']].map(([key, title]) => `<button role="tab" aria-selected="${ui.training === key}" data-action="training-tab" data-tab="${key}">${title}</button>`).join('')}</div>${state.active ? `<button class="active-session" data-action="active-workout"><span class="session-pulse"></span><span><b>${escape(state.active.name)}</b><small>进行中 · 已记录 ${state.active.sets.length} 组</small></span><span>继续${icon('right', 15)}</span></button>` : ''}${state.active ? sessionProgress() : ''}${ui.training === 'plans' ? `${plans.length ? plans.map(plan => `<section class="card plan-card"><div class="plan-head"><span class="pill">${escape(plan.source || '我的计划')}</span><button class="icon-button" data-action="plan-detail" data-id="${plan.id}" aria-label="查看${escape(plan.name)}计划详情">${icon('right', 18)}</button></div><h2>${escape(plan.name)}</h2><p>${plan.exercises.length} 个动作 · 每周 ${plan.days.length} 次</p><div class="plan-days" aria-label="每周训练安排">${['一', '二', '三', '四', '五', '六', '日'].map((day, index) => `<span class="day-chip ${plan.days.includes(index + 1) ? 'on' : ''} ${index === 1 ? 'today' : ''}">${day}</span>`).join('')}</div><div class="plan-today"><span>${plan.days.includes(2) ? '今天是训练日' : '今天休息，恢复也很重要'}</span>${button(state.active ? '继续训练' : '开始训练', 'start-workout', 'primary', `data-id="${plan.id}" ${!state.active && !plan.days.includes(2) ? 'disabled' : ''}`)}</div></section>`).join('') : empty('dumbbell', '你的第一个计划，正在等你', '手动创建，或先让 AI 给一份草案。', button('创建训练计划', 'create-plan', 'primary'))}<div class="create-plan-row">${button(`${icon('plus', 17)} 手动创建`, 'create-plan', 'block')}${button(`${icon('spark', 17)} AI 创建`, 'ai-plan', 'block outline-brand')}</div>` : trainingHistory()}<button class="list-link" data-action="exercise-library">${chip('book')}<span><b>动作库</b><small>先了解动作，再开始训练</small></span>${icon('right', 16)}</button>${volumePanel()}</div>`;
  }
  function exerciseGlyph(row) {
    const muscle = { 胸: 'dumbbell', 背: 'muscle-back', 腿: 'muscle-legs', 肩: 'muscle-shoulders', 手臂: 'muscle-arms', 核心: 'muscle-core', 全身: 'spark' };
    const equipment = { 杠铃: 'barbell', 哑铃: 'dumbbell', 器械: 'machine', 绳索: 'cable', 自重: 'bodyweight', 其他: 'other' };
    return `<span class="exercise-glyph" data-equipment="${equipment[row.equipment] || 'other'}" data-muscle="${escape(row.group)}">${icon(muscle[row.group] || 'dumbbell', 24)}</span>`;
  }
  function exerciseResults() {
    const rows = M.searchExerciseLibrary(state, ui.exerciseQuery, ui.muscle);
    return `<p class="library-result-count" role="status">${rows.length} 个动作</p>${rows.length ? `<div class="exercise-grid">${rows.map(row => `<button class="exercise-tile" data-action="exercise-detail" data-id="${escape(row.id)}" title="${escape(row.name)}"><span class="exercise-tile-top">${exerciseGlyph(row)}<span class="exercise-meta">${escape(row.group)}</span></span><span class="exercise-title">${escape(row.name)}</span><span class="exercise-badges"><span>${escape(row.equipment)}</span><span>${row.difficulty === null ? '难度未知' : escape(row.difficulty)}</span></span></button>`).join('')}</div>` : empty('search', '没有找到动作', '试试其他关键词或肌群，也可以新建本地样例。')}`;
  }
  function exerciseLibraryPage() {
    return `<div class="page exercise-library-page"><div class="library-toolbar"><button class="icon-button" data-action="exercise-library-back" aria-label="返回训练">${icon('back')}</button><h1>动作库</h1>${button(`${icon('plus', 16)} 新建`, 'exercise-create', 'small')}</div><label class="exercise-search search-field">${icon('search', 18)}<input id="exercise-query" type="search" value="${escape(ui.exerciseQuery)}" placeholder="搜索动作或肌群" aria-label="搜索动作或肌群"></label><div class="muscle-filters" role="group" aria-label="目标肌群">${['全部', ...M.muscleGroups].map(group => `<button data-action="muscle-filter" data-group="${group}" aria-pressed="${ui.muscle === group}">${group}</button>`).join('')}</div><div id="exercise-results">${exerciseResults()}</div><p class="subtle-note">独立展示样例，不影响训练计划与统计。新建仅保存在本页内存，刷新复原。</p></div>`;
  }
  function showExercise(id) {
    const row = state.exerciseLibrary.find(item => item.id === id);
    if (!row) return;
    const alternatives = state.exerciseLibrary.filter(item => item.group === row.group && item.id !== id).slice(0, 6);
    openSheet('动作详情', `<div class="exercise-detail-hero" data-id="${escape(row.id)}">${exerciseGlyph(row)}<div class="exercise-detail-main"><h3>${escape(row.name)}</h3><p>${escape(row.group)} · ${escape(row.equipment)} · ${row.origin === 'user' ? '本地新建' : '展示样例'}</p></div></div>${note('示例未含难度与常用资料，不提供动作教学或视频。')}<h3>同肌群替代动作</h3><div class="exercise-alternatives">${alternatives.length ? alternatives.map(item => `<button class="exercise-alternative" data-action="exercise-detail" data-id="${escape(item.id)}">${exerciseGlyph(item)}<span class="exercise-alternative-main"><b>${escape(item.name)}</b><small>${escape(item.equipment)} · 难度未知</small></span>${icon('right', 16)}</button>`).join('') : '<p class="intro-copy">暂无同肌群替代动作。</p>'}</div>`, 'exercise');
  }
  function exerciseCreateForm() {
    openSheet('新建动作样例', form('exercise-create-form', `${field('动作名称', 'exercise-name', '', 'maxlength="80" autocomplete="off"')}<div class="form-field"><label for="exercise-group">目标肌群</label><select id="exercise-group" name="exercise-group">${M.muscleGroups.map(group => `<option>${group}</option>`).join('')}</select></div><div class="form-field"><label for="exercise-equipment">器械类型</label><select id="exercise-equipment" name="exercise-equipment">${M.equipmentTypes.map(type => `<option>${type}</option>`).join('')}</select></div>${note('仅加入当前展示库，刷新复原；不会加入训练计划、历史或容量统计。难度与常用资料保留未知。')}`, '保存本地样例'), 'exercise-create');
  }
  function trainingHistory() {
    return state.history.length ? `<section class="card history-list">${state.history.map(row => `<button class="history-row" data-action="history-detail" data-id="${row.id}">${chip('check')}<span class="history-main"><span class="h-name">${escape(row.name)}</span><span class="h-meta">${row.date.slice(5).replace('-', ' 月 ')} 日 · ${row.minutes} 分钟 · ${row.sets.length} 组</span></span>${icon('right', 16)}</button>`).join('')}</section>` : empty('calendar', '还没有训练记录', '完成一次训练后，会在这里留下足迹。');
  }
  function settingsRow(name, title, subtitle, action, extra = '') {
    return `<button class="settings-row ${extra}" data-action="${action}">${chip(name)}<span class="settings-main"><span class="settings-title">${title}</span>${subtitle ? `<span class="settings-sub">${subtitle}</span>` : ''}</span><span class="chev">${icon('right', 15)}</span></button>`;
  }
  function healthPanel() {
    const h=M.health(state), bmi=h.bmi, range=h.range;
    const axisMax=Math.max(2400,range?.max||0,(h.bmr||0)*1.2);
    return `<section class="card health-panel" data-graphic="health-gauges"><div class="card-row"><h2 class="section-title">我的健康指标</h2><span class="quiet-label">资料与今日记录</span></div><div class="health-metric bmi-metric"><div class="metric-heading"><span>BMI</span><b>${bmi===null?'—':bmi.toFixed(1)} ${bmi===null?'':`<small class="pill today">${escape(h.bmiLabel)}</small>`}</b></div><div class="bmi-scale ${bmi===null?'unknown':''}"><span style="flex:3.5;background:var(--water)"></span><span style="flex:5.5;background:var(--brand)"></span><span style="flex:4;background:var(--carbs)"></span><span style="flex:7;background:var(--protein)"></span>${bmi===null?'':`<i class="gauge-marker" style="left:${h.bmiPosition}%"></i>`}</div>${bmi===null?'':'<div class="bmi-labels"><span>偏瘦</span><span>正常</span><span>超重</span><span>肥胖</span></div>'}<p class="chart-hint">${bmi===null?'记录身高与体重后显示':'18.5 / 24 / 28 为分档边界，仅作健康参考'}</p></div><div class="health-metric"><div class="metric-heading"><span>基础代谢</span><b>${h.bmr===null?'—':format(h.bmr)}<small> kcal/天</small></b></div><div class="target-scale">${range?`<span style="left:${range.min/axisMax*100}%;width:${(range.max-range.min)/axisMax*100}%"></span>`:''}${h.bmr===null?'':`<i class="gauge-marker" style="left:${h.bmr/axisMax*100}%"></i>`}</div><div class="range-labels"><span>0</span><span>${range?`目标 ${format(range.min)}–${format(range.max)} kcal`:'尚无目标区间'}</span><span>${format(axisMax)}</span></div></div><div class="health-metric hydration-metric">${ring(h.waterRatio,h.waterRatio===null?'':Math.round(h.waterRatio*100)+'%','今日进度','var(--water)',72)}<div><span>每日水分目标</span><b>${state.profile.waterGoal>0?format(state.profile.waterGoal/1000):'—'}<small> L</small></b><p>今天已饮 ${format(state.water/1000)} L</p></div>${link('加一杯','water-quick')}</div></section>`;
  }
  function achievementPanel() {
    const rows=M.achievements(state);
    return `<section class="card achievement-panel" data-graphic="achievements"><div class="card-row"><h2 class="section-title">每一份坚持，都算数</h2><span class="quiet-label">${rows.filter(r=>r.unlocked).length} / ${rows.length} 已解锁</span></div>${rows.map(row=>{
      const color=row.tier==='gold'?'var(--carbs)':row.tier==='silver'?'var(--muted)':'var(--weight)';
      return `<div class="achievement-row"><span class="medal ${row.unlocked?'unlocked':''}" style="--medal-color:${color}">${ring(row.progress,'','成就进度',color,44)}<span class="medal-icon">${icon(row.unlocked?(row.icon||'check'):'lock',18)}</span></span><div class="achievement-main"><div><b>${escape(row.label)}</b><span class="tier" style="color:${color}">${row.tier==='gold'?'金':row.tier==='silver'?'银':'铜'}</span></div>${track(row.progress,color)}<small>${row.unlocked?'已解锁':`${row.count} / ${row.target}`}</small></div></div>`;
    }).join('')}<p class="chart-hint">进度为历史最高值，不因删记录而回退。示例快照。</p></section>`;
  }
  function sessionProgress() {
    if(!state.active) return '';
    const goal=state.active.exercises.reduce((sum,e)=>sum+e.sets,0), count=state.active.sets.length;
    return `<div class="session-progress" data-graphic="set-progress"><div><span>完成组数</span><b>${count} / ${goal}</b></div>${track(count/goal)}</div>`;
  }
  function volumePanel() {
    const stats=M.volumeStats(state), max=Math.max(100,...stats.weeks.map(w=>w.volume));
    let offset=0;
    const colors=['var(--brand)','var(--water)','var(--protein)','var(--fat)'];
    const arcs=stats.groups.map((g,i)=>{const len=g.ratio*251.33,arc=`<circle cx="48" cy="48" r="40" fill="none" stroke="${colors[i%4]}" stroke-width="10" stroke-dasharray="${len} 251.33" stroke-dashoffset="${-offset}"/>`;offset+=len;return arc;}).join('');
    return `<section class="card volume-panel" data-graphic="training-volume"><div class="card-row"><h2 class="section-title">训练容量趋势</h2><span class="quiet-label">近四周 · kg</span></div>${stats.weeks.some(w=>w.volume>0)?`<div class="volume-bars">${stats.weeks.map(w=>`<div><b>${format(w.volume)}</b><span><i style="height:${w.volume/max*100}%"></i></span><small>${w.date.slice(5).replace('-','/')}周</small></div>`).join('')}</div>`:'<div class="chart-empty">完成负重训练后显示容量趋势</div>'}<p class="chart-hint">容量 = 每组重量 × 次数的合计</p><div class="card-row muscle-heading"><h2 class="section-title">肌群容量占比</h2><span class="quiet-label">全部已完成训练</span></div>${stats.total?`<div class="muscle-distribution"><div class="muscle-ring" role="img" aria-label="肌群容量分布"><svg viewBox="0 0 96 96" style="transform:rotate(-90deg)"><circle cx="48" cy="48" r="40" fill="none" stroke="var(--track)" stroke-width="10"/>${arcs}</svg><span><b>${format(stats.total)}</b><small>kg</small></span></div><div class="muscle-legend">${stats.groups.map((g,i)=>`<div><i style="background:${colors[i%4]}"></i><span>${escape(g.name)}</span><b>${Math.round(g.ratio*100)}%</b><small>${format(g.volume)} kg</small></div>`).join('')}</div></div>`:'<div class="chart-empty">暂无可分配的训练容量</div>'}</section>`;
  }
  function settingsPage() {
    const last = M.weightChart(state).latest;
    return `<div class="page settings-page">${head('我的', '关于你，也关于你的数据', '<span class="local-badge">本地优先</span>')}<button class="card profile-card" data-action="profile-edit"><span class="avatar">${escape(Array.from(state.profile.name)[0])}</span><span class="profile-main"><span class="profile-name">${escape(state.profile.name)}</span><span class="profile-meta">查看与编辑个人资料</span></span>${icon('right', 17)}</button><div class="quick-stats profile-stats"><div class="stat"><b>${state.meals.length}</b><span>饮食记录</span></div><div class="stat"><b>${state.history.length}</b><span>完成训练</span></div><div class="stat"><b>${last === null ? '—' : last}<small> kg</small></b><span>最近体重</span></div></div>${healthPanel()}${achievementPanel()}<section><h2 class="group-label">身体与目标</h2><div class="card settings-group">${settingsRow('user', '个人资料', '身体数据、活动水平与偏好', 'profile-edit')}${settingsRow('target', '每日目标', '饮水 ' + format(state.profile.waterGoal) + ' ml · 步数 ' + format(state.profile.stepGoal), 'profile-edit')}${settingsRow('scale', '体重记录', '查看趋势或记录今天的体重', 'weight-history')}</div></section><section><h2 class="group-label">AI 与数据</h2><div class="card settings-group">${settingsRow('spark', 'AI 模型', '服务提供商与模型', 'ai-settings')}${settingsRow('shield', '备份数据', '口令加密的 .lfb 文件', 'backup')}${settingsRow('file-import', '恢复数据', '从加密备份文件读入', 'restore-info')}${settingsRow('file-export', '导出饮食记录', '保存为文件', 'export-diet')}${settingsRow('file-export', '导出训练记录', '保存为文件', 'export-training')}${settingsRow('file-export', '导出食物数据', '保存为文件', 'export-food')}${settingsRow('clock', '自动本地备份', '现有备份策略与开关不变', 'auto-backup-info')}</div></section><section><h2 class="group-label">食材与设备</h2><div class="card settings-group">${settingsRow('bowl', '食材数据库', state.foods.length + ' 条演示食物', 'open-foods')}${settingsRow('plus', '添加食物数据', '手动添加或导入目录', 'food-management')}${settingsRow('book', '维护地点 / 窗口 / 菜品', '食堂目录与已分析菜品', 'canteen-directory')}${settingsRow('steps', '步数与身体活动', '运动数据与权限', 'steps-detail')}${settingsRow('scale', '电子体重秤', '接口预留，小米秤暂未适配', 'scale-info')}</div></section><section><h2 class="group-label">关于</h2><div class="card settings-group">${settingsRow('info', '关于 LocalFit AI', '版本、帮助、来源与反馈', 'about')}</div></section><div class="card settings-group">${settingsRow('trash', '清除所有数据', '此设计稿只展示确认流程', 'clear-preview', 'danger')}</div><p class="page-end">LocalFit AI<br><span>让每一次记录，回到你自己。</span></p></div>`;
  }
  const designNotes = {
    today:[['完整热量环，仍是主角','保持热量环与三营养进度的组合，数值回到图形中心。'],['真实的日期槽','周一至周日七格；月图每日一格。没记录就留空。'],['记录就近完成','饮水、体重、餐次的操作紧邻相应数据。']],
    nutrition:[['每一天都有图形线索','日期短柱、七日趋势与目标虚线共同表达摄入变化。'],['小环回到食物列表','环表示每100g能量密度，满刻度1000 kcal，并非每日目标。'],['区分事实与建议','记录为已吃事实；菜单是候选，确认克数后才加入。']],
    ai:[['中央入口仍是聊天','六项创作任务先填写描述，再进入对话。'],['应用才产生计划','草案可应用或忽略，演示回复不伪装真实AI。']],
    training:[['图形与行动都保留','七日分钟、周安排、组数进度、容量趋势和肌群占比。'],['不混淆统计单位','容量按重量乘次数计算，分钟数不冒充容量。']],
    settings:[['三种指标，三种图形','BMI分档尺、代谢目标区间、水分环，不再退化成三块文字。'],['坚持有可见的轨迹','铜银金勋章、锁定状态、进度弧与进度条完整保留。'],['设置入口不删减','健康区在前，设备、数据及偏好依旧可达。']]
  };
  function render(keepScroll = false) {
    const scroll = screen.scrollTop;
    const focused = captureFocus();
    document.documentElement.dataset.view = ui.page === 'training' && ui.training === 'library' ? 'exercise-library' : ui.page;
    screen.innerHTML = ({ today: todayPage, nutrition: nutritionPage, ai: aiPage, training: trainingPage, settings: settingsPage })[ui.page]();
    document.getElementById('preview-page-name').textContent = pages[ui.page];
    document.getElementById('app-nav').innerHTML = [['today', 'home', '今日'], ['nutrition', 'bowl', '饮食'], ['ai', 'spark', 'AI'], ['training', 'dumbbell', '训练'], ['settings', 'user', '我的']].map(([key, name, label]) => `<button class="nav-item ${key === 'ai' ? 'nav-ai' : ''}" data-action="navigate" data-page="${key}" ${ui.page === key ? 'aria-current="page"' : ''}><span class="nav-icon">${icon(name, key === 'ai' ? 25 : 22)}</span><span>${label}</span></button>`).join('');
    document.querySelectorAll('.page-directory button').forEach(item => {
      if (item.dataset.page === ui.page) item.setAttribute('aria-current', 'page');
      else item.removeAttribute('aria-current');
    });
    document.getElementById('page-notes').innerHTML = designNotes[ui.page].map(([title, text]) => `<div class="note-item"><b>${title}</b><span>${text}</span></div>`).join('');
    screen.scrollTop = keepScroll ? scroll : 0;
    document.title = `${pages[ui.page]} · ${variant.toUpperCase()} · LocalFit AI Round7`;
    if (focused && layer.hidden) restoreFocus(focused);
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
    const focused = !layer.hidden && ui.sheet === kind ? captureFocus() : null;
    if (layer.hidden) returnFocus = captureFocus();
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
    const focus = sheet.querySelector('input:not([type="checkbox"]), textarea, select, button');
    if (focused?.root === sheet) restoreFocus(focused, focus);
    else focus?.focus({ preventScroll: true });
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
    restoreFocus(returnFocus);
    returnFocus = null;
  }
  function mealForm(slot = '晚餐', foodId) {
    if (!state.foods.length) {
      openSheet('记录饮食', `${empty('bowl', '先准备你的食物库', '当前预览没有食物数据。导入明确标示的示例食物后，即可体验克数换算与记录。', button('导入示例食物', 'import-examples', 'primary'))}${note('本稿不启动相机、不读取文件，也不会写入 App 数据。')}`);
      return;
    }
    openSheet('记录饮食', form('meal-form', `<div class="form-field"><label for="meal-food">选择食物</label><select id="meal-food" name="food">${state.foods.map(food => `<option value="${escape(food.id)}" ${food.id === foodId ? 'selected' : ''} ${M.foodCanRecord(food) ? '' : 'disabled'}>${escape(food.name)} · ${M.foodCanRecord(food) ? format(food.kcal) + ' kcal / 100 g' : '营养不完整'}</option>`).join('')}</select></div>${field('食用克数（g）', 'grams', '100', 'type="number" inputmode="decimal" min="1" max="5000" step="any"')}<div class="form-field"><label for="meal-slot">餐次</label><select id="meal-slot" name="slot">${['早餐', '午餐', '晚餐', '加餐'].map(value => `<option ${value === slot ? 'selected' : ''}>${value}</option>`).join('')}</select></div>${note('记录到 10 月 13 日。营养值按实际填写克数换算。')}`, '保存饮食记录'));
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
    const density = M.density(food.kcal);
    const editable = food.origin === 'example';
    const source = editable ? '示例' : food.origin === 'builtIn' ? '内置 · 只读' : '只读';
    const nutrientRows = [['protein', '蛋白质'], ['carbs', '碳水'], ['fat', '脂肪']].map(([key, name]) => {
      const value = Number.isFinite(food[key]) && food[key] >= 0 ? food[key] : 0;
      return `<div><i class="macro-dot ${key}"></i><span>${name}</span><b>${format(value)}g</b></div>`;
    }).join('');
    openSheet('食物详情', `<div class="food-detail-hero">${foodSymbol(food, 'food-detail-icon')}<div><h3 class="food-detail-title">${escape(food.name)}</h3><p class="food-detail-meta"><span>${escape(food.category)}${food.brand ? ' · ' + escape(food.brand) : ''}</span><span class="pill today">${source}</span></p></div></div><div class="food-nutrition-panel">${ring(density.ratio, density.value === null ? '—' : format(density.value), '每100g能量密度', 'var(--brand)', 56, 'detail-density', 6)}<div class="food-macro-stack">${nutrientRows}</div></div><p class="food-density-note">每 100g · 满刻度 1000 kcal/100g${density.value === null ? '<br>无热量数据，环留空' : ''}</p>${M.foodCanRecord(food) ? '' : note('营养不完整，暂不能加入饮食记录。缺失的宏量只显示为 0g，不作为已确认营养计算。')}${note('示例营养仅用于界面预览，不代表真实食物检测结果。')}${M.foodCanRecord(food) ? button('记录这份食物', 'food-record', 'primary block confirm', `data-id="${escape(food.id)}"`) : ''}${editable ? `<div class="food-detail-actions">${button(`${icon('edit', 16)} 编辑`, 'food-edit', 'outline-brand', `data-id="${escape(food.id)}"`)}${button(`${icon('trash', 16)} 删除`, 'food-delete', 'danger', `data-id="${escape(food.id)}"`)}</div>` : ''}`, 'food');
  }
  function foodEditForm(foodId) {
    const food = state.foods.find(row => row.id === foodId);
    if (!food || food.origin !== 'example') return;
    const nutrients = [['kcal', '热量（kcal）', 1000], ['protein', '蛋白质（g）', 100], ['carbs', '碳水（g）', 100], ['fat', '脂肪（g）', 100]];
    openSheet('编辑食物样例', form('food-edit-form', `<input type="hidden" name="food-id" value="${escape(food.id)}">${field('食物名称', 'food-name', food.name, 'maxlength="80" autocomplete="off"')}${field('品牌（可选）', 'food-brand', food.brand, 'maxlength="80"')}<div class="form-grid">${nutrients.map(([key, label, max]) => field(label, 'food-' + key, food[key] ?? '', `type="number" inputmode="decimal" min="0" max="${max}" step="any"`)).join('')}</div>${note('以上均为每 100g。留空表示未知；热量为 0 按无数据展示。修改不会回写已记录的餐食。')}${button('取消修改', 'food-detail', 'ghost block', `data-id="${escape(food.id)}"`)}`, '保存修改'), 'food-edit');
  }
  function confirmFoodDelete(foodId) {
    const food = state.foods.find(row => row.id === foodId);
    if (!food || food.origin !== 'example') return;
    openSheet('删除这条示例食物？', `<p class="intro-copy">“${escape(food.name)}”将从本页示例库移除。</p>${note('已记录餐食不会改变；刷新页面可恢复示例，不影响 App。')}<div class="form-actions">${button('取消', 'food-detail', 'ghost', `data-id="${escape(food.id)}"`)}${button('删除示例', 'confirm-food-delete', 'danger', `data-id="${escape(food.id)}"`)}</div>`, 'food-delete');
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
    openSheet('正在训练', `<div class="active-heading"><span class="pill today"><i class="session-pulse"></i>进行中</span><h3>${escape(active.name)}</h3><p>已记录 ${active.sets.length} 组 · 容量 ${format(active.sets.reduce((sum, row) => sum + row.volume, 0))} kg</p></div>${sessionProgress()}<div>${active.exercises.map(exercise => {
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
      ui.proposal = String(++proposalSequence);
      state.proposalStatus = 'pending';
      ui.messages.push({ role: 'ai', text: '这是一份演示训练草案。你可以先检查动作，再决定是否应用。' });
    } else {
      ui.messages.push({ role: 'ai', text: /晚餐|吃法|吃什么|搭配/.test(message)
        ? '示例建议：晚餐可以搭配一份主食、蛋白质食物和蔬菜，份量结合今天的摄入与饥饿感调整。\n这只是建议，不会自动生成饮食记录。'
        : '这是离线交互演示，不会真正分析这条消息。正式 App 会通过你配置的 AI 服务继续对话；计划草案仍需明确确认后才会应用。' });
    }
    navigate('ai');
    screen.scrollTop = screen.scrollHeight;
    screen.querySelector('#chat-form input')?.focus({ preventScroll: true });
  }
  function creationForm(title,prompt) {
    openSheet(title,form('creation-form',`<input type="hidden" name="prompt" value="${escape(prompt)}"><div class="form-field"><label for="creation-description">描述你的需求</label><textarea id="creation-description" name="description" rows="4" maxlength="1000" placeholder="写下你的食材、目标或具体问题…"></textarea></div>${note('发送到演示对话后再查看建议；不会连接真实 AI 或自动写入计划。')}`,'在对话中生成'));
    sheet.querySelector('button[type="submit"]').disabled=true;
  }
  function workbench() {
    openSheet('AI 创作', `<p class="intro-copy">从一个具体想法开始，结果先在对话里讨论。</p><div class="workbench-grid">${[
      ['book', '解析学校菜单', '从菜单文本开始整理', '帮我解析一份学校菜单'],
      ['bowl', '分析菜品营养', '梳理菜名与配料信息', '帮我分析一道菜的营养'],
      ['sun', '生成今日吃法', '只在对话中提供建议', '今天的吃法怎么安排？'],
      ['leaf', '这道菜怎么吃', '讨论份量、搭配与替换', '这道菜怎么搭配更合适？'],
      ['dumbbell', '训练计划', '先看草案，再确认应用', 'plan'],
      ['target', '常吃搭配', '围绕自己的本地食材', '用我常吃的食材构思搭配'],
    ].map(([name, title, subtitle, prompt]) => `<button data-action="creation-form" data-title="${title}" data-prompt="${prompt}">${chip(name, 'mint')}<b>${title}</b><small>${subtitle}</small></button>`).join('')}</div>${note('创作页是对话起点。当前为演示样例，既不联网生成，也不写入真实数据。')}`);
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
    'license-info': ['数据来源与许可证', '正式 App 的来源说明与许可证保留。本稿复用原 App 食物分类 SVG 与本地线性图标，只使用明确标注的示例数据，没有加载网络字体或图片。'],
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
      case 'large-text': {const large=document.documentElement.dataset.large!=='1';document.documentElement.dataset.large=large?'1':'0';target.setAttribute('aria-pressed',String(large));target.textContent=large?'默认文字':'放大文字';break;}
      case 'theme': setTheme(ui.theme === 'light' ? 'dark' : 'light'); break;
      case 'empty':
        ui.empty = !ui.empty; state = M.createState(ui.empty); ui.messages = []; ui.proposal = false; ui.query = ''; ui.category = '全部';
        document.getElementById('empty-toggle').textContent = ui.empty ? '恢复示例数据' : '查看空状态';
        document.getElementById('empty-toggle').setAttribute('aria-pressed', String(ui.empty));
        closeSheet(); render(); toast(ui.empty ? '已切换为空数据预览' : '已恢复示例数据'); break;
      case 'dismiss-sheet': closeSheet(); break;
      case 'weight-period': ui.weightPeriod = data.period; render(true); if (ui.sheet === 'weights') showWeights(); break;
      case 'weight-point': {
        const plot=target.closest('.weight-plot'), tooltip=plot.querySelector('.weight-tooltip');
        const same=tooltip.dataset.date===data.date&&!tooltip.hidden;
        document.querySelectorAll('.weight-tooltip').forEach(t=>{t.hidden=true;});
        if(!same) {
          const bar=target.querySelector('.weight-bar-space > i').getBoundingClientRect(), bounds=plot.getBoundingClientRect();
          tooltip.textContent=`${data.date.slice(5).replace('-','/')}  ${data.value} kg`;
          tooltip.dataset.date=data.date;tooltip.hidden=false;
          const half=tooltip.getBoundingClientRect().width/2;
          tooltip.style.left=Math.max(half,Math.min(bounds.width-half,bar.x+bar.width/2-bounds.x))+'px';
          tooltip.style.top=(bar.y-bounds.y-26)+'px';
        }
        break;
      }
      case 'weight-add': weightForm(); break;
      case 'weight-history': showWeights(); break;
      case 'water-quick': M.addWater(state, 250); render(true); toast('已记录 250 ml 饮水'); break;
      case 'meal-add': mealForm(data.slot); break;
      case 'food-record':
        if (M.foodCanRecord(state.foods.find(food => food.id === data.id))) mealForm('晚餐', data.id);
        break;
      case 'delete-meal': undoMeal = M.removeMeal(state, data.id); render(true); toast('已删除本条饮食记录', true); break;
      case 'undo-meal': M.restoreMeal(state, undoMeal); undoMeal = null; render(true); toast('已恢复饮食记录'); break;
      case 'nutrition-date': ui.date=data.date; render(true); break;
      case 'nutrition-records': ui.date = state.today; ui.nutrition = 'records'; navigate('nutrition'); break;
      case 'nutrition-tab': ui.nutrition = data.tab; render(); break;
      case 'category': ui.category = data.category; render(true); break;
      case 'clear-filter': ui.query = ''; ui.category = '全部'; render(); break;
      case 'food-detail': showFood(data.id); break;
      case 'food-edit': foodEditForm(data.id); break;
      case 'food-delete': confirmFoodDelete(data.id); break;
      case 'confirm-food-delete': M.removeFood(state, data.id); closeSheet(); render(true); toast('已删除本页示例食物，原有餐食不变'); break;
      case 'import-examples': {
        const result = M.importExamples(state); closeSheet(); render(true);
        toast(`示例导入 ${result.imported} 条，跳过重复 ${result.skipped} 条`); break;
      }
      case 'import-info':
        openSheet('导入食物数据', `${note('正式 App 使用现有 21 列结构，兼容旧版 8 列。这里不读取文件，只用 8 条固定示例演示导入后的列表与重复跳过反馈。')}${button('导入 8 条示例食物', 'import-examples', 'primary block')}`); break;
      case 'food-management':
        openSheet('食物库管理', `${settingsRow('file-import', '导入食物数据', '从文件读取到食物库 · 本页仅演示', 'import-info')}${settingsRow('bowl', '浏览食物库', `${state.foods.length} 条演示数据`, 'open-foods')}${settingsRow('trash', '清空内置食物', '不等于清空所有数据', 'clear-built-in')}${note('新装正式 App 不再随包回灌食物。这里的 8 条示例仅用于设计预览。')}`); break;
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
      case 'creation-form': creationForm(data.title,data.prompt); break;
      case 'ai-prompt': creationForm('饮食建议',data.prompt); break;
      case 'ai-plan': creationForm('训练计划','plan'); break;
      case 'apply-proposal':
      case 'ignore-proposal':
        if (data.proposal !== ui.proposal || state.proposalStatus !== 'pending') break;
        if (action === 'apply-proposal') M.applyPlanProposal(state);
        else M.ignorePlanProposal(state);
        render(true); toast(action === 'apply-proposal' ? '计划已加入演示训练列表' : '已忽略，没有写入计划'); break;
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
        if (ui.training !== 'library') ui.trainingReturn = ui.training;
        ui.training = 'library'; navigate('training'); break;
      case 'exercise-library-back': ui.training = ui.trainingReturn; render(); break;
      case 'muscle-filter': ui.muscle = data.group; render(true); break;
      case 'exercise-detail': showExercise(data.id); break;
      case 'exercise-create': exerciseCreateForm(); break;
      case 'history-detail': {
        const row = state.history.find(item => item.id === data.id);
        if (row) openSheet('训练回顾', `<div class="detail-energy"><b>${row.sets.length}</b><span>已完成组数</span></div><h3>${escape(row.name)}</h3><dl class="nutrition-table"><div><dt>训练日期</dt><dd>${row.date}</dd></div><div><dt>训练时长</dt><dd>${row.minutes} 分钟</dd></div><div><dt>总容量</dt><dd>${format(row.volume)} kg</dd></div><div><dt>估算消耗</dt><dd>—</dd></div></dl>${note('历史样例用于排版。新完成的预览训练不虚构计时或卡路里。')}`); break;
      }
      case 'profile-edit': profileForm(); break;
      case 'about': openSheet('关于 LocalFit AI', `<div class="food-detail-heading">${chip('leaf', 'mint')}<div><h3>LocalFit AI</h3><p>第七轮界面设计提案</p></div></div><div class="settings-group">${settingsRow('download', '检查更新', '', 'update-info')}${settingsRow('book', '数据来源与许可证', '', 'license-info')}${settingsRow('info', '帮助文档', '', 'help-info')}${settingsRow('edit', '反馈', '', 'feedback-info')}</div>${note('仅在当前页内存中操作，刷新复原；未修改 Flutter App。')}`); break;
      case 'exports': openSheet('导出数据', `<div class="settings-group">${settingsRow('file-export', '导出饮食记录', '保存为文件', 'export-diet')}${settingsRow('file-export', '导出训练记录', '保存为文件', 'export-training')}${settingsRow('file-export', '导出食物数据', '保存为文件', 'export-food')}</div>${note('此处仅预览操作入口，不下载真实数据。')}`); break;
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
    if (!event.target.closest('[data-action="weight-point"]')) document.querySelectorAll('.weight-tooltip').forEach(t=>{t.hidden=true;});
    const target = event.target.closest('[data-action]');
    if (!target || target.disabled) return;
    try { perform(target.dataset.action, target); }
    catch (error) { toast(error.message || '操作未完成，请检查输入'); }
  });
  document.addEventListener('scroll',()=>document.querySelectorAll('.weight-tooltip').forEach(t=>{t.hidden=true;}),true);
  document.addEventListener('input', event => {
    if(event.target.id==='creation-description') event.target.form.querySelector('button[type="submit"]').disabled=!event.target.value.trim();
    if (event.target.id === 'food-query') {
      ui.query = event.target.value;
      document.getElementById('food-results').innerHTML = foodResults();
    }
    if (event.target.id === 'exercise-query') {
      ui.exerciseQuery = event.target.value;
      document.getElementById('exercise-results').innerHTML = exerciseResults();
    }
  });
  document.addEventListener('submit', event => {
    event.preventDefault();
    const target = event.target;
    const data = new FormData(target);
    const previousError = target.querySelector('.form-error');
    if (previousError) previousError.textContent = '';
    try {
      switch (target.id) {
        case 'food-edit-form': {
          const food = M.updateFood(state, data.get('food-id'), { name: data.get('food-name'), brand: data.get('food-brand'), kcal: data.get('food-kcal'), protein: data.get('food-protein'), carbs: data.get('food-carbs'), fat: data.get('food-fat') });
          render(true); showFood(food.id); toast('示例食物已更新，原有餐食不变'); break;
        }
        case 'exercise-create-form':
          M.createLibraryExercise(state, { name: data.get('exercise-name'), group: data.get('exercise-group'), equipment: data.get('exercise-equipment') });
          ui.exerciseQuery = ''; ui.muscle = '全部'; closeSheet(); render(true); toast('已加入本页动作库'); break;
        case 'meal-form': M.addFoodMeal(state, data.get('food'), data.get('grams'), data.get('slot')); ui.date = state.today; closeSheet(); render(true); toast('饮食记录已保存'); break;
        case 'weight-form': M.saveWeight(state, data.get('weight')); closeSheet(); render(true); toast('体重已保存'); break;
        case 'profile-form': M.updateProfile(state, { name: data.get('profile-name'), waterGoal: data.get('water-goal'), stepGoal: data.get('step-goal') }); closeSheet(); render(true); toast('资料与目标已保存'); break;
        case 'set-form': M.recordSet(state, data.get('exercise'), data.get('set-weight'), data.get('set-reps')); render(true); activeWorkout(); toast('已保存这一组'); break;
        case 'plan-form': M.createManualPlan(state, data.get('plan-name'), data.getAll('exercise')); ui.training = 'plans'; navigate('training'); toast('训练计划已创建'); break;
        case 'dish-form': M.recordDish(state, dishes.find(row => row.id === data.get('dish')), data.get('dish-grams'), data.get('slot')); ui.date = state.today; closeSheet(); ui.nutrition = 'records'; render(); toast('菜品已加入今天的饮食记录'); break;
        case 'creation-form': {const text=String(data.get('description')||'').trim();if(!text) throw new Error('请先描述你的需求'); respond((data.get('prompt')==='plan'?'训练计划':data.get('prompt'))+'：'+text,data.get('prompt')==='plan');break;}
        case 'chat-form': respond(data.get('message')); break;
      }
    } catch (error) {
      const feedback = target.querySelector('.form-error');
      if (feedback) feedback.textContent = error.message || '请检查输入';
      else toast(error.message || '操作未完成');
    }
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      const tooltips = [...document.querySelectorAll('.weight-tooltip')].filter(tooltip => !tooltip.hidden);
      if (tooltips.length) {
        event.preventDefault();
        tooltips.forEach(tooltip => { tooltip.hidden = true; });
        return;
      }
    }
    if (layer.hidden) return;
    if (event.key === 'Escape') { event.preventDefault(); closeSheet(); return; }
    if (event.key === 'Tab') {
      const focusable = [...sheet.querySelectorAll('button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), a[href], [tabindex="0"]')].filter(element => element.offsetParent !== null);
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
  if(params.get('large')==='1'){document.documentElement.dataset.large='1';document.getElementById('text-toggle').setAttribute('aria-pressed','true');document.getElementById('text-toggle').textContent='默认文字';}
  setTheme(ui.theme);
  setWidth(Number(params.get('width')));
  if (ui.empty) {
    document.getElementById('empty-toggle').textContent = '恢复示例数据';
    document.getElementById('empty-toggle').setAttribute('aria-pressed', 'true');
  }
  document.querySelectorAll('[data-icon]').forEach(element => { element.innerHTML = icon(element.dataset.icon, 18); });
  if (ui.page === 'training' && params.get('view') === 'exercise-library') ui.training = 'library';
  render();
  if (ui.page === 'nutrition' && ui.nutrition === 'foods' && state.foods.some(food => food.id === params.get('food'))) showFood(params.get('food'));
})();
