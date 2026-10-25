#!/usr/bin/env node
/**
 * LocalFit AI · 空心管粗管版（H2）的材质打磨。
 *
 * 骨架与管径不动（近黑底 · 管径 60 · 壁 17 · 气口 8 · 薄荷环 + 悬浮珊瑚脉搏），
 * 这一轮逐层加材质：
 *   K1 k1-ambient   环境辉光：霓虹把墙照亮——环半径处一圈薄荷洗光 + 四角暗角
 *   K2 k2-specular  玻璃高光：管壁外侧一条白色 specular，环和脉搏尖峰各一道
 *   K3 k3-falloff   光衰减：管色沿受光面渐变（左上亮、右下深），不再是平涂
 *   K4 k4-residual  管内残光：挖芯不挖成纯底色，掺一点管色，像气体未全灭
 *   K5 k5-electrode 电极节点：脉搏两端各一颗白热电极，像真正接在电路上的灯管
 *   K6 k6-full      以上全部叠加（定稿候选）
 *
 * 只输出 icon 变体。运行：node design/logo/tube-polish.mjs
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SIZE, arc } from './kit.mjs';

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
const W = 60; // 管外径
const PUNCH = 26; // 挖芯宽 → 壁 (60-26)/2 = 17

const NEON = '#4ED9A6';
const NEON_LIT = '#6BEFBA'; // 受光面
const NEON_DIM = '#1FA377'; // 背光面
const CORAL = '#FF8A65';
const CORAL_LIT = '#FF9A75';
const CORAL_DIM = '#F0704A';
const HOLE_MINT = '#19342a'; // 环管内残光（16% 薄荷，已像素采样校准）
const HOLE_CORAL = '#35271f'; // 脉搏管内残光（16% 珊瑚）
const HOT = '#FFE9DC';

const RING = arc(CX, CY, R, BREAK, 360 - BREAK);
const PULSE = `M400 ${CHORD_Y} L458 ${CHORD_Y} L508 206 L536 378 L578 ${CHORD_Y} L624 ${CHORD_Y}`;

/** 空心管：大晕 → 实色管 → 挖芯。stroke 传 url(#…) 即渐变管。 */
function tube(d, stroke, uid, punchColor = BG) {
  return `
    <g filter="url(#soft-${uid})" opacity="0.5"><path d="${d}" fill="none" stroke="${stroke}" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/></g>
    <path d="${d}" fill="none" stroke="${stroke}" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${d}" fill="none" stroke="${punchColor}" stroke-width="${PUNCH}" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** 玻璃高光：管壁外侧一条白 specular（环在左上外缘，脉搏在尖峰外缘）。 */
const SPEC = `
    <path d="${arc(CX, CY, 304, 255, 318)}" fill="none" stroke="#FFFFFF" stroke-width="8" stroke-linecap="round" opacity="0.32"/>
    <path d="${arc(508, 206, 22, 300, 340)}" fill="none" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round" opacity="0.35"/>`;

/** 电极节点：脉搏两端各一颗白热电极，盖在管端圆头上。 */
const ELECTRODES = (uid) => `
    <g filter="url(#tight-${uid})">
      <circle cx="400" cy="${CHORD_Y}" r="13" fill="${HOT}"/>
      <circle cx="624" cy="${CHORD_Y}" r="13" fill="${HOT}"/>
    </g>`;

/** 环境辉光 + 暗角：霓虹把墙照亮，四角压暗出纵深。 */
const ambientRect = (uid) => `
    <rect width="${SIZE}" height="${SIZE}" rx="232" fill="url(#amb-${uid})"/>
    <rect width="${SIZE}" height="${SIZE}" rx="232" fill="url(#vig-${uid})"/>`;

const AMBIENT_DEFS = (uid) => `
    <radialGradient id="amb-${uid}" gradientUnits="userSpaceOnUse" cx="${CX}" cy="${CY}" r="440">
      <stop offset="0" stop-color="${NEON}" stop-opacity="0.05"/>
      <stop offset="0.62" stop-color="${NEON}" stop-opacity="0.13"/>
      <stop offset="1" stop-color="${NEON}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="vig-${uid}" cx="0.5" cy="0.46" r="0.75">
      <stop offset="0.6" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.32"/>
    </radialGradient>`;

const FALLOFF_DEFS = (uid) => `
    <linearGradient id="rg-${uid}" gradientUnits="userSpaceOnUse" x1="240" y1="220" x2="790" y2="810">
      <stop offset="0" stop-color="${NEON_LIT}"/>
      <stop offset="0.45" stop-color="${NEON}"/>
      <stop offset="1" stop-color="${NEON_DIM}"/>
    </linearGradient>
    <linearGradient id="pg-${uid}" gradientUnits="userSpaceOnUse" x1="${X1}" y1="${CHORD_Y}" x2="${X2}" y2="${CHORD_Y}">
      <stop offset="0" stop-color="${CORAL_LIT}"/>
      <stop offset="1" stop-color="${CORAL_DIM}"/>
    </linearGradient>`;

const darkBg = `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`;

const VARIANTS = [
  {
    slug: 'h2-chunky',
    name: 'H2 · 粗管（对照）',
    tag: '管径 60 · 壁 17 · 气口 8',
    note: '你选中的版本，放最前作对照。管色平涂、挖芯是纯底色、无高光无环境光。',
    skipWrite: true,
    bg: () => darkBg,
    glyph: (uid) => `${tube(RING, NEON, uid)}${tube(PULSE, CORAL, uid)}`,
  },
  {
    slug: 'k1-ambient',
    name: 'K1 · 环境辉光',
    tag: '霓虹照亮墙 + 暗角',
    note: '真的霓虹灯会照亮身后的墙：在环半径处铺一圈 13% 的薄荷洗光，四角再压一层暗角出纵深。管子一根线没动，空间感立刻出来——性价比最高的一步。',
    bg: (uid) => `${darkBg}${ambientRect(uid)}`,
    extraDefs: (uid) => AMBIENT_DEFS(uid),
    glyph: (uid) => `${tube(RING, NEON, uid)}${tube(PULSE, CORAL, uid)}`,
  },
  {
    slug: 'k2-specular',
    name: 'K2 · 玻璃高光',
    tag: '管壁白 specular',
    note: '管壁外侧加一道白色高光：环的左上外缘一长条，脉搏尖峰外缘一小段。玻璃管的体积感全靠它——从「平涂圆环」变成「有受光面的管子」。',
    bg: () => darkBg,
    glyph: (uid) => `${tube(RING, NEON, uid)}${tube(PULSE, CORAL, uid)}${SPEC}`,
  },
  {
    slug: 'k3-falloff',
    name: 'K3 · 光衰减',
    tag: '左上亮 · 右下深',
    note: '管色不再是平涂：薄荷从受光的左上亮档衰减到背光的右下深档，珊瑚脉搏同理。光有了方向，管子有了圆面——和高光的区别是它动的是「色」不是「形」。',
    bg: () => darkBg,
    extraDefs: (uid) => FALLOFF_DEFS(uid),
    glyph: (uid) => `${tube(RING, `url(#rg-${uid})`, uid)}${tube(PULSE, `url(#pg-${uid})`, uid)}`,
  },
  {
    slug: 'k4-residual',
    name: 'K4 · 管内残光',
    tag: '挖芯掺色 · 气体未全灭',
    note: '挖芯不挖成纯底色：环管内掺 16% 薄荷（#19342a）、脉搏管内掺 16% 珊瑚（#35271f）。粗管的孔有 26 宽，残光比细管明显得多——两根管子像刚断电。',
    bg: () => darkBg,
    glyph: (uid) => `${tube(RING, NEON, uid, HOLE_MINT)}${tube(PULSE, CORAL, uid, HOLE_CORAL)}`,
  },
  {
    slug: 'k5-electrode',
    name: 'K5 · 电极节点',
    tag: '脉搏两端白热电极',
    note: '真灯管两端有电极：脉搏两端各点一颗白热圆电极（带紧晕）。它同时回答了「脉搏为什么悬浮」——因为那是两根管子的接头。',
    bg: () => darkBg,
    glyph: (uid) => `${tube(RING, NEON, uid)}${tube(PULSE, CORAL, uid)}${ELECTRODES(uid)}`,
  },
  {
    slug: 'k6-full',
    name: 'K6 · 全部叠加',
    tag: '定稿候选',
    note: 'K1–K5 全部叠加：环境辉光 + 暗角 + 光衰减 + 管内残光 + 玻璃高光 + 电极节点。暗底上每一层都在讲「这是一根真的、通电的玻璃管」。',
    bg: (uid) => `${darkBg}${ambientRect(uid)}`,
    extraDefs: (uid) => `${AMBIENT_DEFS(uid)}${FALLOFF_DEFS(uid)}`,
    glyph: (uid) => `
    ${tube(RING, `url(#rg-${uid})`, uid, HOLE_MINT)}
    ${tube(PULSE, `url(#pg-${uid})`, uid, HOLE_CORAL)}
    ${SPEC}
    ${ELECTRODES(uid)}`,
  },
  {
    slug: 'k7-alive',
    name: 'K7 · 会呼吸（动画）',
    tag: 'K6 + 心跳节律 · 彩蛋',
    note: '和 K6 完全同一套几何，只是把脉搏的大晕层加了 SMIL 心跳动画（1.6s 一组：轻-重-歇，电极同步闪）。霓虹本来就会闪——启动图标用不了动画，但启动页/官网/关于页可以。浏览器打开 SVG 或内嵌 HTML 才会动。',
    bg: (uid) => `${darkBg}${ambientRect(uid)}`,
    extraDefs: (uid) => `${AMBIENT_DEFS(uid)}${FALLOFF_DEFS(uid)}`,
    glyph: (uid) => `
    <g filter="url(#soft-${uid})" opacity="0.5">
      <path d="${PULSE}" fill="none" stroke="url(#pg-${uid})" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
      <animate attributeName="opacity" values="0.5;0.5;1;0.5;0.8;0.5" keyTimes="0;0.5;0.58;0.66;0.76;1" dur="1.6s" repeatCount="indefinite"/>
    </g>
    ${tube(RING, `url(#rg-${uid})`, uid, HOLE_MINT)}
    ${tube(PULSE, `url(#pg-${uid})`, uid, HOLE_CORAL)}
    ${SPEC}
    <g filter="url(#tight-${uid})">
      <circle cx="400" cy="${CHORD_Y}" r="13" fill="${HOT}"/>
      <circle cx="624" cy="${CHORD_Y}" r="13" fill="${HOT}"/>
      <animate attributeName="opacity" values="1;1;0.55;1;0.75;1" keyTimes="0;0.5;0.58;0.66;0.76;1" dur="1.6s" repeatCount="indefinite"/>
    </g>`,
  },
  {
    slug: 'k8-final',
    name: 'K8 · 定稿（K7 − K1）',
    tag: '动画版 · 无环境辉光',
    note: '最终选定：K7 去掉环境辉光和暗角，回到纯黑底。保留光衰减、管内残光、玻璃高光、电极节点和心跳动画。mark / iOS 两件套见 finalize.mjs。',
    skipWrite: false,
    bg: () => darkBg,
    extraDefs: (uid) => FALLOFF_DEFS(uid),
    glyph: (uid) => `
    <g filter="url(#soft-${uid})" opacity="0.5">
      <path d="${PULSE}" fill="none" stroke="url(#pg-${uid})" stroke-width="${W}" stroke-linecap="round" stroke-linejoin="round"/>
      <animate attributeName="opacity" values="0.5;0.5;1;0.5;0.8;0.5" keyTimes="0;0.5;0.58;0.66;0.76;1" dur="1.6s" repeatCount="indefinite"/>
    </g>
    ${tube(RING, `url(#rg-${uid})`, uid, HOLE_MINT)}
    ${tube(PULSE, `url(#pg-${uid})`, uid, HOLE_CORAL)}
    ${SPEC}
    <g filter="url(#tight-${uid})">
      <circle cx="400" cy="${CHORD_Y}" r="13" fill="${HOT}"/>
      <circle cx="624" cy="${CHORD_Y}" r="13" fill="${HOT}"/>
      <animate attributeName="opacity" values="1;1;0.55;1;0.75;1" keyTimes="0;0.5;0.58;0.66;0.76;1" dur="1.6s" repeatCount="indefinite"/>
    </g>`,
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
  if (!c.skipWrite) {
    writeFileSync(join(SVG_DIR, `${c.slug}-icon.svg`), renderSvg(c));
  }
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
  join(HERE, 'tube-polish.html'),
  `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · 空心管材质打磨</title>
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
  <h1>空心管 · 材质打磨</h1>
  <div class="sub">管径/壁/气口不动（H2）　｜　逐层加：环境辉光 → 玻璃高光 → 光衰减 → 管内残光 → 电极节点 → 全部叠加</div>
  ${rows}
</body></html>`,
);

console.log(`✓ 空心管材质打磨 ${VARIANTS.filter((c) => !c.skipWrite).length} 个新方案 SVG + tube-polish.html 已写入`);
