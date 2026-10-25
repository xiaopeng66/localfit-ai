#!/usr/bin/env node
/**
 * LocalFit AI · 空心管（深色霓虹线条方案 N3）的管径细化。
 *
 * 骨架不变：近黑底、空心玻璃管、薄荷环正上方破开接悬浮的珊瑚脉搏。
 * 这一轮只动管子的四个物理量：
 *   管径（外径 34/46/60）· 管壁（7/12/17）· 气口（8/12/20/24）· 管端切口（圆头/平头）
 * 外加一个「管内微光」的材质变体。
 *
 * 只输出 icon 变体。运行：node design/logo/hollow-refine.mjs
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
const NEON = '#4ED9A6';
const CORAL = '#FF8A65';
/** 管内微光用的掺色底：bg 里掺 16% 薄荷亮色（#152821 只有 8%，实测几乎不可感）。 */
const INNER = '#19342a';

const ringPath = arc(CX, CY, R, BREAK, 360 - BREAK);

/**
 * 悬浮脉搏：与环两端各留 gap 间距（含两端圆头），尖峰居中。
 * xStart = X1 + 管径 + gap，xEnd = X2 - 管径 - gap。
 */
const pulsePath = (xStart, xEnd) =>
  `M${xStart} ${CHORD_Y} L458 ${CHORD_Y} L508 206 L536 378 L578 ${CHORD_Y} L${xEnd} ${CHORD_Y}`;

/**
 * 空心玻璃管：实色管 → 底色（或掺色）挖芯。
 * cap='round' 是圆头封口；'butt' 是平头切口（管端呈开口圆环截面）。
 */
function hollow(d, color, w, uid, { punch = 0.478, punchColor = BG, cap = 'round' } = {}) {
  return `
    <g filter="url(#soft-${uid})" opacity="0.5"><path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="${cap}" stroke-linejoin="round"/></g>
    <path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="${cap}" stroke-linejoin="round"/>
    <path d="${d}" fill="none" stroke="${punchColor}" stroke-width="${(w * punch).toFixed(1)}" stroke-linecap="${cap}" stroke-linejoin="round"/>`;
}

const VARIANTS = [
  {
    slug: 'n3-hollow',
    name: 'N3 · 空心管（对照）',
    tag: '管径 46 · 壁 12 · 气口 12',
    note: '你选中的版本，放在最前作对照。管径 46、管壁 12、气口 12。',
    skipWrite: true,
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 46, uid)}
    ${hollow(pulsePath(390, 634), CORAL, 46, uid)}`,
  },
  {
    slug: 'h1-slim',
    name: 'H1 · 细管大缝',
    tag: '管径 34 · 壁 7 · 气口 20',
    note: '管径减到 34、壁削到 7、气口拉大到 20。整根管子变细一圈，缝的存在感更强，图标整体变轻、变透气；代价是 24px 下管壁只剩不足 1px。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 34, uid, { punch: 20 / 34 })}
    ${hollow(pulsePath(386, 638), CORAL, 34, uid, { punch: 20 / 34 })}`,
  },
  {
    slug: 'h2-chunky',
    name: 'H2 · 粗管紧缝',
    tag: '管径 60 · 壁 17 · 气口 8',
    note: '反方向：管径加粗到 60、壁加厚到 17、气口收紧到 8。灯管的实体感最强，近看像真的玻璃管，24px 下线条依然粗壮清晰——最「耐小尺寸」的一版。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 60, uid, { punch: 26 / 60 })}
    ${hollow(pulsePath(400, 624), CORAL, 60, uid, { punch: 26 / 60 })}`,
  },
  {
    slug: 'h3-thinwall',
    name: 'H3 · 薄壁宽缝',
    tag: '管径 46 · 壁 7 · 气口 24',
    note: '管径不动、壁削到 7、气口拉到 24。管子薄得像 LED 灯带而不是玻璃管，断开感最明确；和 H1 的区别是外径保持饱满，只把壁掏薄。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 46, uid, { punch: 32 / 46 })}
    ${hollow(pulsePath(402, 622), CORAL, 46, uid, { punch: 32 / 46 })}`,
  },
  {
    slug: 'h4-flatcut',
    name: 'H4 · 平头切口',
    tag: '圆头改平头 · 开口管端',
    note: '管端从圆头封口改成平头切口——管端是开口的圆环截面，像用切管器切出来的。工业感最重，也和其它方案圆头的「软」彻底区分开。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 46, uid, { cap: 'butt' })}
    ${hollow(pulsePath(390, 634), CORAL, 46, uid, { cap: 'butt' })}`,
  },
  {
    slug: 'h5-innerlight',
    name: 'H5 · 管内微光',
    tag: '挖芯掺色 · 气体未全灭',
    note: '几何与对照版完全一致，只把挖芯的底色换成掺了 10% 薄荷的 #152821——管内像有没熄灭的气体。全组最微妙的一版，近看有惊喜、远看几乎不变。',
    bg: () => `<rect width="${SIZE}" height="${SIZE}" rx="232" fill="${BG}"/>`,
    glyph: (uid) => `
    ${hollow(ringPath, NEON, 46, uid, { punchColor: INNER })}
    ${hollow(pulsePath(390, 634), CORAL, 46, uid, { punchColor: INNER })}`,
  },
];

function renderSvg(c) {
  const uid = c.slug;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}" width="${SIZE}" height="${SIZE}">
  <defs>
    <clipPath id="sq-${uid}"><rect width="${SIZE}" height="${SIZE}" rx="232"/></clipPath>
    <filter id="soft-${uid}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="26"/></filter>
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
  join(HERE, 'hollow-refine.html'),
  `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>LocalFit AI · 空心管管径细化</title>
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
  <h1>空心管 · 管径细化</h1>
  <div class="sub">骨架不变：近黑底 · 空心玻璃管 · 薄荷环 + 悬浮珊瑚脉搏　｜　变量：管径 / 管壁 / 气口 / 管端切口 / 管内材质</div>
  ${rows}
</body></html>`,
);

console.log(`✓ 空心管细化 ${VARIANTS.filter((c) => !c.skipWrite).length} 个新方案 SVG + hollow-refine.html 已写入`);
