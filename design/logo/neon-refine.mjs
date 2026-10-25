#!/usr/bin/env node
/**
 * LocalFit AI · 深色霓虹脉搏环（细化方案 P4）的线条优化。
 *
 * 骨架不变：近黑底、薄荷环正上方破开接一段珊瑚色脉搏、整体发光。
 * 这一轮只动「线条怎么画」——霓虹的质感全在描边分层上：
 *
 *   N1 n1-core      管芯发光：大晕/紧晕/亮芯/白热管芯四层，真·霓虹灯管
 *   N2 n2-contrast  细环重脉：环减到 26 细线，脉搏加粗到 58 当主角
 *   N3 n3-hollow    空心管：环和脉搏都挖成空心玻璃管，留 12px 气口
 *   N4 n4-gradient  渐变光管：脉搏沿行程从蜜黄渐变到珊瑚
 *   N5 n5-soft      柔波霓虹：P5 的柔化波形搬进霓虹，无尖角
 *
 * 只输出 icon 变体。运行：node design/logo/neon-refine.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SIZE, arc, polar } from './kit.mjs';
const HERE = dirname(fileURLToPath(import.meta.url));
const SVG_DIR = join(HERE, 'svg');
mkdirSync(SVG_DIR, { recursive: true });

const CX = 512;
const CY = 512;
const R = 280;
const BREAK = 40;
const CHORD_Y = +(CY - R * Math.cos((BREAK * Math.PI) / 180)).toFixed(1);
const X1 = +(CX - R * Math.sin((BREAK * Math.PI) / 180)).toFixed(1);
const X2 = +(CX + R * Math.sin((BREAK * Math.PI) / 180)).toFixed(1);

const BG = '#0F1412';
const NEON = '#4ED9A6'; // mintBright
const HOT_MINT = '#E9FFF7';
const CORAL = '#FF8A65';
const HOT_CORAL = '#FFDFCE';
const HONEY = '#FFC94D';

const ringPath = arc(CX, CY, R, BREAK, 360 - BREAK);
/** 尖峰单波：与 P1/P4 同构，峰顶 202。 */
const spikePath = `M${X1} ${CHORD_Y} L452 ${CHORD_Y} L500 202 L552 384 L600 ${CHORD_Y} L${X2} ${CHORD_Y}`;
/** 柔化波：峰谷全曲线收口（P5 的波形）。 */
const softPath =
  `M${X1} ${CHORD_Y} L448 ${CHORD_Y} ` +
  `C466 ${CHORD_Y} 474 205 500 205 C526 205 534 ${CHORD_Y} 552 ${CHORD_Y} ` +
  `C566 ${CHORD_Y} 562 360 590 360 C618 360 614 ${CHORD_Y} 628 ${CHORD_Y} ` +
  `L${X2} ${CHORD_Y}`;
/** 空心管的悬浮脉搏：与环两端各留 12px 气口（环端圆头半径 23，脉搏圆头 23）。 */
const floatPath = `M390 ${CHORD_Y} L446 ${CHORD_Y} L490 206 L540 378 L582 ${CHORD_Y} L634 ${CHORD_Y}`;

/**
 * 霓虹描边四层：大晕（soft 滤镜）→ 紧晕（tight 滤镜）→ 亮芯 → 白热管芯。
 * hot 传 null 表示不要管芯（细线时管芯会糊成一条浅线）。
 */
function neon(d, color, hot, w, uid) {
  const core = (w * 0.82).toFixed(1);
  const parts = [
    `<g filter="url(#soft-${uid})" opacity="0.5"><path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/></g>`,
    `<g filter="url(#tight-${uid})" opacity="0.85"><path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/></g>`,
    `<path d="${d}" fill="none" stroke="${color}" stroke-width="${core}" stroke-linecap="round" stroke-linejoin="round"/>`,
  ];
  if (hot) {
    parts.push(
      `<path d="${d}" fill="none" stroke="${hot}" stroke-width="${(w * 0.26).toFixed(1)}" stroke-linecap="round" stroke-linejoin="round" opacity="0.92"/>`,
    );
  }
  return parts.join('\n    ');
}

