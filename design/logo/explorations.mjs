#!/usr/bin/env node
/**
 * LocalFit AI · logo 发散探索（10 个方向互不相同的方案）。
 *
 * 与 generate.mjs / ring-variants.mjs 不同：这一组刻意不锁骨架，
 * 色彩（深色霓虹 / 彩虹光圈 / 粉彩软糖 / 深绿徽章）、线条（细线 / 点阵缝线 /
 * 平涂色块 / 线稿）、构图（环 / 盘 / 盾 / 碗筷 / 字标 / 脉搏）都拉开差距。
 *
 * 只输出 icon 变体（这一轮比较的是「观感」，底色本身就是方案的一部分）；
 * 用户选定某个方向后再补 mark / ios 两件套。
 *
 * 运行：node design/logo/explorations.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { C, SIZE, arc, bg, defs, polar } from './kit.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, 'svg');
mkdirSync(SVG_DIR, { recursive: true });

const CX = 512;
const CY = 512;

const lerp = (a, b, t) => a + (b - a) * t;
const mix = (c1, c2, t) => {
  const p = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const [r1, g1, b1] = p(c1);
  const [r2, g2, b2] = p(c2);
  const hex = (v) => Math.round(v).toString(16).padStart(2, '0');
  return `#${hex(lerp(r1, r2, t))}${hex(lerp(g1, g2, t))}${hex(lerp(b1, b2, t))}`;
};

/** 平头环形扇区（外半径 R、内半径 r、角度从 12 点顺时针计）。 */
function annularSector(R, r, from, to, fill) {
  const [ox1, oy1] = polar(CX, CY, R, from);
  const [ox2, oy2] = polar(CX, CY, R, to);
  const [ix2, iy2] = polar(CX, CY, r, to);
  const [ix1, iy1] = polar(CX, CY, r, from);
  return `<path fill="${fill}" d="M ${ox1.toFixed(2)} ${oy1.toFixed(2)} A ${R} ${R} 0 0 1 ${ox2.toFixed(2)} ${oy2.toFixed(2)} L ${ix2.toFixed(2)} ${iy2.toFixed(2)} A ${r} ${r} 0 0 0 ${ix1.toFixed(2)} ${iy1.toFixed(2)} Z"/>`;
}

/** 圆点圆环：用 pathLength 归一化，让点数在任何半径下都均分。 */
function dottedCircle(r, width, color, count) {
  const step = 1000 / count;
  return `<circle cx="${CX}" cy="${CY}" r="${r}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" pathLength="1000" stroke-dasharray="0.1 ${(step - 0.1).toFixed(3)}"/>`;
}

