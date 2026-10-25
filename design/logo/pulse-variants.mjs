#!/usr/bin/env node
/**
 * LocalFit AI · 脉搏环（发散方案 d8）细化变体。
 *
 * 骨架不变：环在正上方破开，接一段脉搏线——「记录」与「训练」在同一条线上。
 * 变的是两件事：
 *   1. 波形怎么画：利落单峰 / 真实心电双峰（P 波 + QRS）/ 柔化圆峰
 *   2. 什么颜色：薄荷+珊瑚 / 单色一笔 / 深色霓虹 / 墨绿纸面
 *
 * 只输出 icon 变体（同 explorations 一轮的逻辑），选定后再补 mark / ios。
 * 运行：node design/logo/pulse-variants.mjs
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
const R = 280; // 环半径；外缘 280+22=302，落在 512-174=338 的安全边界内
const BREAK = 40; // 破口半角（度）：环从 BREAK 画到 360-BREAK，缺口朝正上方
const CHORD_Y = +(CY - R * Math.cos((BREAK * Math.PI) / 180)).toFixed(1);
const X1 = +(CX - R * Math.sin((BREAK * Math.PI) / 180)).toFixed(1);
const X2 = +(CX + R * Math.sin((BREAK * Math.PI) / 180)).toFixed(1);

const MINT = '#2FBE8F';
const CORAL = '#FF8A65';
const INK = '#17251E';
const NEON = '#4ED9A6';

/** 利落单峰：一根直线拉平，中间一个尖峰加一个回落。 */
const spikeSingle = (w) =>
  `M${X1} ${CHORD_Y} L452 ${CHORD_Y} L500 200 L552 386 L600 ${CHORD_Y} L${X2} ${CHORD_Y}`;

/** 真实心电：P 波（小隆起）+ QRS 波群（深谷-高尖-回谷）。 */
const spikeECG = () =>
  `M${X1} ${CHORD_Y} L416 ${CHORD_Y} L442 272 L468 ${CHORD_Y} L484 320 L512 198 L542 334 L562 ${CHORD_Y} L${X2} ${CHORD_Y}`;

/** 柔化波峰：峰和谷都用三次曲线收口，没有尖角。 */
const spikeSoft = () =>
  `M${X1} ${CHORD_Y} L448 ${CHORD_Y} ` +
  `C466 ${CHORD_Y} 474 205 500 205 C526 205 534 ${CHORD_Y} 552 ${CHORD_Y} ` +
  `C566 ${CHORD_Y} 562 360 590 360 C618 360 614 ${CHORD_Y} 628 ${CHORD_Y} ` +
  `L${X2} ${CHORD_Y}`;

const VARIANTS = [
  {
    slug: 'p1-pulse-refined',
    name: 'P1 · 精修单峰',
    tag: '原案的直接收紧',
    note: 'd8 的比例修正：环加粗到 44，尖峰收窄抬高（200，探出环顶），回落压深。峰谷错位更大，「跳一下」的感觉更强。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#FFFFFF"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, R, BREAK, 360 - BREAK)}" fill="none" stroke="${MINT}" stroke-width="44" stroke-linecap="round"/>
    <path d="${spikeSingle()}" fill="none" stroke="${CORAL}" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  {
    slug: 'p2-ecg',
    name: 'P2 · 真实心电',
    tag: 'P 波 + QRS 波群',
    note: '波形换成真正的心电图形状：小隆起的 P 波、深谷、高尖的 R 波、回谷。懂的人一眼认出是心电，代价是小尺寸下细节会并在一起。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#FFFFFF"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, R, BREAK, 360 - BREAK)}" fill="none" stroke="${MINT}" stroke-width="40" stroke-linecap="round"/>
    <path d="${spikeECG()}" fill="none" stroke="${CORAL}" stroke-width="38" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  {
    slug: 'p3-mono',
    name: 'P3 · 一笔单色',
    tag: '同色合并成一条线',
    note: '环和脉搏用同一个墨绿，接缝消失，整条线一笔画完——最安静的一版。奶油底配深绿，和「白底薄荷+珊瑚」的双色版气质完全不同。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${C.cream}"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, R, BREAK, 360 - BREAK)}" fill="none" stroke="${C.mint700}" stroke-width="42" stroke-linecap="round"/>
    <path d="${spikeSingle()}" fill="none" stroke="${C.mint700}" stroke-width="42" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  {
    slug: 'p4-dark',
    name: 'P4 · 深色霓虹',
    tag: '暗底 + 发光',
    note: '把深色霓虹那版（d1）的底和光搬过来：近黑底、薄荷环与珊瑚脉搏都带外晕。全组对比最强，适合走深色沉浸的品牌方向。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#0F1412"/>`,
    extraDefs: (uid) => `<filter id="glow-${uid}" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="16" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>`,
    glyph: (uid) => `<g filter="url(#glow-${uid})">
    <path d="${arc(CX, CY, R, BREAK, 360 - BREAK)}" fill="none" stroke="${NEON}" stroke-width="38" stroke-linecap="round"/>
    <path d="${spikeSingle()}" fill="none" stroke="${CORAL}" stroke-width="38" stroke-linecap="round" stroke-linejoin="round"/>
  </g>`,
  },
  {
    slug: 'p5-soft',
    name: 'P5 · 柔化波峰',
    tag: '曲线收口 · 无尖角',
    note: '峰和谷全部用三次曲线收口，没有一个是尖角——「脉搏」变「呼吸」，和 App 圆角形状语言最贴。其余配色不变。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="#FFFFFF"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, R, BREAK, 360 - BREAK)}" fill="none" stroke="${MINT}" stroke-width="42" stroke-linecap="round"/>
    <path d="${spikeSoft()}" fill="none" stroke="${CORAL}" stroke-width="42" stroke-linecap="round" stroke-linejoin="round"/>`,
  },
  {
    slug: 'p6-ink',
    name: 'P6 · 墨绿纸面',
    tag: '墨色环 + 珊瑚脉搏',
    note: '环压成墨绿黑（textPrimary），只让脉搏保持珊瑚色——纸面印刷感，最「编辑设计」的一版，也最不像健康类 App 的惯用配色。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${C.cream}"/>`,
    glyph: () => `
    <path d="${arc(CX, CY, R, BREAK, 360 - BREAK)}" fill="none" stroke="${INK}" stroke-width="42" stroke-linecap="round"/>
    <path d="${spikeSingle()}" fill="none" stroke="${CORAL}" stroke-width="42" stroke-linecap="round" stroke-linejoin="round"/>`,
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
  join(HERE, 'pulse-variants.html'),
  `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · 脉搏环细化</title>
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
  <h1>脉搏环 · 细化方案</h1>
  <div class="sub">骨架不变：环在正上方破开接一段脉搏线　｜　变的是波形画法（单峰 / 心电 / 柔化）与色彩（双色 / 单色 / 霓虹 / 墨色）</div>
  ${rows}
</body></html>`,
);

console.log(`✓ ${VARIANTS.length} 个脉搏环细化方案 SVG + pulse-variants.html 已写入`);