/** 空心玻璃管：实色彩管之后用底色挖掉管芯，只留管壁；发光只落在管外。 */
function hollow(d, color, w, uid) {
  return `
    <g filter="url(#soft-${uid})" opacity="0.5"><path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/></g>
    <path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${d}" fill="none" stroke="${BG}" stroke-width="${(w * 0.48).toFixed(1)}" stroke-linecap="round" stroke-linejoin="round"/>`;
}

const VARIANTS = [
  {
    slug: 'n1-core',
    name: 'N1 · 管芯发光',
    tag: '四层描边 · 白热管芯',
    note: '线条分四层：大晕（26 高斯）、紧晕（7 高斯）、亮芯、白热管芯。亮芯比原版细一档，中心一条白热线，是真正「通电灯管」的画法——霓虹质感的标准答案。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${neon(ringPath, NEON, HOT_MINT, 40, uid)}
    ${neon(spikePath, CORAL, HOT_CORAL, 40, uid)}`,
  },
  {
    slug: 'n2-contrast',
    name: 'N2 · 细环重脉',
    tag: '线宽对比 26 / 58',
    note: '环减到 26 的细线退成刻度，脉搏加粗到 58 当主角——心跳是画面里最大声的东西。脉搏保留白热管芯，细环不带（细到那种程度管芯会糊）。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${neon(ringPath, NEON, null, 26, uid)}
    ${neon(spikePath, CORAL, HOT_CORAL, 58, uid)}`,
  },
  {
    slug: 'n3-hollow',
    name: 'N3 · 空心管',
    tag: '挖芯 · 12px 气口',
    note: '环和脉搏都挖成空心玻璃管（底色挖掉管芯，只留 12px 管壁），脉搏不再接在环上、两端各留 12px 气口——像真正弯出来分段安装的灯管，线条最「硬件」。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 46, uid)}
    ${hollow(floatPath, CORAL, 46, uid)}`,
  },
  {
    slug: 'n4-gradient',
    name: 'N4 · 渐变光管',
    tag: '脉搏蜜黄→珊瑚',
    note: '脉搏的描边沿行程从蜜黄渐变到珊瑚（再压到深珊瑚），像充了不同气体的灯管；环保持薄荷。比纯珊瑚多一层暖意，也把「能量消耗」的方向感画了出来。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    extraDefs: (uid) => `<linearGradient id="pg-${uid}" gradientUnits="userSpaceOnUse" x1="${X1}" y1="${CHORD_Y}" x2="${X2}" y2="${CHORD_Y}">
      <stop offset="0" stop-color="${HONEY}"/>
      <stop offset="0.5" stop-color="${CORAL}"/>
      <stop offset="1" stop-color="#F0704A"/>
    </linearGradient>`,
    glyph: (uid) => `
    ${neon(ringPath, NEON, HOT_MINT, 40, uid)}
    ${neon(spikePath, `url(#pg-${uid})`, '#FFEDD9', 40, uid)}`,
  },
  {
    slug: 'n5-soft',
    name: 'N5 · 柔波霓虹',
    tag: '曲线波形 · 无尖角',
    note: '把柔化波峰（P5）的曲线波形搬进霓虹：发光的呼吸波，没有一个尖角。暗底 + 软波形，是「冷静的霓虹」，和 N1 的「锐利霓虹」正好两端。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${neon(ringPath, NEON, HOT_MINT, 40, uid)}
    ${neon(softPath, CORAL, HOT_CORAL, 40, uid)}`,
  },
];