const EXPLORATIONS = [
  {
    slug: 'd1-dark-neon',
    name: '深色霓虹',
    tag: '深色沉浸 · 发光细线',
    note: '训练页的深色沉浸往图标上搬：近黑底、薄荷霓虹细环带外晕，三颗宏量色点收在里面。整组方案里唯一用暗底的。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#0F1412"/>`,
    extraDefs: (uid) => `<filter id="glow-${uid}" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="16" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>`,
    glyph: (uid) => {
      const dots = [90, 210, 330]
        .map((deg, i) => {
          const [x, y] = polar(CX, CY, 180, deg);
          return `<circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="42" fill="${[C.peach, C.honey, C.taro][i]}"/>`;
        })
        .join('\n    ');
      const [hx, hy] = polar(CX, CY, 280, 336);
      return `<g filter="url(#glow-${uid})">
    <path d="${arc(CX, CY, 280, 24, 336)}" fill="none" stroke="#4ED9A6" stroke-width="34" stroke-linecap="round"/>
    ${dots}
    <circle cx="${hx.toFixed(2)}" cy="${hy.toFixed(2)}" r="34" fill="#FFFFFF"/>
  </g>`;
    },
  },
  {
    slug: 'd2-minimal-line',
    name: '极简单线',
    tag: '奶油底 · 一根细线',
    note: '把「环」减到不能再减：奶油底上一根等宽细线加一颗圆心，没有任何填充色块。安静、克制，和花哨的同类健康 App 拉开距离。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${C.cream}"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, 268, 20, 340)}" fill="none" stroke="${C.mint600}" stroke-width="26" stroke-linecap="round"/>
    <circle cx="${CX}" cy="${CY}" r="58" fill="${C.mint500}"/>`,
  },
  {
    slug: 'd3-stitch',
    name: '缝线点阵',
    tag: '点状线条 · 手作感',
    note: '环改成一圈均匀的白色圆点，像缝线或串珠，上面缀三颗宏量色珠。线条语言从「实线」换成「点」，是全组里最俏皮的一个。',
    bg: (uid) => bg(uid, 232),
    glyph: () => {
      const beads = [60, 180, 300]
        .map((deg, i) => {
          const [x, y] = polar(CX, CY, 268, deg);
          return `<circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="46" fill="${[C.peach, C.honey, C.taro][i]}"/>`;
        })
        .join('\n    ');
      return `
    ${dottedCircle(268, 30, '#FFFFFF', 27)}
    ${beads}`;
    },
  },
  {
    slug: 'd4-iris',
    name: '彩虹光圈',
    tag: '无缺口 · 多色渐变',
    note: '闭合的粗环沿圆周做薄荷→珊瑚→蜜黄→雾紫→海盐的渐变，没有缺口。一眼是「营养光谱」，也是全组里颜色最丰富的一个。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#FFFFFF"/>`,
    glyph: () => {
      const pal = [C.mint500, C.mint400, C.peach, C.honey, C.taro, '#A8C4D9', C.mint600];
      const N = 24;
      const segs = [];
      for (let i = 0; i < N; i++) {
        const pos = (i / N) * pal.length;
        const k = Math.floor(pos) % pal.length;
        const col = mix(pal[k], pal[(k + 1) % pal.length], pos - Math.floor(pos));
        segs.push(
          `<path d="${arc(CX, CY, 272, (i * 360) / N, ((i + 1) * 360) / N)}" fill="none" stroke="${col}" stroke-width="88"/>`,
        );
      }
      return segs.join('\n    ');
    },
  },
  {
    slug: 'd5-wedges',
    name: '扇形餐盘',
    tag: '平涂色块 · 无描边',
    note: '整张方案里唯一没有「线条」的：圆盘直接切成三块扇形平涂，中挖奶油圆孔。营养素比例即图形，俯视是一份搭配好的餐。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#FFFFFF"/>`,
    glyph: () =>
      [
        [5, 115, C.peach],
        [125, 235, C.honey],
        [245, 355, C.taro],
      ]
        .map(([a, b, col]) => annularSector(300, 150, a, b, col))
        .join('\n    '),
  },
  {
    slug: 'd6-emblem',
    name: '深绿盾徽',
    tag: '徽章 · 描边盾形',
    note: '底色压到深绿（薄荷 800→900），白描边盾形 + 浅薄荷叶。讲「数据留在本机」，气质从清新App 变成可信工具。',
    bg: (uid) => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="url(#dark-${uid})"/>`,
    extraDefs: (uid) => `<linearGradient id="dark-${uid}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1024" y2="1024">
      <stop offset="0" stop-color="#179167"/>
      <stop offset="1" stop-color="#0A4F37"/>
    </linearGradient>`,
    glyph: () => `
    <path d="M512 268 L742 354 L742 512 C742 636 660 716 512 758 C364 716 282 636 282 512 L282 354 Z"
      fill="none" stroke="#FFFFFF" stroke-width="46" stroke-linejoin="round"/>
    <path fill="${C.mint300}" transform="rotate(38 512 512)"
      d="M512 399.2 C596.3 433.9 613.7 528.1 512 624.8 C410.3 528.1 459.9 433.9 512 399.2 Z"/>`,
  },
  {
    slug: 'd7-lineart',
    name: '线稿碗筷',
    tag: '单色线稿 · 食物符号',
    note: '一笔等宽线勾出碗和筷子，不用任何填充。食堂场景最直白的符号，也是全组里唯一具象画食物的。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${C.cream}"/>`,
    glyph: () => `
    <g fill="none" stroke="${C.mint700}" stroke-width="30" stroke-linecap="round">
      <path d="M300 560 A212 212 0 0 0 724 560"/>
      <path d="M452 800 L572 800"/>
      <path d="M344 306 L648 566"/>
      <path d="M436 278 L744 566"/>
    </g>`,
  },
  {
    slug: 'd8-pulse',
    name: '脉搏环',
    tag: '健身 · 心电图线',
    note: '环在正上方破开，接一段心电 spikes——「记录」与「训练」在同一条线上。珊瑚色脉搏从薄荷环里跳出来，是全组里最有动感的。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#FFFFFF"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, 276, 40, 320)}" fill="none" stroke="${C.mint500}" stroke-width="40" stroke-linecap="round"/>
    <path d="M334.6 300.6 L452 300.6 L508 210 L560 388 L604 300.6 L689.4 300.6"
      fill="none" stroke="${C.peach}" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  {
    slug: 'd9-monogram',
    name: 'LF 字标',
    tag: '字母组合 · 圆头笔画',
    note: 'LocalFit 的 L 和 F 用圆头粗笔画拼出来，同一条基线。唯一带字母的方案，品牌感最强、也最依赖识读；F 的中横用薄荷 300 做一点色彩层次。',
    bg: (uid) => bg(uid, 232),
    glyph: () => `
    <g fill="none" stroke="#FFFFFF" stroke-width="82" stroke-linecap="round" stroke-linejoin="round">
      <path d="M330 306 L330 700 L520 700"/>
      <path d="M566 306 L566 700"/>
      <path d="M566 306 L712 306"/>
    </g>
    <path d="M566 500 L676 500" fill="none" stroke="${C.mint300}" stroke-width="82" stroke-linecap="round"/>`,
  },
  {
    slug: 'd10-candy',
    name: '粉彩软糖',
    tag: '低饱和 · 高光质感',
    note: '三段粉彩粗弧（蜜桃/蜂蜜/香芋的 300 档）拼环，弧上加一道白色高光模拟软糖的光泽。全组里饱和度最低、最「奶油」的。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${C.mint50}"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, 272, 77, 163)}" fill="none" stroke="#FFB89E" stroke-width="96" stroke-linecap="round"/>
    <path d="${arc(CX, CY, 272, 197, 283)}" fill="none" stroke="#C9B9E7" stroke-width="96" stroke-linecap="round"/>
    <path d="${arc(CX, CY, 272, 317, 360)}" fill="none" stroke="#FFDA85" stroke-width="96" stroke-linecap="round"/>
    <path d="${arc(CX, CY, 272, 0, 43)}" fill="none" stroke="#FFDA85" stroke-width="96" stroke-linecap="round"/>
    <path d="${arc(CX, CY, 272, 88, 128)}" fill="none" stroke="#FFFFFF" stroke-width="34" stroke-linecap="round" opacity="0.55"/>`,
  },
];

function renderSvg(c) {
  const uid = c.slug;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  ${defs(uid)}
  ${c.extraDefs ? c.extraDefs(uid) : ''}
  ${c.bg(uid)}
  ${c.glyph(uid)}
</svg>
`;
}

for (const c of EXPLORATIONS) {
  writeFileSync(join(SVG_DIR, `${c.slug}-icon.svg`), renderSvg(c));
}

// ── 预览页（双栏） ─────────────────────────────────────────────────────────
const iconSvg = (c) => renderSvg(c);

const cell = (c) => `
  <section class="cell">
    <div class="hero">${iconSvg(c)}</div>
    <div class="ladder">
      <div class="ladder-cell"><div class="s s128">${iconSvg(c)}</div><span>128</span></div>
      <div class="ladder-cell"><div class="s s64">${iconSvg(c)}</div><span>64</span></div>
      <div class="ladder-cell"><div class="s s48">${iconSvg(c)}</div><span>48</span></div>
      <div class="ladder-cell"><div class="s s32">${iconSvg(c)}</div><span>32</span></div>
      <div class="ladder-cell"><div class="s s24">${iconSvg(c)}</div><span>24</span></div>
    </div>
    <h2>${c.name}</h2>
    <div class="tag">${c.tag}</div>
    <p class="note">${c.note}</p>
  </section>`;

const style = `
  :root { --ink:#17251E; --ink2:#5A6B62; --ink3:#93A29A; --line:#E7ECE8; }
  * { box-sizing:border-box; }
  body { margin:0; padding:44px 52px 60px; background:#FAFBF9; color:var(--ink);
         font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif; }
  h1 { font-size:28px; margin:0 0 6px; letter-spacing:-.4px; }
  .sub { color:var(--ink2); font-size:14px; margin-bottom:26px; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:0 52px; }
  .cell { padding:26px 0 30px; border-top:1px solid var(--line); }
  .hero { width:250px; margin-bottom:20px; }
  .hero svg { width:100%; height:auto; border-radius:24%; box-shadow:0 10px 26px rgba(23,37,30,.13); display:block; }
  .ladder { display:flex; align-items:flex-end; gap:22px; margin-bottom:18px; }
  .ladder-cell { display:flex; flex-direction:column; align-items:center; gap:6px; }
  .ladder-cell span { font-size:11px; color:var(--ink3); }
  .s svg { display:block; border-radius:22%; }
  .s128 svg { width:128px; height:128px; box-shadow:0 5px 14px rgba(23,37,30,.10); }
  .s64 svg  { width:64px;  height:64px;  box-shadow:0 3px 9px rgba(23,37,30,.09); }
  .s48 svg  { width:48px;  height:48px;  box-shadow:0 2px 7px rgba(23,37,30,.08); }
  .s32 svg  { width:32px;  height:32px; }
  .s24 svg  { width:24px;  height:24px; }
  h2 { font-size:21px; margin:0 0 4px; letter-spacing:-.2px; }
  .tag { font-size:12.5px; color:#1FA377; margin-bottom:8px; }
  .note { margin:0; font-size:13.5px; line-height:1.65; color:var(--ink2); }
`;

const page = (items, file, title) =>
  writeFileSync(
    join(HERE, file),
    `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>${title}</title><style>${style}</style></head>
<body><h1>${title}</h1><div class="sub">发散探索 · 色彩 / 线条 / 构图各不相同　｜　色彩仍取自 app_colors.dart 的色板</div>
<div class="grid">${items.map(cell).join('\n')}</div></body></html>`,
  );

page(EXPLORATIONS.slice(0, 5), 'explorations-a.html', 'LocalFit AI · 发散方案 1/2');
page(EXPLORATIONS.slice(5), 'explorations-b.html', 'LocalFit AI · 发散方案 2/2');
page(EXPLORATIONS, 'explorations.html', 'LocalFit AI · 发散方案（全部）');

console.log(`✓ ${EXPLORATIONS.length} 个探索方案 SVG + 3 个预览页已写入`);
