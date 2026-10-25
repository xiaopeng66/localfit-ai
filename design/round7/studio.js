(() => {
  'use strict';

  const controls = document.getElementById('preview-controls');
  if (!controls) return;

  const compare = document.body.dataset.studioMode === 'compare';
  const frames = Array.from(document.querySelectorAll('.phone-frame'));
  const links = Array.from(document.querySelectorAll('[data-preview-link]'));
  const widthControl = document.getElementById('preview-width');
  const themeControl = document.getElementById('preview-theme');
  const emptyControl = document.getElementById('preview-empty');
  const pageControl = document.getElementById('preview-page');
  const status = document.getElementById('preview-status');
  const pages = { today: '今日', nutrition: '饮食记录', ai: 'AI 助手', training: '训练', settings: '我的' };
  const variants = { a: 'A 原版精修', b: 'B 健康仪表台', c: 'C 每日节奏' };
  const query = new URLSearchParams(window.location.search);
  const allowed = (value, values, fallback) => values.includes(value) ? value : fallback;

  widthControl.value = allowed(query.get('width'), ['360', '390', '430'], '360');
  themeControl.value = allowed(query.get('theme'), ['light', 'dark'], 'light');
  emptyControl.value = query.get('empty') === '1' ? '1' : '0';
  if (pageControl) pageControl.value = allowed(query.get('page'), ['today', 'nutrition', 'settings'], 'today');

  function render(reset) {
    const width = allowed(widthControl.value, ['360', '390', '430'], '360');
    const theme = allowed(themeControl.value, ['light', 'dark'], 'light');
    const empty = emptyControl.value === '1';
    const selectedPage = pageControl ? allowed(pageControl.value, ['today', 'nutrition', 'settings'], 'today') : 'today';
    document.documentElement.style.setProperty('--preview-width', `${width}px`);

    function previewURL(element, embed) {
      const params = new URLSearchParams();
      if (embed) params.set('embed', '1');
      params.set('variant', element.dataset.variant);
      params.set('page', compare ? selectedPage : element.dataset.page);
      params.set('width', width);
      params.set('theme', theme);
      if (empty) params.set('empty', '1');
      return `index.html?${params.toString()}`;
    }

    // Changing any control deliberately reloads every frame. The visible notice
    // explains that samples are independent and in-frame edits will be reset.
    frames.forEach(frame => {
      const page = compare ? selectedPage : frame.dataset.page;
      frame.setAttribute('width', width);
      frame.setAttribute('height', '900');
      frame.setAttribute('title', `${variants[frame.dataset.variant]} · ${pages[page]} · ${width} × 900 像素${theme === 'dark' ? '深色' : '浅色'}预览${empty ? ' · 空状态' : ''}`);
      const source = previewURL(frame, true);
      if (reset || frame.getAttribute('src') !== source) frame.setAttribute('src', source);
    });
    links.forEach(link => link.setAttribute('href', previewURL(link, false)));

    const scope = compare ? `三个方案的${pages[selectedPage]}` : 'A 方案五页';
    status.textContent = `${scope}均为 ${width} × 900 px；${theme === 'dark' ? '深色' : '浅色'}，${empty ? '空状态' : '样例记录'}。${reset ? '已重新载入全部预览，框内操作与临时记录已重置。' : ''}`;
  }

  controls.addEventListener('change', () => render(true));
  render(false);
  controls.disabled = false;
})();