function renderSvg(c) {
  const uid = c.slug;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  <defs>
    <clipPath id="sq-${uid}"><rect width="${SIZE}" height="${SIZE}" rx="232"/></clipPath>
    <filter id="soft-${uid}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="26"/></filter>
    <filter id="tight-${uid}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="7"/></filter>
    ${c.extraDefs ? c.extraDefs(uid) : ''}
  </defs>
  ${c.bg(uid)}
  <g clip-path="url(#sq-${uid})">
    ${c.glyph(uid)}
  </g>
</svg>
`;
}

for (const c of VARIANTS) {
  writeFileSync(join(SVG_DIR, `${c.slug}-icon.svg`), renderSvg(c));
}

const iconSvg = (c) => renderSvg(c);
const rows = VARIANTS.map(
  (c) => `
  <section class="row">
    <div class="hero">${iconSvg(c)}</div>
    <div class="body">
      <h2>${c.name}</h2>
      <div class="tag">${c.tag}</div>
      <div class="ladder">
        <div class="ladder-cell"><div class="s s128">${iconSvg(c)}</div><span>128</span></div>
        <div class="ladder-cell"><div class="s s64">${iconSvg(c)}</div><span>64</span></div>
        <div class="ladder-cell"><div class="s s48">${iconSvg(c)}</div><span>48</span></div>
        <div class="ladder-cell"><div class="s s32">${iconSvg(c)}</div><span>32</span></div>
        <div class="ladder-cell"><div class="s s24">${iconSvg(c)}</div><span>24</span></div>
      </div>
      <p class="note">${c.note}</p>
    </div>
  </section>`,
).join('\n');

writeFileSync(
  join(HERE, 'neon-refine.html'),
  `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · 深色霓虹线条优化</title>
<style>
  :root { --ink:#17251E; --ink2:#5A6B62; --ink3:#93A29A; --line:#E7ECE8; }
  * { box-sizing:border-box; }
  body { margin:0; padding:44px 52px 60px; background:#FAFBF9; color:var(--ink);
         font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif; }
  h1 { font-size:28px; margin:0 0 6px; letter-spacing:-.4px; }
  .sub { color:var(--ink2); font-size:14px; margin-bottom:10px; }
  .row { display:grid; grid-template-columns:320px 1fr; gap:0 44px; align-items:center;
         padding:30px 0; border-top:1px solid var(--line); }
  .row:first-of-type { border-top:none; margin-top:18px; }
  .hero { width:300px; }
  .hero svg { width:100%; height:auto; border-radius:24%; box-shadow:0 10px 26px rgba(23,37,30,.13); display:block; }
  h2 { font-size:22px; margin:0 0 6px; letter-spacing:-.2px; }
  .tag { font-size:13px; color:#1FA377; margin-bottom:20px; }
  .ladder { display:flex; align-items:flex-end; gap:24px; }
  .ladder-cell { display:flex; flex-direction:column; align-items:center; gap:7px; }
  .ladder-cell span { font-size:11px; color:var(--ink3); }
  .s svg { display:block; border-radius:22%; }
  .s128 svg { width:128px; height:128px; box-shadow:0 5px 14px rgba(23,37,30,.10); }
  .s64 svg  { width:64px;  height:64px;  box-shadow:0 3px 9px rgba(23,37,30,.09); }
  .s48 svg  { width:48px;  height:48px;  box-shadow:0 2px 7px rgba(23,37,30,.08); }
  .s32 svg  { width:32px;  height:32px; }
  .s24 svg  { width:24px;  height:24px; }
  .note { margin:22px 0 0; font-size:14px; line-height:1.7; color:var(--ink2); max-width:880px; }
</style></head>
<body>
  <h1>深色霓虹 · 线条优化</h1>
  <div class="sub">骨架不变：近黑底 · 薄荷环正上方破开接珊瑚色脉搏 · 整体发光　｜　这一轮只动画线的画法</div>
  ${rows}
</body></html>`,
);

console.log(`✓ ${VARIANTS.length} 个深色霓虹线条方案 SVG + neon-refine.html 已写入`);
